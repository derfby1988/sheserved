DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename = 'provider_profiles'
  ) THEN
    ALTER TABLE public.provider_profiles ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "provider_profiles_select" ON public.provider_profiles;
    DROP POLICY IF EXISTS "provider_profiles_modify" ON public.provider_profiles;

    CREATE POLICY "provider_profiles_select"
      ON public.provider_profiles
      FOR SELECT
      USING (true);

    CREATE POLICY "provider_profiles_modify"
      ON public.provider_profiles
      FOR ALL
      USING (true)
      WITH CHECK (true);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename = 'provider_credentials'
  ) THEN
    ALTER TABLE public.provider_credentials ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "provider_credentials_select" ON public.provider_credentials;
    DROP POLICY IF EXISTS "provider_credentials_modify" ON public.provider_credentials;

    CREATE POLICY "provider_credentials_select"
      ON public.provider_credentials
      FOR SELECT
      USING (true);

    CREATE POLICY "provider_credentials_modify"
      ON public.provider_credentials
      FOR ALL
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
