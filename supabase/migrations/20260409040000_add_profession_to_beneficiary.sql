-- =====================================================
-- Migration: Add profession_id to beneficiary_organizations
-- Date: 2026-04-09
-- Purpose: ลิงก์ Beneficiary (Escrow Account) เข้ากับกลุ่มผู้อนุมัติ (Profession)
-- เพื่อให้สามารถจำกัดการเลือก Escrow ได้ตาม Flow การอนุมัติของหมวดหมู่
-- =====================================================

ALTER TABLE public.beneficiary_organizations
    ADD COLUMN IF NOT EXISTS profession_id UUID REFERENCES public.professions(id) ON DELETE SET NULL;
