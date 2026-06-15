-- Normalize legacy consultation package expert-group roles to canonical profession IDs
-- This keeps package seed data, admin-edited packages, and existing room experts aligned.

CREATE OR REPLACE FUNCTION public.normalize_consultation_expert_group_role(
  p_role TEXT,
  p_name TEXT DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
  v_role TEXT := lower(trim(coalesce(p_role, '')));
  v_name TEXT := lower(trim(coalesce(p_name, '')));
BEGIN
  IF v_role = '' THEN
    RETURN '';
  END IF;

  -- Canonical built-in profession IDs
  IF v_role IN ('doctor', 'หมอ') OR v_name LIKE '%แพทย์ทั่วไป%' OR v_name LIKE '%general practitioner%' THEN
    RETURN '00000000-0000-0000-0000-000000000101';
  ELSIF v_role IN ('specialist', 'เฉพาะทาง') OR v_name LIKE '%แพทย์เฉพาะทาง%' OR v_name LIKE '%specialist physician%' THEN
    RETURN '00000000-0000-0000-0000-000000000103';
  ELSIF v_role IN ('pharmacist', 'เภสัช') OR v_name LIKE '%เภสัชกร%' OR v_name LIKE '%pharmacist%' THEN
    RETURN '00000000-0000-0000-0000-000000000105';
  END IF;

  -- Professor does not have a built-in stable profession ID in the current model.
  IF v_role IN ('professor', 'อาจารย์') OR v_name LIKE '%อาจารย์แพทย์%' THEN
    RETURN 'professor';
  END IF;

  RETURN coalesce(p_role, '');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Normalize expert_groups JSONB inside consultation_packages
UPDATE public.consultation_packages cp
SET expert_groups = normalized.new_expert_groups,
    updated_at = NOW()
FROM (
  SELECT
    cp_inner.id,
    COALESCE(
      jsonb_agg(
        jsonb_set(
          group_obj,
          '{role}',
          to_jsonb(public.normalize_consultation_expert_group_role(group_obj->>'role', group_obj->>'name')),
          true
        ) ORDER BY ord
      ),
      '[]'::jsonb
    ) AS new_expert_groups
  FROM public.consultation_packages cp_inner
  CROSS JOIN LATERAL jsonb_array_elements(COALESCE(cp_inner.expert_groups, '[]'::jsonb)) WITH ORDINALITY AS g(group_obj, ord)
  GROUP BY cp_inner.id
) AS normalized
WHERE cp.id = normalized.id
  AND cp.expert_groups IS DISTINCT FROM normalized.new_expert_groups;

-- Normalize already-created consultation_room_experts rows as well so existing rooms stay consistent.
UPDATE public.consultation_room_experts cre
SET expert_group_role = public.normalize_consultation_expert_group_role(cre.expert_group_role, cre.expert_group_name)
WHERE cre.expert_group_role IS NOT NULL
  AND cre.expert_group_role IS DISTINCT FROM public.normalize_consultation_expert_group_role(cre.expert_group_role, cre.expert_group_name);

DROP FUNCTION IF EXISTS public.normalize_consultation_expert_group_role(TEXT, TEXT);
