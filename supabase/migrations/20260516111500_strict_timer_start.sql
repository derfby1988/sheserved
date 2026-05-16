-- Update: Start session timer only when ALL REQUIRED experts have joined
CREATE OR REPLACE FUNCTION public.assign_provider_to_group(
  p_consultation_id UUID,
  p_provider_id UUID,
  p_expert_group_id TEXT
) RETURNS JSONB AS $$
DECLARE
  v_expert_record RECORD;
  v_current_count INT;
  v_remaining_required INT;
  v_room_id TEXT;
BEGIN
  -- 1. ค้นหาข้อมูล expert group ในคำปรึกษานี้
  SELECT * INTO v_expert_record 
  FROM public.consultation_room_experts 
  WHERE consultation_id = p_consultation_id AND expert_group_id = p_expert_group_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'ไม่พบกลุ่มผู้เชี่ยวชาญนี้ในแพ็คเกจ');
  END IF;

  -- 2. นับจำนวนคนที่รับงานไปแล้วในกลุ่มนี้
  SELECT COUNT(*) INTO v_current_count
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id 
    AND expert_group_id = p_expert_group_id 
    AND status = 'joined'
    AND provider_id IS NOT NULL;

  IF v_current_count >= v_expert_record.max_experts THEN
    RETURN jsonb_build_object('success', false, 'message', 'โควต้ากลุ่มนี้เต็มแล้ว');
  END IF;

  -- 3. เพิ่ม provider เข้าไป
  IF v_expert_record.provider_id IS NULL THEN
    UPDATE public.consultation_room_experts
    SET provider_id = p_provider_id,
        status = 'joined',
        joined_at = now()
    WHERE id = v_expert_record.id;
  ELSE
    INSERT INTO public.consultation_room_experts (
      consultation_id, room_id, expert_group_id, expert_group_name, expert_group_role,
      max_experts, is_required, provider_id, status, joined_at
    ) VALUES (
      p_consultation_id, v_expert_record.room_id, p_expert_group_id, v_expert_record.expert_group_name, v_expert_record.expert_group_role,
      v_expert_record.max_experts, v_expert_record.is_required, p_provider_id, 'joined', now()
    );
  END IF;

  -- 4. ตรวจสอบว่ากลุ่มที่ "จำเป็น" (Required) ครบหรือยัง
  SELECT COUNT(*) INTO v_remaining_required
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id 
    AND is_required = true 
    AND (status = 'waiting' OR provider_id IS NULL);

  -- 5. ดึง room_id และตรวจสอบเริ่มเซสชั่น
  SELECT room_id INTO v_room_id FROM public.consultation_requests WHERE id = p_consultation_id;
  
  IF v_room_id IS NOT NULL THEN
    -- เพิ่มหมอเป็น member ของห้อง (ทำทันทีที่เข้า ไม่ต้องรอครบ)
    INSERT INTO public.chat_room_members (room_id, user_id, role)
    VALUES (v_room_id, p_provider_id, 'doctor')
    ON CONFLICT DO NOTHING;

    -- เริ่มเซสชั่น (Timer) เฉพาะเมื่อ Required Experts ครบแล้ว
    IF v_remaining_required = 0 THEN
      UPDATE public.chat_rooms
      SET started_at = COALESCE(started_at, now()),
          updated_at = now()
      WHERE id = v_room_id;
      
      UPDATE public.consultation_requests
      SET status = 'in_progress',
          updated_at = now()
      WHERE id = p_consultation_id;
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'เข้าร่วมสำเร็จ');
END;
$$ LANGUAGE plpgsql;
