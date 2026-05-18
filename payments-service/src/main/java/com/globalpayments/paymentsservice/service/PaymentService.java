package com.globalpayments.paymentsservice.service;

import com.globalpayments.paymentsservice.exception.DuplicatePaymentException;
import com.globalpayments.paymentsservice.exception.PaymentNotFoundException;
import com.globalpayments.paymentsservice.exception.PaymentStateException;
import com.globalpayments.paymentsservice.model.dto.PaymentDtos.*;
import com.globalpayments.paymentsservice.model.entity.Payment;
import com.globalpayments.paymentsservice.model.enums.PaymentStatus;
import com.globalpayments.paymentsservice.repository.PaymentRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Service
@Slf4j
public class PaymentService {

    private static final String PAYMENT_EVENTS_TOPIC = "payment-events";

    private final PaymentRepository paymentRepository;
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final PaymentReferenceGenerator referenceGenerator;

    // ── Micrometer Metrics ─────────────────────────────────────────────────
    private final Counter paymentsCreatedCounter;
    private final Counter paymentsCompletedCounter;
    private final Counter paymentsFailedCounter;
    private final Timer   paymentProcessingTimer;

    public PaymentService(
            PaymentRepository paymentRepository,
            KafkaTemplate<String, Object> kafkaTemplate,
            PaymentReferenceGenerator referenceGenerator,
            MeterRegistry meterRegistry) {

        this.paymentRepository   = paymentRepository;
        this.kafkaTemplate       = kafkaTemplate;
        this.referenceGenerator  = referenceGenerator;

        // Register custom metrics — surfaced in Prometheus/Grafana
        this.paymentsCreatedCounter   = Counter.builder("payments.created.total")
                .description("Total payments created").register(meterRegistry);
        this.paymentsCompletedCounter = Counter.builder("payments.completed.total")
                .description("Total payments completed").register(meterRegistry);
        this.paymentsFailedCounter    = Counter.builder("payments.failed.total")
                .description("Total payments failed").register(meterRegistry);
        this.paymentProcessingTimer   = Timer.builder("payments.processing.duration")
                .description("Time to process a payment end-to-end")
                .register(meterRegistry);
    }

    // ── Create Payment ─────────────────────────────────────────────────────

    @Transactional
    public PaymentResponse createPayment(CreatePaymentRequest request) {
        log.info("Creating payment: sender={}, amount={} {}",
                 request.getSenderAccountId(),
                 request.getAmount(),
                 request.getCurrency());

        // Idempotency check — return existing result if duplicate request
        if (request.getIdempotencyKey() != null) {
            return paymentRepository.findByIdempotencyKey(request.getIdempotencyKey())
                .map(this::toResponse)
                .orElseGet(() -> persistAndPublish(request));
        }

        return persistAndPublish(request);
    }

    private PaymentResponse persistAndPublish(CreatePaymentRequest request) {
        // Convert amount to minor units
        long minorUnits = toMinorUnits(request.getAmount(),
                                       request.getCurrency().getDecimalPlaces());

        Payment payment = Payment.builder()
                .paymentReference(referenceGenerator.generate())
                .senderAccountId(request.getSenderAccountId())
                .receiverAccountId(request.getReceiverAccountId())
                .receiverBankCode(request.getReceiverBankCode())
                .amountMinorUnits(minorUnits)
                .currency(request.getCurrency())
                .status(PaymentStatus.PENDING)
                .paymentType(request.getPaymentType())
                .description(request.getDescription())
                .idempotencyKey(request.getIdempotencyKey())
                .build();

        Payment saved = paymentRepository.save(payment);
        paymentsCreatedCounter.increment();

        // Publish event to Kafka for async processing by clearing sub-system
        publishPaymentEvent("PAYMENT_CREATED", saved);
        log.info("Payment created: ref={}, id={}", saved.getPaymentReference(), saved.getId());

        return toResponse(saved);
    }

    // ── Get Payment ────────────────────────────────────────────────────────

    @Transactional(readOnly = true)
    public PaymentResponse getPaymentById(UUID id) {
        return paymentRepository.findById(id)
                .map(this::toResponse)
                .orElseThrow(() -> new PaymentNotFoundException("Payment not found: " + id));
    }

    @Transactional(readOnly = true)
    public PaymentResponse getPaymentByReference(String reference) {
        return paymentRepository.findByPaymentReference(reference)
                .map(this::toResponse)
                .orElseThrow(() -> new PaymentNotFoundException(
                        "Payment not found with reference: " + reference));
    }

    @Transactional(readOnly = true)
    public PaymentPageResponse getPaymentsBySender(String accountId, Pageable pageable) {
        Page<Payment> page = paymentRepository.findBySenderAccountId(accountId, pageable);
        return toPageResponse(page);
    }

    // ── Update Status (called by clearing/settlement sub-system via Kafka) ─

