-- Phase 21.7.3 — Sports Hub: Book Court supply, owner onboarding and trust
-- baseline.
--
-- Conventions follow the fitness_buddies schema:
--   * custom auth -> every mutating RPC takes an explicit actor id
--     (p_user_id / p_admin_id) and performs its own authorization checks
--   * RLS enabled with SELECT-only policies; all writes go through RPCs
--   * sensitive owner data (contact, evidence) is never exposed through a
--     public SELECT policy -- owner/admin reads go through SECURITY DEFINER
--     functions
--   * durable notifications are written to public.app_notifications

-- ===============
-- Notification categories
-- ===============
DO $$
BEGIN
  ALTER TABLE public.app_notifications
    DROP CONSTRAINT IF EXISTS app_notifications_category_check;
EXCEPTION WHEN undefined_table THEN
  NULL;
END
$$;

DO $$
BEGIN
  IF to_regclass('public.app_notifications') IS NOT NULL THEN
    ALTER TABLE public.app_notifications
      ADD CONSTRAINT app_notifications_category_check
      CHECK (category IN (
        'procurement', 'inventory', 'kpi', 'hr', 'system', 'donation',
        'health', 'admin', 'sport', 'venue_booking', 'coach_booking',
        'venue_supply'
      ));
  END IF;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END
$$;

-- ===============
-- Court unit catalog (admin-managed, per sport + locale)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_court_unit_defaults (
  sport_id UUID NOT NULL REFERENCES public.sports(id) ON DELETE CASCADE,
  locale VARCHAR(10) NOT NULL DEFAULT 'th',
  singular VARCHAR(40) NOT NULL,
  plural VARCHAR(40) NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (sport_id, locale),
  CHECK (length(btrim(singular)) > 0 AND length(btrim(plural)) > 0)
);

-- Seed a generic fallback for every approved sport that has no mapping yet.
-- Runtime code must read this catalog; it must not guess unit names from
-- the sport name.
INSERT INTO public.sports_court_unit_defaults (sport_id, locale, singular, plural)
SELECT s.id, 'th', 'สนาม', 'สนาม'
FROM public.sports s
WHERE s.status = 'approved'
ON CONFLICT (sport_id, locale) DO NOTHING;

INSERT INTO public.sports_court_unit_defaults (sport_id, locale, singular, plural)
SELECT s.id, 'en', 'court', 'courts'
FROM public.sports s
WHERE s.status = 'approved'
ON CONFLICT (sport_id, locale) DO NOTHING;

-- Sport-specific Thai labels for common court sports.
INSERT INTO public.sports_court_unit_defaults (sport_id, locale, singular, plural)
SELECT s.id, 'th', 'คอร์ท', 'คอร์ท'
FROM public.sports s
WHERE s.status = 'approved'
  AND lower(COALESCE(s.name_en, '')) IN (
    'badminton', 'tennis', 'table tennis', 'squash', 'volleyball',
    'basketball', 'futsal', 'football', 'sepak takraw', 'pickleball'
  )
ON CONFLICT (sport_id, locale) DO UPDATE
  SET singular = EXCLUDED.singular, plural = EXCLUDED.plural,
      updated_at = now();

