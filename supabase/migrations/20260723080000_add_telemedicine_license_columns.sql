DO $$
BEGIN
  -- Add is_telemedicine_licensed column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'provider_profiles'
      AND column_name = 'is_telemedicine_licensed'
  ) THEN
    ALTER TABLE public.provider_profiles
      ADD COLUMN is_telemedicine_licensed BOOLEAN DEFAULT false;
  END IF;

  -- Add license_type column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'provider_profiles'
      AND column_name = 'license_type'
  ) THEN
    ALTER TABLE public.provider_profiles
      ADD COLUMN license_type TEXT;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
