-- Migration: Settlement RPC Functions
-- Date: 2026-06-12
-- Prerequisites: Phase 2 settlement tables (vendor_contracts, payment_allocations, payout_batches, payout_batch_lines, merchant_accounts)

-- ============================================================
-- 1. CALCULATE PAYMENT ALLOCATION
-- คำนวณ fee จาก vendor contract แล้วบันทึก payment_allocations
-- ============================================================
CREATE OR REPLACE FUNCTION calculate_payment_allocation(
    p_order_id UUID,
    p_payment_txn_id UUID,
    p_gross_amount DECIMAL(12,2)
)
RETURNS UUID AS $$
DECLARE
    v_profession_id UUID;
    v_contract RECORD;
    v_fee_amount DECIMAL(12,2);
    v_net_amount DECIMAL(12,2);
    v_platform_fee DECIMAL(12,2);
    v_merchant_payout DECIMAL(12,2);
    v_allocation_id UUID;
BEGIN
    -- Get profession_id from order
    SELECT profession_id INTO v_profession_id
    FROM public.orders
    WHERE id = p_order_id;

    IF v_profession_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    -- Find active vendor contract for this profession (prefer platform type, then merchant)
    SELECT *
    INTO v_contract
    FROM public.vendor_contracts
    WHERE profession_id = v_profession_id
      AND is_active = true
      AND effective_from <= CURRENT_DATE
      AND (effective_until IS NULL OR effective_until >= CURRENT_DATE)
    ORDER BY
        CASE vendor_type
            WHEN 'platform' THEN 1
            WHEN 'merchant' THEN 2
            ELSE 3
        END,
        fee_percent DESC
    LIMIT 1;

    -- Calculate fee
    IF v_contract IS NOT NULL THEN
        v_fee_amount := (p_gross_amount * v_contract.fee_percent / 100) + v_contract.fixed_fee_per_txn;

        -- Clamp with min/max
        IF v_contract.min_fee > 0 AND v_fee_amount < v_contract.min_fee THEN
            v_fee_amount := v_contract.min_fee;
        END IF;
        IF v_contract.max_fee > 0 AND v_fee_amount > v_contract.max_fee THEN
            v_fee_amount := v_contract.max_fee;
        END IF;
    ELSE
        v_fee_amount := 0;
    END IF;

    v_platform_fee := v_fee_amount;
    v_merchant_payout := p_gross_amount - v_fee_amount;
    v_net_amount := p_gross_amount;

    -- Insert payment allocation
    INSERT INTO public.payment_allocations (
        profession_id,
        order_id,
        payment_txn_id,
        vendor_contract_id,
        gross_amount,
        fee_amount,
        net_amount,
        platform_fee,
        merchant_payout,
        allocation_status
    )
    VALUES (
        v_profession_id,
        p_order_id,
        p_payment_txn_id,
        v_contract.id,
        p_gross_amount,
        v_fee_amount,
        v_net_amount,
        v_platform_fee,
        v_merchant_payout,
        'calculated'
    )
    RETURNING id INTO v_allocation_id;

    RETURN v_allocation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 2. CREATE PAYOUT BATCH
-- รวม payment_allocations ที่ calculated แล้วสร้าง payout batch
-- ============================================================
CREATE OR REPLACE FUNCTION create_payout_batch(
    p_profession_id UUID,
    p_merchant_account_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_batch_id UUID;
    v_total_amount DECIMAL(12,2);
BEGIN
    -- Calculate total pending payout for this profession
    SELECT COALESCE(SUM(merchant_payout), 0)
    INTO v_total_amount
    FROM public.payment_allocations
    WHERE profession_id = p_profession_id
      AND allocation_status = 'calculated';

    IF v_total_amount <= 0 THEN
        RAISE EXCEPTION 'No calculated allocations to payout for profession %', p_profession_id;
    END IF;

    -- Create payout batch
    INSERT INTO public.payout_batches (
        profession_id,
        batch_date,
        total_amount,
        status
    )
    VALUES (
        p_profession_id,
        CURRENT_DATE,
        v_total_amount,
        'pending'
    )
    RETURNING id INTO v_batch_id;

    -- Create batch lines and mark allocations as paid_out
    INSERT INTO public.payout_batch_lines (
        payout_batch_id,
        allocation_id,
        merchant_account_id,
        amount,
        status
    )
    SELECT
        v_batch_id,
        pa.id,
        COALESCE(p_merchant_account_id, (
            SELECT id FROM public.merchant_accounts
            WHERE profession_id = p_profession_id AND is_primary = true
            LIMIT 1
        )),
        pa.merchant_payout,
        'pending'
    FROM public.payment_allocations pa
    WHERE pa.profession_id = p_profession_id
      AND pa.allocation_status = 'calculated';

    -- Mark allocations as paid_out
    UPDATE public.payment_allocations
    SET allocation_status = 'paid_out',
        paid_out_at = NOW()
    WHERE profession_id = p_profession_id
      AND allocation_status = 'calculated';

    RETURN v_batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3. GET SETTLEMENT SUMMARY
-- สรุปยอดรอจ่าย / จ่ายแล้ว / รายได้แพลตฟอร์ม
-- ============================================================
CREATE OR REPLACE FUNCTION get_settlement_summary(p_profession_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_gross', COALESCE(SUM(gross_amount), 0),
        'total_fee', COALESCE(SUM(fee_amount), 0),
        'total_platform_fee', COALESCE(SUM(platform_fee), 0),
        'total_merchant_payout', COALESCE(SUM(merchant_payout), 0),
        'pending_count', COUNT(*) FILTER (WHERE allocation_status = 'pending'),
        'calculated_count', COUNT(*) FILTER (WHERE allocation_status = 'calculated'),
        'paid_out_count', COUNT(*) FILTER (WHERE allocation_status = 'paid_out'),
        'failed_count', COUNT(*) FILTER (WHERE allocation_status = 'failed')
    )
    INTO v_result
    FROM public.payment_allocations
    WHERE profession_id = p_profession_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
