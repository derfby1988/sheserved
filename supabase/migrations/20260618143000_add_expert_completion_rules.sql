-- =====================================================
-- Migration: Add Expert Completion Rules (Phase 6.8)
-- วันที่: 2026-06-18
-- =====================================================

-- 1. เพิ่ม fields กำหนดกรอบของ package ลงใน consultation_packages
ALTER TABLE public.consultation_packages
ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS requires_prescription_approval BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS min_required_questions INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS requires_all_questions_answered BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS requires_video_call BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS requires_health_assessment BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS min_general_messages INT DEFAULT 0;

-- 2. สร้างตาราง profession_package_rules ผูก profession + package กับกฎโดยละเอียด
CREATE TABLE IF NOT EXISTS public.profession_package_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id TEXT NOT NULL REFERENCES public.consultation_packages(id) ON DELETE CASCADE,
  profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  
  -- กฎเกี่ยวกับใบสั่งยา
  can_prescribe BOOLEAN DEFAULT false,
  must_prescribe BOOLEAN DEFAULT false,
  requires_prescription_approval BOOLEAN DEFAULT false,
  min_prescription_items INT DEFAULT 0,
  
  -- กฎเกี่ยวกับคำถามบังคับ
  can_set_required_questions BOOLEAN DEFAULT true,
  min_required_questions INT DEFAULT 0,
  must_answer_all_questions BOOLEAN DEFAULT false,
  
  -- กฎเกี่ยวกับ video call
  requires_video_call BOOLEAN DEFAULT false,
  
  -- กฎเกี่ยวกับ health assessment
  requires_health_assessment BOOLEAN DEFAULT false,
  
  -- กฎเกี่ยวกับการร่วมสนทนาทั่วไป
  min_general_messages INT DEFAULT 0,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(package_id, profession_id)
);

-- Index สำหรับการ query
CREATE INDEX IF NOT EXISTS idx_ppr_package ON public.profession_package_rules(package_id);
CREATE INDEX IF NOT EXISTS idx_ppr_profession ON public.profession_package_rules(profession_id);

-- Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION update_profession_package_rules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_profession_package_rules_updated_at ON public.profession_package_rules;
CREATE TRIGGER trg_profession_package_rules_updated_at
  BEFORE UPDATE ON public.profession_package_rules
  FOR EACH ROW EXECUTE FUNCTION update_profession_package_rules_updated_at();

-- Enable Row Level Security
ALTER TABLE public.profession_package_rules ENABLE ROW LEVEL SECURITY;

-- Policy: ทุกคนอ่านได้
DROP POLICY IF EXISTS "Public read profession_package_rules" ON public.profession_package_rules;
CREATE POLICY "Public read profession_package_rules"
ON public.profession_package_rules FOR SELECT
TO authenticated
USING (true);

-- Policy: Admin จัดการได้
DROP POLICY IF EXISTS "Service role manage profession_package_rules" ON public.profession_package_rules;
CREATE POLICY "Service role manage profession_package_rules"
ON public.profession_package_rules FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Policy: ทั้ง Authenticated จัดการได้ (สำหรับช่วงพัฒนา)
DROP POLICY IF EXISTS "Manage profession_package_rules for all" ON public.profession_package_rules;
CREATE POLICY "Manage profession_package_rules for all"
ON public.profession_package_rules FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- 3. เพิ่ม fields ใน consultation_room_experts (ถ้าจำเป็น)
ALTER TABLE public.consultation_room_experts
ADD COLUMN IF NOT EXISTS has_video_call BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS has_assessment BOOLEAN DEFAULT false;

