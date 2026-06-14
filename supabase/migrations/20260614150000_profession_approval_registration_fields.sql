-- ============================================================
-- Migration: Profession Approval, Evidence Upload & Registration Fields
-- Date: 2026-06-14 15:00:00
-- Goal:
--   - Add approval/capability flags to professions
--   - Add immutable field_key + attachment metadata to registration_field_configs
--   - Add provider identity / credential tables for Telemedicine checks
--   - Add evidence attachment table for registration flow
--   - Seed canonical professions + default field configs
--   - Keep existing registration flow backward compatible
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1) PROFILES / PERMISSION FIELDS ON professions
-- ============================================================
ALTER TABLE public.professions
  ADD COLUMN IF NOT EXISTS profession_code TEXT,
  ADD COLUMN IF NOT EXISTS requires_sheserved_approval BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_prescribe_medication BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_dispense_medication BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_manage_drug_risk BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS requires_telemedicine_license BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS approval_required_license_types TEXT[] DEFAULT '{}';

CREATE UNIQUE INDEX IF NOT EXISTS idx_professions_profession_code_unique
  ON public.professions(profession_code)
  WHERE profession_code IS NOT NULL;

-- Backfill canonical codes for built-in professions
UPDATE public.professions
SET profession_code = CASE id
  WHEN '00000000-0000-0000-0000-000000000001' THEN 'consumer'
  WHEN '00000000-0000-0000-0000-000000000002' THEN 'expert'
  WHEN '00000000-0000-0000-0000-000000000003' THEN 'clinic'
  WHEN '00000000-0000-0000-0000-000000000101' THEN 'doctor_gp'
  WHEN '00000000-0000-0000-0000-000000000102' THEN 'doctor_family'
  WHEN '00000000-0000-0000-0000-000000000103' THEN 'doctor_specialist'
  WHEN '00000000-0000-0000-0000-000000000104' THEN 'dentist'
  WHEN '00000000-0000-0000-0000-000000000105' THEN 'pharmacist'
  WHEN '00000000-0000-0000-0000-000000000106' THEN 'telemedicine_provider'
  ELSE profession_code
END
WHERE profession_code IS NULL OR profession_code = '';

-- Seed / refresh canonical profession capability matrix
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
) VALUES
  (
    '00000000-0000-0000-0000-000000000001',
    'consumer',
    'ผู้ซื้อ/ผู้รับบริการ',
    'Consumer',
    'ผู้ใช้ทั่วไปที่ต้องการซื้อสินค้าหรือรับบริการ',
    'shopping_cart',
    'consumer',
    true,
    true,
    false,
    false,
    false,
    false,
    false,
    false,
    '{}'::text[],
    0,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'expert',
    'ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า',
    'Expert/Seller',
    'ผู้เชี่ยวชาญ ผู้ขายสินค้า หรือเจ้าของร้านค้า',
    'store',
    'provider',
    true,
    true,
    true,
    true,
    false,
    false,
    true,
    false,
    ARRAY['business_registration'],
    1,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000003',
    'clinic',
    'คลินิก/ศูนย์',
    'Clinic/Center',
    'คลินิก ศูนย์บริการ หรือสถานประกอบการ',
    'local_hospital',
    'provider',
    true,
    true,
    true,
    true,
    false,
    true,
    true,
    false,
    ARRAY['clinic_license'],
    2,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000101',
    'doctor_gp',
    'แพทย์ทั่วไป',
    'General Practitioner / Family Physician',
    'แพทย์ที่สามารถตรวจ วินิจฉัย และสั่งจ่ายยาตามขอบเขตวิชาชีพ',
    'medical_services',
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
    10,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    'doctor_family',
    'แพทย์เวชปฏิบัติครอบครัว',
    'Family Physician',
    'แพทย์เวชปฏิบัติครอบครัวสำหรับการดูแลแบบปฐมภูมิ',
    'family_restroom',
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
    11,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'doctor_specialist',
    'แพทย์เฉพาะทาง',
    'Specialist Physician',
    'แพทย์เฉพาะทางที่มีขอบเขตการรักษาเฉพาะสาขา',
    'psychology',
    'provider',
    true,
    true,
    true,
    true,
    true,
    false,
    true,
    true,
    ARRAY['medical_council', 'specialist_license', 'telemedicine'],
    12,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000104',
    'dentist',
    'ทันตแพทย์',
    'Dentist',
    'ผู้ประกอบวิชาชีพทันตกรรม',
    'mood',
    'provider',
    true,
    true,
    true,
    true,
    true,
    false,
    true,
    true,
    ARRAY['dental_council', 'telemedicine'],
    13,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000105',
    'pharmacist',
    'เภสัชกร',
    'Pharmacist',
    'ผู้ประกอบวิชาชีพเภสัชกรรมสำหรับจ่ายยาและให้คำแนะนำ',
    'local_pharmacy',
    'provider',
    true,
    true,
    true,
    true,
    true,
    false,
    true,
    false,
    ARRAY['pharmacy_council'],
    14,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000106',
    'telemedicine_provider',
    'ผู้ให้บริการ Telemedicine',
    'Telemedicine Provider',
    'ผู้ให้บริการที่ผ่านการตรวจสอบสิทธิ์สำหรับการให้บริการทางไกล',
    'video_call',
    'provider',
    true,
    true,
    true,
    true,
    true,
    true,
    true,
    true,
    ARRAY['telemedicine'],
    15,
    NOW(),
    NOW()
  )
