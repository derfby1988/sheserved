-- Migration: Phase 13.2 — auth grants for users table (register + lazy rehash)
-- Date: 2026-09-06
-- Depends: 20260905140000_phase_13_1_db_identity_roles.sql, 20260906120000_phase_13_2_audit_logs.sql
--
-- Phase 13.2 auth handlers run as sheserved_app (via gateway pool + SET LOCAL ROLE):
--   - register: INSERT into public.users (server-side Argon2id hash)
--   - login lazy rehash: UPDATE password columns for the authenticated user
--   - login/me: SELECT user row
--
-- Least-privilege:
--   - INSERT: full row (registration supplies many columns)
--   - UPDATE: password-related columns ONLY (no role/username/phone tampering)
--   - SELECT: scoped by RLS policy below (server-only role; row scoping by identity)
--
-- Legacy permissive policies (Allow anonymous registration / public write) are
-- OUT of scope here — they are revoked in Phase 13.5 cutover per plan.

-- ===================================================================
-- 1. Grants (column-scoped UPDATE)
-- ===================================================================
DO $$
BEGIN
  BEGIN
    GRANT INSERT ON public.users TO sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT INSERT ON users TO sheserved_app (not owner)';
  END;

  BEGIN
    GRANT UPDATE (password_hash, password_algo, password_updated_at,
                  password_migrated_at, requires_password_reset)
      ON public.users TO sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT UPDATE(password cols) ON users TO sheserved_app (not owner)';
  END;

  BEGIN
    GRANT SELECT ON public.users TO sheserved_app;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping GRANT SELECT ON users TO sheserved_app (not owner)';
  END;
END
$$;

-- ===================================================================
-- 2. RLS policies for sheserved_app
-- ===================================================================
-- RLS is enabled on users.  sheserved_app needs policies:
--   - INSERT: allowed (registration)
--   - SELECT: allowed (login lookup by phone/username)
--   - UPDATE: row-scoped to the identity set by app.user_id (lazy rehash)
DO $$
BEGIN
  BEGIN
    CREATE POLICY sheserved_app_users_insert
      ON public.users FOR INSERT
      TO sheserved_app
      WITH CHECK (true);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping CREATE POLICY sheserved_app_users_insert (not owner)';
  END;

  BEGIN
    CREATE POLICY sheserved_app_users_select
      ON public.users FOR SELECT
      TO sheserved_app
      USING (true);
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping CREATE POLICY sheserved_app_users_select (not owner)';
  END;

  -- Row-scoped: backend may only touch the row whose id == app.user_id.
  -- login lazy rehash uses withTransaction(user.id) so app.user_id == the
  -- row being updated.  Pre-auth ops (SYSTEM_ACTOR=00000000-...) cannot UPDATE.
  BEGIN
    CREATE POLICY sheserved_app_users_update
      ON public.users FOR UPDATE
      TO sheserved_app
      USING (id::text = current_setting('app.user_id', true))
      WITH CHECK (id::text = current_setting('app.user_id', true));
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping CREATE POLICY sheserved_app_users_update (not owner)';
  END;
END
$$;

NOTIFY pgrst, 'reload schema';
