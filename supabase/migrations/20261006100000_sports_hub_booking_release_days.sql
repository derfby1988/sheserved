ALTER TABLE public.sports_venues
  ADD COLUMN IF NOT EXISTS booking_release_days SMALLINT[];

ALTER TABLE public.sports_venue_courts
  ADD COLUMN IF NOT EXISTS booking_release_days SMALLINT[];

CREATE OR REPLACE FUNCTION public.sports_venue_booking_release_days_valid(
  p_days SMALLINT[]
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    p_days IS NOT NULL
    AND cardinality(p_days) BETWEEN 1 AND 7
    AND array_ndims(p_days) = 1
    AND array_lower(p_days, 1) = 1
    AND (SELECT count(*) = cardinality(p_days)
         FROM unnest(p_days) AS d(day)
         WHERE d.day BETWEEN 0 AND 6)
    AND p_days = ARRAY(
      SELECT DISTINCT d.day
      FROM unnest(p_days) AS d(day)
      ORDER BY d.day),
    false);
$$;

CREATE OR REPLACE FUNCTION public.sports_venue_booking_release_min_window(
  p_days SMALLINT[]
)
RETURNS INT
LANGUAGE SQL
IMMUTABLE
SET search_path = public
AS $$
  WITH ordered AS (
    SELECT d.day,
           lead(d.day) OVER (ORDER BY d.day) AS next_day,
           first_value(d.day) OVER (ORDER BY d.day) AS first_day
    FROM unnest(p_days) AS d(day)
  )
  SELECT COALESCE(max(
    CASE WHEN next_day IS NULL THEN first_day + 7 - day
         ELSE next_day - day END), 0)::INT
  FROM ordered;
$$;

CREATE OR REPLACE FUNCTION public.sports_venue_booking_release_parse_days(
  p_days JSONB
)
RETURNS SMALLINT[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_days SMALLINT[];
BEGIN
  IF jsonb_typeof(p_days) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;
  IF jsonb_array_length(p_days) NOT BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_days) AS e(value)
    WHERE jsonb_typeof(e.value) <> 'number'
       OR e.value::TEXT !~ '^[0-6]$'
  ) THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;

  SELECT array_agg(e.value::SMALLINT ORDER BY e.value::SMALLINT)
  INTO v_days
  FROM jsonb_array_elements_text(p_days) AS e(value);

  IF cardinality(v_days) <> (
    SELECT count(DISTINCT e.value::SMALLINT)
    FROM jsonb_array_elements_text(p_days) AS e(value)
  ) THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;
  RETURN v_days;
END;
$$;

UPDATE public.sports_venues
SET booking_release_days = ARRAY[booking_release_day_of_week]::SMALLINT[]
WHERE booking_release_days IS NULL
  AND booking_release_day_of_week IS NOT NULL;

UPDATE public.sports_venue_courts
SET booking_release_days = ARRAY[booking_release_day_of_week]::SMALLINT[]
WHERE booking_release_mode = 'custom'
  AND booking_release_days IS NULL
  AND booking_release_day_of_week IS NOT NULL;

ALTER TABLE public.sports_venues
  DROP CONSTRAINT IF EXISTS sports_venues_booking_release_chk;
ALTER TABLE public.sports_venues
  ADD CONSTRAINT sports_venues_booking_release_chk CHECK (
    (booking_release_days IS NULL
      AND booking_release_day_of_week IS NULL
      AND booking_release_time IS NULL
      AND booking_release_window_days IS NULL)
    OR (public.sports_venue_booking_release_days_valid(booking_release_days)
      AND booking_release_day_of_week = booking_release_days[1]
      AND booking_release_time IS NOT NULL
      AND booking_release_window_days IS NOT NULL
      AND booking_release_window_days >=
          public.sports_venue_booking_release_min_window(booking_release_days))
  );

ALTER TABLE public.sports_venue_courts
  DROP CONSTRAINT IF EXISTS sports_venue_courts_booking_release_chk;
ALTER TABLE public.sports_venue_courts
  ADD CONSTRAINT sports_venue_courts_booking_release_chk CHECK (
    (booking_release_mode = 'custom'
      AND public.sports_venue_booking_release_days_valid(booking_release_days)
      AND booking_release_day_of_week = booking_release_days[1]
      AND booking_release_time IS NOT NULL
      AND booking_release_window_days IS NOT NULL
      AND booking_release_window_days >=
          public.sports_venue_booking_release_min_window(booking_release_days))
    OR (booking_release_mode IN ('inherit', 'always_open')
      AND booking_release_days IS NULL
      AND booking_release_day_of_week IS NULL
      AND booking_release_time IS NULL
      AND booking_release_window_days IS NULL)
  );

