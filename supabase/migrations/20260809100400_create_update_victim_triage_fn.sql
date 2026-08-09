-- Triage System: Atomic triage update function with FOR UPDATE lock
-- migration: 20260809100400_create_update_victim_triage_fn.sql

CREATE OR REPLACE FUNCTION update_victim_triage(
    p_victim_id UUID, p_new_level triage_level,
    p_user_id UUID, p_note TEXT
) RETURNS incident_victims AS $$
DECLARE
    v_old        incident_victims;
    v_role       VARCHAR(100);
    v_prof_id    UUID;
    v_prof_cat   VARCHAR(50);
BEGIN
    SELECT * INTO v_old FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    SELECT p.name, p.id, p.category
      INTO v_role, v_prof_id, v_prof_cat
      FROM users u
      LEFT JOIN professions p ON p.id = u.profession_id
     WHERE u.id = p_user_id;

    IF p_new_level = 'deceased' THEN
        IF v_prof_cat IS NULL OR v_prof_cat <> 'provider' THEN
            RAISE EXCEPTION 'DECEASED_REQUIRES_PROVIDER_PROFESSION';
        END IF;
        IF COALESCE(p_note, '') = '' OR char_length(p_note) < 10 THEN
            RAISE EXCEPTION 'DECEASED_REASON_TOO_SHORT';
        END IF;
    END IF;

    UPDATE incident_victims SET
        triage_level                   = p_new_level,
        triaged_by                     = p_user_id,
        triaged_at                     = NOW(),
        triage_note                    = COALESCE(p_note, triage_note),
        triaged_by_profession_id       = v_prof_id,
        triaged_by_profession_category = v_prof_cat,
        verify_status                  = 'confirmed',
        is_synced                      = FALSE,
        updated_at                     = NOW(),
        deceased_confirmed_by          = CASE WHEN p_new_level = 'deceased' THEN p_user_id ELSE deceased_confirmed_by END,
        deceased_confirmed_at          = CASE WHEN p_new_level = 'deceased' THEN NOW()        ELSE deceased_confirmed_at END,
        deceased_reason                = CASE WHEN p_new_level = 'deceased' THEN p_note         ELSE deceased_reason END
     WHERE id = p_victim_id;

    INSERT INTO incident_victim_triage_logs
        (victim_id, incident_id, from_level, to_level, changed_by, changed_by_role,
         changed_by_profession_id, changed_by_profession_category, note)
    VALUES
        (p_victim_id, v_old.incident_id, v_old.triage_level, p_new_level, p_user_id, v_role,
         v_prof_id, v_prof_cat, p_note);

    RETURN (SELECT * FROM incident_victims WHERE id = p_victim_id);
END;
$$ LANGUAGE plpgsql;
