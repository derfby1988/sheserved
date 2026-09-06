-- Migration: Phase 13.1 — DB identity context, roles and RLS foundation
-- Date: 2026-09-05
-- Depends: 20260903110900_phase_13_0_fitness_public_views.sql
--
-- Decision Q7 = C: single helper that resolves identity from both
--   (a) gateway transaction context: current_setting('app.user_id')
--   (b) PostgREST JWT context: current_setting('request.jwt.claims') -> 'sub'
-- If both are present and differ -> UNAUTHORIZED (no COALESCE masking).
--
-- Decision Q12 = B: least-privilege role model
--   sheserved_app        NOLOGIN  permission role (no BYPASSRLS, no DDL)
--   sheserved_gateway    LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS
--                        server-only business connection role; SET LOCAL ROLE sheserved_app
--   sheserved_auth       NOLOGIN  auth helper role
--   sheserved_auth_gateway LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS
--                        auth connection role with minimal privileges
--   sheserved_worker     NOLOGIN  worker/audit role
--   sheserved_readonly   NOLOGIN  analytics/reporting role
--   sheserved_migrate    NOLOGIN  migration role (DDL capable, not used by app)
--   sheserved_fitness_owner NOLOGIN owner of secure Fitness RPCs

-- ===================================================================
-- 0. Schema
-- ===================================================================
CREATE SCHEMA IF NOT EXISTS app;

-- ===================================================================
-- 1. Roles (idempotent)
-- ===================================================================
DO $$
BEGIN
  -- Supabase standard roles (needed for REVOKE/GRANT expressions)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_app') THEN
    CREATE ROLE sheserved_app NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_gateway') THEN
    CREATE ROLE sheserved_gateway LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_auth') THEN
    CREATE ROLE sheserved_auth NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_auth_gateway') THEN
    CREATE ROLE sheserved_auth_gateway LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_worker') THEN
    CREATE ROLE sheserved_worker NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_readonly') THEN
    CREATE ROLE sheserved_readonly NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  -- Migration role: NOLOGIN, does not need CREATEROLE (migrations run as admin).
  -- In Supabase hosted Postgres, CREATEROLE is restricted to built-in roles.
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_migrate') THEN
    CREATE ROLE sheserved_migrate NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sheserved_fitness_owner') THEN
    CREATE ROLE sheserved_fitness_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
END
$$;

-- Role memberships: gateway inherits privileges of app at session time via SET LOCAL ROLE
GRANT sheserved_app TO sheserved_gateway;
GRANT sheserved_auth TO sheserved_auth_gateway;

-- worker/readonly are separate; do not grant app privileges

-- Allow the migration runner (role that created the roles) to transfer
-- object ownership to sheserved_fitness_owner.  This membership is needed
-- because ALTER ... OWNER TO requires membership in the target role.
GRANT sheserved_fitness_owner TO CURRENT_USER;

-- Allow the migration runner / postgres connection (Supavisor username postgres.<ref>)
-- to SET LOCAL ROLE sheserved_app / sheserved_auth during dry-run/spike and gateway setup.
-- This does NOT change the connecting user's login password; it only grants the right
-- to drop into the NOLOGIN permission role inside a transaction.
GRANT sheserved_app TO CURRENT_USER;
GRANT sheserved_auth TO CURRENT_USER;

-- ===================================================================
-- 2. Identity helper: app.current_user_id()
-- ===================================================================
-- Returns the verified user UUID from either gateway context or
-- PostgREST JWT claims.  If both are present and differ, raises
-- UNAUTHORIZED.  If nether is present, returns NULL.  Does NOT check
-- active status by default; use app.require_current_user_id() for that.

CREATE OR REPLACE FUNCTION app.current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_gateway_text TEXT;
  v_jwt_text TEXT;
  v_jwt_sub TEXT;
  v_gateway_id UUID;
  v_jwt_id UUID;
