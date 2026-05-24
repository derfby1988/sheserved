-- Migration: Repair consultation chat rooms
-- Purpose: Backfill old consultation rooms so both patient and provider can
-- rediscover the room and reload message history after leaving/re-entering.

CREATE OR REPLACE FUNCTION public.repair_consultation_chat_room(
  p_consultation_id UUID
)
RETURNS TEXT AS $$
DECLARE
  v_request RECORD;
  v_room_id TEXT;
  v_joined_provider_ids UUID[] := '{}'::UUID[];
BEGIN
  SELECT
    cr.id,
    cr.user_id AS patient_id,
    cr.provider_id,
    cr.package_id,
    cr.package_name,
    cr.room_id
  INTO v_request
  FROM public.consultation_requests cr
  WHERE cr.id = p_consultation_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT provider_id), '{}'::UUID[])
  INTO v_joined_provider_ids
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id
    AND provider_id IS NOT NULL
    AND status = 'joined';

  -- Preserve an existing mapped room_id first, then fall back to consultation_id-based room.
  SELECT room_id
  INTO v_room_id
  FROM public.consultation_requests
  WHERE id = p_consultation_id
    AND room_id IS NOT NULL
  LIMIT 1;

  IF v_room_id IS NULL THEN
    SELECT id
    INTO v_room_id
    FROM public.chat_rooms
    WHERE consultation_id = p_consultation_id
    LIMIT 1;
  END IF;

  IF v_room_id IS NULL THEN
    v_room_id := 'consult_' || p_consultation_id::text;
  END IF;

  -- Ensure the room row exists.
  INSERT INTO public.chat_rooms (
    id,
    participant_ids,
    room_type,
    consultation_id,
    package_id,
    title,
    is_active,
    updated_at
  ) VALUES (
    v_room_id,
    (
      SELECT ARRAY(
        SELECT DISTINCT u
        FROM unnest(
          COALESCE(ARRAY[v_request.patient_id], '{}'::UUID[])
          || COALESCE(ARRAY[v_request.provider_id], '{}'::UUID[])
          || COALESCE(v_joined_provider_ids, '{}'::UUID[])
        ) AS u
        WHERE u IS NOT NULL
      )
    ),
    'consultation',
    p_consultation_id,
    v_request.package_id,
    v_request.package_name,
    true,
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  -- Merge any existing room participants with the required consultation members.
  UPDATE public.chat_rooms AS cr
  SET
    participant_ids = (
      SELECT ARRAY(
        SELECT DISTINCT u
        FROM unnest(
          COALESCE(cr.participant_ids, '{}'::UUID[])
          || COALESCE(ARRAY[v_request.patient_id], '{}'::UUID[])
          || COALESCE(ARRAY[v_request.provider_id], '{}'::UUID[])
          || COALESCE(v_joined_provider_ids, '{}'::UUID[])
        ) AS u
        WHERE u IS NOT NULL
      )
    ),
    room_type = 'consultation',
    consultation_id = p_consultation_id,
    package_id = COALESCE(v_request.package_id, cr.package_id),
    title = COALESCE(v_request.package_name, cr.title),
    updated_at = now()
  WHERE cr.id = v_room_id;

  -- Keep consultation_requests.room_id aligned with the repaired room.
  UPDATE public.consultation_requests
  SET room_id = v_room_id,
      updated_at = now()
  WHERE id = p_consultation_id
    AND (room_id IS NULL OR room_id <> v_room_id);

  -- Keep consultation_room_experts.room_id aligned too.
  UPDATE public.consultation_room_experts
  SET room_id = v_room_id
  WHERE consultation_id = p_consultation_id
    AND (room_id IS NULL OR room_id <> v_room_id);

  -- Ensure the patient and current/joined providers are in chat_room_members.
  INSERT INTO public.chat_room_members (room_id, user_id, role, joined_at)
  VALUES (v_room_id, v_request.patient_id, 'patient', now())
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET role = EXCLUDED.role;

  IF v_request.provider_id IS NOT NULL THEN
    INSERT INTO public.chat_room_members (room_id, user_id, role, joined_at)
    VALUES (v_room_id, v_request.provider_id, 'doctor', now())
    ON CONFLICT (room_id, user_id)
    DO UPDATE SET role = EXCLUDED.role;
  END IF;

  INSERT INTO public.chat_room_members (room_id, user_id, role, joined_at)
  SELECT v_room_id, ce.provider_id, 'doctor', now()
  FROM public.consultation_room_experts ce
  WHERE ce.consultation_id = p_consultation_id
    AND ce.provider_id IS NOT NULL
    AND ce.status = 'joined'
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET role = EXCLUDED.role;

  RETURN v_room_id;
END;
$$ LANGUAGE plpgsql;

-- Repair only consultation requests that already have evidence of a room/history.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT q.id
    FROM public.consultation_requests q
    WHERE q.room_id IS NOT NULL
       OR EXISTS (
         SELECT 1
         FROM public.chat_rooms cr
         WHERE cr.consultation_id = q.id
            OR cr.id = 'consult_' || q.id::text
       )
       OR EXISTS (
         SELECT 1
         FROM public.chat_messages cm
         WHERE cm.room_id = 'consult_' || q.id::text
       )
       OR EXISTS (
         SELECT 1
         FROM public.consultation_room_experts ce
         WHERE ce.consultation_id = q.id
       )
  LOOP
    PERFORM public.repair_consultation_chat_room(r.id);
  END LOOP;
END $$;

-- Optional helper for manual re-runs.
CREATE OR REPLACE FUNCTION public.repair_all_consultation_chat_rooms()
RETURNS void AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id
    FROM public.consultation_requests
  LOOP
    PERFORM public.repair_consultation_chat_room(r.id);
  END LOOP;
END;
$$ LANGUAGE plpgsql;
