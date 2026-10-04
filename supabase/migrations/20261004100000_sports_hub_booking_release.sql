-- Phase 21.7.18: recurring weekly booking release.
--
-- Owners may configure a recurring weekly release (day of week + local time
-- in the venue timezone + booking window >= 7 days) at the venue level.
-- Courts inherit the venue rule by default and may override it with
-- 'always_open' (unlimited advance booking) or a 'custom' triple. With no
-- effective rule, advance booking is unlimited — matching pre-21.7.18
-- behaviour, so the migration alone changes nothing until an owner opts in.
--
-- The gate is computed from the CURRENT rule at booking time (no release
-- ledger): a slot starting at S is bookable once the earliest weekly
-- release R satisfying local(R) > local(S) - window AND R <= S has passed
-- (`opensAt` semantics, half-open coverage [R, R+N)). The check runs after
-- the idempotency lookup so retries return the original booking even if
-- the rule has since changed, and it is not re-applied when a pending
-- booking is approved. Locks are taken court -> venue (FOR SHARE) so
-- concurrent bookings stay parallel while venue rule updates wait for
-- in-flight booking transactions.

ALTER TABLE public.sports_venues
  ADD COLUMN IF NOT EXISTS booking_release_day_of_week SMALLINT,
  ADD COLUMN IF NOT EXISTS booking_release_time TIME,
  ADD COLUMN IF NOT EXISTS booking_release_window_days SMALLINT;

ALTER TABLE public.sports_venues
  DROP CONSTRAINT IF EXISTS sports_venues_booking_release_chk;
ALTER TABLE public.sports_venues
  ADD CONSTRAINT sports_venues_booking_release_chk CHECK (
    (booking_release_day_of_week IS NULL
       AND booking_release_time IS NULL
       AND booking_release_window_days IS NULL)
    OR (booking_release_day_of_week IS NOT NULL
        AND booking_release_day_of_week BETWEEN 0 AND 6
        AND booking_release_time IS NOT NULL
        AND booking_release_window_days IS NOT NULL
        AND booking_release_window_days >= 7)
  );

ALTER TABLE public.sports_venue_courts
  ADD COLUMN IF NOT EXISTS booking_release_mode VARCHAR(20) NOT NULL
    DEFAULT 'inherit',
  ADD COLUMN IF NOT EXISTS booking_release_day_of_week SMALLINT,
  ADD COLUMN IF NOT EXISTS booking_release_time TIME,
  ADD COLUMN IF NOT EXISTS booking_release_window_days SMALLINT;

ALTER TABLE public.sports_venue_courts
  DROP CONSTRAINT IF EXISTS sports_venue_courts_booking_release_mode_chk;
ALTER TABLE public.sports_venue_courts
  ADD CONSTRAINT sports_venue_courts_booking_release_mode_chk CHECK (
    booking_release_mode IN ('inherit', 'always_open', 'custom')
  );

ALTER TABLE public.sports_venue_courts
  DROP CONSTRAINT IF EXISTS sports_venue_courts_booking_release_chk;
ALTER TABLE public.sports_venue_courts
  ADD CONSTRAINT sports_venue_courts_booking_release_chk CHECK (
    (booking_release_mode = 'custom'
       AND booking_release_day_of_week IS NOT NULL
       AND booking_release_day_of_week BETWEEN 0 AND 6
       AND booking_release_time IS NOT NULL
       AND booking_release_window_days IS NOT NULL
       AND booking_release_window_days >= 7)
    OR (booking_release_mode IN ('inherit', 'always_open')
        AND booking_release_day_of_week IS NULL
        AND booking_release_time IS NULL
        AND booking_release_window_days IS NULL)
  );

