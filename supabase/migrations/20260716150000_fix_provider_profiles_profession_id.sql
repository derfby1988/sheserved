-- Keep provider_profiles aligned with RegistrationRepository.approveApplication().
-- Some databases were created from an older provider_profiles definition without profession_id.

ALTER TABLE public.provider_profiles
ADD COLUMN IF NOT EXISTS profession_id UUID REFERENCES public.professions(id);

CREATE INDEX IF NOT EXISTS idx_provider_profiles_profession_id
  ON public.provider_profiles(profession_id);

NOTIFY pgrst, 'reload schema';
