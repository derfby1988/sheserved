-- Fitness Buddies: atomic leave/remove group membership
-- The Flutter repository already calls leave_fitness_group, but the RPC was
-- missing from the migrations and PostgREST could not resolve the call.
-- This project uses custom AuthService, so authorization is app-layer based.

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

  SELECT
    p_actor_id = p_user_id
    OR g.created_by = p_actor_id
    OR EXISTS (
      SELECT 1
      FROM public.fitness_group_members m
      WHERE m.group_id = p_group_id
        AND m.user_id = p_actor_id
        AND m.role = 'admin'
        AND m.is_active = true
    )
  INTO v_can_manage
  FROM public.fitness_groups g
  WHERE g.id = p_group_id;

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

GRANT EXECUTE ON FUNCTION public.leave_fitness_group(UUID, UUID, UUID)
TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
