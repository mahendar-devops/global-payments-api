package com.globalpayments.paymentsservice.controller;

import com.globalpayments.paymentsservice.exception.PaymentNotFoundException;
import com.globalpayments.paymentsservice.exception.PaymentStateException;
import com.globalpayments.paymentsservice.model.dto.PaymentDtos.*;
import com.globalpayments.paymentsservice.service.PaymentService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/payments")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "Payments", description = "Core payment processing API")
@SecurityRequirement(name = "bearerAuth")
public class PaymentController {

    private final PaymentService paymentService;

    // ── POST /api/v1/payments ──────────────────────────────────────────────

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasAnyRole('PAYMENT_INITIATOR', 'ADMIN')")
    @Operation(
        summary = "Create a new payment",
        description = "Initiates a new payment. Supports idempotency via the Idempotency-Key header."
    )
    @ApiResponse(responseCode = "201", description = "Payment created")
    @ApiResponse(responseCode = "400", description = "Validation error")
    @ApiResponse(responseCode = "409", description = "Duplicate idempotency key with different payload")
    public ResponseEntity<PaymentResponse> createPayment(
            @Valid @RequestBody CreatePaymentRequest request,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey) {

        // If idempotency key provided in header, merge into request
        CreatePaymentRequest enriched = idempotencyKey != null
                ? CreatePaymentRequest.builder()
                    .senderAccountId(request.getSenderAccountId())
                    .receiverAccountId(request.getReceiverAccountId())
                    .receiverBankCode(request.getReceiverBankCode())
                    .amount(request.getAmount())
                    .currency(request.getCurrency())
                    .paymentType(request.getPaymentType())
                    .description(request.getDescription())
                    .idempotencyKey(idempotencyKey)
                    .build()
                : request;

        PaymentResponse response = paymentService.createPayment(enriched);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    // ── GET /api/v1/payments/{id} ──────────────────────────────────────────

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('PAYMENT_VIEWER', 'PAYMENT_INITIATOR', 'ADMIN')")
    @Operation(summary = "Get payment by ID")
    @ApiResponse(responseCode = "200", description = "Payment found")
    @ApiResponse(responseCode = "404", description = "Payment not found")
    public ResponseEntity<PaymentResponse> getPaymentById(
            @PathVariable @Parameter(description = "Payment UUID") UUID id) {
        return ResponseEntity.ok(paymentService.getPaymentById(id));
    }

    // ── GET /api/v1/payments/ref/{reference} ──────────────────────────────

    @GetMapping("/ref/{reference}")
    @PreAuthorize("hasAnyRole('PAYMENT_VIEWER', 'PAYMENT_INITIATOR', 'ADMIN')")
    @Operation(summary = "Get payment by business reference (PAY-YYYYMMDD-NNNNNN)")
    public ResponseEntity<PaymentResponse> getPaymentByReference(
            @PathVariable String reference) {
        return ResponseEntity.ok(paymentService.getPaymentByReference(reference));
    }

    // ── GET /api/v1/payments?senderAccountId=...&page=0&size=20 ───────────

    @GetMapping
    @PreAuthorize("hasAnyRole('PAYMENT_VIEWER', 'PAYMENT_INITIATOR', 'ADMIN')")
    @Operation(summary = "List payments for a sender account (paginated)")
    public ResponseEntity<PaymentPageResponse> getPayments(
            @RequestParam String senderAccountId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {

        // Cap page size to prevent abuse
        int cappedSize = Math.min(size, 100);

        PageRequest pageRequest = PageRequest.of(
                page, cappedSize, Sort.by(Sort.Direction.DESC, "createdAt"));

        return ResponseEntity.ok(
                paymentService.getPaymentsBySender(senderAccountId, pageRequest));
    }

    // ── PATCH /api/v1/payments/{id}/status ────────────────────────────────
    // Internal endpoint: called by the clearing/settlement service, not clients

    @PatchMapping("/{id}/status")
    @PreAuthorize("hasRole('INTERNAL_SERVICE')")
    @Operation(
        summary = "Update payment status (internal)",
        description = "Called by internal clearing/settlement services only. Not exposed externally."
    )
    public ResponseEntity<PaymentResponse> updateStatus(
            @PathVariable UUID id,
            @Valid @RequestBody UpdateStatusRequest request) {
        return ResponseEntity.ok(paymentService.updateStatus(id, request));
    }
}
