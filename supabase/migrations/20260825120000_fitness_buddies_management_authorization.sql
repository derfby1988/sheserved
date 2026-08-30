-- Fitness Buddies: group-management authorization
-- Group owners/group admins and Sheserved admins may manage a group.
-- The Flutter repository validates the custom AuthService identity before calling
-- direct table mutations; these RPCs apply the same manager rule in the database.

CREATE OR REPLACE FUNCTION public.is_fitness_group_manager(
  p_group_id UUID,
  p_actor_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_groups g
    WHERE g.id = p_group_id
      AND (
        g.created_by = p_actor_id
        OR EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = p_actor_id
            AND u.role = 'admin'
        )
        OR EXISTS (
          SELECT 1
          FROM public.fitness_group_members m
          WHERE m.group_id = p_group_id
            AND m.user_id = p_actor_id
            AND m.role = 'admin'
            AND m.is_active = true
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.leave_fitness_group(
  p_group_id UUID,
  p_user_id UUID,
  p_actor_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_group_exists BOOLEAN;
  v_is_owner BOOLEAN;
  v_can_manage BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_groups g
    WHERE g.id = p_group_id
  ) INTO v_group_exists;

  IF NOT v_group_exists THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;

  SELECT g.created_by = p_user_id
  INTO v_is_owner
  FROM public.fitness_groups g
  WHERE g.id = p_group_id;

  IF COALESCE(v_is_owner, false) THEN
    RAISE EXCEPTION 'OWNER_USE_PARTICIPATION_TOGGLE';
  END IF;

  v_can_manage := p_actor_id = p_user_id
    OR public.is_fitness_group_manager(p_group_id, p_actor_id);

  IF NOT COALESCE(v_can_manage, false) THEN
    RAISE EXCEPTION 'NOT_GROUP_ADMIN';
  END IF;

  UPDATE public.fitness_group_members
  SET is_active = false
  WHERE group_id = p_group_id
    AND user_id = p_user_id;

  UPDATE public.fitness_group_bookings b
  SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = CASE
      WHEN p_actor_id = p_user_id THEN 'user'
      ELSE 'owner'
    END,
    cancel_reason = CASE
      WHEN p_actor_id = p_user_id THEN 'LEAVE_GROUP'
      ELSE 'REMOVED_BY_ADMIN'
    END
  FROM public.fitness_group_sessions s
  WHERE b.session_id = s.id
    AND s.group_id = p_group_id
    AND b.user_id = p_user_id
    AND b.status IN ('pending', 'confirmed');
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_fitness_session_booking(
  p_booking_id UUID,
  p_owner_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_user_id UUID;
  v_session_id UUID;
  v_group_id UUID;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_can_manage BOOLEAN;
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

  SELECT public.is_fitness_group_manager(v_group_id, p_owner_id)
  INTO v_can_manage;

  IF NOT COALESCE(v_can_manage, false) THEN
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
$$;

GRANT EXECUTE ON FUNCTION public.is_fitness_group_manager(UUID, UUID)
TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.leave_fitness_group(UUID, UUID, UUID)
TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_fitness_session_booking(UUID, UUID)
TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
