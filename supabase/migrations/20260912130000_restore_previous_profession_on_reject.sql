-- Migration: Restore previous profession on reject/cancel
-- Date: 2026-09-12
--
-- ปัญหา: reject_registration_application / cancel_registration_application
--   hard-code reset profession เป็น default consumer ('ผู้ใช้งานทั่วไป')
--   ทำให้ user ที่เปลี่ยนอาชีพ (เช่น แพทย์ทั่วไป → กู้ภัย) แล้วถูกปฏิเสธ
--   เสียอาชีพเดิมไป แทนที่จะกลับไปอาชีพเดิม
--
-- แนวทาง:
--   1. เพิ่มคอลัมน์ previous_profession_id เก็บอาชีพเดิมแบบ server-side
--      (ไม่เชื่อ registration_data ที่ client ส่งมา)
--   2. create_registration_application snapshot users.profession_id
--      ก่อนเปลี่ยน และอัปเดต user เป็นอาชีพใหม่ใน transaction เดียว
--   3. reject/cancel restore จากคอลัมน์นั้น (fallback default consumer
--      เมื่อไม่มีอาชีพเดิม หรืออาชีพเดิมถูก deactivate)
--   4. ไม่เซ็ต role ตรงๆ — trigger trigger_sync_role_from_profession
--      derive role/user_category_id จาก professions.category ให้เอง
--
-- ⚠️ PostgREST side-effect: ตารางนี้มี FK ไป professions สองตัว
--    (profession_id + previous_profession_id) ทำให้ embed
--    profession:professions(*) ambiguous (PGRST201) — ฝั่ง client ต้อง
--    ใช้ FK hint: profession:professions!profession_id(*) เสมอ

