-- Triage System: Audit log tables for consent and health data access
-- migration: 20260809100300_create_victim_audit_tables.sql

CREATE TABLE IF NOT EXISTS victim_report_consent_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    victim_id       UUID NOT NULL REFERENCES incident_victims(id) ON DELETE CASCADE,
    reported_by     UUID NOT NULL REFERENCES users(id),
    consented       BOOLEAN NOT NULL DEFAULT TRUE,
    ip_address      INET,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_victim_consent_victim ON victim_report_consent_logs(victim_id, created_at DESC);
ALTER TABLE victim_report_consent_logs DISABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS victim_health_access_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    victim_id       UUID NOT NULL REFERENCES incident_victims(id) ON DELETE CASCADE,
    accessed_by     UUID NOT NULL REFERENCES users(id),
    session_id      UUID,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_victim_health_access_victim ON victim_health_access_logs(victim_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_victim_health_access_user   ON victim_health_access_logs(accessed_by, created_at DESC);
ALTER TABLE victim_health_access_logs DISABLE ROW LEVEL SECURITY;
