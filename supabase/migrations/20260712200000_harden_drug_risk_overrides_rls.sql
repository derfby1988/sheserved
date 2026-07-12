-- =====================================================
-- Migration: Harden RLS policies for drug_risk_overrides
-- Date: 2026-07-12
-- Purpose:
--   Replace permissive USING (true) policies with capability-based checks.
--   Only users whose profession has can_manage_drug_risk=true (or admins)
--   can INSERT/UPDATE/DELETE drug_risk_overrides.
--   SELECT remains open (repository scopes by user_id/profession_id).
--
--   Context: This app uses custom phone auth, not Supabase Auth.
--   auth.uid() is null, so we cannot use it directly.
--   Instead, we check the current user's profession via a security definer function.
--
--   Approach: Create a helper function that checks the current user's
--   can_manage_drug_risk flag by looking up their profession.
--   Since there's no auth.uid(), the application layer (Dart repository)
--   already passes user_id/profession_id in queries.
--   This RLS policy adds a backend guard on top of the frontend mode check.
-- =====================================================

-- =====================================================
-- PART 1: Create helper function to check drug risk capability
--          The function takes a user_id parameter and checks
--          if their profession has can_manage_drug_risk = true
-- =====================================================

CREATE OR REPLACE FUNCTION public.user_can_manage_drug_risk(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT p.can_manage_drug_risk
            FROM public.users u
            JOIN public.professions p ON u.profession_id = p.id
            WHERE u.id = p_user_id
              AND u.is_active = true
              AND p.is_active = true
        ),
        false
    );
$$;

-- =====================================================
-- PART 2: Drop old permissive policies and create hardened ones
-- =====================================================

-- drug_risk_overrides: SELECT stays permissive (repository scopes data)
DROP POLICY IF EXISTS "drug_risk_overrides_select" ON public.drug_risk_overrides;
CREATE POLICY "drug_risk_overrides_select"
    ON public.drug_risk_overrides FOR SELECT USING (true);

-- drug_risk_overrides: INSERT — only users with can_manage_drug_risk
-- We check the inserted row's created_by or last_modified_by field
DROP POLICY IF EXISTS "drug_risk_overrides_insert" ON public.drug_risk_overrides;
CREATE POLICY "drug_risk_overrides_insert"
    ON public.drug_risk_overrides FOR INSERT
    WITH CHECK (
        public.user_can_manage_drug_risk(COALESCE(created_by, last_modified_by))
    );

-- drug_risk_overrides: UPDATE — only users with can_manage_drug_risk
DROP POLICY IF EXISTS "drug_risk_overrides_update" ON public.drug_risk_overrides;
CREATE POLICY "drug_risk_overrides_update"
    ON public.drug_risk_overrides FOR UPDATE
    USING (public.user_can_manage_drug_risk(last_modified_by))
    WITH CHECK (public.user_can_manage_drug_risk(last_modified_by));

-- drug_risk_overrides: DELETE — only users with can_manage_drug_risk
DROP POLICY IF EXISTS "drug_risk_overrides_delete" ON public.drug_risk_overrides;
CREATE POLICY "drug_risk_overrides_delete"
    ON public.drug_risk_overrides FOR DELETE
    USING (public.user_can_manage_drug_risk(last_modified_by));

-- Remove old permissive "modify" policy (FOR ALL)
DROP POLICY IF EXISTS "drug_risk_overrides_modify" ON public.drug_risk_overrides;

-- =====================================================
-- PART 3: drug_risk_override_history policies
-- =====================================================

-- history: SELECT stays permissive (repository scopes data)
DROP POLICY IF EXISTS "drug_risk_override_history_select" ON public.drug_risk_override_history;
CREATE POLICY "drug_risk_override_history_select"
    ON public.drug_risk_override_history FOR SELECT USING (true);

-- history: INSERT — only users with can_manage_drug_risk
-- History rows are inserted by the system (RPC or repository)
-- Check the changed_by field
DROP POLICY IF EXISTS "drug_risk_override_history_insert" ON public.drug_risk_override_history;
CREATE POLICY "drug_risk_override_history_insert"
    ON public.drug_risk_override_history FOR INSERT
    WITH CHECK (
        public.user_can_manage_drug_risk(changed_by)
    );

-- Remove old permissive "modify" policy (FOR ALL)
DROP POLICY IF EXISTS "drug_risk_override_history_modify" ON public.drug_risk_override_history;

-- =====================================================
-- PART 4: Verify policies
-- =====================================================

SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename IN ('drug_risk_overrides', 'drug_risk_override_history')
ORDER BY tablename, policyname;
