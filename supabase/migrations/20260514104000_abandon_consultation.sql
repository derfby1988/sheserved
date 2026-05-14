-- Migration: Abandon Consultation Request
-- Description: Allows a provider to abandon a consultation request and gives the quota back.

CREATE OR REPLACE FUNCTION public.abandon_provider_from_group(
  p_consultation_id UUID,
  p_provider_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_expert_record RECORD;
  v_room_id TEXT;
  v_count INT;
BEGIN
  -- หา record ที่ provider รับงานไป
  SELECT * INTO v_expert_record 
  FROM public.consultation_room_experts 
  WHERE consultation_id = p_consultation_id 
    AND provider_id = p_provider_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'ไม่พบการรับงานของท่านในคำปรึกษานี้');
  END IF;

  -- หาจำนวน slot ทั้งหมดของกลุ่มนี้ใน consultation นี้
  SELECT COUNT(*) INTO v_count
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id
    AND expert_group_id = v_expert_record.expert_group_id;

  IF v_count = 1 THEN
    -- ถ้ามี slot เดียว ให้เคลียร์ provider_id กลับไปเป็น waiting
    UPDATE public.consultation_room_experts
    SET provider_id = NULL,
        status = 'waiting',
        joined_at = NULL
    WHERE id = v_expert_record.id;
  ELSE
    -- ถ้ามีหลาย slot (เกินมาจาก max_experts หรือเป็นการเพิ่ม slot) ให้ลบทิ้งได้เลย
    DELETE FROM public.consultation_room_experts
    WHERE id = v_expert_record.id;
  END IF;

  -- ดึง room_id ออกมา
  SELECT room_id INTO v_room_id FROM public.consultation_requests WHERE id = p_consultation_id;
  
  IF v_room_id IS NOT NULL THEN
    -- นำแพทย์ออกจาก chat_room_members
    DELETE FROM public.chat_room_members
    WHERE room_id = v_room_id AND user_id = p_provider_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'สละสิทธิ์สำเร็จ');
END;
$$ LANGUAGE plpgsql;
