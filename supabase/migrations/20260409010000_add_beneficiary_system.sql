-- =====================================================
-- Migration: Add Beneficiary System
-- Date: 2026-04-09
-- Purpose: สร้างระบบผู้รับมรดก (Beneficiary Organization) สำหรับ Escrow Architecture
--          เงินบริจาคทุกบาทจะพักที่ Beneficiary Account (บุคคลที่สาม) แทนที่จะผ่าน Sheserved
--          จนกว่าภารกิจจะสมบูรณ์ (Mission Complete + Consensus)
-- Depends on: 20260227200000_donation_system.sql
-- =====================================================

-- =====================================================
-- TABLE: beneficiary_organizations
-- หน่วยงานที่ทำหน้าที่เป็น Escrow Account
-- ต้องเป็นนิติบุคคลที่จดทะเบียนถูกกฎหมาย (มูลนิธิ/สมาคม/บริษัท)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.beneficiary_organizations (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(255) NOT NULL,
    registration_no     VARCHAR(100),                   -- เลขทะเบียนนิติบุคคล (ต้องใส่เพื่อ verify)
    bank_name           VARCHAR(100),                   -- ชื่อธนาคาร
    bank_account        VARCHAR(50),                    -- เลขบัญชี (ควร encrypt at-rest)
    bank_account_name   VARCHAR(255),                   -- ชื่อบัญชีธนาคาร
    contact_email       VARCHAR(255),                   -- อีเมลผู้ประสานงาน
    omise_recipient_id  VARCHAR(255),                   -- Omise Recipient ID (สำหรับ auto-transfer Production)
    promptpay_id        VARCHAR(50),                    -- PromptPay ID (สำหรับ batch transfer)
    is_verified         BOOLEAN     NOT NULL DEFAULT FALSE,  -- ผ่านการตรวจสอบบัญชีธนาคารและเอกสารแล้ว
    is_active           BOOLEAN     NOT NULL DEFAULT FALSE,  -- เปิดใช้ได้เฉพาะเมื่อ is_verified = TRUE
    is_global_default   BOOLEAN     NOT NULL DEFAULT FALSE,  -- ใช้เป็น Global Fallback ถ้า category ไม่มี beneficiary
    has_mou             BOOLEAN     NOT NULL DEFAULT FALSE,  -- มี MOU/ข้อตกลงกับ Sheserved แล้ว
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ป้องกัน: is_active = TRUE ได้เฉพาะเมื่อ is_verified = TRUE
    CONSTRAINT active_requires_verified CHECK (NOT is_active OR is_verified)
);

-- Index ช่วยค้นหา active beneficiaries เร็วขึ้น
CREATE INDEX IF NOT EXISTS idx_beneficiary_orgs_active
    ON public.beneficiary_organizations (is_active);

-- Index สำหรับ Global Default lookup
CREATE INDEX IF NOT EXISTS idx_beneficiary_orgs_global_default
    ON public.beneficiary_organizations (is_global_default)
    WHERE is_global_default = TRUE;

-- =====================================================
-- TABLE: beneficiary_audit_logs
-- บันทึกทุก INSERT/UPDATE ของ beneficiary_organizations
-- ป้องกัน Risk #1: ข้อมูลบัญชีถูกแก้ไขโดยไม่ได้รับอนุญาต
-- เฉพาะ Super Admin เท่านั้นที่แก้ไขได้ (enforce ฝั่ง App)
-- =====================================================
CREATE TABLE IF NOT EXISTS public.beneficiary_audit_logs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id      UUID        NOT NULL REFERENCES public.beneficiary_organizations(id) ON DELETE CASCADE,
    changed_by  UUID        NOT NULL,   -- user_id ของ Super Admin ที่ดำเนินการ (จาก ServiceLocator)
    action      VARCHAR(20) NOT NULL,   -- 'INSERT' | 'UPDATE' | 'DEACTIVATE' | 'VERIFY'
    old_data    JSONB,                  -- ค่าก่อนแก้ไข (NULL ถ้าเป็น INSERT)
    new_data    JSONB,                  -- ค่าหลังแก้ไข
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT audit_action_valid CHECK (action IN ('INSERT', 'UPDATE', 'DEACTIVATE', 'VERIFY'))
);

-- Index สำหรับ lookup audit trail ต่อ org
CREATE INDEX IF NOT EXISTS idx_beneficiary_audit_org_id
    ON public.beneficiary_audit_logs (org_id, changed_at DESC);