-- ===============
-- Venue owner profiles (one per user, admin-reviewed)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_owner_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.users(id),
  business_name VARCHAR(120) NOT NULL,
  contact_name VARCHAR(120) NOT NULL,
  contact_phone VARCHAR(30) NOT NULL,
  contact_email VARCHAR(200),
  -- Private storage object paths/urls for supporting evidence. Never
  -- exposed through public SELECT.
  evidence JSONB NOT NULL DEFAULT '[]'::jsonb,
  status VARCHAR(10) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','suspended')),
  reviewed_by UUID REFERENCES public.users(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===============
-- Venues
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_profile_id UUID NOT NULL
    REFERENCES public.sports_venue_owner_profiles(id),
  name VARCHAR(120) NOT NULL,
  description VARCHAR(1000),
  province TEXT,
  district TEXT,
  address VARCHAR(500),
  lat DOUBLE PRECISION CHECK (lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION CHECK (lng BETWEEN -180 AND 180),
  -- IANA timezone name; operating hours and availability are entered and
  -- displayed in this local time, while bookings resolve to absolute
  -- timestamps for conflict checks.
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  status VARCHAR(10) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','suspended')),
  reviewed_by UUID REFERENCES public.users(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sports_venues_status
  ON public.sports_venues(status, province);
CREATE INDEX IF NOT EXISTS idx_sports_venues_geo
  ON public.sports_venues(lat, lng) WHERE status = 'approved';

-- Venue-scoped owner/manager membership. The venue owner (via
-- owner_profile) always manages every one of their venues; this table
-- adds invited managers per venue.
CREATE TABLE IF NOT EXISTS public.sports_venue_owner_members (
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id),
  role VARCHAR(10) NOT NULL CHECK (role IN ('owner','manager')),
  invited_by UUID REFERENCES public.users(id),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (venue_id, user_id)
);

-- ===============
-- Venue sports, courts (bookable resources), schedule
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_sports (
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id) ON DELETE CASCADE,
  sport_id UUID NOT NULL REFERENCES public.sports(id),
  -- Per venue+sport unit label override (e.g. "สนาม" vs "คอร์ท"); when NULL
  -- readers fall back to sports_court_unit_defaults.
  unit_label_override VARCHAR(40),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (venue_id, sport_id),
  CHECK (
    unit_label_override IS NULL OR
    length(btrim(unit_label_override)) BETWEEN 1 AND 40
  )
);

CREATE TABLE IF NOT EXISTS public.sports_venue_courts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id) ON DELETE CASCADE,
  sport_id UUID NOT NULL REFERENCES public.sports(id),
  name VARCHAR(80) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  -- Concurrent confirmed bookings the resource can hold per slot.
  capacity INT NOT NULL DEFAULT 1 CHECK (capacity BETWEEN 1 AND 100),
  price_amount NUMERIC(10,2) CHECK (price_amount >= 0),
  pricing_unit VARCHAR(20) NOT NULL DEFAULT 'hour'
    CHECK (pricing_unit IN ('hour','session','match','day')),
  court_type VARCHAR(40),
  indoor BOOLEAN,
  -- 'instant' confirms immediately when the slot is free;
  -- 'owner_approval' creates a pending booking that does not hold the slot.
  booking_approval_mode VARCHAR(15) NOT NULL DEFAULT 'instant'
    CHECK (booking_approval_mode IN ('instant','owner_approval')),
  -- Snapshot of the unit label in use; editing it later never rewrites
  -- existing booking snapshots.
  unit_label VARCHAR(40),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sports_venue_courts_venue
  ON public.sports_venue_courts(venue_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_sports_venue_courts_sport
  ON public.sports_venue_courts(sport_id) WHERE is_active;

CREATE TABLE IF NOT EXISTS public.sports_venue_operating_hours (
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id) ON DELETE CASCADE,
  day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  open_time TIME,
  close_time TIME,
  is_closed BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (venue_id, day_of_week),
  CHECK (is_closed OR (open_time IS NOT NULL AND close_time IS NOT NULL))
);

-- Court-level availability exceptions (blocked maintenance windows or
-- extra open slots outside operating hours).
CREATE TABLE IF NOT EXISTS public.sports_venue_availability (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id UUID NOT NULL REFERENCES public.sports_venue_courts(id)
    ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  kind VARCHAR(10) NOT NULL DEFAULT 'blocked'
    CHECK (kind IN ('blocked','available')),
  note VARCHAR(300),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_sports_venue_availability_court
  ON public.sports_venue_availability(court_id, starts_at, ends_at);

-- Owner-attested amenities; filters must only surface amenities that the
-- owner actually registered.
CREATE TABLE IF NOT EXISTS public.sports_venue_amenities (
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id) ON DELETE CASCADE,
  amenity_key VARCHAR(40) NOT NULL CHECK (amenity_key IN (
    'parking', 'restroom', 'shower', 'ev_charging', 'equipment_rental',
    'lighting', 'locker', 'wifi', 'cafe', 'first_aid'
  )),
  PRIMARY KEY (venue_id, amenity_key)
);

CREATE TABLE IF NOT EXISTS public.sports_venue_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id) ON DELETE CASCADE,
  url VARCHAR(500) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===============