ON CONFLICT (id) DO UPDATE SET
  profession_code = EXCLUDED.profession_code,
  name = EXCLUDED.name,
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

-- ============================================================
-- 2) REGISTRATION FIELD CONFIGS EXTENSION
-- ============================================================
ALTER TABLE public.registration_field_configs
  ADD COLUMN IF NOT EXISTS field_key TEXT,
  ADD COLUMN IF NOT EXISTS is_locked BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS requires_attachment BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS attachment_group_key TEXT,
  ADD COLUMN IF NOT EXISTS attachment_required_when_filled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS visible_when_profession_code TEXT[] DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_registration_field_configs_field_key
  ON public.registration_field_configs(field_key);

CREATE UNIQUE INDEX IF NOT EXISTS idx_registration_field_configs_profession_field_key
  ON public.registration_field_configs(profession_id, field_key)
  WHERE field_key IS NOT NULL;

-- Backfill existing records to keep current flow stable
UPDATE public.registration_field_configs
SET field_key = COALESCE(field_key, field_id),
    is_locked = COALESCE(is_locked, false),
    requires_attachment = COALESCE(requires_attachment, false),
    attachment_required_when_filled = COALESCE(attachment_required_when_filled, false),
    visible_when_profession_code = COALESCE(visible_when_profession_code, '{}'::text[])
WHERE true;

-- Lock canonical seed fields so first-created keys stay immutable
UPDATE public.registration_field_configs
SET is_locked = true,
    field_key = COALESCE(field_key, field_id)
WHERE profession_id IN (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000103',
  '00000000-0000-0000-0000-000000000104',
  '00000000-0000-0000-0000-000000000105',
  '00000000-0000-0000-0000-000000000106'
);

-- ============================================================
-- 3) PROVIDER IDENTITY / CREDENTIAL TABLES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.provider_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  profession_id UUID REFERENCES public.professions(id),
  profession_code TEXT,
  display_name TEXT,
  verification_status TEXT NOT NULL DEFAULT 'pending',
  identity_verified_at TIMESTAMPTZ,
  telemedicine_license_no TEXT,
  telemedicine_license_status TEXT NOT NULL DEFAULT 'unverified',
  telemedicine_license_verified_at TIMESTAMPTZ,
  telemedicine_license_expires_at TIMESTAMPTZ,
  license_authority TEXT,
  practice_scope_json JSONB DEFAULT '{}'::jsonb,
  is_telemedicine_licensed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_provider_profiles_profession_id
  ON public.provider_profiles(profession_id);
CREATE INDEX IF NOT EXISTS idx_provider_profiles_profession_code
  ON public.provider_profiles(profession_code);
