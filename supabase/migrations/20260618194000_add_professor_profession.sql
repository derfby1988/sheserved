-- Migration: Add professor profession as a real UUID-backed built-in profession
-- This fixes profession_package_rules inserts for expert groups whose UI role is "professor".

ALTER TABLE public.professions
  ADD COLUMN IF NOT EXISTS profession_code TEXT;

ALTER TABLE public.professions
  ADD COLUMN IF NOT EXISTS requires_sheserved_approval BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_prescribe_medication BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_dispense_medication BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_manage_drug_risk BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS requires_telemedicine_license BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS approval_required_license_types TEXT[] DEFAULT '{}';

INSERT INTO public.professions (
  id,
  profession_code,
  name,
  name_en,
  description,
  icon_name,
  category,
  is_built_in,
  is_active,
  requires_verification,
  requires_sheserved_approval,
  can_prescribe_medication,
  can_dispense_medication,
  can_manage_drug_risk,
  requires_telemedicine_license,
  approval_required_license_types,
  display_order,
  created_at,
  updated_at
) VALUES (
  '00000000-0000-0000-0000-000000000107',
  'professor',
  'อาจารย์แพทย์',
  'Professor Physician',
  'แพทย์อาวุโส/อาจารย์แพทย์สำหรับการปรึกษาและให้คำแนะนำ',
  'workspace_premium',
  'provider',
  true,
  true,
  true,
  true,
  true,
  false,
  true,
  true,
  ARRAY['medical_council', 'telemedicine'],
  9,
  NOW(),
  NOW()
)
ON CONFLICT (name) DO UPDATE SET
  profession_code = EXCLUDED.profession_code,
  name_en = EXCLUDED.name_en,
  description = EXCLUDED.description,
  icon_name = EXCLUDED.icon_name,
  category = EXCLUDED.category,
  is_built_in = EXCLUDED.is_built_in,
  is_active = EXCLUDED.is_active,
  requires_verification = EXCLUDED.requires_verification,
  requires_sheserved_approval = EXCLUDED.requires_sheserved_approval,
  can_prescribe_medication = EXCLUDED.can_prescribe_medication,
  can_dispense_medication = EXCLUDED.can_dispense_medication,
  can_manage_drug_risk = EXCLUDED.can_manage_drug_risk,
  requires_telemedicine_license = EXCLUDED.requires_telemedicine_license,
  approval_required_license_types = EXCLUDED.approval_required_license_types,
  display_order = EXCLUDED.display_order,
  updated_at = NOW();
