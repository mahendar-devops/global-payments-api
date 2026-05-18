package com.globalpayments.paymentsservice.exception;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

/**
 * Thrown when a payment creation attempt is detected as a duplicate.
 * This is distinct from idempotency (which returns the original result silently).
 * This fires when the same idempotency key is submitted with DIFFERENT payload values.
 * Maps to HTTP 409 Conflict.
 */
@ResponseStatus(HttpStatus.CONFLICT)
public class DuplicatePaymentException extends RuntimeException {

    public DuplicatePaymentException(String message) {
        super(message);
    }

    public DuplicatePaymentException(String message, Throwable cause) {
        super(message, cause);
    }
}
