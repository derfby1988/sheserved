-- Triage System: Victim mutation DB functions (insert, dispute, edit, soft delete, helper)
-- migration: 20260809100500_create_victim_mutation_fns.sql

-- 1. insert_victim — called from POST /api/incidents/:id/victims
CREATE OR REPLACE FUNCTION insert_victim(
    p_incident_id UUID,
    p_prefix      VARCHAR(20),
    p_first_name  VARCHAR(100),
    p_last_name   VARCHAR(100),
    p_masked_name VARCHAR(120),
    p_reported_by UUID,
    p_consent     BOOLEAN
) RETURNS incident_victims AS $$
DECLARE
    v_limit   INT;
    v_count   INT;
    v_victim  incident_victims;
BEGIN
    SELECT (value->>'victimReportRateLimitPerIncident')::INT INTO v_limit
    FROM app_settings WHERE key = 'video_system_config';
    v_limit := COALESCE(v_limit, 0);

    IF v_limit > 0 THEN
        SELECT COUNT(*) INTO v_count
        FROM incident_victims
        WHERE incident_id = p_incident_id
          AND reported_by = p_reported_by
          AND is_deleted = FALSE;

        IF v_count >= v_limit THEN
            RAISE EXCEPTION 'VICTIM_REPORT_RATE_LIMIT_EXCEEDED';
        END IF;
    END IF;

    INSERT INTO incident_victims (
        incident_id, prefix, first_name, last_name, masked_name,
        reported_by, verify_status
    ) VALUES (
        p_incident_id, p_prefix, p_first_name, p_last_name, p_masked_name,
        p_reported_by, 'unverified'
    ) RETURNING * INTO v_victim;

    INSERT INTO victim_report_consent_logs (victim_id, reported_by, consented)
    VALUES (v_victim.id, p_reported_by, p_consent);

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;

-- 2. dispute_victim — called from POST /api/victims/:id/dispute
CREATE OR REPLACE FUNCTION dispute_victim(
    p_victim_id UUID,
    p_disputed_by UUID,
    p_reason TEXT
) RETURNS incident_victims AS $$
DECLARE
    v_victim incident_victims;
BEGIN
    SELECT * INTO v_victim FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    IF v_victim.verify_status = 'disputed' THEN
        RAISE EXCEPTION 'ALREADY_DISPUTED';
    END IF;

    IF p_reason IS NULL OR char_length(p_reason) < 10 THEN
        RAISE EXCEPTION 'DISPUTE_REASON_TOO_SHORT';
    END IF;

    UPDATE incident_victims SET
        verify_status   = 'disputed',
        disputed_by     = p_disputed_by,
        disputed_reason = p_reason,
        disputed_at     = NOW(),
        is_synced       = FALSE,
        updated_at      = NOW()
     WHERE id = p_victim_id
    RETURNING * INTO v_victim;

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;

-- 3. edit_victim_name — called from PATCH /api/victims/:id
CREATE OR REPLACE FUNCTION edit_victim_name(
    p_victim_id UUID,
    p_editor_id UUID,
    p_prefix     VARCHAR(20),
    p_first_name VARCHAR(100),
    p_last_name  VARCHAR(100),
    p_masked_name VARCHAR(120)
) RETURNS incident_victims AS $$
DECLARE
    v_victim incident_victims;
BEGIN
    SELECT * INTO v_victim FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    UPDATE incident_victims SET
        prefix        = p_prefix,
        first_name    = p_first_name,
        last_name     = p_last_name,
        masked_name   = p_masked_name,
        verify_status = 'confirmed',
        is_synced     = FALSE,
        updated_at    = NOW()
     WHERE id = p_victim_id
    RETURNING * INTO v_victim;

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;

-- 4. soft_delete_victim — called from DELETE /api/victims/:id
CREATE OR REPLACE FUNCTION soft_delete_victim(
    p_victim_id UUID,
    p_deleted_by UUID,
    p_reason TEXT
) RETURNS incident_victims AS $$
DECLARE
    v_victim incident_victims;
BEGIN
    SELECT * INTO v_victim FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    IF p_reason IS NULL OR char_length(p_reason) < 10 THEN
        RAISE EXCEPTION 'DELETE_REASON_TOO_SHORT';
    END IF;

    UPDATE incident_victims SET
        is_deleted     = TRUE,
        deleted_by     = p_deleted_by,
        deleted_at     = NOW(),
        deleted_reason = p_reason,
        is_synced      = FALSE,
        updated_at     = NOW()
     WHERE id = p_victim_id
    RETURNING * INTO v_victim;

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;

-- 5. Helper: check if user is a responder in an incident
CREATE OR REPLACE FUNCTION is_victim_responder(p_user_id UUID, p_incident_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM incident_responses
         WHERE video_id = p_incident_id
           AND volunteer_id = p_user_id
           AND status IN ('accepted','en_route','arrived')
    );
END;
$$ LANGUAGE plpgsql;