CREATE OR REPLACE FUNCTION public.sports_venue_booking_release_opens_at_for_days(
  p_timezone VARCHAR,
  p_days SMALLINT[],
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
  v_candidate_date DATE;
  v_candidate_local TIMESTAMP;
  v_candidate_instant TIMESTAMPTZ;
  v_previous_date DATE;
  v_offset INT;
BEGIN
  v_lower := (p_slot_start AT TIME ZONE p_timezone)
             - make_interval(days => p_window_days);
  FOR v_offset IN 0..7 LOOP
    v_candidate_date := v_lower::DATE + v_offset;
    IF EXTRACT(DOW FROM v_candidate_date)::SMALLINT = ANY(p_days) THEN
      v_candidate_local := v_candidate_date + p_release_time;
      IF v_candidate_local > v_lower THEN
        v_candidate_instant := v_candidate_local AT TIME ZONE p_timezone;
        EXIT;
      END IF;
    END IF;
  END LOOP;
  IF v_candidate_instant IS NULL THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;

  IF v_candidate_instant > p_slot_start THEN
    FOR v_offset IN 1..7 LOOP
      v_previous_date := v_candidate_date - v_offset;
      IF EXTRACT(DOW FROM v_previous_date)::SMALLINT = ANY(p_days) THEN
        RETURN (v_previous_date + p_release_time) AT TIME ZONE p_timezone;
      END IF;
    END LOOP;
  END IF;
  RETURN v_candidate_instant;
END;
$$;

CREATE OR REPLACE FUNCTION public.sports_venue_booking_release_opens_at(
  p_timezone VARCHAR,
  p_day_of_week INT,
  p_release_time TIME,
  p_window_days INT,
  p_slot_start TIMESTAMPTZ
)
RETURNS TIMESTAMPTZ
LANGUAGE SQL
STABLE
SET search_path = public
AS $$
  SELECT public.sports_venue_booking_release_opens_at_for_days(
    p_timezone, ARRAY[p_day_of_week::SMALLINT], p_release_time,
    p_window_days, p_slot_start);
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_release_days_valid(
  SMALLINT[]
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_release_min_window(
  SMALLINT[]
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_release_parse_days(
  JSONB
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_release_opens_at_for_days(
  VARCHAR, SMALLINT[], TIME, INT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_release_opens_at(
  VARCHAR, INT, TIME, INT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_sports_venue_booking_release_days(
  p_user_id UUID,
  p_venue_id UUID,
  p_days_of_week JSONB DEFAULT NULL,
  p_time TIME DEFAULT NULL,
  p_window_days INT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days SMALLINT[];
  v_min_window INT;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF p_days_of_week IS NULL AND p_time IS NULL AND p_window_days IS NULL THEN
    UPDATE public.sports_venues
    SET booking_release_days = NULL,
        booking_release_day_of_week = NULL,
        booking_release_time = NULL,
        booking_release_window_days = NULL,
        updated_at = now()
    WHERE id = p_venue_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'VENUE_NOT_FOUND';
    END IF;
    RETURN;
  END IF;
  IF p_days_of_week IS NULL OR p_time IS NULL OR p_window_days IS NULL THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;

  v_days := public.sports_venue_booking_release_parse_days(p_days_of_week);
  v_min_window := public.sports_venue_booking_release_min_window(v_days);
  IF p_window_days < v_min_window OR p_window_days > 32767 THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;

  UPDATE public.sports_venues
  SET booking_release_days = v_days,
      booking_release_day_of_week = v_days[1],
      booking_release_time = p_time,
      booking_release_window_days = p_window_days,
      updated_at = now()
  WHERE id = p_venue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
END;
$$;

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
  PERFORM public.set_sports_venue_booking_release_days(
    p_user_id,
    p_venue_id,
    CASE WHEN p_day_of_week IS NULL THEN NULL
         ELSE jsonb_build_array(p_day_of_week) END,
    p_time,
    p_window_days);
END;
$$;

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
  v_days SMALLINT[];
  v_day SMALLINT;
  v_time TIME;
  v_win SMALLINT;
  v_tz VARCHAR;
  v_vdays SMALLINT[];
  v_vday SMALLINT;
  v_vtime TIME;
  v_vwin SMALLINT;
  v_hours INT;
  v_last_start TIMESTAMPTZ;
  v_opens_at TIMESTAMPTZ;
BEGIN
  SELECT c.venue_id, c.booking_release_mode,
         c.booking_release_days, c.booking_release_day_of_week,
         c.booking_release_time, c.booking_release_window_days
    INTO v_venue_id, v_mode, v_days, v_day, v_time, v_win
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  v_days := COALESCE(v_days, CASE WHEN v_day IS NULL THEN NULL
                                  ELSE ARRAY[v_day] END);

  SELECT v.timezone, v.booking_release_days,
         v.booking_release_day_of_week, v.booking_release_time,
         v.booking_release_window_days
    INTO v_tz, v_vdays, v_vday, v_vtime, v_vwin
  FROM public.sports_venues v
  WHERE v.id = v_venue_id
  FOR SHARE;
  v_vdays := COALESCE(v_vdays, CASE WHEN v_vday IS NULL THEN NULL
                                    ELSE ARRAY[v_vday] END);

  IF v_mode = 'always_open' THEN
    RETURN;
  END IF;
  IF v_mode = 'inherit' THEN
    v_days := v_vdays;
    v_time := v_vtime;
    v_win := v_vwin;
  END IF;
  IF v_days IS NULL OR v_time IS NULL OR v_win IS NULL THEN
    RETURN;
  END IF;

  v_hours := GREATEST(1, CEIL(
    EXTRACT(EPOCH FROM (p_ends_at - p_starts_at)) / 3600.0)::INT);
  v_last_start := p_starts_at + ((v_hours - 1) * interval '1 hour');
  v_opens_at := public.sports_venue_booking_release_opens_at_for_days(
    v_tz, v_days, v_time, v_win, v_last_start);
  IF v_opens_at > now() THEN
    RAISE EXCEPTION 'BOOKING_NOT_OPEN_YET'
      USING DETAIL = to_char(
        v_opens_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  END IF;
END;
$$;

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
  v_days SMALLINT[];
  v_day SMALLINT;
  v_time TIME;
  v_win SMALLINT;
  v_vdays SMALLINT[];
  v_vday SMALLINT;
  v_vtime TIME;
  v_vwin SMALLINT;
BEGIN
  SELECT c.venue_id, c.booking_release_mode,
         c.booking_release_days, c.booking_release_day_of_week,
         c.booking_release_time, c.booking_release_window_days
    INTO v_venue_id, v_mode, v_days, v_day, v_time, v_win
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id AND c.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  v_days := COALESCE(v_days, CASE WHEN v_day IS NULL THEN NULL
                                  ELSE ARRAY[v_day] END);

  SELECT v.timezone, v.booking_release_days,
         v.booking_release_day_of_week, v.booking_release_time,
         v.booking_release_window_days
    INTO v_tz, v_vdays, v_vday, v_vtime, v_vwin
  FROM public.sports_venues v
  WHERE v.id = v_venue_id AND v.status = 'approved';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;
  v_vdays := COALESCE(v_vdays, CASE WHEN v_vday IS NULL THEN NULL
                                    ELSE ARRAY[v_vday] END);

  IF v_mode = 'always_open' THEN
    v_days := NULL;
    v_time := NULL;
    v_win := NULL;
  ELSIF v_mode = 'inherit' THEN
    v_days := v_vdays;
    v_time := v_vtime;
    v_win := v_vwin;
  END IF;
  IF v_days IS NULL OR v_time IS NULL OR v_win IS NULL THEN
    v_days := NULL;
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
    'notOpen', CASE WHEN v_days IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'slotStart', o.slot_start, 'opensAt', o.opens_at)
          ORDER BY o.slot_start)
      FROM (
        SELECT s.slot_start,
               public.sports_venue_booking_release_opens_at_for_days(
                 v_tz, v_days, v_time, v_win, s.slot_start) AS opens_at
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
    'release', CASE WHEN v_days IS NULL THEN NULL ELSE JSONB_BUILD_OBJECT(
      'mode', v_mode,
      'dayOfWeek', v_days[1],
      'daysOfWeek', v_days,
      'releaseTime', v_time,
      'windowDays', v_win) END
  );
END;
$$;

DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer,character varying,character varying)'
     ) IS NOT NULL
     AND to_regprocedure(
       'public.upsert_sports_venue_court_single_release(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer,character varying,character varying)'
     ) IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer,character varying,character varying) RENAME TO upsert_sports_venue_court_single_release';
  END IF;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue_court_single_release(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer,character varying,character varying)'
     ) IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.upsert_sports_venue_court_single_release(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer,character varying,character varying) FROM PUBLIC, anon, authenticated';
  END IF;
END;
$$;

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
  p_booking_release_window_days INT DEFAULT NULL,
  p_unit_label_mode VARCHAR DEFAULT NULL,
  p_unit_label_override VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
BEGIN
  IF p_booking_release_mode IS NOT NULL
     AND p_booking_release_mode NOT IN ('inherit', 'always_open', 'custom') THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;
  IF p_booking_release_mode = 'custom'
     AND (p_booking_release_day_of_week IS NULL
       OR p_booking_release_day_of_week NOT BETWEEN 0 AND 6
       OR p_booking_release_time IS NULL
       OR p_booking_release_window_days IS NULL
       OR p_booking_release_window_days < 7
       OR p_booking_release_window_days > 32767) THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;

  v_court_id := public.upsert_sports_venue_court_single_release(
    p_user_id, p_court_id, p_venue_id, p_sport_id, p_name, p_capacity,
    p_price_amount, p_pricing_unit, p_court_type, p_indoor,
    p_booking_approval_mode, p_unit_label, p_is_active, p_price_rules,
    NULL, p_booking_release_day_of_week, p_booking_release_time,
    p_booking_release_window_days, p_unit_label_mode, p_unit_label_override);

  IF p_booking_release_mode = 'custom' THEN
    UPDATE public.sports_venue_courts
    SET booking_release_mode = 'custom',
        booking_release_days = ARRAY[p_booking_release_day_of_week::SMALLINT],
        booking_release_day_of_week = p_booking_release_day_of_week,
        booking_release_time = p_booking_release_time,
        booking_release_window_days = p_booking_release_window_days,
        updated_at = now()
    WHERE id = v_court_id;
  ELSIF p_booking_release_mode IN ('inherit', 'always_open') THEN
    UPDATE public.sports_venue_courts
    SET booking_release_mode = p_booking_release_mode,
        booking_release_days = NULL,
        booking_release_day_of_week = NULL,
        booking_release_time = NULL,
        booking_release_window_days = NULL,
        updated_at = now()
    WHERE id = v_court_id;
  END IF;
  RETURN v_court_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_sports_venue_court_with_release_days(
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
  p_booking_release_window_days INT DEFAULT NULL,
  p_unit_label_mode VARCHAR DEFAULT NULL,
  p_unit_label_override VARCHAR DEFAULT NULL,
  p_booking_release_days JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
  v_days SMALLINT[];
  v_min_window INT;
  v_release_mode VARCHAR;
BEGIN
  IF p_booking_release_mode IS NULL THEN
    IF p_booking_release_days IS NOT NULL THEN
      RAISE EXCEPTION 'INVALID_RELEASE_RULE';
    END IF;
  ELSIF p_booking_release_mode NOT IN ('inherit', 'always_open', 'custom') THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  ELSIF p_booking_release_mode = 'custom' THEN
    v_days := public.sports_venue_booking_release_parse_days(
      COALESCE(p_booking_release_days,
        CASE WHEN p_booking_release_day_of_week IS NULL THEN NULL
             ELSE jsonb_build_array(p_booking_release_day_of_week) END));
    v_min_window := public.sports_venue_booking_release_min_window(v_days);
    IF p_booking_release_time IS NULL
       OR p_booking_release_window_days IS NULL
       OR p_booking_release_window_days < v_min_window
       OR p_booking_release_window_days > 32767 THEN
      RAISE EXCEPTION 'INVALID_RELEASE_RULE';
    END IF;
  ELSIF p_booking_release_days IS NOT NULL THEN
    RAISE EXCEPTION 'INVALID_RELEASE_RULE';
  END IF;

  v_release_mode := CASE WHEN p_booking_release_mode = 'custom' THEN NULL
                         ELSE p_booking_release_mode END;
  v_court_id := public.upsert_sports_venue_court(
    p_user_id, p_court_id, p_venue_id, p_sport_id, p_name, p_capacity,
    p_price_amount, p_pricing_unit, p_court_type, p_indoor,
    p_booking_approval_mode, p_unit_label, p_is_active, p_price_rules,
    v_release_mode, p_booking_release_day_of_week,
    p_booking_release_time, p_booking_release_window_days,
    p_unit_label_mode, p_unit_label_override);

  IF p_booking_release_mode = 'custom' THEN
    UPDATE public.sports_venue_courts
    SET booking_release_mode = 'custom',
        booking_release_days = v_days,
        booking_release_day_of_week = v_days[1],
        booking_release_time = p_booking_release_time,
        booking_release_window_days = p_booking_release_window_days,
        updated_at = now()
    WHERE id = v_court_id;
  END IF;
  RETURN v_court_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
