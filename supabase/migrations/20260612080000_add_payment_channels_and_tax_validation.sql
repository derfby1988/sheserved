-- Migration: Payment Channels + branch_tax_code validation (Phase 3)
-- Date: 2026-06-12

-- =====================================================
-- PAYMENT CHANNELS TABLE
-- =====================================================
CREATE TABLE IF NOT EXISTS public.payment_channels (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    channel_code    TEXT NOT NULL,                  -- e.g. 'promptpay', 'cash', 'credit_card', 'qr_code'
    channel_name    TEXT NOT NULL,                  -- display name e.g. 'PromptPay QR'
    channel_type    TEXT NOT NULL DEFAULT 'other'
                        CHECK (channel_type IN ('cash', 'bank_transfer', 'promptpay', 'credit_card', 'e_wallet', 'other')),
    is_enabled      BOOLEAN NOT NULL DEFAULT true,
    is_default      BOOLEAN NOT NULL DEFAULT false,
    config          JSONB DEFAULT '{}'::jsonb,     -- gateway-specific config: {qr_code_payload, merchant_id, terminal_id, ...}
    fee_percent     DECIMAL(5,2) NOT NULL DEFAULT 0, -- fee charged by gateway
    display_order   INTEGER NOT NULL DEFAULT 0,
    icon_name       TEXT,                           -- flutter icon name e.g. 'qr_code', 'money', 'credit_card'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(profession_id, channel_code)
);

COMMENT ON TABLE public.payment_channels IS 'ช่องทางการชำระเงินที่ตั้งค่าไว้ต่อองค์กร';

-- RLS
ALTER TABLE public.payment_channels ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payment_channels_select ON public.payment_channels;
CREATE POLICY payment_channels_select ON public.payment_channels
    FOR SELECT USING (true);

DROP POLICY IF EXISTS payment_channels_modify ON public.payment_channels;
CREATE POLICY payment_channels_modify ON public.payment_channels
    FOR ALL USING (EXISTS (
        SELECT 1 FROM public.employee_roles er
        JOIN public.organization_roles r ON r.id = er.role_id
        WHERE er.user_id = auth.uid()
        AND er.profession_id = payment_channels.profession_id
        AND er.is_active = true
        AND r.role_name IN ('owner', 'admin')
    ));

-- =====================================================
-- SEED DEFAULT PAYMENT CHANNELS
-- =====================================================
CREATE OR REPLACE FUNCTION seed_default_payment_channels(p_profession_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.payment_channels (
        profession_id, channel_code, channel_name, channel_type,
        is_enabled, is_default, display_order, icon_name, fee_percent
    )
    VALUES
        (p_profession_id, 'cash', 'เงินสด', 'cash', true, true, 1, 'money', 0),
        (p_profession_id, 'promptpay', 'PromptPay QR', 'promptpay', true, false, 2, 'qr_code', 0),
        (p_profession_id, 'credit_card', 'บัตรเครดิต', 'credit_card', true, false, 3, 'credit_card', 2.5)
    ON CONFLICT (profession_id, channel_code) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- branch_tax_code VALIDATION FUNCTION
-- =====================================================
-- Thai branch tax code: typically 5 digits (00000 = head office)
CREATE OR REPLACE FUNCTION validate_branch_tax_code(p_branch_tax_code TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Allow NULL/empty (not required)
    IF p_branch_tax_code IS NULL OR p_branch_tax_code = '' THEN
        RETURN true;
    END IF;
    -- Must be exactly 5 digits (00000 - 99999)
    IF p_branch_tax_code ~ '^[0-9]{5}$' THEN
        RETURN true;
    END IF;
    RETURN false;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =====================================================
-- UPDATE upsert_branch TO VALIDATE branch_tax_code
-- =====================================================
CREATE OR REPLACE FUNCTION upsert_branch(
    p_branch_id         UUID,
    p_profession_id     UUID,
    p_branch_code       TEXT,
    p_branch_name       TEXT,
    p_tax_id            TEXT,
    p_branch_tax_code   TEXT,
    p_address           TEXT,
    p_phone             TEXT,
    p_email             TEXT,
    p_is_main_branch    BOOLEAN,
    p_is_active         BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- Validate branch_tax_code format
    IF p_branch_tax_code IS NOT NULL AND p_branch_tax_code != '' THEN
        IF NOT validate_branch_tax_code(p_branch_tax_code) THEN
            RAISE EXCEPTION 'รหัสสาขาภาษีต้องเป็นตัวเลข 5 หลัก (เช่น 00000, 00001)';
        END IF;
    END IF;

    IF p_branch_id IS NOT NULL THEN
        UPDATE public.organization_branches
        SET
            branch_code     = COALESCE(p_branch_code, branch_code),
            branch_name     = COALESCE(p_branch_name, branch_name),
            tax_id          = p_tax_id,
            branch_tax_code = p_branch_tax_code,
            address         = p_address,
            phone           = p_phone,
            email           = p_email,
            is_main_branch  = COALESCE(p_is_main_branch, is_main_branch),
            is_active       = COALESCE(p_is_active, is_active),
            updated_at      = NOW()
        WHERE id = p_branch_id
        RETURNING jsonb_build_object(
            'branch_id', id,
            'branch_code', branch_code,
            'branch_name', branch_name
        ) INTO v_result;
    ELSE
        INSERT INTO public.organization_branches (
            profession_id, branch_code, branch_name, tax_id, branch_tax_code,
            address, phone, email, is_main_branch, is_active
        )
        VALUES (
            p_profession_id, p_branch_code, p_branch_name, p_tax_id, p_branch_tax_code,
            p_address, p_phone, p_email, COALESCE(p_is_main_branch, false), COALESCE(p_is_active, true)
        )
        RETURNING jsonb_build_object(
            'branch_id', id,
            'branch_code', branch_code,
            'branch_name', branch_name
        ) INTO v_result;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
