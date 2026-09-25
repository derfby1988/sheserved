-- Phase 21.7.11 — Sports Hub: owner venue setup truthfulness, review
-- readiness gate and resubmission flow.
--
-- Contract changes:
--   * venues start as 'draft' and reach 'pending' only through the new
--     submit_sports_venue_for_review RPC once every required setup item is
--     persisted; admin 'approved' decisions are gated server-side by the
--     same readiness check (review_sports_venue can no longer approve an
--     incomplete venue)
--   * rejected venues resubmit through the same RPC; suspended venues
--     cannot resubmit through the normal path
--   * amenities are optional but the "confirmed none" choice is persisted
--     (amenities_confirmed); platform base terms (version 0) are a valid
--     explicit choice (uses_platform_terms)
--   * operating hours must cover all 7 days; cross-midnight windows are
--     rejected (bookings do not support cross-day slots)
--   * a venue sport cannot be removed while active courts are still bound
--     to it (SPORT_IN_USE)
--   * list_my_sports_venues / get_my_sports_venue_detail now expose the
--     caller's member_role so venue managers (without their own owner
--     profile) get full manage scope; venue creation still requires an
--     approved owner profile
--   * every review/submission transition is audited in
--     sports_venue_status_events and notified through sports_hub_notify

-- ===============
-- Schema changes
-- ===============
ALTER TABLE public.sports_venues
  ADD COLUMN IF NOT EXISTS uses_platform_terms BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS amenities_confirmed BOOLEAN NOT NULL DEFAULT false;

-- 'draft' is the state before the owner submits for review.
ALTER TABLE public.sports_venues
  DROP CONSTRAINT IF EXISTS sports_venues_status_check;
ALTER TABLE public.sports_venues
  ADD CONSTRAINT sports_venues_status_check
  CHECK (status IN ('draft','pending','approved','rejected','suspended'));
ALTER TABLE public.sports_venues
  ALTER COLUMN status SET DEFAULT 'draft';

-- Audit trail for venue lifecycle transitions (submit / review / suspend).
CREATE TABLE IF NOT EXISTS public.sports_venue_status_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id)
    ON DELETE CASCADE,
  actor_id UUID REFERENCES public.users(id),
  event_type VARCHAR(30) NOT NULL,
  previous_status VARCHAR(10),
  new_status VARCHAR(10) NOT NULL,
  reason VARCHAR(500),
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sports_venue_status_events_venue
  ON public.sports_venue_status_events(venue_id, created_at);

ALTER TABLE public.sports_venue_status_events ENABLE ROW LEVEL SECURITY;
-- No public SELECT policy: audit rows are read by owners/admins only via
-- SECURITY DEFINER surfaces if ever needed.

-- ===============
-- Readiness: which mandatory setup items are still missing
-- ===============
-- Returns the list of missing item keys; an empty array means the venue is
-- ready to submit for review / be approved. Required items mirror the
-- owner checklist plus the venue-profile fields discovery depends on:
--   owner_not_approved, name, province, district, address, location,
--   timezone, sports, hours, amenities, terms, courts
-- Photos stay optional — they are not part of the readiness gate.
CREATE OR REPLACE FUNCTION public.sports_venue_setup_missing(
  p_venue_id UUID
)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec RECORD;
  v_missing TEXT[] := ARRAY[]::text[];
