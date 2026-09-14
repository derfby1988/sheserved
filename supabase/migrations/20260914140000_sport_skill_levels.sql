-- ===================================================================
-- Phase 16: Sport Skill Levels System (ระบบระบุระดับทักษะผู้เล่นตามชนิดกีฬา)
-- ===================================================================

-- 1. Add skill_levels JSONB configuration to sports table
ALTER TABLE public.sports
  ADD COLUMN IF NOT EXISTS skill_levels JSONB NULL;

-- 2. Add target_skill_levels and skill_level_note to fitness_groups table
ALTER TABLE public.fitness_groups
  ADD COLUMN IF NOT EXISTS target_skill_levels TEXT[] NOT NULL DEFAULT '{all}',
  ADD COLUMN IF NOT EXISTS skill_level_note VARCHAR(150) NULL;

CREATE INDEX IF NOT EXISTS idx_fg_target_skill_levels
  ON public.fitness_groups USING GIN (target_skill_levels);

-- 3. Add target_skill_levels to fitness_group_sessions
ALTER TABLE public.fitness_group_sessions
  ADD COLUMN IF NOT EXISTS target_skill_levels TEXT[] NULL;

-- 4. Add declared_skill_level to fitness_group_bookings
ALTER TABLE public.fitness_group_bookings
  ADD COLUMN IF NOT EXISTS declared_skill_level VARCHAR(32) NULL;

-- 5. Seed sport-specific skill levels for well-known sports
-- 5.1 Badminton (แบดมินตัน: BG, P-, P, P+, C, B, A)
UPDATE public.sports
SET skill_levels = '{
  "type": "custom",
  "name": "มาตรฐานระดับมือแบดมินตัน",
  "levels": [
    {"key": "all", "label_th": "เปิดรับทุกระดับ", "label_en": "All Levels", "description": "ไม่จำกัดระดับฝีมือ เล่นได้ทุกระดับ"},
    {"key": "bg", "label_th": "BG (Beginner)", "label_en": "Beginner", "description": "มือใหม่ เพิ่งเริ่มเล่นหรือกำลังฝึกเสิร์ฟ/ตีโต้"},
    {"key": "p_minus", "label_th": "มือ P-", "label_en": "P- (Pre-P)", "description": "เริ่มวิ่งคอร์ตได้บ้าง ตีโต้ลูกพื้นฐานได้"},
    {"key": "p", "label_th": "มือ P", "label_en": "P", "description": "ตีเกมได้ วิ่งคอร์ตและจับจังหวะการเล่นคู่ได้"},
    {"key": "p_plus", "label_th": "มือ P+", "label_en": "P+", "description": "เล่นเกมคล่อง มีลูกตบ ลูกตัด หยอดได้สม่ำเสมอ"},
    {"key": "c", "label_th": "มือ C", "label_en": "C", "description": "เล่นประจำ แข็งแรง มีสปีดเกมและความแน่นอน"},
    {"key": "b", "label_th": "มือ B", "label_en": "B", "description": "ระดับนักกีฬาแข่งขัน/มือเดินสาย ทักษะระดับสูง"},
    {"key": "a", "label_th": "มือ A", "label_en": "A", "description": "ระดับแชมป์ / อดีตนักกีฬาทีมชาติ / มือโปร"}
  ]
}'::jsonb
WHERE name_th LIKE '%แบดมินตัน%' OR name_en ILIKE '%badminton%';

-- 5.2 Tennis & Pickleball (เทนนิส และ พิกเคิลบอล: NTRP / DUPR)
UPDATE public.sports
SET skill_levels = '{
  "type": "custom",
  "name": "NTRP Rating Scale",
  "levels": [
    {"key": "all", "label_th": "เปิดรับทุกระดับ", "label_en": "All Levels", "description": "ไม่จำกัดระดับฝีมือ เล่นร่วมกันได้"},
    {"key": "ntrp_2", "label_th": "NTRP 2.0 - 2.5", "label_en": "NTRP 2.0 - 2.5", "description": "มือใหม่ กำลังฝึกตีโฟร์แฮนด์/แบ็กแฮนด์และรักษาแรลลี่สั้นๆ"},
    {"key": "ntrp_3", "label_th": "NTRP 3.0 - 3.5", "label_en": "NTRP 3.0 - 3.5", "description": "ระดับปานกลาง ตีโต้ได้ต่อเนื่อง คุมทิศทางบอลได้ เล่นเกมแต้มสนุก"},
    {"key": "ntrp_4", "label_th": "NTRP 4.0 - 4.5", "label_en": "NTRP 4.0 - 4.5", "description": "ระดับสูง มีพลัง เสิร์ฟแน่นอน เล่นหน้าเน็ตคล่อง จังหวะเกมเร็ว"},
    {"key": "ntrp_5", "label_th": "NTRP 5.0+", "label_en": "NTRP 5.0+", "description": "ระดับแข่งขัน / อดีตนักกีฬา สภาพร่างกายและแท็กติกสูง"}
  ]
}'::jsonb
WHERE name_th LIKE '%เทนนิส%' OR name_th LIKE '%พิกเคิล%' OR name_en ILIKE '%tennis%' OR name_en ILIKE '%pickleball%';

