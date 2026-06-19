-- Fix: RPC functions were querying chat_messages.consultation_id which does not exist.
-- The correct column is room_id, stored in consultation_requests.room_id.

-- 1. Fix can_expert_finish_job
DROP FUNCTION IF EXISTS public.can_expert_finish_job(UUID, UUID);
CREATE OR REPLACE FUNCTION public.can_expert_finish_job(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_package_id TEXT;
  v_profession_id UUID;
  v_room_id TEXT;
  v_rules RECORD;
  v_missing JSONB := '[]'::JSONB;
  v_prescription_count INT;
  v_question_count INT;
  v_unanswered_count INT;
  v_has_video_call BOOLEAN;
  v_has_assessment BOOLEAN;
  v_general_message_count INT;
BEGIN
  -- ดึง package_id, room_id และ profession_id
  SELECT cp.package_id, cr.room_id INTO v_package_id, v_room_id
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
  
  -- เช็คคำถามบังคับ (ใช้ v_room_id แทน consultation_id ใน chat_messages)
  IF v_rules.min_required_questions > 0 THEN
    SELECT COUNT(*) INTO v_question_count
    FROM public.chat_messages
    WHERE room_id = v_room_id 
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
    WHERE room_id = v_room_id 
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
    WHERE room_id = v_room_id
      AND sender_id = p_provider_id
      AND (is_required = false OR is_required IS NULL);
    
    IF v_general_message_count < v_rules.min_general_messages THEN
      v_missing := v_missing || to_jsonb(
        'ต้องส่งข้อความขั้นต่ำ ' || v_rules.min_general_messages || ' ข้อ (ปัจจุบัน ' || v_general_message_count || ')'
      );
    END IF;
  END IF;
  
  -- เช็ค video call
  IF v_rules.requires_video_call THEN
    SELECT COALESCE(has_video_call, false) INTO v_has_video_call
    FROM public.consultation_room_experts
    WHERE consultation_id = p_consultation_id AND provider_id = p_provider_id;
    
    IF NOT v_has_video_call THEN
      v_missing := v_missing || to_jsonb('ต้องทำ Video Call');
    END IF;
  END IF;
  
  -- เช็ค health assessment
  IF v_rules.requires_health_assessment THEN
    SELECT COALESCE(has_assessment, false) INTO v_has_assessment
    FROM public.consultation_room_experts
    WHERE consultation_id = p_consultation_id AND provider_id = p_provider_id;
    
    IF NOT v_has_assessment THEN
      v_missing := v_missing || to_jsonb('ต้องทำ Health Assessment');
    END IF;
  END IF;
  
  RETURN json_build_object(
    'can_finish', jsonb_array_length(v_missing) = 0,
    'missing_requirements', v_missing
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Fix get_expert_completion_status
DROP FUNCTION IF EXISTS public.get_expert_completion_status(UUID, UUID);
CREATE OR REPLACE FUNCTION public.get_expert_completion_status(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_package_id TEXT;
  v_profession_id UUID;
  v_room_id TEXT;
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
  -- ดึง package_id, room_id และ profession_id
  SELECT cr.package_id, cr.room_id INTO v_package_id, v_room_id
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
  
  -- นับคำถามบังคับ (ใช้ room_id แทน consultation_id ใน chat_messages)
  SELECT COUNT(*) INTO v_question_count
  FROM public.chat_messages
  WHERE room_id = v_room_id 
    AND is_required = true 
    AND required_owner_id = p_provider_id;
  
  SELECT COUNT(*) INTO v_answered_count
  FROM public.chat_messages
  WHERE room_id = v_room_id 
    AND is_required = true 
    AND required_owner_id = p_provider_id
    AND required_status = 'answered';
  
  SELECT COUNT(*) INTO v_unanswered_count
  FROM public.chat_messages
  WHERE room_id = v_room_id 
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
  WHERE room_id = v_room_id
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
