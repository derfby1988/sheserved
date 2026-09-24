-- Phase 21.7.5/21.7.6/21.7.7 — Sports Hub: venue bookings, owner approval,
-- cancellation policy and reviews.
--
-- Contract highlights (see Match_Sport_PLAN.md 21.6):
--   * instant mode creates 'confirmed' bookings atomically after a locked
--     capacity/overlap recheck; owner_approval mode creates 'pending' rows
--     that never hold the slot
--   * terms are versioned per venue; every booking snapshots the accepted
--     version, text and cancellation cutoff; a stale version is rejected
--     with TERMS_VERSION_CHANGED so the client re-consents
--   * every state change writes sports_venue_booking_events and sends
--     durable app_notifications under category 'venue_booking'
--   * pending rows expire at their slot start; confirmed rows become
--     'completed' via a trusted transition only

-- ===============
-- Tables
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id UUID NOT NULL REFERENCES public.sports_venue_courts(id),
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id),
  sport_id UUID NOT NULL REFERENCES public.sports(id),
  user_id UUID NOT NULL REFERENCES public.users(id),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending','confirmed','completed','cancelled','rejected','expired')),
  booking_approval_mode_snapshot VARCHAR(15) NOT NULL
    CHECK (booking_approval_mode_snapshot IN ('instant','owner_approval')),
  price_amount_snapshot NUMERIC(10,2),
  pricing_unit_snapshot VARCHAR(20),
  unit_label_snapshot VARCHAR(40),
  accepted_terms_version INT NOT NULL DEFAULT 0,
  terms_text_snapshot TEXT,
  cancellation_cutoff_minutes_snapshot INT NOT NULL DEFAULT 60,
  terms_accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_by UUID REFERENCES public.users(id),
  cancellation_reason VARCHAR(300),
  cancelled_at TIMESTAMPTZ,
  decided_by UUID REFERENCES public.users(id),
  decided_at TIMESTAMPTZ,
  rejection_reason VARCHAR(300),
  idempotency_key VARCHAR(80),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

-- User-scoped idempotency: a retried submit with the same key returns the
-- same booking instead of creating a duplicate.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sports_venue_bookings_idem
  ON public.sports_venue_bookings(user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_court_slot
  ON public.sports_venue_bookings(court_id, starts_at, ends_at)
  WHERE status = 'confirmed';
CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_user
  ON public.sports_venue_bookings(user_id, status, starts_at);
CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_venue
  ON public.sports_venue_bookings(venue_id, status, starts_at);
CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_pending_expiry
  ON public.sports_venue_bookings(starts_at) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS public.sports_venue_booking_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL
    REFERENCES public.sports_venue_bookings(id) ON DELETE CASCADE,
  event_type VARCHAR(40) NOT NULL,
  actor_id UUID REFERENCES public.users(id),
  previous_status VARCHAR(10),
  new_status VARCHAR(10),
  old_starts_at TIMESTAMPTZ,
  old_ends_at TIMESTAMPTZ,
  new_starts_at TIMESTAMPTZ,
  new_ends_at TIMESTAMPTZ,
  reason VARCHAR(300),
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_events_booking
  ON public.sports_venue_booking_events(booking_id, created_at);

-- ===============
-- Reviews
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id),
  court_id UUID REFERENCES public.sports_venue_courts(id),
  -- One review per completed booking, enforced by the unique index below.
  booking_id UUID NOT NULL REFERENCES public.sports_venue_bookings(id),
  user_id UUID NOT NULL REFERENCES public.users(id),
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment VARCHAR(500),
  status VARCHAR(10) NOT NULL DEFAULT 'published'
    CHECK (status IN ('published','hidden','rejected')),
  reported_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sports_venue_reviews_booking
  ON public.sports_venue_reviews(booking_id);