BEGIN
  -- Gateway path: backend transaction sets this before query/RPC
  v_gateway_text := current_setting('app.user_id', true);

  -- PostgREST path: short-lived token minted by Backend in Phase 13.2
  -- current_setting('request.jwt.claims') returns a JSON text in PostgREST
  v_jwt_text := current_setting('request.jwt.claims', true);

  -- Parse gateway UUID
  IF v_gateway_text IS NOT NULL AND btrim(v_gateway_text) <> '' THEN
    BEGIN
      v_gateway_id := v_gateway_text::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'UNAUTHORIZED';
    END;
  END IF;

  -- Parse JWT sub
  IF v_jwt_text IS NOT NULL AND btrim(v_jwt_text) <> '' THEN
    BEGIN
      v_jwt_sub := (v_jwt_text::JSONB) ->> 'sub';
      IF v_jwt_sub IS NOT NULL AND btrim(v_jwt_sub) <> '' THEN
        v_jwt_id := v_jwt_sub::UUID;
      END IF;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'UNAUTHORIZED';
    WHEN OTHERS THEN
      -- malformed JSON / missing sub
      v_jwt_id := NULL;
    END;
  END IF;

  -- Conflict detection: if both identity sources are present and differ,
  -- fail closed.  COALESCE must not be used to mask a conflict.
  IF v_gateway_id IS NOT NULL AND v_jwt_id IS NOT NULL AND v_gateway_id <> v_jwt_id THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN COALESCE(v_gateway_id, v_jwt_id);
END;
$$;

-- ===================================================================
-- 3. Active-user helper: app.is_active_user()
-- ===================================================================
CREATE OR REPLACE FUNCTION app.is_active_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p_user_id
      AND u.is_active = true
  );
END;
$$;

-- ===================================================================
-- 4. Update app.require_current_user_id() to use unified helper
-- ===================================================================
CREATE OR REPLACE FUNCTION app.require_current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := app.current_user_id();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  IF NOT app.is_active_user(v_user_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN v_user_id;
END;
$$;

-- ===================================================================
-- 5. Secure Fitness RPC ownership transfer and grants
-- ===================================================================
-- These RPCs were created in earlier migrations and REVOKEd from
-- PUBLIC/anon/authenticated, but are still owned by the admin role.
-- Transfer ownership to sheserved_fitness_owner so RLS/SECURITY DEFINER
-- semantics are scoped to a dedicated owner, then grant EXECUTE to
-- sheserved_app (the role gateway assumes after SET LOCAL ROLE).

DO $$
DECLARE
  v_fn RECORD;
  v_args TEXT;
BEGIN
  -- PostgreSQL rule: to ALTER ... OWNER TO, the NEW owner role must have
  -- CREATE privilege on the function's schema.  sheserved_fitness_owner has
  -- no privileges by design, so grant CREATE on schema public transiently,
  -- transfer ownership, then revoke it again (least privilege).
  BEGIN
    GRANT CREATE ON SCHEMA public TO sheserved_fitness_owner;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Cannot grant CREATE ON SCHEMA public TO sheserved_fitness_owner (not schema owner)';
  END;

  -- Functions to transfer.  If a function does not exist yet (e.g.
  -- migration not applied), the ownership statement is skipped.
  FOR v_fn IN
    SELECT p.oid, n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS identity_args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'is_fitness_group_manager',
        'set_fitness_group_owner_auto_join',
        'book_fitness_session',
        'approve_fitness_session_booking',
        'leave_fitness_group',
        'remove_fitness_session_participant'
      )
  LOOP
    v_args := COALESCE(v_fn.identity_args, '');
    BEGIN
      IF v_args = '' THEN
        EXECUTE format('ALTER FUNCTION public.%I() OWNER TO sheserved_fitness_owner', v_fn.proname);
      ELSE
        EXECUTE format('ALTER FUNCTION public.%I(%s) OWNER TO sheserved_fitness_owner', v_fn.proname, v_args);
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping ALTER FUNCTION public.% OWNER TO sheserved_fitness_owner (not owner)', v_fn.proname;
    END;
  END LOOP;

  -- Least privilege: the owner role must not retain CREATE on schema public.
  BEGIN
    REVOKE CREATE ON SCHEMA public FROM sheserved_fitness_owner;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE CREATE ON SCHEMA public FROM sheserved_fitness_owner (not schema owner)';
  END;
END
$$;

-- Grant USAGE on schemas to app roles.  Wrapped because Supavisor connection
-- may not be the owner of schema public (Supabase hosted owns it as supabase_admin).
DO $$
BEGIN
  BEGIN
    GRANT USAGE ON SCHEMA app TO sheserved_app, sheserved_auth, sheserved_worker, sheserved_readonly;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT USAGE ON SCHEMA app (not owner)';
  END;
  BEGIN
    GRANT USAGE ON SCHEMA public TO sheserved_app, sheserved_auth, sheserved_worker, sheserved_readonly;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT USAGE ON SCHEMA public (not owner)';
  END;
END
$$;

