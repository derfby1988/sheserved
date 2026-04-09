-- =====================================================
-- Migration: Add Flexible Platform Fee System
-- Date: 2026-04-09
-- Purpose: สร้างระบบค่าธรรมเนียมแพลตฟอร์มแบบยืดหยุ่น
--          Admin กำหนด fee items ต่อ Category ได้ไม่จำกัด
--          รองรับ 3 ประเภท: % of gross / fixed ฿ / % per transaction
--          พร้อม Net Goal → Gross Target UX Model
-- Depends on: 20260409030000_add_grace_period_columns.sql
-- =====================================================

-- =====================================================
-- TABLE: category_fee_items
-- รายการค่าธรรมเนียมต่อ Category (ไม่จำกัดจำนวนรายการ)
-- Admin เพิ่ม/แก้ไข/ลบได้ผ่าน Category Admin UI
-- =====================================================
CREATE TABLE IF NOT EXISTS public.category_fee_items (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id     UUID        NOT NULL REFERENCES public.donation_categories(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,      -- ชื่อรายการ เช่น "Sheserved Service Fee"
    fee_type        VARCHAR(50) NOT NULL,
    -- 'percent_of_gross'       → rate × gross_amount (คิดจากยอด escrow รวม ณ เวลา disburse)
    -- 'fixed_baht'             → amount คงที่ (฿) ต่อการ disburse 1 ครั้ง
    -- 'percent_per_transaction' → rate × each confirmed transaction amount
    rate            DECIMAL(10, 4),             -- ค่า % เช่น 2.5 = 2.5% — NULL ถ้า fixed_baht
    amount          DECIMAL(12, 2),             -- ฿ คงที่ — NULL ถ้าเป็น %
    display_order   INTEGER     NOT NULL DEFAULT 0,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    note            TEXT,                       -- หมายเหตุ Admin ว่าทำไมถึงมีค่านี้
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ตรวจสอบ fee_type ที่ถูกต้อง
    CONSTRAINT fee_type_valid CHECK (
        fee_type IN ('percent_of_gross', 'fixed_baht', 'percent_per_transaction')
    ),
    -- ตรวจสอบว่าใส่ rate หรือ amount ให้ถูกต้องตาม fee_type
    CONSTRAINT rate_or_amount_required CHECK (
        (fee_type = 'fixed_baht'  AND amount IS NOT NULL AND rate IS NULL) OR
        (fee_type != 'fixed_baht' AND rate   IS NOT NULL AND amount IS NULL)
    ),
    -- rate ต้องมากกว่า 0 เสมอ
    CONSTRAINT rate_positive CHECK (rate IS NULL OR rate > 0),
    -- amount ต้องมากกว่า 0 เสมอ
    CONSTRAINT amount_positive CHECK (amount IS NULL OR amount > 0)
);

-- Index สำหรับ query fee items ต่อ category (เรียงตาม display_order)
CREATE INDEX IF NOT EXISTS idx_fee_items_category_id
    ON public.category_fee_items (category_id, display_order);

-- =====================================================
-- TABLE: donation_disbursement_logs
-- บันทึกทุกครั้งที่ escrow ถูก release ให้ Reporter (Mission Complete)
-- เก็บ fee_breakdown แบบละเอียดสำหรับ Tax/Audit/Report
-- =====================================================
CREATE TABLE IF NOT EXISTS public.donation_disbursement_logs (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id        UUID        NOT NULL REFERENCES public.donation_requests(id) ON DELETE CASCADE,
    disbursed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    gross_amount      DECIMAL(12, 2) NOT NULL CHECK (gross_amount > 0),
    -- ยอด escrow รวมก่อนหักค่าธรรมเนียม
    net_amount        DECIMAL(12, 2) NOT NULL CHECK (net_amount >= 0),
    -- ยอดสุทธิที่โอนให้ Reporter (gross - total_fees)
    fee_breakdown     JSONB       NOT NULL,
    -- รายละเอียดทุกรายการที่หัก:
    -- [{ "name": "Sheserved Service", "fee_type": "percent_of_gross",
    --    "rate": 2.5, "deducted": 25.77 }, ...]
    total_fees        DECIMAL(12, 2) NOT NULL CHECK (total_fees >= 0),
    -- ยอดค่าธรรมเนียมรวม (gross - net)
    recipient_account VARCHAR(255),             -- บัญชีปลายทางของ Reporter
    transfer_ref      VARCHAR(255),             -- reference จาก gateway ขณะโอน
    disbursed_by      VARCHAR(50) NOT NULL DEFAULT 'system',
    -- 'system'       → อัตโนมัติหลัง consensus ผ่าน
    -- 'manual_admin' → Admin บังคับ release ด้วยตนเอง

    CONSTRAINT disbursed_by_valid CHECK (disbursed_by IN ('system', 'manual_admin')),
    -- ตรวจสอบว่า net + fees = gross (อนุญาต ±0.01 เพราะ floating point)
    CONSTRAINT amounts_consistent CHECK (
        ABS(gross_amount - net_amount - total_fees) < 0.02
    )
);

-- Index สำหรับ Reports tab (query ตาม request_id และวันที่)
CREATE INDEX IF NOT EXISTS idx_disbursement_logs_request_id
    ON public.donation_disbursement_logs (request_id, disbursed_at DESC);

-- Index สำหรับ summary report (query ตามช่วงวันที่)
CREATE INDEX IF NOT EXISTS idx_disbursement_logs_date
    ON public.donation_disbursement_logs (disbursed_at DESC);

-- =====================================================
-- TABLE: donation_closure_consensus
-- บันทึกการโหวตของ Responder แต่ละรายหลัง Incident Resolved
-- ใช้ตัดสินว่าจะเปิดรับบริจาคต่อหรือระงับ
-- =====================================================
CREATE TABLE IF NOT EXISTS public.donation_closure_consensus (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id    UUID        NOT NULL REFERENCES public.donation_requests(id) ON DELETE CASCADE,
    responder_id  UUID        NOT NULL,  -- volunteer_id จาก incident_responses
    can_continue  BOOLEAN     NOT NULL,  -- TRUE = อนุญาตรับบริจาคต่อ, FALSE = Veto (ระงับ)
    voted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    note          TEXT,                  -- เหตุผลเสริม (optional)

    -- 1 responder โหวตได้ 1 ครั้งต่อ 1 คำร้อง
    UNIQUE (request_id, responder_id)
);

-- Index สำหรับ query votes ของ request นี้
CREATE INDEX IF NOT EXISTS idx_closure_consensus_request_id
    ON public.donation_closure_consensus (request_id);

-- =====================================================
-- DB FUNCTION: process_donation_consensus
-- ตรวจสอบผล Consensus และอัปเดตสถานะคำร้องบริจาค
-- เรียกหลัง Responder กด "เสร็จสิ้น" ทุกราย
-- =====================================================
CREATE OR REPLACE FUNCTION public.process_donation_consensus(p_request_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    veto_exists     BOOLEAN;
    v_pause_hours   INTEGER;
    v_deadline      TIMESTAMPTZ;
BEGIN
    -- 1. ตรวจว่ามี Responder แม้แต่รายเดียวที่โหวต Veto (FALSE) หรือไม่
    SELECT EXISTS (
        SELECT 1 FROM public.donation_closure_consensus
        WHERE request_id = p_request_id AND can_continue = FALSE
    ) INTO veto_exists;

    IF veto_exists THEN
        -- 2a. ดึง pause_grace_period_hours จาก category ของคำร้องนี้
        SELECT COALESCE(dc.pause_grace_period_hours, 72)
        INTO v_pause_hours
        FROM public.donation_requests dr
        JOIN public.donation_categories dc ON dc.id = dr.category_id
        WHERE dr.id = p_request_id;

        v_deadline := NOW() + (v_pause_hours || ' hours')::INTERVAL;

        -- 2b. ระงับคำร้อง + ตั้ง pause_deadline สำหรับ background job
        UPDATE public.donation_requests
        SET is_paused    = TRUE,
            pause_reason = 'ไม่ได้รับความเห็นชอบจากเจ้าหน้าที่ทุกรายให้รับบริจาคต่อ',
            pause_deadline = v_deadline,
            updated_at   = NOW()
        WHERE id = p_request_id;

        RETURN jsonb_build_object(
            'result', 'paused',
            'pause_deadline', v_deadline
        );
    ELSE
        -- 3. ทุกคนเห็นชอบ → คงสถานะ active (ไม่ต้องทำอะไร)
        RETURN jsonb_build_object('result', 'active');
    END IF;
END;
$$;

-- =====================================================
-- RLS Policies
-- =====================================================
ALTER TABLE public.category_fee_items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_disbursement_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_closure_consensus ENABLE ROW LEVEL SECURITY;

-- category_fee_items: ทุกคนอ่านได้ (ผู้บริจาคต้องเห็น fee ก่อนชำระ)
CREATE POLICY "fee_items_select_all"
    ON public.category_fee_items FOR SELECT USING (true);

-- INSERT/UPDATE/DELETE: เฉพาะ Super Admin (enforce ฝั่ง App)
CREATE POLICY "fee_items_insert_all"
    ON public.category_fee_items FOR INSERT WITH CHECK (true);

CREATE POLICY "fee_items_update_all"
    ON public.category_fee_items FOR UPDATE USING (true);

CREATE POLICY "fee_items_delete_all"
    ON public.category_fee_items FOR DELETE USING (true);

-- donation_disbursement_logs: ทุกคนอ่านได้ (สำหรับ Transparency/Audit)
CREATE POLICY "disbursement_logs_select_all"
    ON public.donation_disbursement_logs FOR SELECT USING (true);

CREATE POLICY "disbursement_logs_insert_all"
    ON public.donation_disbursement_logs FOR INSERT WITH CHECK (true);

-- donation_closure_consensus: ทุกคนอ่านได้ (Transparency)
CREATE POLICY "closure_consensus_select_all"
    ON public.donation_closure_consensus FOR SELECT USING (true);

CREATE POLICY "closure_consensus_insert_all"
    ON public.donation_closure_consensus FOR INSERT WITH CHECK (true);

CREATE POLICY "closure_consensus_update_all"
    ON public.donation_closure_consensus FOR UPDATE USING (true);

-- =====================================================
-- Seed: เพิ่ม default fee items ตัวอย่าง (สำหรับ Dev)
-- Admin สามารถแก้ไขได้ผ่าน Admin UI
-- =====================================================
-- (ไม่ seed จริงในนี้ เพราะต้องรู้ category_id ก่อน
--  ให้ Admin ตั้งค่าใน Category Admin UI แทน)
