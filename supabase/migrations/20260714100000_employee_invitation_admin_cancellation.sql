-- E4: Separate admin cancellation from invitee rejection
-- Migration: Add columns for admin cancellation + fix CHECK constraint + new RPCs

-- ============================================================
-- E4.1: Add columns for admin cancellation
-- ============================================================
ALTER TABLE public.employee_invitations
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

-- ⚠️ Fix CHECK constraint to allow status 'cancelled'
ALTER TABLE public.employee_invitations
  DROP CONSTRAINT IF EXISTS employee_invitations_status_check;
ALTER TABLE public.employee_invitations
  ADD CONSTRAINT employee_invitations_status_check
  CHECK (status IN ('pending','accepted','rejected','expired','cancelled'));

-- ============================================================
-- E4.2: RPC cancel_employee_invitation (B-lite approach)
-- ============================================================
CREATE OR REPLACE FUNCTION public.cancel_employee_invitation(
  p_token TEXT,
  p_cancelled_by UUID,
  p_cancellation_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_invitation public.employee_invitations%ROWTYPE;
BEGIN
  IF p_cancelled_by IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ไม่พบผู้ใช้ใน session');
  END IF;

  SELECT * INTO v_invitation
  FROM public.employee_invitations
  WHERE token = p_token AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'คำเชิญไม่ถูกต้องหรือดำเนินการไปแล้ว');
  END IF;

  PERFORM set_config('app.user_id', p_cancelled_by::TEXT, true);

  IF NOT app.can_manage_employees(v_invitation.profession_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ไม่มีสิทธิ์ยกเลิกคำเชิญ');
  END IF;

  UPDATE public.employee_invitations
  SET status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = p_cancelled_by,
      cancellation_reason = p_cancellation_reason,
      updated_at = now()
  WHERE id = v_invitation.id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================
-- E4.4: RPC get_cancelled_invitations_for_user
-- Returns cancelled invitations for a specific user (read-only feed)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_cancelled_invitations_for_user(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ei.id,
        'token', ei.token,
        'profession_id', ei.profession_id,
        'profession_name', p.name,
        'organization_name', COALESCE(
          NULLIF(TRIM(org.organization_name), ''),
          p.name
        ),
        'full_name', ei.full_name,
        'job_title', ei.job_title,
        'status', ei.status,
        'cancelled_at', ei.cancelled_at,
        'cancellation_reason', ei.cancellation_reason,
        'cancelled_by_name', COALESCE(
          NULLIF(TRIM(cu.first_name || ' ' || cu.last_name), ''),
          cu.username,
          cu.email
        ),
        'created_at', ei.created_at
      )
      ORDER BY ei.cancelled_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM public.employee_invitations ei
  LEFT JOIN public.professions p ON p.id = ei.profession_id
  LEFT JOIN public.organizations org ON org.profession_id = ei.profession_id
  LEFT JOIN public.users cu ON cu.id = ei.cancelled_by
  WHERE ei.user_id = p_user_id
    AND ei.status = 'cancelled';

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- ============================================================
-- E4.4: Update get_invitation_history_for_user to include cancellation info
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_invitation_history_for_user(
  p_profession_id UUID,
  p_user_id UUID DEFAULT NULL,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ei.id,
        'status', ei.status,
        'full_name', ei.full_name,
        'created_at', ei.created_at,
        'updated_at', ei.updated_at,
        'rejected_at', ei.rejected_at,
        'rejection_reason', ei.rejection_reason,
        'cancelled_at', ei.cancelled_at,
        'cancellation_reason', ei.cancellation_reason,
        'cancelled_by_name', COALESCE(
          NULLIF(TRIM(cu.first_name || ' ' || cu.last_name), ''),
          cu.username,
          cu.email
        ),
        'invited_by_name', COALESCE(
          NULLIF(TRIM(iu.first_name || ' ' || iu.last_name), ''),
          iu.username,
          iu.email
        ),
        'expires_at', ei.expires_at,
        'intended_role_name', ei.intended_role_name
      )
      ORDER BY ei.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM public.employee_invitations ei
  LEFT JOIN public.users iu ON iu.id = ei.invited_by
  LEFT JOIN public.users cu ON cu.id = ei.cancelled_by
  WHERE ei.profession_id = p_profession_id
    AND (
      (p_user_id IS NOT NULL AND ei.user_id = p_user_id)
      OR (p_email IS NOT NULL AND ei.email = p_email)
      OR (p_phone IS NOT NULL AND ei.phone = p_phone)
    );

  RETURN v_result;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.cancel_employee_invitation(TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cancelled_invitations_for_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_invitation_history_for_user(UUID, UUID, TEXT, TEXT) TO authenticated;