-- ============================================================
-- 1. เพิ่มคอลัมน์ previous_profession_id + backfill จาก JSONB เดิม
-- ============================================================
ALTER TABLE public.registration_applications
  ADD COLUMN IF NOT EXISTS previous_profession_id UUID
  REFERENCES public.professions(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.registration_applications.previous_profession_id IS
  'อาชีพเดิมของผู้สมัคร ณ ตอนสร้างใบสมัคร (server-side snapshot) ใช้ restore เมื่อ reject/cancel';

UPDATE public.registration_applications
SET previous_profession_id = (registration_data->>'previous_profession_id')::uuid
WHERE previous_profession_id IS NULL
  AND registration_data ? 'previous_profession_id'
  AND registration_data->>'previous_profession_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- ============================================================
-- 2. create_registration_application: snapshot + update user atomically
-- ============================================================
-- หมายเหตุลำดับ: ต้อง UPDATE users ก่อน INSERT ใบสมัคร เพราะ trigger
-- trg_auto_cancel_pending_apps (AFTER UPDATE OF profession_id) จะยกเลิก
-- ใบสมัคร pending ทั้งหมดของ user — ถ้า insert ก่อน ใบใหม่จะถูกยกเลิกทันที
CREATE OR REPLACE FUNCTION public.create_registration_application(
  p_user_id UUID,
  p_profession_id UUID,
  p_first_name TEXT,
  p_last_name TEXT,
  p_username TEXT,
  p_phone TEXT DEFAULT NULL,
  p_profile_image_url TEXT DEFAULT NULL,
  p_registration_data JSONB DEFAULT '{}'::jsonb
)
RETURNS public.registration_applications
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_existing_pending BOOLEAN;
  v_existing_approved BOOLEAN;
  v_existing_role BOOLEAN;
  v_previous_profession_id UUID;
  v_now TIMESTAMPTZ := now();
  v_inserted public.registration_applications;
BEGIN
  -- 0. Auth guard: ผู้ใช้ PostgREST สร้างใบสมัครให้ตัวเองเท่านั้น
  --    (service role / backend auth ที่ auth.uid() IS NULL ผ่านได้
  --     เพราะ backend verify req.userId จาก JWT แล้ว)
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- 0b. Admin guard: admin ไม่ควรถูก demote โดย trigger sync_role
  --     ป้องกัน admin เสียสิทธิ์เมื่อสมัครเปลี่ยนอาชีพ
  IF EXISTS (
    SELECT 1 FROM public.users WHERE id = p_user_id AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'ADMIN_CANNOT_APPLY';
  END IF;

  -- 1. ตรวจสอบ pending ที่มีอยู่ (ทุกอาชีพ)
  SELECT EXISTS(
    SELECT 1 FROM public.registration_applications
    WHERE user_id = p_user_id AND status = 'pending'
  ) INTO v_existing_pending;

  IF v_existing_pending THEN
    RAISE EXCEPTION 'PENDING_EXISTS';
  END IF;

  -- 2. ตรวจสอบ approved สำหรับอาชีพเดียวกัน
  -- บล็อกเฉพาะเมื่อ user ยังอยู่ในอาชีพนี้จริงๆ
  SELECT EXISTS(
    SELECT 1 FROM public.registration_applications
    WHERE user_id = p_user_id
      AND profession_id = p_profession_id
      AND status = 'approved'
  ) INTO v_existing_approved;

  IF v_existing_approved AND EXISTS(
    SELECT 1 FROM public.users
    WHERE id = p_user_id AND profession_id = p_profession_id
  ) THEN
    RAISE EXCEPTION 'APPROVED_EXISTS';
  END IF;

  -- 3. ตรวจสอบ active employee_roles สำหรับอาชีพเดียวกัน
  SELECT EXISTS(
    SELECT 1 FROM public.employee_roles
    WHERE user_id = p_user_id
      AND profession_id = p_profession_id
      AND is_active = true
  ) INTO v_existing_role;

  IF v_existing_role THEN
    RAISE EXCEPTION 'ROLE_EXISTS';
  END IF;

  -- 4. Snapshot อาชีพเดิม (authoritative — อ่านจาก DB ไม่ใช่ client)
  SELECT profession_id INTO v_previous_profession_id
  FROM public.users
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  -- 5. อัปเดต user เป็นอาชีพใหม่ (pending) ใน transaction เดียว
  --    trigger sync_role_from_profession derive role/user_category_id ให้
  --    trigger auto_cancel_pending_applications ยิงตอนนี้ — ปลอดภัยเพราะ
  --    ใบสมัครใหม่ยังไม่ถูก insert
  UPDATE public.users
  SET profession_id = p_profession_id,
      verification_status = 'pending',
      updated_at = v_now
  WHERE id = p_user_id;

  -- 6. Insert (unique partial index เป็น safety net สุดท้าย)
  INSERT INTO public.registration_applications (
    user_id, profession_id, previous_profession_id,
    first_name, last_name, username, phone, profile_image_url,
    registration_data, status, created_at, updated_at
  ) VALUES (
    p_user_id, p_profession_id, v_previous_profession_id,
    p_first_name, p_last_name, p_username, p_phone, p_profile_image_url,
    p_registration_data, 'pending', v_now, v_now
  )
  RETURNING * INTO v_inserted;

  RETURN v_inserted;
END;
$$;

-- ============================================================
-- 3. reject_registration_application: restore อาชีพเดิม
-- ============================================================
CREATE OR REPLACE FUNCTION public.reject_registration_application(
  p_application_id UUID,
  p_review_note TEXT,
  p_reviewed_by UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_pending_profession_id UUID;
  v_previous_profession_id UUID;
  v_restore_id UUID;
  v_now TIMESTAMPTZ := now();
BEGIN
  -- 1. ปฏิเสธใบสมัคร (ต้องเป็น pending เท่านั้น)
  UPDATE public.registration_applications
  SET status = 'rejected',
      review_note = p_review_note,
      reviewed_by = p_reviewed_by,
      reviewed_at = v_now,
      updated_at = v_now
  WHERE id = p_application_id
    AND status = 'pending'
  RETURNING user_id, profession_id, previous_profession_id
  INTO v_user_id, v_pending_profession_id, v_previous_profession_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_PENDING';
  END IF;

  -- 2. อาชีพเดิมต้องยัง active — ไม่งั้น fallback default consumer
  SELECT p.id INTO v_restore_id
  FROM public.professions p
  WHERE p.id = v_previous_profession_id AND p.is_active = true;
  v_restore_id := COALESCE(
    v_restore_id, '00000000-0000-0000-0000-000000000001');

  -- 3. Restore อาชีพเดิม — guard: เฉพาะเมื่อ user ยังค้างที่อาชีพที่ขอ
  --    (ถ้าย้ายไปแล้ว trigger auto_cancel จัดการไว้แล้ว ไม่ทับ state ใหม่)
  --    ไม่เซ็ต role — trigger sync_role_from_profession derive ให้เอง
  UPDATE public.users
  SET profession_id = v_restore_id,
      verification_status = 'verified',
      updated_at = v_now
  WHERE id = v_user_id
    AND profession_id = v_pending_profession_id;
END;
$$;

-- ============================================================
-- 4. cancel_registration_application: restore อาชีพเดิมเช่นกัน
-- ============================================================
CREATE OR REPLACE FUNCTION public.cancel_registration_application(
  p_application_id UUID,
  p_user_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pending_profession_id UUID;
  v_previous_profession_id UUID;
  v_restore_id UUID;
  v_now TIMESTAMPTZ := now();
BEGIN
  -- 1. ยกเลิกใบสมัคร (ต้องเป็น pending ของ user คนนี้เท่านั้น)
  UPDATE public.registration_applications
  SET status = 'cancelled',
      cancelled_by = 'user',
      cancelled_at = v_now,
      updated_at = v_now
  WHERE id = p_application_id
    AND user_id = p_user_id
    AND status = 'pending'
  RETURNING profession_id, previous_profession_id
  INTO v_pending_profession_id, v_previous_profession_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_PENDING_OR_NOT_OWNER';
  END IF;

  -- 2. อาชีพเดิมต้องยัง active — ไม่งั้น fallback default consumer
  SELECT p.id INTO v_restore_id
  FROM public.professions p
  WHERE p.id = v_previous_profession_id AND p.is_active = true;
  v_restore_id := COALESCE(
    v_restore_id, '00000000-0000-0000-0000-000000000001');

  -- 3. Restore อาชีพเดิม (guard เหมือน reject)
  UPDATE public.users
  SET profession_id = v_restore_id,
      verification_status = 'verified',
      updated_at = v_now
  WHERE id = p_user_id
    AND profession_id = v_pending_profession_id;
END;
$$;

-- Grant access (CREATE OR REPLACE คง grant เดิม แต่ re-grant เพื่อความชัวร์)
GRANT EXECUTE ON FUNCTION public.create_registration_application(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.reject_registration_application(
  UUID, TEXT, UUID
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.cancel_registration_application(
  UUID, UUID
) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
