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

  IF (p_ends_at AT TIME ZONE v_tz)::date
     <> (p_starts_at AT TIME ZONE v_tz)::date THEN
    RETURN true;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.sports_venue_operating_hours h
    WHERE h.venue_id = v_venue_id
  ) THEN
    RETURN true;
  END IF;

  v_dow := EXTRACT(ISODOW FROM p_starts_at AT TIME ZONE v_tz)::int % 7;
  v_local_start := (p_starts_at AT TIME ZONE v_tz)::time;
  v_local_end := (p_ends_at AT TIME ZONE v_tz)::time;

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