CREATE INDEX IF NOT EXISTS idx_provider_profiles_license_status
  ON public.provider_profiles(telemedicine_license_status);

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_provider_profiles_updated_at ON public.provider_profiles;
CREATE TRIGGER trg_provider_profiles_updated_at
  BEFORE UPDATE ON public.provider_profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.provider_credentials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  profession_id UUID REFERENCES public.professions(id),
  credential_type TEXT NOT NULL,
  credential_number TEXT,
  issuing_authority TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  issued_at DATE,
  expires_at DATE,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES public.users(id),
  document_url TEXT,
  metadata_json JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_provider_credentials_user_id
  ON public.provider_credentials(user_id);
CREATE INDEX IF NOT EXISTS idx_provider_credentials_profession_id
  ON public.provider_credentials(profession_id);
CREATE INDEX IF NOT EXISTS idx_provider_credentials_type
  ON public.provider_credentials(credential_type);
CREATE INDEX IF NOT EXISTS idx_provider_credentials_status
  ON public.provider_credentials(status);

DROP TRIGGER IF EXISTS trg_provider_credentials_updated_at ON public.provider_credentials;
CREATE TRIGGER trg_provider_credentials_updated_at
  BEFORE UPDATE ON public.provider_credentials
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 4) REGISTRATION APPLICATION ATTACHMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.registration_application_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES public.registration_applications(id) ON DELETE CASCADE,
  field_key TEXT NOT NULL,
  attachment_type TEXT NOT NULL,
  file_url TEXT NOT NULL,
  mime_type TEXT,
  file_size_bytes BIGINT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_registration_application_attachments_application_id
  ON public.registration_application_attachments(application_id);
CREATE INDEX IF NOT EXISTS idx_registration_application_attachments_field_key
  ON public.registration_application_attachments(field_key);

-- ============================================================
-- 5) STORAGE BUCKET FOR EVIDENCE IMAGES
-- ============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'registration_evidence',
  'registration_evidence',
  true,
  10485760,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Registration evidence public read" ON storage.objects;
DROP POLICY IF EXISTS "Registration evidence anon upload" ON storage.objects;
DROP POLICY IF EXISTS "Registration evidence anon update" ON storage.objects;
DROP POLICY IF EXISTS "Registration evidence anon delete" ON storage.objects;

CREATE POLICY "Registration evidence public read" ON storage.objects
  FOR SELECT USING (bucket_id = 'registration_evidence');

CREATE POLICY "Registration evidence anon upload" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'registration_evidence');

CREATE POLICY "Registration evidence anon update" ON storage.objects
  FOR UPDATE USING (bucket_id = 'registration_evidence');

CREATE POLICY "Registration evidence anon delete" ON storage.objects
  FOR DELETE USING (bucket_id = 'registration_evidence');

-- ============================================================
-- 6) DEFAULT FIELD CONFIGS FOR LICENSE-BEARING PROFESSIONS
-- ============================================================
-- Existing built-ins: make keys explicit and locked so the first created key never changes.
UPDATE public.registration_field_configs
SET
  field_key = COALESCE(field_key, field_id),
  is_locked = true
WHERE profession_id = '00000000-0000-0000-0000-000000000001'
  AND field_id IN ('email', 'phone', 'birthday');

UPDATE public.registration_field_configs
SET
  field_key = COALESCE(field_key, field_id),
  is_locked = true,
  requires_attachment = CASE WHEN field_id = 'id_card_image' THEN true ELSE requires_attachment END,
  attachment_group_key = CASE WHEN field_id = 'id_card_image' THEN 'identity' ELSE attachment_group_key END,
  attachment_required_when_filled = CASE WHEN field_id = 'id_card_image' THEN true ELSE attachment_required_when_filled END
WHERE profession_id = '00000000-0000-0000-0000-000000000002'
  AND field_id IN ('profile_image', 'business_name', 'specialty', 'business_phone', 'business_email', 'business_address', 'experience', 'id_card_image', 'description');

UPDATE public.registration_field_configs
SET
  field_key = COALESCE(field_key, field_id),
  is_locked = true,
  requires_attachment = CASE WHEN field_id = 'license_number' THEN true ELSE requires_attachment END,
  attachment_group_key = CASE WHEN field_id = 'license_number' THEN 'clinic_license' ELSE attachment_group_key END,
  attachment_required_when_filled = CASE WHEN field_id = 'license_number' THEN true ELSE attachment_required_when_filled END
