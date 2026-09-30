CREATE TABLE IF NOT EXISTS public.expert_closed_ended_option_history (
  expert_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  normalized_label TEXT NOT NULL,
  option_label TEXT NOT NULL,
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (expert_id, normalized_label),
  CHECK (length(btrim(option_label)) BETWEEN 1 AND 80)
);

CREATE INDEX IF NOT EXISTS idx_expert_closed_ended_option_history_recent
ON public.expert_closed_ended_option_history(expert_id, last_used_at DESC);

ALTER TABLE public.expert_closed_ended_option_history ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.expert_closed_ended_option_history
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_expert_closed_ended_option_history_backend(
  p_expert_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_options JSONB;
BEGIN
  IF p_expert_id IS NULL THEN
    RETURN jsonb_build_object('code', 'UNAUTHORIZED');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      recent.option_label
      ORDER BY recent.last_used_at DESC, recent.normalized_label
    ),
    '[]'::jsonb
  )
  INTO v_options
  FROM (
    SELECT option_label, normalized_label, last_used_at
    FROM public.expert_closed_ended_option_history
    WHERE expert_id = p_expert_id
    ORDER BY last_used_at DESC, normalized_label
    LIMIT 15
  ) AS recent;

  RETURN jsonb_build_object('code', 'OK', 'options', v_options);
END;
$$;

CREATE OR REPLACE FUNCTION public.answer_closed_ended_question_with_history_backend(
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
  v_result JSONB;
  v_expert_id UUID;
  v_config JSONB;
  v_option TEXT;
BEGIN
  v_result := public.answer_closed_ended_question_backend(
    p_question_message_id,
    p_selected_index,
    p_caller_id
  );

  IF v_result->>'code' IS DISTINCT FROM 'OK' THEN
    RETURN v_result;
  END IF;

  SELECT COALESCE(m.required_owner_id, m.sender_id), m.closed_ended_config
  INTO v_expert_id, v_config
  FROM public.chat_messages m
  WHERE m.id = p_question_message_id;

  IF v_expert_id IS NULL OR v_config->>'type' IS DISTINCT FROM 'qualitative' THEN
    RETURN v_result;
  END IF;

  FOR v_option IN
    SELECT jsonb_array_elements_text(v_config->'options')
  LOOP
    INSERT INTO public.expert_closed_ended_option_history (
      expert_id,
      normalized_label,
      option_label,
      last_used_at
    ) VALUES (
      v_expert_id,
      lower(btrim(v_option)),
      btrim(v_option),
      clock_timestamp()
    )
    ON CONFLICT (expert_id, normalized_label) DO UPDATE
    SET option_label = EXCLUDED.option_label,
        last_used_at = EXCLUDED.last_used_at;
  END LOOP;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_expert_closed_ended_option_history_backend(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_expert_closed_ended_option_history_backend(UUID)
  TO service_role;

REVOKE ALL ON FUNCTION public.answer_closed_ended_question_with_history_backend(UUID, INT, UUID)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.answer_closed_ended_question_with_history_backend(UUID, INT, UUID)
  TO service_role;

NOTIFY pgrst, 'reload schema';
