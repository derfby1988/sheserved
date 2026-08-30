ALTER TABLE public.fitness_group_sessions
  ADD COLUMN IF NOT EXISTS capacity INTEGER;

UPDATE public.fitness_group_sessions s
SET capacity = COALESCE(s.capacity, g.capacity, 5)
FROM public.fitness_groups g
WHERE g.id = s.group_id
  AND s.capacity IS NULL;

ALTER TABLE public.fitness_group_sessions
  ALTER COLUMN capacity SET DEFAULT 5;

ALTER TABLE public.fitness_group_sessions
  ALTER COLUMN capacity SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class r ON r.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = r.relnamespace
    WHERE n.nspname = 'public'
      AND r.relname = 'fitness_group_sessions'
      AND c.conname = 'fitness_group_sessions_capacity_range'
  ) THEN
    ALTER TABLE public.fitness_group_sessions
      ADD CONSTRAINT fitness_group_sessions_capacity_range
      CHECK (capacity BETWEEN 1 AND 30);
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.fitness_groups g
    JOIN public.fitness_group_sessions s1 ON s1.group_id = g.id
    JOIN public.fitness_group_sessions s2
      ON s2.group_id = s1.group_id
     AND s1.id < s2.id
    WHERE COALESCE(g.owner_auto_join, true)
      AND g.created_by IS NOT NULL
      AND s1.ends_at >= now()
      AND s2.ends_at >= now()
      AND (s1.starts_at, s1.ends_at) OVERLAPS (s2.starts_at, s2.ends_at)
  ) THEN
    RAISE EXCEPTION 'OWNER_AUTO_JOIN_OVERLAP_EXISTING_DATA';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.fitness_groups g
    JOIN public.fitness_group_sessions s ON s.group_id = g.id
    WHERE COALESCE(g.owner_auto_join, true)
      AND g.created_by IS NOT NULL
      AND s.ends_at >= now()
      AND (
        SELECT COUNT(DISTINCT b.user_id)
        FROM public.fitness_group_bookings b
        WHERE b.session_id = s.id
          AND b.status = 'confirmed'
      ) >= s.capacity
      AND NOT EXISTS (
        SELECT 1
        FROM public.fitness_group_bookings b
        WHERE b.session_id = s.id
          AND b.user_id = g.created_by
          AND b.status = 'confirmed'
      )
  ) THEN
    RAISE EXCEPTION 'OWNER_AUTO_JOIN_CAPACITY_EXISTING_DATA';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.create_fitness_group_side_effects()
RETURNS TRIGGER AS $$
DECLARE
  v_room_id TEXT;
  v_owner_active BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_room_id := 'group_' || NEW.id::text;

    INSERT INTO public.chat_rooms (id, participant_ids, last_message, room_type, room_ref_id)
      VALUES (v_room_id, ARRAY[]::UUID[], NULL, 'fitness_group', NEW.id)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  IF NEW.created_by IS NOT NULL THEN
    SELECT COALESCE(NEW.owner_auto_join, true)
      OR EXISTS (
        SELECT 1
        FROM public.fitness_group_bookings b
        JOIN public.fitness_group_sessions s ON s.id = b.session_id
        WHERE s.group_id = NEW.id
          AND b.user_id = NEW.created_by
          AND b.status = 'confirmed'
          AND s.ends_at >= now()
      )
    INTO v_owner_active;

    INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
      VALUES (NEW.id, NEW.created_by, 'admin', COALESCE(v_owner_active, false), now())
    ON CONFLICT (group_id, user_id)
      DO UPDATE SET
        role = 'admin',
        is_active = EXCLUDED.is_active,
        joined_at = now();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_fitness_group_side_effects ON public.fitness_groups;
CREATE TRIGGER trg_create_fitness_group_side_effects
AFTER INSERT OR UPDATE ON public.fitness_groups
FOR EACH ROW EXECUTE FUNCTION public.create_fitness_group_side_effects();

