-- Add get_all_experts_can_finish RPC to return completion status for ALL experts in a consultation
-- This enables real-time display of each expert's canFinish status in the ExpertStatusBanner

CREATE OR REPLACE FUNCTION public.get_all_experts_can_finish(
  p_consultation_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB := '[]'::jsonb;
  v_expert RECORD;
  v_can_finish BOOLEAN;
  v_package_id TEXT;
  v_room_id TEXT := public._get_room_id_for_consultation(p_consultation_id);
  v_rules RECORD;
  v_prescription_count INT;
  v_approved_count INT;
  v_question_count INT;
  v_answered_count INT;
  v_unanswered_count INT;
  v_has_video_call BOOLEAN;
  v_has_assessment BOOLEAN;
  v_general_message_count INT;
  v_progress INT;
  v_total INT;
BEGIN
  SELECT cr.package_id INTO v_package_id
  FROM public.consultation_requests cr WHERE cr.id = p_consultation_id;

  FOR v_expert IN
    SELECT re.provider_id, re.expert_group_name, re.finished_at, u.profession_id
    FROM public.consultation_room_experts re
    LEFT JOIN public.users u ON u.id = re.provider_id
    WHERE re.consultation_id = p_consultation_id
      AND re.provider_id IS NOT NULL
      AND re.status = 'joined'
  LOOP
    -- Reset per expert
    v_can_finish := false;
    v_progress := 0;
    v_total := 0;
    v_prescription_count := 0;
    v_approved_count := 0;
    v_question_count := 0;
    v_answered_count := 0;
    v_unanswered_count := 0;
    v_has_video_call := false;
    v_has_assessment := false;
    v_general_message_count := 0;

    -- Load rules for this expert's profession
    SELECT * INTO v_rules
    FROM public.get_profession_package_rules(v_package_id, v_expert.profession_id);

    IF FOUND THEN
      -- Count prescriptions
      SELECT COUNT(*) INTO v_prescription_count
      FROM public.prescriptions
      WHERE consultation_id = p_consultation_id AND provider_id = v_expert.provider_id;

      SELECT COUNT(*) INTO v_approved_count
      FROM public.prescriptions
      WHERE consultation_id = p_consultation_id AND provider_id = v_expert.provider_id AND is_approved = true;

      -- Count questions (by room_id)
      SELECT COUNT(*) INTO v_question_count
      FROM public.chat_messages
      WHERE room_id = v_room_id AND is_required = true AND required_owner_id = v_expert.provider_id;

      SELECT COUNT(*) INTO v_answered_count
      FROM public.chat_messages
      WHERE room_id = v_room_id AND is_required = true AND required_owner_id = v_expert.provider_id AND required_status = 'answered';

      SELECT COUNT(*) INTO v_unanswered_count
      FROM public.chat_messages
      WHERE room_id = v_room_id AND is_required = true AND required_owner_id = v_expert.provider_id AND required_status != 'answered';

      -- Video call & assessment
      SELECT COALESCE(has_video_call, false), COALESCE(has_assessment, false)
      INTO v_has_video_call, v_has_assessment
      FROM public.consultation_room_experts
      WHERE consultation_id = p_consultation_id AND provider_id = v_expert.provider_id;

      -- General messages
      SELECT COUNT(*) INTO v_general_message_count
      FROM public.chat_messages
      WHERE room_id = v_room_id AND sender_id = v_expert.provider_id AND (is_required = false OR is_required IS NULL);

      -- Calculate total required items
      IF v_rules.must_prescribe THEN v_total := v_total + 1; END IF;
      IF v_rules.min_required_questions > 0 THEN v_total := v_total + 1; END IF;
      IF v_rules.must_answer_all_questions THEN v_total := v_total + 1; END IF;
      IF v_rules.requires_video_call THEN v_total := v_total + 1; END IF;
      IF v_rules.requires_health_assessment THEN v_total := v_total + 1; END IF;
      IF v_rules.min_general_messages > 0 THEN v_total := v_total + 1; END IF;

      -- Calculate progress
      IF v_rules.must_prescribe AND v_prescription_count > 0 THEN v_progress := v_progress + 1; END IF;
      IF v_rules.min_required_questions > 0 AND v_question_count >= v_rules.min_required_questions THEN v_progress := v_progress + 1; END IF;
      IF v_rules.must_answer_all_questions AND v_unanswered_count = 0 THEN v_progress := v_progress + 1; END IF;
      IF v_rules.requires_video_call AND v_has_video_call THEN v_progress := v_progress + 1; END IF;
      IF v_rules.requires_health_assessment AND v_has_assessment THEN v_progress := v_progress + 1; END IF;
      IF v_rules.min_general_messages > 0 AND v_general_message_count >= v_rules.min_general_messages THEN v_progress := v_progress + 1; END IF;

      v_can_finish := v_total > 0 AND v_progress >= v_total;
    ELSE
      -- No rules found → allow finish
      v_can_finish := true;
    END IF;

    v_result := v_result || jsonb_build_object(
      'provider_id', v_expert.provider_id,
      'can_finish', v_can_finish,
      'progress', CASE WHEN v_total > 0 THEN (v_progress * 100 / v_total) ELSE 100 END,
      'finished_at', v_expert.finished_at
    );
  END LOOP;

  RETURN jsonb_build_object('experts', v_result);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Force reload schema cache
NOTIFY pgrst, 'reload schema';
