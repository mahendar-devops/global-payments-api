package com.globalpayments.paymentsservice.model.enums;

public enum PaymentType {
    DOMESTIC,   // Same-bank or domestic transfer (Faster Payments)
    SEPA,       // Single Euro Payments Area (EU)
    SWIFT       // International SWIFT transfer
}
