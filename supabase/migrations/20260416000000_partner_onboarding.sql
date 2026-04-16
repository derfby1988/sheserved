-- เพิ่มฟิลด์รองรับระบบ Partner Onboarding ให้กับ beneficiary_organizations
ALTER TABLE beneficiary_organizations 
ADD COLUMN owner_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
ADD COLUMN document_urls JSONB DEFAULT '[]'::jsonb;
