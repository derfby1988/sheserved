-- Phase 21.7.8/21.7.9 — Sports Hub: coach supply, discovery, booking
-- requests and reviews.
--
-- Same conventions as the venue supply migration: custom auth with explicit
-- actor ids, SELECT-only RLS, mutations through SECURITY DEFINER RPCs, and
-- durable notifications under category 'coach_booking' / 'coach_supply'.

-- ===============
-- Notification category
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
        'venue_supply', 'coach_supply'
      ));
  END IF;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END
$$;

-- ===============
-- Tables
-- ===============

-- A user may be both a player and a coach, so coach identity lives in its
-- own profile table rather than on users.
CREATE TABLE IF NOT EXISTS public.coach_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.users(id),
  display_name VARCHAR(120) NOT NULL,
  bio VARCHAR(1000),
  -- IANA timezone of the coach/service area; availability is entered and
  -- displayed in this local time.
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  hourly_rate NUMERIC(10,2) CHECK (hourly_rate >= 0),
  teaching_mode VARCHAR(10) NOT NULL DEFAULT 'onsite'
    CHECK (teaching_mode IN ('onsite','online','both')),
  status VARCHAR(10) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','suspended')),
  is_verified BOOLEAN NOT NULL DEFAULT false,
  reviewed_by UUID REFERENCES public.users(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coach_sports (
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  sport_id UUID NOT NULL REFERENCES public.sports(id),
  skill_levels VARCHAR(10)[] NOT NULL DEFAULT '{}', -- e.g. {beginner,intermediate,advanced}
  specialties TEXT[] NOT NULL DEFAULT '{}',
  PRIMARY KEY (coach_id, sport_id)
);

CREATE TABLE IF NOT EXISTS public.coach_certifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  issuer VARCHAR(120),
  issued_year SMALLINT CHECK (issued_year BETWEEN 1950 AND 2100),
  -- Private storage path; not part of the public profile surface.
  document_url VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coach_service_areas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  province TEXT,
  district TEXT,
  lat DOUBLE PRECISION CHECK (lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION CHECK (lng BETWEEN -180 AND 180),
  radius_km NUMERIC(6,2) CHECK (radius_km > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coach_service_areas_coach
  ON public.coach_service_areas(coach_id);

CREATE TABLE IF NOT EXISTS public.coach_availability (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_coach_availability_coach
  ON public.coach_availability(coach_id, day_of_week)
  WHERE is_active;

CREATE TABLE IF NOT EXISTS public.coach_booking_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id),
  user_id UUID NOT NULL REFERENCES public.users(id),
  sport_id UUID NOT NULL REFERENCES public.sports(id),
  -- Snapshot of what the user requested so later profile edits never
  -- rewrite history.
  teaching_mode_snapshot VARCHAR(10)
    CHECK (teaching_mode_snapshot IN ('onsite','online')),
  hourly_rate_snapshot NUMERIC(10,2),
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  message VARCHAR(500),
  status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending','confirmed','completed','cancelled','rejected','expired')),
  decided_by UUID REFERENCES public.users(id),
  decided_at TIMESTAMPTZ,
  rejection_reason VARCHAR(300),
  cancelled_by UUID REFERENCES public.users(id),
  cancellation_reason VARCHAR(300),
  cancelled_at TIMESTAMPTZ,
  idempotency_key VARCHAR(80),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_coach_booking_requests_idem
  ON public.coach_booking_requests(user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_coach_booking_requests_coach
  ON public.coach_booking_requests(coach_id, status, starts_at);
CREATE INDEX IF NOT EXISTS idx_coach_booking_requests_user
  ON public.coach_booking_requests(user_id, status, starts_at);

CREATE TABLE IF NOT EXISTS public.coach_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id),
  booking_id UUID NOT NULL
    REFERENCES public.coach_booking_requests(id),
  user_id UUID NOT NULL REFERENCES public.users(id),
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment VARCHAR(500),
  status VARCHAR(10) NOT NULL DEFAULT 'published'
    CHECK (status IN ('published','hidden','rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_coach_reviews_booking
  ON public.coach_reviews(booking_id);

-- ===============
-- Public discovery surface
-- ===============

CREATE OR REPLACE VIEW public.coach_profiles_public
WITH (security_invoker = on) AS
SELECT p.id, p.user_id, p.display_name, p.bio, p.timezone,
       p.hourly_rate, p.teaching_mode, p.is_verified, p.created_at,
       u.profile_image_url AS avatar_url
FROM public.coach_profiles p
LEFT JOIN public.users u ON u.id = p.user_id
WHERE p.status = 'approved';

CREATE OR REPLACE VIEW public.coach_sports_public
WITH (security_invoker = on) AS
SELECT s.coach_id, s.sport_id, s.skill_levels, s.specialties
FROM public.coach_sports s
JOIN public.coach_profiles p ON p.id = s.coach_id
WHERE p.status = 'approved';

CREATE OR REPLACE VIEW public.coach_service_areas_public
WITH (security_invoker = on) AS
SELECT a.id, a.coach_id, a.province, a.district, a.lat, a.lng, a.radius_km
FROM public.coach_service_areas a
JOIN public.coach_profiles p ON p.id = a.coach_id
WHERE p.status = 'approved';

CREATE OR REPLACE VIEW public.coach_availability_public
WITH (security_invoker = on) AS
SELECT a.coach_id, a.day_of_week, a.start_time, a.end_time
FROM public.coach_availability a
JOIN public.coach_profiles p ON p.id = a.coach_id
WHERE p.status = 'approved' AND a.is_active;

CREATE OR REPLACE VIEW public.coach_reviews_public
WITH (security_invoker = on) AS
SELECT r.id, r.coach_id, r.booking_id, r.user_id,
       NULLIF(btrim(CONCAT_WS(' ', u.first_name, u.last_name)), '')
         AS user_display_name,
       u.profile_image_url AS user_avatar_url,
       r.rating, r.comment, r.created_at
FROM public.coach_reviews r
LEFT JOIN public.users u ON u.id = r.user_id
WHERE r.status = 'published';

CREATE OR REPLACE VIEW public.coach_review_summary
WITH (security_invoker = on) AS
SELECT coach_id,
       ROUND(AVG(rating)::numeric, 2) AS average_rating,
       COUNT(*) AS review_count
FROM public.coach_reviews
WHERE status = 'published'
GROUP BY coach_id;

-- ===============
-- Coach onboarding RPCs
-- ===============

-- Create or update the caller's coach profile. New profiles start as
-- 'pending' and appear publicly only after admin approval.
CREATE OR REPLACE FUNCTION public.upsert_coach_profile(
  p_user_id UUID,
  p_display_name VARCHAR,
  p_bio VARCHAR DEFAULT NULL,
  p_timezone VARCHAR DEFAULT 'Asia/Bangkok',
  p_hourly_rate NUMERIC DEFAULT NULL,
  p_teaching_mode VARCHAR DEFAULT 'onsite'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_status VARCHAR(10);
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF length(btrim(COALESCE(p_display_name, ''))) = 0 THEN
    RAISE EXCEPTION 'INVALID_PROFILE';
  END IF;
  IF p_teaching_mode NOT IN ('onsite','online','both') THEN
    RAISE EXCEPTION 'INVALID_TEACHING_MODE';
  END IF;

  SELECT id, status INTO v_id, v_status
  FROM public.coach_profiles WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_status = 'suspended' THEN
    RAISE EXCEPTION 'COACH_SUSPENDED';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.coach_profiles (
      user_id, display_name, bio, timezone, hourly_rate, teaching_mode,
      status
    ) VALUES (
      p_user_id, p_display_name, p_bio,
      COALESCE(NULLIF(p_timezone, ''), 'Asia/Bangkok'),
      p_hourly_rate, p_teaching_mode, 'pending'
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.coach_profiles
    SET display_name = p_display_name,
        bio = p_bio,
        timezone = COALESCE(NULLIF(p_timezone, ''), timezone),
        hourly_rate = p_hourly_rate,
        teaching_mode = p_teaching_mode,
        updated_at = now()
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_coach_sports(
  p_user_id UUID,
  p_sports JSONB  -- [{"sport_id": uuid, "skill_levels": [...], "specialties": [...]}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT id INTO v_coach_id FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;

  DELETE FROM public.coach_sports WHERE coach_id = v_coach_id;
  INSERT INTO public.coach_sports (coach_id, sport_id, skill_levels, specialties)
  SELECT v_coach_id,
         (item->>'sport_id')::uuid,
         COALESCE((
           SELECT array_agg(x::varchar) FILTER (
             WHERE x IN ('beginner','intermediate','advanced','pro'))
           FROM jsonb_array_elements_text(item->'skill_levels') x
         ), '{}'),
         COALESCE((
           SELECT array_agg(btrim(x)) FILTER (WHERE length(btrim(x)) > 0)
           FROM jsonb_array_elements_text(item->'specialties') x
         ), '{}')
  FROM jsonb_array_elements(COALESCE(p_sports, '[]'::jsonb)) AS item
  WHERE (item->>'sport_id') IS NOT NULL
  ON CONFLICT (coach_id, sport_id) DO UPDATE
    SET skill_levels = EXCLUDED.skill_levels,
        specialties = EXCLUDED.specialties;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_coach_availability(
  p_user_id UUID,
  p_windows JSONB  -- [{"day":0-6,"start":"HH:MM","end":"HH:MM"}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT id INTO v_coach_id FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;

  DELETE FROM public.coach_availability WHERE coach_id = v_coach_id;
  INSERT INTO public.coach_availability (
    coach_id, day_of_week, start_time, end_time
  )
  SELECT v_coach_id,
         (item->>'day')::smallint,
         (item->>'start')::time,
         (item->>'end')::time
  FROM jsonb_array_elements(COALESCE(p_windows, '[]'::jsonb)) AS item
  WHERE (item->>'day') IS NOT NULL
    AND (item->>'start') IS NOT NULL
    AND (item->>'end') IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_coach_service_areas(
  p_user_id UUID,
  p_areas JSONB  -- [{"province":..,"district":..,"lat":..,"lng":..,"radiusKm":..}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT id INTO v_coach_id FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;

  DELETE FROM public.coach_service_areas WHERE coach_id = v_coach_id;
  INSERT INTO public.coach_service_areas (
    coach_id, province, district, lat, lng, radius_km
  )
  SELECT v_coach_id,
         item->>'province', item->>'district',
         (item->>'lat')::double precision,
         (item->>'lng')::double precision,
         (item->>'radiusKm')::numeric
  FROM jsonb_array_elements(COALESCE(p_areas, '[]'::jsonb)) AS item;
END;
$$;

-- Admin review of a coach profile.
CREATE OR REPLACE FUNCTION public.review_coach_profile(
  p_admin_id UUID,
  p_coach_id UUID,
  p_decision VARCHAR,  -- 'approved' | 'suspended' | 'pending'
  p_verified BOOLEAN DEFAULT NULL,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_decision NOT IN ('approved','suspended','pending') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;

  UPDATE public.coach_profiles
  SET status = p_decision,
      is_verified = COALESCE(p_verified, is_verified),
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      rejection_reason = p_reason,
      updated_at = now()
  WHERE id = p_coach_id
  RETURNING user_id, display_name INTO v_user_id, v_name;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;

  PERFORM public.sports_hub_notify(
    v_user_id, 'coach_supply', 'coach.profile_' || p_decision,
    CASE p_decision
      WHEN 'approved' THEN 'โปรไฟล์โค้ชได้รับการอนุมัติ'
      WHEN 'suspended' THEN 'โปรไฟล์โค้ชถูกระงับ'
      ELSE 'โปรไฟล์โค้ชอยู่ระหว่างตรวจสอบ'
    END,
    CASE
      WHEN p_decision = 'approved'
        THEN FORMAT('"%s" แสดงในรายการโค้ชแล้ว', v_name)
      ELSE FORMAT('%s — %s', v_name, COALESCE(p_reason, ''))
    END,
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'coachId', p_coach_id, 'status', p_decision));
END;
$$;

CREATE OR REPLACE FUNCTION public.list_coach_applications(
  p_admin_id UUID,
  p_status VARCHAR DEFAULT 'pending'
)
RETURNS SETOF public.coach_profiles
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
  SELECT * FROM public.coach_profiles
  WHERE status = p_status
  ORDER BY created_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_coach_profile(p_user_id UUID)
RETURNS SETOF public.coach_profiles
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
  SELECT * FROM public.coach_profiles WHERE user_id = p_user_id;
END;
$$;

-- ===============
-- Coach booking requests
-- ===============

CREATE OR REPLACE FUNCTION public.create_coach_booking_request(
  p_user_id UUID,
  p_coach_id UUID,
  p_sport_id UUID,
  p_teaching_mode VARCHAR,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_message VARCHAR DEFAULT NULL,
  p_idempotency_key VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_request_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;
  IF p_ends_at <= now() THEN
    RAISE EXCEPTION 'SLOT_IN_PAST';
  END IF;
  IF p_teaching_mode NOT IN ('onsite','online') THEN
    RAISE EXCEPTION 'INVALID_TEACHING_MODE';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT r.id INTO v_request_id
    FROM public.coach_booking_requests r
    WHERE r.user_id = p_user_id AND r.idempotency_key = p_idempotency_key;
    IF v_request_id IS NOT NULL THEN
      RETURN v_request_id;
    END IF;
  END IF;

  -- Lock the coach profile so duplicate concurrent requests serialize.
  SELECT p.id, p.user_id AS coach_user_id, p.status, p.display_name,
         p.timezone, p.hourly_rate, p.teaching_mode
  INTO v_coach
  FROM public.coach_profiles p
  WHERE p.id = p_coach_id
  FOR UPDATE;

  IF v_coach.id IS NULL OR v_coach.status <> 'approved' THEN
    RAISE EXCEPTION 'COACH_NOT_AVAILABLE';
  END IF;
  IF v_coach.coach_user_id = p_user_id THEN
    RAISE EXCEPTION 'SELF_REQUEST_NOT_ALLOWED';
  END IF;

  -- The coach must offer the sport and the requested teaching mode.
  PERFORM 1 FROM public.coach_sports s
  WHERE s.coach_id = p_coach_id AND s.sport_id = p_sport_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SPORT_NOT_OFFERED';
  END IF;
  IF v_coach.teaching_mode <> 'both'
     AND v_coach.teaching_mode <> p_teaching_mode THEN
    RAISE EXCEPTION 'TEACHING_MODE_NOT_OFFERED';
  END IF;

  -- Coach must cover the slot in their availability (coach-local time).
  IF EXISTS (SELECT 1 FROM public.coach_availability a
             WHERE a.coach_id = p_coach_id) THEN
    IF (p_ends_at AT TIME ZONE v_coach.timezone)::date
       <> (p_starts_at AT TIME ZONE v_coach.timezone)::date THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.coach_availability a
      WHERE a.coach_id = p_coach_id
        AND a.is_active
        AND a.day_of_week =
            EXTRACT(ISODOW FROM p_starts_at AT TIME ZONE v_coach.timezone)::int % 7
        AND a.start_time <= (p_starts_at AT TIME ZONE v_coach.timezone)::time
        AND a.end_time >= (p_ends_at AT TIME ZONE v_coach.timezone)::time
    ) THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE';
    END IF;
  END IF;

  -- No overlapping active request for the same coach.
  IF EXISTS (
    SELECT 1 FROM public.coach_booking_requests r
    WHERE r.coach_id = p_coach_id
      AND r.status IN ('pending','confirmed')
      AND r.starts_at < p_ends_at AND r.ends_at > p_starts_at
  ) THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE';
  END IF;

  INSERT INTO public.coach_booking_requests (
    coach_id, user_id, sport_id, teaching_mode_snapshot,
    hourly_rate_snapshot, timezone, starts_at, ends_at, message,
    status, idempotency_key
  ) VALUES (
    p_coach_id, p_user_id, p_sport_id, p_teaching_mode,
    v_coach.hourly_rate, v_coach.timezone, p_starts_at, p_ends_at,
    p_message, 'pending', p_idempotency_key
  )
  RETURNING id INTO v_request_id;

  PERFORM public.sports_hub_notify(
    v_coach.coach_user_id, 'coach_booking', 'coach_booking.requested',
    'มีคำขอจองโค้ชใหม่',
    FORMAT('%s มีคำขอฝึกซ้อมใหม่', v_coach.display_name),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', v_request_id, 'coachId', p_coach_id));
  PERFORM public.sports_hub_notify(
    p_user_id, 'coach_booking', 'coach_booking.requested',
    'ส่งคำขอจองโค้ชแล้ว',
    FORMAT('รอ %s ตอบรับ', v_coach.display_name),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', v_request_id, 'coachId', p_coach_id));

  RETURN v_request_id;
END;
$$;

-- Coach approves or rejects a pending request.
CREATE OR REPLACE FUNCTION public.decide_coach_booking_request(
  p_user_id UUID,
  p_request_id UUID,
  p_decision VARCHAR,  -- 'approve' | 'reject'
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
BEGIN
  SELECT r.*, p.user_id AS coach_user_id, p.display_name AS coach_name
  INTO v_request
  FROM public.coach_booking_requests r
  JOIN public.coach_profiles p ON p.id = r.coach_id
  WHERE r.id = p_request_id
  FOR UPDATE OF r;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND';
  END IF;
  IF v_request.coach_user_id <> p_user_id
     AND NOT public.is_admin_role(p_user_id) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'REQUEST_NOT_PENDING';
  END IF;
  IF p_decision NOT IN ('approve','reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;

  IF p_decision = 'reject' AND
     length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  UPDATE public.coach_booking_requests
  SET status = CASE WHEN p_decision = 'approve' THEN 'confirmed'
                    ELSE 'rejected' END,
      decided_by = p_user_id, decided_at = now(),
      rejection_reason = CASE WHEN p_decision = 'reject' THEN p_reason END,
      updated_at = now()
  WHERE id = p_request_id;

  PERFORM public.sports_hub_notify(
    v_request.user_id, 'coach_booking',
    'coach_booking.' || CASE WHEN p_decision = 'approve'
                             THEN 'confirmed' ELSE 'rejected' END,
    CASE WHEN p_decision = 'approve'
         THEN 'โค้ชตอบรับคำขอแล้ว' ELSE 'โค้ชปฏิเสธคำขอ' END,
    CASE WHEN p_decision = 'approve'
         THEN FORMAT('%s ยืนยันนัดฝึกซ้อม', v_request.coach_name)
         ELSE FORMAT('%s — เหตุผล: %s', v_request.coach_name,
                     COALESCE(p_reason, 'ไม่ระบุ')) END,
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', p_request_id,
                       'coachId', v_request.coach_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_coach_booking_request(
  p_user_id UUID,
  p_request_id UUID,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_is_requester BOOLEAN;
  v_is_coach BOOLEAN;
BEGIN
  SELECT r.*, p.user_id AS coach_user_id, p.display_name AS coach_name
  INTO v_request
  FROM public.coach_booking_requests r
  JOIN public.coach_profiles p ON p.id = r.coach_id
  WHERE r.id = p_request_id
  FOR UPDATE OF r;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND';
  END IF;
  IF v_request.status NOT IN ('pending','confirmed') THEN
    RAISE EXCEPTION 'REQUEST_NOT_CANCELLABLE';
  END IF;

  v_is_requester := v_request.user_id = p_user_id;
  v_is_coach := v_request.coach_user_id = p_user_id
                OR public.is_admin_role(p_user_id);
  IF NOT v_is_requester AND NOT v_is_coach THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_is_coach AND NOT v_is_requester
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  UPDATE public.coach_booking_requests
  SET status = 'cancelled', cancelled_by = p_user_id,
      cancellation_reason = p_reason, cancelled_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  PERFORM public.sports_hub_notify(
    CASE WHEN v_is_requester THEN v_request.coach_user_id
         ELSE v_request.user_id END,
    'coach_booking', 'coach_booking.cancelled',
    'นัดฝึกซ้อมถูกยกเลิก',
    FORMAT('%s — %s', v_request.coach_name,
           COALESCE(p_reason, 'ผู้ใช้ยกเลิก')),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', p_request_id,
                       'coachId', v_request.coach_id));
END;
$$;

-- Trusted housekeeping: pending requests expire at slot start; confirmed
-- requests complete at slot end.
CREATE OR REPLACE FUNCTION public.expire_pending_coach_booking_requests()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_count INT := 0;
BEGIN
  FOR r IN
    UPDATE public.coach_booking_requests
    SET status = 'expired', updated_at = now()
    WHERE status = 'pending' AND starts_at <= now()
    RETURNING id, user_id, coach_id
  LOOP
    PERFORM public.sports_hub_notify(
      r.user_id, 'coach_booking', 'coach_booking.expired',
      'คำขอจองโค้ชหมดอายุ',
      'คำขอของคุณหมดอายุเนื่องจากถึงเวลาเริ่มแล้ว',
      JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                         'requestId', r.id, 'coachId', r.coach_id));
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_coach_booking_requests()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE public.coach_booking_requests
  SET status = 'completed', updated_at = now()
  WHERE status = 'confirmed' AND ends_at <= now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ===============
-- Coach reviews (only after a completed request)
-- ===============
CREATE OR REPLACE FUNCTION public.submit_coach_review(
  p_user_id UUID,
  p_request_id UUID,
  p_rating INT,
  p_comment VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_review_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'INVALID_RATING';
  END IF;
  IF p_comment IS NOT NULL AND length(p_comment) > 500 THEN
    RAISE EXCEPTION 'COMMENT_TOO_LONG';
  END IF;

  SELECT r.*, p.user_id AS coach_user_id INTO v_request
  FROM public.coach_booking_requests r
  JOIN public.coach_profiles p ON p.id = r.coach_id
  WHERE r.id = p_request_id
  FOR UPDATE OF r;

  IF v_request.id IS NULL OR v_request.user_id <> p_user_id THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND';
  END IF;
  IF v_request.status <> 'completed' THEN
    RAISE EXCEPTION 'REQUEST_NOT_COMPLETED';
  END IF;
  IF v_request.coach_user_id = p_user_id THEN
    RAISE EXCEPTION 'SELF_REVIEW_NOT_ALLOWED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.coach_reviews r WHERE r.booking_id = p_request_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_REVIEWED';
  END IF;

  INSERT INTO public.coach_reviews (
    coach_id, booking_id, user_id, rating, comment
  ) VALUES (
    v_request.coach_id, p_request_id, p_user_id,
    p_rating, NULLIF(btrim(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;
  RETURN v_review_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.moderate_coach_review(
  p_admin_id UUID,
  p_review_id UUID,
  p_action VARCHAR  -- 'hide' | 'reject' | 'publish'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status VARCHAR(10);
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  v_status := CASE p_action
    WHEN 'hide' THEN 'hidden'
    WHEN 'reject' THEN 'rejected'
    WHEN 'publish' THEN 'published'
    ELSE NULL END;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;
  UPDATE public.coach_reviews
  SET status = v_status, updated_at = now()
  WHERE id = p_review_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'REVIEW_NOT_FOUND';
  END IF;
END;
$$;

-- Coach's own request queue.
CREATE OR REPLACE FUNCTION public.list_coach_booking_requests_for_coach(
  p_user_id UUID,
  p_statuses VARCHAR[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT id INTO v_coach_id FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'starts_at' ASC) FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', r.id, 'coachId', r.coach_id, 'sportId', r.sport_id,
        'startsAt', r.starts_at, 'endsAt', r.ends_at, 'status', r.status,
        'teachingMode', r.teaching_mode_snapshot,
        'hourlyRate', r.hourly_rate_snapshot,
        'message', r.message,
        'requesterName', NULLIF(btrim(
          CONCAT_WS(' ', u.first_name, u.last_name)), ''),
        'createdAt', r.created_at
      ) AS row
      FROM public.coach_booking_requests r
      LEFT JOIN public.users u ON u.id = r.user_id
      WHERE r.coach_id = v_coach_id
        AND (p_statuses IS NULL OR r.status = ANY(p_statuses))
      ORDER BY r.starts_at ASC
      LIMIT 300
    ) rows
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_coach_booking_requests(
  p_user_id UUID,
  p_statuses VARCHAR[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'starts_at' DESC) FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', r.id, 'coachId', r.coach_id, 'sportId', r.sport_id,
        'startsAt', r.starts_at, 'endsAt', r.ends_at, 'status', r.status,
        'teachingMode', r.teaching_mode_snapshot,
        'hourlyRate', r.hourly_rate_snapshot,
        'coachName', p.display_name,
        'rejectionReason', r.rejection_reason,
        'cancellationReason', r.cancellation_reason,
        'createdAt', r.created_at
      ) AS row
      FROM public.coach_booking_requests r
      JOIN public.coach_profiles p ON p.id = r.coach_id
      WHERE r.user_id = p_user_id
        AND (p_statuses IS NULL OR r.status = ANY(p_statuses))
      ORDER BY r.starts_at DESC
      LIMIT 200
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- ===============
-- RLS: SELECT-only policies; all writes via RPC
-- ===============
ALTER TABLE public.coach_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_sports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_certifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_service_areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_booking_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_reviews ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  -- coach_profiles exposes only approved rows publicly; full rows are read
  -- through get_my_coach_profile / admin RPCs.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='coach_profiles' AND policyname='coach_profiles_select_all') THEN
    CREATE POLICY coach_profiles_select_all
      ON public.coach_profiles FOR SELECT USING (status = 'approved');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='coach_sports' AND policyname='coach_sports_select_all') THEN
    CREATE POLICY coach_sports_select_all
      ON public.coach_sports FOR SELECT USING (true);
  END IF;
  -- certifications may carry document paths: no public select.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='coach_service_areas' AND policyname='coach_service_areas_select_all') THEN
    CREATE POLICY coach_service_areas_select_all
      ON public.coach_service_areas FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='coach_availability' AND policyname='coach_availability_select_all') THEN
    CREATE POLICY coach_availability_select_all
      ON public.coach_availability FOR SELECT USING (true);
  END IF;
  -- requests carry user identity: no public select; reads via RPCs.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='coach_reviews' AND policyname='coach_reviews_select_all') THEN
    CREATE POLICY coach_reviews_select_all
      ON public.coach_reviews FOR SELECT USING (status = 'published');
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
