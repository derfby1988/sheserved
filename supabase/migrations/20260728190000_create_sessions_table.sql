-- ============================================================
-- Migration: Create sessions table for Plan 08 Option B
-- (Opaque Session Token + Redis + Durable Postgres Backup)
-- Date: 2026-07-28
-- Description: Durable session storage with audit trail for
--              HIS/LAB compliance. Redis is the fast path;
--              this table is the fallback + audit source.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL,                          -- SHA-256(token), never store raw token
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    ip_address      INET,
    device_info     JSONB,                                  -- { platform, device_name, app_version }
    revoked_at      TIMESTAMPTZ,
    revoked_by      TEXT,                                   -- 'user', 'admin', 'system', 'password_change'
    revoke_reason   TEXT
);

-- Index for looking up active sessions by user (revoke-all-devices, concurrent session check)
CREATE INDEX IF NOT EXISTS idx_sessions_user_id
    ON public.sessions(user_id)
    WHERE revoked_at IS NULL;

-- Index for token hash lookup (verifyToken fallback when Redis is down)
CREATE INDEX IF NOT EXISTS idx_sessions_token_hash
    ON public.sessions(token_hash);

-- Index for cron cleanup of expired sessions
CREATE INDEX IF NOT EXISTS idx_sessions_expires
    ON public.sessions(expires_at)
    WHERE revoked_at IS NULL;

-- Enable RLS (using true pattern — app-layer control, consistent with K2 audit)
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'sessions'
      AND policyname = 'sessions_select'
  ) THEN
    CREATE POLICY sessions_select ON public.sessions
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'sessions'
      AND policyname = 'sessions_modify'
  ) THEN
    CREATE POLICY sessions_modify ON public.sessions
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;
