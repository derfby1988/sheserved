CREATE OR REPLACE FUNCTION public.remove_fitness_session_participant(
  p_booking_id UUID,
  p_actor_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_target_user_id UUID;
  v_status TEXT;
  v_group_id UUID;
  v_group_owner_id UUID;
  v_can_manage BOOLEAN;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT
    b.user_id,
    b.status,
    s.group_id,
    g.created_by
  INTO
    v_target_user_id,
    v_status,
    v_group_id,
    v_group_owner_id
  FROM public.fitness_group_bookings b
  JOIN public.fitness_group_sessions s ON s.id = b.session_id
  JOIN public.fitness_groups g ON g.id = s.group_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b, s, g;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT public.is_fitness_group_manager(v_group_id, p_actor_id)
  INTO v_can_manage;

  IF NOT COALESCE(v_can_manage, false) THEN
    RAISE EXCEPTION 'NOT_GROUP_ADMIN';
  END IF;

  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'BOOKING_NOT_CONFIRMED';
  END IF;

  IF v_target_user_id = v_group_owner_id THEN
    RAISE EXCEPTION 'OWNER_USE_PARTICIPATION_TOGGLE';
  END IF;

  UPDATE public.fitness_group_bookings
  SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = 'owner',
    cancel_reason = 'REMOVED_FROM_SESSION'
  WHERE id = p_booking_id;

  IF NOT EXISTS (
    SELECT 1
    FROM public.fitness_group_members m
    WHERE m.group_id = v_group_id
      AND m.user_id = v_target_user_id
      AND m.role = 'admin'
      AND m.is_active = true
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE s.group_id = v_group_id
      AND b.user_id = v_target_user_id
      AND b.status = 'confirmed'
  ) THEN
    UPDATE public.fitness_group_members
    SET is_active = false
    WHERE group_id = v_group_id
      AND user_id = v_target_user_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_fitness_session_participant(
  p_booking_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.remove_fitness_session_participant(
    p_booking_id,
    app.require_current_user_id()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.remove_fitness_session_participant(UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.remove_fitness_session_participant(UUID, UUID)
TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
