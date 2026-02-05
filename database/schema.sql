-- =====================================================
-- Sheserved Database Schema v2.1
-- สำหรับ Local PostgreSQL และ Supabase
-- รวม Location Tracking + Dynamic Profession System
-- =====================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- 1. PROFESSIONS TABLE - ตารางอาชีพ (Dynamic)
-- =====================================================
CREATE TABLE IF NOT EXISTS professions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    name_en VARCHAR(100),
    description TEXT,
    icon_name VARCHAR(100),
    category VARCHAR(20) NOT NULL CHECK (category IN ('consumer', 'provider')),
    is_built_in BOOLEAN DEFAULT FALSE,  -- Built-in ลบไม่ได้
    is_active BOOLEAN DEFAULT TRUE,
    requires_verification BOOLEAN DEFAULT TRUE,  -- ต้องตรวจสอบก่อนใช้งาน
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_professions_category ON professions(category);
CREATE INDEX IF NOT EXISTS idx_professions_is_active ON professions(is_active);
CREATE INDEX IF NOT EXISTS idx_professions_display_order ON professions(display_order);

-- =====================================================
-- 2. USERS TABLE - ข้อมูลผู้ใช้หลัก (รวม WebSocket + Auth)
-- =====================================================
-- หมายเหตุ: ถ้ามี users table เดิม ต้อง migrate ข้อมูลก่อน drop
-- ALTER TABLE users RENAME TO users_old;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    profession_id UUID REFERENCES professions(id),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255),  -- เพิ่มจาก schema เดิม
    password_hash VARCHAR(255), -- NULL for social login
    phone VARCHAR(20),
    profile_image_url TEXT,
    -- Social Login Fields
    social_provider VARCHAR(20) CHECK (social_provider IN ('google', 'facebook', 'apple', 'line', 'tiktok')),
    social_id VARCHAR(255),
    -- Status
    verification_status VARCHAR(20) DEFAULT 'pending' CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Ensure social login uniqueness
    UNIQUE(social_provider, social_id)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_users_profession_id ON users(profession_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_social ON users(social_provider, social_id);
CREATE INDEX IF NOT EXISTS idx_users_verification_status ON users(verification_status);

-- =====================================================
-- 3. LOCATIONS TABLE - ข้อมูลตำแหน่ง (จาก WebSocket Server)
-- =====================================================
CREATE TABLE IF NOT EXISTS locations (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    accuracy DECIMAL(10, 2),
    speed DECIMAL(10, 2),
    heading DECIMAL(5, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_locations_user_id ON locations(user_id);
CREATE INDEX IF NOT EXISTS idx_locations_created_at ON locations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_locations_user_created ON locations(user_id, created_at DESC);

-- =====================================================
-- 4. REGISTRATION_FIELD_CONFIGS TABLE - การตั้งค่าฟิลด์ลงทะเบียน
-- =====================================================
CREATE TABLE IF NOT EXISTS registration_field_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    profession_id UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    field_id VARCHAR(100) NOT NULL,
    label VARCHAR(200) NOT NULL,
    hint VARCHAR(500),
    field_type VARCHAR(50) NOT NULL CHECK (field_type IN ('text', 'email', 'phone', 'number', 'date', 'image', 'multilineText', 'dropdown')),
    is_required BOOLEAN DEFAULT FALSE,
    field_order INTEGER DEFAULT 0,
    icon_name VARCHAR(100),
    dropdown_options TEXT[],
    validation_regex VARCHAR(500),
    validation_message VARCHAR(500),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(profession_id, field_id)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_registration_field_configs_profession_id ON registration_field_configs(profession_id);
CREATE INDEX IF NOT EXISTS idx_registration_field_configs_field_order ON registration_field_configs(field_order);

-- =====================================================
-- 5. USER_REGISTRATION_DATA TABLE - ข้อมูลที่กรอกตาม Dynamic Fields
-- =====================================================
CREATE TABLE IF NOT EXISTS user_registration_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    field_id VARCHAR(100) NOT NULL,
    field_value TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, field_id)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_user_registration_data_user_id ON user_registration_data(user_id);

-- =====================================================
-- 6. REGISTRATION_APPLICATIONS TABLE - ใบสมัครรอตรวจสอบ
-- =====================================================
CREATE TABLE IF NOT EXISTS registration_applications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profession_id UUID NOT NULL REFERENCES professions(id),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    username VARCHAR(50) NOT NULL,
    phone VARCHAR(20),
    profile_image_url TEXT,
    registration_data JSONB DEFAULT '{}',  -- เก็บข้อมูล dynamic fields
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    review_note TEXT,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_registration_applications_user_id ON registration_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_registration_applications_profession_id ON registration_applications(profession_id);
CREATE INDEX IF NOT EXISTS idx_registration_applications_status ON registration_applications(status);
CREATE INDEX IF NOT EXISTS idx_registration_applications_created_at ON registration_applications(created_at DESC);

-- =====================================================
-- 7. CONSUMER_PROFILES TABLE - ข้อมูลผู้ซื้อ/ผู้รับบริการ
-- =====================================================
CREATE TABLE IF NOT EXISTS consumer_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    birthday DATE,
    address TEXT,
    emergency_contact VARCHAR(100),
    emergency_phone VARCHAR(20),
    health_info JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================================
-- 8. PROVIDER_PROFILES TABLE - ข้อมูลผู้ให้บริการ
-- =====================================================
CREATE TABLE IF NOT EXISTS provider_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    business_name VARCHAR(200),
    license_number VARCHAR(100),
    specialty VARCHAR(200),
    experience_years INTEGER,
    business_address TEXT,
    business_phone VARCHAR(20),
    business_email VARCHAR(255),
    description TEXT,
    business_image_url TEXT,
    id_card_image_url TEXT,
    certificate_image_url TEXT,
    license_image_url TEXT,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    rating DECIMAL(3,2) DEFAULT 0,
    review_count INTEGER DEFAULT 0,
    is_available BOOLEAN DEFAULT TRUE,
    working_hours JSONB,
    services TEXT[],
    extra_data JSONB DEFAULT '{}',  -- ข้อมูลเพิ่มเติมตามอาชีพ
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_provider_profiles_user_id ON provider_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_provider_profiles_specialty ON provider_profiles(specialty);
CREATE INDEX IF NOT EXISTS idx_provider_profiles_rating ON provider_profiles(rating);
CREATE INDEX IF NOT EXISTS idx_provider_profiles_location ON provider_profiles(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_provider_profiles_is_available ON provider_profiles(is_available);

-- =====================================================
-- TRIGGERS - Auto update updated_at
-- =====================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to all tables (DROP IF EXISTS to avoid duplicates)
DROP TRIGGER IF EXISTS update_professions_updated_at ON professions;
CREATE TRIGGER update_professions_updated_at
    BEFORE UPDATE ON professions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_registration_field_configs_updated_at ON registration_field_configs;
CREATE TRIGGER update_registration_field_configs_updated_at
    BEFORE UPDATE ON registration_field_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_registration_data_updated_at ON user_registration_data;
CREATE TRIGGER update_user_registration_data_updated_at
    BEFORE UPDATE ON user_registration_data
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_registration_applications_updated_at ON registration_applications;
CREATE TRIGGER update_registration_applications_updated_at
    BEFORE UPDATE ON registration_applications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_consumer_profiles_updated_at ON consumer_profiles;
CREATE TRIGGER update_consumer_profiles_updated_at
    BEFORE UPDATE ON consumer_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_provider_profiles_updated_at ON provider_profiles;
CREATE TRIGGER update_provider_profiles_updated_at
    BEFORE UPDATE ON provider_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- FUNCTIONS - Location Tracking (จาก WebSocket Server)
-- =====================================================

-- Function to get latest location for each user
CREATE OR REPLACE FUNCTION get_latest_locations()
RETURNS TABLE (
    user_id UUID,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (l.user_id)
        l.user_id,
        l.latitude,
        l.longitude,
        l.created_at
    FROM locations l
    ORDER BY l.user_id, l.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to get user's location history
CREATE OR REPLACE FUNCTION get_user_location_history(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    id INTEGER,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    accuracy DECIMAL(10, 2),
    speed DECIMAL(10, 2),
    heading DECIMAL(5, 2),
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        l.id,
        l.latitude,
        l.longitude,
        l.accuracy,
        l.speed,
        l.heading,
        l.created_at
    FROM locations l
    WHERE l.user_id = p_user_id
    ORDER BY l.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- DEFAULT DATA - อาชีพเริ่มต้น (Built-in)
-- =====================================================

-- Built-in professions with fixed UUIDs (use ON CONFLICT to avoid duplicates)
INSERT INTO professions (id, name, name_en, description, icon_name, category, is_built_in, requires_verification, display_order) VALUES
('00000000-0000-0000-0000-000000000001', 'ผู้ซื้อ/ผู้รับบริการ', 'Consumer', 'ผู้ใช้ทั่วไปที่ต้องการซื้อสินค้าหรือรับบริการ', 'shopping_cart', 'consumer', true, false, 0),
('00000000-0000-0000-0000-000000000002', 'ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า', 'Expert/Seller', 'ผู้เชี่ยวชาญ ผู้ขายสินค้า หรือเจ้าของร้านค้า', 'store', 'provider', true, true, 1),
('00000000-0000-0000-0000-000000000003', 'คลินิก/ศูนย์', 'Clinic/Center', 'คลินิก ศูนย์บริการ หรือสถานประกอบการ', 'local_hospital', 'provider', true, true, 2)
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- DEFAULT DATA - Field Configs สำหรับแต่ละอาชีพ
-- =====================================================

-- Consumer fields
INSERT INTO registration_field_configs (profession_id, field_id, label, hint, field_type, is_required, field_order, icon_name) VALUES
('00000000-0000-0000-0000-000000000001', 'email', 'อีเมล', 'กรอกอีเมลของคุณ', 'email', true, 0, 'email_outlined'),
('00000000-0000-0000-0000-000000000001', 'phone', 'เบอร์โทร', 'กรอกเบอร์โทรศัพท์', 'phone', true, 1, 'phone_outlined'),
('00000000-0000-0000-0000-000000000001', 'birthday', 'วันเกิด', 'เลือกวันเกิด', 'date', false, 2, 'calendar_today_outlined')
ON CONFLICT (profession_id, field_id) DO NOTHING;

-- Expert/Seller fields
INSERT INTO registration_field_configs (profession_id, field_id, label, hint, field_type, is_required, field_order, icon_name) VALUES
('00000000-0000-0000-0000-000000000002', 'profile_image', 'รูปโปรไฟล์', 'อัพโหลดรูปโปรไฟล์', 'image', false, 0, 'person'),
('00000000-0000-0000-0000-000000000002', 'business_name', 'ชื่อร้าน/ชื่อธุรกิจ', 'กรอกชื่อร้านหรือธุรกิจของคุณ', 'text', true, 1, 'store_outlined'),
('00000000-0000-0000-0000-000000000002', 'specialty', 'ความเชี่ยวชาญ/ประเภทสินค้า', 'ระบุความเชี่ยวชาญหรือประเภทสินค้า', 'text', false, 2, 'category_outlined'),
('00000000-0000-0000-0000-000000000002', 'business_phone', 'เบอร์โทรติดต่อ', 'กรอกเบอร์โทรสำหรับติดต่อ', 'phone', true, 3, 'phone_outlined'),
('00000000-0000-0000-0000-000000000002', 'business_email', 'อีเมลธุรกิจ', 'กรอกอีเมลสำหรับติดต่อธุรกิจ', 'email', false, 4, 'email_outlined'),
('00000000-0000-0000-0000-000000000002', 'business_address', 'ที่อยู่ร้าน/สถานที่ให้บริการ', 'กรอกที่อยู่', 'multilineText', false, 5, 'location_on_outlined'),
('00000000-0000-0000-0000-000000000002', 'experience', 'ประสบการณ์ (ปี)', 'กรอกจำนวนปีประสบการณ์', 'number', false, 6, 'work_outline'),
('00000000-0000-0000-0000-000000000002', 'id_card_image', 'รูปบัตรประชาชน', 'อัพโหลดรูปบัตรประชาชน', 'image', true, 7, 'credit_card'),
('00000000-0000-0000-0000-000000000002', 'description', 'แนะนำตัว/ธุรกิจ', 'เขียนแนะนำตัวหรือธุรกิจของคุณ', 'multilineText', false, 8, 'description_outlined')
ON CONFLICT (profession_id, field_id) DO NOTHING;

-- Clinic/Center fields
INSERT INTO registration_field_configs (profession_id, field_id, label, hint, field_type, is_required, field_order, icon_name) VALUES
('00000000-0000-0000-0000-000000000003', 'business_image', 'รูปสถานประกอบการ', 'อัพโหลดรูปสถานประกอบการ', 'image', false, 0, 'business'),
('00000000-0000-0000-0000-000000000003', 'clinic_name', 'ชื่อคลินิก/ศูนย์', 'กรอกชื่อคลินิกหรือศูนย์', 'text', true, 1, 'local_hospital_outlined'),
('00000000-0000-0000-0000-000000000003', 'license_number', 'เลขใบอนุญาตประกอบกิจการ', 'กรอกเลขใบอนุญาต', 'text', true, 2, 'verified_outlined'),
('00000000-0000-0000-0000-000000000003', 'service_type', 'ประเภทบริการ', 'เช่น คลินิกผิวหนัง, ฟิตเนส', 'text', false, 3, 'medical_services_outlined'),
('00000000-0000-0000-0000-000000000003', 'business_phone', 'เบอร์โทรติดต่อ', 'กรอกเบอร์โทรสำหรับติดต่อ', 'phone', true, 4, 'phone_outlined'),
('00000000-0000-0000-0000-000000000003', 'business_email', 'อีเมลธุรกิจ', 'กรอกอีเมลสำหรับติดต่อ', 'email', false, 5, 'email_outlined'),
('00000000-0000-0000-0000-000000000003', 'business_address', 'ที่อยู่สถานประกอบการ', 'กรอกที่อยู่', 'multilineText', false, 6, 'location_on_outlined'),
('00000000-0000-0000-0000-000000000003', 'license_image', 'รูปใบอนุญาตประกอบกิจการ', 'อัพโหลดรูปใบอนุญาต', 'image', true, 7, 'document_scanner'),
('00000000-0000-0000-0000-000000000003', 'id_card_image', 'รูปบัตรประชาชนผู้จดทะเบียน', 'อัพโหลดรูปบัตรประชาชน', 'image', true, 8, 'credit_card'),
('00000000-0000-0000-0000-000000000003', 'description', 'รายละเอียดบริการ', 'เขียนรายละเอียดบริการ', 'multilineText', false, 9, 'description_outlined')
ON CONFLICT (profession_id, field_id) DO NOTHING;

-- =====================================================
-- STORAGE BUCKETS (สำหรับ Supabase - ใช้ Dashboard สร้าง)
-- =====================================================
-- CREATE BUCKET: profile_images
-- CREATE BUCKET: id_cards
-- CREATE BUCKET: certificates
-- CREATE BUCKET: business_images
-- CREATE BUCKET: license_images

-- =====================================================
-- ROW LEVEL SECURITY (สำหรับ Supabase)
-- =====================================================
-- Uncomment these when using Supabase

-- ALTER TABLE users ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE professions ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE registration_field_configs ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE registration_applications ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE consumer_profiles ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE provider_profiles ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE locations ENABLE ROW LEVEL SECURITY;

-- Professions: ทุกคนอ่านได้
-- CREATE POLICY "Public read professions" ON professions
--   FOR SELECT USING (is_active = true);

-- Registration Field Configs: ทุกคนอ่านได้
-- CREATE POLICY "Public read field configs" ON registration_field_configs
--   FOR SELECT USING (is_active = true);

-- Users: เจ้าของดูได้
-- CREATE POLICY "Users can view own data" ON users
--   FOR SELECT USING (auth.uid() = id);

-- Registration Applications: เจ้าของหรือแอดมินดูได้
-- CREATE POLICY "Users can view own applications" ON registration_applications
--   FOR SELECT USING (auth.uid() = user_id);

-- Locations: เจ้าของดูและเขียนได้
-- CREATE POLICY "Users can manage own locations" ON locations
--   FOR ALL USING (auth.uid() = user_id);
