-- Migration for emergency health data auto-release system (Phase 1a)
-- Creates settings/sessions/tokens/logs + RLS + realtime

-- ============================================================
-- TABLE 1: emergency_health_data_settings
-- ============================================================
CREATE TABLE IF NOT EXISTS emergency_health_data_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT false,
    release_delay_minutes INT NOT NULL DEFAULT 5 CHECK (release_delay_minutes BETWEEN 1 AND 120),
    enabled_fields JSONB NOT NULL DEFAULT '["blood_type","allergies","emergency_contact"]',
    require_active_responder BOOLEAN DEFAULT true,
    require_medical_profession BOOLEAN DEFAULT false,
    require_verified BOOLEAN DEFAULT false,
    emergency_fallback BOOLEAN DEFAULT false,
    whitelisted_user_ids UUID[] DEFAULT '{}',
    consent_given_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id)
);

ALTER TABLE emergency_health_data_settings ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_data_settings'
          AND policyname = 'Emergency settings owner'
    ) THEN
        CREATE POLICY "Emergency settings owner" ON emergency_health_data_settings
            USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;
END$$;

-- ============================================================
-- TABLE 2: emergency_health_release_sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS emergency_health_release_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    release_delay_minutes INT NOT NULL DEFAULT 5,
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    panic_cancelled_at TIMESTAMPTZ,
    auto_released_at TIMESTAMPTZ,
    released_fields JSONB,
    status VARCHAR(20) NOT NULL DEFAULT 'counting'
        CHECK (status IN ('counting','cancelled','released','expired')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE emergency_health_release_sessions ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_release_sessions'
          AND policyname = 'Emergency session patient select'
    ) THEN
        CREATE POLICY "Emergency session patient select" ON emergency_health_release_sessions
            FOR SELECT USING (auth.uid() = patient_id);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_release_sessions'
          AND policyname = 'Emergency session patient cancel'
    ) THEN
        CREATE POLICY "Emergency session patient cancel" ON emergency_health_release_sessions
            FOR UPDATE USING (auth.uid() = patient_id);
    END IF;
END$$;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_rel pr
        JOIN pg_publication p ON p.oid = pr.prpubid
        WHERE p.pubname = 'supabase_realtime'
          AND pr.prrelid = 'emergency_health_release_sessions'::regclass
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE emergency_health_release_sessions;
    END IF;
END$$;

-- ============================================================
-- TABLE 3: emergency_health_access_tokens
-- ============================================================
CREATE TABLE IF NOT EXISTS emergency_health_access_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES emergency_health_release_sessions(id) ON DELETE CASCADE,
    responder_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    incident_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (session_id, responder_id)
);

ALTER TABLE emergency_health_access_tokens ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'emergency_health_access_tokens'
          AND policyname = 'Responder token select'
    ) THEN
        CREATE POLICY "Responder token select" ON emergency_health_access_tokens
            FOR SELECT USING (auth.uid() = responder_id);
    END IF;
END$$;
-- INSERT / revoke handled by service_role

-- ============================================================
-- TABLE 4: health_data_access_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS health_data_access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id UUID REFERENCES videos(id) ON DELETE SET NULL,
    patient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    accessor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    accessor_profession_id UUID REFERENCES professions(id) ON DELETE SET NULL,
    accessed_fields JSONB NOT NULL DEFAULT '{}',
    access_method VARCHAR(40) NOT NULL
        CHECK (access_method IN ('map_dialog','emergency_card','auto_release','consultation_request')),
    token_id UUID REFERENCES emergency_health_access_tokens(id) ON DELETE SET NULL,
    location_lat DECIMAL(10,8),
    location_lng DECIMAL(11,8),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE health_data_access_logs ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'health_data_access_logs'
          AND policyname = 'Patient audit select'
    ) THEN
        CREATE POLICY "Patient audit select" ON health_data_access_logs
            FOR SELECT USING (auth.uid() = patient_id);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'health_data_access_logs'
          AND policyname = 'Accessor audit select'
    ) THEN
        CREATE POLICY "Accessor audit select" ON health_data_access_logs
            FOR SELECT USING (auth.uid() = accessor_id);
    END IF;
END$$;
-- INSERT only via service_role, no UPDATE/DELETE permitted

-- ============================================================
-- Indexes for performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_eh_settings_user ON emergency_health_data_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_eh_sessions_patient ON emergency_health_release_sessions(patient_id);
CREATE INDEX IF NOT EXISTS idx_eh_sessions_status ON emergency_health_release_sessions(status);
CREATE INDEX IF NOT EXISTS idx_eh_sessions_incident ON emergency_health_release_sessions(incident_id);
CREATE INDEX IF NOT EXISTS idx_eh_tokens_responder ON emergency_health_access_tokens(responder_id);
CREATE INDEX IF NOT EXISTS idx_eh_tokens_session ON emergency_health_access_tokens(session_id);
CREATE INDEX IF NOT EXISTS idx_hd_logs_patient ON health_data_access_logs(patient_id);
CREATE INDEX IF NOT EXISTS idx_hd_logs_accessor ON health_data_access_logs(accessor_id);
CREATE INDEX IF NOT EXISTS idx_hd_logs_incident ON health_data_access_logs(incident_id);
