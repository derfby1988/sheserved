-- Triage System: Main table for incident victims
-- migration: 20260809100100_create_incident_victims.sql

DO $$ BEGIN
    CREATE TYPE triage_level AS ENUM ('deceased', 'critical', 'urgent', 'non_urgent', 'white');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE victim_verify_status AS ENUM ('unverified', 'confirmed', 'disputed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE incident_victims (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id       UUID NOT NULL,

    prefix            VARCHAR(20) NOT NULL DEFAULT 'ไม่ระบุ',
    first_name        VARCHAR(100),
    last_name         VARCHAR(100),
    masked_name       VARCHAR(120) NOT NULL,
    linked_user_id    UUID REFERENCES users(id) ON DELETE SET NULL,

    triage_level      triage_level NOT NULL DEFAULT 'white',
    triaged_by        UUID REFERENCES users(id) ON DELETE SET NULL,
    triaged_at        TIMESTAMPTZ,
    triage_note       TEXT,
    triaged_by_profession_id       UUID REFERENCES professions(id) ON DELETE SET NULL,
    triaged_by_profession_category VARCHAR(50),

    deceased_confirmed_by     UUID REFERENCES users(id) ON DELETE SET NULL,
    deceased_confirmed_at     TIMESTAMPTZ,
    deceased_reason           TEXT,

    verify_status     victim_verify_status NOT NULL DEFAULT 'unverified',
    disputed_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    disputed_reason   TEXT,
    disputed_at       TIMESTAMPTZ,

    reported_by       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_deleted        BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_by        UUID REFERENCES users(id) ON DELETE SET NULL,
    deleted_at        TIMESTAMPTZ,
    deleted_reason    TEXT,

    health_data_consent_verified BOOLEAN NOT NULL DEFAULT FALSE,
    health_data_unlocked_at      TIMESTAMPTZ,

    retention_countdown_started_at TIMESTAMPTZ,

    is_synced         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_victims_incident      ON incident_victims(incident_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_victims_triage        ON incident_victims(incident_id, triage_level) WHERE is_deleted = FALSE;
CREATE INDEX idx_victims_deceased      ON incident_victims(incident_id)
    WHERE is_deleted = FALSE AND triage_level = 'deceased';
CREATE INDEX idx_victims_sync          ON incident_victims(is_synced) WHERE is_synced = FALSE;
CREATE INDEX idx_victims_linked_user   ON incident_victims(linked_user_id) WHERE linked_user_id IS NOT NULL;
CREATE INDEX idx_victims_retention     ON incident_victims(retention_countdown_started_at)
    WHERE is_deleted = FALSE AND retention_countdown_started_at IS NOT NULL;

CREATE UNIQUE INDEX idx_victims_no_dup
    ON incident_victims(incident_id, lower(first_name), lower(last_name))
    WHERE is_deleted = FALSE AND first_name IS NOT NULL AND last_name IS NOT NULL;

ALTER TABLE incident_victims ADD CONSTRAINT chk_deceased_requires_confirmation
    CHECK (
        triage_level <> 'deceased'
        OR (deceased_confirmed_by IS NOT NULL
            AND deceased_confirmed_at IS NOT NULL
            AND char_length(coalesce(deceased_reason, '')) >= 10)
    );

ALTER TABLE incident_victims ADD CONSTRAINT chk_deceased_no_health_unlock
    CHECK (NOT (triage_level = 'deceased' AND health_data_consent_verified = TRUE));

ALTER TABLE incident_victims DISABLE ROW LEVEL SECURITY;
