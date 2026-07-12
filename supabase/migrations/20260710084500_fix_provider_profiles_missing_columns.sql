-- Fix provider_profiles schema to match Flutter code expectations
-- Columns is_verified and verified_at are referenced by RegistrationRepository.approveApplication()

-- Add is_verified flag (defaults to false for existing rows)
ALTER TABLE public.provider_profiles
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT false;

-- Add verified_at timestamp
ALTER TABLE public.provider_profiles
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;

-- Reload PostgREST schema cache so Flutter sees the new columns
NOTIFY pgrst, 'reload schema';
