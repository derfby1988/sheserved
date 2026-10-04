CREATE OR REPLACE FUNCTION public.sports_venue_booking_release_opens_at_for_slot(
  p_timezone VARCHAR,
  p_mode VARCHAR,
  p_court_days SMALLINT[],
  p_court_time TIME,
  p_court_window_days INT,
  p_venue_days SMALLINT[],
  p_venue_time TIME,
  p_venue_window_days INT,
  p_slot_start TIMESTAMPTZ
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slot_day SMALLINT;
BEGIN
  IF p_mode = 'always_open' THEN
    RETURN NULL;
  END IF;
  v_slot_day := EXTRACT(DOW FROM
    (p_slot_start AT TIME ZONE p_timezone)::DATE)::SMALLINT;
  IF p_mode = 'custom'
     AND p_court_days IS NOT NULL
     AND v_slot_day = ANY(p_court_days) THEN
    IF p_court_time IS NULL OR p_court_window_days IS NULL THEN
      RAISE EXCEPTION 'INVALID_RELEASE_RULE';
    END IF;
    RETURN public.sports_venue_booking_release_opens_at_for_days(
      p_timezone, p_court_days, p_court_time,
      p_court_window_days, p_slot_start);
  END IF;
  -- The venue rule gates every booking date: p_venue_days decides when a
  -- release runs, and the nearest covering release opens the slot.
  IF p_venue_days IS NOT NULL THEN
    IF p_venue_time IS NULL OR p_venue_window_days IS NULL THEN
      RAISE EXCEPTION 'INVALID_RELEASE_RULE';
    END IF;
    RETURN public.sports_venue_booking_release_opens_at_for_days(
      p_timezone, p_venue_days, p_venue_time,
      p_venue_window_days, p_slot_start);
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.sports_venue_booking_release_opens_at_for_slot(
    VARCHAR, VARCHAR, SMALLINT[], TIME, INT, SMALLINT[], TIME, INT,
    TIMESTAMPTZ
  ) FROM PUBLIC, anon, authenticated;

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
  v_timezone VARCHAR;
  v_court_days SMALLINT[];
  v_court_day SMALLINT;
  v_court_time TIME;
  v_court_window SMALLINT;
  v_venue_days SMALLINT[];
  v_venue_day SMALLINT;
  v_venue_time TIME;
  v_venue_window SMALLINT;
  v_selected_day SMALLINT;
  v_selected_date DATE;
  v_selected_time TIME;
  v_selected_window SMALLINT;
  v_selected_opens_at TIMESTAMPTZ;
  v_effective_days SMALLINT[];
  v_next_release_at TIMESTAMPTZ;
BEGIN
  SELECT c.venue_id, c.booking_release_mode,
         c.booking_release_days, c.booking_release_day_of_week,
         c.booking_release_time, c.booking_release_window_days
    INTO v_venue_id, v_mode, v_court_days, v_court_day,
         v_court_time, v_court_window
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id AND c.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  v_court_days := COALESCE(
    v_court_days,
    CASE WHEN v_court_day IS NULL THEN NULL ELSE ARRAY[v_court_day] END);

  SELECT v.timezone, v.booking_release_days,
         v.booking_release_day_of_week, v.booking_release_time,
         v.booking_release_window_days
    INTO v_timezone, v_venue_days, v_venue_day,
         v_venue_time, v_venue_window
  FROM public.sports_venues v
  WHERE v.id = v_venue_id AND v.status = 'approved';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;
  v_venue_days := COALESCE(
    v_venue_days,
    CASE WHEN v_venue_day IS NULL THEN NULL ELSE ARRAY[v_venue_day] END);

  IF v_mode = 'always_open' THEN
    v_effective_days := NULL;
  ELSE
    SELECT array_agg(d.day ORDER BY d.day)
      INTO v_effective_days
    FROM (
      SELECT unnest(COALESCE(v_venue_days, '{}'::SMALLINT[])) AS day
      UNION
      SELECT unnest(
        CASE WHEN v_mode = 'custom'
          THEN COALESCE(v_court_days, '{}'::SMALLINT[])
          ELSE '{}'::SMALLINT[]
        END) AS day
    ) d;
  END IF;

  v_selected_date := (p_from AT TIME ZONE v_timezone)::DATE;
  v_selected_day := EXTRACT(DOW FROM v_selected_date)::SMALLINT;
  IF v_mode = 'custom'
     AND v_court_days IS NOT NULL
     AND v_selected_day = ANY(v_court_days) THEN
    v_selected_time := v_court_time;
    v_selected_window := v_court_window;
  ELSIF v_mode <> 'always_open'
     AND v_venue_days IS NOT NULL THEN
    v_selected_time := v_venue_time;
    v_selected_window := v_venue_window;
  END IF;

  -- The release that governs the selected date. Its own date may be earlier
  -- than the booking date, so the UI can name it instead of guessing a weekday.
  IF v_effective_days IS NOT NULL THEN
    SELECT max(o.opens_at)
      INTO v_selected_opens_at
    FROM generate_series(0, 23) AS hour_num
    CROSS JOIN LATERAL (
      SELECT public.sports_venue_booking_release_opens_at_for_slot(
        v_timezone, v_mode,
        v_court_days, v_court_time, v_court_window,
        v_venue_days, v_venue_time, v_venue_window,
        (v_selected_date + (hour_num || ' hours')::interval)
          AT TIME ZONE v_timezone) AS opens_at
    ) o;
  END IF;

  v_next_release_at := public.sports_venue_booking_release_next_at(
    v_timezone, now(), v_mode, v_court_days, v_court_time,
    v_venue_days, v_venue_time);

  RETURN JSONB_BUILD_OBJECT(
    'courtId', p_court_id,
    'serverNow', now(),
    'nextReleaseAt', v_next_release_at,
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
    'notOpen', CASE WHEN v_effective_days IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'slotStart', o.slot_start, 'opensAt', o.opens_at)
          ORDER BY o.slot_start)
      FROM (
        SELECT s.slot_start,
               public.sports_venue_booking_release_opens_at_for_slot(
                 v_timezone, v_mode,
                 v_court_days, v_court_time, v_court_window,
                 v_venue_days, v_venue_time, v_venue_window,
                 s.slot_start) AS opens_at
        FROM (
          SELECT (gen::date + (hour_num || ' hours')::interval)
                 AT TIME ZONE v_timezone AS slot_start
          FROM generate_series(
            (p_from AT TIME ZONE v_timezone)::date,
            (p_to AT TIME ZONE v_timezone)::date,
            '1 day'::interval) AS gen,
          generate_series(0, 23) AS hour_num
        ) s
        WHERE s.slot_start >= p_from AND s.slot_start < p_to
      ) o
      WHERE o.opens_at > now()
    ), '[]'::jsonb) END,
    'release', CASE WHEN v_effective_days IS NULL THEN NULL
      ELSE JSONB_BUILD_OBJECT(
        'mode', v_mode,
        'dayOfWeek', v_effective_days[1],
        'daysOfWeek', v_effective_days,
        'releaseTime', COALESCE(v_selected_time, v_court_time, v_venue_time),
        'windowDays', COALESCE(v_selected_window,
                               v_court_window, v_venue_window),
        'selectedDayReleaseTime', v_selected_time,
        'selectedDayOpensAt', v_selected_opens_at)
      END
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
