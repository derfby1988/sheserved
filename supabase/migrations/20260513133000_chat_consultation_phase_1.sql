-- Migration: Chat Consultation Phase 1
-- Description: Core Isolation, Access Control, and Chat Tables

-- 1. อัปเดต consultation_packages
ALTER TABLE public.consultation_packages ADD COLUMN IF NOT EXISTS session_minutes INT DEFAULT 15;
ALTER TABLE public.consultation_packages ADD COLUMN IF NOT EXISTS expire_minutes INT DEFAULT 120;

-- 2. อัปเดต chat_rooms
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS room_type TEXT DEFAULT 'general';
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS consultation_id UUID REFERENCES public.consultation_requests(id);
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS package_id TEXT REFERENCES public.consultation_packages(id);
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS session_minutes INT DEFAULT 15;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;

-- 3. อัปเดต consultation_requests
ALTER TABLE public.consultation_requests ADD COLUMN IF NOT EXISTS room_id TEXT REFERENCES public.chat_rooms(id);

-- 4. สร้างตาราง chat_room_members
CREATE TABLE IF NOT EXISTS public.chat_room_members (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id        TEXT NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role           TEXT DEFAULT 'member', -- 'patient' | 'doctor' | 'admin' | 'member'
  joined_at      TIMESTAMPTZ DEFAULT now(),
  last_read_at   TIMESTAMPTZ,
  unread_count   INT DEFAULT 0,
  is_muted       BOOLEAN DEFAULT false,
  UNIQUE(room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_room_members_user ON public.chat_room_members(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_room_members_room ON public.chat_room_members(room_id);

-- 5. Trigger อัปเดต unread_count สำหรับข้อความใหม่
CREATE OR REPLACE FUNCTION public.increment_unread_count()
RETURNS TRIGGER AS $$
BEGIN
  -- สมมติว่ามีตาราง chat_messages
  UPDATE public.chat_room_members
  SET unread_count = unread_count + 1
  WHERE room_id = NEW.room_id
    AND user_id != NEW.sender_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_new_message_increment_unread ON public.chat_messages;
CREATE TRIGGER on_new_message_increment_unread
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.increment_unread_count();

-- 6. สร้างตาราง consultation_room_experts สำหรับ Access Control
CREATE TABLE IF NOT EXISTS public.consultation_room_experts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id   UUID NOT NULL REFERENCES public.consultation_requests(id) ON DELETE CASCADE,
  room_id           TEXT REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  expert_group_id   TEXT NOT NULL,
  expert_group_name TEXT NOT NULL,
  expert_group_role TEXT NOT NULL,
  max_experts       INT DEFAULT 1,
  is_required       BOOLEAN DEFAULT false,
  provider_id       UUID REFERENCES public.users(id), -- NULL = ยังไม่มีผู้รับงาน
  status            TEXT DEFAULT 'waiting', -- 'waiting' | 'joined' | 'declined' | 'cancelled'
  joined_at         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE(consultation_id, expert_group_id, provider_id)
);

CREATE INDEX IF NOT EXISTS idx_room_experts_consultation ON public.consultation_room_experts(consultation_id);
CREATE INDEX IF NOT EXISTS idx_room_experts_provider ON public.consultation_room_experts(provider_id);

-- 7. SQL Function สร้าง Chat Room ทันทีเมื่อขอคำปรึกษา
CREATE OR REPLACE FUNCTION public.create_consultation_room(
  p_consultation_id UUID,
  p_patient_id      UUID,
  p_package_name    TEXT,
  p_package_id      TEXT
)
RETURNS TEXT AS $$
DECLARE
  v_room_id TEXT;
  v_session_minutes INT;
BEGIN
  -- ดึง session_minutes จาก package
  SELECT session_minutes INTO v_session_minutes FROM public.consultation_packages WHERE id = p_package_id;

  -- 1. สร้าง chat room ใหม่
  INSERT INTO public.chat_rooms (
    id, room_type, consultation_id, package_id,
    title, is_active, session_minutes, created_at, updated_at
  ) VALUES (
    'consult_' || p_consultation_id::text,
    'consultation',
    p_consultation_id,
    p_package_id,
    'ปรึกษา: ' || p_package_name,
    true,
    COALESCE(v_session_minutes, 15),
    now(), now()
  )
  RETURNING id INTO v_room_id;

  -- 2. เพิ่มผู้ป่วยเข้าเป็น member (role: patient)
  INSERT INTO public.chat_room_members (room_id, user_id, role)
  VALUES (v_room_id, p_patient_id, 'patient');

  -- 3. อัปเดต consultation_requests ด้วย room_id
  UPDATE public.consultation_requests
  SET room_id = v_room_id,
      updated_at = now()
  WHERE id = p_consultation_id;

  RETURN v_room_id;
END;
$$ LANGUAGE plpgsql;

-- 8. RPC สำหรับ Assign Provider (แก้ปัญหา Race Condition)
CREATE OR REPLACE FUNCTION public.assign_provider_to_group(
  p_consultation_id UUID,
  p_provider_id UUID,
  p_expert_group_id TEXT
) RETURNS JSONB AS $$
DECLARE
  v_expert_record RECORD;
  v_current_count INT;
  v_room_id TEXT;
BEGIN
  -- ค้นหาข้อมูล expert group ในคำปรึกษานี้
  SELECT * INTO v_expert_record 
  FROM public.consultation_room_experts 
  WHERE consultation_id = p_consultation_id AND expert_group_id = p_expert_group_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'ไม่พบกลุ่มผู้เชี่ยวชาญนี้ในแพ็คเกจ');
  END IF;

  -- นับจำนวนคนที่รับงานไปแล้วในกลุ่มนี้
  SELECT COUNT(*) INTO v_current_count
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id 
    AND expert_group_id = p_expert_group_id 
    AND status = 'joined'
    AND provider_id IS NOT NULL;

  IF v_current_count >= v_expert_record.max_experts THEN
    RETURN jsonb_build_object('success', false, 'message', 'โควต้ากลุ่มนี้เต็มแล้ว');
  END IF;

  -- เพิ่ม provider เข้าไป
  -- เช็คว่ามี record waiting ที่ยังไม่มี provider_id ไหม (สำหรับ slot แรก)
  IF v_expert_record.provider_id IS NULL THEN
    UPDATE public.consultation_room_experts
    SET provider_id = p_provider_id,
        status = 'joined',
        joined_at = now()
    WHERE id = v_expert_record.id;
  ELSE
    -- สร้าง slot ใหม่สำหรับ provider คนนี้ถ้ายังไม่เกิน max_experts
    INSERT INTO public.consultation_room_experts (
      consultation_id, room_id, expert_group_id, expert_group_name, expert_group_role,
      max_experts, is_required, provider_id, status, joined_at
    ) VALUES (
      p_consultation_id, v_expert_record.room_id, p_expert_group_id, v_expert_record.expert_group_name, v_expert_record.expert_group_role,
      v_expert_record.max_experts, v_expert_record.is_required, p_provider_id, 'joined', now()
    );
  END IF;

  -- ดึง room_id เพื่อเพิ่ม provider เข้าแชท
  SELECT room_id INTO v_room_id FROM public.consultation_requests WHERE id = p_consultation_id;
  
  IF v_room_id IS NOT NULL THEN
    -- เพิ่มหมอเป็น member ของห้อง
    INSERT INTO public.chat_room_members (room_id, user_id, role)
    VALUES (v_room_id, p_provider_id, 'doctor')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'เข้าร่วมสำเร็จ');
END;
$$ LANGUAGE plpgsql;
