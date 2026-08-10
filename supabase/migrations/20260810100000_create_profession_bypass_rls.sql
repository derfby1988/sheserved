-- Create RPC function for inserting professions bypassing RLS
-- This mirrors the existing update_profession_bypass_rls pattern
-- Needed because Supabase RLS policies for professions were tightened
-- and direct client inserts are now blocked even for authenticated users

CREATE OR REPLACE FUNCTION public.create_profession_bypass_rls(
  p_data JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result_row JSONB;
BEGIN
  INSERT INTO public.professions (
    profession_code,
    name,
    name_en,
    description,
    icon_name,
    category,
    color_hex,
    is_built_in,
    is_active,
    is_volunteer,
    requires_verification,
    requires_sheserved_approval,
    can_prescribe_medication,
    can_dispense_medication,
    can_manage_drug_risk,
    requires_telemedicine_license,
    approval_required_license_types,
    display_order,
    created_at,
    updated_at
  ) VALUES (
    p_data->>'profession_code',
    p_data->>'name',
    NULLIF(p_data->>'name_en', ''),
    NULLIF(p_data->>'description', ''),
    p_data->>'icon_name',
    p_data->>'category',
    p_data->>'color_hex',
    COALESCE((p_data->>'is_built_in')::boolean, false),
    COALESCE((p_data->>'is_active')::boolean, true),
    COALESCE((p_data->>'is_volunteer')::boolean, false),
    COALESCE((p_data->>'requires_verification')::boolean, true),
    COALESCE((p_data->>'requires_sheserved_approval')::boolean, false),
    COALESCE((p_data->>'can_prescribe_medication')::boolean, false),
    COALESCE((p_data->>'can_dispense_medication')::boolean, false),
    COALESCE((p_data->>'can_manage_drug_risk')::boolean, false),
    COALESCE((p_data->>'requires_telemedicine_license')::boolean, false),
    COALESCE(
      (SELECT ARRAY_AGG(value::text)
       FROM jsonb_array_elements_text(COALESCE(p_data->'approval_required_license_types', '[]'::jsonb)) AS value
      ),
      ARRAY[]::text[]
    ),
    COALESCE((p_data->>'display_order')::integer, 0),
    COALESCE((p_data->>'created_at')::timestamptz, NOW()),
    COALESCE((p_data->>'updated_at')::timestamptz, NOW())
  )
  RETURNING to_jsonb(professions.*) INTO result_row;

  RETURN result_row;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.create_profession_bypass_rls(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_profession_bypass_rls(JSONB) TO service_role;
