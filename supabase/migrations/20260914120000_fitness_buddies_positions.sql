-- Migration: Phase 15 — Simulated Field Lineup and Player Positions
-- Date: 2026-09-14
-- Depends: 20260825130000_fitness_buddies_session_capacity.sql,
--          20260903110900_phase_13_0_fitness_public_views.sql,
--          20260905140000_phase_13_1_db_identity_roles.sql,
--          20260914100000_fitness_buddies_costs.sql

-- ===================================================================
-- 1. sports.field_layout
-- ===================================================================
ALTER TABLE public.sports
  ADD COLUMN IF NOT EXISTS field_layout VARCHAR(10) NULL
  CHECK (field_layout IN ('none', 'single', 'double'));

COMMENT ON COLUMN public.sports.field_layout IS
  'Field layout: NULL = legacy/unconfirmed (positions disabled), none = no positions, single = one side, double = two sides.';

-- ===================================================================
-- 2. fitness_group_positions
-- ===================================================================
CREATE TABLE IF NOT EXISTS public.fitness_group_positions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    UUID NOT NULL REFERENCES public.fitness_groups(id) ON DELETE CASCADE,
  side        SMALLINT NOT NULL DEFAULT 0 CHECK (side IN (0, 1)),
  x           DOUBLE PRECISION NOT NULL CHECK (x BETWEEN 0 AND 1),
  y           DOUBLE PRECISION NOT NULL CHECK (y BETWEEN 0 AND 1),
  icon        VARCHAR(32) NOT NULL DEFAULT 'player',
  color       CHAR(7) NOT NULL DEFAULT '#2196F3' CHECK (color ~* '^#[0-9a-f]{6}$'),
  label       VARCHAR(60) NOT NULL,
  slots       INTEGER NOT NULL DEFAULT 1 CHECK (slots BETWEEN 1 AND 50),
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fgp_group
  ON public.fitness_group_positions(group_id)
  WHERE is_active;

-- ===================================================================
-- 3. fitness_group_sessions.owner_position_id & fitness_group_bookings.position_id
-- ===================================================================
ALTER TABLE public.fitness_group_sessions
  ADD COLUMN IF NOT EXISTS owner_position_id UUID
  REFERENCES public.fitness_group_positions(id) ON DELETE RESTRICT;

ALTER TABLE public.fitness_group_bookings
  ADD COLUMN IF NOT EXISTS position_id UUID
  REFERENCES public.fitness_group_positions(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_fgb_position
  ON public.fitness_group_bookings(position_id)
  WHERE status = 'confirmed';

-- ===================================================================
-- 4. Public views
-- ===================================================================
CREATE OR REPLACE VIEW public.fitness_group_positions_public AS
SELECT
  p.id,
  p.group_id,
  p.side,
  p.x,
  p.y,
  p.icon,
  p.color,
  p.label,
  p.slots,
  p.is_active
FROM public.fitness_group_positions p
JOIN public.fitness_groups g ON g.id = p.group_id
WHERE p.is_active = true
  AND g.visibility = 'public';

CREATE OR REPLACE VIEW public.fitness_session_position_taken_public AS
SELECT
  b.session_id,
  b.position_id,
  COUNT(*)::int AS taken_count
FROM public.fitness_group_bookings b
JOIN public.fitness_group_sessions s ON s.id = b.session_id
JOIN public.fitness_groups g ON g.id = s.group_id
WHERE b.status = 'confirmed'
  AND b.position_id IS NOT NULL
  AND g.visibility = 'public'
GROUP BY b.session_id, b.position_id;

-- ===================================================================
-- 5. Trigger: sync_fitness_session_owner_booking update
-- ===================================================================
CREATE OR REPLACE FUNCTION public.sync_fitness_session_owner_booking()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_id UUID;
  v_owner_auto_join BOOLEAN;
  v_has_positions BOOLEAN;
  v_pos_group_id UUID;
  v_pos_active BOOLEAN;
  v_pos_slots INT;
  v_pos_taken INT;
BEGIN
  SELECT g.created_by, COALESCE(g.owner_auto_join, true)
  INTO v_owner_id, v_owner_auto_join
  FROM public.fitness_groups g
  WHERE g.id = NEW.group_id;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_positions p
    WHERE p.group_id = NEW.group_id
      AND p.is_active = true
  ) INTO v_has_positions;

  IF v_owner_id IS NOT NULL AND v_owner_auto_join THEN
    IF v_has_positions THEN
      IF NEW.owner_position_id IS NULL THEN
        RAISE EXCEPTION 'POSITION_REQUIRED';
      END IF;

      SELECT p.group_id, p.is_active, p.slots
      INTO v_pos_group_id, v_pos_active, v_pos_slots
      FROM public.fitness_group_positions p
      WHERE p.id = NEW.owner_position_id;

      IF v_pos_group_id IS NULL OR v_pos_group_id <> NEW.group_id OR NOT COALESCE(v_pos_active, false) THEN
        RAISE EXCEPTION 'POSITION_INVALID';
      END IF;

      SELECT COUNT(*)
      INTO v_pos_taken
      FROM public.fitness_group_bookings b
      WHERE b.session_id = NEW.id
        AND b.position_id = NEW.owner_position_id
        AND b.status = 'confirmed';

      IF v_pos_taken >= v_pos_slots THEN
        RAISE EXCEPTION 'POSITION_FULL';
      END IF;
    END IF;

    INSERT INTO public.fitness_group_bookings (session_id, user_id, status, position_id)
    VALUES (NEW.id, v_owner_id, 'confirmed', NEW.owner_position_id)
    ON CONFLICT (session_id, user_id)
    DO UPDATE SET
      status = 'confirmed',
      position_id = EXCLUDED.position_id,
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

