-- Migration: Add Refund Preferences and Credit System
-- Description: Supports donor-selected refund preferences (Credits vs Beneficiary Redirect)

-- 1. Add refund preference to donation_transactions
ALTER TABLE public.donation_transactions
ADD COLUMN IF NOT EXISTS refund_preference text DEFAULT 'credit'
CHECK (refund_preference IN ('credit', 'beneficiary'));

-- 2. Add refund_credit_expiry_days to donation_categories
ALTER TABLE public.donation_categories
ADD COLUMN IF NOT EXISTS refund_credit_expiry_days integer DEFAULT 90;

-- 3. Create donation_credits_ledger to track user refund credits
CREATE TABLE IF NOT EXISTS public.donation_credits_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) NOT NULL,
    transaction_ref_id uuid REFERENCES public.donation_transactions(id),
    amount numeric(15, 2) NOT NULL,
    type text NOT NULL CHECK (type IN ('refund_earned', 'credit_used', 'credit_expired', 'credit_withdrawn')),
    created_at timestamptz DEFAULT now(),
    expires_at timestamptz
);

-- Index for fast user balance calculation
CREATE INDEX IF NOT EXISTS idx_donation_credits_user_id ON public.donation_credits_ledger(user_id);

-- RLS
ALTER TABLE public.donation_credits_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own credits"
    ON public.donation_credits_ledger FOR SELECT
    USING (auth.uid() = user_id);

-- Note: Inserts managed strictly by Node.js Escrow Service (Service Role)
