-- =====================================================
-- Migration: เพิ่ม rejection_reason + rejected_at ใน employee_invitations
-- + แก้ reject_employee_invitation ให้รับเหตุผล
-- + เพิ่ม get_pending_employee_invitations_for_user
-- Date: 2026-07-13
-- =====================================================

-- 1. Add columns
ALTER TABLE public.employee_invitations
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
  ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;

-- 2. Update reject_employee_invitation to accept rejection reason
CREATE OR REPLACE FUNCTION public.reject_employee_invitation(
  p_token TEXT,
  p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_invitation public.employee_invitations%ROWTYPE;
BEGIN
  SELECT * INTO v_invitation
  FROM public.employee_invitations
  WHERE token = p_token AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'คำเชิญไม่ถูกต้อง');
  END IF;

  IF v_invitation.expires_at < now() THEN
    UPDATE public.employee_invitations
    SET status = 'expired', updated_at = now()
    WHERE id = v_invitation.id;
    RETURN jsonb_build_object('success', false, 'error', 'คำเชิญหมดอายุ');
  END IF;

  UPDATE public.employee_invitations
  SET status = 'rejected',
      rejection_reason = p_rejection_reason,
      rejected_at = now(),
      updated_at = now()
  WHERE id = v_invitation.id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 3. New RPC: get pending invitations for a user (invitee side)
CREATE OR REPLACE FUNCTION public.get_pending_employee_invitations_for_user(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(jsonb_build_object(
      'id', ei.id,
      'token', ei.token,
      'profession_id', ei.profession_id,
      'profession_name', p.name,
      'organization_name', COALESCE(
        NULLIF(TRIM(pp.business_name), ''),
        NULLIF(TRIM(ra_business.business_name), ''),
        p.name
      ),
      'full_name', ei.full_name,
      'employee_code', ei.employee_code,
      'department', ei.department,
      'job_title', ei.job_title,
      'branch_name', b.branch_name,
      'invited_by_name', COALESCE(NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''), u.username, u.email),
      'expires_at', ei.expires_at,
      'created_at', ei.created_at
    ) ORDER BY ei.created_at DESC)
    FROM public.employee_invitations ei
    JOIN public.professions p ON p.id = ei.profession_id
    LEFT JOIN public.organization_branches b ON b.id = ei.branch_id
    LEFT JOIN public.users u ON u.id = ei.invited_by
    LEFT JOIN public.provider_profiles pp ON pp.user_id = ei.invited_by
    LEFT JOIN LATERAL (
      SELECT (ra.registration_data->>'business_name')::TEXT AS business_name
      FROM public.registration_applications ra
      WHERE ra.user_id = ei.invited_by
        AND ra.profession_id = ei.profession_id
        AND ra.status = 'approved'
      ORDER BY ra.updated_at DESC
      LIMIT 1
    ) ra_business ON true
    WHERE ei.user_id = p_user_id
      AND ei.status = 'pending'
      AND ei.expires_at > now()
  );
END;
$$;
