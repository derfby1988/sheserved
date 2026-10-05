CREATE OR REPLACE FUNCTION public.manage_sports_venue_availability(
  p_user_id UUID,
  p_court_id UUID,
  p_action TEXT,
  p_ranges JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue_id UUID;
  v_timezone TEXT;
  v_count INT;
  v_item JSONB;
  v_starts TIMESTAMPTZ[] := ARRAY[]::TIMESTAMPTZ[];
  v_ends TIMESTAMPTZ[] := ARRAY[]::TIMESTAMPTZ[];
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
  v_local_start TIMESTAMP;
  v_local_end TIMESTAMP;
  v_selection_date DATE;
  v_now TIMESTAMPTZ := now();
  v_i INT;
  v_j INT;
  v_cursor TIMESTAMPTZ;
  v_cut_start TIMESTAMPTZ;
  v_cut_end TIMESTAMPTZ;
  v_block RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_action IS NULL OR p_action NOT IN ('suspend', 'unsuspend') THEN
    RAISE EXCEPTION 'INVALID_AVAILABILITY_ACTION';
  END IF;
  IF p_ranges IS NULL OR jsonb_typeof(p_ranges) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGES';
  END IF;
  v_count := jsonb_array_length(p_ranges);
  IF v_count < 1 OR v_count > 24 THEN
    RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGES';
  END IF;

  SELECT c.venue_id, v.timezone
    INTO v_venue_id, v_timezone
  FROM public.sports_venue_courts c
  JOIN public.sports_venues v ON v.id = c.venue_id
  WHERE c.id = p_court_id
    AND c.is_active
    AND v.status = 'approved'
  FOR UPDATE OF c;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.sports_venue_owner_profiles op
    JOIN public.sports_venues v ON v.owner_profile_id = op.id
    WHERE v.id = v_venue_id AND op.user_id = p_user_id
  ) AND NOT EXISTS (
    SELECT 1
    FROM public.sports_venue_owner_members m
    WHERE m.venue_id = v_venue_id
      AND m.user_id = p_user_id
      AND m.is_active
      AND m.role IN ('owner', 'manager')
  ) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_ranges)
  LOOP
    BEGIN
      v_start := NULLIF(v_item->>'starts_at', '')::TIMESTAMPTZ;
      v_end := NULLIF(v_item->>'ends_at', '')::TIMESTAMPTZ;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGE';
    END;

    IF v_start IS NULL OR v_end IS NULL OR v_end <= v_start
       OR v_start < v_now THEN
      RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGE';
    END IF;

    v_local_start := v_start AT TIME ZONE v_timezone;
    v_local_end := v_end AT TIME ZONE v_timezone;
    IF EXTRACT(MINUTE FROM v_local_start) <> 0
       OR EXTRACT(SECOND FROM v_local_start) <> 0
       OR EXTRACT(MINUTE FROM v_local_end) <> 0
       OR EXTRACT(SECOND FROM v_local_end) <> 0
       OR v_local_end <= v_local_start
       OR v_local_end::DATE <> v_local_start::DATE
       OR EXTRACT(EPOCH FROM (v_local_end - v_local_start))::BIGINT % 3600 <> 0
       OR EXTRACT(EPOCH FROM (v_local_end - v_local_start)) > 86400 THEN
      RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGE';
    END IF;
    IF v_selection_date IS NULL THEN
      v_selection_date := v_local_start::DATE;
    ELSIF v_selection_date <> v_local_start::DATE THEN
      RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGES';
    END IF;

    v_starts := array_append(v_starts, v_start);
    v_ends := array_append(v_ends, v_end);
  END LOOP;

  FOR v_i IN 2..v_count LOOP
    IF v_starts[v_i] < v_starts[v_i - 1] THEN
      RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGES';
    END IF;
  END LOOP;

  FOR v_i IN 1..v_count LOOP
    FOR v_j IN (v_i + 1)..v_count LOOP
      IF v_starts[v_i] < v_ends[v_j]
         AND v_ends[v_i] > v_starts[v_j] THEN
        RAISE EXCEPTION 'INVALID_AVAILABILITY_RANGES';
      END IF;
    END LOOP;
  END LOOP;

  IF p_action = 'suspend' THEN
    FOR v_i IN 1..v_count LOOP
      IF EXISTS (
        SELECT 1
        FROM public.sports_venue_bookings b
        WHERE b.court_id = p_court_id
          AND b.status IN ('pending', 'confirmed')
          AND b.starts_at < v_ends[v_i]
          AND b.ends_at > v_starts[v_i]
      ) THEN
        RAISE EXCEPTION 'AVAILABILITY_RANGE_HAS_BOOKING';
      END IF;
      IF EXISTS (
        SELECT 1
        FROM public.sports_venue_availability a
        WHERE a.court_id = p_court_id
          AND a.kind = 'blocked'
          AND a.starts_at < v_ends[v_i]
          AND a.ends_at > v_starts[v_i]
      ) THEN
        RAISE EXCEPTION 'AVAILABILITY_ALREADY_SUSPENDED';
      END IF;
      IF public.sports_venue_slot_blocked(
        p_court_id, v_starts[v_i], v_ends[v_i]
      ) THEN
        RAISE EXCEPTION 'AVAILABILITY_OUTSIDE_OPERATING_HOURS';
      END IF;
    END LOOP;

    FOR v_i IN 1..v_count LOOP
      INSERT INTO public.sports_venue_availability (
        court_id, starts_at, ends_at, kind
      ) VALUES (
        p_court_id, v_starts[v_i], v_ends[v_i], 'blocked'
      );
    END LOOP;
    RETURN;
  END IF;

  FOR v_i IN 1..v_count LOOP
    PERFORM 1
    FROM public.sports_venue_availability a
    WHERE a.court_id = p_court_id
      AND a.kind = 'blocked'
      AND a.starts_at < v_ends[v_i]
      AND a.ends_at > v_starts[v_i]
    FOR UPDATE;

    v_cursor := v_starts[v_i];
    WHILE v_cursor < v_ends[v_i] LOOP
      v_cut_end := LEAST(v_cursor + interval '1 hour', v_ends[v_i]);
      IF NOT EXISTS (
        SELECT 1
        FROM public.sports_venue_availability a
        WHERE a.court_id = p_court_id
          AND a.kind = 'blocked'
          AND a.starts_at < v_cut_end
          AND a.ends_at > v_cursor
      ) THEN
        RAISE EXCEPTION 'AVAILABILITY_NOT_SUSPENDED';
      END IF;
      v_cursor := v_cut_end;
    END LOOP;
  END LOOP;

  FOR v_block IN
    SELECT a.id, a.starts_at, a.ends_at, a.note
    FROM public.sports_venue_availability a
    WHERE a.court_id = p_court_id
      AND a.kind = 'blocked'
      AND EXISTS (
        SELECT 1
        FROM generate_subscripts(v_starts, 1) i
        WHERE a.starts_at < v_ends[i]
          AND a.ends_at > v_starts[i]
      )
    FOR UPDATE
  LOOP
    v_cursor := v_block.starts_at;
    FOR v_i IN 1..v_count LOOP
      IF v_starts[v_i] < v_block.ends_at
         AND v_ends[v_i] > v_block.starts_at THEN
        v_cut_start := GREATEST(v_starts[v_i], v_block.starts_at);
        v_cut_end := LEAST(v_ends[v_i], v_block.ends_at);
        IF v_cut_start > v_cursor THEN
          INSERT INTO public.sports_venue_availability (
            court_id, starts_at, ends_at, kind, note
          ) VALUES (
            p_court_id, v_cursor, v_cut_start, 'blocked', v_block.note
          );
        END IF;
        v_cursor := GREATEST(v_cursor, v_cut_end);
      END IF;
    END LOOP;
    IF v_cursor < v_block.ends_at THEN
      INSERT INTO public.sports_venue_availability (
        court_id, starts_at, ends_at, kind, note
      ) VALUES (
        p_court_id, v_cursor, v_block.ends_at, 'blocked', v_block.note
      );
    END IF;
    DELETE FROM public.sports_venue_availability WHERE id = v_block.id;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.manage_sports_venue_availability(
  UUID, UUID, TEXT, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.manage_sports_venue_availability(
  UUID, UUID, TEXT, JSONB
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
