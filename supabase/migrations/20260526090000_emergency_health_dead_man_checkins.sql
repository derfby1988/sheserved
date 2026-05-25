-- Phase 4: Dead Man's Switch check-in tracking
-- Stores user-configurable intervals, reminders, and the last time a release session was triggered.

CREATE TABLE IF NOT EXISTS emergency_health_dead_man_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT false,
    check_in_interval_minutes INT NOT NULL DEFAULT 720 CHECK (check_in_interval_minutes BETWEEN 60 AND 1440),
    last_check_in_at TIMESTAMPTZ,
    last_triggered_at TIMESTAMPTZ,
    last_reminder_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id)
);

ALTER TABLE emergency_health_dead_man_checkins ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Dead man owner" ON emergency_health_dead_man_checkins
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_eh_dead_man_user ON emergency_health_dead_man_checkins(user_id);
CREATE INDEX IF NOT EXISTS idx_eh_dead_man_enabled ON emergency_health_dead_man_checkins(is_enabled);
