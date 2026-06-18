-- Fix RLS for profession_package_rules so package editor saves do not fail
-- The package editor currently writes through an unauthenticated/public client
-- path in this environment, so this table must allow the same public access
-- pattern as consultation_packages.

ALTER TABLE public.profession_package_rules ENABLE ROW LEVEL SECURITY;

-- Public read access for editor/reload flows.
DROP POLICY IF EXISTS "Public read profession_package_rules" ON public.profession_package_rules;
CREATE POLICY "Public read profession_package_rules"
ON public.profession_package_rules
FOR SELECT
TO public
USING (true);

-- Keep the service role policy for privileged backend jobs.
DROP POLICY IF EXISTS "Service role manage profession_package_rules" ON public.profession_package_rules;
CREATE POLICY "Service role manage profession_package_rules"
ON public.profession_package_rules
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Allow the app client to insert/update/delete rules during package editing.
DROP POLICY IF EXISTS "Manage profession_package_rules for all" ON public.profession_package_rules;
CREATE POLICY "Manage profession_package_rules for all"
ON public.profession_package_rules
FOR ALL
TO public
USING (true)
WITH CHECK (true);

-- Reload PostgREST schema cache so the new policy is visible immediately.
NOTIFY pgrst, 'reload schema';