-- ===================================================================
-- 6. RPC: book_fitness_session with position support
-- ===================================================================
CREATE OR REPLACE FUNCTION public.book_fitness_session(
  p_session_id UUID,
  p_user_id UUID,
  p_position_id UUID DEFAULT NULL
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
  v_existing_pos_id UUID;
  v_confirmed_count INT;
  v_is_owner BOOLEAN;
  v_has_positions BOOLEAN;
  v_pos_group_id UUID;
  v_pos_active BOOLEAN;
  v_pos_slots INT;
  v_pos_taken INT;
BEGIN
  -- Lock group & session
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

  SELECT b.status, b.position_id
  INTO v_existing_status, v_existing_pos_id
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

  -- Position checks
  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_positions p
    WHERE p.group_id = v_group_id
      AND p.is_active = true
  ) INTO v_has_positions;

  IF v_has_positions THEN
    IF p_position_id IS NULL THEN
      RAISE EXCEPTION 'POSITION_REQUIRED';
    END IF;

    SELECT p.group_id, p.is_active, p.slots
    INTO v_pos_group_id, v_pos_active, v_pos_slots
    FROM public.fitness_group_positions p
    WHERE p.id = p_position_id;

    IF v_pos_group_id IS NULL OR v_pos_group_id <> v_group_id OR NOT COALESCE(v_pos_active, false) THEN
      RAISE EXCEPTION 'POSITION_INVALID';
    END IF;
  ELSIF p_position_id IS NOT NULL THEN
    -- Group has no active positions, ignore or validate
    p_position_id := NULL;
  END IF;

  v_status := CASE WHEN v_requires_approval THEN 'pending' ELSE 'confirmed' END;

  IF v_status = 'confirmed' THEN
    IF v_existing_status IS DISTINCT FROM 'confirmed' THEN
      SELECT COUNT(DISTINCT b.user_id)
      INTO v_confirmed_count
      FROM public.fitness_group_bookings b
      WHERE b.session_id = p_session_id
        AND b.status = 'confirmed';

      IF v_confirmed_count >= v_capacity THEN
        RAISE EXCEPTION 'SESSION_FULL';
      END IF;
    END IF;

    IF v_has_positions AND (v_existing_status IS DISTINCT FROM 'confirmed' OR v_existing_pos_id IS DISTINCT FROM p_position_id) THEN
      SELECT COUNT(*)
      INTO v_pos_taken
      FROM public.fitness_group_bookings b
      WHERE b.session_id = p_session_id
        AND b.position_id = p_position_id
        AND b.status = 'confirmed'
        AND b.user_id <> p_user_id;

      IF v_pos_taken >= v_pos_slots THEN
        RAISE EXCEPTION 'POSITION_FULL';
      END IF;
    END IF;
  END IF;

  INSERT INTO public.fitness_group_bookings (session_id, user_id, status, position_id)
  VALUES (p_session_id, p_user_id, v_status, p_position_id)
  ON CONFLICT (session_id, user_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    position_id = EXCLUDED.position_id,
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

-- 1-arg overload for PostgREST JWT
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
    app.require_current_user_id(),
    NULL
  );