WHERE profession_id = '00000000-0000-0000-0000-000000000003'
  AND field_id IN ('business_image', 'clinic_name', 'license_number', 'service_type', 'business_phone', 'business_email', 'business_address', 'license_image', 'id_card_image', 'description');

-- Doctor GP
INSERT INTO public.registration_field_configs (
  profession_id,
  field_id,
  field_key,
  label,
  hint,
  field_type,
  is_required,
  is_locked,
  requires_attachment,
  attachment_group_key,
  attachment_required_when_filled,
  visible_when_profession_code,
  field_order,
  icon_name,
  is_active,
  created_at,
  updated_at
) VALUES
  (
    '00000000-0000-0000-0000-000000000101',
    'profile_image',
    'profile_image',
    'รูปโปรไฟล์',
    'อัปโหลดรูปโปรไฟล์',
    'image',
    true,
    true,
    false,
    NULL,
    false,
    ARRAY['doctor_gp'],
    0,
    'person',
    true,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000101',
    'medical_council_number',
    'medical_council_number',
    'เลขที่ใบประกอบวิชาชีพเวชกรรม',
    'กรอกเลขที่ใบอนุญาตแพทยสภา',
    'text',
    true,
    true,
    true,
    'medical_council',
    true,
    ARRAY['doctor_gp', 'doctor_family', 'doctor_specialist', 'telemedicine_provider'],
    1,
    'verified_outlined',
    true,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000101',
    'medical_council_image',
    'medical_council_image',
    'รูปใบประกอบวิชาชีพเวชกรรม',
    'อัปโหลดภาพใบประกอบวิชาชีพเวชกรรม',
    'image',
    true,
    true,
    false,
    'medical_council',
    false,
    ARRAY['doctor_gp', 'doctor_family', 'doctor_specialist'],
    2,
    'image_outlined',
    true,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000101',
    'telemedicine_license_number',
    'telemedicine_license_number',
    'เลขใบอนุญาต Telemedicine',
    'กรอกเลขใบอนุญาต Telemedicine',
    'text',
    true,
    true,
    true,
    'telemedicine_license',
    true,
    ARRAY['doctor_gp', 'doctor_family', 'doctor_specialist', 'dentist', 'telemedicine_provider'],
    3,
    'smart_display_outlined',
    true,
    NOW(),
    NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000101',
    'telemedicine_license_image',
    'telemedicine_license_image',
    'รูปใบอนุญาต Telemedicine',
    'อัปโหลดรูปใบอนุญาต Telemedicine',
    'image',
    true,
    true,
    false,
    'telemedicine_license',
    false,
    ARRAY['doctor_gp', 'doctor_family', 'doctor_specialist', 'dentist', 'telemedicine_provider'],
    4,
    'document_scanner',
    true,
    NOW(),
    NOW()
  )
ON CONFLICT (profession_id, field_id) DO UPDATE SET
  field_key = EXCLUDED.field_key,
  label = EXCLUDED.label,
  hint = EXCLUDED.hint,
  field_type = EXCLUDED.field_type,
  is_required = EXCLUDED.is_required,
  is_locked = EXCLUDED.is_locked,
  requires_attachment = EXCLUDED.requires_attachment,
  attachment_group_key = EXCLUDED.attachment_group_key,
  attachment_required_when_filled = EXCLUDED.attachment_required_when_filled,
  visible_when_profession_code = EXCLUDED.visible_when_profession_code,
  field_order = EXCLUDED.field_order,
  icon_name = EXCLUDED.icon_name,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- Doctor Family / Specialist / Dentist / Pharmacist / Telemedicine Provider
