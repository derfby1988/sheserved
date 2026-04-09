-- =====================================================
-- Migration: Add Grace Period & Beneficiary columns to donation_categories
-- Date: 2026-04-09
-- Purpose: ให้ Admin กำหนด beneficiary_org ต่อ Category
--          และตั้งค่า Grace Period แบบยืดหยุ่นต่อ Category
-- Depends on: 20260409010000_add_beneficiary_system.sql
-- =====================================================

-- =====================================================
-- PART 1: เชื่อม donation_categories → beneficiary_organizations
-- =====================================================

ALTER TABLE public.donation_categories
    ADD COLUMN IF NOT EXISTS beneficiary_org_id UUID
        REFERENCES public.beneficiary_organizations(id) ON DELETE SET NULL;
-- NULL = ใช้ Global Default Beneficiary (is_global_default = TRUE) เป็น fallback

-- =====================================================
-- PART 2: Grace Period Columns (ยืดหยุ่นต่อ Category)
-- =====================================================

ALTER TABLE public.donation_categories
    ADD COLUMN IF NOT EXISTS pause_grace_period_hours INTEGER NOT NULL DEFAULT 72;
-- ชั่วโมงที่รอหลัง pause_deadline ก่อนโอนเงินให้ Beneficiary อัตโนมัติ
-- min = 12h (ป้องกัน Grace Period สั้นเกินไปจนผู้ใช้ไม่มีเวลาแก้ไข)
-- max = 720h (30 วัน)

ALTER TABLE public.donation_categories
    ADD COLUMN IF NOT EXISTS transfer_failure_grace_hours INTEGER NOT NULL DEFAULT 48;
-- ชั่วโมงที่ให้ Reporter แก้ไขบัญชีปลายทาง ก่อนโอนให้ Beneficiary
-- min = 6h | max = 720h

ALTER TABLE public.donation_categories
    ADD COLUMN IF NOT EXISTS cancellation_grace_hours INTEGER NOT NULL DEFAULT 24;
-- ชั่วโมงที่ให้ผู้บริจาคตัดสินใจ Refund vs Donate-to-Beneficiary
-- หลัง Reporter ยกเลิกคำร้อง
-- min = 1h (ยืดหยุ่นกว่าสองกรณีข้างบนเพราะ Reporter อาจยกเลิกเพราะต้องการด่วน)
-- max = 720h

-- Validate range ของ Grace Period columns
ALTER TABLE public.donation_categories
    ADD CONSTRAINT pause_grace_hours_range CHECK (
        pause_grace_period_hours BETWEEN 12 AND 720
    );

ALTER TABLE public.donation_categories
    ADD CONSTRAINT transfer_failure_grace_hours_range CHECK (
        transfer_failure_grace_hours BETWEEN 6 AND 720
    );

ALTER TABLE public.donation_categories
    ADD CONSTRAINT cancellation_grace_hours_range CHECK (
        cancellation_grace_hours BETWEEN 1 AND 720
    );

-- =====================================================
-- PART 3: Index เพื่อเร่งความเร็วในการ lookup
-- =====================================================

-- Index สำหรับ query หา category ที่มี/ไม่มี beneficiary (ใช้ใน Admin UI Warning)
CREATE INDEX IF NOT EXISTS idx_donation_categories_beneficiary_org
    ON public.donation_categories (beneficiary_org_id);

-- =====================================================
-- PART 4: ตรวจสอบ Global Default Beneficiary
-- DB Function: คืน beneficiary ที่เหมาะสมสำหรับ category นี้
-- ใช้ใน BeneficiaryTransferService ฝั่ง Node.js / Dart
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_effective_beneficiary(p_category_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_beneficiary_id UUID;
    v_global_id      UUID;
BEGIN
    -- 1. ดึง beneficiary ที่กำหนดไว้สำหรับ category นี้โดยตรง
    SELECT dc.beneficiary_org_id
    INTO v_beneficiary_id
    FROM public.donation_categories dc
    JOIN public.beneficiary_organizations bo ON bo.id = dc.beneficiary_org_id
    WHERE dc.id = p_category_id
      AND bo.is_active = TRUE
      AND bo.is_verified = TRUE;

    IF v_beneficiary_id IS NOT NULL THEN
        RETURN v_beneficiary_id;
    END IF;

    -- 2. Fallback: ดึง Global Default Beneficiary
    SELECT id
    INTO v_global_id
    FROM public.beneficiary_organizations
    WHERE is_global_default = TRUE
      AND is_active = TRUE
      AND is_verified = TRUE
    LIMIT 1;

    -- 3. ถ้าไม่มีทั้งคู่ → คืน NULL (ระบบต้อง block transfer + แจ้ง Admin)
    RETURN v_global_id;
END;
$$;

-- =====================================================
-- PART 5: เพิ่ม columns สำหรับ Net Goal / Gross Target ใน donation_requests
-- (ใช้คู่กับ Platform Fee System ซึ่งจะสร้างใน _add_fee_system.sql)
-- =====================================================
ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS goal_amount_net DECIMAL(12, 2);
    -- ยอดที่ผู้รับต้องการจริง (ที่แสดงให้ผู้ชมบนหน้า Live) = Net Goal

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS goal_amount_gross DECIMAL(12, 2);
    -- ยอดที่ระบบเปิดรับบริจาค = Net + Σfees (Gross Target)
    -- คำนวณจาก FeeCalculatorService ตอนสร้างคำร้อง

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS fee_snapshot JSONB;
    -- Snapshot ของ fee items ณ เวลาสร้างคำร้อง
    -- ป้องกัน: Admin เปลี่ยน platform fee ภายหลัง ไม่กระทบคำร้องที่มีอยู่แล้ว
    -- Format: [{ "name": "Sheserved Service", "fee_type": "percent_of_gross", "rate": 2.5 }, ...]
