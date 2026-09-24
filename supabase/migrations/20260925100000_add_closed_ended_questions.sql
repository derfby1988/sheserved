-- Phase 6.14: Closed-ended Question System (ระบบคำถามปลายปิด)
-- Additive migration: does NOT change existing chat_messages defaults,
-- policies, or behavior for other message types.
--
-- Layout:
--   1) chat_messages.closed_ended_config JSONB (nullable, immutable question
--      definition — answers live in a separate table)
--   2) closed_ended_question_answers (one confirmed answer per question)
--   3) Scoped CHECK constraint for type='closed_ended_question'
--   4) Write-path guard trigger (closed-ended rows mutate via RPC only)
--   5) RPCs: send / mark-reading / answer (SECURITY DEFINER, fixed search_path)
--   6) Grants + RLS

-- =====================================================================
-- 1) Config column (immutable question definition)
-- =====================================================================
ALTER TABLE public.chat_messages
ADD COLUMN IF NOT EXISTS closed_ended_config JSONB;

COMMENT ON COLUMN public.chat_messages.closed_ended_config IS
'Phase 6.14: immutable closed-ended question definition. '
'{"schema_version":1,"type":"quantitative","scale_levels":3|5|10} or '
'{"schema_version":1,"type":"qualitative","options":[...2..10 labels]}. '
'Confirmed answers live in closed_ended_question_answers; '
'required_answer/required_answered_at are compatibility projections.';

-- =====================================================================
-- 2) Answer table — exactly one confirmed answer per question
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.closed_ended_question_answers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question_message_id UUID NOT NULL UNIQUE
    REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.users(id),
  selected_index SMALLINT NOT NULL CHECK (selected_index >= 0),
  selected_value TEXT NOT NULL CHECK (length(btrim(selected_value)) > 0),
  answered_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.closed_ended_question_answers IS
'Phase 6.14: confirmed patient answers for closed_ended_question messages. '
'selected_value snapshots the chosen label; UNIQUE(question_message_id) '
'enforces one answer per question. Writes go through '
'answer_closed_ended_question() only.';

CREATE INDEX IF NOT EXISTS idx_closed_ended_answers_patient
ON public.closed_ended_question_answers(patient_id);

-- =====================================================================
-- 3) Scoped CHECK — only constrains the new message type
-- =====================================================================
ALTER TABLE public.chat_messages
  DROP CONSTRAINT IF EXISTS chat_messages_closed_ended_config_chk;

ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_closed_ended_config_chk
  CHECK (
    type <> 'closed_ended_question'
    OR (
      is_required = true
      AND jsonb_typeof(closed_ended_config) = 'object'
      AND (
        (
          closed_ended_config->>'type' = 'quantitative'
          AND jsonb_typeof(closed_ended_config->'scale_levels') = 'number'
          AND (closed_ended_config->>'scale_levels')::numeric IN (3, 5, 10)
        )
        OR (
          closed_ended_config->>'type' = 'qualitative'
          AND jsonb_typeof(closed_ended_config->'options') = 'array'
          AND jsonb_array_length(closed_ended_config->'options') BETWEEN 2 AND 10
        )
      )
    )
  );

-- =====================================================================
-- 4) Write-path guard: closed-ended lifecycle columns change via RPC only
--    (the RPCs set a transaction-local GUC before writing). Other message
--    types and unrelated columns (content, read_by, …) pass untouched.
-- =====================================================================
CREATE OR REPLACE FUNCTION public._guard_closed_ended_question_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.type = 'closed_ended_question'
       AND current_setting('app.closed_ended_rpc', true) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION
        'closed_ended_question must be created via send_closed_ended_question()';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF (NEW.type = 'closed_ended_question'
        OR OLD.type = 'closed_ended_question')
       AND current_setting('app.closed_ended_rpc', true) IS DISTINCT FROM 'on' THEN
      IF NEW.type IS DISTINCT FROM OLD.type
         OR NEW.is_required IS DISTINCT FROM OLD.is_required
         OR NEW.required_status IS DISTINCT FROM OLD.required_status
         OR NEW.required_answer IS DISTINCT FROM OLD.required_answer
         OR NEW.required_answered_at IS DISTINCT FROM OLD.required_answered_at
         OR NEW.closed_ended_config IS DISTINCT FROM OLD.closed_ended_config THEN
        RAISE EXCEPTION
          'closed_ended_question status/answer/config change via RPC only';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_closed_ended_question_write