INSERT INTO public.registration_field_configs (
  profession_id,
  field_id,
  field_key,
  label,
  hint,
  field_type,
  is_required,
  is_locked,
  requires_attachment,
  attachment_group_key,
  attachment_required_when_filled,
  visible_when_profession_code,
  field_order,
  icon_name,
  is_active,
  created_at,
  updated_at
) VALUES
  (
    '00000000-0000-0000-0000-000000000102',
    'profile_image', 'profile_image', 'รูปโปรไฟล์', 'อัปโหลดรูปโปรไฟล์', 'image', true, true, false, NULL, false, ARRAY['doctor_family'], 0, 'person', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    'medical_council_number', 'medical_council_number', 'เลขที่ใบประกอบวิชาชีพเวชกรรม', 'กรอกเลขที่ใบอนุญาตแพทยสภา', 'text', true, true, true, 'medical_council', true, ARRAY['doctor_family'], 1, 'verified_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    'medical_council_image', 'medical_council_image', 'รูปใบประกอบวิชาชีพเวชกรรม', 'อัปโหลดภาพใบประกอบวิชาชีพเวชกรรม', 'image', true, true, false, 'medical_council', false, ARRAY['doctor_family'], 2, 'image_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    'telemedicine_license_number', 'telemedicine_license_number', 'เลขใบอนุญาต Telemedicine', 'กรอกเลขใบอนุญาต Telemedicine', 'text', true, true, true, 'telemedicine_license', true, ARRAY['doctor_family'], 3, 'smart_display_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000102',
    'telemedicine_license_image', 'telemedicine_license_image', 'รูปใบอนุญาต Telemedicine', 'อัปโหลดรูปใบอนุญาต Telemedicine', 'image', true, true, false, 'telemedicine_license', false, ARRAY['doctor_family'], 4, 'document_scanner', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'profile_image', 'profile_image', 'รูปโปรไฟล์', 'อัปโหลดรูปโปรไฟล์', 'image', true, true, false, NULL, false, ARRAY['doctor_specialist'], 0, 'person', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'specialty', 'specialty', 'สาขาเฉพาะทาง', 'กรอกสาขาเฉพาะทาง', 'text', true, true, false, NULL, false, ARRAY['doctor_specialist'], 1, 'psychology', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'medical_council_number', 'medical_council_number', 'เลขที่ใบประกอบวิชาชีพเวชกรรม', 'กรอกเลขที่ใบอนุญาตแพทยสภา', 'text', true, true, true, 'medical_council', true, ARRAY['doctor_specialist'], 2, 'verified_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'medical_council_image', 'medical_council_image', 'รูปใบประกอบวิชาชีพเวชกรรม', 'อัปโหลดภาพใบประกอบวิชาชีพเวชกรรม', 'image', true, true, false, 'medical_council', false, ARRAY['doctor_specialist'], 3, 'image_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'telemedicine_license_number', 'telemedicine_license_number', 'เลขใบอนุญาต Telemedicine', 'กรอกเลขใบอนุญาต Telemedicine', 'text', true, true, true, 'telemedicine_license', true, ARRAY['doctor_specialist'], 4, 'smart_display_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000103',
    'telemedicine_license_image', 'telemedicine_license_image', 'รูปใบอนุญาต Telemedicine', 'อัปโหลดรูปใบอนุญาต Telemedicine', 'image', true, true, false, 'telemedicine_license', false, ARRAY['doctor_specialist'], 5, 'document_scanner', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000104',
    'profile_image', 'profile_image', 'รูปโปรไฟล์', 'อัปโหลดรูปโปรไฟล์', 'image', true, true, false, NULL, false, ARRAY['dentist'], 0, 'person', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000104',
    'license_number', 'license_number', 'เลขที่ใบประกอบวิชาชีพทันตกรรม', 'กรอกเลขที่ใบอนุญาตทันตแพทย์', 'text', true, true, true, 'dental_council', true, ARRAY['dentist'], 1, 'verified_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000104',
    'license_image', 'license_image', 'รูปใบประกอบวิชาชีพทันตกรรม', 'อัปโหลดรูปใบประกอบวิชาชีพทันตกรรม', 'image', true, true, false, 'dental_council', false, ARRAY['dentist'], 2, 'document_scanner', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000104',
    'telemedicine_license_number', 'telemedicine_license_number', 'เลขใบอนุญาต Telemedicine', 'กรอกเลขใบอนุญาต Telemedicine', 'text', true, true, true, 'telemedicine_license', true, ARRAY['dentist'], 3, 'smart_display_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000104',
    'telemedicine_license_image', 'telemedicine_license_image', 'รูปใบอนุญาต Telemedicine', 'อัปโหลดรูปใบอนุญาต Telemedicine', 'image', true, true, false, 'telemedicine_license', false, ARRAY['dentist'], 4, 'image_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000105',
    'profile_image', 'profile_image', 'รูปโปรไฟล์', 'อัปโหลดรูปโปรไฟล์', 'image', true, true, false, NULL, false, ARRAY['pharmacist'], 0, 'person', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000105',
    'pharmacy_council_number', 'pharmacy_council_number', 'เลขที่ใบประกอบวิชาชีพเภสัชกรรม', 'กรอกเลขที่ใบอนุญาตเภสัชกร', 'text', true, true, true, 'pharmacy_council', true, ARRAY['pharmacist'], 1, 'verified_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000105',
    'pharmacy_council_image', 'pharmacy_council_image', 'รูปใบประกอบวิชาชีพเภสัชกรรม', 'อัปโหลดรูปใบประกอบวิชาชีพเภสัชกรรม', 'image', true, true, false, 'pharmacy_council', false, ARRAY['pharmacist'], 2, 'document_scanner', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000106',
    'profile_image', 'profile_image', 'รูปโปรไฟล์', 'อัปโหลดรูปโปรไฟล์', 'image', true, true, false, NULL, false, ARRAY['telemedicine_provider'], 0, 'person', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000106',
    'telemedicine_license_number', 'telemedicine_license_number', 'เลขใบอนุญาต Telemedicine', 'กรอกเลขใบอนุญาต Telemedicine', 'text', true, true, true, 'telemedicine_license', true, ARRAY['telemedicine_provider'], 1, 'smart_display_outlined', true, NOW(), NOW()
  ),
  (
    '00000000-0000-0000-0000-000000000106',
    'telemedicine_license_image', 'telemedicine_license_image', 'รูปใบอนุญาต Telemedicine', 'อัปโหลดรูปใบอนุญาต Telemedicine', 'image', true, true, false, 'telemedicine_license', false, ARRAY['telemedicine_provider'], 2, 'document_scanner', true, NOW(), NOW()
  )
