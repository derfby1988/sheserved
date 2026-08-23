-- Fitness Buddies: owner participation toggle and capacity 1-30
-- Date: 2026-08-23
-- Phase 9: allow owner to control whether they are an active member of the group,
-- and allow capacity as low as 1 (which can be the owner alone, or one other member).

-- 1. Add the owner participation flag (default: owner auto-joins)
ALTER TABLE public.fitness_groups
  ADD COLUMN IF NOT EXISTS owner_auto_join BOOLEAN NOT NULL DEFAULT true;

-- 2. Replace the capacity CHECK constraint with the new 1-30 range.
-- The original constraint may be unnamed, so drop the existing constraint on the
-- `capacity` column first, then add a named one.
DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  SELECT con.conname INTO v_constraint_name
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
  WHERE nsp.nspname = 'public'
    AND rel.relname = 'fitness_groups'
    AND con.contype = 'c'
    AND a.attname = 'capacity';

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.fitness_groups DROP CONSTRAINT %I', v_constraint_name);
  END IF;
END $$;

ALTER TABLE public.fitness_groups
  ADD CONSTRAINT fitness_groups_capacity_range CHECK (capacity BETWEEN 1 AND 30);

-- 3. Existing groups keep the default behaviour (owner auto-joins).
UPDATE public.fitness_groups
  SET owner_auto_join = true
  WHERE owner_auto_join IS NULL;

-- 4. Update the side-effects function so owner membership follows `owner_auto_join`
--    on both INSERT and UPDATE.
CREATE OR REPLACE FUNCTION public.create_fitness_group_side_effects()
RETURNS TRIGGER AS $$
DECLARE
  v_room_id TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Create a chat room for this fitness group (id is TEXT; prefix with 'group_')
    v_room_id := 'group_' || NEW.id::text;

    INSERT INTO public.chat_rooms (id, participant_ids, last_message, room_type, room_ref_id)
      VALUES (v_room_id, ARRAY[]::UUID[], NULL, 'fitness_group', NEW.id)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  -- Ensure creator becomes an admin member when owner_auto_join is true,
  -- and is marked inactive when owner_auto_join is false.
  IF NEW.created_by IS NOT NULL THEN
    INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
      VALUES (NEW.id, NEW.created_by, 'admin', COALESCE(NEW.owner_auto_join, true), now())
    ON CONFLICT (group_id, user_id)
      DO UPDATE SET role = 'admin', is_active = EXCLUDED.is_active, joined_at = now();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_fitness_group_side_effects ON public.fitness_groups;
CREATE TRIGGER trg_create_fitness_group_side_effects
AFTER INSERT OR UPDATE ON public.fitness_groups
FOR EACH ROW EXECUTE FUNCTION public.create_fitness_group_side_effects();

-- 5. Update booking capacity guard to be group-level, honouring owner_auto_join.
CREATE OR REPLACE FUNCTION public.book_fitness_session(p_session_id UUID, p_user_id UUID)
RETURNS UUID AS $$
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
  v_current_members INT;
  v_already_booked BOOLEAN;
BEGIN
  SELECT s.group_id, g.capacity, g.owner_auto_join, g.created_by, s.starts_at, s.ends_at, g.requires_owner_approval
  INTO v_group_id, v_capacity, v_owner_auto_join, v_owner_id, v_starts, v_ends, v_requires_approval
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

  -- Current effective group participants: owner (when auto-joining) + distinct non-owner
  -- users with any pending/confirmed booking in this group.
  SELECT
    COALESCE(
      (CASE WHEN v_owner_auto_join THEN 1 ELSE 0 END)
      + COUNT(DISTINCT CASE WHEN b.user_id <> v_owner_id THEN b.user_id END),
      0
    )::INT
  INTO v_current_members
  FROM public.fitness_group_sessions s
  LEFT JOIN public.fitness_group_bookings b
    ON b.session_id = s.id
    AND b.status IN ('pending', 'confirmed')
  WHERE s.group_id = v_group_id;

  -- If the requesting user is already a pending/confirmed participant, they do not
  -- consume an additional slot (re-booking / reactivating the same session).
  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE s.group_id = v_group_id
      AND b.user_id = p_user_id
      AND b.status IN ('pending', 'confirmed')
  ) INTO v_already_booked;

  IF NOT v_already_booked THEN
    v_current_members := v_current_members + 1;
  END IF;

  IF v_current_members > v_capacity THEN
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

-- 6. Approval must also respect owner participation: the group owner can approve
--    even when their own membership is inactive, in addition to active admins.
CREATE OR REPLACE FUNCTION public.approve_fitness_session_booking(p_booking_id UUID, p_owner_id UUID)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_session_id UUID;
  v_group_id UUID;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_can_approve BOOLEAN;
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

  SELECT (
    g.created_by = p_owner_id
    OR EXISTS (
      SELECT 1
      FROM public.fitness_group_members m
      WHERE m.group_id = v_group_id
        AND m.user_id = p_owner_id
        AND m.role = 'admin'
        AND m.is_active = true
    )
  ) INTO v_can_approve
  FROM public.fitness_groups g
  WHERE g.id = v_group_id;

  IF NOT COALESCE(v_can_approve, false) THEN
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