-- Defensive: revoke CREATE on public schema from PUBLIC and from app/auth/worker/readonly
-- roles so they cannot create new tables/functions.  Only sheserved_migrate and the
-- migration runner (admin) may create objects.  Supabase hosted Postgres grants
-- CREATE to PUBLIC by default; this tightens it for least-privilege.
-- Wrapped in DO block because Supavisor connection may not own schema public.
DO $$
BEGIN
  BEGIN
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE CREATE ON SCHEMA public FROM PUBLIC (not schema owner)';
  END;
  BEGIN
    REVOKE CREATE ON SCHEMA public FROM sheserved_app, sheserved_auth, sheserved_worker, sheserved_readonly, sheserved_fitness_owner;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE CREATE ON SCHEMA public FROM app roles (not schema owner)';
  END;
END
$$;

-- Helper grants (always applied; helper functions are created above).
-- Wrapped in DO block because Supavisor connection may not own functions
-- created by previous migrations (owned by supabase_admin).
DO $$
BEGIN
  BEGIN
    GRANT EXECUTE ON FUNCTION app.current_user_id() TO sheserved_app, sheserved_auth, sheserved_worker, sheserved_readonly;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT EXECUTE ON app.current_user_id() (not owner)';
  END;
  BEGIN
    GRANT EXECUTE ON FUNCTION app.require_current_user_id() TO sheserved_app, sheserved_auth, sheserved_worker;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT EXECUTE ON app.require_current_user_id() (not owner)';
  END;
  BEGIN
    GRANT EXECUTE ON FUNCTION app.is_active_user(UUID) TO sheserved_app, sheserved_auth, sheserved_worker, sheserved_readonly;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT EXECUTE ON app.is_active_user(UUID) (not owner)';
  END;
  BEGIN
    REVOKE ALL ON FUNCTION app.current_user_id() FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE ON app.current_user_id() (not owner)';
  END;
  BEGIN
    REVOKE ALL ON FUNCTION app.require_current_user_id() FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE ON app.require_current_user_id() (not owner)';
  END;
  BEGIN
    REVOKE ALL ON FUNCTION app.is_active_user(UUID) FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping REVOKE ON app.is_active_user(UUID) (not owner)';
  END;
END
$$;

-- Grant EXECUTE on secure RPCs to app role only (idempotent; functions may not exist yet).
-- Each GRANT/REVOKE wrapped in sub-block because Supavisor connection may not own
-- functions created by previous migrations (owned by supabase_admin).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'is_fitness_group_manager') THEN
    BEGIN
      GRANT EXECUTE ON FUNCTION public.is_fitness_group_manager(UUID) TO sheserved_app;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on public.is_fitness_group_manager (not owner)';
    END;
    BEGIN
      REVOKE ALL ON FUNCTION public.is_fitness_group_manager(UUID) FROM PUBLIC, anon, authenticated;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping REVOKE on public.is_fitness_group_manager (not owner)';
    END;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'set_fitness_group_owner_auto_join') THEN
    BEGIN
      GRANT EXECUTE ON FUNCTION public.set_fitness_group_owner_auto_join(UUID, UUID, BOOLEAN, BOOLEAN) TO sheserved_app;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on public.set_fitness_group_owner_auto_join (not owner)';
    END;
    BEGIN
      REVOKE ALL ON FUNCTION public.set_fitness_group_owner_auto_join(UUID, UUID, BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping REVOKE on public.set_fitness_group_owner_auto_join (not owner)';
    END;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'book_fitness_session') THEN
    BEGIN
      GRANT EXECUTE ON FUNCTION public.book_fitness_session(UUID, UUID) TO sheserved_app;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on public.book_fitness_session (not owner)';
    END;
    BEGIN
      REVOKE ALL ON FUNCTION public.book_fitness_session(UUID, UUID) FROM PUBLIC, anon, authenticated;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping REVOKE on public.book_fitness_session (not owner)';
    END;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'approve_fitness_session_booking') THEN
    BEGIN
      GRANT EXECUTE ON FUNCTION public.approve_fitness_session_booking(UUID, UUID) TO sheserved_app;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on public.approve_fitness_session_booking (not owner)';
    END;
    BEGIN
      REVOKE ALL ON FUNCTION public.approve_fitness_session_booking(UUID, UUID) FROM PUBLIC, anon, authenticated;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping REVOKE on public.approve_fitness_session_booking (not owner)';
    END;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'leave_fitness_group') THEN
    BEGIN
      GRANT EXECUTE ON FUNCTION public.leave_fitness_group(UUID, UUID) TO sheserved_app;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on public.leave_fitness_group (not owner)';
    END;
    BEGIN
      REVOKE ALL ON FUNCTION public.leave_fitness_group(UUID, UUID) FROM PUBLIC, anon, authenticated;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping REVOKE on public.leave_fitness_group (not owner)';
    END;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'remove_fitness_session_participant') THEN
    BEGIN
      GRANT EXECUTE ON FUNCTION public.remove_fitness_session_participant(UUID, UUID) TO sheserved_app;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on public.remove_fitness_session_participant (not owner)';
    END;
    BEGIN
      REVOKE ALL ON FUNCTION public.remove_fitness_session_participant(UUID, UUID) FROM PUBLIC, anon, authenticated;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping REVOKE on public.remove_fitness_session_participant (not owner)';
    END;
  END IF;
