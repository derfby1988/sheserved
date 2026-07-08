-- Migration: Atomic cancel + reject application RPC
-- Date: 2026-07-08
-- Eliminates TOCTOU by doing cancel/reject + user reset in a single transaction
-- SECURITY DEFINER bypasses RLS so the user update always succeeds

-- 1. Cancel application RPC (สำหรับผู้ใช้ยกเลิกเอง)
CREATE OR REPLACE FUNCTION public.cancel_registration_application(
  p_application_id UUID,
  p_user_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_updated_count INTEGER;
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
    AND status = 'pending';

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 THEN
    RAISE EXCEPTION 'NOT_PENDING_OR_NOT_OWNER';
  END IF;

  -- 2. Reset user กลับไป default consumer profession
  UPDATE public.users
  SET profession_id = '00000000-0000-0000-0000-000000000001',
      role = 'consumer',
      verification_status = 'verified',
      updated_at = v_now
  WHERE id = p_user_id;
END;
$$;

-- 2. Reject application RPC (สำหรับ admin ปฏิเสธ)
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
  v_updated_count INTEGER;
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
  RETURNING user_id INTO v_user_id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 THEN
    RAISE EXCEPTION 'NOT_PENDING';
  END IF;

  -- 2. Reset user กลับไป default consumer profession
  UPDATE public.users
  SET profession_id = '00000000-0000-0000-0000-000000000001',
      role = 'consumer',
      verification_status = 'verified',
      updated_at = v_now
  WHERE id = v_user_id;
END;
$$;

-- Grant access
GRANT EXECUTE ON FUNCTION public.cancel_registration_application(
  UUID, UUID
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.reject_registration_application(
  UUID, TEXT, UUID
) TO authenticated;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
