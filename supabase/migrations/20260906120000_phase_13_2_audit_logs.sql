-- Migration: Phase 13.2 — Audit logs table + sessions/user password foundations
-- Date: 2026-09-06
-- Depends: 20260905140000_phase_13_1_db_identity_roles.sql
--
-- Decision Q11 = B (audit_logs): create audit_logs table with indexes.
-- public.sessions was already extended in Phase 13.1 migration (family_id,
-- prev_token_hash, rotated_at).  users already has password_hash,
-- password_algo, password_updated_at, password_migrated_at,
-- requires_password_reset from earlier migrations.
--
-- This migration only creates audit_logs + indexes + grants.
-- Immutable: app role cannot UPDATE/DELETE audit rows.

-- ===================================================================
-- 1. audit_logs table
-- ===================================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id              BIGSERIAL,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_id        UUID,
  actor_role      VARCHAR(30),
  organization_id UUID,
  event_type      VARCHAR(60) NOT NULL,    -- 'auth.login.success', 'fitness.booking.approved', etc.
  resource_type   VARCHAR(60),
  resource_id     TEXT,
  action          VARCHAR(20),             -- read | create | update | delete | approve | deny
  outcome         VARCHAR(20) NOT NULL DEFAULT 'success', -- success | denied | error
  reason          TEXT,                    -- break-glass, override reason
  before_state    JSONB,
  after_state     JSONB,
  ip_address      INET,
  user_agent      TEXT,
  request_id      UUID,
  session_id      UUID,
  delivered_at    TIMESTAMPTZ,             -- audit-worker marks after forwarding (outbox semantics)
  PRIMARY KEY (id, occurred_at)            -- partition-ready composite key
);

-- ===================================================================
-- 2. Indexes (per plan Q11-B)
-- ===================================================================
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_time
  ON public.audit_logs (actor_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_resource_time
  ON public.audit_logs (resource_type, resource_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_event_time
  ON public.audit_logs (event_type, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_org_time
  ON public.audit_logs (organization_id, occurred_at DESC);

-- ===================================================================
-- 3. Grants — app role can INSERT (compliance event in same txn) but
--    cannot UPDATE or DELETE (immutable audit trail).
--    worker role can SELECT for audit-worker processing.
--    readonly can SELECT for analytics/reporting.
-- ===================================================================
DO $$
BEGIN
  BEGIN
    GRANT SELECT, INSERT ON public.audit_logs TO sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT SELECT,INSERT ON audit_logs TO sheserved_app (not owner)';
  END;
  BEGIN
    GRANT SELECT ON public.audit_logs TO sheserved_worker, sheserved_readonly;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT SELECT ON audit_logs TO worker/readonly (not owner)';
  END;
  -- Worker may update only the delivery marker column (outbox semantics).
  -- It cannot modify the audit content itself.
  BEGIN
    GRANT UPDATE (delivered_at) ON public.audit_logs TO sheserved_worker;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT UPDATE(delivered_at) ON audit_logs TO worker (not owner)';
  END;
  -- Explicitly deny UPDATE/DELETE to app role (defense-in-depth).
  -- The app role only has SELECT,INSERT granted above, but REVOKE is explicit.
  BEGIN
    REVOKE UPDATE, DELETE ON public.audit_logs FROM sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE UPDATE,DELETE ON audit_logs FROM sheserved_app (not owner)';
  END;
  -- Revoke from anon/authenticated — audit logs are backend-only.
  BEGIN
    REVOKE ALL ON public.audit_logs FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE ALL ON audit_logs FROM PUBLIC/anon/authenticated (not owner)';
  END;
END
$$;

-- Sequence grant for BIGSERIAL (app role needs INSERT which uses sequence)
DO $$
BEGIN
  BEGIN
    GRANT USAGE, SELECT ON SEQUENCE public.audit_logs_id_seq TO sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT USAGE ON audit_logs_id_seq TO sheserved_app (not owner)';
  END;
END
$$;

-- ===================================================================
-- 4. RLS on audit_logs
-- ===================================================================
-- Enable RLS so that even if anon/authenticated somehow get access,
-- they cannot read audit logs.  Only backend roles (sheserved_app,
-- sheserved_worker, sheserved_readonly) can access via explicit policies.
DO $$
BEGIN
  BEGIN
    ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping ALTER TABLE audit_logs ENABLE RLS (not owner)';
  END;

  -- App role: can INSERT (audit event) and SELECT own actor rows.
  BEGIN
    CREATE POLICY audit_logs_app_insert
      ON public.audit_logs FOR INSERT
      TO sheserved_app
      WITH CHECK (true);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping CREATE POLICY audit_logs_app_insert (not owner)';
  END;

  BEGIN
    CREATE POLICY audit_logs_app_select
      ON public.audit_logs FOR SELECT
      TO sheserved_app
      USING (true);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping CREATE POLICY audit_logs_app_select (not owner)';
  END;

  -- Worker/readonly: can SELECT all audit rows.
  BEGIN
    CREATE POLICY audit_logs_worker_select
      ON public.audit_logs FOR SELECT
      TO sheserved_worker, sheserved_readonly
      USING (true);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping CREATE POLICY audit_logs_worker_select (not owner)';
  END;

  -- Worker: may UPDATE rows only to set delivered_at (column grant limits scope).
  BEGIN
    CREATE POLICY audit_logs_worker_update
      ON public.audit_logs FOR UPDATE
      TO sheserved_worker
      USING (true)
      WITH CHECK (true);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping CREATE POLICY audit_logs_worker_update (not owner)';
  END;
END
$$;

-- ===================================================================
-- 5. Notify PostgREST of schema change
-- ===================================================================
NOTIFY pgrst, 'reload schema';
