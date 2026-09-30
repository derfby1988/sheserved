CREATE OR REPLACE FUNCTION public.edit_required_question_backend(
  p_question_message_id UUID,
  p_content TEXT,
  p_caller_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_msg RECORD;
  v_consultation_id UUID;
  v_updated_id UUID;
BEGIN
  IF p_caller_id IS NULL THEN
    RETURN jsonb_build_object('code', 'UNAUTHORIZED');
  END IF;

  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RETURN jsonb_build_object('code', 'INVALID_CONTENT');
  END IF;

  SELECT m.id, m.room_id, m.content, m.type, m.is_required,
         m.required_status, m.closed_ended_config, r.consultation_id
  INTO v_msg
  FROM public.chat_messages m
  LEFT JOIN public.chat_rooms r ON r.id = m.room_id
  WHERE m.id = p_question_message_id
  FOR UPDATE OF m;

  IF NOT FOUND
     OR v_msg.is_required IS DISTINCT FROM true
     OR v_msg.type NOT IN ('required_question', 'closed_ended_question') THEN
    RETURN jsonb_build_object('code', 'NOT_FOUND');
  END IF;

  v_consultation_id := v_msg.consultation_id;
  IF v_consultation_id IS NULL THEN
    SELECT cr.id INTO v_consultation_id
    FROM public.consultation_requests cr
    WHERE cr.room_id = v_msg.room_id
    LIMIT 1;
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1 FROM public.consultation_room_experts e
      WHERE e.consultation_id = v_consultation_id
        AND e.provider_id = p_caller_id
        AND e.status = 'joined'
    )
    OR EXISTS (
      SELECT 1 FROM public.consultation_requests cr
      WHERE cr.id = v_consultation_id AND cr.provider_id = p_caller_id
    )
    OR EXISTS (
      SELECT 1 FROM public.chat_room_members mem
      WHERE mem.room_id = v_msg.room_id
        AND mem.user_id = p_caller_id
        AND mem.role IN ('doctor', 'admin')
    )
  ) THEN
    RETURN jsonb_build_object('code', 'FORBIDDEN');
  END IF;

  IF v_msg.required_status IS DISTINCT FROM 'unread' THEN
    RETURN jsonb_build_object(
      'code', 'STATUS_CHANGED',
      'status', v_msg.required_status,
      'message_id', v_msg.id
    );
  END IF;

  IF v_msg.type = 'closed_ended_question'
     AND public._validate_closed_ended_config(v_msg.closed_ended_config) IS NOT NULL THEN
    RETURN jsonb_build_object('code', 'INVALID_CONFIG');
  END IF;

  IF v_msg.type = 'closed_ended_question' THEN
    PERFORM set_config('app.closed_ended_rpc', 'on', true);
  END IF;

  UPDATE public.chat_messages
  SET content = btrim(p_content),
      required_owner_id = p_caller_id
  WHERE id = p_question_message_id
    AND required_status = 'unread'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RETURN jsonb_build_object(
      'code', 'STATUS_CHANGED',
      'status', v_msg.required_status,
      'message_id', v_msg.id
    );
  END IF;

  INSERT INTO public.required_question_edits (
    message_id, previous_content, edited_by
  ) VALUES (
    v_msg.id, v_msg.content, p_caller_id
  );

  RETURN jsonb_build_object('code', 'OK', 'message_id', v_msg.id);
END;
$$;

REVOKE ALL ON FUNCTION public.edit_required_question_backend(UUID, TEXT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.edit_required_question_backend(UUID, TEXT, UUID)
  TO service_role;

NOTIFY pgrst, 'reload schema';