END;
$$;

-- ===================================================================
-- 7. RPC: approve_fitness_session_booking with position slot validation
-- ===================================================================
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
  v_pos_id UUID;
  v_confirmed_count INT;
  v_pos_slots INT;
  v_pos_taken INT;
  v_pos_active BOOLEAN;
  v_group_name TEXT;
BEGIN
  SELECT
    b.user_id,
    b.session_id,
    b.status,
    b.position_id,
    s.group_id,
    s.capacity,
    s.starts_at,
    s.ends_at,
    g.name
  INTO
    v_user_id,
    v_session_id,
    v_status,
    v_pos_id,
    v_group_id,
    v_capacity,
    v_starts,
    v_ends,
    v_group_name
  FROM public.fitness_group_bookings b
  JOIN public.fitness_group_sessions s ON s.id = b.session_id
  JOIN public.fitness_groups g ON g.id = s.group_id
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

  -- Capacity check
  SELECT COUNT(DISTINCT b.user_id)
  INTO v_confirmed_count
  FROM public.fitness_group_bookings b
  WHERE b.session_id = v_session_id
    AND b.status = 'confirmed';

  IF v_confirmed_count >= v_capacity THEN
    RAISE EXCEPTION 'SESSION_FULL';
  END IF;

  -- Position slot check
  IF v_pos_id IS NOT NULL THEN
    SELECT p.slots, p.is_active
    INTO v_pos_slots, v_pos_active
    FROM public.fitness_group_positions p
    WHERE p.id = v_pos_id;

    IF v_pos_slots IS NULL OR NOT COALESCE(v_pos_active, false) THEN
      RAISE EXCEPTION 'POSITION_INVALID';
    END IF;

    SELECT COUNT(*)
    INTO v_pos_taken
    FROM public.fitness_group_bookings b
    WHERE b.session_id = v_session_id
      AND b.position_id = v_pos_id
      AND b.status = 'confirmed';

    IF v_pos_taken >= v_pos_slots THEN
      -- Notify applicant that selected position is full, keep booking pending
      PERFORM pg_notify(
        'fitness_booking_status_updates',
        jsonb_build_object(
          'bookingId', p_booking_id,
          'booking_id', p_booking_id,
          'sessionId', v_session_id,
          'session_id', v_session_id,
          'groupId', v_group_id,
          'group_id', v_group_id,
          'groupName', v_group_name,
          'group_name', v_group_name,
          'userId', v_user_id,
          'user_id', v_user_id,
          'status', 'position_full',
          'message', 'ตำแหน่งที่คุณเลือกเต็มแล้ว กรุณาเลือกตำแหน่งใหม่'
        )::text
      );
      RAISE EXCEPTION 'POSITION_FULL';
    END IF;
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

-- 1-arg overload for PostgREST JWT
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

