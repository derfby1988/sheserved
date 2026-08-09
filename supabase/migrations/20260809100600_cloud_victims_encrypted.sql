-- Triage System: Cloud sync schema with pgcrypto encrypted name columns
-- migration: 20260809100600_cloud_victims_encrypted.sql

-- Ensure pgcrypto extension is available
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Cloud mirror table for victim data (encrypted PII)
CREATE TABLE IF NOT EXISTS cloud_incident_victims (
    id                UUID PRIMARY KEY,
    incident_id       UUID NOT NULL,
    prefix            VARCHAR(20) NOT NULL DEFAULT 'ไม่ระบุ',
    first_name_enc    BYTEA,
    last_name_enc     BYTEA,
    masked_name       VARCHAR(120) NOT NULL,
    triage_level      triage_level NOT NULL DEFAULT 'white',
    triaged_by        UUID,
    triaged_at        TIMESTAMPTZ,
    triage_note       TEXT,
    triaged_by_profession_id       UUID,
    triaged_by_profession_category VARCHAR(50),
    verify_status     victim_verify_status NOT NULL DEFAULT 'unverified',
    is_deleted        BOOLEAN NOT NULL DEFAULT FALSE,
    reported_by       UUID NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cloud_victims_incident ON cloud_incident_victims(incident_id);
CREATE INDEX IF NOT EXISTS idx_cloud_victims_triage  ON cloud_incident_victims(incident_id, triage_level);

ALTER TABLE cloud_incident_victims ENABLE ROW LEVEL SECURITY;

-- Policy: only service role can read/write (admin key bypasses RLS)
CREATE POLICY cloud_victims_service_all ON cloud_incident_victims
    FOR ALL USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Helper function to encrypt a name using pgcrypto
-- Key is passed as parameter from environment variable
CREATE OR REPLACE FUNCTION encrypt_victim_name(p_name TEXT, p_key TEXT)
RETURNS BYTEA AS $$
BEGIN
    IF p_name IS NULL OR p_key IS NULL THEN RETURN NULL; END IF;
    RETURN pgp_sym_encrypt(p_name, p_key);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to decrypt
CREATE OR REPLACE FUNCTION decrypt_victim_name(p_enc BYTEA, p_key TEXT)
RETURNS TEXT AS $$
BEGIN
    IF p_enc IS NULL OR p_key IS NULL THEN RETURN NULL; END IF;
    RETURN pgp_sym_decrypt(p_enc, p_key);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