BEGIN
  SELECT ven.*, op.status AS owner_status
  INTO v_rec
  FROM public.sports_venues ven
  LEFT JOIN public.sports_venue_owner_profiles op
    ON op.id = ven.owner_profile_id
  WHERE ven.id = p_venue_id;

  IF v_rec.id IS NULL THEN
    RETURN ARRAY['venue_not_found'];
  END IF;

  IF v_rec.owner_status IS NULL OR v_rec.owner_status <> 'approved' THEN
    v_missing := array_append(v_missing, 'owner_not_approved');
  END IF;
  IF length(btrim(COALESCE(v_rec.name, ''))) = 0 THEN
    v_missing := array_append(v_missing, 'name');
  END IF;
  IF length(btrim(COALESCE(v_rec.province, ''))) = 0 THEN
    v_missing := array_append(v_missing, 'province');
  END IF;
  IF length(btrim(COALESCE(v_rec.district, ''))) = 0 THEN
    v_missing := array_append(v_missing, 'district');
  END IF;
  IF length(btrim(COALESCE(v_rec.address, ''))) = 0 THEN
    v_missing := array_append(v_missing, 'address');
  END IF;
  IF v_rec.lat IS NULL OR v_rec.lng IS NULL THEN
    v_missing := array_append(v_missing, 'location');
  END IF;
  IF length(btrim(COALESCE(v_rec.timezone, ''))) = 0 THEN
    v_missing := array_append(v_missing, 'timezone');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.sports_venue_sports vs
    WHERE vs.venue_id = p_venue_id
  ) THEN
    v_missing := array_append(v_missing, 'sports');
  END IF;
  -- Hours must be explicit for every weekday (0-6); absence of rows is
  -- never interpreted as 24/7.
  IF (
    SELECT count(DISTINCT h.day_of_week)
    FROM public.sports_venue_operating_hours h
    WHERE h.venue_id = p_venue_id AND h.day_of_week BETWEEN 0 AND 6
  ) < 7 THEN
    v_missing := array_append(v_missing, 'hours');
  END IF;
  IF NOT v_rec.amenities_confirmed THEN
    v_missing := array_append(v_missing, 'amenities');
  END IF;
  IF NOT v_rec.uses_platform_terms AND NOT EXISTS (
    SELECT 1 FROM public.sports_venue_terms t
    WHERE t.venue_id = p_venue_id AND t.status = 'active'
  ) THEN
    v_missing := array_append(v_missing, 'terms');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.sports_venue_courts c
    WHERE c.venue_id = p_venue_id AND c.is_active
  ) THEN
    v_missing := array_append(v_missing, 'courts');
  END IF;

  RETURN v_missing;
END;
$$;

-- ===============
-- Venue lifecycle
-- ===============

