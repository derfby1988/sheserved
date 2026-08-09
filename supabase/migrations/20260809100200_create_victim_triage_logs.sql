-- Triage System: History table for triage level changes
-- migration: 20260809100200_create_victim_triage_logs.sql

CREATE TABLE incident_victim_triage_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    victim_id      UUID NOT NULL REFERENCES incident_victims(id) ON DELETE CASCADE,
    incident_id    UUID NOT NULL,
    from_level     triage_level,
    to_level       triage_level NOT NULL,
    changed_by     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    changed_by_role VARCHAR(100),
    changed_by_profession_id       UUID REFERENCES professions(id) ON DELETE SET NULL,
    changed_by_profession_category VARCHAR(50),
    note           TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_triage_logs_victim ON incident_victim_triage_logs(victim_id, created_at DESC);
CREATE INDEX idx_triage_logs_deceased ON incident_victim_triage_logs(incident_id, created_at DESC)
    WHERE to_level = 'deceased';
ALTER TABLE incident_victim_triage_logs DISABLE ROW LEVEL SECURITY;
