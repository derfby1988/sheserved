CREATE TABLE IF NOT EXISTS public.sports_venue_platform_terms (
  singleton_key SMALLINT PRIMARY KEY CHECK (singleton_key = 1),
  id UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  version INT NOT NULL DEFAULT 0 CHECK (version >= 0),
  terms_text TEXT NOT NULL
    CHECK (length(btrim(terms_text)) BETWEEN 1 AND 10000),
  cancellation_cutoff_minutes INT NOT NULL DEFAULT 60
    CHECK (cancellation_cutoff_minutes >= 0),
  is_configured BOOLEAN NOT NULL DEFAULT false,
  edited_by UUID REFERENCES public.users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.sports_venue_platform_terms (
  singleton_key, version, terms_text, cancellation_cutoff_minutes,
  is_configured
) VALUES (
  1, 0, 'เงื่อนไขการใช้สนามมาตรฐานของแพลตฟอร์ม', 60, false
)
ON CONFLICT (singleton_key) DO NOTHING;

ALTER TABLE public.sports_venue_platform_terms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.sports_venue_platform_terms
  FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  singleton_key, id, version, terms_text,
  cancellation_cutoff_minutes, is_configured, updated_at
) ON TABLE public.sports_venue_platform_terms TO anon, authenticated;
DROP POLICY IF EXISTS sports_venue_platform_terms_read_public
  ON public.sports_venue_platform_terms;
CREATE POLICY sports_venue_platform_terms_read_public
  ON public.sports_venue_platform_terms FOR SELECT
  TO anon, authenticated USING (true);

