-- Fitness Buddies: owner rejoin bypasses closed-group approval
-- Phase 9: an owner who opted out can rejoin by booking a session directly.
-- The owner is confirmed immediately even when requires_owner_approval = true.

CREATE OR REPLACE FUNCTION public.book_fitness_session(p_session_id UUID, p_user_id UUID)
RETURNS UUID AS $$
DECLARE
  v_group_id UUID;
  v_capacity INT;
  v_owner_auto_join BOOLEAN;
  v_owner_id UUID;
  v_is_owner BOOLEAN;
  v_booking_id UUID;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_overlaps BOOLEAN;
  v_requires_approval BOOLEAN;
  v_status TEXT;
  v_current_members INT;
  v_already_booked BOOLEAN;
BEGIN
  SELECT
    s.group_id,
    g.capacity,
    COALESCE(g.owner_auto_join, true),
    g.created_by,
    s.starts_at,
    s.ends_at,
    COALESCE(g.requires_owner_approval, false)
  INTO
    v_group_id,
    v_capacity,
    v_owner_auto_join,
    v_owner_id,
    v_starts,
    v_ends,
    v_requires_approval
  FROM public.fitness_group_sessions s
  JOIN public.fitness_groups g ON g.id = s.group_id
  WHERE s.id = p_session_id
  FOR UPDATE OF g;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_NOT_FOUND';
  END IF;

  v_is_owner := COALESCE(v_owner_id = p_user_id, false);
  -- The owner can rejoin a private group without waiting for approval.
  v_requires_approval := v_requires_approval AND NOT v_is_owner;

  IF NOT v_requires_approval THEN
    SELECT public.check_booking_overlap(p_user_id, v_starts, v_ends)
    INTO v_overlaps;
    IF v_overlaps THEN
      RAISE EXCEPTION 'OVERLAP_BOOKING';
    END IF;
  END IF;

  -- Count the effective group capacity. The owner consumes one slot when already
  -- auto-joined, or when this booking is the owner's rejoin operation. Other users
  -- reserve a slot through pending/confirmed bookings across the group.
  SELECT
    (
      CASE WHEN v_owner_auto_join OR v_is_owner THEN 1 ELSE 0 END
      + COUNT(
          DISTINCT CASE
            WHEN v_owner_id IS NULL OR b.user_id <> v_owner_id THEN b.user_id
          END
        )
    )::INT
  INTO v_current_members
  FROM public.fitness_group_sessions s
  LEFT JOIN public.fitness_group_bookings b
    ON b.session_id = s.id
    AND b.status IN ('pending', 'confirmed')
  WHERE s.group_id = v_group_id;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE s.group_id = v_group_id
      AND b.user_id = p_user_id
      AND b.status IN ('pending', 'confirmed')
  ) INTO v_already_booked;

  -- The owner is already represented by owner_auto_join or by the rejoin slot;
  -- do not charge a second slot for the booking itself.
  IF NOT v_already_booked AND NOT v_is_owner THEN
    v_current_members := v_current_members + 1;
  END IF;

  IF v_current_members > v_capacity THEN
    RAISE EXCEPTION 'GROUP_FULL';
  END IF;

  v_status := CASE WHEN v_requires_approval THEN 'pending' ELSE 'confirmed' END;

  INSERT INTO public.fitness_group_bookings (session_id, user_id, status)
  VALUES (p_session_id, p_user_id, v_status)
  ON CONFLICT (session_id, user_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    cancelled_at = NULL,
    cancel_reason = NULL,
    cancelled_by = NULL
  RETURNING id INTO v_booking_id;

  -- Booking is the owner's explicit rejoin action. Restore the owner flag so
  -- subsequent capacity, member-list, and chat synchronization use one state.
  IF v_is_owner AND NOT v_owner_auto_join THEN
    UPDATE public.fitness_groups
    SET owner_auto_join = true
    WHERE id = v_group_id;
  END IF;

  INSERT INTO public.fitness_group_members (
    group_id,
    user_id,
    role,
    is_active,
    joined_at
  )
  VALUES (
    v_group_id,
    p_user_id,
    CASE WHEN v_is_owner THEN 'admin' ELSE 'member' END,
    true,
    now()
  )
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET
    role = CASE WHEN v_is_owner THEN 'admin' ELSE fitness_group_members.role END,
    is_active = true,
    joined_at = COALESCE(fitness_group_members.joined_at, now());

  RETURN v_booking_id;
END;
$$ LANGUAGE plpgsql;

NOTIFY pgrst, 'reload schema';
