-- Fix Drug Risk modifier resolution to match the actual users schema.
-- users has first_name/last_name/username/email, not users.name.
-- When both scopes are supplied, Personal Override has priority over Organization Override.

CREATE OR REPLACE FUNCTION public.resolve_effective_modifier(
    p_medication_id UUID,
    p_profession_id UUID DEFAULT NULL,
    p_user_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_override RECORD;
    v_modifier RECORD;
BEGIN
    SELECT dro.last_modified_by, dro.last_modified_at
    INTO v_override
    FROM public.drug_risk_overrides dro
    WHERE dro.medication_id = p_medication_id
      AND (
        (p_user_id IS NOT NULL AND dro.user_id = p_user_id)
        OR (p_profession_id IS NOT NULL AND dro.profession_id = p_profession_id)
      )
    ORDER BY CASE WHEN p_user_id IS NOT NULL AND dro.user_id = p_user_id THEN 1 ELSE 2 END
    LIMIT 1;

    IF v_override IS NULL THEN
        RETURN json_build_object(
            'name', 'Sheserved Default',
            'status', 'no_override'
        );
    END IF;

    IF v_override.last_modified_by IS NOT NULL THEN
        SELECT
            u.id,
            COALESCE(
                NULLIF(TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), ''),
                NULLIF(u.username, ''),
                NULLIF(u.email, ''),
                NULLIF(u.phone, ''),
                'ไม่ระบุชื่อ'
            ) AS display_name,
            u.is_active,
            p.can_manage_drug_risk
        INTO v_modifier
        FROM public.users u
        LEFT JOIN public.professions p ON p.id = u.profession_id
        WHERE u.id = v_override.last_modified_by;

        IF v_modifier IS NOT NULL
           AND v_modifier.is_active = true
           AND v_modifier.can_manage_drug_risk = true THEN
            RETURN json_build_object(
                'id', v_modifier.id,
                'name', v_modifier.display_name,
                'status', 'active',
                'modified_at', v_override.last_modified_at
            );
        END IF;
    END IF;

    SELECT
        h.changed_by,
        h.changed_by_name,
        u.id AS uid,
        COALESCE(
            NULLIF(TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), ''),
            NULLIF(u.username, ''),
            NULLIF(u.email, ''),
            NULLIF(u.phone, ''),
            'ไม่ระบุชื่อ'
        ) AS display_name,
        u.is_active,
        p.can_manage_drug_risk
    INTO v_modifier
    FROM public.drug_risk_override_history h
    JOIN public.users u ON u.id = h.changed_by
    LEFT JOIN public.professions p ON p.id = u.profession_id
    WHERE h.medication_id = p_medication_id
      AND (
        (p_user_id IS NOT NULL AND h.user_id = p_user_id)
        OR (p_profession_id IS NOT NULL AND h.profession_id = p_profession_id)
      )
      AND u.is_active = true
      AND p.can_manage_drug_risk = true
    ORDER BY h.changed_at DESC
    LIMIT 1;

    IF v_modifier IS NOT NULL THEN
        RETURN json_build_object(
            'id', v_modifier.uid,
            'name', v_modifier.display_name,
            'status', 'fallback_history',
            'snapshot_name', v_modifier.changed_by_name
        );
    END IF;

    RETURN json_build_object(
        'name', 'System Admin',
        'status', 'fallback_system'
    );
END;
$$;