CREATE OR REPLACE FUNCTION public.sync_fitness_session_owner_booking()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_id UUID;
  v_owner_auto_join BOOLEAN;
BEGIN
  SELECT g.created_by, COALESCE(g.owner_auto_join, true)
  INTO v_owner_id, v_owner_auto_join
  FROM public.fitness_groups g
  WHERE g.id = NEW.group_id;

  IF v_owner_id IS NOT NULL AND v_owner_auto_join THEN
    INSERT INTO public.fitness_group_bookings (session_id, user_id, status)
    VALUES (NEW.id, v_owner_id, 'confirmed')
    ON CONFLICT (session_id, user_id)
    DO UPDATE SET
      status = 'confirmed',
      cancelled_at = NULL,
      cancelled_by = NULL,
      cancel_reason = NULL;

    INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
    VALUES (NEW.group_id, v_owner_id, 'admin', true, now())
    ON CONFLICT (group_id, user_id)
    DO UPDATE SET
      role = 'admin',
      is_active = true,
      joined_at = COALESCE(public.fitness_group_members.joined_at, now());
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_fitness_session_owner_booking
  ON public.fitness_group_sessions;
CREATE TRIGGER trg_sync_fitness_session_owner_booking
AFTER INSERT ON public.fitness_group_sessions
FOR EACH ROW EXECUTE FUNCTION public.sync_fitness_session_owner_booking();

CREATE OR REPLACE FUNCTION public.guard_fitness_session_owner_overlap()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_auto_join BOOLEAN;
BEGIN
  SELECT COALESCE(g.owner_auto_join, true)
  INTO v_owner_auto_join
  FROM public.fitness_groups g
  WHERE g.id = NEW.group_id;

  IF v_owner_auto_join
     AND NEW.ends_at >= now()
     AND EXISTS (
       SELECT 1
       FROM public.fitness_group_sessions s
       WHERE s.group_id = NEW.group_id
         AND s.id <> NEW.id
         AND s.ends_at >= now()
         AND (s.starts_at, s.ends_at) OVERLAPS (NEW.starts_at, NEW.ends_at)
     ) THEN
    RAISE EXCEPTION 'OWNER_AUTO_JOIN_OVERLAP';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_fitness_session_owner_overlap
  ON public.fitness_group_sessions;
CREATE TRIGGER trg_guard_fitness_session_owner_overlap
BEFORE INSERT OR UPDATE OF starts_at, ends_at ON public.fitness_group_sessions
FOR EACH ROW EXECUTE FUNCTION public.guard_fitness_session_owner_overlap();

INSERT INTO public.fitness_group_bookings (session_id, user_id, status)
SELECT s.id, g.created_by, 'confirmed'
FROM public.fitness_group_sessions s
JOIN public.fitness_groups g ON g.id = s.group_id
WHERE COALESCE(g.owner_auto_join, true)
  AND g.created_by IS NOT NULL
  AND s.ends_at >= now()
ON CONFLICT (session_id, user_id)
DO UPDATE SET
  status = 'confirmed',
  cancelled_at = NULL,
  cancelled_by = NULL,
  cancel_reason = NULL;

CREATE OR REPLACE FUNCTION public.sync_fitness_owner_membership_from_booking()
RETURNS TRIGGER AS $$
DECLARE
  v_group_id UUID;
  v_owner_id UUID;
  v_owner_auto_join BOOLEAN;
  v_has_confirmed_booking BOOLEAN;
BEGIN
  SELECT s.group_id, g.created_by, COALESCE(g.owner_auto_join, true)
  INTO v_group_id, v_owner_id, v_owner_auto_join
  FROM public.fitness_group_sessions s
  JOIN public.fitness_groups g ON g.id = s.group_id
  WHERE s.id = NEW.session_id;

  IF v_group_id IS NULL OR NEW.user_id IS DISTINCT FROM v_owner_id THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE s.group_id = v_group_id
      AND b.user_id = v_owner_id
      AND b.status = 'confirmed'
      AND s.ends_at >= now()
  ) INTO v_has_confirmed_booking;

  INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
  VALUES (
    v_group_id,
    v_owner_id,
    'admin',
    v_owner_auto_join OR v_has_confirmed_booking,
    now()
  )
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET
    role = 'admin',
    is_active = EXCLUDED.is_active,
    joined_at = COALESCE(public.fitness_group_members.joined_at, now());

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_fitness_owner_membership_from_booking
  ON public.fitness_group_bookings;
