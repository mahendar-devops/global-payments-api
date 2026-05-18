package com.globalpayments.paymentsservice.exception;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

/**
 * Thrown when an invalid payment state transition is attempted.
 * Examples:
 *   - Trying to move a COMPLETED payment back to PENDING
 *   - Trying to cancel a payment that is already FAILED
 * Maps to HTTP 422 Unprocessable Entity.
 */
@ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
public class PaymentStateException extends RuntimeException {

    public PaymentStateException(String message) {
        super(message);
    }

    public PaymentStateException(String message, Throwable cause) {
        super(message, cause);
    }
}
