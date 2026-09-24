CREATE OR REPLACE FUNCTION public.send_closed_ended_question_backend(
  p_room_id TEXT,
  p_content TEXT,
  p_config JSONB,
  p_body_part TEXT,
  p_caller_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_caller UUID := p_caller_id;
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

  SELECT r.consultation_id INTO v_consultation_id
  FROM public.chat_rooms r
  WHERE r.id = p_room_id;

  IF v_consultation_id IS NULL THEN
    SELECT cr.id INTO v_consultation_id
    FROM public.consultation_requests cr
    WHERE cr.room_id = p_room_id
    LIMIT 1;
  END IF;

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

CREATE OR REPLACE FUNCTION public.mark_closed_ended_question_reading_backend(
  p_question_message_id UUID,
  p_caller_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_caller UUID := p_caller_id;
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

CREATE OR REPLACE FUNCTION public.answer_closed_ended_question_backend(
  p_question_message_id UUID,
  p_selected_index INT,
  p_caller_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_caller UUID := p_caller_id;
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

ALTER FUNCTION public._validate_closed_ended_config(JSONB)
  SET search_path = pg_catalog, public;

REVOKE ALL ON FUNCTION public.send_closed_ended_question(TEXT, TEXT, JSONB, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.mark_closed_ended_question_reading(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.answer_closed_ended_question(UUID, INT)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.send_closed_ended_question_backend(TEXT, TEXT, JSONB, TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.mark_closed_ended_question_reading_backend(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.answer_closed_ended_question_backend(UUID, INT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.send_closed_ended_question_backend(TEXT, TEXT, JSONB, TEXT, UUID)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_closed_ended_question_reading_backend(UUID, UUID)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.answer_closed_ended_question_backend(UUID, INT, UUID)
  TO service_role;

REVOKE ALL PRIVILEGES ON TABLE public.closed_ended_question_answers
  FROM PUBLIC, anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