-- Venue terms (versioned; bookings snapshot the accepted version)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_terms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id) ON DELETE CASCADE,
  version INT NOT NULL,
  terms_text TEXT NOT NULL,
  cancellation_cutoff_minutes INT NOT NULL DEFAULT 60
    CHECK (cancellation_cutoff_minutes >= 0),
  status VARCHAR(12) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','superseded')),
  edited_by UUID REFERENCES public.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (venue_id, version)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sports_venue_terms_active
  ON public.sports_venue_terms(venue_id) WHERE status = 'active';

-- ===============
-- Authorization helpers
-- ===============

-- True when p_user_id may manage the venue: the venue owner, an active
-- owner/manager member, or a Sheserved admin.
CREATE OR REPLACE FUNCTION public.is_sports_venue_manager(
  p_venue_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = p_user_id AND u.role = 'admin'
  ) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.sports_venues v
    JOIN public.sports_venue_owner_profiles op
      ON op.id = v.owner_profile_id
    WHERE v.id = p_venue_id AND op.user_id = p_user_id
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.sports_venue_owner_members m
    WHERE m.venue_id = p_venue_id
      AND m.user_id = p_user_id
      AND m.is_active = true
      AND m.role IN ('owner','manager')
  );
END;
$$;

-- Durable notification writer; never throws so business transactions are
-- not aborted by a notification failure.
CREATE OR REPLACE FUNCTION public.sports_hub_notify(
  p_recipient_id UUID,
  p_category TEXT,
  p_event_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_recipient_id IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO public.app_notifications (
    recipient_id, category, event_type, title, body, payload
  ) VALUES (
    p_recipient_id, p_category, p_event_type, p_title, p_body,
    COALESCE(p_payload, '{}'::jsonb)
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'sports_hub_notify failed: %', SQLERRM;
END;
$$;

-- ===============
-- Owner onboarding RPCs
-- ===============

-- Submit (or resubmit after rejection) a venue-owner application.
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
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF length(btrim(COALESCE(p_business_name, ''))) = 0
     OR length(btrim(COALESCE(p_contact_name, ''))) = 0
     OR length(btrim(COALESCE(p_contact_phone, ''))) = 0 THEN
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
      contact_email, evidence, status
    ) VALUES (
      p_user_id, p_business_name, p_contact_name, p_contact_phone,
      p_contact_email, COALESCE(p_evidence, '[]'::jsonb), 'pending'
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
        updated_at = now()
    WHERE id = v_id;
  END IF;

  -- Notify Sheserved admins about the new application.
  INSERT INTO public.app_notifications (
    recipient_id, category, event_type, title, body, payload
  )
  SELECT u.id, 'venue_supply', 'venue_owner.application_submitted',
         'มีคำขอลงทะเบียนเจ้าของสนามใหม่',
         FORMAT('%s ส่งคำขอลงทะเบียนสนาม "%s"',
                p_contact_name, p_business_name),
         JSONB_BUILD_OBJECT(
           'route', '/community/sports/courts/owner/applications',
           'ownerProfileId', v_id
         )
  FROM public.users u
  WHERE u.role = 'admin';

  RETURN v_id;
END;
$$;

-- Admin decision on an owner application.
CREATE OR REPLACE FUNCTION public.review_sports_venue_owner_application(
  p_admin_id UUID,
  p_owner_profile_id UUID,
  p_decision VARCHAR,  -- 'approved' | 'rejected' | 'suspended'
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_business TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_decision NOT IN ('approved','rejected','suspended') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;
  IF p_decision IN ('rejected','suspended')
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  UPDATE public.sports_venue_owner_profiles
  SET status = p_decision,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      rejection_reason = CASE
        WHEN p_decision = 'approved' THEN NULL ELSE p_reason END,
      updated_at = now()
  WHERE id = p_owner_profile_id
  RETURNING user_id, business_name INTO v_user_id, v_business;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'APPLICATION_NOT_FOUND';
  END IF;

  -- Suspension also suspends every venue of the owner.
  IF p_decision = 'suspended' THEN
    UPDATE public.sports_venues
    SET status = 'suspended', updated_at = now()
    WHERE owner_profile_id = p_owner_profile_id
      AND status <> 'suspended';
  END IF;

  v_title := CASE p_decision
    WHEN 'approved' THEN 'คำขอลงทะเบียนสนามได้รับการอนุมัติ'
    WHEN 'rejected' THEN 'คำขอลงทะเบียนสนามถูกปฏิเสธ'
    ELSE 'บัญชีเจ้าของสนามถูกระงับ'
  END;
  v_body := CASE
    WHEN p_decision = 'approved'
      THEN FORMAT('"%s" พร้อมเพิ่มสนามและเปิดรับการจองแล้ว', v_business)
    ELSE FORMAT('เหตุผล: %s', COALESCE(p_reason, 'ไม่ระบุ'))
  END;

  PERFORM public.sports_hub_notify(
    v_user_id,
    'venue_supply',
    'venue_owner.application_' || p_decision,
    v_title,
    v_body,
    JSONB_BUILD_OBJECT(
      'route', '/community/sports/courts/owner/dashboard',
      'ownerProfileId', p_owner_profile_id,
      'status', p_decision,
      'rejectionReason', p_reason
    )
  );
END;
$$;

-- Admin queue of owner applications.
CREATE OR REPLACE FUNCTION public.list_sports_venue_owner_applications(
  p_admin_id UUID,
  p_status VARCHAR DEFAULT 'pending'
)
RETURNS SETOF public.sports_venue_owner_profiles
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  RETURN QUERY
  SELECT * FROM public.sports_venue_owner_profiles
  WHERE status = p_status
  ORDER BY created_at ASC;
END;
$$;

-- Owner reads their own profile (includes private contact/evidence).
CREATE OR REPLACE FUNCTION public.get_my_sports_venue_owner_profile(
  p_user_id UUID
)
RETURNS SETOF public.sports_venue_owner_profiles
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
  SELECT * FROM public.sports_venue_owner_profiles
  WHERE user_id = p_user_id;
END;
$$;

-- ===============
-- Venue / resource management RPCs (owner scope)
-- ===============

-- Create or update a venue. The owner profile must be approved; new venues
-- start as 'pending' and appear publicly only after admin approval.
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
      COALESCE(NULLIF(p_timezone, ''), 'Asia/Bangkok'), 'pending'
    )
    RETURNING id INTO v_id;
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

-- Admin decision on a venue listing.
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
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_decision NOT IN ('approved','rejected','suspended') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;

  UPDATE public.sports_venues
  SET status = p_decision,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      rejection_reason = CASE
        WHEN p_decision = 'approved' THEN NULL ELSE p_reason END,
      updated_at = now()
  WHERE id = p_venue_id
  RETURNING name INTO v_name;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;

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

-- Admin queue of venues pending review.
CREATE OR REPLACE FUNCTION public.list_sports_venues_for_review(
  p_admin_id UUID,
  p_status VARCHAR DEFAULT 'pending'
)
RETURNS SETOF public.sports_venues
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  RETURN QUERY
  SELECT * FROM public.sports_venues
  WHERE status = p_status
  ORDER BY created_at ASC;
END;
$$;

-- Replace the sport set of a venue (venue+sport rows). Unit label
-- overrides are validated per row.
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
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
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

-- Create or update a bookable resource (court/field/room).
CREATE OR REPLACE FUNCTION public.upsert_sports_venue_court(
  p_user_id UUID,
  p_court_id UUID,
  p_venue_id UUID,
  p_sport_id UUID,
  p_name VARCHAR,
  p_capacity INT DEFAULT 1,
  p_price_amount NUMERIC DEFAULT NULL,
  p_pricing_unit VARCHAR DEFAULT 'hour',
  p_court_type VARCHAR DEFAULT NULL,
  p_indoor BOOLEAN DEFAULT NULL,
  p_booking_approval_mode VARCHAR DEFAULT 'instant',
  p_unit_label VARCHAR DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT true
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_label VARCHAR(40);
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF length(btrim(COALESCE(p_name, ''))) = 0 THEN
    RAISE EXCEPTION 'INVALID_COURT';
  END IF;
  IF p_booking_approval_mode NOT IN ('instant','owner_approval') THEN
    RAISE EXCEPTION 'INVALID_APPROVAL_MODE';
  END IF;
  -- The venue must declare the sport before adding resources for it.
  PERFORM 1 FROM public.sports_venue_sports vs
  WHERE vs.venue_id = p_venue_id AND vs.sport_id = p_sport_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SPORT_NOT_ON_VENUE';
  END IF;

  -- Resolve the unit label: explicit label -> venue+sport override ->
  -- sport catalog default -> generic fallback.
  v_label := NULLIF(btrim(p_unit_label), '');
  IF v_label IS NULL THEN
    SELECT NULLIF(btrim(vs.unit_label_override), '') INTO v_label
    FROM public.sports_venue_sports vs
    WHERE vs.venue_id = p_venue_id AND vs.sport_id = p_sport_id;
  END IF;
  IF v_label IS NULL THEN
    SELECT d.singular INTO v_label
    FROM public.sports_court_unit_defaults d
    WHERE d.sport_id = p_sport_id AND d.locale = 'th';
  END IF;
  v_label := COALESCE(v_label, 'สนาม');

  IF p_court_id IS NULL THEN
    INSERT INTO public.sports_venue_courts (
      venue_id, sport_id, name, is_active, capacity, price_amount,
      pricing_unit, court_type, indoor, booking_approval_mode, unit_label
    ) VALUES (
      p_venue_id, p_sport_id, p_name, COALESCE(p_is_active, true),
      COALESCE(p_capacity, 1), p_price_amount,
      COALESCE(p_pricing_unit, 'hour'), p_court_type, p_indoor,
      p_booking_approval_mode, v_label
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.sports_venue_courts
    SET sport_id = p_sport_id,
        name = p_name,
        is_active = COALESCE(p_is_active, is_active),
        capacity = COALESCE(p_capacity, capacity),
        price_amount = p_price_amount,
        pricing_unit = COALESCE(p_pricing_unit, pricing_unit),
        court_type = p_court_type,
        indoor = p_indoor,
        booking_approval_mode = p_booking_approval_mode,
        unit_label = v_label,
        updated_at = now()
    WHERE id = p_court_id AND venue_id = p_venue_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'COURT_NOT_FOUND';
    END IF;
    v_id := p_court_id;
  END IF;
  RETURN v_id;
END;
$$;

-- Replace weekly operating hours for a venue.
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

-- Replace the amenity set of a venue.
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
END;
$$;

-- Publish a new version of venue terms; previous versions are kept so old
-- booking snapshots still resolve. Cancellation cutoff is part of terms.
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
    COALESCE(p_cancellation_cutoff_minutes, 60), 'active', p_user_id
  );
  RETURN v_version;
END;
$$;

-- ===============
-- Owner/manager read RPCs (sensitive data never crosses public SELECT)
-- ===============

-- Venues manageable by the user, with court counts.
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
         v.created_at
  FROM public.sports_venues v
  WHERE public.is_sports_venue_manager(v.id, p_user_id)
  ORDER BY v.created_at DESC;
END;
$$;

-- Full venue detail for its managers (courts, hours, amenities, terms).
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
  WHERE v.id = p_venue_id;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
  RETURN v_result;
END;
$$;

-- Invite or update a venue manager.
CREATE OR REPLACE FUNCTION public.set_sports_venue_member(
  p_user_id UUID,
  p_venue_id UUID,
  p_member_user_id UUID,
  p_role VARCHAR DEFAULT 'manager',
  p_is_active BOOLEAN DEFAULT true
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
  IF p_role NOT IN ('owner','manager') THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;
  INSERT INTO public.sports_venue_owner_members (
    venue_id, user_id, role, invited_by, is_active
  ) VALUES (
    p_venue_id, p_member_user_id, p_role, p_user_id,
    COALESCE(p_is_active, true)
  )
  ON CONFLICT (venue_id, user_id) DO UPDATE
    SET role = EXCLUDED.role, is_active = EXCLUDED.is_active;
END;
$$;

-- ===============
-- Public discovery surface
-- ===============

-- Public venue list/detail: approved venues only, no owner contact data.
CREATE OR REPLACE VIEW public.sports_venues_public
WITH (security_invoker = on) AS
SELECT v.id, v.name, v.description, v.province, v.district, v.address,
       v.lat, v.lng, v.timezone, v.created_at
FROM public.sports_venues v
WHERE v.status = 'approved';

-- Approved courts of approved venues.
CREATE OR REPLACE VIEW public.sports_venue_courts_public
WITH (security_invoker = on) AS
SELECT c.id, c.venue_id, c.sport_id, c.name, c.capacity, c.price_amount,
       c.pricing_unit, c.court_type, c.indoor, c.booking_approval_mode,
       c.unit_label, c.created_at
FROM public.sports_venue_courts c
JOIN public.sports_venues v ON v.id = c.venue_id
WHERE c.is_active AND v.status = 'approved';

CREATE OR REPLACE VIEW public.sports_venue_operating_hours_public
WITH (security_invoker = on) AS
SELECT h.venue_id, h.day_of_week, h.open_time, h.close_time, h.is_closed
FROM public.sports_venue_operating_hours h
JOIN public.sports_venues v ON v.id = h.venue_id
WHERE v.status = 'approved';

CREATE OR REPLACE VIEW public.sports_venue_amenities_public
WITH (security_invoker = on) AS
SELECT a.venue_id, a.amenity_key
FROM public.sports_venue_amenities a
JOIN public.sports_venues v ON v.id = a.venue_id
WHERE v.status = 'approved';

CREATE OR REPLACE VIEW public.sports_venue_photos_public
WITH (security_invoker = on) AS
SELECT p.id, p.venue_id, p.url, p.sort_order
FROM public.sports_venue_photos p
JOIN public.sports_venues v ON v.id = p.venue_id
WHERE v.status = 'approved';

CREATE OR REPLACE VIEW public.sports_venue_sports_public
WITH (security_invoker = on) AS
SELECT vs.venue_id, vs.sport_id, vs.unit_label_override
FROM public.sports_venue_sports vs
JOIN public.sports_venues v ON v.id = vs.venue_id
WHERE v.status = 'approved';

CREATE OR REPLACE VIEW public.sports_venue_terms_public
WITH (security_invoker = on) AS
SELECT t.id, t.venue_id, t.version, t.terms_text,
       t.cancellation_cutoff_minutes, t.created_at
FROM public.sports_venue_terms t
JOIN public.sports_venues v ON v.id = t.venue_id
WHERE t.status = 'active' AND v.status = 'approved';

-- ===============
-- RLS: SELECT-only policies; all writes via RPC
-- ===============
ALTER TABLE public.sports_court_unit_defaults ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_owner_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_owner_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_sports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_courts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_operating_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_amenities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_terms ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_court_unit_defaults' AND policyname='sports_court_unit_defaults_select_all') THEN
    CREATE POLICY sports_court_unit_defaults_select_all
      ON public.sports_court_unit_defaults FOR SELECT USING (true);
  END IF;

  -- Owner profiles carry contact + evidence: no public row-level read.
  -- Access goes through get_my_sports_venue_owner_profile /
  -- list_sports_venue_owner_applications (SECURITY DEFINER, authorized).

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venues' AND policyname='sports_venues_select_all') THEN
    -- Public sees approved venues only; pending/rejected/suspended rows are
    -- reachable through manager/admin RPCs.
    CREATE POLICY sports_venues_select_all
      ON public.sports_venues FOR SELECT USING (status = 'approved');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_owner_members' AND policyname='sports_venue_owner_members_select_all') THEN
    CREATE POLICY sports_venue_owner_members_select_all
      ON public.sports_venue_owner_members FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_sports' AND policyname='sports_venue_sports_select_all') THEN
    CREATE POLICY sports_venue_sports_select_all
      ON public.sports_venue_sports FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_courts' AND policyname='sports_venue_courts_select_all') THEN
    CREATE POLICY sports_venue_courts_select_all
      ON public.sports_venue_courts FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_operating_hours' AND policyname='sports_venue_operating_hours_select_all') THEN
    CREATE POLICY sports_venue_operating_hours_select_all
      ON public.sports_venue_operating_hours FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_availability' AND policyname='sports_venue_availability_select_all') THEN
    CREATE POLICY sports_venue_availability_select_all
      ON public.sports_venue_availability FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_amenities' AND policyname='sports_venue_amenities_select_all') THEN
    CREATE POLICY sports_venue_amenities_select_all
      ON public.sports_venue_amenities FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_photos' AND policyname='sports_venue_photos_select_all') THEN
    CREATE POLICY sports_venue_photos_select_all
      ON public.sports_venue_photos FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_terms' AND policyname='sports_venue_terms_select_all') THEN
    CREATE POLICY sports_venue_terms_select_all
      ON public.sports_venue_terms FOR SELECT USING (true);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
