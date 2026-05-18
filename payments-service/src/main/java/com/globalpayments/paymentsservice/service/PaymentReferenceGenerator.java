package com.globalpayments.paymentsservice.service;

import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Generates human-readable, sortable payment references.
 * Format: PAY-YYYYMMDD-NNNNNN  (e.g. PAY-20240315-000042)
 *
 * In a multi-instance production setup, the sequence would be backed
 * by a DB sequence or Redis counter to ensure global uniqueness.
 * For this service, a UUID suffix provides collision resistance.
 */
@Component
public class PaymentReferenceGenerator {

    private static final DateTimeFormatter DATE_FMT =
            DateTimeFormatter.ofPattern("yyyyMMdd");

    private final AtomicLong sequence = new AtomicLong(0);

    public String generate() {
        String date = LocalDate.now().format(DATE_FMT);
        long seq = sequence.incrementAndGet();
        // Append 4-char UUID fragment for cross-instance uniqueness
        String suffix = java.util.UUID.randomUUID().toString()
                .replaceAll("-", "").substring(0, 4).toUpperCase();
        return String.format("PAY-%s-%06d-%s", date, seq, suffix);
    }
}
