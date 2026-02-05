-- =====================================================
-- Migration Script: จาก Schema เดิม (WebSocket) → Schema ใหม่ (v2.1)
-- =====================================================
-- 
-- ใช้สำหรับ database ที่มี users และ locations table เดิมอยู่แล้ว
-- 
-- ขั้นตอน:
-- 1. Backup database ก่อน!
-- 2. รัน script นี้
-- 3. ตรวจสอบข้อมูล
-- =====================================================

-- =====================================================
-- STEP 0: Enable UUID extension
-- =====================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- STEP 1: Backup ตาราง users เดิม
-- =====================================================
-- ถ้ามี users table เดิม (VARCHAR id, name, email)
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users') THEN
        -- Check if old schema (VARCHAR id)
        IF EXISTS (
            SELECT FROM information_schema.columns 
            WHERE table_name = 'users' AND column_name = 'id' AND data_type = 'character varying'
        ) THEN
            RAISE NOTICE 'พบ users table เดิม (VARCHAR id) - กำลัง backup...';
            ALTER TABLE users RENAME TO users_old_backup;
        ELSE
            RAISE NOTICE 'users table มี UUID id อยู่แล้ว - ข้ามการ backup';
        END IF;
    ELSE
        RAISE NOTICE 'ไม่พบ users table - จะสร้างใหม่';
    END IF;
END $$;

-- =====================================================
-- STEP 2: Backup ตาราง locations เดิม (ถ้ามี)
-- =====================================================
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'locations') THEN
        -- Check if old schema (VARCHAR user_id)
        IF EXISTS (
            SELECT FROM information_schema.columns 
            WHERE table_name = 'locations' AND column_name = 'user_id' AND data_type = 'character varying'
        ) THEN
            RAISE NOTICE 'พบ locations table เดิม (VARCHAR user_id) - กำลัง backup...';
            ALTER TABLE locations RENAME TO locations_old_backup;
        ELSE
            RAISE NOTICE 'locations table มี UUID user_id อยู่แล้ว - ข้ามการ backup';
        END IF;
    ELSE
        RAISE NOTICE 'ไม่พบ locations table - จะสร้างใหม่';
    END IF;
END $$;

-- =====================================================
-- STEP 3: สร้างตารางใหม่ทั้งหมด
-- =====================================================

-- 3.1 Professions Table
CREATE TABLE IF NOT EXISTS professions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    name_en VARCHAR(100),
    description TEXT,
    icon_name VARCHAR(100),
    category VARCHAR(20) NOT NULL CHECK (category IN ('consumer', 'provider')),
    is_built_in BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    requires_verification BOOLEAN DEFAULT TRUE,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_professions_category ON professions(category);
CREATE INDEX IF NOT EXISTS idx_professions_is_active ON professions(is_active);

-- 3.2 Users Table (ใหม่)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    profession_id UUID REFERENCES professions(id),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255),  -- Optional (ไม่บังคับ)
    password_hash VARCHAR(255),
    phone VARCHAR(20) NOT NULL UNIQUE,  -- Primary identifier (บังคับ + ไม่ซ้ำ)
    profile_image_url TEXT,
    social_provider VARCHAR(20) CHECK (social_provider IN ('google', 'facebook', 'apple', 'line', 'tiktok')),
    social_id VARCHAR(255),
    verification_status VARCHAR(20) DEFAULT 'pending' CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    is_active BOOLEAN DEFAULT TRUE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(social_provider, social_id)
);

CREATE INDEX IF NOT EXISTS idx_users_profession_id ON users(profession_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

-- 3.3 Locations Table (ใหม่ - UUID user_id)
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

CREATE INDEX IF NOT EXISTS idx_locations_user_id ON locations(user_id);
CREATE INDEX IF NOT EXISTS idx_locations_created_at ON locations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_locations_user_created ON locations(user_id, created_at DESC);

-- 3.4 Registration Field Configs
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

-- 3.5 User Registration Data
CREATE TABLE IF NOT EXISTS user_registration_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    field_id VARCHAR(100) NOT NULL,
    field_value TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, field_id)
);

-- 3.6 Registration Applications
CREATE TABLE IF NOT EXISTS registration_applications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profession_id UUID NOT NULL REFERENCES professions(id),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    username VARCHAR(50) NOT NULL,
    phone VARCHAR(20) NOT NULL,  -- Primary identifier (บังคับ)
    email VARCHAR(255),  -- Optional (ไม่บังคับ)
    profile_image_url TEXT,
    registration_data JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    review_note TEXT,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3.7 Consumer Profiles
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

-- 3.8 Provider Profiles
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
    extra_data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================================
-- STEP 4: Insert Default Data
-- =====================================================

-- Built-in professions
INSERT INTO professions (id, name, name_en, description, icon_name, category, is_built_in, requires_verification, display_order) VALUES
('00000000-0000-0000-0000-000000000001', 'ผู้ซื้อ/ผู้รับบริการ', 'Consumer', 'ผู้ใช้ทั่วไปที่ต้องการซื้อสินค้าหรือรับบริการ', 'shopping_cart', 'consumer', true, false, 0),
('00000000-0000-0000-0000-000000000002', 'ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า', 'Expert/Seller', 'ผู้เชี่ยวชาญ ผู้ขายสินค้า หรือเจ้าของร้านค้า', 'store', 'provider', true, true, 1),
('00000000-0000-0000-0000-000000000003', 'คลินิก/ศูนย์', 'Clinic/Center', 'คลินิก ศูนย์บริการ หรือสถานประกอบการ', 'local_hospital', 'provider', true, true, 2)
ON CONFLICT (id) DO NOTHING;

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
-- STEP 5: Migrate ข้อมูลจากตารางเดิม (ถ้ามี)
-- =====================================================

-- Migrate users from old table (ถ้ามี users_old_backup)
-- หมายเหตุ: ต้อง manual migrate เพราะ schema ต่างกันมาก
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users_old_backup') THEN
        RAISE NOTICE '==============================================';
        RAISE NOTICE 'พบ users_old_backup table';
        RAISE NOTICE 'ข้อมูล users เดิมต้อง migrate manually เพราะ schema ต่างกัน';
        RAISE NOTICE 'ใช้คำสั่งต่อไปนี้เพื่อดูข้อมูลเดิม:';
        RAISE NOTICE 'SELECT * FROM users_old_backup;';
        RAISE NOTICE '==============================================';
    END IF;
END $$;

-- =====================================================
-- STEP 6: สร้าง Functions
-- =====================================================

-- Auto update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Location functions
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
-- STEP 7: สร้าง Triggers
-- =====================================================

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
-- สรุปผล
-- =====================================================
DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Migration เสร็จสมบูรณ์!';
    RAISE NOTICE '';
    RAISE NOTICE 'ตารางใหม่ที่สร้าง:';
    RAISE NOTICE '  - professions (3 built-in professions)';
    RAISE NOTICE '  - users (UUID id)';
    RAISE NOTICE '  - locations (UUID user_id)';
    RAISE NOTICE '  - registration_field_configs';
    RAISE NOTICE '  - user_registration_data';
    RAISE NOTICE '  - registration_applications';
    RAISE NOTICE '  - consumer_profiles';
    RAISE NOTICE '  - provider_profiles';
    RAISE NOTICE '';
    RAISE NOTICE 'ตรวจสอบตารางเดิม:';
    RAISE NOTICE '  - users_old_backup (ถ้ามี)';
    RAISE NOTICE '  - locations_old_backup (ถ้ามี)';
    RAISE NOTICE '==============================================';
END $$;