ON CONFLICT (profession_id, field_id) DO UPDATE SET
  field_key = EXCLUDED.field_key,
  label = EXCLUDED.label,
  hint = EXCLUDED.hint,
  field_type = EXCLUDED.field_type,
  is_required = EXCLUDED.is_required,
  is_locked = EXCLUDED.is_locked,
  requires_attachment = EXCLUDED.requires_attachment,
  attachment_group_key = EXCLUDED.attachment_group_key,
  attachment_required_when_filled = EXCLUDED.attachment_required_when_filled,
  visible_when_profession_code = EXCLUDED.visible_when_profession_code,
  field_order = EXCLUDED.field_order,
  icon_name = EXCLUDED.icon_name,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- ============================================================
-- 7) RLS (Enable but allow all — controlled at app layer)
-- ============================================================
ALTER TABLE public.provider_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_application_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "provider_profiles_select" ON public.provider_profiles;
DROP POLICY IF EXISTS "provider_profiles_modify" ON public.provider_profiles;
DROP POLICY IF EXISTS "provider_credentials_select" ON public.provider_credentials;
DROP POLICY IF EXISTS "provider_credentials_modify" ON public.provider_credentials;
DROP POLICY IF EXISTS "registration_application_attachments_select" ON public.registration_application_attachments;
DROP POLICY IF EXISTS "registration_application_attachments_modify" ON public.registration_application_attachments;

CREATE POLICY "provider_profiles_select" ON public.provider_profiles FOR SELECT USING (true);
CREATE POLICY "provider_profiles_modify" ON public.provider_profiles FOR ALL USING (true);
CREATE POLICY "provider_credentials_select" ON public.provider_credentials FOR SELECT USING (true);
CREATE POLICY "provider_credentials_modify" ON public.provider_credentials FOR ALL USING (true);
CREATE POLICY "registration_application_attachments_select" ON public.registration_application_attachments FOR SELECT USING (true);
CREATE POLICY "registration_application_attachments_modify" ON public.registration_application_attachments FOR ALL USING (true);

-- ============================================================
-- End of migration
-- ============================================================
