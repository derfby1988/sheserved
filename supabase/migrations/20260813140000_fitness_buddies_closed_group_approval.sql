-- Fitness Buddies: closed-group approval flow fix
-- Date: 2026-08-13
--
-- Goals:
-- 1) Allow closed groups (requires_owner_approval = true) to create pending bookings
--    without failing on overlap at request time.
-- 2) Enforce overlap only when an owner approves the pending booking.
-- 3) Keep open groups enforcing overlap at booking time.

CREATE OR REPLACE FUNCTION public.book_fitness_session(p_session_id UUID, p_user_id UUID)
RETURNS UUID AS $$
DECLARE
  v_group_id UUID;
  v_capacity INT;
  v_booking_id UUID;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_overlaps BOOLEAN;
  v_requires_approval BOOLEAN;
  v_status TEXT;
BEGIN
  SELECT s.group_id, g.capacity, s.starts_at, s.ends_at, g.requires_owner_approval
  INTO v_group_id, v_capacity, v_starts, v_ends, v_requires_approval
  FROM public.fitness_group_sessions s
  JOIN public.fitness_groups g ON g.id = s.group_id
  WHERE s.id = p_session_id
  FOR UPDATE OF g;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_NOT_FOUND';
  END IF;

  v_requires_approval := COALESCE(v_requires_approval, false);

  IF NOT v_requires_approval THEN
    SELECT public.check_booking_overlap(p_user_id, v_starts, v_ends) INTO v_overlaps;
    IF v_overlaps THEN
      RAISE EXCEPTION 'OVERLAP_BOOKING';
    END IF;
  END IF;

  IF (
    SELECT COUNT(1)
    FROM public.fitness_group_bookings b
    WHERE b.session_id = p_session_id AND b.status IN ('pending','confirmed')
  ) >= v_capacity THEN
    RAISE EXCEPTION 'GROUP_FULL';
  END IF;

  v_status := CASE WHEN v_requires_approval THEN 'pending' ELSE 'confirmed' END;

  INSERT INTO public.fitness_group_bookings (session_id, user_id, status)
  VALUES (p_session_id, p_user_id, v_status)
  ON CONFLICT (session_id, user_id)
  DO UPDATE SET status = EXCLUDED.status, cancelled_at = NULL, cancel_reason = NULL, cancelled_by = NULL
  RETURNING id INTO v_booking_id;

  INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
  VALUES (v_group_id, p_user_id, 'member', true, now())
  ON CONFLICT (group_id, user_id) DO UPDATE SET is_active = true;

  RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.approve_fitness_session_booking(p_booking_id UUID, p_owner_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_session_id UUID;
  v_group_id UUID;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_is_admin BOOLEAN;
  v_overlaps BOOLEAN;
BEGIN
  SELECT b.user_id, b.session_id, s.group_id, s.starts_at, s.ends_at
  INTO v_user_id, v_session_id, v_group_id, v_starts, v_ends
  FROM public.fitness_group_bookings b
  JOIN public.fitness_group_sessions s ON s.id = b.session_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b, s;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_members m
    WHERE m.group_id = v_group_id
      AND m.user_id = p_owner_id
      AND m.role = 'admin'
      AND m.is_active = true
  ) INTO v_is_admin;

  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'NOT_GROUP_ADMIN';
  END IF;

  IF (
    SELECT status
    FROM public.fitness_group_bookings
    WHERE id = p_booking_id
  ) <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE b.user_id = v_user_id
      AND b.id <> p_booking_id
      AND b.status IN ('pending', 'confirmed')
      AND (s.starts_at, s.ends_at) OVERLAPS (v_starts, v_ends)
  ) INTO v_overlaps;

  IF v_overlaps THEN
    RAISE EXCEPTION 'OVERLAP_BOOKING';
  END IF;

  UPDATE public.fitness_group_bookings
  SET status = 'confirmed'
  WHERE id = p_booking_id;
END;
$$ LANGUAGE plpgsql;

NOTIFY pgrst, 'reload schema';
