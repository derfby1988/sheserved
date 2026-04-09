-- =====================================================
-- Migration: Add Escrow Columns to donation_requests & update donation_transactions status
-- Date: 2026-04-09
-- Purpose: รองรับสถาปัตยกรรม Escrow-via-Beneficiary
--          เพิ่มฟิลด์ติดตาม Escrow Status และขยาย status ของ donation_transactions
--          ให้ครอบคลุม 13 states ของระบบ Escrow ตาม VIDEO_SYSTEM_PLAN.md
-- Depends on: 20260409010000_add_beneficiary_system.sql
--             20260408000000_create_donation_transactions.sql
-- =====================================================

-- =====================================================
-- PART 1: เพิ่ม Escrow columns ใน donation_requests
-- =====================================================

-- สถานะ Escrow โดยรวมของคำร้อง
ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS escrow_status VARCHAR(30) NOT NULL DEFAULT 'not_started';
    -- 'not_started' → ยังไม่มี transaction ใดถูก confirm
    -- 'in_escrow'   → มีเงินพักที่ Beneficiary Escrow Account อยู่
    -- 'released'    → Beneficiary โอนให้ Reporter สำเร็จแล้ว (disbursed)
    -- 'returned'    → เงินถูกคืนให้ผู้บริจาค (Refund) หรือโอนให้ Beneficiary ถาวร

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS escrow_released_at TIMESTAMPTZ;
    -- เวลาที่ escrow ถูก release (ไปยัง Reporter หรือ Beneficiary ถาวร)

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS escrow_release_ref VARCHAR(255);
    -- Payment reference จาก gateway ขณะ release escrow

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS beneficiary_transfer_at TIMESTAMPTZ;
    -- เวลาที่เงิน "ถูกโอนให้ Beneficiary ถาวร" (กรณีพิเศษ ไม่ใช่ normal disbursement)

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS beneficiary_transfer_ref VARCHAR(255);
    -- Gateway reference สำหรับกรณีโอนให้ Beneficiary ถาวร

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;
    -- เวลาที่คำร้องถูกปิด

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS closed_reason VARCHAR(50);
    -- 'incident_resolved'        → ปิดหลัง Mission Complete
    -- 'manual_close'             → Reporter/Admin ปิดเอง
    -- 'expired'                  → หมดเวลาตาม Time-Based Policy
    -- 'transferred_to_beneficiary' → เงินถูกโอนให้ Beneficiary แทน

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS is_paused BOOLEAN NOT NULL DEFAULT FALSE;
    -- TRUE = คำร้องถูกระงับ (Consensus ไม่ผ่าน / มี Responder โหวต Veto)

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS pause_reason TEXT;
    -- เหตุผลที่ถูกระงับ (ส่งให้ Reporter + แสดงใน Live Chat)

ALTER TABLE public.donation_requests
    ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ;
    -- เวลา Deadline ก่อนที่ระบบจะโอนเงินให้ Beneficiary อัตโนมัติ
    -- = เวลาที่ pause + donation_categories.pause_grace_period_hours

-- เพิ่ม Constraint บน escrow_status
ALTER TABLE public.donation_requests
    ADD CONSTRAINT escrow_status_valid CHECK (
        escrow_status IN ('not_started', 'in_escrow', 'released', 'returned')
    );

-- เพิ่ม Constraint บน closed_reason
ALTER TABLE public.donation_requests
    ADD CONSTRAINT closed_reason_valid CHECK (
        closed_reason IS NULL OR
        closed_reason IN (
            'incident_resolved', 'manual_close', 'expired', 'transferred_to_beneficiary'
        )
    );

-- Index สำหรับ query คำร้องที่ถูกระงับ (Escrow background job จะ query นี้บ่อย)
CREATE INDEX IF NOT EXISTS idx_donation_requests_paused
    ON public.donation_requests (is_paused, pause_deadline)
    WHERE is_paused = TRUE;

-- Index สำหรับ query escrow status
CREATE INDEX IF NOT EXISTS idx_donation_requests_escrow_status
    ON public.donation_requests (escrow_status);

