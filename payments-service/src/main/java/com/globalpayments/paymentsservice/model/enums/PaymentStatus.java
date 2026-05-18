package com.globalpayments.paymentsservice.model.enums;

public enum PaymentStatus {
    PENDING,        // Created, awaiting processing
    PROCESSING,     // Sent to clearing network
    COMPLETED,      // Successfully settled
    FAILED,         // Processing failed (may retry)
    CANCELLED,      // Cancelled before processing
    REFUNDED        // Reversed after completion
}
