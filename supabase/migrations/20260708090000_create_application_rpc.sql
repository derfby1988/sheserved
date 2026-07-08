-- Migration: Atomic create_application RPC
-- Date: 2026-07-08
-- Eliminates TOCTOU race condition by doing check + insert in a single atomic transaction

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
  v_now TIMESTAMPTZ := now();
  v_inserted public.registration_applications;
BEGIN
  -- 1. ตรวจสอบ pending ที่มีอยู่ (ทุกอาชีพ)
  SELECT EXISTS(
    SELECT 1 FROM public.registration_applications
    WHERE user_id = p_user_id AND status = 'pending'
  ) INTO v_existing_pending;

  IF v_existing_pending THEN
    RAISE EXCEPTION 'PENDING_EXISTS';
  END IF;

  -- 2. ตรวจสอบ approved สำหรับอาชีพเดียวกัน
  SELECT EXISTS(
    SELECT 1 FROM public.registration_applications
    WHERE user_id = p_user_id
      AND profession_id = p_profession_id
      AND status = 'approved'
  ) INTO v_existing_approved;

  IF v_existing_approved THEN
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

  -- 4. Insert (unique partial index เป็น safety net สุดท้าย)
  INSERT INTO public.registration_applications (
    user_id, profession_id, first_name, last_name,
    username, phone, profile_image_url,
    registration_data, status, created_at, updated_at
  ) VALUES (
    p_user_id, p_profession_id, p_first_name, p_last_name,
    p_username, p_phone, p_profile_image_url,
    p_registration_data, 'pending', v_now, v_now
  )
  RETURNING * INTO v_inserted;

  RETURN v_inserted;
END;
$$;

-- Grant access
GRANT EXECUTE ON FUNCTION public.create_registration_application(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) TO anon, authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
