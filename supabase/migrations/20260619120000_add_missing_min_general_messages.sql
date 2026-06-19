-- Fix: profession_package_rules table missing min_general_messages column
-- This causes get_profession_package_rules and get_expert_completion_status to fail

-- 1. Add missing column
ALTER TABLE public.profession_package_rules
ADD COLUMN IF NOT EXISTS min_general_messages INT DEFAULT 0;

-- 2. Recreate get_profession_package_rules to ensure proper validation
DROP FUNCTION IF EXISTS public.get_profession_package_rules(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.get_profession_package_rules(
  p_package_id TEXT,
  p_profession_id UUID
)
RETURNS TABLE (
  id UUID,
  package_id TEXT,
  profession_id UUID,
  can_prescribe BOOLEAN,
  must_prescribe BOOLEAN,
  requires_prescription_approval BOOLEAN,
  min_prescription_items INT,
  can_set_required_questions BOOLEAN,
  min_required_questions INT,
  must_answer_all_questions BOOLEAN,
  requires_video_call BOOLEAN,
  requires_health_assessment BOOLEAN,
  min_general_messages INT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ppr.id,
    ppr.package_id,
    ppr.profession_id,
    ppr.can_prescribe,
    ppr.must_prescribe,
    ppr.requires_prescription_approval,
    ppr.min_prescription_items,
    ppr.can_set_required_questions,
    ppr.min_required_questions,
    ppr.must_answer_all_questions,
    ppr.requires_video_call,
    ppr.requires_health_assessment,
    ppr.min_general_messages,
    ppr.created_at,
    ppr.updated_at
  FROM public.profession_package_rules ppr
  WHERE ppr.package_id = p_package_id AND ppr.profession_id = p_profession_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

NOTIFY pgrst, 'reload schema';
