-- Fitness Buddies Feature Schema and Realtime
-- Date: 2026-08-03

-- ===============
-- Helper: ensure extensions
-- ===============
DO $$ BEGIN
  PERFORM 1 FROM pg_extension WHERE extname = 'pgcrypto';
  IF NOT FOUND THEN
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
  END IF;
EXCEPTION WHEN insufficient_privilege THEN
  NULL;
END $$;

-- ===============
-- sports table (with proposal workflow fields)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_th TEXT NOT NULL,
  name_en TEXT,
  icon TEXT,
  status VARCHAR(10) DEFAULT 'approved' CHECK (status IN ('pending','approved','rejected')),
  proposed_by UUID REFERENCES public.users(id),
  proposed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES public.users(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason VARCHAR(200)
);

-- ===============
-- fitness_groups and related tables
-- ===============
CREATE TABLE IF NOT EXISTS public.fitness_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sport_id UUID REFERENCES public.sports(id),
  name VARCHAR(60) NOT NULL,
  description VARCHAR(500),
  province TEXT,
  district TEXT,
  lat DOUBLE PRECISION CHECK (lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION CHECK (lng BETWEEN -180 AND 180),
  visibility VARCHAR(10) DEFAULT 'public' CHECK (visibility IN ('public','private')),
  requires_owner_approval BOOLEAN DEFAULT false,
  cover_image_url VARCHAR(500),
  capacity INTEGER NOT NULL DEFAULT 5 CHECK (capacity BETWEEN 2 AND 30),
  created_by UUID REFERENCES public.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.fitness_group_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.fitness_groups(id) ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  place_name VARCHAR(200),
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  note VARCHAR(500),
  CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS public.fitness_group_members (
  group_id UUID NOT NULL REFERENCES public.fitness_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id),
  role VARCHAR(10) NOT NULL DEFAULT 'member' CHECK (role IN ('member','admin')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  joined_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.fitness_group_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.fitness_group_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id),
  status VARCHAR(10) NOT NULL CHECK (status IN ('pending','confirmed','cancelled','rejected')),
  created_at TIMESTAMPTZ DEFAULT now(),
  cancelled_at TIMESTAMPTZ,
  cancelled_by VARCHAR(10) CHECK (cancelled_by IN ('user','owner','system')),
  cancel_reason VARCHAR(200),
  UNIQUE (session_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.fitness_group_blocklist (
  group_id UUID NOT NULL REFERENCES public.fitness_groups(id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES public.users(id),
  blocked_by UUID NOT NULL REFERENCES public.users(id),
  reason VARCHAR(200),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (group_id, blocked_user_id)
);

-- ===============
-- chat_rooms integration (room_type, room_ref_id)
-- ===============
DO $$ BEGIN
  PERFORM 1 FROM information_schema.columns 
    WHERE table_schema='public' AND table_name='chat_rooms' AND column_name='room_type';
  IF NOT FOUND THEN
    ALTER TABLE public.chat_rooms
      ADD COLUMN room_type VARCHAR(20) DEFAULT 'direct' CHECK (room_type IN ('direct','fitness_group')),
      ADD COLUMN room_ref_id UUID;
    CREATE INDEX IF NOT EXISTS idx_chat_rooms_ref ON public.chat_rooms(room_type, room_ref_id);
  END IF;
END $$;

-- ===============
-- triggers: create chat room on new group, ensure creator becomes admin member
-- ===============
CREATE OR REPLACE FUNCTION public.create_fitness_group_side_effects()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.chat_rooms (id, participant_ids, last_message, room_type, room_ref_id)
    VALUES (gen_random_uuid(), ARRAY[]::UUID[], NULL, 'fitness_group', NEW.id)
  ON CONFLICT DO NOTHING;

  IF NEW.created_by IS NOT NULL THEN
    INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
      VALUES (NEW.id, NEW.created_by, 'admin', true, now())
    ON CONFLICT (group_id, user_id) DO UPDATE SET role='admin', is_active=true;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_fitness_group_side_effects ON public.fitness_groups;
CREATE TRIGGER trg_create_fitness_group_side_effects
AFTER INSERT ON public.fitness_groups
FOR EACH ROW EXECUTE FUNCTION public.create_fitness_group_side_effects();

-- ===============
-- trigger: sync chat_rooms.participant_ids when members change
-- ===============
CREATE OR REPLACE FUNCTION public.sync_fitness_chat_participants()
RETURNS TRIGGER AS $$
DECLARE
  v_group_id UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_group_id := OLD.group_id;
  ELSE
    v_group_id := NEW.group_id;
  END IF;

  UPDATE public.chat_rooms cr
  SET participant_ids = (
    SELECT COALESCE(array_agg(m.user_id), ARRAY[]::UUID[])
    FROM public.fitness_group_members m
    WHERE m.group_id = v_group_id AND m.is_active = true
  )
  WHERE cr.room_type = 'fitness_group' AND cr.room_ref_id = v_group_id;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_members_ins ON public.fitness_group_members;
CREATE TRIGGER trg_sync_members_ins
AFTER INSERT ON public.fitness_group_members
FOR EACH ROW EXECUTE FUNCTION public.sync_fitness_chat_participants();

DROP TRIGGER IF EXISTS trg_sync_members_upd ON public.fitness_group_members;
CREATE TRIGGER trg_sync_members_upd
AFTER UPDATE ON public.fitness_group_members
FOR EACH ROW EXECUTE FUNCTION public.sync_fitness_chat_participants();

DROP TRIGGER IF EXISTS trg_sync_members_del ON public.fitness_group_members;
CREATE TRIGGER trg_sync_members_del
AFTER DELETE ON public.fitness_group_members
FOR EACH ROW EXECUTE FUNCTION public.sync_fitness_chat_participants();

-- ===============
-- RPC: check booking overlap
-- ===============
CREATE OR REPLACE FUNCTION public.check_booking_overlap(p_user_id UUID, p_starts_at TIMESTAMPTZ, p_ends_at TIMESTAMPTZ)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON s.id = b.session_id
    WHERE b.user_id = p_user_id
      AND b.status IN ('pending','confirmed')
      AND (s.starts_at, s.ends_at) OVERLAPS (p_starts_at, p_ends_at)
  );
END;
$$ LANGUAGE plpgsql STABLE;

-- ===============
-- RPC: book fitness session with capacity and overlap guards
-- ===============
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

  SELECT public.check_booking_overlap(p_user_id, v_starts, v_ends) INTO v_overlaps;
  IF v_overlaps THEN
    RAISE EXCEPTION 'OVERLAP_BOOKING';
  END IF;

  IF (
    SELECT COUNT(1)
    FROM public.fitness_group_bookings b
    WHERE b.session_id = p_session_id AND b.status IN ('pending','confirmed')
  ) >= v_capacity THEN
    RAISE EXCEPTION 'GROUP_FULL';
  END IF;

  v_status := CASE WHEN COALESCE(v_requires_approval, true) THEN 'pending' ELSE 'confirmed' END;

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

-- ===============
-- Indexes
-- ===============
CREATE INDEX IF NOT EXISTS idx_fitness_sessions_group_starts ON public.fitness_group_sessions(group_id, starts_at);
CREATE INDEX IF NOT EXISTS idx_fitness_bookings_user_status ON public.fitness_group_bookings(user_id, status);
CREATE INDEX IF NOT EXISTS idx_fitness_bookings_session_active ON public.fitness_group_bookings(session_id) WHERE status IN ('pending','confirmed');
CREATE INDEX IF NOT EXISTS idx_fitness_groups_sport_province ON public.fitness_groups(sport_id, province, district);
CREATE INDEX IF NOT EXISTS idx_fitness_members_group_active ON public.fitness_group_members(group_id) WHERE is_active = true;

-- ===============
-- RLS: Phase 1 (USING true) — App layer enforces writes
-- ===============
ALTER TABLE public.sports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fitness_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fitness_group_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fitness_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fitness_group_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fitness_group_blocklist ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sports' AND policyname='sports_select_all') THEN
    CREATE POLICY sports_select_all ON public.sports FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fitness_groups' AND policyname='fitness_groups_select_all') THEN
    CREATE POLICY fitness_groups_select_all ON public.fitness_groups FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fitness_group_sessions' AND policyname='fitness_group_sessions_select_all') THEN
    CREATE POLICY fitness_group_sessions_select_all ON public.fitness_group_sessions FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fitness_group_members' AND policyname='fitness_group_members_select_all') THEN
    CREATE POLICY fitness_group_members_select_all ON public.fitness_group_members FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fitness_group_bookings' AND policyname='fitness_group_bookings_select_all') THEN
    CREATE POLICY fitness_group_bookings_select_all ON public.fitness_group_bookings FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fitness_group_blocklist' AND policyname='fitness_group_blocklist_select_all') THEN
    CREATE POLICY fitness_group_blocklist_select_all ON public.fitness_group_blocklist FOR SELECT USING (true);
  END IF;
END $$;