-- ---------------------------------------------------------------------
-- opensAt helper: the first weekly release instant R covering slot start
-- S — the earliest R with local(R) > local(S) - window AND R <= S.
-- ---------------------------------------------------------------------
-- Parameters are INT, not SMALLINT: Postgres has no implicit int4 -> int2
-- cast for function resolution, so SQL callers passing integer literals
-- (smoke tests, future migrations) would not resolve a SMALLINT signature.
-- The columns stay SMALLINT; assignment casts them down.
CREATE OR REPLACE FUNCTION public.sports_venue_booking_release_opens_at(
  p_timezone VARCHAR,
  p_day_of_week INT,
  p_release_time TIME,
  p_window_days INT,
  p_slot_start TIMESTAMPTZ
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_lower TIMESTAMP;
  v_day DATE;
  v_rel TIMESTAMP;
  v_instant TIMESTAMPTZ;
BEGIN
  -- Release coverage is a venue-local half-open window [R, R+N), so the
  -- covering releases of S are those whose local time exceeds S - N.
  v_lower := (p_slot_start AT TIME ZONE p_timezone)
             - make_interval(days => p_window_days);
  v_day := v_lower::date;
  v_rel := (v_day
            + ((p_day_of_week - EXTRACT(dow FROM v_day)::int + 7) % 7))
           + p_release_time;
  WHILE v_rel <= v_lower LOOP
    v_rel := v_rel + interval '7 days';
  END LOOP;
  v_instant := v_rel AT TIME ZONE p_timezone;
  -- DST overlap can order the candidate's instant after the slot even
  -- though its local time precedes it; step back one weekly release.
  IF v_instant > p_slot_start THEN
    v_instant := (v_rel - interval '7 days') AT TIME ZONE p_timezone;
  END IF;
  RETURN v_instant;
END;
$$;

-- ---------------------------------------------------------------------
-- Release gate shared by create/change-slot. Caller must already hold a
-- FOR UPDATE lock on the court row; this takes FOR SHARE on the venue row
-- so parallel bookings do not serialize on each other, while an owner
-- UPDATE of the release rule waits for in-flight booking transactions.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_sports_venue_booking_release(
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue_id UUID;
  v_mode VARCHAR;
  v_tz VARCHAR;
  v_dow SMALLINT;
  v_time TIME;
  v_win SMALLINT;
  v_vdow SMALLINT;
  v_vtime TIME;
  v_vwin SMALLINT;
  v_hours INT;
  v_last_start TIMESTAMPTZ;
  v_opens_at TIMESTAMPTZ;
BEGIN
  SELECT c.venue_id, c.booking_release_mode,
         c.booking_release_day_of_week, c.booking_release_time,
         c.booking_release_window_days
    INTO v_venue_id, v_mode, v_dow, v_time, v_win
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;

  -- FOR SHARE, not FOR UPDATE: shared locks keep bookings parallel while
  -- still serializing this read against concurrent venue rule updates.
  SELECT v.timezone, v.booking_release_day_of_week,
         v.booking_release_time, v.booking_release_window_days
    INTO v_tz, v_vdow, v_vtime, v_vwin
  FROM public.sports_venues v
  WHERE v.id = v_venue_id
  FOR SHARE;

  IF v_mode = 'always_open' THEN
    RETURN;
  END IF;
  IF v_mode = 'inherit' THEN
    v_dow := v_vdow;
    v_time := v_vtime;
    v_win := v_vwin;
  END IF;
  IF v_dow IS NULL OR v_time IS NULL OR v_win IS NULL THEN
    RETURN;
  END IF;

  -- Candidate starts are hour-aligned from the booking start, matching
  -- the client picker grid. opensAt is monotonic in S, so the last
  -- candidate covers every candidate in the range.
  v_hours := GREATEST(1, CEIL(
    EXTRACT(EPOCH FROM (p_ends_at - p_starts_at)) / 3600.0)::INT);
  v_last_start := p_starts_at + ((v_hours - 1) * interval '1 hour');
  v_opens_at := public.sports_venue_booking_release_opens_at(
    v_tz, v_dow, v_time, v_win, v_last_start);
  IF v_opens_at > now() THEN
    RAISE EXCEPTION 'BOOKING_NOT_OPEN_YET'
      USING DETAIL = to_char(
        v_opens_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_release_opens_at(
  VARCHAR, INT, TIME, INT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.assert_sports_venue_booking_release(
  UUID, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Venue-level release settings. All three NULL clears the rule
-- (unlimited advance booking); otherwise a complete valid triple is
-- required. Takes a FOR UPDATE row lock on the venue via the UPDATE.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_sports_venue_booking_release(
  p_user_id UUID,
  p_venue_id UUID,
  p_day_of_week INT,
  p_time TIME,
  p_window_days INT
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
  IF p_day_of_week IS NULL
     AND p_time IS NULL
     AND p_window_days IS NULL THEN
    UPDATE public.sports_venues
    SET booking_release_day_of_week = NULL,
        booking_release_time = NULL,
        booking_release_window_days = NULL,
        updated_at = now()
    WHERE id = p_venue_id;
    RETURN;
  END IF;
  IF p_day_of_week IS NULL
     OR p_day_of_week NOT BETWEEN 0 AND 6
     OR p_time IS NULL
     OR p_window_days IS NULL
     OR p_window_days < 7 THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;
  UPDATE public.sports_venues
  SET booking_release_day_of_week = p_day_of_week,
      booking_release_time = p_time,
      booking_release_window_days = p_window_days,
      updated_at = now()
  WHERE id = p_venue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- upsert_sports_venue_court: keep the 21.7.16 implementation callable as
-- a private helper, then extend the public signature with the release
-- fields. p_booking_release_mode NULL means "keep current settings" so
-- older clients never clear an override accidentally (same convention as
-- p_price_rules NULL = unchanged).
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb)'
     ) IS NOT NULL
     AND to_regprocedure(
       'public.upsert_sports_venue_court_pricing(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb)'
     ) IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb) RENAME TO upsert_sports_venue_court_pricing';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upsert_sports_venue_court_pricing(
  UUID, UUID, UUID, UUID, VARCHAR, INT, NUMERIC, VARCHAR, VARCHAR,
  BOOLEAN, VARCHAR, VARCHAR, BOOLEAN, JSONB
) FROM PUBLIC, anon, authenticated;

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
  p_is_active BOOLEAN DEFAULT true,
  p_price_rules JSONB DEFAULT NULL,
  p_booking_release_mode VARCHAR DEFAULT NULL,
  p_booking_release_day_of_week INT DEFAULT NULL,
  p_booking_release_time TIME DEFAULT NULL,
  p_booking_release_window_days INT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
BEGIN
  v_court_id := public.upsert_sports_venue_court_pricing(
    p_user_id, p_court_id, p_venue_id, p_sport_id, p_name, p_capacity,
    p_price_amount, p_pricing_unit, p_court_type, p_indoor,
    p_booking_approval_mode, p_unit_label, p_is_active, p_price_rules);

  IF p_booking_release_mode IS NULL THEN
    RETURN v_court_id;
  END IF;
  IF p_booking_release_mode NOT IN ('inherit', 'always_open', 'custom') THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;
  IF p_booking_release_mode = 'custom' THEN
    IF p_booking_release_day_of_week IS NULL
       OR p_booking_release_day_of_week NOT BETWEEN 0 AND 6
       OR p_booking_release_time IS NULL
       OR p_booking_release_window_days IS NULL
       OR p_booking_release_window_days < 7 THEN
      RAISE EXCEPTION 'INVALID_RELEASE_RULE';
    END IF;
    UPDATE public.sports_venue_courts
    SET booking_release_mode = 'custom',
        booking_release_day_of_week = p_booking_release_day_of_week,
        booking_release_time = p_booking_release_time,
        booking_release_window_days = p_booking_release_window_days,
        updated_at = now()
    WHERE id = v_court_id;
  ELSE
    UPDATE public.sports_venue_courts
    SET booking_release_mode = p_booking_release_mode,
        booking_release_day_of_week = NULL,
        booking_release_time = NULL,
        booking_release_window_days = NULL,
        updated_at = now()
    WHERE id = v_court_id;
  END IF;
  RETURN v_court_id;
END;
$$;

-- ---------------------------------------------------------------------
-- get_court_availability: additive serverNow + per-slot notOpen opensAt
-- + the effective rule echo for the client release banner.
-- ---------------------------------------------------------------------
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
  v_mode VARCHAR;
  v_tz VARCHAR;
  v_dow SMALLINT;
  v_time TIME;
  v_win SMALLINT;
  v_vdow SMALLINT;
  v_vtime TIME;
  v_vwin SMALLINT;
BEGIN
  SELECT c.venue_id, c.booking_release_mode,
         c.booking_release_day_of_week, c.booking_release_time,
         c.booking_release_window_days
    INTO v_venue_id, v_mode, v_dow, v_time, v_win
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id AND c.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  SELECT v.timezone, v.booking_release_day_of_week,
         v.booking_release_time, v.booking_release_window_days
    INTO v_tz, v_vdow, v_vtime, v_vwin
  FROM public.sports_venues v
  WHERE v.id = v_venue_id AND v.status = 'approved';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;

  IF v_mode = 'always_open' THEN
    v_dow := NULL;
    v_time := NULL;
    v_win := NULL;
  ELSIF v_mode = 'inherit' THEN
    v_dow := v_vdow;
    v_time := v_vtime;
    v_win := v_vwin;
  END IF;
  IF v_dow IS NULL OR v_time IS NULL OR v_win IS NULL THEN
    v_dow := NULL;
    v_time := NULL;
    v_win := NULL;
  END IF;

  RETURN JSONB_BUILD_OBJECT(
    'courtId', p_court_id,
    'serverNow', now(),
    'booked', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'startsAt', b.starts_at, 'endsAt', b.ends_at))
      FROM public.sports_venue_bookings b
      WHERE b.court_id = p_court_id
        AND b.status = 'confirmed'
        AND b.starts_at < p_to AND b.ends_at > p_from
    ), '[]'::jsonb),
    'blocked', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'startsAt', s.starts_at, 'endsAt', s.ends_at))
      FROM public.sports_venue_availability s
      WHERE s.court_id = p_court_id
        AND s.kind = 'blocked'
        AND s.starts_at < p_to AND s.ends_at > p_from
    ), '[]'::jsonb),
    'hours', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'day', h.day_of_week, 'open', h.open_time,
          'close', h.close_time, 'closed', h.is_closed))
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v_venue_id
    ), '[]'::jsonb),
    'notOpen', CASE WHEN v_dow IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'slotStart', o.slot_start, 'opensAt', o.opens_at)
          ORDER BY o.slot_start)
      FROM (
        SELECT s.slot_start,
               public.sports_venue_booking_release_opens_at(
                 v_tz, v_dow, v_time, v_win, s.slot_start) AS opens_at
        FROM (
          SELECT (gen::date + (hour_num || ' hours')::interval)
                 AT TIME ZONE v_tz AS slot_start
          FROM generate_series(
            (p_from AT TIME ZONE v_tz)::date,
            (p_to AT TIME ZONE v_tz)::date,
            '1 day'::interval) AS gen,
          generate_series(0, 23) AS hour_num
        ) s
        WHERE s.slot_start >= p_from AND s.slot_start < p_to
      ) o
      WHERE o.opens_at > now()
    ), '[]'::jsonb) END,
    'release', CASE WHEN v_dow IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
      'mode', v_mode,
      'dayOfWeek', v_dow,
      'releaseTime', v_time,
      'windowDays', v_win) END
  );
