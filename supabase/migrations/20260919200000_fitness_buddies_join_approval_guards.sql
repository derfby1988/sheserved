-- ===================================================================
-- Phase 19: Join & Approval Flow Integrity (P1 - Critical Guards)
-- 1. Grace Period on session starts_at in book_fitness_session
-- 2. Prevent re-applying for previously rejected bookings in same session
-- 3. Manager Approval Bypass (Co-Admins & Sheserved Admins bypass pending in private groups)
-- 4. Prevent approving past sessions (ends_at <= now() check in approve_fitness_session_booking)
-- 5. Re-check blocklist upon booking approval
-- ===================================================================

-- 1. Canonical book_fitness_session RPC with P1 guards
CREATE OR REPLACE FUNCTION public.book_fitness_session(
  p_session_id UUID,
  p_user_id UUID,
  p_position_id UUID DEFAULT NULL,
  p_declared_skill_level VARCHAR DEFAULT NULL
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
  v_is_manager BOOLEAN;
  v_has_positions BOOLEAN;
  v_pos_group_id UUID;
  v_pos_active BOOLEAN;
  v_pos_slots INT;
  v_pos_taken INT;
BEGIN
  -- Lock group & session rows
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

  IF v_ends <= now() THEN
    RAISE EXCEPTION 'SESSION_ENDED';
  END IF;

  -- P1.1: Grace period 15 minutes after session starts_at
  IF v_starts + INTERVAL '15 minutes' <= now() THEN
    RAISE EXCEPTION 'SESSION_ALREADY_STARTED';
  END IF;

  -- User blocked check
  IF EXISTS (
    SELECT 1 FROM public.fitness_group_blocklist bl
    WHERE bl.group_id = v_group_id
      AND bl.blocked_user_id = p_user_id
      AND bl.is_active = true
  ) THEN
    RAISE EXCEPTION 'USER_BLOCKED';
  END IF;

  -- P1.3: Manager check - group creator, active group admin, or Sheserved admin
  v_is_manager := public.is_fitness_group_manager(v_group_id, p_user_id);
  v_requires_approval := v_requires_approval AND NOT v_is_manager;

  -- Check existing booking
  SELECT b.status, b.position_id INTO v_existing_status, v_existing_pos_id
  FROM public.fitness_group_bookings b
  WHERE b.session_id = p_session_id AND b.user_id = p_user_id
  FOR UPDATE;

  IF v_existing_status = 'confirmed' THEN
    RAISE EXCEPTION 'ALREADY_JOINED';
  ELSIF v_existing_status = 'pending' THEN
    RAISE EXCEPTION 'ALREADY_REQUESTED';
  -- P1.2: Prevent re-applying if previously rejected in this session
  ELSIF v_existing_status = 'rejected' THEN
    RAISE EXCEPTION 'BOOKING_PREVIOUSLY_REJECTED';
  END IF;

  -- Overlap check (skip for manager and pending paths)
  IF NOT v_is_manager AND NOT v_requires_approval THEN
    SELECT public.check_booking_overlap(p_user_id, v_starts, v_ends)
    INTO v_overlaps;
    IF v_overlaps AND v_existing_status IS DISTINCT FROM 'confirmed' THEN
      RAISE EXCEPTION 'OVERLAP_BOOKING';
    END IF;
  END IF;

  -- Position validation
  SELECT EXISTS (
    SELECT 1 FROM public.fitness_group_positions p
    WHERE p.group_id = v_group_id AND p.is_active = true
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
    p_position_id := NULL; -- ignore position for groups without layout
  END IF;

  -- Determine status and check capacity
  IF v_requires_approval THEN
    v_status := 'pending';
  ELSE
    SELECT COUNT(DISTINCT b.user_id)
    INTO v_confirmed_count
    FROM public.fitness_group_bookings b
    WHERE b.session_id = p_session_id AND b.status = 'confirmed';

    IF v_existing_status IS DISTINCT FROM 'confirmed' AND v_confirmed_count >= v_capacity THEN
      RAISE EXCEPTION 'SESSION_FULL';
    END IF;

    IF v_has_positions AND p_position_id IS NOT NULL AND
       (v_existing_status IS DISTINCT FROM 'confirmed' OR v_existing_pos_id IS DISTINCT FROM p_position_id) THEN
      SELECT COUNT(*) INTO v_pos_taken
      FROM public.fitness_group_bookings b
      WHERE b.session_id = p_session_id
        AND b.position_id = p_position_id
        AND b.status = 'confirmed'
        AND b.user_id <> p_user_id;

      IF v_pos_taken >= v_pos_slots THEN
        RAISE EXCEPTION 'POSITION_FULL';
      END IF;
    END IF;

    v_status := 'confirmed';
  END IF;

  INSERT INTO public.fitness_group_bookings (
    session_id, user_id, status, position_id, declared_skill_level
  ) VALUES (
    p_session_id, p_user_id, v_status, p_position_id, p_declared_skill_level
  )
  ON CONFLICT (session_id, user_id) DO UPDATE SET
    status              = EXCLUDED.status,
    position_id         = EXCLUDED.position_id,
    declared_skill_level = EXCLUDED.declared_skill_level,
    cancelled_at        = NULL,
    cancel_reason       = NULL,
    cancelled_by        = NULL
  RETURNING id INTO v_booking_id;

  -- Upsert membership on confirmed / pending booking
  INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
  VALUES (
    v_group_id,
    p_user_id,
    CASE WHEN v_is_manager THEN 'admin' ELSE 'member' END,
    true,
    now()
  )
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET
    role = CASE
      WHEN v_is_manager THEN 'admin'
      ELSE public.fitness_group_members.role
    END,
    is_active = true,
    joined_at = COALESCE(public.fitness_group_members.joined_at, now());

  RETURN v_booking_id;
END;
$$;


-- 2. Canonical approve_fitness_session_booking RPC with P1 guards
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

  -- P1.4: Prevent approving past sessions
  IF v_ends <= now() THEN
    RAISE EXCEPTION 'SESSION_ENDED';
  END IF;

  -- P1.5: Re-check blocklist on approval
  IF EXISTS (
    SELECT 1 FROM public.fitness_group_blocklist bl
    WHERE bl.group_id = v_group_id
      AND bl.blocked_user_id = v_user_id
      AND bl.is_active = true
  ) THEN
    RAISE EXCEPTION 'USER_BLOCKED';
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


-- 3. Grants and Schema Reload
GRANT EXECUTE ON FUNCTION public.book_fitness_session(UUID, UUID, UUID, VARCHAR)
  TO anon, authenticated, sheserved_app;

GRANT EXECUTE ON FUNCTION public.approve_fitness_session_booking(UUID, UUID)
  TO anon, authenticated, sheserved_app;

NOTIFY pgrst, 'reload schema';
