-- ============================================================================
-- 007_payment.sql
-- Application fee / payment status (mirrors the real portal's "Fee Status").
-- One payment row per application, auto-created PENDING by a trigger on submit
-- (see triggers/02_rules.sql), settled by sp_pay_fee (mock gateway).
-- ============================================================================

CREATE TABLE IF NOT EXISTS payment (
    application_id VARCHAR(20)  PRIMARY KEY REFERENCES application(application_id) ON DELETE CASCADE,
    amount         NUMERIC(8,2) NOT NULL DEFAULT 150.00 CHECK (amount >= 0),
    status         VARCHAR(10)  NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PAID')),
    method         VARCHAR(20),
    paid_at        TIMESTAMPTZ,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_status ON payment(status);
