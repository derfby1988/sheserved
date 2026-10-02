-- Track the latest owner-application submission separately from created_at.
--
-- Rejected applications are resubmitted via UPDATE on the same profile row,
-- so created_at always reports the first-ever submission. submitted_at is
-- stamped on every submit_sports_venue_owner_application call; the owner
-- dashboard shows it as the submission date alongside reviewed_at (the
-- approval/rejection date set by review_sports_venue_owner_application).

ALTER TABLE public.sports_venue_owner_profiles
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ;

UPDATE public.sports_venue_owner_profiles
SET submitted_at = created_at
WHERE submitted_at IS NULL;

ALTER TABLE public.sports_venue_owner_profiles
  ALTER COLUMN submitted_at SET NOT NULL;

CREATE OR REPLACE FUNCTION public.submit_sports_venue_owner_application(
  p_user_id UUID,
  p_business_name VARCHAR,
  p_contact_name VARCHAR,
  p_contact_phone VARCHAR,
  p_contact_email VARCHAR DEFAULT NULL,
  p_evidence JSONB DEFAULT '[]'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_status TEXT;
  r RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF length(btrim(COALESCE(p_business_name, ''))) = 0
     OR length(btrim(COALESCE(p_contact_name, ''))) = 0
     OR (length(btrim(COALESCE(p_contact_phone, ''))) = 0
         AND length(btrim(COALESCE(p_contact_email, ''))) = 0) THEN
    RAISE EXCEPTION 'INVALID_APPLICATION';
  END IF;

  SELECT id, status INTO v_id, v_status
  FROM public.sports_venue_owner_profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_status IN ('pending','approved','suspended') THEN
    -- approved owners do not re-apply; suspended stays suspended.
    IF v_status = 'approved' THEN
      RAISE EXCEPTION 'ALREADY_APPROVED';
    END IF;
    IF v_status = 'suspended' THEN
      RAISE EXCEPTION 'OWNER_SUSPENDED';
    END IF;
    RAISE EXCEPTION 'APPLICATION_PENDING';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.sports_venue_owner_profiles (
      user_id, business_name, contact_name, contact_phone,
      contact_email, evidence, status, submitted_at
    ) VALUES (
      p_user_id, p_business_name, p_contact_name, p_contact_phone,
      p_contact_email, COALESCE(p_evidence, '[]'::jsonb), 'pending', now()
    )
    RETURNING id INTO v_id;
  ELSE
    -- Rejected applications may be resubmitted with fresh data.
    UPDATE public.sports_venue_owner_profiles
    SET business_name = p_business_name,
        contact_name = p_contact_name,
        contact_phone = p_contact_phone,
        contact_email = p_contact_email,
        evidence = COALESCE(p_evidence, '[]'::jsonb),
        status = 'pending',
        reviewed_by = NULL,
        reviewed_at = NULL,
        rejection_reason = NULL,
        submitted_at = now(),
        updated_at = now()
    WHERE id = v_id;
  END IF;

  -- Notify Sheserved admins about the new application. Guarded helper:
  -- notification failures must never abort the application.
  FOR r IN SELECT u.id FROM public.users u WHERE u.role = 'admin'
  LOOP
    PERFORM public.sports_hub_notify(
      r.id, 'venue_supply', 'venue_owner.application_submitted',
      'มีคำขอลงทะเบียนเจ้าของสนามใหม่',
      FORMAT('%s ส่งคำขอลงทะเบียนสนาม "%s"', p_contact_name, p_business_name),
      JSONB_BUILD_OBJECT(
        'route', '/community/sports/courts/owner/applications',
        'ownerProfileId', v_id
      )
    );
  END LOOP;

  RETURN v_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
