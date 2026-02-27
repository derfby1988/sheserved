-- Migration: Seed Default Professions and Field Configs
-- Created at: 2026-02-27 11:30:00

-- 1. เพิ่ม UNIQUE constraint ให้กับ registration_field_configs (ถ้ายังไม่มี) 
-- เพื่อให้ใช้ ON CONFLICT (profession_id, field_id) ได้
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'registration_field_configs_profession_id_field_id_key'
    ) THEN
        ALTER TABLE public.registration_field_configs 
        ADD CONSTRAINT registration_field_configs_profession_id_field_id_key 
        UNIQUE (profession_id, field_id);
    END IF;
END $$;

-- 2. แทรกข้อมูลอาชีพหลัก (Built-in Professions)
INSERT INTO public.professions (id, name, name_en, description, icon_name, category, is_built_in, requires_verification, display_order, is_active) VALUES
('00000000-0000-0000-0000-000000000001', 'ผู้ซื้อ/ผู้รับบริการ', 'Consumer', 'ผู้ใช้ทั่วไปที่ต้องการซื้อสินค้าหรือรับบริการ', 'shopping_cart', 'consumer', true, false, 0, true),
('00000000-0000-0000-0000-000000000002', 'ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า', 'Expert/Seller', 'ผู้เชี่ยวชาญ ผู้ขายสินค้า หรือเจ้าของร้านค้า', 'store', 'provider', true, true, 1, true),
('00000000-0000-0000-0000-000000000003', 'คลินิก/ศูนย์', 'Clinic/Center', 'คลินิก ศูนย์บริการ หรือสถานประกอบการ', 'local_hospital', 'provider', true, true, 2, true)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    name_en = EXCLUDED.name_en,
    description = EXCLUDED.description,
    icon_name = EXCLUDED.icon_name,
    category = EXCLUDED.category,
    is_built_in = EXCLUDED.is_built_in,
    requires_verification = EXCLUDED.requires_verification,
    display_order = EXCLUDED.display_order,
    is_active = EXCLUDED.is_active,
    updated_at = NOW();

-- 3. แทรกข้อมูลฟิลด์ลงทะเบียนเริ่มต้น (Default Field Configs)

-- สำหรับ Consumer
INSERT INTO public.registration_field_configs (profession_id, field_id, label, hint, field_type, is_required, field_order, icon_name, is_active) VALUES
('00000000-0000-0000-0000-000000000001', 'email', 'อีเมล', 'กรอกอีเมลของคุณ', 'email', true, 0, 'email_outlined', true),
('00000000-0000-0000-0000-000000000001', 'phone', 'เบอร์โทร', 'กรอกเบอร์โทรศัพท์', 'phone', true, 1, 'phone_outlined', true),
('00000000-0000-0000-0000-000000000001', 'birthday', 'วันเกิด', 'เลือกวันเกิด', 'date', false, 2, 'calendar_today_outlined', true)
ON CONFLICT (profession_id, field_id) DO UPDATE SET
    label = EXCLUDED.label,
    hint = EXCLUDED.hint,
    field_type = EXCLUDED.field_type,
    is_required = EXCLUDED.is_required,
    field_order = EXCLUDED.field_order,
    icon_name = EXCLUDED.icon_name,
    is_active = EXCLUDED.is_active,
    updated_at = NOW();