END;
$$;

-- ---------------------------------------------------------------------
-- create_sports_venue_booking: same signature as 21.7.16; the release
-- gate runs after the post-lock idempotency lookup so a retry returns
-- the original booking even if the rule changed in between.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_sports_venue_booking(
  p_user_id UUID,
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_terms_version INT,
  p_idempotency_key VARCHAR DEFAULT NULL,
  p_expected_price_schedule_version BIGINT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court RECORD;
  v_price JSONB;
  v_booking_id UUID;
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

  SELECT c.id INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id
  FOR UPDATE;
  IF v_court.id IS NULL THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT b.id INTO v_booking_id
    FROM public.sports_venue_bookings b
    WHERE b.user_id = p_user_id AND b.idempotency_key = p_idempotency_key;
    IF v_booking_id IS NOT NULL THEN
      RETURN v_booking_id;
    END IF;
  END IF;

  -- 21.7.18: recurring release gate (locks venue FOR SHARE, raises
  -- BOOKING_NOT_OPEN_YET with opensAt in the exception DETAIL).
  PERFORM public.assert_sports_venue_booking_release(
    p_court_id, p_starts_at, p_ends_at);

  v_price := public.sports_venue_court_price_quote_internal(
    p_court_id, p_starts_at, p_ends_at
  );
  IF v_price->>'price_error' IS NOT NULL THEN
    RAISE EXCEPTION '%', v_price->>'price_error';
  END IF;
  IF (v_price->>'has_time_pricing')::BOOLEAN
     AND p_expected_price_schedule_version IS NULL THEN
    RAISE EXCEPTION 'PRICE_VERSION_REQUIRED';
  END IF;
  IF p_expected_price_schedule_version IS NOT NULL
     AND p_expected_price_schedule_version <>
         (v_price->>'price_schedule_version')::BIGINT THEN
    RAISE EXCEPTION 'PRICE_CHANGED';
  END IF;

  v_booking_id := public.create_sports_venue_booking_legacy(
    p_user_id, p_court_id, p_starts_at, p_ends_at,
    p_terms_version, p_idempotency_key
  );
  UPDATE public.sports_venue_bookings
  SET price_amount_snapshot = NULLIF(v_price->>'price_amount', '')::NUMERIC,
      pricing_unit_snapshot = v_price->>'pricing_unit',
      price_total_snapshot = NULLIF(v_price->>'total_amount', '')::NUMERIC,
      price_breakdown_snapshot = COALESCE(v_price->'breakdown', '[]'::jsonb),
      price_schedule_version_snapshot =
        (v_price->>'price_schedule_version')::BIGINT
  WHERE id = v_booking_id AND user_id = p_user_id;
  RETURN v_booking_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.change_pending_venue_booking_slot(
  p_user_id UUID,
  p_booking_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_terms_version INT DEFAULT NULL,
  p_expected_price_schedule_version BIGINT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
  v_court RECORD;
  v_price JSONB;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at
     OR p_ends_at <= now() THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;
  SELECT b.court_id INTO v_court_id
  FROM public.sports_venue_bookings b
  WHERE b.id = p_booking_id;
  IF v_court_id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT c.id INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = v_court_id
  FOR UPDATE;
  IF v_court.id IS NULL THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;

  -- 21.7.18: same release gate as booking creation. Only pending
  -- bookings reach this function (the legacy call enforces that), so
  -- approvals of already-pending bookings are never re-gated here.
  PERFORM public.assert_sports_venue_booking_release(
    v_court_id, p_starts_at, p_ends_at);

  v_price := public.sports_venue_court_price_quote_internal(
    v_court_id, p_starts_at, p_ends_at
  );
  IF v_price->>'price_error' IS NOT NULL THEN
    RAISE EXCEPTION '%', v_price->>'price_error';
  END IF;
  IF (v_price->>'has_time_pricing')::BOOLEAN
     AND p_expected_price_schedule_version IS NULL THEN
    RAISE EXCEPTION 'PRICE_VERSION_REQUIRED';
  END IF;
  IF p_expected_price_schedule_version IS NOT NULL
     AND p_expected_price_schedule_version <>
         (v_price->>'price_schedule_version')::BIGINT THEN
    RAISE EXCEPTION 'PRICE_CHANGED';
  END IF;

  PERFORM public.change_pending_venue_booking_slot_legacy(
    p_user_id, p_booking_id, p_starts_at, p_ends_at, p_terms_version
  );
  UPDATE public.sports_venue_bookings
  SET price_amount_snapshot = NULLIF(v_price->>'price_amount', '')::NUMERIC,
      pricing_unit_snapshot = v_price->>'pricing_unit',
      price_total_snapshot = NULLIF(v_price->>'total_amount', '')::NUMERIC,
      price_breakdown_snapshot = COALESCE(v_price->'breakdown', '[]'::jsonb),
      price_schedule_version_snapshot =
        (v_price->>'price_schedule_version')::BIGINT
  WHERE id = p_booking_id AND user_id = p_user_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
