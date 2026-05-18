package com.globalpayments.paymentsservice;

import com.globalpayments.paymentsservice.model.dto.PaymentDtos.*;
import com.globalpayments.paymentsservice.model.enums.Currency;
import com.globalpayments.paymentsservice.model.enums.PaymentStatus;
import com.globalpayments.paymentsservice.model.enums.PaymentType;
import com.globalpayments.paymentsservice.service.PaymentService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.kafka.test.context.EmbeddedKafka;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Integration tests for PaymentService.
 *
 * Uses:
 * - Testcontainers (PostgreSQL) via the 'test' profile TC JDBC URL
 * - Embedded Kafka for event publishing tests
 * - Flyway to set up the schema automatically
 *
 * These tests verify the full service → repository → database flow.
 */
@SpringBootTest
@ActiveProfiles("test")
@EmbeddedKafka(partitions = 1, topics = {"payment-events"})
@Transactional   // Rolls back DB state after each test
class PaymentServiceIntegrationTest {

    @Autowired
    private PaymentService paymentService;

    // ── Helpers ────────────────────────────────────────────────────────────

    private CreatePaymentRequest buildRequest() {
        return CreatePaymentRequest.builder()
                .senderAccountId("GB29NWBK60161331926819")
                .receiverAccountId("GB82WEST12345698765432")
                .receiverBankCode("BARCGB22")
                .amount(new BigDecimal("250.00"))
                .currency(Currency.GBP)
                .paymentType(PaymentType.DOMESTIC)
                .description("Test payment")
                .build();
    }

    // ── Tests ──────────────────────────────────────────────────────────────

    @Test
    @DisplayName("createPayment — should create payment with PENDING status")
    void createPayment_ShouldReturnPendingPayment() {
        PaymentResponse response = paymentService.createPayment(buildRequest());

        assertThat(response.getId()).isNotNull();
        assertThat(response.getPaymentReference()).startsWith("PAY-");
        assertThat(response.getStatus()).isEqualTo(PaymentStatus.PENDING);
        assertThat(response.getAmount()).isEqualByComparingTo(new BigDecimal("250.00"));
        assertThat(response.getCurrency()).isEqualTo(Currency.GBP);
    }

    @Test
    @DisplayName("createPayment — idempotency key should return same result on duplicate")
    void createPayment_WithIdempotencyKey_ShouldReturnSamePayment() {
        String idempotencyKey = UUID.randomUUID().toString();

        CreatePaymentRequest request = CreatePaymentRequest.builder()
                .senderAccountId("GB29NWBK60161331926819")
                .receiverAccountId("GB82WEST12345698765432")
                .receiverBankCode("BARCGB22")
                .amount(new BigDecimal("100.00"))
                .currency(Currency.GBP)
                .paymentType(PaymentType.DOMESTIC)
                .idempotencyKey(idempotencyKey)
                .build();

        PaymentResponse first  = paymentService.createPayment(request);
        PaymentResponse second = paymentService.createPayment(request);

        // Must return exact same payment ID — not create a second payment
        assertThat(first.getId()).isEqualTo(second.getId());
        assertThat(first.getPaymentReference()).isEqualTo(second.getPaymentReference());
    }

    @Test
    @DisplayName("getPaymentById — should return payment when found")
    void getPaymentById_ShouldReturnPayment() {
        PaymentResponse created = paymentService.createPayment(buildRequest());
        PaymentResponse fetched = paymentService.getPaymentById(created.getId());

        assertThat(fetched.getId()).isEqualTo(created.getId());
        assertThat(fetched.getPaymentReference()).isEqualTo(created.getPaymentReference());
    }

    @Test
    @DisplayName("getPaymentById — should throw when payment not found")
    void getPaymentById_ShouldThrowWhenNotFound() {
        UUID nonExistentId = UUID.randomUUID();

        assertThatThrownBy(() -> paymentService.getPaymentById(nonExistentId))
                .hasMessageContaining(nonExistentId.toString());
    }

    @Test
    @DisplayName("updateStatus — should update from PENDING to COMPLETED")
    void updateStatus_ShouldTransitionSuccessfully() {
        PaymentResponse created = paymentService.createPayment(buildRequest());

        UpdateStatusRequest statusRequest = UpdateStatusRequest.builder()
                .newStatus(PaymentStatus.COMPLETED)
                .clearingReference("CLR-2024-123456")
                .build();

        PaymentResponse updated = paymentService.updateStatus(created.getId(), statusRequest);

        assertThat(updated.getStatus()).isEqualTo(PaymentStatus.COMPLETED);
        assertThat(updated.getClearingReference()).isEqualTo("CLR-2024-123456");
    }

    @Test
    @DisplayName("updateStatus — should throw when transitioning from COMPLETED")
    void updateStatus_ShouldRejectTransitionFromFinalState() {
        PaymentResponse created = paymentService.createPayment(buildRequest());

        // First, complete it
        paymentService.updateStatus(created.getId(), UpdateStatusRequest.builder()
                .newStatus(PaymentStatus.COMPLETED).build());

        // Then try to move it back — should fail
        assertThatThrownBy(() -> paymentService.updateStatus(created.getId(),
                UpdateStatusRequest.builder().newStatus(PaymentStatus.PENDING).build()))
                .hasMessageContaining("COMPLETED");
    }
}