-- 5.3 Running (วิ่ง: Pace range)
UPDATE public.sports
SET skill_levels = '{
  "type": "custom",
  "name": "ช่วงความเร็วการวิ่ง (Pace)",
  "levels": [
    {"key": "all", "label_th": "เปิดรับทุกระดับ", "label_en": "All Levels", "description": "วิ่งเพซไหนก็ได้ วิ่งชิลๆ รอเพื่อน"},
    {"key": "fun_run", "label_th": "Fun Run / เดิน-วิ่ง", "label_en": "Easy / Fun Run", "description": "วิ่งสลับเดิน เน้นเพื่อสุขภาพ พูดคุยได้สบาย (Pace 8-10+)"},
    {"key": "pace_7_8", "label_th": "Pace 7 - 8", "label_en": "Pace 7 - 8", "description": "วิ่งสบายๆ ต่อเนื่อง ไม่เหนื่อยเกินไป"},
    {"key": "pace_6", "label_th": "Pace 6", "label_en": "Pace 6 (Moderate)", "description": "วิ่งเร็วปานกลาง ฟิตซ้อมระยะมินิมาราธอน (10K)"},
    {"key": "pace_5", "label_th": "Pace 5", "label_en": "Pace 5 (Tempo)", "description": "วิ่งเร็ว ต่อเนื่อง ความฟิตสูง"},
    {"key": "sub_pace_4", "label_th": "Pace 4 ลงไป (Sub-4)", "label_en": "Sub-4 Pace (Fast)", "description": "วิ่งระดับแข่งขัน วิ่งเร็วมาก/อินเทอร์วัล"}
  ]
}'::jsonb
WHERE name_th LIKE '%วิ่ง%' OR name_en ILIKE '%running%';

-- 6. Update fitness_groups_public view to include target_skill_levels and skill_level_note
DROP VIEW IF EXISTS public.fitness_groups_public;

CREATE VIEW public.fitness_groups_public AS
SELECT
  g.id,
  g.sport_id,
  g.name,
  g.description,
  g.province,
  g.district,
  g.subdistrict,
  g.postal_code,
  g.lat,
  g.lng,
  g.gender_preference,
  g.requires_owner_approval,
  g.capacity,
  g.cover_image_url,
  g.venue_photo_url,
  g.created_at,
  g.target_skill_levels,
  g.skill_level_note,
  (
    SELECT COUNT(*)
    FROM public.fitness_group_sessions s
    WHERE s.group_id = g.id
      AND s.starts_at > now()
  ) AS upcoming_sessions_count,
  (
    SELECT COUNT(*)
    FROM public.fitness_group_sessions s
    JOIN public.fitness_group_bookings b ON b.session_id = s.id
    WHERE s.group_id = g.id
      AND s.starts_at > now()
      AND b.status = 'confirmed'
  ) AS upcoming_confirmed_count,
  (
    SELECT COUNT(*)
    FROM public.fitness_group_sessions s
    JOIN public.fitness_group_bookings b ON b.session_id = s.id
    WHERE s.group_id = g.id
      AND s.starts_at > now()
      AND b.status = 'pending'
  ) AS upcoming_pending_count
FROM public.fitness_groups g
WHERE g.visibility = 'public';

GRANT SELECT ON public.fitness_groups_public TO anon, authenticated;

-- 7. Update book_fitness_session to support declared_skill_level
-- Full superset of Phase 15 version: includes USER_BLOCKED, OVERLAP_BOOKING,
-- fitness_group_members upsert, and COUNT(DISTINCT) capacity check.
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
  v_is_owner BOOLEAN;
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

  -- User blocked check
  IF EXISTS (
    SELECT 1 FROM public.fitness_group_blocklist bl
    WHERE bl.group_id = v_group_id
      AND bl.blocked_user_id = p_user_id
      AND bl.is_active = true
  ) THEN
    RAISE EXCEPTION 'USER_BLOCKED';
  END IF;

  v_is_owner := COALESCE(v_owner_id = p_user_id, false);
  v_requires_approval := v_requires_approval AND NOT v_is_owner;

  -- Check existing booking
  SELECT b.status, b.position_id INTO v_existing_status, v_existing_pos_id
  FROM public.fitness_group_bookings b
  WHERE b.session_id = p_session_id AND b.user_id = p_user_id
  FOR UPDATE;

  IF v_existing_status = 'confirmed' THEN
    RAISE EXCEPTION 'ALREADY_JOINED';
  ELSIF v_existing_status = 'pending' THEN
    RAISE EXCEPTION 'ALREADY_REQUESTED';
  END IF;

  -- Overlap check (skip for owner auto-join and pending paths)
  IF NOT (v_is_owner AND v_owner_auto_join) AND NOT v_requires_approval THEN
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

NOTIFY pgrst, 'reload schema';