END
$$;

-- ===================================================================
-- 6. public.sessions auth-private
-- ===================================================================
-- Extend public.sessions for refresh-token registry if not already present.
-- Then lock down grants: only backend/worker roles can read/write.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'sessions'
  ) THEN
    BEGIN
      ALTER TABLE public.sessions
        ADD COLUMN IF NOT EXISTS family_id UUID,
        ADD COLUMN IF NOT EXISTS prev_token_hash TEXT,
        ADD COLUMN IF NOT EXISTS rotated_at TIMESTAMPTZ;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping ALTER TABLE public.sessions (not owner)';
    END;

    BEGIN
      CREATE INDEX IF NOT EXISTS idx_sessions_family_id ON public.sessions(family_id);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping CREATE INDEX idx_sessions_family_id (not owner)';
    END;
    BEGIN
      CREATE INDEX IF NOT EXISTS idx_sessions_rotated_at ON public.sessions(rotated_at);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping CREATE INDEX idx_sessions_rotated_at (not owner)';
    END;

    -- Table privileges: app/auth/worker only.  No SELECT/INSERT/UPDATE/DELETE
    -- for anon/authenticated; backend mints/verifies sessions directly.
    BEGIN
      REVOKE ALL ON public.sessions FROM PUBLIC, anon, authenticated;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping REVOKE ALL ON public.sessions (not owner)';
    END;
    BEGIN
      GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO sheserved_app, sheserved_auth, sheserved_worker;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT ON public.sessions (not owner)';
    END;

    -- Drop permissive policies that expose sessions to authenticated (legacy).
    BEGIN
      DROP POLICY IF EXISTS sessions_select ON public.sessions;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping DROP POLICY sessions_select (not owner)';
    END;
    BEGIN
      DROP POLICY IF EXISTS sessions_modify ON public.sessions;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping DROP POLICY sessions_modify (not owner)';
    END;

    -- Strict role-scoped policies: only backend app/auth/worker roles may access.
    BEGIN
      CREATE POLICY sessions_app_select ON public.sessions FOR SELECT TO sheserved_app, sheserved_auth, sheserved_worker USING (true);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping CREATE POLICY sessions_app_select (not owner)';
    END;
    BEGIN
      CREATE POLICY sessions_app_insert ON public.sessions FOR INSERT TO sheserved_app, sheserved_auth, sheserved_worker WITH CHECK (true);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping CREATE POLICY sessions_app_insert (not owner)';
    END;
    BEGIN
      CREATE POLICY sessions_app_update ON public.sessions FOR UPDATE TO sheserved_app, sheserved_auth, sheserved_worker USING (true) WITH CHECK (true);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping CREATE POLICY sessions_app_update (not owner)';
    END;
    BEGIN
      CREATE POLICY sessions_app_delete ON public.sessions FOR DELETE TO sheserved_app, sheserved_auth, sheserved_worker USING (true);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping CREATE POLICY sessions_app_delete (not owner)';
    END;
  END IF;
END
$$;

-- ===================================================================
-- 7. Grant base-table read privileges needed by app role during transition
-- ===================================================================
-- In Phase 13.5 strict RLS cutover, base-table SELECT for anon will be
-- revoked and replaced by public VIEW grants.  Until then, app role needs
-- SELECT on tables it will touch via gateway transactions.
DO $$
BEGIN
  BEGIN
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT SELECT ON ALL TABLES IN SCHEMA public TO sheserved_app (not owner)';
  END;
  BEGIN
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping ALTER DEFAULT PRIVILEGES for sheserved_app (not owner)';
  END;
END
$$;

-- worker can read all (for audit/jobs); do not grant write by default.
DO $$
BEGIN
  BEGIN
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO sheserved_worker, sheserved_readonly;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT SELECT ON ALL TABLES IN SCHEMA public TO worker/readonly (not owner)';
  END;
  BEGIN
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO sheserved_worker, sheserved_readonly;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping ALTER DEFAULT PRIVILEGES for worker/readonly (not owner)';
  END;
END
$$;

-- ===================================================================
-- 8. Notify PostgREST of schema change
-- ===================================================================
NOTIFY pgrst, 'reload schema';