-- ===================================================================
-- 8. RPC: set_booking_position
-- ===================================================================
CREATE OR REPLACE FUNCTION public.set_booking_position(
  p_booking_id UUID,
  p_user_id UUID,
  p_position_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_booking_user_id UUID;
  v_session_id UUID;
  v_group_id UUID;
  v_status TEXT;
  v_ends_at TIMESTAMPTZ;
  v_has_positions BOOLEAN;
  v_pos_group_id UUID;
  v_pos_active BOOLEAN;
  v_pos_slots INT;
  v_pos_taken INT;
BEGIN
  SELECT
    b.user_id,
    b.session_id,
    b.status,
    s.group_id,
    s.ends_at
  INTO
    v_booking_user_id,
    v_session_id,
    v_status,
    v_group_id,
    v_ends_at
  FROM public.fitness_group_bookings b
  JOIN public.fitness_group_sessions s ON s.id = b.session_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b, s;

  IF v_booking_user_id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  IF v_booking_user_id <> p_user_id THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF v_status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'INVALID_BOOKING_STATUS';
  END IF;

  IF v_ends_at <= now() THEN
    RAISE EXCEPTION 'SESSION_ENDED';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_positions p
    WHERE p.group_id = v_group_id
      AND p.is_active = true
  ) INTO v_has_positions;

  IF v_has_positions THEN
    IF p_position_id IS NULL THEN
      RAISE EXCEPTION 'POSITION_REQUIRED';
    END IF;

    SELECT p.group_id, p.is_active, p.slots
    INTO v_pos_group_id, v_pos_active, v_pos_slots
    FROM public.fitness_group_positions p
    WHERE p.id = p_position_id;

    IF v_pos_group_id IS NULL OR v_pos_group_id <> v_group_id OR NOT COALESCE(v_pos_active, false) THEN
      RAISE EXCEPTION 'POSITION_INVALID';
    END IF;

    IF v_status = 'confirmed' THEN
      SELECT COUNT(*)
      INTO v_pos_taken
      FROM public.fitness_group_bookings b
      WHERE b.session_id = v_session_id
        AND b.position_id = p_position_id
        AND b.status = 'confirmed'
        AND b.id <> p_booking_id;

      IF v_pos_taken >= v_pos_slots THEN
        RAISE EXCEPTION 'POSITION_FULL';
      END IF;
    END IF;
  ELSE
    p_position_id := NULL;
  END IF;

  UPDATE public.fitness_group_bookings
  SET position_id = p_position_id
  WHERE id = p_booking_id;
END;
$$;