ON public.chat_messages;

CREATE TRIGGER trg_guard_closed_ended_question_write
  BEFORE INSERT OR UPDATE ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public._guard_closed_ended_question_write();

-- =====================================================================
-- 5) RPCs
-- =====================================================================

-- Shared config validator: returns NULL when valid, error text otherwise.
CREATE OR REPLACE FUNCTION public._validate_closed_ended_config(p_config JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_type TEXT;
  v_levels NUMERIC;
  v_options JSONB;
  v_label TEXT;
  v_seen TEXT[] := '{}'::TEXT[];
  v_norm TEXT;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN 'config must be a JSON object';
  END IF;

  v_type := p_config->>'type';

  IF v_type = 'quantitative' THEN
    IF jsonb_typeof(p_config->'scale_levels') IS DISTINCT FROM 'number' THEN
      RETURN 'quantitative requires numeric scale_levels';
    END IF;
    v_levels := (p_config->>'scale_levels')::numeric;
    IF v_levels NOT IN (3, 5, 10) THEN
      RETURN 'scale_levels must be 3, 5 or 10';
    END IF;
    RETURN NULL;
  END IF;

  IF v_type = 'qualitative' THEN
    v_options := p_config->'options';
    IF jsonb_typeof(v_options) IS DISTINCT FROM 'array' THEN
      RETURN 'qualitative requires an options array';
    END IF;
    IF jsonb_array_length(v_options) < 2
       OR jsonb_array_length(v_options) > 10 THEN
      RETURN 'options must contain 2-10 entries';
    END IF;
    FOR v_label IN
      SELECT jsonb_array_elements_text(v_options)
    LOOP
      v_norm := lower(btrim(v_label));
      IF v_norm = '' THEN
        RETURN 'options must not contain empty labels';
      END IF;
      IF length(v_norm) > 80 THEN
        RETURN 'option labels must not exceed 80 characters';
      END IF;
      IF v_norm = ANY(v_seen) THEN
        RETURN 'options must not contain duplicate labels';
      END IF;
      v_seen := v_seen || v_norm;
    END LOOP;
    RETURN NULL;
  END IF;

  RETURN 'type must be quantitative or qualitative';
END;
$$;

-- Expert sends a closed-ended question into a consultation room.
CREATE OR REPLACE FUNCTION public.send_closed_ended_question(
  p_room_id TEXT,
  p_content TEXT,
  p_config JSONB,
  p_body_part TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_consultation_id UUID;
  v_config_error TEXT;
  v_message_id UUID;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('code', 'UNAUTHORIZED');
  END IF;

  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RETURN jsonb_build_object('code', 'INVALID_CONTENT');
  END IF;

  -- Resolve the consultation behind the room (both directions exist in
  -- production data: chat_rooms.consultation_id and
  -- consultation_requests.room_id).
  SELECT r.consultation_id INTO v_consultation_id
  FROM public.chat_rooms r
  WHERE r.id = p_room_id;

  IF v_consultation_id IS NULL THEN
    SELECT cr.id INTO v_consultation_id
    FROM public.consultation_requests cr
    WHERE cr.room_id = p_room_id
    LIMIT 1;
  END IF;

  -- Caller must be an expert of this consultation (not merely a participant).
  IF NOT (
    EXISTS (
      SELECT 1 FROM public.consultation_room_experts e
      WHERE e.consultation_id = v_consultation_id
        AND e.provider_id = v_caller
        AND e.status = 'joined'
    )
    OR EXISTS (
      SELECT 1 FROM public.consultation_requests cr
      WHERE cr.id = v_consultation_id AND cr.provider_id = v_caller
    )
    OR EXISTS (
      SELECT 1 FROM public.chat_room_members m
      WHERE m.room_id = p_room_id
        AND m.user_id = v_caller
        AND m.role IN ('doctor', 'admin')
    )
  ) THEN
    RETURN jsonb_build_object('code', 'FORBIDDEN');
  END IF;

  v_config_error := public._validate_closed_ended_config(p_config);
  IF v_config_error IS NOT NULL THEN
    RETURN jsonb_build_object('code', 'INVALID_CONFIG', 'detail', v_config_error);
  END IF;

  PERFORM set_config('app.closed_ended_rpc', 'on', true);

  INSERT INTO public.chat_messages (
    room_id, sender_id, content, type,
    is_required, required_status, required_owner_id,
    body_part, closed_ended_config
  ) VALUES (
    p_room_id, v_caller, btrim(p_content), 'closed_ended_question',
    true, 'unread', v_caller,
    p_body_part, p_config
  )
  RETURNING id INTO v_message_id;

  UPDATE public.chat_rooms
  SET last_message = btrim(p_content), updated_at = now()
  WHERE id = p_room_id;

  RETURN jsonb_build_object('code', 'OK', 'message_id', v_message_id);
END;
$$;

-- Patient opens a closed-ended question: unread -> reading.
-- Idempotent for 'reading'; never moves 'answered' backwards.
CREATE OR REPLACE FUNCTION public.mark_closed_ended_question_reading(
  p_question_message_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_msg RECORD;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('code', 'UNAUTHORIZED');
  END IF;

  SELECT m.id, m.type, m.required_status, m.room_id, r.consultation_id
  INTO v_msg
  FROM public.chat_messages m
  LEFT JOIN public.chat_rooms r ON r.id = m.room_id
  WHERE m.id = p_question_message_id
  FOR UPDATE OF m;

  IF NOT FOUND OR v_msg.type <> 'closed_ended_question' THEN
    RETURN jsonb_build_object('code', 'NOT_FOUND');
  END IF;

  -- Caller must be the patient bound to this consultation/room.
  IF NOT (
    EXISTS (
      SELECT 1 FROM public.consultation_requests cr
      WHERE cr.id = v_msg.consultation_id AND cr.user_id = v_caller
    )
    OR EXISTS (
      SELECT 1 FROM public.chat_room_members mem
      WHERE mem.room_id = v_msg.room_id
        AND mem.user_id = v_caller
        AND mem.role = 'patient'
    )
  ) THEN
    RETURN jsonb_build_object('code', 'FORBIDDEN');
  END IF;

  IF v_msg.required_status = 'answered' THEN
    RETURN jsonb_build_object('code', 'ALREADY_ANSWERED');
  END IF;

  IF v_msg.required_status = 'reading' THEN
    RETURN jsonb_build_object('code', 'OK', 'status', 'reading');
  END IF;

  PERFORM set_config('app.closed_ended_rpc', 'on', true);

  UPDATE public.chat_messages
  SET required_status = 'reading'
  WHERE id = p_question_message_id
    AND required_status = 'unread';

  RETURN jsonb_build_object('code', 'OK', 'status', 'reading');
END;
$$;

-- Patient confirms an option: insert answer + project status atomically.
-- Unique(question_message_id) + row lock guard double submit/replay.
CREATE OR REPLACE FUNCTION public.answer_closed_ended_question(
  p_question_message_id UUID,
  p_selected_index INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_msg RECORD;
  v_config JSONB;
  v_type TEXT;
  v_count INT;
  v_label TEXT;
  v_existing RECORD;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('code', 'UNAUTHORIZED');
  END IF;

  -- Lock the question row for the whole transaction.
  SELECT m.id, m.type, m.is_required, m.required_status, m.room_id,
         m.closed_ended_config, r.consultation_id
  INTO v_msg
  FROM public.chat_messages m
  LEFT JOIN public.chat_rooms r ON r.id = m.room_id
  WHERE m.id = p_question_message_id
  FOR UPDATE OF m;

  IF NOT FOUND OR v_msg.type <> 'closed_ended_question' THEN
    RETURN jsonb_build_object('code', 'NOT_FOUND');
  END IF;

  IF v_msg.is_required IS DISTINCT FROM true
     OR public._validate_closed_ended_config(v_msg.closed_ended_config) IS NOT NULL THEN
    RETURN jsonb_build_object('code', 'INVALID_CONFIG');
  END IF;

  -- Caller must be the patient bound to this consultation/room.
  IF NOT (
    EXISTS (
      SELECT 1 FROM public.consultation_requests cr
      WHERE cr.id = v_msg.consultation_id AND cr.user_id = v_caller
    )
    OR EXISTS (
      SELECT 1 FROM public.chat_room_members mem
      WHERE mem.room_id = v_msg.room_id
        AND mem.user_id = v_caller
        AND mem.role = 'patient'
    )
  ) THEN
    RETURN jsonb_build_object('code', 'FORBIDDEN');
  END IF;

  -- Idempotent replay: never overwrite the original confirmed answer.
  SELECT a.selected_index, a.selected_value
  INTO v_existing
  FROM public.closed_ended_question_answers a
  WHERE a.question_message_id = p_question_message_id;

  IF FOUND OR v_msg.required_status = 'answered' THEN
    RETURN jsonb_build_object(
      'code', 'ALREADY_ANSWERED',
      'selected_index', v_existing.selected_index,
      'selected_value', v_existing.selected_value
    );
  END IF;

  -- Resolve the chosen label from the immutable config.
  v_config := v_msg.closed_ended_config;
  v_type := v_config->>'type';
  IF v_type = 'quantitative' THEN
    v_count := (v_config->>'scale_levels')::int;
    v_label := (p_selected_index + 1)::text;
  ELSE
    v_count := jsonb_array_length(v_config->'options');
    v_label := v_config->'options'->>p_selected_index;
  END IF;

  IF p_selected_index IS NULL
     OR p_selected_index < 0
     OR p_selected_index >= v_count
     OR v_label IS NULL THEN
    RETURN jsonb_build_object('code', 'INVALID_INDEX');
  END IF;

  PERFORM set_config('app.closed_ended_rpc', 'on', true);

  -- Unique(question_message_id) makes a concurrent second insert fail;
  -- the conditional update below then returns ALREADY_ANSWERED.
  INSERT INTO public.closed_ended_question_answers (
    question_message_id, patient_id, selected_index, selected_value
  ) VALUES (
    p_question_message_id, v_caller, p_selected_index, v_label
  );

  UPDATE public.chat_messages
  SET required_status = 'answered',
      required_answer = v_label,
      required_answered_at = now()
  WHERE id = p_question_message_id
    AND required_status <> 'answered';

  RETURN jsonb_build_object(
    'code', 'OK',
    'selected_index', p_selected_index,
    'selected_value', v_label
  );
END;
$$;

-- =====================================================================
-- 6) Grants + RLS
-- =====================================================================
REVOKE ALL ON FUNCTION public._validate_closed_ended_config(JSONB)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._guard_closed_ended_question_write()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.send_closed_ended_question(TEXT, TEXT, JSONB, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_closed_ended_question_reading(UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.answer_closed_ended_question(UUID, INT)
  TO authenticated;

-- Answers: read-only via RLS; all writes go through the RPC above.
ALTER TABLE public.closed_ended_question_answers ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE ON public.closed_ended_question_answers
  FROM anon, authenticated;
GRANT SELECT ON public.closed_ended_question_answers TO authenticated;

DROP POLICY IF EXISTS "closed_ended_answers_select"
ON public.closed_ended_question_answers;

CREATE POLICY "closed_ended_answers_select"
ON public.closed_ended_question_answers
FOR SELECT TO authenticated
USING (
  patient_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.chat_messages m
    JOIN public.chat_rooms r ON r.id = m.room_id
    WHERE m.id = question_message_id
      AND (
        EXISTS (
          SELECT 1 FROM public.consultation_requests cr
          WHERE cr.id = r.consultation_id AND cr.provider_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.consultation_room_experts e
          WHERE e.consultation_id = r.consultation_id
            AND e.provider_id = auth.uid()
            AND e.status = 'joined'
        )
        OR EXISTS (
          SELECT 1 FROM public.chat_room_members mem
          WHERE mem.room_id = m.room_id
            AND mem.user_id = auth.uid()
            AND mem.role IN ('doctor', 'admin')
        )
      )
  )
);

NOTIFY pgrst, 'reload schema';
