-- Migration: Seed Phase 2 Sample Data
-- Date: 2026-06-11
-- Prerequisites: Phase 2 tables exist + professions with category='provider' exist

-- ============================================================
-- 1. Seed Riders
-- ============================================================
DO $$
DECLARE
    v_profession_id UUID;
BEGIN
    SELECT id INTO v_profession_id
    FROM public.professions
    WHERE category = 'provider'
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RAISE NOTICE 'No provider profession found — skipping rider seed';
        RETURN;
    END IF;

    INSERT INTO public.riders (profession_id, rider_code, full_name, phone, vehicle_type, license_plate, is_available)
    VALUES
        (v_profession_id, 'R001', 'สมชาย รวดเร็ว', '081-111-1111', 'motorcycle', '1กค 1234', true),
        (v_profession_id, 'R002', 'สุดา ขับดี', '082-222-2222', 'motorcycle', '2ขค 5678', true),
        (v_profession_id, 'R003', 'มานะ ส่งไว', '083-333-3333', 'car', '3คง 9012', false)
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'Seeded riders for profession %', v_profession_id;
END $$;

-- ============================================================
-- 2. Seed Vendor Contracts (Settlement)
-- ============================================================
DO $$
DECLARE
    v_profession_id UUID;
BEGIN
    SELECT id INTO v_profession_id
    FROM public.professions
    WHERE category = 'provider'
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.vendor_contracts (
        profession_id, vendor_name, vendor_type, contract_code,
        fee_percent, fixed_fee_per_txn, payout_cycle_days, is_active
    )
    VALUES
        (v_profession_id, 'Sheserved Platform', 'platform', 'SHE-001', 3.00, 0, 7, true),
        (v_profession_id, 'Delivery Partner Co.', 'delivery_partner', 'DEL-001', 15.00, 0, 14, true),
        (v_profession_id, 'PromptPay Gateway', 'payment_provider', 'PAY-001', 1.50, 5.00, 1, true)
    ON CONFLICT DO NOTHING;
END $$;

-- ============================================================
-- 3. Seed Merchant Accounts
-- ============================================================
DO $$
DECLARE
    v_profession_id UUID;
BEGIN
    SELECT id INTO v_profession_id
    FROM public.professions
    WHERE category = 'provider'
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.merchant_accounts (
        profession_id, account_name, account_number, bank_code, bank_name, account_type, is_primary, is_verified
    )
    VALUES
        (v_profession_id, 'คลินิกแพทย์ทั่วไป', '123-4-56789-0', '002', 'ธนาคารกรุงเทพ', 'corporate', true, true),
        (v_profession_id, 'สำรอง', '987-6-54321-0', '004', 'ธนาคารกสิกรไทย', 'savings', false, true)
    ON CONFLICT DO NOTHING;
END $$;