-- 4. RPC Function: ดึง rules ของ profession ใน package
DROP FUNCTION IF EXISTS public.get_profession_package_rules(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.get_profession_package_rules(
  p_package_id TEXT,
  p_profession_id UUID
)
RETURNS TABLE (
  id UUID,
  package_id TEXT,
  profession_id UUID,
  can_prescribe BOOLEAN,
  must_prescribe BOOLEAN,
  requires_prescription_approval BOOLEAN,
  min_prescription_items INT,
  can_set_required_questions BOOLEAN,
  min_required_questions INT,
  must_answer_all_questions BOOLEAN,
  requires_video_call BOOLEAN,
  requires_health_assessment BOOLEAN,
  min_general_messages INT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ppr.id,
    ppr.package_id,
    ppr.profession_id,
    ppr.can_prescribe,
    ppr.must_prescribe,
    ppr.requires_prescription_approval,
    ppr.min_prescription_items,
    ppr.can_set_required_questions,
    ppr.min_required_questions,
    ppr.must_answer_all_questions,
    ppr.requires_video_call,
    ppr.requires_health_assessment,
    ppr.min_general_messages,
    ppr.created_at,
    ppr.updated_at
  FROM public.profession_package_rules ppr
  WHERE ppr.package_id = p_package_id AND ppr.profession_id = p_profession_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC Function: ตรวจสอบว่า expert สามารถจบงานได้หรือไม่
DROP FUNCTION IF EXISTS public.can_expert_finish_job(UUID, UUID);
CREATE OR REPLACE FUNCTION public.can_expert_finish_job(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_package_id TEXT;
  v_profession_id UUID;
  v_rules RECORD;
  v_missing JSONB := '[]'::JSONB;
  v_prescription_count INT;
  v_question_count INT;
  v_unanswered_count INT;
  v_has_video_call BOOLEAN;
  v_has_assessment BOOLEAN;
  v_general_message_count INT;
BEGIN
  -- ดึง package_id และ profession_id
  SELECT cp.package_id INTO v_package_id
  FROM public.consultation_requests cr
  JOIN public.consultation_packages cp ON cr.package_id = cp.id
  WHERE cr.id = p_consultation_id;
  
  SELECT u.profession_id INTO v_profession_id
  FROM public.users u
  WHERE u.id = p_provider_id;
  
  -- ถ้าไม่พบ package หรือ profession = ไม่มีข้อบังคับ
  IF v_package_id IS NULL OR v_profession_id IS NULL THEN
    RETURN json_build_object('can_finish', true, 'missing_requirements', '[]'::JSONB);
  END IF;
  
  -- ดึง rules
  SELECT * INTO v_rules
  FROM public.get_profession_package_rules(v_package_id, v_profession_id);
  
  -- ถ้าไม่มี rules = ไม่มีข้อบังคับ
  IF NOT FOUND THEN
    RETURN json_build_object('can_finish', true, 'missing_requirements', '[]'::JSONB);
  END IF;
  
  -- เช็คใบสั่งยา
  IF v_rules.must_prescribe THEN
    SELECT COUNT(*) INTO v_prescription_count
    FROM public.prescriptions
    WHERE consultation_id = p_consultation_id AND provider_id = p_provider_id;
    
    IF v_prescription_count = 0 THEN
      v_missing := v_missing || to_jsonb('ต้องออกใบสั่งยา');
    ELSIF v_rules.min_prescription_items > 0 AND v_prescription_count < v_rules.min_prescription_items THEN
      v_missing := v_missing || to_jsonb(
        'ต้องออกยาขั้นต่ำ ' || v_rules.min_prescription_items || ' รายการ (ปัจจุบัน ' || v_prescription_count || ')'
      );
    END IF;
    
    IF v_rules.requires_prescription_approval THEN
      SELECT COUNT(*) INTO v_prescription_count
      FROM public.prescriptions
      WHERE consultation_id = p_consultation_id 
        AND provider_id = p_provider_id 
        AND is_approved = true;
      
      IF v_prescription_count = 0 THEN
        v_missing := v_missing || to_jsonb('ใบสั่งยาต้องได้รับการอนุมัติ');
      END IF;
    END IF;
  END IF;
  
  -- เช็คคำถามบังคับ
  IF v_rules.min_required_questions > 0 THEN
    SELECT COUNT(*) INTO v_question_count
    FROM public.chat_messages
    WHERE consultation_id = p_consultation_id 
      AND is_required = true 
      AND required_owner_id = p_provider_id;
    
    IF v_question_count < v_rules.min_required_questions THEN
      v_missing := v_missing || to_jsonb(
        'ต้องตั้งคำถามบังคับขั้นต่ำ ' || v_rules.min_required_questions || ' ข้อ (ปัจจุบัน ' || v_question_count || ')'
      );
    END IF;
  END IF;
  
  IF v_rules.must_answer_all_questions THEN
    SELECT COUNT(*) INTO v_unanswered_count
    FROM public.chat_messages
    WHERE consultation_id = p_consultation_id 
      AND is_required = true 
      AND required_status != 'answered';
    
    IF v_unanswered_count > 0 THEN
      v_missing := v_missing || to_jsonb(
        'มีคำถามบังคับที่ยังไม่ได้ตอบ ' || v_unanswered_count || ' ข้อ'
      );
    END IF;
  END IF;
  
  -- เช็คการร่วมสนทนาทั่วไป
  IF v_rules.min_general_messages > 0 THEN
    SELECT COUNT(*) INTO v_general_message_count
    FROM public.chat_messages
    WHERE consultation_id = p_consultation_id
      AND sender_id = p_provider_id
      AND (is_required = false OR is_required IS NULL);
    
    IF v_general_message_count < v_rules.min_general_messages THEN
      v_missing := v_missing || to_jsonb(
        'ต้องร่วมสนทนาทั่วไปขั้นต่ำ ' || v_rules.min_general_messages || ' ข้อความ (ปัจจุบัน ' || v_general_message_count || ')'
      );
    END IF;
  END IF;
  
  -- เช็ค video call
  IF v_rules.requires_video_call THEN
    SELECT COALESCE(bool_or(has_video_call), false) INTO v_has_video_call
    FROM public.consultation_room_experts
    WHERE consultation_id = p_consultation_id AND provider_id = p_provider_id;
    
    IF NOT v_has_video_call THEN
      v_missing := v_missing || to_jsonb('ต้องทำ video call');
    END IF;
  END IF;
  
  -- เช็ค health assessment
  IF v_rules.requires_health_assessment THEN
    SELECT COALESCE(bool_or(has_assessment), false) INTO v_has_assessment
    FROM public.consultation_room_experts
    WHERE consultation_id = p_consultation_id AND provider_id = p_provider_id;
    
    IF NOT v_has_assessment THEN
      v_missing := v_missing || to_jsonb('ต้องทำ health assessment');
    END IF;
  END IF;
  
  RETURN json_build_object(
    'can_finish', jsonb_array_length(v_missing) = 0,
    'missing_requirements', v_missing
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC Function: ดึงสถานะการทำงานของ expert
DROP FUNCTION IF EXISTS public.get_expert_completion_status(UUID, UUID);
CREATE OR REPLACE FUNCTION public.get_expert_completion_status(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_package_id TEXT;
  v_profession_id UUID;
  v_rules RECORD;
  v_result JSONB := '{}'::JSONB;
  v_prescription_count INT := 0;
  v_approved_count INT := 0;
  v_question_count INT := 0;
  v_answered_count INT := 0;
  v_unanswered_count INT := 0;
  v_has_video_call BOOLEAN := false;
  v_has_assessment BOOLEAN := false;
  v_general_message_count INT := 0;
  v_progress INT := 0;
  v_total INT := 0;
BEGIN
  -- ดึง package_id และ profession_id
  SELECT cr.package_id INTO v_package_id
  FROM public.consultation_requests cr
  WHERE cr.id = p_consultation_id;
  
  SELECT u.profession_id INTO v_profession_id
  FROM public.users u
  WHERE u.id = p_provider_id;
  
  -- ถ้าไม่พบ package หรือ profession
  IF v_package_id IS NULL OR v_profession_id IS NULL THEN
    RETURN json_build_object(
      'can_finish', true,
      'progress', 100,
      'items', '[]'::JSONB
    );
  END IF;
  
  -- ดึง rules
  SELECT * INTO v_rules
  FROM public.get_profession_package_rules(v_package_id, v_profession_id);
  
  -- ถ้าไม่มี rules
  IF NOT FOUND THEN
    RETURN json_build_object(
      'can_finish', true,
      'progress', 100,
      'items', '[]'::JSONB
    );
  END IF;
  
  -- นับ prescriptions
  SELECT COUNT(*) INTO v_prescription_count
  FROM public.prescriptions
  WHERE consultation_id = p_consultation_id AND provider_id = p_provider_id;
  
  SELECT COUNT(*) INTO v_approved_count
  FROM public.prescriptions
  WHERE consultation_id = p_consultation_id 
    AND provider_id = p_provider_id 
    AND is_approved = true;
  
  -- นับคำถามบังคับ
  SELECT COUNT(*) INTO v_question_count
  FROM public.chat_messages
  WHERE consultation_id = p_consultation_id 
    AND is_required = true 
    AND required_owner_id = p_provider_id;
  
  SELECT COUNT(*) INTO v_answered_count
  FROM public.chat_messages
  WHERE consultation_id = p_consultation_id 
    AND is_required = true 
    AND required_owner_id = p_provider_id
    AND required_status = 'answered';
  
  SELECT COUNT(*) INTO v_unanswered_count
  FROM public.chat_messages
  WHERE consultation_id = p_consultation_id 
    AND is_required = true 
    AND required_status != 'answered';
  
  -- ตรวจสอบ video call และ assessment
  SELECT COALESCE(has_video_call, false), COALESCE(has_assessment, false)
  INTO v_has_video_call, v_has_assessment
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id AND provider_id = p_provider_id;
  
  -- นับข้อความสนทนาทั่วไปของ expert
  SELECT COUNT(*) INTO v_general_message_count
  FROM public.chat_messages
  WHERE consultation_id = p_consultation_id
    AND sender_id = p_provider_id
    AND (is_required = false OR is_required IS NULL);
  
  -- คำนวณ progress
  v_total := 0;
  IF v_rules.must_prescribe THEN v_total := v_total + 1; END IF;
  IF v_rules.min_required_questions > 0 THEN v_total := v_total + 1; END IF;
  IF v_rules.must_answer_all_questions THEN v_total := v_total + 1; END IF;
  IF v_rules.requires_video_call THEN v_total := v_total + 1; END IF;
  IF v_rules.requires_health_assessment THEN v_total := v_total + 1; END IF;
  IF v_rules.min_general_messages > 0 THEN v_total := v_total + 1; END IF;
  
  IF v_rules.must_prescribe AND v_prescription_count > 0 THEN
    v_progress := v_progress + 1;
  END IF;
  IF v_rules.min_required_questions > 0 AND v_question_count >= v_rules.min_required_questions THEN
    v_progress := v_progress + 1;
  END IF;
  IF v_rules.must_answer_all_questions AND v_unanswered_count = 0 THEN
    v_progress := v_progress + 1;
  END IF;
  IF v_rules.requires_video_call AND v_has_video_call THEN
    v_progress := v_progress + 1;
  END IF;
  IF v_rules.requires_health_assessment AND v_has_assessment THEN
    v_progress := v_progress + 1;
  END IF;
  IF v_rules.min_general_messages > 0 AND v_general_message_count >= v_rules.min_general_messages THEN
    v_progress := v_progress + 1;
  END IF;
  
  RETURN json_build_object(
    'can_finish', 
      (NOT v_rules.must_prescribe OR v_prescription_count > 0) AND
      (v_rules.min_required_questions = 0 OR v_question_count >= v_rules.min_required_questions) AND
      (NOT v_rules.must_answer_all_questions OR v_unanswered_count = 0) AND
      (NOT v_rules.requires_video_call OR v_has_video_call) AND
      (NOT v_rules.requires_health_assessment OR v_has_assessment) AND
      (v_rules.min_general_messages = 0 OR v_general_message_count >= v_rules.min_general_messages),
    'progress', CASE WHEN v_total = 0 THEN 100 ELSE (v_progress * 100 / v_total) END,
    'prescription_count', v_prescription_count,
    'approved_count', v_approved_count,
    'question_count', v_question_count,
    'answered_count', v_answered_count,
    'unanswered_count', v_unanswered_count,
    'has_video_call', v_has_video_call,
    'has_assessment', v_has_assessment,
    'general_message_count', v_general_message_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

NOTIFY pgrst, 'reload schema';