-- Create or update a venue. New venues start as 'draft' — they reach
-- 'pending' only via submit_sports_venue_for_review.
CREATE OR REPLACE FUNCTION public.upsert_sports_venue(
  p_user_id UUID,
  p_venue_id UUID,
  p_name VARCHAR,
  p_description VARCHAR DEFAULT NULL,
  p_province TEXT DEFAULT NULL,
  p_district TEXT DEFAULT NULL,
  p_address VARCHAR DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL,
  p_timezone VARCHAR DEFAULT 'Asia/Bangkok'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id UUID;
  v_id UUID;
BEGIN
  SELECT id INTO v_profile_id
  FROM public.sports_venue_owner_profiles
  WHERE user_id = p_user_id AND status = 'approved';
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'OWNER_NOT_APPROVED';
  END IF;
  IF length(btrim(COALESCE(p_name, ''))) = 0 THEN
    RAISE EXCEPTION 'INVALID_VENUE';
  END IF;

  IF p_venue_id IS NULL THEN
    INSERT INTO public.sports_venues (
      owner_profile_id, name, description, province, district, address,
      lat, lng, timezone, status
    ) VALUES (
      v_profile_id, p_name, p_description, p_province, p_district,
      p_address, p_lat, p_lng,
      COALESCE(NULLIF(p_timezone, ''), 'Asia/Bangkok'), 'draft'
    )
    RETURNING id INTO v_id;

    INSERT INTO public.sports_venue_status_events (
      venue_id, actor_id, event_type, new_status
    ) VALUES (v_id, p_user_id, 'created', 'draft');
  ELSE
    IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
      RAISE EXCEPTION 'NOT_VENUE_MANAGER';
    END IF;
    UPDATE public.sports_venues
    SET name = p_name,
        description = p_description,
        province = p_province,
        district = p_district,
        address = p_address,
        lat = p_lat,
        lng = p_lng,
        timezone = COALESCE(NULLIF(p_timezone, ''), timezone),
        updated_at = now()
    WHERE id = p_venue_id;
    v_id := p_venue_id;
  END IF;
  RETURN v_id;
END;
$$;

-- Owner/manager submits a draft (or previously rejected) venue for admin
-- review. Every mandatory setup item must be persisted first.
CREATE OR REPLACE FUNCTION public.submit_sports_venue_for_review(
  p_user_id UUID,
  p_venue_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status VARCHAR(10);
  v_name VARCHAR;
  v_missing TEXT[];
  r RECORD;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  SELECT status, name INTO v_status, v_name
  FROM public.sports_venues WHERE id = p_venue_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
  -- Suspended venues are excluded from the normal resubmission path.
  IF v_status NOT IN ('draft','rejected') THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  v_missing := public.sports_venue_setup_missing(p_venue_id);
  IF COALESCE(array_length(v_missing, 1), 0) > 0 THEN
    RAISE EXCEPTION 'VENUE_NOT_READY: %', array_to_string(v_missing, ',');
  END IF;

  UPDATE public.sports_venues
  SET status = 'pending',
      reviewed_by = NULL,
      reviewed_at = NULL,
      rejection_reason = NULL,
      updated_at = now()
  WHERE id = p_venue_id;

  INSERT INTO public.sports_venue_status_events (
    venue_id, actor_id, event_type, previous_status, new_status
  ) VALUES (
    p_venue_id, p_user_id,
    CASE WHEN v_status = 'rejected'
         THEN 'resubmitted' ELSE 'submitted' END,
    v_status, 'pending'
  );

  FOR r IN SELECT u.id FROM public.users u WHERE u.role = 'admin'
  LOOP
    PERFORM public.sports_hub_notify(
      r.id, 'venue_supply',
      CASE WHEN v_status = 'rejected'
           THEN 'venue.resubmitted' ELSE 'venue.submitted' END,
      'มีสนามส่งตรวจสอบ',
      FORMAT('"%s" ส่งขออนุมัติเปิดรับการจอง', v_name),
      JSONB_BUILD_OBJECT(
        'route', '/community/sports/courts/owner/applications',
        'venueId', p_venue_id
      )
    );
  END LOOP;
END;
$$;

-- Owner confirms the platform base terms (version 0) instead of
-- publishing custom venue terms.
CREATE OR REPLACE FUNCTION public.confirm_sports_venue_platform_terms(
  p_user_id UUID,
  p_venue_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  UPDATE public.sports_venues
  SET uses_platform_terms = true, updated_at = now()
  WHERE id = p_venue_id;
END;
$$;

-- Admin decision on a venue listing. 'approved' requires the venue to be
-- pending AND fully set up — admins cannot publish an incomplete venue.
CREATE OR REPLACE FUNCTION public.review_sports_venue(
  p_admin_id UUID,
  p_venue_id UUID,
  p_decision VARCHAR,  -- 'approved' | 'rejected' | 'suspended'
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_user_id UUID;
  v_name TEXT;
  v_status VARCHAR(10);
  v_missing TEXT[];
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_decision NOT IN ('approved','rejected','suspended') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;

  SELECT status, name INTO v_status, v_name
  FROM public.sports_venues WHERE id = p_venue_id FOR UPDATE;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;

  IF p_decision IN ('rejected','suspended')
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  IF p_decision = 'approved' THEN
    IF v_status <> 'pending' THEN
      RAISE EXCEPTION 'INVALID_STATUS';
    END IF;
    v_missing := public.sports_venue_setup_missing(p_venue_id);
    IF COALESCE(array_length(v_missing, 1), 0) > 0 THEN
      RAISE EXCEPTION 'VENUE_NOT_READY: %', array_to_string(v_missing, ',');
    END IF;
  ELSIF p_decision = 'rejected' THEN
    IF v_status <> 'pending' THEN
      RAISE EXCEPTION 'INVALID_STATUS';
    END IF;
  ELSE
    -- suspend: allowed from any live status, idempotent on suspended.
    IF v_status = 'suspended' THEN
      RAISE EXCEPTION 'INVALID_STATUS';
    END IF;
  END IF;

  UPDATE public.sports_venues
  SET status = p_decision,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      rejection_reason = CASE
        WHEN p_decision = 'approved' THEN NULL ELSE p_reason END,
      updated_at = now()
  WHERE id = p_venue_id;

  INSERT INTO public.sports_venue_status_events (
    venue_id, actor_id, event_type, previous_status, new_status, reason
  ) VALUES (p_venue_id, p_admin_id, p_decision, v_status, p_decision, p_reason);

  SELECT op.user_id INTO v_owner_user_id
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op ON op.id = v.owner_profile_id
  WHERE v.id = p_venue_id;

  PERFORM public.sports_hub_notify(
    v_owner_user_id,
    'venue_supply',
    'venue.' || p_decision,
    CASE p_decision
      WHEN 'approved' THEN 'สนามของคุณได้รับการอนุมัติ'
      WHEN 'rejected' THEN 'สนามของคุณถูกปฏิเสธ'
      ELSE 'สนามของคุณถูกระงับ'
    END,
    CASE
      WHEN p_decision = 'approved'
        THEN FORMAT('"%s" แสดงในรายการสนามแล้ว', v_name)
      ELSE FORMAT('%s — เหตุผล: %s', v_name, COALESCE(p_reason, 'ไม่ระบุ'))
    END,
    JSONB_BUILD_OBJECT(
      'route', '/community/sports/courts/owner/dashboard',
      'venueId', p_venue_id,
      'status', p_decision
    )
  );
END;
$$;

-- ===============
-- Setup write RPCs (hardened)
-- ===============

-- Replace the sport set of a venue. A sport that still has ACTIVE courts
-- bound to it cannot be removed — the owner must move or deactivate those
-- courts first, otherwise venue/resource mapping would go inconsistent.
CREATE OR REPLACE FUNCTION public.set_sports_venue_sports(
  p_user_id UUID,
  p_venue_id UUID,
  p_sports JSONB  -- [{"sport_id": uuid, "unit_label_override": text?}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_blocked UUID;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  SELECT vs.sport_id INTO v_blocked
  FROM public.sports_venue_sports vs
  WHERE vs.venue_id = p_venue_id
    AND EXISTS (
      SELECT 1 FROM public.sports_venue_courts c
      WHERE c.venue_id = p_venue_id
        AND c.sport_id = vs.sport_id
        AND c.is_active
    )
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(p_sports, '[]'::jsonb)) item
      WHERE (item->>'sport_id')::uuid = vs.sport_id
    )
  LIMIT 1;
  IF v_blocked IS NOT NULL THEN
    RAISE EXCEPTION 'SPORT_IN_USE';
  END IF;

  DELETE FROM public.sports_venue_sports WHERE venue_id = p_venue_id;

  INSERT INTO public.sports_venue_sports (
    venue_id, sport_id, unit_label_override
  )
  SELECT p_venue_id,
         (item->>'sport_id')::uuid,
         NULLIF(btrim(item->>'unit_label_override'), '')
  FROM jsonb_array_elements(COALESCE(p_sports, '[]'::jsonb)) AS item
  WHERE (item->>'sport_id') IS NOT NULL
  ON CONFLICT (venue_id, sport_id) DO UPDATE
    SET unit_label_override = EXCLUDED.unit_label_override;
END;
$$;

-- Replace weekly operating hours. The submission must specify all 7 days
-- explicitly (open window or closed) — missing days are never treated as
-- open, and cross-midnight windows are rejected because bookings do not
-- support cross-day slots.
CREATE OR REPLACE FUNCTION public.set_sports_venue_operating_hours(
  p_user_id UUID,
  p_venue_id UUID,
  p_hours JSONB  -- [{"day":0-6,"open":"HH:MM","close":"HH:MM","closed":bool}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  -- Every day 0-6 must appear exactly once.
  IF (
    SELECT count(*) FROM (
      SELECT DISTINCT (item->>'day')::smallint AS d
      FROM jsonb_array_elements(COALESCE(p_hours, '[]'::jsonb)) item
      WHERE (item->>'day') IS NOT NULL
        AND (item->>'day')::smallint BETWEEN 0 AND 6
    ) days
  ) < 7 THEN
    RAISE EXCEPTION 'INCOMPLETE_HOURS';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(COALESCE(p_hours, '[]'::jsonb)) item
    GROUP BY (item->>'day')::smallint
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'INVALID_HOURS';
  END IF;
  -- Non-closed days need a forward open->close window in the same day.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(p_hours, '[]'::jsonb)) item
    WHERE COALESCE((item->>'closed')::boolean, false) = false
      AND NOT (
        NULLIF(item->>'open', '')::time IS NOT NULL
        AND NULLIF(item->>'close', '')::time IS NOT NULL
        AND NULLIF(item->>'close', '')::time
            > NULLIF(item->>'open', '')::time
      )
  ) THEN
    RAISE EXCEPTION 'INVALID_HOURS';
  END IF;

  DELETE FROM public.sports_venue_operating_hours WHERE venue_id = p_venue_id;

  INSERT INTO public.sports_venue_operating_hours (
    venue_id, day_of_week, open_time, close_time, is_closed
  )
  SELECT p_venue_id,
         (item->>'day')::smallint,
         NULLIF(item->>'open', '')::time,
         NULLIF(item->>'close', '')::time,
         COALESCE((item->>'closed')::boolean, false)
  FROM jsonb_array_elements(COALESCE(p_hours, '[]'::jsonb)) AS item
  WHERE (item->>'day') IS NOT NULL;
END;
$$;

-- Replace the amenity set. Saving — even an empty list — persists the
-- owner's confirmation ("ยืนยันว่าไม่มี" is different from "ยังไม่ระบุ").
CREATE OR REPLACE FUNCTION public.set_sports_venue_amenities(
  p_user_id UUID,
  p_venue_id UUID,
  p_amenities TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  DELETE FROM public.sports_venue_amenities WHERE venue_id = p_venue_id;
  INSERT INTO public.sports_venue_amenities (venue_id, amenity_key)
  SELECT p_venue_id, a
  FROM unnest(COALESCE(p_amenities, ARRAY[]::text[])) AS a
  WHERE a IN (
    'parking', 'restroom', 'shower', 'ev_charging', 'equipment_rental',
    'lighting', 'locker', 'wifi', 'cafe', 'first_aid'
  )
  ON CONFLICT DO NOTHING;
  UPDATE public.sports_venues
  SET amenities_confirmed = true, updated_at = now()
  WHERE id = p_venue_id;
END;
$$;

-- Publish a new version of venue terms. Publishing custom terms also
-- records that the platform-terms shortcut is no longer the active choice.
CREATE OR REPLACE FUNCTION public.publish_sports_venue_terms(
  p_user_id UUID,
  p_venue_id UUID,
  p_terms_text TEXT,
  p_cancellation_cutoff_minutes INT DEFAULT 60
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_version INT;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF length(btrim(COALESCE(p_terms_text, ''))) = 0 THEN
    RAISE EXCEPTION 'INVALID_TERMS';
  END IF;
  IF p_cancellation_cutoff_minutes IS NULL
     OR p_cancellation_cutoff_minutes < 0 THEN
    RAISE EXCEPTION 'INVALID_CUTOFF';
  END IF;

  UPDATE public.sports_venue_terms
  SET status = 'superseded'
  WHERE venue_id = p_venue_id AND status = 'active';

  SELECT COALESCE(MAX(version), 0) + 1 INTO v_version
  FROM public.sports_venue_terms
  WHERE venue_id = p_venue_id;

  INSERT INTO public.sports_venue_terms (
    venue_id, version, terms_text, cancellation_cutoff_minutes,
    status, edited_by
  ) VALUES (
    p_venue_id, v_version, p_terms_text,
    p_cancellation_cutoff_minutes, 'active', p_user_id
  );

  UPDATE public.sports_venues
  SET uses_platform_terms = false, updated_at = now()
  WHERE id = p_venue_id;

  RETURN v_version;
END;
$$;

-- ===============
-- Owner/manager read RPCs
-- ===============

-- Venues manageable by the user with the caller's role per venue. Owners
-- (via approved profile) and invited managers both appear; only approved
-- owners may create new venues (upsert_sports_venue enforces that).
DROP FUNCTION IF EXISTS public.list_my_sports_venues(uuid);
CREATE OR REPLACE FUNCTION public.list_my_sports_venues(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  name VARCHAR,
  province TEXT,
  district TEXT,
  timezone VARCHAR,
  status VARCHAR,
  rejection_reason VARCHAR,
  court_count BIGINT,
  member_role VARCHAR,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN QUERY
  SELECT v.id, v.name, v.province, v.district, v.timezone, v.status,
         v.rejection_reason,
         (SELECT count(*) FROM public.sports_venue_courts c
           WHERE c.venue_id = v.id),
         CASE
           WHEN op.user_id = p_user_id THEN 'owner'::varchar
           ELSE COALESCE(m.role, 'manager')::varchar
         END AS member_role,
         v.created_at
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  LEFT JOIN public.sports_venue_owner_members m
    ON m.venue_id = v.id AND m.user_id = p_user_id AND m.is_active
  WHERE public.is_sports_venue_manager(v.id, p_user_id)
  ORDER BY v.created_at DESC;
END;
$$;

-- Full venue detail for its managers, including owner-profile status,
-- caller role and the server-computed missing setup items — the owner UI
-- must mirror persisted state, not infer readiness from partial rows.
CREATE OR REPLACE FUNCTION public.get_my_sports_venue_detail(
  p_user_id UUID,
  p_venue_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  SELECT JSONB_BUILD_OBJECT(
    'venue', to_jsonb(v),
    'owner_status', op.status,
    'member_role', CASE
      WHEN op.user_id = p_user_id THEN 'owner'
      ELSE COALESCE(m.role, 'manager') END,
    'setup_missing', public.sports_venue_setup_missing(v.id),
    'sports', COALESCE((
      SELECT jsonb_agg(to_jsonb(vs)) FROM public.sports_venue_sports vs
      WHERE vs.venue_id = v.id), '[]'::jsonb),
    'courts', COALESCE((
      SELECT jsonb_agg(to_jsonb(c) ORDER BY c.name)
      FROM public.sports_venue_courts c WHERE c.venue_id = v.id), '[]'::jsonb),
    'hours', COALESCE((
      SELECT jsonb_agg(to_jsonb(h) ORDER BY h.day_of_week)
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v.id), '[]'::jsonb),
    'amenities', COALESCE((
      SELECT jsonb_agg(a.amenity_key)
      FROM public.sports_venue_amenities a WHERE a.venue_id = v.id),
      '[]'::jsonb),
    'photos', COALESCE((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.sort_order)
      FROM public.sports_venue_photos p WHERE p.venue_id = v.id), '[]'::jsonb),
    'terms', (
      SELECT to_jsonb(t) FROM public.sports_venue_terms t
      WHERE t.venue_id = v.id AND t.status = 'active')
  ) INTO v_result
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  LEFT JOIN public.sports_venue_owner_members m
    ON m.venue_id = v.id AND m.user_id = p_user_id AND m.is_active
  WHERE v.id = p_venue_id;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
  RETURN v_result;
END;
$$;

-- ===============
-- Admin review detail
-- ===============

-- Per-venue readiness snapshot for the admin review surface: the venue
-- row plus the server-computed missing setup items so reviewers see the
-- same checklist truth the owner saw before submitting.
CREATE OR REPLACE FUNCTION public.get_sports_venue_admin_review_detail(
  p_admin_id UUID,
  p_venue_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  SELECT JSONB_BUILD_OBJECT(
    'venue', to_jsonb(v),
    'owner_business_name', op.business_name,
    'setup_missing', public.sports_venue_setup_missing(v.id),
    'sports', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
        'sport_id', vs.sport_id,
        'unit_label_override', vs.unit_label_override))
      FROM public.sports_venue_sports vs
      WHERE vs.venue_id = v.id), '[]'::jsonb),
    'court_count', (
      SELECT count(*) FROM public.sports_venue_courts c
      WHERE c.venue_id = v.id),
    'active_court_count', (
      SELECT count(*) FROM public.sports_venue_courts c
      WHERE c.venue_id = v.id AND c.is_active),
    'hours_count', (
      SELECT count(DISTINCT h.day_of_week)
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v.id AND h.day_of_week BETWEEN 0 AND 6),
    'amenities_confirmed', v.amenities_confirmed,
    'uses_platform_terms', v.uses_platform_terms,
    'terms_version', (
      SELECT t.version FROM public.sports_venue_terms t
      WHERE t.venue_id = v.id AND t.status = 'active'),
    'status_history', COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC)
      FROM public.sports_venue_status_events e
      WHERE e.venue_id = v.id), '[]'::jsonb)
  ) INTO v_result
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  WHERE v.id = p_venue_id;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';