    @Transactional
    public PaymentResponse updateStatus(UUID id, UpdateStatusRequest request) {
        Payment payment = paymentRepository.findById(id)
                .orElseThrow(() -> new PaymentNotFoundException("Payment not found: " + id));

        // Guard against invalid state transitions
        validateStatusTransition(payment.getStatus(), request.getNewStatus());

        PaymentStatus previousStatus = payment.getStatus();
        payment.setStatus(request.getNewStatus());

        if (request.getClearingReference() != null) {
            payment.setClearingReference(request.getClearingReference());
        }
        if (request.getFailureReason() != null) {
            payment.setFailureReason(request.getFailureReason());
        }

        Payment updated = paymentRepository.save(payment);

        // Metrics
        if (request.getNewStatus() == PaymentStatus.COMPLETED) {
            paymentsCompletedCounter.increment();
        } else if (request.getNewStatus() == PaymentStatus.FAILED) {
            paymentsFailedCounter.increment();
        }

        publishPaymentEvent("PAYMENT_STATUS_CHANGED", updated);
        log.info("Payment {} status changed: {} → {}", id, previousStatus, request.getNewStatus());

        return toResponse(updated);
    }

    // ── Retry Scheduler ────────────────────────────────────────────────────

    /**
     * Scheduled job: every 5 minutes, pick up failed payments eligible for retry.
     * Uses a 5-minute backoff before re-queuing.
     */
    @Scheduled(fixedDelayString = "300000")
    @Transactional
    public void retryFailedPayments() {
        Instant cutoff = Instant.now().minus(5, ChronoUnit.MINUTES);
        List<Payment> retryable = paymentRepository.findRetryablePayments(cutoff);

        if (!retryable.isEmpty()) {
            log.info("Retrying {} failed payments", retryable.size());
        }

        retryable.forEach(payment -> {
            payment.setStatus(PaymentStatus.PENDING);
            payment.setRetryCount(payment.getRetryCount() + 1);
            paymentRepository.save(payment);
            publishPaymentEvent("PAYMENT_RETRY", payment);
            log.info("Re-queued payment {} for retry (attempt {})",
                     payment.getPaymentReference(), payment.getRetryCount());
        });
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private void validateStatusTransition(PaymentStatus from, PaymentStatus to) {
        if (from.equals(to)) {
            return; // No-op is allowed
        }
        // Prevent moving from a terminal state
        if (from == PaymentStatus.COMPLETED || from == PaymentStatus.CANCELLED) {
            throw new PaymentStateException(
                String.format("Cannot transition from %s to %s", from, to));
        }
        // Prevent arbitrary backwards transitions
        if (to == PaymentStatus.PENDING && from != PaymentStatus.FAILED) {
            throw new PaymentStateException(
                String.format("Invalid transition: %s → %s", from, to));
        }
    }

    private long toMinorUnits(BigDecimal amount, int decimalPlaces) {
        return amount.movePointRight(decimalPlaces).longValueExact();
    }

    private void publishPaymentEvent(String eventType, Payment payment) {
        try {
            var event = java.util.Map.of(
                "eventType",        eventType,
                "paymentId",        payment.getId().toString(),
                "paymentReference", payment.getPaymentReference(),
                "status",           payment.getStatus().name(),
                "amount",           payment.getAmountMinorUnits(),
                "currency",         payment.getCurrency().name(),
                "timestamp",        Instant.now().toString()
            );
            kafkaTemplate.send(PAYMENT_EVENTS_TOPIC,
                               payment.getPaymentReference(), event);
        } catch (Exception e) {
            // Kafka publish failure is non-critical — log and continue.
            // A separate Kafka monitoring alert will fire if the broker is down.
            log.error("Failed to publish Kafka event for payment {}: {}",
                      payment.getPaymentReference(), e.getMessage());
        }
    }

    private PaymentResponse toResponse(Payment p) {
        return PaymentResponse.builder()
                .id(p.getId())
                .paymentReference(p.getPaymentReference())
                .senderAccountId(p.getSenderAccountId())
                .receiverAccountId(p.getReceiverAccountId())
                .receiverBankCode(p.getReceiverBankCode())
                .amount(p.getAmountAsDecimal())
                .currency(p.getCurrency())
                .status(p.getStatus())
                .paymentType(p.getPaymentType())
                .description(p.getDescription())
                .clearingReference(p.getClearingReference())
                .retryCount(p.getRetryCount())
                .failureReason(p.getFailureReason())
                .createdAt(p.getCreatedAt())
                .updatedAt(p.getUpdatedAt())
                .createdBy(p.getCreatedBy())
                .build();
    }

    private PaymentPageResponse toPageResponse(Page<Payment> page) {
        return PaymentPageResponse.builder()
                .payments(page.getContent().stream().map(this::toResponse).toList())
                .page(page.getNumber())
                .size(page.getSize())
                .totalElements(page.getTotalElements())
                .totalPages(page.getTotalPages())
                .build();
    }
}
