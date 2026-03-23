-- ====================================================
-- แทนที่ can_approve_donation (boolean เดียว)
-- ด้วย approver_profession_ids (array ของกลุ่มอาชีพที่ต้องอนุมัติ)
-- ====================================================

-- เพิ่มคอลัมน์ใหม่
ALTER TABLE public.donation_categories
  ADD COLUMN IF NOT EXISTS approver_profession_ids TEXT[] DEFAULT '{}';

-- สร้างตาราง donation_request_approvals สำหรับบันทึกการอนุมัติรายกลุ่มอาชีพ
CREATE TABLE IF NOT EXISTS public.donation_request_approvals (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  request_id    UUID NOT NULL REFERENCES public.donation_requests(id) ON DELETE CASCADE,
  profession_id UUID NOT NULL REFERENCES public.professions(id),
  approved_by   UUID NOT NULL REFERENCES public.users(id),
  status        TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('approved', 'rejected')),
  note          TEXT,
  approved_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(request_id, profession_id)
);

-- Index เพื่อ query เร็ว
CREATE INDEX IF NOT EXISTS idx_dra_request_id     ON public.donation_request_approvals(request_id);
CREATE INDEX IF NOT EXISTS idx_dra_profession_id  ON public.donation_request_approvals(profession_id);
CREATE INDEX IF NOT EXISTS idx_dra_approved_by    ON public.donation_request_approvals(approved_by);