-- 2-arg overload for PostgREST JWT
CREATE OR REPLACE FUNCTION public.set_booking_position(
  p_booking_id UUID,
  p_position_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.set_booking_position(
    p_booking_id,
    app.require_current_user_id(),
    p_position_id
  );
END;
$$;

-- ===================================================================
-- 9. RPC: replace_fitness_group_positions (Atomic replacement)
-- ===================================================================
CREATE OR REPLACE FUNCTION public.replace_fitness_group_positions(
  p_group_id UUID,
  p_actor_id UUID,
  p_positions JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_can_manage BOOLEAN;
  v_pos JSONB;
  v_id UUID;
  v_side SMALLINT;
  v_x DOUBLE PRECISION;
  v_y DOUBLE PRECISION;
  v_icon TEXT;
  v_color TEXT;
  v_label TEXT;
  v_slots INT;
  v_is_active BOOLEAN;
  v_processed_ids UUID[] := ARRAY[]::UUID[];
BEGIN
  SELECT public.is_fitness_group_manager(p_group_id, p_actor_id)
  INTO v_can_manage;

  IF NOT COALESCE(v_can_manage, false) THEN
    RAISE EXCEPTION 'NOT_GROUP_ADMIN';
  END IF;

  IF p_positions IS NOT NULL AND jsonb_typeof(p_positions) = 'array' THEN
    FOR v_pos IN SELECT * FROM jsonb_array_elements(p_positions)
    LOOP
      v_id := NULL;
      IF v_pos ? 'id' AND (v_pos->>'id') IS NOT NULL AND (v_pos->>'id') <> '' THEN
        v_id := (v_pos->>'id')::UUID;
      END IF;

      v_side := COALESCE((v_pos->>'side')::SMALLINT, 0);
      IF v_side NOT IN (0, 1) THEN v_side := 0; END IF;

      v_x := COALESCE((v_pos->>'x')::DOUBLE PRECISION, 0.5);
      IF v_x < 0.0 THEN v_x := 0.0; ELSIF v_x > 1.0 THEN v_x := 1.0; END IF;

      v_y := COALESCE((v_pos->>'y')::DOUBLE PRECISION, 0.5);
      IF v_y < 0.0 THEN v_y := 0.0; ELSIF v_y > 1.0 THEN v_y := 1.0; END IF;

      v_icon := COALESCE(v_pos->>'icon', 'player');
      v_color := COALESCE(v_pos->>'color', '#2196F3');
      IF v_color !~* '^#[0-9a-f]{6}$' THEN v_color := '#2196F3'; END IF;

      v_label := TRIM(COALESCE(v_pos->>'label', ''));
      IF v_label = '' THEN
        RAISE EXCEPTION 'LABEL_REQUIRED';
      END IF;
      IF LENGTH(v_label) > 60 THEN
        v_label := SUBSTRING(v_label FROM 1 FOR 60);
      END IF;

      v_slots := COALESCE((v_pos->>'slots')::INT, 1);
      IF v_slots < 1 THEN v_slots := 1; ELSIF v_slots > 50 THEN v_slots := 50; END IF;

      v_is_active := COALESCE((v_pos->>'is_active')::BOOLEAN, true);

      IF v_id IS NOT NULL THEN
        -- Check if belongs to this group
        IF EXISTS (SELECT 1 FROM public.fitness_group_positions WHERE id = v_id AND group_id = p_group_id) THEN
          UPDATE public.fitness_group_positions
          SET
            side = v_side,
            x = v_x,
            y = v_y,
            icon = v_icon,
            color = v_color,
            label = v_label,
            slots = v_slots,
            is_active = v_is_active,
            updated_at = now()
          WHERE id = v_id;
          v_processed_ids := array_append(v_processed_ids, v_id);
        END IF;
      ELSE
        INSERT INTO public.fitness_group_positions (
          group_id, side, x, y, icon, color, label, slots, is_active
        ) VALUES (
          p_group_id, v_side, v_x, v_y, v_icon, v_color, v_label, v_slots, v_is_active
        ) RETURNING id INTO v_id;
        v_processed_ids := array_append(v_processed_ids, v_id);
      END IF;
    END LOOP;
  END IF;

  -- Deactivate positions of this group not in processed_ids (or delete if never referenced)
  -- Deactivate ones that have bookings:
  UPDATE public.fitness_group_positions
  SET is_active = false, updated_at = now()
  WHERE group_id = p_group_id
    AND is_active = true
    AND (v_processed_ids IS NULL OR id <> ALL(v_processed_ids))
    AND EXISTS (
      SELECT 1 FROM public.fitness_group_bookings WHERE position_id = public.fitness_group_positions.id
    );

  -- Delete unreferenced ones:
  DELETE FROM public.fitness_group_positions
  WHERE group_id = p_group_id
    AND (v_processed_ids IS NULL OR id <> ALL(v_processed_ids))
    AND NOT EXISTS (
      SELECT 1 FROM public.fitness_group_bookings WHERE position_id = public.fitness_group_positions.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.fitness_group_sessions WHERE owner_position_id = public.fitness_group_positions.id
    );
END;
$$;

-- 2-arg overload for PostgREST JWT
CREATE OR REPLACE FUNCTION public.replace_fitness_group_positions(
  p_group_id UUID,
  p_positions JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.replace_fitness_group_positions(
    p_group_id,
    app.require_current_user_id(),
    p_positions
  );
END;
$$;

-- ===================================================================
-- 10. Permissions and Grants
-- ===================================================================
GRANT SELECT ON public.fitness_group_positions_public TO anon, authenticated;
GRANT SELECT ON public.fitness_session_position_taken_public TO anon, authenticated;

GRANT SELECT ON public.fitness_group_positions TO anon, authenticated;
GRANT ALL ON public.fitness_group_positions TO sheserved_app;

GRANT EXECUTE ON FUNCTION public.book_fitness_session(UUID, UUID, UUID) TO anon, authenticated, sheserved_app;
GRANT EXECUTE ON FUNCTION public.book_fitness_session(UUID) TO anon, authenticated, sheserved_app;

GRANT EXECUTE ON FUNCTION public.approve_fitness_session_booking(UUID, UUID) TO anon, authenticated, sheserved_app;
GRANT EXECUTE ON FUNCTION public.approve_fitness_session_booking(UUID) TO anon, authenticated, sheserved_app;

GRANT EXECUTE ON FUNCTION public.set_booking_position(UUID, UUID, UUID) TO anon, authenticated, sheserved_app;
GRANT EXECUTE ON FUNCTION public.set_booking_position(UUID, UUID) TO anon, authenticated, sheserved_app;

GRANT EXECUTE ON FUNCTION public.replace_fitness_group_positions(UUID, UUID, JSONB) TO anon, authenticated, sheserved_app;
GRANT EXECUTE ON FUNCTION public.replace_fitness_group_positions(UUID, JSONB) TO anon, authenticated, sheserved_app;

NOTIFY pgrst, 'reload schema';
