-- Fix cancelled invitation feed to use the canonical organization sources.
-- The project does not define public.organizations; professions is the ERP organization root.

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
          NULLIF(TRIM(pp.business_name), ''),
          NULLIF(TRIM(ra_business.business_name), ''),
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
  LEFT JOIN public.users cu ON cu.id = ei.cancelled_by
  WHERE ei.user_id = p_user_id
    AND ei.status = 'cancelled';

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cancelled_invitations_for_user(UUID) TO authenticated;
