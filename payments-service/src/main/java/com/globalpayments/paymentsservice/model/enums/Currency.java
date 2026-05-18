package com.globalpayments.paymentsservice.model.enums;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * Supported currencies with their ISO 4217 decimal places.
 * e.g. GBP and USD have 2 decimal places (100 pence/cents per unit).
 * JPY has 0 (no sub-unit).
 */
@Getter
@RequiredArgsConstructor
public enum Currency {
    GBP(2),
    USD(2),
    EUR(2),
    JPY(0),
    CHF(2),
    CAD(2),
    AUD(2),
    SGD(2),
    HKD(2),
    INR(2);

    private final int decimalPlaces;
}