CREATE INDEX IF NOT EXISTS idx_sports_venue_reviews_venue
  ON public.sports_venue_reviews(venue_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.sports_venue_review_tag_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  label_th VARCHAR(60) NOT NULL,
  label_en VARCHAR(60),
  is_active BOOLEAN NOT NULL DEFAULT true,
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.sports_venue_review_tag_catalog
  (label_th, label_en, display_order)
SELECT * FROM (VALUES
  ('สะอาด/ดูแลดี', 'Clean & well maintained', 1),
  ('บริการพนักงานดี', 'Great staff service', 2),
  ('คุ้มค่าราคา', 'Good value', 3),
  ('ที่จอดรถสะดวก', 'Convenient parking', 4),
  ('สิ่งอำนวยความสะดวกครบ', 'Well equipped', 5)
) AS seed(label_th, label_en, display_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sports_venue_review_tag_catalog
);

CREATE TABLE IF NOT EXISTS public.sports_venue_review_tags (
  review_id UUID NOT NULL
    REFERENCES public.sports_venue_reviews(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL
    REFERENCES public.sports_venue_review_tag_catalog(id),
  PRIMARY KEY (review_id, tag_id)
);

CREATE TABLE IF NOT EXISTS public.sports_venue_review_custom_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id UUID NOT NULL
    REFERENCES public.sports_venue_reviews(id) ON DELETE CASCADE,
  label VARCHAR(60) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Public review surfaces: published reviews only. Aggregates are computed
-- server-side; client-sent aggregate values are never trusted.
CREATE OR REPLACE VIEW public.sports_venue_reviews_public
WITH (security_invoker = on) AS
SELECT r.id, r.venue_id, r.court_id, r.booking_id, r.user_id,
       NULLIF(btrim(CONCAT_WS(' ', u.first_name, u.last_name)), '')
         AS user_display_name,
       u.profile_image_url AS user_avatar_url,
       r.rating, r.comment, r.created_at
FROM public.sports_venue_reviews r
LEFT JOIN public.users u ON u.id = r.user_id
WHERE r.status = 'published';

CREATE OR REPLACE VIEW public.sports_venue_review_summary
WITH (security_invoker = on) AS
SELECT venue_id,
       ROUND(AVG(rating)::numeric, 2) AS average_rating,
       COUNT(*) AS review_count
FROM public.sports_venue_reviews
WHERE status = 'published'
GROUP BY venue_id;

-- ===============
-- Helpers
-- ===============

-- Confirmed bookings overlapping the slot on the same court. Pending rows
-- never hold capacity.
CREATE OR REPLACE FUNCTION public.sports_venue_confirmed_overlap_count(
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_exclude_booking_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.sports_venue_bookings b
  WHERE b.court_id = p_court_id
    AND b.status = 'confirmed'
    AND b.starts_at < p_ends_at
    AND b.ends_at > p_starts_at
    AND (p_exclude_booking_id IS NULL OR b.id <> p_exclude_booking_id);
  RETURN COALESCE(v_count, 0);
END;
$$;

-- A slot is blocked when a 'blocked' availability window overlaps it or it
-- falls outside the venue operating hours (in the venue local timezone).
-- Venues with no operating-hours rows are treated as always open so that
-- onboarding without a schedule does not silently block booking.
CREATE OR REPLACE FUNCTION public.sports_venue_slot_blocked(
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue_id UUID;
  v_tz TEXT;
  v_dow INT;
  v_local_start TIME;
  v_local_end TIME;
BEGIN
  SELECT c.venue_id INTO v_venue_id
  FROM public.sports_venue_courts c WHERE c.id = p_court_id;
  IF v_venue_id IS NULL THEN
    RETURN true;
  END IF;

  SELECT v.timezone INTO v_tz
  FROM public.sports_venues v WHERE v.id = v_venue_id;
  v_tz := COALESCE(v_tz, 'Asia/Bangkok');

  IF EXISTS (
    SELECT 1 FROM public.sports_venue_availability a
    WHERE a.court_id = p_court_id
      AND a.kind = 'blocked'
      AND a.starts_at < p_ends_at
      AND a.ends_at > p_starts_at
  ) THEN
    RETURN true;
  END IF;

  -- Slots that cross midnight in venue-local time are not supported.
  IF (p_ends_at AT TIME ZONE v_tz)::date
     <> (p_starts_at AT TIME ZONE v_tz)::date THEN
    RETURN true;
  END IF;

  -- No operating hours configured -> treat as always open.
  IF NOT EXISTS (
    SELECT 1 FROM public.sports_venue_operating_hours h
    WHERE h.venue_id = v_venue_id
  ) THEN
    RETURN false;
  END IF;

  v_dow := EXTRACT(ISODOW FROM p_starts_at AT TIME ZONE v_tz)::int % 7;
  v_local_start := (p_starts_at AT TIME ZONE v_tz)::time;
  v_local_end := (p_ends_at AT TIME ZONE v_tz)::time;

  -- The whole slot must fit inside one open window of that day.
  RETURN NOT EXISTS (
    SELECT 1 FROM public.sports_venue_operating_hours h
    WHERE h.venue_id = v_venue_id
      AND h.day_of_week = v_dow
      AND h.is_closed = false
      AND h.open_time <= v_local_start
      AND h.close_time >= v_local_end
  );
END;
$$;

-- Notify every active manager of a venue plus the venue owner.
CREATE OR REPLACE FUNCTION public.notify_sports_venue_managers(
  p_venue_id UUID,
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
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT uid FROM (
      SELECT op.user_id AS uid
      FROM public.sports_venues v
      JOIN public.sports_venue_owner_profiles op
        ON op.id = v.owner_profile_id
      WHERE v.id = p_venue_id
      UNION
      SELECT m.user_id FROM public.sports_venue_owner_members m
      WHERE m.venue_id = p_venue_id AND m.is_active = true
    ) managers
  LOOP
    PERFORM public.sports_hub_notify(
      r.uid, 'venue_booking', p_event_type, p_title, p_body, p_payload);
  END LOOP;
END;
$$;

-- Write a booking event row.
CREATE OR REPLACE FUNCTION public.log_sports_venue_booking_event(
  p_booking_id UUID,
  p_event_type VARCHAR,
  p_actor_id UUID,
  p_previous_status VARCHAR DEFAULT NULL,
  p_new_status VARCHAR DEFAULT NULL,
  p_reason VARCHAR DEFAULT NULL,
  p_old_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_old_ends_at TIMESTAMPTZ DEFAULT NULL,
  p_new_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_new_ends_at TIMESTAMPTZ DEFAULT NULL,
  p_meta JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.sports_venue_booking_events (
    booking_id, event_type, actor_id, previous_status, new_status,
    old_starts_at, old_ends_at, new_starts_at, new_ends_at, reason, meta
  ) VALUES (
    p_booking_id, p_event_type, p_actor_id, p_previous_status, p_new_status,
    p_old_starts_at, p_old_ends_at, p_new_starts_at, p_new_ends_at,
    p_reason, COALESCE(p_meta, '{}'::jsonb)
  );
END;
$$;

-- ===============
-- Create booking (instant confirm or owner-approval pending)
-- ===============
CREATE OR REPLACE FUNCTION public.create_sports_venue_booking(
  p_user_id UUID,
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_terms_version INT,
  p_idempotency_key VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court RECORD;
  v_venue RECORD;
  v_terms RECORD;
  v_booking_id UUID;
  v_status VARCHAR(10);
  v_terms_version INT;
  v_terms_text TEXT;
  v_cutoff INT;
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

  -- Idempotent retry: same user + key returns the existing booking.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT b.id INTO v_booking_id
    FROM public.sports_venue_bookings b
    WHERE b.user_id = p_user_id AND b.idempotency_key = p_idempotency_key;
    IF v_booking_id IS NOT NULL THEN
      RETURN v_booking_id;
    END IF;
  END IF;

  -- Lock the court row so concurrent creates serialize on the resource.
  SELECT c.id, c.venue_id, c.sport_id, c.capacity, c.price_amount,
         c.pricing_unit, c.unit_label, c.booking_approval_mode, c.is_active,
         c.name AS court_name
  INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id
  FOR UPDATE;

  IF v_court.id IS NULL OR NOT v_court.is_active THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;

  SELECT v.id, v.status, v.name INTO v_venue
  FROM public.sports_venues v WHERE v.id = v_court.venue_id;
  IF v_venue.id IS NULL OR v_venue.status <> 'approved' THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;

  -- Terms resolution: the client must have accepted the current active
  -- version. Venues without custom terms use platform base terms
  -- (version 0) with the default cutoff.
  SELECT t.version, t.terms_text, t.cancellation_cutoff_minutes
  INTO v_terms
  FROM public.sports_venue_terms t
  WHERE t.venue_id = v_venue.id AND t.status = 'active';

  IF v_terms.version IS NULL THEN
    v_terms_version := 0;
    v_terms_text := 'เงื่อนไขการใช้สนามมาตรฐานของแพลตฟอร์ม';
    v_cutoff := 60;
  ELSE
    v_terms_version := v_terms.version;
    v_terms_text := v_terms.terms_text;
    v_cutoff := v_terms.cancellation_cutoff_minutes;
  END IF;

  IF COALESCE(p_terms_version, -1) <> v_terms_version THEN
    RAISE EXCEPTION 'TERMS_VERSION_CHANGED';
  END IF;

  IF v_court.booking_approval_mode = 'instant' THEN
    -- Atomic availability: the court row is locked above, so the overlap
    -- count is stable within this transaction.
    IF public.sports_venue_slot_blocked(
         p_court_id, p_starts_at, p_ends_at) THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE';
    END IF;
    IF public.sports_venue_confirmed_overlap_count(
         p_court_id, p_starts_at, p_ends_at) >= v_court.capacity THEN
      RAISE EXCEPTION 'SLOT_FULL';
    END IF;
    v_status := 'confirmed';
  ELSE
    -- Pending requests never hold the slot; availability is rechecked
    -- atomically on approve.
    v_status := 'pending';
  END IF;

  INSERT INTO public.sports_venue_bookings (
    court_id, venue_id, sport_id, user_id, starts_at, ends_at, status,
    booking_approval_mode_snapshot, price_amount_snapshot,
    pricing_unit_snapshot, unit_label_snapshot,
    accepted_terms_version, terms_text_snapshot,
    cancellation_cutoff_minutes_snapshot, terms_accepted_at,
    idempotency_key
  ) VALUES (
    p_court_id, v_venue.id, v_court.sport_id, p_user_id,
    p_starts_at, p_ends_at, v_status,
    v_court.booking_approval_mode, v_court.price_amount,
    v_court.pricing_unit, v_court.unit_label,
    v_terms_version, v_terms_text, v_cutoff, now(),
    p_idempotency_key
  )
  RETURNING id INTO v_booking_id;

  PERFORM public.log_sports_venue_booking_event(
    v_booking_id,
    CASE WHEN v_status = 'confirmed'
         THEN 'created_confirmed' ELSE 'created_pending' END,
    p_user_id, NULL, v_status,
    p_new_starts_at := p_starts_at, p_new_ends_at := p_ends_at
  );

  IF v_status = 'confirmed' THEN
    PERFORM public.sports_hub_notify(
      p_user_id, 'venue_booking', 'venue_booking.confirmed',
      'การจองสนามยืนยันแล้ว',
      FORMAT('%s — %s', v_venue.name, v_court.court_name),
      JSONB_BUILD_OBJECT(
        'route', '/community/sports/courts/' || v_venue.id::text,
        'bookingId', v_booking_id, 'venueId', v_venue.id,
        'courtId', p_court_id, 'status', 'confirmed'));
    PERFORM public.notify_sports_venue_managers(
      v_venue.id, 'venue_booking.confirmed',
      'มีการจองสนามใหม่',
      FORMAT('%s — %s', v_venue.name, v_court.court_name),
      JSONB_BUILD_OBJECT(
        'route', '/community/sports/courts/owner/dashboard',
        'bookingId', v_booking_id, 'venueId', v_venue.id));
  ELSE
    PERFORM public.sports_hub_notify(
      p_user_id, 'venue_booking', 'venue_booking.requested',
      'ส่งคำขอจองสนามแล้ว',
      FORMAT('%s — %s รอเจ้าของอนุมัติ', v_venue.name, v_court.court_name),
      JSONB_BUILD_OBJECT(
        'route', '/community/sports/courts/' || v_venue.id::text,
        'bookingId', v_booking_id, 'venueId', v_venue.id,
        'courtId', p_court_id, 'status', 'pending'));
    PERFORM public.notify_sports_venue_managers(
      v_venue.id, 'venue_booking.requested',
      'มีคำขอจองรออนุมัติ',
      FORMAT('%s — %s', v_venue.name, v_court.court_name),
      JSONB_BUILD_OBJECT(
        'route', '/community/sports/courts/owner/dashboard',
        'bookingId', v_booking_id, 'venueId', v_venue.id));
  END IF;

  RETURN v_booking_id;
END;
$$;

-- ===============
-- Cancellation (booker before cutoff; owner/manager with reason)
-- ===============
CREATE OR REPLACE FUNCTION public.cancel_sports_venue_booking(
  p_user_id UUID,
  p_booking_id UUID,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_is_booker BOOLEAN;
  v_is_manager BOOLEAN;
  v_cutoff_at TIMESTAMPTZ;
  v_venue_name TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT b.*, v.name AS venue_name, c.name AS court_name
  INTO v_booking
  FROM public.sports_venue_bookings b
  JOIN public.sports_venues v ON v.id = b.venue_id
  JOIN public.sports_venue_courts c ON c.id = b.court_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.status NOT IN ('pending','confirmed') THEN
    RAISE EXCEPTION 'BOOKING_NOT_CANCELLABLE';
  END IF;

  v_is_booker := v_booking.user_id = p_user_id;
  v_is_manager := public.is_sports_venue_manager(v_booking.venue_id, p_user_id);
  v_venue_name := v_booking.venue_name;

  IF NOT v_is_booker AND NOT v_is_manager THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  IF v_is_booker AND NOT v_is_manager THEN
    v_cutoff_at := v_booking.starts_at
      - make_interval(mins => v_booking.cancellation_cutoff_minutes_snapshot);
    IF now() >= v_cutoff_at THEN
      RAISE EXCEPTION 'CUTOFF_PASSED';
    END IF;
  ELSE
    -- Manager/owner cancellation always requires a reason.
    IF length(btrim(COALESCE(p_reason, ''))) = 0 THEN
      RAISE EXCEPTION 'REASON_REQUIRED';
    END IF;
  END IF;

  UPDATE public.sports_venue_bookings
  SET status = 'cancelled',
      cancelled_by = p_user_id,
      cancellation_reason = p_reason,
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_booking_id;

  PERFORM public.log_sports_venue_booking_event(
    p_booking_id, 'cancelled', p_user_id, v_booking.status, 'cancelled',
    p_reason := p_reason);

  -- Notify the counterparty.
  IF v_is_booker THEN
    PERFORM public.notify_sports_venue_managers(
      v_booking.venue_id, 'venue_booking.cancelled',
      'ผู้จองยกเลิกการจอง',
      FORMAT('%s — %s', v_venue_name, v_booking.court_name),
      JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                         'venueId', v_booking.venue_id));
  ELSE
    PERFORM public.sports_hub_notify(
      v_booking.user_id, 'venue_booking', 'venue_booking.cancelled',
      'การจองของคุณถูกยกเลิกโดยสนาม',
      FORMAT('%s — %s เหตุผล: %s', v_venue_name, v_booking.court_name,
             COALESCE(p_reason, 'ไม่ระบุ')),
      JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                         'venueId', v_booking.venue_id));
  END IF;
END;
$$;

-- ===============
-- Owner approval: approve / reject a pending booking
-- ===============
CREATE OR REPLACE FUNCTION public.decide_sports_venue_booking(
  p_user_id UUID,
  p_booking_id UUID,
  p_decision VARCHAR,  -- 'approve' | 'reject'
  p_reason VARCHAR DEFAULT NULL
)
RETURNS TEXT  -- 'confirmed' | 'rejected' | 'conflict'
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_capacity INT;
BEGIN
  SELECT b.*, c.capacity, c.name AS court_name, v.name AS venue_name
  INTO v_booking
  FROM public.sports_venue_bookings b
  JOIN public.sports_venue_courts c ON c.id = b.court_id
  JOIN public.sports_venues v ON v.id = b.venue_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b, c;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF NOT public.is_sports_venue_manager(v_booking.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF v_booking.status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;
  IF p_decision NOT IN ('approve','reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;

  IF p_decision = 'reject' THEN
    IF length(btrim(COALESCE(p_reason, ''))) = 0 THEN
      RAISE EXCEPTION 'REASON_REQUIRED';
    END IF;
    UPDATE public.sports_venue_bookings
    SET status = 'rejected', decided_by = p_user_id, decided_at = now(),
        rejection_reason = p_reason, updated_at = now()
    WHERE id = p_booking_id;

    PERFORM public.log_sports_venue_booking_event(
      p_booking_id, 'rejected', p_user_id, 'pending', 'rejected',
      p_reason := p_reason);
    PERFORM public.sports_hub_notify(
      v_booking.user_id, 'venue_booking', 'venue_booking.rejected',
      'คำขอจองถูกปฏิเสธ',
      FORMAT('%s — %s เหตุผล: %s', v_booking.venue_name,
             v_booking.court_name, p_reason),
      JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                         'venueId', v_booking.venue_id));
    RETURN 'rejected';
  END IF;

  -- Approve: the court row is locked via FOR UPDATE OF c, so the overlap
  -- recheck below is atomic against concurrent creates/approvals.
  IF public.sports_venue_slot_blocked(
       v_booking.court_id, v_booking.starts_at, v_booking.ends_at)
     OR public.sports_venue_confirmed_overlap_count(
          v_booking.court_id, v_booking.starts_at, v_booking.ends_at,
          p_booking_id) >= v_booking.capacity THEN
    -- Slot got taken while pending: keep the booking pending and let the
    -- booker move to another slot on the same court or cancel.
    PERFORM public.log_sports_venue_booking_event(
      p_booking_id, 'approve_conflict', p_user_id, 'pending', 'pending');
    PERFORM public.sports_hub_notify(
      v_booking.user_id, 'venue_booking', 'venue_booking.slot_conflict',
      'ช่วงเวลาที่ขอถูกใช้แล้ว',
      FORMAT('%s — %s กรุณาเลือกเวลาใหม่หรือยกเลิกคำขอ',
             v_booking.venue_name, v_booking.court_name),
      JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                         'venueId', v_booking.venue_id,
                         'action', 'change_slot_or_cancel'));
    RETURN 'conflict';
  END IF;

  UPDATE public.sports_venue_bookings
  SET status = 'confirmed', decided_by = p_user_id, decided_at = now(),
      updated_at = now()
  WHERE id = p_booking_id;

  PERFORM public.log_sports_venue_booking_event(
    p_booking_id, 'approved', p_user_id, 'pending', 'confirmed');
  PERFORM public.sports_hub_notify(
    v_booking.user_id, 'venue_booking', 'venue_booking.confirmed',
    'คำขอจองได้รับการอนุมัติ',
    FORMAT('%s — %s', v_booking.venue_name, v_booking.court_name),
    JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                       'venueId', v_booking.venue_id));
  RETURN 'confirmed';
END;
$$;

-- ===============
-- Change the slot of a pending booking (same court only)
-- ===============
CREATE OR REPLACE FUNCTION public.change_pending_venue_booking_slot(
  p_user_id UUID,
  p_booking_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_terms_version INT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_active_terms_version INT;
BEGIN
  SELECT b.*, c.name AS court_name, v.name AS venue_name
  INTO v_booking
  FROM public.sports_venue_bookings b
  JOIN public.sports_venue_courts c ON c.id = b.court_id
  JOIN public.sports_venues v ON v.id = b.venue_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.user_id <> p_user_id THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_booking.status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at
     OR p_ends_at <= now() THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;

  -- Re-consent when the venue terms version moved since the request.
  SELECT t.version INTO v_active_terms_version
  FROM public.sports_venue_terms t
  WHERE t.venue_id = v_booking.venue_id AND t.status = 'active';
  v_active_terms_version := COALESCE(v_active_terms_version, 0);
  IF v_active_terms_version <> v_booking.accepted_terms_version THEN
    IF COALESCE(p_terms_version, -1) <> v_active_terms_version THEN
      RAISE EXCEPTION 'TERMS_VERSION_CHANGED';
    END IF;
  END IF;

  -- New slot must not already be fully booked by confirmed rows.
  IF public.sports_venue_slot_blocked(
       v_booking.court_id, p_starts_at, p_ends_at) THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE';
  END IF;

  UPDATE public.sports_venue_bookings
  SET starts_at = p_starts_at, ends_at = p_ends_at,
      accepted_terms_version = v_active_terms_version,
      terms_accepted_at = CASE
        WHEN v_active_terms_version <> accepted_terms_version THEN now()
        ELSE terms_accepted_at END,
      updated_at = now()
  WHERE id = p_booking_id;

  PERFORM public.log_sports_venue_booking_event(
    p_booking_id, 'slot_changed', p_user_id, 'pending', 'pending',
    p_old_starts_at := v_booking.starts_at,
    p_old_ends_at := v_booking.ends_at,
    p_new_starts_at := p_starts_at,
    p_new_ends_at := p_ends_at);

  PERFORM public.notify_sports_venue_managers(
    v_booking.venue_id, 'venue_booking.slot_changed',
    'คำขอจองเปลี่ยนเวลา',
    FORMAT('%s — %s ผู้จองขอเปลี่ยนเวลา กรุณาพิจารณาใหม่',
           v_booking.venue_name, v_booking.court_name),
    JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                       'venueId', v_booking.venue_id));
END;
$$;

-- ===============
-- Trusted status transitions (housekeeping)
-- ===============

-- Expire pending requests whose slot already started.
CREATE OR REPLACE FUNCTION public.expire_pending_sports_venue_bookings()
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
    UPDATE public.sports_venue_bookings
    SET status = 'expired', updated_at = now()
    WHERE status = 'pending' AND starts_at <= now()
    RETURNING id, user_id, venue_id
  LOOP
    PERFORM public.log_sports_venue_booking_event(
      r.id, 'expired', NULL, 'pending', 'expired');
    PERFORM public.sports_hub_notify(
      r.user_id, 'venue_booking', 'venue_booking.expired',
      'คำขอจองหมดอายุ',
      'คำขอจองของคุณหมดอายุเนื่องจากถึงเวลาเริ่มแล้ว',
      JSONB_BUILD_OBJECT('bookingId', r.id, 'venueId', r.venue_id));
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- Mark confirmed bookings completed once their slot ends. Only this
-- trusted transition may set 'completed'; clients cannot self-certify.
CREATE OR REPLACE FUNCTION public.complete_sports_venue_bookings()
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
    UPDATE public.sports_venue_bookings
    SET status = 'completed', updated_at = now()
    WHERE status = 'confirmed' AND ends_at <= now()
    RETURNING id, user_id, venue_id
  LOOP
    PERFORM public.log_sports_venue_booking_event(
      r.id, 'completed', NULL, 'confirmed', 'completed');
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- ===============
-- Read RPCs (bookings carry user ids -> no public table read)
-- ===============

-- Busy ranges for read-only availability display: confirmed bookings plus
-- blocked availability windows. No user identity is exposed.
CREATE OR REPLACE FUNCTION public.get_court_availability(
  p_court_id UUID,
  p_from TIMESTAMPTZ,
  p_to TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue_id UUID;
  v_result JSONB;
BEGIN
  SELECT c.venue_id INTO v_venue_id
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id AND c.is_active;
  IF v_venue_id IS NULL THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.sports_venues v
    WHERE v.id = v_venue_id AND v.status = 'approved'
  ) THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;

  SELECT JSONB_BUILD_OBJECT(
    'courtId', p_court_id,
    'booked', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
               'startsAt', b.starts_at, 'endsAt', b.ends_at))
      FROM public.sports_venue_bookings b
      WHERE b.court_id = p_court_id
        AND b.status = 'confirmed'
        AND b.starts_at < p_to AND b.ends_at > p_from), '[]'::jsonb),
    'blocked', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
               'startsAt', a.starts_at, 'endsAt', a.ends_at))
      FROM public.sports_venue_availability a
      WHERE a.court_id = p_court_id
        AND a.kind = 'blocked'
        AND a.starts_at < p_to AND a.ends_at > p_from), '[]'::jsonb),
    'hours', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
               'day', h.day_of_week, 'open', h.open_time,
               'close', h.close_time, 'closed', h.is_closed))
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v_venue_id), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- Current user's bookings (with venue/court display fields).
CREATE OR REPLACE FUNCTION public.list_my_sports_venue_bookings(
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
        'id', b.id, 'courtId', b.court_id, 'venueId', b.venue_id,
        'sportId', b.sport_id, 'startsAt', b.starts_at, 'endsAt', b.ends_at,
        'status', b.status, 'venueName', v.name, 'courtName', c.name,
        'unitLabel', b.unit_label_snapshot,
        'priceAmount', b.price_amount_snapshot,
        'pricingUnit', b.pricing_unit_snapshot,
        'approvalMode', b.booking_approval_mode_snapshot,
        'termsVersion', b.accepted_terms_version,
        'cancellationCutoffMinutes', b.cancellation_cutoff_minutes_snapshot,
        'rejectionReason', b.rejection_reason,
        'cancellationReason', b.cancellation_reason,
        'createdAt', b.created_at
      ) AS row
      FROM public.sports_venue_bookings b
      JOIN public.sports_venues v ON v.id = b.venue_id
      JOIN public.sports_venue_courts c ON c.id = b.court_id
      WHERE b.user_id = p_user_id
        AND (p_statuses IS NULL OR b.status = ANY(p_statuses))
      ORDER BY b.starts_at DESC
      LIMIT 200
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- Venue booking queue for owners/managers.
CREATE OR REPLACE FUNCTION public.list_sports_venue_bookings_for_manager(
  p_user_id UUID,
  p_venue_id UUID,
  p_statuses VARCHAR[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'starts_at' ASC) FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', b.id, 'courtId', b.court_id, 'venueId', b.venue_id,
        'sportId', b.sport_id, 'startsAt', b.starts_at, 'endsAt', b.ends_at,
        'status', b.status, 'courtName', c.name,
        'unitLabel', b.unit_label_snapshot,
        'priceAmount', b.price_amount_snapshot,
        'pricingUnit', b.pricing_unit_snapshot,
        'approvalMode', b.booking_approval_mode_snapshot,
        'bookerName', NULLIF(btrim(
          CONCAT_WS(' ', u.first_name, u.last_name)), ''),
        'createdAt', b.created_at
      ) AS row
      FROM public.sports_venue_bookings b
      JOIN public.sports_venue_courts c ON c.id = b.court_id
      LEFT JOIN public.users u ON u.id = b.user_id
      WHERE b.venue_id = p_venue_id
        AND (p_statuses IS NULL OR b.status = ANY(p_statuses))
      ORDER BY b.starts_at ASC
      LIMIT 300
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- ===============
-- Reviews
-- ===============

