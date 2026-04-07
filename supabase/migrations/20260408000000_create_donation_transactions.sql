-- =====================================================
-- Migration: Create donation_transactions table
-- Date: 2026-04-08
-- Purpose: Track real payment transactions for donation requests.
--          Supports mock (dev), promptpay, and omise_card methods.
--          current_amount on donation_requests is updated ONLY after
--          a transaction is confirmed — no more optimistic accumulation.
-- =====================================================

CREATE TABLE IF NOT EXISTS donation_transactions (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id         UUID NOT NULL REFERENCES donation_requests(id) ON DELETE CASCADE,
    donor_user_id      UUID NOT NULL,
    amount             DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    payment_method     VARCHAR(50) NOT NULL DEFAULT 'mock',
                       -- allowed values: 'mock' | 'promptpay' | 'omise_card'
    payment_reference  VARCHAR(255),
                       -- transaction reference from payment gateway (null while pending)
    status             VARCHAR(20) NOT NULL DEFAULT 'pending',
                       -- allowed values: 'pending' | 'confirmed' | 'failed'
    confirmed_at       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookup by request
CREATE INDEX IF NOT EXISTS idx_donation_transactions_request_id
    ON donation_transactions (request_id);

-- Index for fast lookup by donor
CREATE INDEX IF NOT EXISTS idx_donation_transactions_donor_user_id
    ON donation_transactions (donor_user_id);

-- =====================================================
-- RLS Policies
-- Note: Sheserved does not use Supabase Auth directly (auth.uid() is null).
-- Logic checks happen via ServiceLocator and Flutter app.
-- =====================================================

ALTER TABLE donation_transactions ENABLE ROW LEVEL SECURITY;

-- Allow all read access
CREATE POLICY "transaction_select_all"
    ON donation_transactions
    FOR SELECT
    USING (true);

-- Allow all insert access
CREATE POLICY "transaction_insert_all"
    ON donation_transactions
    FOR INSERT
    WITH CHECK (true);

-- Allow all update access
CREATE POLICY "transaction_update_all"
    ON donation_transactions
    FOR UPDATE
    USING (true);

-- Service role bypass (for Supabase Edge Functions / webhook confirmations)
-- No explicit policy needed — service_role bypasses RLS by default.

-- =====================================================
-- Function: Confirm transaction & update current_amount atomically
-- Called by: PaymentService.confirmTransaction() or webhook Edge Function
-- =====================================================

CREATE OR REPLACE FUNCTION confirm_donation_transaction(p_transaction_id UUID, p_reference VARCHAR DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_amount      DECIMAL(12, 2);
    v_request_id  UUID;
    v_status      VARCHAR(20);
BEGIN
    -- Lock the row and fetch info
    SELECT amount, request_id, status
    INTO v_amount, v_request_id, v_status
    FROM donation_transactions
    WHERE id = p_transaction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction not found: %', p_transaction_id;
    END IF;

    IF v_status = 'confirmed' THEN
        RETURN; -- idempotent: already confirmed, skip
    END IF;

    IF v_status = 'failed' THEN
        RAISE EXCEPTION 'Cannot confirm a failed transaction: %', p_transaction_id;
    END IF;

    -- Mark transaction as confirmed
    UPDATE donation_transactions
    SET status           = 'confirmed',
        confirmed_at     = NOW(),
        payment_reference = COALESCE(p_reference, payment_reference)
    WHERE id = p_transaction_id;

    -- Atomically increment current_amount on the donation_request
    UPDATE donation_requests
    SET current_amount = current_amount + v_amount,
        updated_at     = NOW()
    WHERE id = v_request_id;
END;
$$;
