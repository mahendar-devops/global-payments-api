-- V1__create_payments_table.sql
-- Flyway migration: creates the core payments table.
-- NEVER modify this file after it has run in any environment.
-- Create a new V2__ migration for any changes.

CREATE TABLE IF NOT EXISTS payments (
    id                   UUID         NOT NULL DEFAULT gen_random_uuid(),
    payment_reference    VARCHAR(30)  NOT NULL,
    sender_account_id    VARCHAR(34)  NOT NULL,
    receiver_account_id  VARCHAR(34)  NOT NULL,
    receiver_bank_code   VARCHAR(11)  NOT NULL,
    amount_minor_units   BIGINT       NOT NULL CHECK (amount_minor_units > 0),
    currency             VARCHAR(3)   NOT NULL,
    status               VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    payment_type         VARCHAR(20)  NOT NULL,
    description          VARCHAR(140),
    clearing_reference   VARCHAR(50),
    idempotency_key      VARCHAR(64),
    retry_count          INTEGER      NOT NULL DEFAULT 0,
    failure_reason       VARCHAR(500),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by           VARCHAR(100),
    version              BIGINT       NOT NULL DEFAULT 0,

    CONSTRAINT pk_payments               PRIMARY KEY (id),
    CONSTRAINT uq_payment_reference      UNIQUE (payment_reference),
    CONSTRAINT uq_idempotency_key        UNIQUE (idempotency_key),
    CONSTRAINT ck_currency               CHECK (currency IN ('GBP','USD','EUR','JPY','CHF','CAD','AUD','SGD','HKD','INR')),
    CONSTRAINT ck_status                 CHECK (status IN ('PENDING','PROCESSING','COMPLETED','FAILED','CANCELLED','REFUNDED')),
    CONSTRAINT ck_payment_type           CHECK (payment_type IN ('DOMESTIC','SEPA','SWIFT')),
    CONSTRAINT ck_retry_count            CHECK (retry_count >= 0 AND retry_count <= 3)
);

-- Indexes for common query patterns
CREATE INDEX idx_payments_reference      ON payments (payment_reference);
CREATE INDEX idx_payments_sender_acc     ON payments (sender_account_id);
CREATE INDEX idx_payments_receiver_acc   ON payments (receiver_account_id);
CREATE INDEX idx_payments_status         ON payments (status);
CREATE INDEX idx_payments_created_at     ON payments (created_at DESC);
CREATE INDEX idx_payments_idempotency    ON payments (idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Trigger to auto-update updated_at on row modification
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE  payments                IS 'Core payment transactions table';
COMMENT ON COLUMN payments.amount_minor_units IS 'Amount in minor currency units (e.g. pence, cents). Use with currency.decimal_places.';
COMMENT ON COLUMN payments.idempotency_key    IS 'Client-supplied deduplication key. NULL for non-idempotent requests.';