-- =====================================================
-- TABLE: beneficiary_transfer_logs
-- บันทึกทุกครั้งที่เงินถูกโอนหาผู้รับมรดกแบบถาวร
-- (กรณีพิเศษ: pause_deadline / transfer_failed / cancellation)
-- กรณีปกติ (mission complete) ใช้ donation_disbursement_logs แทน
-- =====================================================
CREATE TABLE IF NOT EXISTS public.beneficiary_transfer_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id      UUID        NOT NULL REFERENCES public.donation_requests(id) ON DELETE CASCADE,
    beneficiary_id  UUID        NOT NULL REFERENCES public.beneficiary_organizations(id),
    amount          DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    reason          VARCHAR(50) NOT NULL,
    -- 'pause_deadline'    → คำร้องถูกระงับจนหมดเวลา (pause_grace_period_hours ล่วงเลย)
    -- 'transfer_failed'   → โอนให้ Reporter ไม่สำเร็จ เกิน transfer_failure_grace_hours
    -- 'cancellation'      → Reporter ยกเลิกคำร้อง / ผู้บริจาคเลือกไม่รับเงินคืน
    transfer_ref    VARCHAR(255),       -- reference จาก Payment Gateway (NULL ในกรณี Dev/Mock)
    transferred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    note            TEXT,               -- หมายเหตุเพิ่มเติม (เช่น เหตุผลจาก Admin)

    CONSTRAINT transfer_reason_valid CHECK (reason IN ('pause_deadline', 'transfer_failed', 'cancellation'))
);

-- Index สำหรับ query ตาม request_id
CREATE INDEX IF NOT EXISTS idx_beneficiary_transfer_request_id
    ON public.beneficiary_transfer_logs (request_id);

-- Index สำหรับ statistics ต่อ beneficiary
CREATE INDEX IF NOT EXISTS idx_beneficiary_transfer_beneficiary_id
    ON public.beneficiary_transfer_logs (beneficiary_id, transferred_at DESC);

-- =====================================================
-- RLS Policies
-- หมายเหตุ: Sheserved ไม่ใช้ Supabase Auth โดยตรง (auth.uid() = null เสมอ)
--           Auth Logic ใช้ ServiceLocator + AuthService ฝั่ง Flutter เท่านั้น
--           RLS ที่นี่เปิดกว้างไว้ก่อน และ enforce สิทธิ์ใน App Layer
-- =====================================================

ALTER TABLE public.beneficiary_organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beneficiary_audit_logs    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beneficiary_transfer_logs ENABLE ROW LEVEL SECURITY;

-- beneficiary_organizations: ทุกคนอ่านได้ (เพื่อแสดงชื่อ Escrow Account ให้ผู้บริจาคเห็น)
CREATE POLICY "beneficiary_orgs_select_all"
    ON public.beneficiary_organizations FOR SELECT USING (true);

-- INSERT/UPDATE/DELETE: เฉพาะ Super Admin (enforce ฝั่ง App ผ่าน BeneficiaryRepository)
-- RLS เปิดกว้างเพราะ auth.uid() = NULL ตลอด — App Layer ตรวจสิทธิ์เอง
CREATE POLICY "beneficiary_orgs_insert_super_admin"
    ON public.beneficiary_organizations FOR INSERT WITH CHECK (true);

CREATE POLICY "beneficiary_orgs_update_super_admin"
    ON public.beneficiary_organizations FOR UPDATE USING (true);

CREATE POLICY "beneficiary_orgs_delete_super_admin"
    ON public.beneficiary_organizations FOR DELETE USING (true);

-- beneficiary_audit_logs: ทุกคนอ่านได้ (Transparency), เฉพาะ System INSERT
CREATE POLICY "beneficiary_audit_select_all"
    ON public.beneficiary_audit_logs FOR SELECT USING (true);

CREATE POLICY "beneficiary_audit_insert_all"
    ON public.beneficiary_audit_logs FOR INSERT WITH CHECK (true);

-- beneficiary_transfer_logs: ทุกคนอ่านได้ (Transparency/Accountability)
CREATE POLICY "beneficiary_transfer_select_all"
    ON public.beneficiary_transfer_logs FOR SELECT USING (true);

CREATE POLICY "beneficiary_transfer_insert_all"
    ON public.beneficiary_transfer_logs FOR INSERT WITH CHECK (true);
