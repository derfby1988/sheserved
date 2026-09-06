-- Staging / Shadow script: Phase 13.1 — Strict Fitness RLS policies
-- Date: 2026-09-05
-- Depends: 20260905140000_phase_13_1_db_identity_roles.sql
--
-- ⚠️  DO NOT RUN IN PRODUCTION until Phase 13.5 cutover.
-- This script is meant for staging/canary shadow testing only.
-- Apply manually in a staging environment, never through the default
-- Supabase CLI migration path, because it revokes permissive table
-- access that the current Flutter client still relies on.
--
-- Principles:
--   * Public browse remains through public VIEWs only (Phase 13.0).
--   * Private read goes through PostgREST token with role 'authenticated'
--     and identity helper app.current_user_id().
--   * Mutation goes through Backend gateway with SET LOCAL ROLE sheserved_app
--     and SET LOCAL app.user_id, then secure RPCs.
--   * service_role / sheserved_worker are exempt for sync/audit jobs.
--
-- Requires roles created by 20260905140000_phase_13_1_db_identity_roles.sql:
--   sheserved_app, sheserved_worker, sheserved_fitness_owner.

-- ===================================================================
-- 0. Reusable helper: current actor is manager of a group
-- ===================================================================
CREATE OR REPLACE FUNCTION public.fitness_group_manager_check(p_group_id UUID)
RETURNS BOOLEAN
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
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.fitness_groups g
    WHERE g.id = p_group_id
      AND (
        g.created_by = v_user_id
        OR EXISTS (
          SELECT 1 FROM public.users u WHERE u.id = v_user_id AND u.role = 'admin'
        )
        OR EXISTS (
          SELECT 1
          FROM public.fitness_group_members m
          WHERE m.group_id = p_group_id
            AND m.user_id = v_user_id
            AND m.role = 'admin'
            AND m.is_active = true
        )
      )
  );
END;
$$;

-- ===================================================================
-- 1. sports
-- ===================================================================
DROP POLICY IF EXISTS sports_select_public ON public.sports;
DROP POLICY IF EXISTS sports_modify_all ON public.sports;

CREATE POLICY sports_select_public ON public.sports
  FOR SELECT TO authenticated
  USING (status = 'approved');

-- Admin-only mutation; sheserved_app/worker can mutate for sync.
CREATE POLICY sports_admin_modify ON public.sports
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = app.current_user_id() AND u.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = app.current_user_id() AND u.role = 'admin'
    )
  );

GRANT SELECT ON public.sports TO sheserved_app, sheserved_worker;

-- ===================================================================
-- 2. fitness_groups
-- ===================================================================
DROP POLICY IF EXISTS fitness_groups_modify_all ON public.fitness_groups;
DROP POLICY IF EXISTS fitness_groups_select_all ON public.fitness_groups;

-- authenticated users can view public groups and private groups they are members of.
CREATE POLICY fitness_groups_select ON public.fitness_groups
  FOR SELECT TO authenticated
  USING (
    visibility = 'public'
    OR created_by = app.current_user_id()
    OR EXISTS (
      SELECT 1 FROM public.fitness_group_members m
      WHERE m.group_id = id
        AND m.user_id = app.current_user_id()
        AND m.is_active = true
    )
  );

-- Authenticated users can create groups; created_by is forced to actor by trigger/DB default.
CREATE POLICY fitness_groups_insert ON public.fitness_groups
  FOR INSERT TO authenticated
  WITH CHECK (app.current_user_id() IS NOT NULL);

-- Only owner/group admin/Sheserved admin can update/delete.
CREATE POLICY fitness_groups_manager_modify ON public.fitness_groups
  FOR ALL TO authenticated
  USING (public.fitness_group_manager_check(id))
  WITH CHECK (public.fitness_group_manager_check(id));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fitness_groups TO sheserved_app;