CREATE OR REPLACE FUNCTION public.get_sports_venue_platform_terms(
  p_admin_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_terms public.sports_venue_platform_terms%ROWTYPE;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  SELECT * INTO v_terms
  FROM public.sports_venue_platform_terms
  WHERE singleton_key = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PLATFORM_TERMS_NOT_FOUND';
  END IF;
  RETURN JSONB_BUILD_OBJECT(
    'version', v_terms.version,
    'terms_text', v_terms.terms_text,
    'cancellation_cutoff_minutes', v_terms.cancellation_cutoff_minutes,
    'is_configured', v_terms.is_configured,
    'updated_at', v_terms.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_sports_venue_platform_terms(
  p_admin_id UUID,
  p_terms_text TEXT,
  p_cancellation_cutoff_minutes INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_terms public.sports_venue_platform_terms%ROWTYPE;
  v_terms_text TEXT;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  v_terms_text := btrim(COALESCE(p_terms_text, ''));
  IF length(v_terms_text) NOT BETWEEN 1 AND 10000
     OR v_terms_text = 'เงื่อนไขการใช้สนามมาตรฐานของแพลตฟอร์ม' THEN
    RAISE EXCEPTION 'INVALID_PLATFORM_TERMS';
  END IF;
  IF p_cancellation_cutoff_minutes IS NULL
     OR p_cancellation_cutoff_minutes < 0 THEN
    RAISE EXCEPTION 'INVALID_CUTOFF';
  END IF;

  SELECT * INTO v_terms
  FROM public.sports_venue_platform_terms
  WHERE singleton_key = 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PLATFORM_TERMS_NOT_FOUND';
  END IF;

  IF v_terms.is_configured
     AND v_terms.terms_text = v_terms_text
     AND v_terms.cancellation_cutoff_minutes = p_cancellation_cutoff_minutes THEN
    RETURN JSONB_BUILD_OBJECT(
      'version', v_terms.version,
      'terms_text', v_terms.terms_text,
      'cancellation_cutoff_minutes', v_terms.cancellation_cutoff_minutes,
      'is_configured', v_terms.is_configured,
      'updated_at', v_terms.updated_at
    );
  END IF;

  UPDATE public.sports_venue_platform_terms
  SET version = version + 1,
      terms_text = v_terms_text,
      cancellation_cutoff_minutes = p_cancellation_cutoff_minutes,
      is_configured = true,
      edited_by = p_admin_id,
      updated_at = now()
  WHERE singleton_key = 1
  RETURNING * INTO v_terms;

  RETURN JSONB_BUILD_OBJECT(
    'version', v_terms.version,
    'terms_text', v_terms.terms_text,
    'cancellation_cutoff_minutes', v_terms.cancellation_cutoff_minutes,
    'is_configured', v_terms.is_configured,
    'updated_at', v_terms.updated_at
  );
END;
$$;

UPDATE public.sports_venue_terms t
SET status = 'superseded'
FROM public.sports_venues v
WHERE v.id = t.venue_id
  AND v.uses_platform_terms
  AND t.status = 'active';

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
  IF NOT EXISTS (
    SELECT 1 FROM public.sports_venue_platform_terms
    WHERE singleton_key = 1 AND is_configured
  ) THEN
    RAISE EXCEPTION 'PLATFORM_TERMS_NOT_CONFIGURED';
  END IF;
  UPDATE public.sports_venue_terms
  SET status = 'superseded'
  WHERE venue_id = p_venue_id AND status = 'active';
  UPDATE public.sports_venues
  SET uses_platform_terms = true, updated_at = now()
  WHERE id = p_venue_id;
END;
$$;

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
  IF v_rec.uses_platform_terms THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.sports_venue_platform_terms
      WHERE singleton_key = 1 AND is_configured
    ) THEN
      v_missing := array_append(v_missing, 'terms');
    END IF;
  ELSIF NOT EXISTS (
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

CREATE OR REPLACE VIEW public.sports_venue_terms_public
WITH (security_invoker = on) AS
SELECT t.id, t.venue_id, t.version, t.terms_text,
       t.cancellation_cutoff_minutes, t.created_at
FROM public.sports_venue_terms t
JOIN public.sports_venues v ON v.id = t.venue_id
WHERE t.status = 'active'
  AND v.status = 'approved'
  AND NOT v.uses_platform_terms
UNION ALL
SELECT p.id, v.id AS venue_id, p.version, p.terms_text,
       p.cancellation_cutoff_minutes, p.updated_at AS created_at
FROM public.sports_venues v
CROSS JOIN public.sports_venue_platform_terms p
WHERE v.status = 'approved'
  AND p.singleton_key = 1
  AND p.is_configured
  AND (
    v.uses_platform_terms
    OR NOT EXISTS (
      SELECT 1 FROM public.sports_venue_terms t
      WHERE t.venue_id = v.id AND t.status = 'active'
    )
  );

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
  v_platform_terms_required BOOLEAN := false;
  v_platform_terms_configured BOOLEAN := false;
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

  IF p_idempotency_key IS NOT NULL THEN
    SELECT b.id INTO v_booking_id
    FROM public.sports_venue_bookings b
    WHERE b.user_id = p_user_id AND b.idempotency_key = p_idempotency_key;
    IF v_booking_id IS NOT NULL THEN
      RETURN v_booking_id;
    END IF;
  END IF;

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

  SELECT v.id, v.status, v.name, v.uses_platform_terms
  INTO v_venue
  FROM public.sports_venues v WHERE v.id = v_court.venue_id;
  IF v_venue.id IS NULL OR v_venue.status <> 'approved' THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;

  IF v_venue.uses_platform_terms THEN
    v_platform_terms_required := true;
    SELECT p.version, p.terms_text, p.cancellation_cutoff_minutes,
           p.is_configured
    INTO v_terms
    FROM public.sports_venue_platform_terms p
    WHERE p.singleton_key = 1
    FOR SHARE;
    v_platform_terms_configured := COALESCE(v_terms.is_configured, false);
  ELSE
    SELECT t.version, t.terms_text, t.cancellation_cutoff_minutes
    INTO v_terms
    FROM public.sports_venue_terms t
    WHERE t.venue_id = v_venue.id AND t.status = 'active';
    IF v_terms.version IS NULL THEN
      v_platform_terms_required := true;
      SELECT p.version, p.terms_text, p.cancellation_cutoff_minutes,
             p.is_configured
      INTO v_terms
      FROM public.sports_venue_platform_terms p
      WHERE p.singleton_key = 1
      FOR SHARE;
      v_platform_terms_configured := COALESCE(v_terms.is_configured, false);
    END IF;
  END IF;

  IF v_platform_terms_required AND NOT v_platform_terms_configured THEN
    RAISE EXCEPTION 'PLATFORM_TERMS_NOT_CONFIGURED';
  END IF;

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
  v_terms RECORD;
  v_active_terms_version INT;
  v_terms_text TEXT;
  v_cutoff INT;
  v_platform_terms_required BOOLEAN := false;
  v_platform_terms_configured BOOLEAN := false;
BEGIN
  SELECT b.*, c.name AS court_name, v.name AS venue_name,
         v.uses_platform_terms
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

  IF v_booking.uses_platform_terms THEN
    v_platform_terms_required := true;
    SELECT p.version, p.terms_text, p.cancellation_cutoff_minutes,
           p.is_configured
    INTO v_terms
    FROM public.sports_venue_platform_terms p
    WHERE p.singleton_key = 1
    FOR SHARE;
    v_platform_terms_configured := COALESCE(v_terms.is_configured, false);
  ELSE
    SELECT t.version, t.terms_text, t.cancellation_cutoff_minutes
    INTO v_terms
    FROM public.sports_venue_terms t
    WHERE t.venue_id = v_booking.venue_id AND t.status = 'active';
    IF v_terms.version IS NULL THEN
      v_platform_terms_required := true;
      SELECT p.version, p.terms_text, p.cancellation_cutoff_minutes,
             p.is_configured
      INTO v_terms
      FROM public.sports_venue_platform_terms p
      WHERE p.singleton_key = 1
      FOR SHARE;
      v_platform_terms_configured := COALESCE(v_terms.is_configured, false);
    END IF;
  END IF;

  IF v_platform_terms_required AND NOT v_platform_terms_configured THEN
    RAISE EXCEPTION 'PLATFORM_TERMS_NOT_CONFIGURED';
  END IF;

  IF v_terms.version IS NULL THEN
    v_active_terms_version := 0;
    v_terms_text := 'เงื่อนไขการใช้สนามมาตรฐานของแพลตฟอร์ม';
    v_cutoff := 60;
  ELSE
    v_active_terms_version := v_terms.version;
    v_terms_text := v_terms.terms_text;
    v_cutoff := v_terms.cancellation_cutoff_minutes;
  END IF;

  IF v_active_terms_version <> v_booking.accepted_terms_version
     AND COALESCE(p_terms_version, -1) <> v_active_terms_version THEN
    RAISE EXCEPTION 'TERMS_VERSION_CHANGED';
  END IF;

  IF public.sports_venue_slot_blocked(
       v_booking.court_id, p_starts_at, p_ends_at) THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE';
  END IF;

  UPDATE public.sports_venue_bookings
  SET starts_at = p_starts_at,
      ends_at = p_ends_at,
      accepted_terms_version = v_active_terms_version,
      terms_text_snapshot = CASE
        WHEN v_active_terms_version <> accepted_terms_version
        THEN v_terms_text ELSE terms_text_snapshot END,
      cancellation_cutoff_minutes_snapshot = CASE
        WHEN v_active_terms_version <> accepted_terms_version
        THEN v_cutoff ELSE cancellation_cutoff_minutes_snapshot END,
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
    'terms_version', CASE
      WHEN v.uses_platform_terms THEN (
        SELECT p.version FROM public.sports_venue_platform_terms p
        WHERE p.singleton_key = 1)
      ELSE (
        SELECT t.version FROM public.sports_venue_terms t
        WHERE t.venue_id = v.id AND t.status = 'active')
    END,
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