CREATE OR REPLACE FUNCTION public.submit_sports_venue_review(
  p_user_id UUID,
  p_booking_id UUID,
  p_rating INT,
  p_comment VARCHAR DEFAULT NULL,
  p_tag_ids UUID[] DEFAULT NULL,
  p_custom_tags TEXT[] DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_review_id UUID;
  v_tag_count INT;
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

  v_tag_count := COALESCE(array_length(p_tag_ids, 1), 0)
               + COALESCE(array_length(p_custom_tags, 1), 0);
  IF v_tag_count > 5 THEN
    RAISE EXCEPTION 'TOO_MANY_TAGS';
  END IF;

  SELECT b.* INTO v_booking
  FROM public.sports_venue_bookings b
  WHERE b.id = p_booking_id
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.user_id <> p_user_id THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.status <> 'completed' THEN
    RAISE EXCEPTION 'BOOKING_NOT_COMPLETED';
  END IF;
  -- Owners/managers may not review their own venue.
  IF public.is_sports_venue_manager(v_booking.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'SELF_REVIEW_NOT_ALLOWED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.sports_venue_reviews r
    WHERE r.booking_id = p_booking_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_REVIEWED';
  END IF;

  -- Standard tags must come from the catalog.
  IF p_tag_ids IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_tag_ids) t
    WHERE NOT EXISTS (
      SELECT 1 FROM public.sports_venue_review_tag_catalog c
      WHERE c.id = t AND c.is_active
    )
  ) THEN
    RAISE EXCEPTION 'INVALID_TAG';
  END IF;

  -- Review + tags are written atomically in this transaction.
  INSERT INTO public.sports_venue_reviews (
    venue_id, court_id, booking_id, user_id, rating, comment
  ) VALUES (
    v_booking.venue_id, v_booking.court_id, p_booking_id, p_user_id,
    p_rating, NULLIF(btrim(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;

  INSERT INTO public.sports_venue_review_tags (review_id, tag_id)
  SELECT v_review_id, t FROM unnest(COALESCE(p_tag_ids, ARRAY[]::uuid[])) t
  ON CONFLICT DO NOTHING;

  INSERT INTO public.sports_venue_review_custom_tags (review_id, label)
  SELECT v_review_id, btrim(label)
  FROM unnest(COALESCE(p_custom_tags, ARRAY[]::text[])) AS label
  WHERE length(btrim(label)) BETWEEN 1 AND 60;

  RETURN v_review_id;
END;
$$;

-- Report a review for moderation.
CREATE OR REPLACE FUNCTION public.report_sports_venue_review(
  p_user_id UUID,
  p_review_id UUID,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  UPDATE public.sports_venue_reviews
  SET reported_count = reported_count + 1, updated_at = now()
  WHERE id = p_review_id AND status = 'published';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'REVIEW_NOT_FOUND';
  END IF;
END;
$$;

-- Admin moderation: hide or reject a review (removed from public listing
-- and aggregates), or restore to published.
CREATE OR REPLACE FUNCTION public.moderate_sports_venue_review(
  p_admin_id UUID,
  p_review_id UUID,
  p_action VARCHAR,  -- 'hide' | 'reject' | 'publish'
  p_reason VARCHAR DEFAULT NULL
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
    ELSE NULL
  END;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  UPDATE public.sports_venue_reviews
  SET status = v_status, updated_at = now()
  WHERE id = p_review_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'REVIEW_NOT_FOUND';
  END IF;
END;
$$;

-- Reviews of the current user joined with their tags, for eligibility
-- checks ("one review per booking").
CREATE OR REPLACE FUNCTION public.list_my_sports_venue_review_booking_ids(
  p_user_id UUID
)
RETURNS SETOF UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT r.booking_id FROM public.sports_venue_reviews r
  WHERE r.user_id = p_user_id;
END;
$$;

-- Tag catalog for the review sheet.
CREATE OR REPLACE FUNCTION public.list_sports_venue_review_tags()
RETURNS SETOF public.sports_venue_review_tag_catalog
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.sports_venue_review_tag_catalog
  WHERE is_active
  ORDER BY display_order, label_th;
END;
$$;

-- ===============
-- RLS
-- ===============
ALTER TABLE public.sports_venue_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_booking_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_review_tag_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_review_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_review_custom_tags ENABLE ROW LEVEL SECURITY;

-- bookings/events carry user identity -> no public SELECT policy; reads go
-- through the authorized RPCs above. Reviews are read through
-- sports_venue_reviews_public (published only).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_reviews' AND policyname='sports_venue_reviews_select_all') THEN
    CREATE POLICY sports_venue_reviews_select_all
      ON public.sports_venue_reviews FOR SELECT
      USING (status = 'published');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_review_tag_catalog' AND policyname='sports_venue_review_tag_catalog_select_all') THEN
    CREATE POLICY sports_venue_review_tag_catalog_select_all
      ON public.sports_venue_review_tag_catalog FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_review_tags' AND policyname='sports_venue_review_tags_select_all') THEN
    CREATE POLICY sports_venue_review_tags_select_all
      ON public.sports_venue_review_tags FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports_venue_review_custom_tags' AND policyname='sports_venue_review_custom_tags_select_all') THEN
    CREATE POLICY sports_venue_review_custom_tags_select_all
      ON public.sports_venue_review_custom_tags FOR SELECT USING (true);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
