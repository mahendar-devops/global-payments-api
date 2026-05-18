package com.globalpayments.paymentsservice.model.dto;

import com.globalpayments.paymentsservice.model.enums.Currency;
import com.globalpayments.paymentsservice.model.enums.PaymentStatus;
import com.globalpayments.paymentsservice.model.enums.PaymentType;
import jakarta.validation.constraints.*;
import lombok.Builder;
import lombok.Value;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

// ── Immutable DTOs using Lombok @Value ─────────────────────────────────────

/**
 * Inbound request to create a new payment.
 * Validated by Spring's @Valid before reaching the service layer.
 */
public class PaymentDtos {

    @Value
    @Builder
    public static class CreatePaymentRequest {

        @NotBlank(message = "Sender account ID is required")
        @Size(max = 34, message = "Account ID must not exceed 34 characters (IBAN)")
        String senderAccountId;

        @NotBlank(message = "Receiver account ID is required")
        @Size(max = 34)
        String receiverAccountId;

        @NotBlank(message = "Receiver bank code (BIC) is required")
        @Size(min = 8, max = 11, message = "BIC must be 8 or 11 characters")
        String receiverBankCode;

        /**
         * Amount in major units with decimal (e.g. 10.50).
         * Converted to minor units by the service layer.
         */
        @NotNull(message = "Amount is required")
        @DecimalMin(value = "0.01", message = "Amount must be greater than 0")
        @DecimalMax(value = "1000000.00", message = "Amount exceeds single-transaction limit")
        @Digits(integer = 10, fraction = 2)
        BigDecimal amount;

        @NotNull(message = "Currency is required")
        Currency currency;

        @NotNull(message = "Payment type is required")
        PaymentType paymentType;

        @Size(max = 140, message = "Description must not exceed 140 characters")
        String description;

        /**
         * Client-supplied idempotency key.
         * If the same key is submitted twice, the second call returns the
         * original result without creating a duplicate payment.
         */
        @Size(max = 64)
        String idempotencyKey;
    }

    /**
     * Outbound response for a payment. Returned on create and get.
     */
    @Value
    @Builder
    public static class PaymentResponse {
        UUID id;
        String paymentReference;
        String senderAccountId;
        String receiverAccountId;
        String receiverBankCode;
        BigDecimal amount;         // Human-readable major units
        Currency currency;
        PaymentStatus status;
        PaymentType paymentType;
        String description;
        String clearingReference;
        Integer retryCount;
        String failureReason;
        Instant createdAt;
        Instant updatedAt;
        String createdBy;
    }

    /**
     * Request to update a payment status (e.g., from an internal clearing event).
     */
    @Value
    @Builder
    public static class UpdateStatusRequest {

        @NotNull
        PaymentStatus newStatus;

        @Size(max = 50)
        String clearingReference;

        @Size(max = 500)
        String failureReason;
    }

    /**
     * Paginated list wrapper for collection endpoints.
     */
    @Value
    @Builder
    public static class PaymentPageResponse {
        java.util.List<PaymentResponse> payments;
        int page;
        int size;
        long totalElements;
        int totalPages;
    }
}