-- =====================================================
-- PART 2: ขยาย donation_transactions.status
-- เพิ่มจาก 3 states เดิม (pending/confirmed/failed)
-- เป็น 13 states ของระบบ Escrow
-- =====================================================

-- ลบ CHECK constraint เดิมถ้ามี (ใน Supabase อาจไม่มี named constraint)
-- สร้าง status column ใหม่แบบ VARCHAR ที่ไม่มี ENUM limitation

-- เพิ่ม column ใหม่สำหรับ Escrow tracking ใน donation_transactions
ALTER TABLE public.donation_transactions
    ADD COLUMN IF NOT EXISTS escrow_batch_id VARCHAR(255);
    -- ID ของ batch ที่ transaction นี้ถูกรวมไปโอนเข้า Escrow (สำหรับ PromptPay batch)

ALTER TABLE public.donation_transactions
    ADD COLUMN IF NOT EXISTS escrow_submitted_at TIMESTAMPTZ;
    -- เวลาที่ส่ง transaction เข้า Escrow (เปลี่ยนสถานะเป็น 'in_escrow')

ALTER TABLE public.donation_transactions
    ADD COLUMN IF NOT EXISTS refund_reason TEXT;
    -- เหตุผลที่คืนเงิน (กรณี refund_pending/refunded)

ALTER TABLE public.donation_transactions
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    -- Timestamp สำหรับ tracking การเปลี่ยนแปลงสถานะ

-- อัปเดต status บน transaction ที่ยังเป็น 'failed' ขณะ pending ไม่ต้องทำ migration
-- แต่ต้องรองรับ 13 states ใหม่ผ่าน Comment (enforce ฝั่ง App Layer):

COMMENT ON COLUMN public.donation_transactions.status IS
'สถานะ 13 states ของระบบ Escrow:
  pending                      → รอผู้บริจาคชำระเงิน
  confirmed                    → ชำระสำเร็จ รอส่งเข้า Escrow
  in_escrow                    → เงินอยู่ที่ Beneficiary Escrow Account
  disbursed                    → Beneficiary โอนให้ Reporter สำเร็จ
  failed                       → การชำระเงินล้มเหลวตั้งแต่ต้น
  transfer_failed              → โอนเข้า Escrow ไม่สำเร็จ (retry ไม่ผ่าน)
  processing_transfer          → Lock ชั่วคราว ป้องกัน Race Condition
  transfer_blocked_no_beneficiary → ไม่มี beneficiary → ระงับ + แจ้ง Admin
  cancelled                    → ยกเลิกก่อนชำระ (pending → cancelled)
  refund_pending               → รอ Admin ดำเนินการคืนเงินด้วยตนเอง
  refunded                     → คืนเงินให้ผู้บริจาคสำเร็จแล้ว
  cancelled_refunded           → ยกเลิก + คืนเงินให้ผู้บริจาคแล้ว
  transferred_to_beneficiary   → เงินถูกเก็บไว้กับ Beneficiary ถาวร (ตามนโยบาย)';

-- Index สำหรับ background job ตรวจสอบ transactions ที่ค้างอยู่ใน escrow
CREATE INDEX IF NOT EXISTS idx_donation_transactions_status
    ON public.donation_transactions (status)
    WHERE status IN ('pending', 'confirmed', 'in_escrow', 'processing_transfer', 'refund_pending');

-- =====================================================
-- FUNCTION: DB Function อัปเดต escrow_status บน donation_requests
-- เรียกหลังจากมี transaction เปลี่ยนสถานะเป็น in_escrow
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_request_escrow_status(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_has_escrow BOOLEAN;
BEGIN
    -- ตรวจสอบว่ามี transaction ที่อยู่ใน escrow หรือ disbursed อยู่ไหม
    SELECT EXISTS(
        SELECT 1 FROM public.donation_transactions
        WHERE request_id = p_request_id
          AND status IN ('in_escrow', 'disbursed')
    ) INTO v_has_escrow;

    IF v_has_escrow THEN
        UPDATE public.donation_requests
        SET escrow_status = 'in_escrow',
            updated_at    = NOW()
        WHERE id = p_request_id
          AND escrow_status = 'not_started';
    END IF;
END;
$$;