-- สำหรับ Expert/Seller
INSERT INTO public.registration_field_configs (profession_id, field_id, label, hint, field_type, is_required, field_order, icon_name, is_active) VALUES
('00000000-0000-0000-0000-000000000002', 'profile_image', 'รูปโปรไฟล์', 'อัพโหลดรูปโปรไฟล์', 'image', false, 0, 'person', true),
('00000000-0000-0000-0000-000000000002', 'business_name', 'ชื่อร้าน/ชื่อธุรกิจ', 'กรอกชื่อร้านหรือธุรกิจของคุณ', 'text', true, 1, 'store_outlined', true),
('00000000-0000-0000-0000-000000000002', 'specialty', 'ความเชี่ยวชาญ/ประเภทสินค้า', 'ระบุความเชี่ยวชาญหรือประเภทสินค้า', 'text', false, 2, 'category_outlined', true),
('00000000-0000-0000-0000-000000000002', 'business_phone', 'เบอร์โทรติดต่อ', 'กรอกเบอร์โทรสำหรับติดต่อ', 'phone', true, 3, 'phone_outlined', true),
('00000000-0000-0000-0000-000000000002', 'business_email', 'อีเมลธุรกิจ', 'กรอกอีเมลสำหรับติดต่อธุรกิจ', 'email', false, 4, 'email_outlined', true),
('00000000-0000-0000-0000-000000000002', 'business_address', 'ที่อยู่ร้าน/สถานที่ให้บริการ', 'กรอกที่อยู่', 'multilineText', false, 5, 'location_on_outlined', true),
('00000000-0000-0000-0000-000000000002', 'experience', 'ประสบการณ์ (ปี)', 'กรอกจำนวนปีประสบการณ์', 'number', false, 6, 'work_outline', true),
('00000000-0000-0000-0000-000000000002', 'id_card_image', 'รูปบัตรประชาชน', 'อัพโหลดรูปบัตรประชาชน', 'image', true, 7, 'credit_card', true),
('00000000-0000-0000-0000-000000000002', 'description', 'แนะนำตัว/ธุรกิจ', 'เขียนแนะนำตัวหรือธุรกิจของคุณ', 'multilineText', false, 8, 'description_outlined', true)
ON CONFLICT (profession_id, field_id) DO UPDATE SET
    label = EXCLUDED.label,
    hint = EXCLUDED.hint,
    field_type = EXCLUDED.field_type,
    is_required = EXCLUDED.is_required,
    field_order = EXCLUDED.field_order,
    icon_name = EXCLUDED.icon_name,
    is_active = EXCLUDED.is_active,
    updated_at = NOW();

-- สำหรับ Clinic/Center
INSERT INTO public.registration_field_configs (profession_id, field_id, label, hint, field_type, is_required, field_order, icon_name, is_active) VALUES
('00000000-0000-0000-0000-000000000003', 'business_image', 'รูปสถานประกอบการ', 'อัพโหลดรูปสถานประกอบการ', 'image', false, 0, 'business', true),
('00000000-0000-0000-0000-000000000003', 'clinic_name', 'ชื่อคลินิก/ศูนย์', 'กรอกชื่อคลินิกหรือศูนย์', 'text', true, 1, 'local_hospital_outlined', true),
('00000000-0000-0000-0000-000000000003', 'license_number', 'เลขใบอนุญาตประกอบกิจการ', 'กรอกเลขใบอนุญาต', 'text', true, 2, 'verified_outlined', true),
('00000000-0000-0000-0000-000000000003', 'service_type', 'ประเภทบริการ', 'เช่น คลินิกผิวหนัง, ฟิตเนส', 'text', false, 3, 'medical_services_outlined', true),
('00000000-0000-0000-0000-000000000003', 'business_phone', 'เบอร์โทรติดต่อ', 'กรอกเบอร์โทรสำหรับติดต่อ', 'phone', true, 4, 'phone_outlined', true),
('00000000-0000-0000-0000-000000000003', 'business_email', 'อีเมลธุรกิจ', 'กรอกอีเมลสำหรับติดต่อ', 'email', false, 5, 'email_outlined', true),
('00000000-0000-0000-0000-000000000003', 'business_address', 'ที่อยู่สถานประกอบการ', 'กรอกที่อยู่', 'multilineText', false, 6, 'location_on_outlined', true),
('00000000-0000-0000-0000-000000000003', 'license_image', 'รูปใบอนุญาตประกอบกิจการ', 'อัพโหลดรูปใบอนุญาต', 'image', true, 7, 'document_scanner', true),
('00000000-0000-0000-0000-000000000003', 'id_card_image', 'รูปบัตรประชาชนผู้จดทะเบียน', 'อัพโหลดรูปบัตรประชาชน', 'image', true, 8, 'credit_card', true),
('00000000-0000-0000-0000-000000000003', 'description', 'รายละเอียดบริการ', 'เขียนรายละเอียดบริการ', 'multilineText', false, 9, 'description_outlined', true)
ON CONFLICT (profession_id, field_id) DO UPDATE SET
    label = EXCLUDED.label,
    hint = EXCLUDED.hint,
    field_type = EXCLUDED.field_type,
    is_required = EXCLUDED.is_required,
    field_order = EXCLUDED.field_order,
    icon_name = EXCLUDED.icon_name,
    is_active = EXCLUDED.is_active,
    updated_at = NOW();
