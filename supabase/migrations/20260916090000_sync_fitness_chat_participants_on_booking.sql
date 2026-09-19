CREATE OR REPLACE FUNCTION public.refresh_fitness_chat_participants(
  p_group_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.chat_rooms cr
  SET participant_ids = (
    SELECT COALESCE(array_agg(m.user_id ORDER BY m.user_id), ARRAY[]::UUID[])
    FROM public.fitness_group_members m
    JOIN public.fitness_groups g ON g.id = m.group_id
    WHERE m.group_id = p_group_id
      AND m.is_active = true
      AND NOT EXISTS (
        SELECT 1
        FROM public.fitness_group_blocklist bl
        WHERE bl.group_id = m.group_id
          AND bl.blocked_user_id = m.user_id
          AND bl.is_active = true
      )
      AND (
        (
          m.role = 'admin'
          AND (
            g.created_by IS NULL
            OR m.user_id IS DISTINCT FROM g.created_by
            OR COALESCE(g.owner_auto_join, true)
            OR EXISTS (
              SELECT 1
              FROM public.fitness_group_bookings b
              JOIN public.fitness_group_sessions s ON s.id = b.session_id
              WHERE s.group_id = m.group_id
                AND b.user_id = m.user_id
                AND b.status = 'confirmed'
                AND s.ends_at >= now()
            )
          )
        )
        OR EXISTS (
          SELECT 1
          FROM public.fitness_group_bookings b
          JOIN public.fitness_group_sessions s ON s.id = b.session_id
          WHERE s.group_id = m.group_id
            AND b.user_id = m.user_id
            AND b.status = 'confirmed'
        )
      )
  )
  WHERE cr.room_type = 'fitness_group'
    AND cr.room_ref_id = p_group_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_fitness_chat_participants()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_group_id UUID;
BEGIN
  v_group_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.group_id ELSE NEW.group_id END;
  PERFORM public.refresh_fitness_chat_participants(v_group_id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_fitness_group_member_from_booking()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_session_id UUID;
  v_group_id UUID;
  v_user_id UUID;
  v_owner_id UUID;
  v_owner_auto_join BOOLEAN;
  v_role TEXT;
  v_is_blocked BOOLEAN;
  v_has_confirmed BOOLEAN;
  v_has_upcoming_confirmed BOOLEAN;
  v_should_be_active BOOLEAN;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_session_id := OLD.session_id;
    v_user_id := OLD.user_id;
  ELSE
    v_session_id := NEW.session_id;
    v_user_id := NEW.user_id;
  END IF;

  SELECT s.group_id, g.created_by, COALESCE(g.owner_auto_join, true)
  INTO v_group_id, v_owner_id, v_owner_auto_join
  FROM public.fitness_group_sessions s
  JOIN public.fitness_groups g ON g.id = s.group_id
  WHERE s.id = v_session_id;

  IF v_group_id IS NULL OR v_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT m.role
  INTO v_role
  FROM public.fitness_group_members m
  WHERE m.group_id = v_group_id
    AND m.user_id = v_user_id;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_blocklist bl
    WHERE bl.group_id = v_group_id
      AND bl.blocked_user_id = v_user_id
      AND bl.is_active = true
  )
  INTO v_is_blocked;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE s.group_id = v_group_id
      AND b.user_id = v_user_id
      AND b.status = 'confirmed'
  )
  INTO v_has_confirmed;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE s.group_id = v_group_id
      AND b.user_id = v_user_id
      AND b.status = 'confirmed'
      AND s.ends_at >= now()
  )
  INTO v_has_upcoming_confirmed;

  v_should_be_active := NOT COALESCE(v_is_blocked, false)
    AND CASE
      WHEN v_user_id = v_owner_id THEN
        v_owner_auto_join OR v_has_upcoming_confirmed
      ELSE
        v_role = 'admin' OR v_has_confirmed
    END;

  IF v_should_be_active THEN
    INSERT INTO public.fitness_group_members (
      group_id,
      user_id,
      role,
      is_active,
      joined_at
    )
    VALUES (
      v_group_id,
      v_user_id,
      CASE WHEN v_user_id = v_owner_id THEN 'admin' ELSE 'member' END,
      true,
      now()
    )
    ON CONFLICT (group_id, user_id)
    DO UPDATE SET
      role = CASE
        WHEN v_user_id = v_owner_id THEN 'admin'
        ELSE public.fitness_group_members.role
      END,
      is_active = true,
      joined_at = COALESCE(public.fitness_group_members.joined_at, now());
  ELSE
    UPDATE public.fitness_group_members
    SET is_active = false
    WHERE group_id = v_group_id
      AND user_id = v_user_id;
  END IF;

  PERFORM public.refresh_fitness_chat_participants(v_group_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_fitness_chat_on_booking
  ON public.fitness_group_bookings;
CREATE TRIGGER trg_sync_fitness_chat_on_booking
AFTER INSERT OR UPDATE OF status OR DELETE
ON public.fitness_group_bookings
FOR EACH ROW
EXECUTE FUNCTION public.sync_fitness_group_member_from_booking();

UPDATE public.fitness_group_members m
SET is_active = CASE
  WHEN EXISTS (
    SELECT 1
    FROM public.fitness_group_blocklist bl
    WHERE bl.group_id = m.group_id
      AND bl.blocked_user_id = m.user_id
      AND bl.is_active = true
  ) THEN false
  WHEN m.user_id = g.created_by THEN
    COALESCE(g.owner_auto_join, true)
    OR EXISTS (
      SELECT 1
      FROM public.fitness_group_bookings b
      JOIN public.fitness_group_sessions s ON s.id = b.session_id
      WHERE s.group_id = m.group_id
        AND b.user_id = m.user_id
        AND b.status = 'confirmed'
        AND s.ends_at >= now()
    )
  WHEN m.role = 'admin' THEN true
  ELSE EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE s.group_id = m.group_id
      AND b.user_id = m.user_id
      AND b.status = 'confirmed'
  )
END
FROM public.fitness_groups g
WHERE g.id = m.group_id;

DO $$
DECLARE
  v_group_id UUID;
BEGIN
  FOR v_group_id IN SELECT id FROM public.fitness_groups LOOP
    PERFORM public.refresh_fitness_chat_participants(v_group_id);
  END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
