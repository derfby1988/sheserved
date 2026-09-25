-- Patient returns a closed-ended question from 'reading' back to 'unread'
-- when switching to another required question (or closing the answer UI).
--
-- Only one required question may be 'reading' at a time: the amber colour +
-- typing animation means "patient is answering this question". Leaving the
-- previous question in 'reading' made the expert see several amber buttons
-- and assume the patient was answering multiple questions at once.
CREATE OR REPLACE FUNCTION public.mark_closed_ended_question_unread_backend(
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

  -- Patient-only: the expert never reverts the reading state.
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

  IF v_msg.required_status IS DISTINCT FROM 'reading' THEN
    RETURN jsonb_build_object('code', 'OK', 'status', v_msg.required_status);
  END IF;

  PERFORM set_config('app.closed_ended_rpc', 'on', true);

  UPDATE public.chat_messages
  SET required_status = 'unread'
  WHERE id = p_question_message_id
    AND required_status = 'reading';

  RETURN jsonb_build_object('code', 'OK', 'status', 'unread');
END;
$$;

REVOKE ALL ON FUNCTION public.mark_closed_ended_question_unread_backend(UUID, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_closed_ended_question_unread_backend(UUID, UUID)
  TO service_role;

NOTIFY pgrst, 'reload schema';