-- ===================================================================
-- 3. fitness_group_sessions
-- ===================================================================
DROP POLICY IF EXISTS fitness_group_sessions_modify_all ON public.fitness_group_sessions;
DROP POLICY IF EXISTS fitness_group_sessions_select_all ON public.fitness_group_sessions;

-- Members of the group can view sessions; public groups allow any authenticated user.
CREATE POLICY fitness_group_sessions_select ON public.fitness_group_sessions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.fitness_groups g
      WHERE g.id = group_id
        AND (
          g.visibility = 'public'
          OR g.created_by = app.current_user_id()
          OR EXISTS (
            SELECT 1 FROM public.fitness_group_members m
            WHERE m.group_id = g.id
              AND m.user_id = app.current_user_id()
              AND m.is_active = true
          )
        )
    )
  );

-- Manager can create/update/delete sessions.
CREATE POLICY fitness_group_sessions_manager_modify ON public.fitness_group_sessions
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.fitness_groups g
      WHERE g.id = group_id
        AND public.fitness_group_manager_check(g.id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.fitness_groups g
      WHERE g.id = group_id
        AND public.fitness_group_manager_check(g.id)
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fitness_group_sessions TO sheserved_app;

-- ===================================================================
-- 4. fitness_group_members
-- ===================================================================
DROP POLICY IF EXISTS fitness_group_members_modify_all ON public.fitness_group_members;
DROP POLICY IF EXISTS fitness_group_members_select_all ON public.fitness_group_members;

-- Members can see other members of groups they belong to.
-- Manager can see all members of managed groups.
CREATE POLICY fitness_group_members_select ON public.fitness_group_members
  FOR SELECT TO authenticated
  USING (
    user_id = app.current_user_id()
    OR EXISTS (
      SELECT 1 FROM public.fitness_group_members m
      WHERE m.group_id = fitness_group_members.group_id
        AND m.user_id = app.current_user_id()
        AND m.is_active = true
    )
    OR public.fitness_group_manager_check(group_id)
  );

-- Manager can insert/update/delete members.
CREATE POLICY fitness_group_members_manager_modify ON public.fitness_group_members
  FOR ALL TO authenticated
  USING (public.fitness_group_manager_check(group_id))
  WITH CHECK (public.fitness_group_manager_check(group_id));

-- Users can remove themselves (leave group) via the app layer, which calls secure RPC.
CREATE POLICY fitness_group_members_self_deactivate ON public.fitness_group_members
  FOR UPDATE TO authenticated
  USING (user_id = app.current_user_id())
  WITH CHECK (user_id = app.current_user_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fitness_group_members TO sheserved_app;

-- ===================================================================
-- 5. fitness_group_bookings
-- ===================================================================
DROP POLICY IF EXISTS fitness_group_bookings_modify_all ON public.fitness_group_bookings;
DROP POLICY IF EXISTS fitness_group_bookings_select_all ON public.fitness_group_bookings;

-- Users can see their own bookings.
-- Manager can see all bookings in groups they manage.
-- Members can see bookings for sessions in their groups (no PII beyond user_id, which is needed for coordination).
CREATE POLICY fitness_group_bookings_select ON public.fitness_group_bookings
  FOR SELECT TO authenticated
  USING (
    user_id = app.current_user_id()
    OR public.fitness_group_manager_check(
      (SELECT group_id FROM public.fitness_group_sessions s WHERE s.id = session_id)
    )
    OR EXISTS (
      SELECT 1 FROM public.fitness_group_members m
      JOIN public.fitness_group_sessions s ON s.group_id = m.group_id
      WHERE s.id = session_id
        AND m.user_id = app.current_user_id()
        AND m.is_active = true
    )
  );

-- Authenticated user can insert a booking for themselves only.
CREATE POLICY fitness_group_bookings_insert_self ON public.fitness_group_bookings
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = app.current_user_id()
    AND EXISTS (
      SELECT 1 FROM public.fitness_group_sessions s
      JOIN public.fitness_groups g ON g.id = s.group_id
      WHERE s.id = session_id
        AND (
          g.visibility = 'public'
          OR EXISTS (
            SELECT 1 FROM public.fitness_group_members m
            WHERE m.group_id = g.id
              AND m.user_id = app.current_user_id()
              AND m.is_active = true
          )
        )
    )
  );

-- Manager can update/delete bookings for sessions in their groups.
CREATE POLICY fitness_group_bookings_manager_modify ON public.fitness_group_bookings
  FOR ALL TO authenticated
  USING (
    public.fitness_group_manager_check(
      (SELECT group_id FROM public.fitness_group_sessions s WHERE s.id = session_id)
    )
  )
  WITH CHECK (
    public.fitness_group_manager_check(
      (SELECT group_id FROM public.fitness_group_sessions s WHERE s.id = session_id)
    )
  );

-- Users can cancel their own pending bookings.
CREATE POLICY fitness_group_bookings_self_cancel ON public.fitness_group_bookings
  FOR UPDATE TO authenticated
  USING (
    user_id = app.current_user_id()
    AND status IN ('pending','confirmed')
  )
  WITH CHECK (
    user_id = app.current_user_id()
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fitness_group_bookings TO sheserved_app;

-- ===================================================================
-- 6. fitness_group_blocklist
-- ===================================================================
DROP POLICY IF EXISTS fitness_group_blocklist_modify_all ON public.fitness_group_blocklist;
DROP POLICY IF EXISTS fitness_group_blocklist_select_all ON public.fitness_group_blocklist;

-- Manager can view/modify blocklist.
-- Blocked users can see their own block entries.
CREATE POLICY fitness_group_blocklist_select ON public.fitness_group_blocklist
  FOR SELECT TO authenticated
  USING (
    blocked_user_id = app.current_user_id()
    OR public.fitness_group_manager_check(group_id)
  );

CREATE POLICY fitness_group_blocklist_manager_modify ON public.fitness_group_blocklist
  FOR ALL TO authenticated
  USING (public.fitness_group_manager_check(group_id))
  WITH CHECK (public.fitness_group_manager_check(group_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fitness_group_blocklist TO sheserved_app;

-- ===================================================================
-- 7. chat_rooms (fitness_group rooms)
-- ===================================================================
-- Note: full chat_rooms RLS is part of Phase 13.6 chat wave.
-- This section only scopes fitness_group rooms tied to managed groups.
DROP POLICY IF EXISTS chat_rooms_modify_all ON public.chat_rooms;

CREATE POLICY chat_rooms_fitness_select ON public.chat_rooms
  FOR SELECT TO authenticated
  USING (
    room_type <> 'fitness_group'
    OR room_ref_id IS NULL
    OR EXISTS (
      SELECT 1 FROM public.fitness_group_members m
      WHERE m.group_id = room_ref_id
        AND m.user_id = app.current_user_id()
        AND m.is_active = true
    )
    OR public.fitness_group_manager_check(room_ref_id)
  );

GRANT SELECT ON public.chat_rooms TO sheserved_app;

-- ===================================================================
-- 8. Deny/allow matrix summary (intended grants after 13.5)
-- ===================================================================
-- Role            | public VIEWs | base table SELECT | base table write | RPC EXECUTE
-- ----------------|--------------|-------------------|------------------|---------------
-- anon            | SELECT       | none              | none             | none (legacy revoked)
-- authenticated   | SELECT       | RLS-restricted    | none             | none (legacy revoked)
-- sheserved_app   | all          | all               | all (via RLS)    | secure RPCs
-- sheserved_worker| all          | all               | none by default  | audit/jobs
-- service_role    | all          | all               | all              | bypass (only migration/worker)
--
-- service_role must not be used by HTTP/Socket request handlers.

NOTIFY pgrst, 'reload schema';