CREATE TRIGGER trg_sync_fitness_owner_membership_from_booking
AFTER INSERT OR UPDATE OF status ON public.fitness_group_bookings
FOR EACH ROW EXECUTE FUNCTION public.sync_fitness_owner_membership_from_booking();

CREATE OR REPLACE FUNCTION public.set_fitness_group_owner_auto_join(
  p_group_id UUID,
  p_actor_id UUID,
  p_enabled BOOLEAN,
  p_cancel_bookings BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_owner_id UUID;
  v_current BOOLEAN;
  v_session RECORD;
  v_confirmed_count INT;
BEGIN
  SELECT g.created_by, COALESCE(g.owner_auto_join, true)
  INTO v_owner_id, v_current
  FROM public.fitness_groups g
  WHERE g.id = p_group_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;

  IF v_owner_id IS NULL OR v_owner_id <> p_actor_id THEN
    RAISE EXCEPTION 'OWNER_ONLY';
  END IF;

  IF p_enabled = v_current THEN
    RETURN;
  END IF;

  IF p_enabled THEN
    IF EXISTS (
      SELECT 1
      FROM public.fitness_group_sessions s1
      JOIN public.fitness_group_sessions s2
        ON s2.group_id = s1.group_id
       AND s1.id < s2.id
      WHERE s1.group_id = p_group_id
        AND s1.ends_at >= now()
        AND s2.ends_at >= now()
        AND (s1.starts_at, s1.ends_at) OVERLAPS (s2.starts_at, s2.ends_at)
    ) THEN
      RAISE EXCEPTION 'OWNER_AUTO_JOIN_OVERLAP';
    END IF;

    FOR v_session IN
      SELECT s.id, s.capacity
      FROM public.fitness_group_sessions s
      WHERE s.group_id = p_group_id
        AND s.ends_at >= now()
      ORDER BY s.starts_at, s.id
      FOR UPDATE
    LOOP
      SELECT COUNT(DISTINCT b.user_id)
      INTO v_confirmed_count
      FROM public.fitness_group_bookings b
      WHERE b.session_id = v_session.id
        AND b.status = 'confirmed';

      IF v_confirmed_count > v_session.capacity
         OR (
           v_confirmed_count >= v_session.capacity
           AND NOT EXISTS (
             SELECT 1
             FROM public.fitness_group_bookings b
             WHERE b.session_id = v_session.id
               AND b.user_id = v_owner_id
               AND b.status = 'confirmed'
           )
         ) THEN
        RAISE EXCEPTION 'OWNER_AUTO_JOIN_CAPACITY';
      END IF;
    END LOOP;

    UPDATE public.fitness_groups
    SET owner_auto_join = true
    WHERE id = p_group_id;

    INSERT INTO public.fitness_group_bookings (session_id, user_id, status)
    SELECT s.id, v_owner_id, 'confirmed'
    FROM public.fitness_group_sessions s
    WHERE s.group_id = p_group_id
      AND s.ends_at >= now()
    ON CONFLICT (session_id, user_id)
    DO UPDATE SET
      status = 'confirmed',
      cancelled_at = NULL,
      cancelled_by = NULL,
      cancel_reason = NULL;
  ELSE
    IF p_cancel_bookings THEN
      UPDATE public.fitness_group_bookings b
      SET
        status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = 'owner',
        cancel_reason = 'OWNER_AUTO_JOIN_DISABLED'
      FROM public.fitness_group_sessions s
      WHERE b.session_id = s.id
        AND s.group_id = p_group_id
        AND s.ends_at >= now()
        AND b.user_id = v_owner_id
        AND b.status IN ('pending', 'confirmed');
    END IF;

    UPDATE public.fitness_groups
    SET owner_auto_join = false
    WHERE id = p_group_id;
  END IF;

  UPDATE public.fitness_group_members m
  SET is_active = CASE
    WHEN p_enabled THEN true
    ELSE EXISTS (
      SELECT 1
      FROM public.fitness_group_bookings b
      JOIN public.fitness_group_sessions s ON s.id = b.session_id
      WHERE s.group_id = p_group_id
        AND b.user_id = v_owner_id
        AND b.status = 'confirmed'
        AND s.ends_at >= now()
    )
  END
  WHERE m.group_id = p_group_id
    AND m.user_id = v_owner_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.book_fitness_session(
  p_session_id UUID,
  p_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_group_id UUID;
  v_capacity INT;
  v_owner_auto_join BOOLEAN;
  v_owner_id UUID;
  v_booking_id UUID;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_overlaps BOOLEAN;
  v_requires_approval BOOLEAN;
  v_status TEXT;
  v_existing_status TEXT;
  v_confirmed_count INT;
  v_is_owner BOOLEAN;
BEGIN
  SELECT
    g.id,
    COALESCE(g.owner_auto_join, true),
    g.created_by,
    COALESCE(g.requires_owner_approval, false)
  INTO
    v_group_id,
    v_owner_auto_join,
    v_owner_id,
    v_requires_approval
  FROM public.fitness_groups g
  JOIN public.fitness_group_sessions s ON s.group_id = g.id
  WHERE s.id = p_session_id
  FOR UPDATE OF g;

  SELECT s.group_id, s.capacity, s.starts_at, s.ends_at
  INTO v_group_id, v_capacity, v_starts, v_ends
  FROM public.fitness_group_sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'SESSION_NOT_FOUND';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.fitness_group_blocklist bl
    WHERE bl.group_id = v_group_id
      AND bl.blocked_user_id = p_user_id
      AND bl.is_active = true
  ) THEN
    RAISE EXCEPTION 'USER_BLOCKED';
  END IF;

  v_is_owner := COALESCE(v_owner_id = p_user_id, false);
  v_requires_approval := v_requires_approval AND NOT v_is_owner;

  SELECT b.status
  INTO v_existing_status
  FROM public.fitness_group_bookings b
  WHERE b.session_id = p_session_id
    AND b.user_id = p_user_id
  FOR UPDATE;

  IF NOT (v_is_owner AND v_owner_auto_join) AND NOT v_requires_approval THEN
    SELECT public.check_booking_overlap(p_user_id, v_starts, v_ends)
    INTO v_overlaps;
    IF v_overlaps AND v_existing_status IS DISTINCT FROM 'confirmed' THEN
      RAISE EXCEPTION 'OVERLAP_BOOKING';
    END IF;
  END IF;

  v_status := CASE WHEN v_requires_approval THEN 'pending' ELSE 'confirmed' END;

  IF v_status = 'confirmed' AND v_existing_status IS DISTINCT FROM 'confirmed' THEN
    SELECT COUNT(DISTINCT b.user_id)
    INTO v_confirmed_count
    FROM public.fitness_group_bookings b
    WHERE b.session_id = p_session_id
      AND b.status = 'confirmed';

    IF v_confirmed_count >= v_capacity THEN
      RAISE EXCEPTION 'SESSION_FULL';
    END IF;
  END IF;

  INSERT INTO public.fitness_group_bookings (session_id, user_id, status)
  VALUES (p_session_id, p_user_id, v_status)
  ON CONFLICT (session_id, user_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    cancelled_at = NULL,
    cancel_reason = NULL,
    cancelled_by = NULL
  RETURNING id INTO v_booking_id;

  INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
  VALUES (
    v_group_id,
    p_user_id,
    CASE WHEN v_is_owner THEN 'admin' ELSE 'member' END,
    true,
    now()
  )
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET
    role = CASE
      WHEN v_is_owner THEN 'admin'
      ELSE public.fitness_group_members.role
    END,
    is_active = true,
    joined_at = COALESCE(public.fitness_group_members.joined_at, now());

  RETURN v_booking_id;
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
  v_capacity INT;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_can_manage BOOLEAN;
  v_overlaps BOOLEAN;
  v_status TEXT;
  v_confirmed_count INT;
BEGIN
  SELECT
    b.user_id,
    b.session_id,
    b.status,
    s.group_id,
    s.capacity,
    s.starts_at,
    s.ends_at
  INTO
    v_user_id,
    v_session_id,
    v_status,
    v_group_id,
    v_capacity,
    v_starts,
    v_ends
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

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;

  SELECT COUNT(DISTINCT b.user_id)
  INTO v_confirmed_count
  FROM public.fitness_group_bookings b
  WHERE b.session_id = v_session_id
    AND b.status = 'confirmed';

  IF v_confirmed_count >= v_capacity THEN
    RAISE EXCEPTION 'SESSION_FULL';
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

  INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
  VALUES (v_group_id, v_user_id, 'member', true, now())
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET is_active = true;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_fitness_session_capacity_update()
RETURNS TRIGGER AS $$
DECLARE
  v_confirmed_count INT;
BEGIN
  IF NEW.capacity IS DISTINCT FROM OLD.capacity THEN
    SELECT COUNT(DISTINCT b.user_id)
    INTO v_confirmed_count
    FROM public.fitness_group_bookings b
    WHERE b.session_id = OLD.id
      AND b.status = 'confirmed';

    IF NEW.capacity < v_confirmed_count THEN
      RAISE EXCEPTION 'SESSION_CAPACITY_BELOW_CONFIRMED';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_guard_fitness_session_capacity_update
  ON public.fitness_group_sessions;
CREATE TRIGGER trg_guard_fitness_session_capacity_update
BEFORE UPDATE OF capacity ON public.fitness_group_sessions
FOR EACH ROW EXECUTE FUNCTION public.guard_fitness_session_capacity_update();

CREATE SCHEMA IF NOT EXISTS app;

CREATE OR REPLACE FUNCTION app.require_current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id_text TEXT;
  v_user_id UUID;
BEGIN
  v_user_id_text := current_setting('app.user_id', true);
  IF v_user_id_text IS NULL OR btrim(v_user_id_text) = '' THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  v_user_id := v_user_id_text::UUID;
  IF NOT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = v_user_id
      AND u.is_active = true
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN v_user_id;
EXCEPTION
  WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
END;
$$;

CREATE OR REPLACE FUNCTION public.is_fitness_group_manager(
  p_group_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.is_fitness_group_manager(
    p_group_id,
    app.require_current_user_id()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_fitness_group_owner_auto_join(
  p_group_id UUID,
  p_enabled BOOLEAN,
  p_cancel_bookings BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.set_fitness_group_owner_auto_join(
    p_group_id,
    app.require_current_user_id(),
    p_enabled,
    p_cancel_bookings
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.book_fitness_session(
  p_session_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.book_fitness_session(
    p_session_id,
    app.require_current_user_id()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_fitness_session_booking(
  p_booking_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.approve_fitness_session_booking(
    p_booking_id,
    app.require_current_user_id()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_fitness_group(
  p_group_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.leave_fitness_group(
    p_group_id,
    p_user_id,
    app.require_current_user_id()
  );
END;
$$;

REVOKE ALL ON FUNCTION app.require_current_user_id() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_fitness_group_manager(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_fitness_group_owner_auto_join(UUID, BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.book_fitness_session(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_fitness_session_booking(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leave_fitness_group(UUID, UUID) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.set_fitness_group_owner_auto_join(UUID, UUID, BOOLEAN, BOOLEAN)
TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.book_fitness_session(UUID, UUID)
TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_fitness_session_booking(UUID, UUID)
TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
