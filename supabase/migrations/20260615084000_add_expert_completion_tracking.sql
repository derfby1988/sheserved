-- Migration: Add expert completion tracking for multi-expert consultations
-- Description: Track when each expert finishes their work, and only mark consultation as completed when ALL experts have finished

-- 1. Add finished_at column to consultation_room_experts
ALTER TABLE public.consultation_room_experts
ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ;

COMMENT ON COLUMN public.consultation_room_experts.finished_at IS 'Timestamp when this expert marked their work as finished. NULL = still working.';

-- 2. Create index for efficient querying
CREATE INDEX IF NOT EXISTS idx_room_experts_finished_at ON public.consultation_room_experts(consultation_id, finished_at);

-- 3. RPC: Mark expert as finished and check if all experts are done
CREATE OR REPLACE FUNCTION public.mark_expert_finished(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_total_experts INT;
  v_finished_experts INT;
  v_all_finished BOOLEAN := false;
BEGIN
  -- Mark this expert as finished
  UPDATE public.consultation_room_experts
  SET finished_at = now()
  WHERE consultation_id = p_consultation_id
    AND provider_id = p_provider_id
    AND finished_at IS NULL;

  -- Count total assigned experts for this consultation
  SELECT COUNT(*) INTO v_total_experts
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id
    AND provider_id IS NOT NULL;

  -- Count finished experts
  SELECT COUNT(*) INTO v_finished_experts
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id
    AND provider_id IS NOT NULL
    AND finished_at IS NOT NULL;

  -- Check if all experts have finished
  IF v_total_experts > 0 AND v_finished_experts >= v_total_experts THEN
    v_all_finished := true;
    
    -- Mark consultation as completed
    UPDATE public.consultation_requests
    SET status = 'completed',
        updated_at = now()
    WHERE id = p_consultation_id
      AND status != 'completed';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'all_finished', v_all_finished,
    'finished_count', v_finished_experts,
    'total_count', v_total_experts,
    'remaining_count', v_total_experts - v_finished_experts
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RPC: Get expert completion status for a consultation
CREATE OR REPLACE FUNCTION public.get_expert_completion_status(
  p_consultation_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_total_experts INT;
  v_finished_experts INT;
  v_experts JSONB;
BEGIN
  -- Count total assigned experts
  SELECT COUNT(*) INTO v_total_experts
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id
    AND provider_id IS NOT NULL;

  -- Count finished experts
  SELECT COUNT(*) INTO v_finished_experts
  FROM public.consultation_room_experts
  WHERE consultation_id = p_consultation_id
    AND provider_id IS NOT NULL
    AND finished_at IS NOT NULL;

  -- Get list of experts with their completion status
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'provider_id', re.provider_id,
      'expert_group_name', re.expert_group_name,
      'finished_at', re.finished_at,
      'is_finished', re.finished_at IS NOT NULL
    )
  ), '[]'::jsonb) INTO v_experts
  FROM public.consultation_room_experts re
  WHERE re.consultation_id = p_consultation_id
    AND re.provider_id IS NOT NULL;

  RETURN jsonb_build_object(
    'total_count', v_total_experts,
    'finished_count', v_finished_experts,
    'remaining_count', v_total_experts - v_finished_experts,
    'all_finished', v_total_experts > 0 AND v_finished_experts >= v_total_experts,
    'experts', v_experts
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: Reset expert finish status (for admin/debug purposes)
CREATE OR REPLACE FUNCTION public.reset_expert_completion(
  p_consultation_id UUID
)
RETURNS JSONB AS $$
BEGIN
  UPDATE public.consultation_room_experts
  SET finished_at = NULL
  WHERE consultation_id = p_consultation_id;

  RETURN jsonb_build_object('success', true, 'message', 'Reset expert completion status');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Add left_at column to track when expert leaves the chat room
ALTER TABLE public.consultation_room_experts
ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ;

COMMENT ON COLUMN public.consultation_room_experts.left_at IS 'Timestamp when this expert left the chat room. NULL = still in room. Set when provider navigates away from chat. Cleared when they re-enter.';

-- 7. Create index for efficient querying of left_at
CREATE INDEX IF NOT EXISTS idx_room_experts_left_at ON public.consultation_room_experts(consultation_id, provider_id, left_at);

-- 8. RPC: Mark expert as left the room
CREATE OR REPLACE FUNCTION public.mark_expert_left(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSONB AS $$
BEGIN
  UPDATE public.consultation_room_experts
  SET left_at = now()
  WHERE consultation_id = p_consultation_id
    AND provider_id = p_provider_id
    AND status = 'joined'
    AND left_at IS NULL;

  RETURN jsonb_build_object('success', true, 'message', 'Marked as left');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. RPC: Mark expert as re-entered the room
CREATE OR REPLACE FUNCTION public.mark_expert_reentered(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSONB AS $$
BEGIN
  UPDATE public.consultation_room_experts
  SET left_at = NULL
  WHERE consultation_id = p_consultation_id
    AND provider_id = p_provider_id
    AND status = 'joined';

  RETURN jsonb_build_object('success', true, 'message', 'Marked as re-entered');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. RPC: Revert expert finished status (ยกเลิกจบงาน)
CREATE OR REPLACE FUNCTION public.mark_expert_reverted(
  p_consultation_id UUID,
  p_provider_id UUID
)
RETURNS JSONB AS $$
BEGIN
  UPDATE public.consultation_room_experts
  SET finished_at = NULL
  WHERE consultation_id = p_consultation_id
    AND provider_id = p_provider_id
    AND finished_at IS NOT NULL;

  RETURN jsonb_build_object('success', true, 'message', 'Reverted finish status');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
