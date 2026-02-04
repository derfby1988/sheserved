-- =====================================================
-- Sheserved Database Schema
-- สำหรับ Supabase PostgreSQL
-- =====================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- 1. USERS TABLE - ข้อมูลผู้ใช้หลัก
-- =====================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('consumer', 'expert', 'clinic')),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    username VARCHAR(50) UNIQUE NOT NULL,
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

-- Index for faster lookups
CREATE INDEX idx_users_user_type ON users(user_type);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_social ON users(social_provider, social_id);
CREATE INDEX idx_users_verification_status ON users(verification_status);

-- =====================================================
-- 2. CONSUMER_PROFILES TABLE - ข้อมูลผู้ซื้อ/ผู้รับบริการ
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
-- 3. EXPERT_PROFILES TABLE - ข้อมูลผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า
-- =====================================================
CREATE TABLE IF NOT EXISTS expert_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    business_name VARCHAR(200),
    specialty VARCHAR(200),
    experience_years INTEGER,
    business_address TEXT,
    business_phone VARCHAR(20),
    business_email VARCHAR(255),
    description TEXT,
    id_card_image_url TEXT,
    certificate_image_url TEXT,
    rating DECIMAL(3,2) DEFAULT 0,
    review_count INTEGER DEFAULT 0,
    is_available BOOLEAN DEFAULT TRUE,
    working_hours JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX idx_expert_profiles_specialty ON expert_profiles(specialty);
CREATE INDEX idx_expert_profiles_rating ON expert_profiles(rating);
CREATE INDEX idx_expert_profiles_is_available ON expert_profiles(is_available);

-- =====================================================
-- 4. CLINIC_PROFILES TABLE - ข้อมูลคลินิก/ศูนย์ฯ
-- =====================================================
CREATE TABLE IF NOT EXISTS clinic_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    clinic_name VARCHAR(200),
    license_number VARCHAR(100),
    service_type VARCHAR(200),
    business_address TEXT,
    business_phone VARCHAR(20),
    business_email VARCHAR(255),
    description TEXT,
    business_image_url TEXT,
    license_image_url TEXT,
    id_card_image_url TEXT,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    rating DECIMAL(3,2) DEFAULT 0,
    review_count INTEGER DEFAULT 0,
    is_open BOOLEAN DEFAULT TRUE,
    working_hours JSONB,
    services TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX idx_clinic_profiles_service_type ON clinic_profiles(service_type);
CREATE INDEX idx_clinic_profiles_rating ON clinic_profiles(rating);
CREATE INDEX idx_clinic_profiles_location ON clinic_profiles(latitude, longitude);
CREATE INDEX idx_clinic_profiles_is_open ON clinic_profiles(is_open);

-- =====================================================
-- 5. REGISTRATION_FIELD_CONFIGS TABLE - การตั้งค่าฟิลด์ลงทะเบียน
-- =====================================================
CREATE TABLE IF NOT EXISTS registration_field_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('consumer', 'expert', 'clinic')),
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
    UNIQUE(user_type, field_id)
);

-- Index
CREATE INDEX idx_registration_field_configs_user_type ON registration_field_configs(user_type);
CREATE INDEX idx_registration_field_configs_field_order ON registration_field_configs(field_order);

-- =====================================================
-- 6. USER_REGISTRATION_DATA TABLE - ข้อมูลที่กรอกตาม Dynamic Fields
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
CREATE INDEX idx_user_registration_data_user_id ON user_registration_data(user_id);

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

-- Apply trigger to all tables
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_consumer_profiles_updated_at
    BEFORE UPDATE ON consumer_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_expert_profiles_updated_at
    BEFORE UPDATE ON expert_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_clinic_profiles_updated_at
    BEFORE UPDATE ON clinic_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_registration_field_configs_updated_at
    BEFORE UPDATE ON registration_field_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_registration_data_updated_at
    BEFORE UPDATE ON user_registration_data
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- ROW LEVEL SECURITY (RLS) - Disabled for simplicity
-- =====================================================
-- Note: Enable RLS and add policies when implementing proper authentication

-- Allow all operations for now (development mode)
-- In production, enable RLS and implement proper policies

-- =====================================================
-- DEFAULT DATA - ค่าเริ่มต้น Field Configs
-- =====================================================

-- Consumer fields
INSERT INTO registration_field_configs (user_type, field_id, label, hint, field_type, is_required, field_order, icon_name) VALUES
('consumer', 'email', 'อีเมล', 'กรอกอีเมลของคุณ', 'email', true, 0, 'email_outlined'),
('consumer', 'phone', 'เบอร์โทร', 'กรอกเบอร์โทรศัพท์', 'phone', true, 1, 'phone_outlined'),
('consumer', 'birthday', 'วันเกิด', 'เลือกวันเกิด', 'date', false, 2, 'calendar_today_outlined');

-- Expert fields
INSERT INTO registration_field_configs (user_type, field_id, label, hint, field_type, is_required, field_order, icon_name) VALUES
('expert', 'profile_image', 'รูปโปรไฟล์', 'อัพโหลดรูปโปรไฟล์', 'image', false, 0, 'person'),
('expert', 'business_name', 'ชื่อร้าน/ชื่อธุรกิจ', 'กรอกชื่อร้านหรือธุรกิจของคุณ', 'text', true, 1, 'store_outlined'),
('expert', 'specialty', 'ความเชี่ยวชาญ/ประเภทสินค้า', 'ระบุความเชี่ยวชาญหรือประเภทสินค้า', 'text', false, 2, 'category_outlined'),
('expert', 'business_phone', 'เบอร์โทรติดต่อ', 'กรอกเบอร์โทรสำหรับติดต่อ', 'phone', true, 3, 'phone_outlined'),
('expert', 'business_email', 'อีเมลธุรกิจ', 'กรอกอีเมลสำหรับติดต่อธุรกิจ', 'email', false, 4, 'email_outlined'),
('expert', 'business_address', 'ที่อยู่ร้าน/สถานที่ให้บริการ', 'กรอกที่อยู่', 'multilineText', false, 5, 'location_on_outlined'),
('expert', 'experience', 'ประสบการณ์ (ปี)', 'กรอกจำนวนปีประสบการณ์', 'number', false, 6, 'work_outline'),
('expert', 'id_card_image', 'รูปบัตรประชาชน', 'อัพโหลดรูปบัตรประชาชน', 'image', true, 7, 'credit_card'),
('expert', 'description', 'แนะนำตัว/ธุรกิจ', 'เขียนแนะนำตัวหรือธุรกิจของคุณ', 'multilineText', false, 8, 'description_outlined');

-- Clinic fields
INSERT INTO registration_field_configs (user_type, field_id, label, hint, field_type, is_required, field_order, icon_name) VALUES
('clinic', 'business_image', 'รูปสถานประกอบการ', 'อัพโหลดรูปสถานประกอบการ', 'image', false, 0, 'business'),
('clinic', 'clinic_name', 'ชื่อคลินิก/ศูนย์', 'กรอกชื่อคลินิกหรือศูนย์', 'text', true, 1, 'local_hospital_outlined'),
('clinic', 'license_number', 'เลขใบอนุญาตประกอบกิจการ', 'กรอกเลขใบอนุญาต', 'text', true, 2, 'verified_outlined'),
('clinic', 'service_type', 'ประเภทบริการ', 'เช่น คลินิกผิวหนัง, ฟิตเนส', 'text', false, 3, 'medical_services_outlined'),
('clinic', 'business_phone', 'เบอร์โทรติดต่อ', 'กรอกเบอร์โทรสำหรับติดต่อ', 'phone', true, 4, 'phone_outlined'),
('clinic', 'business_email', 'อีเมลธุรกิจ', 'กรอกอีเมลสำหรับติดต่อ', 'email', false, 5, 'email_outlined'),
('clinic', 'business_address', 'ที่อยู่สถานประกอบการ', 'กรอกที่อยู่', 'multilineText', false, 6, 'location_on_outlined'),
('clinic', 'license_image', 'รูปใบอนุญาตประกอบกิจการ', 'อัพโหลดรูปใบอนุญาต', 'image', true, 7, 'document_scanner'),
('clinic', 'id_card_image', 'รูปบัตรประชาชนผู้จดทะเบียน', 'อัพโหลดรูปบัตรประชาชน', 'image', true, 8, 'credit_card'),
('clinic', 'description', 'รายละเอียดบริการ', 'เขียนรายละเอียดบริการ', 'multilineText', false, 9, 'description_outlined');

-- =====================================================
-- STORAGE BUCKETS (run in Supabase Dashboard)
-- =====================================================
-- CREATE BUCKET: profile_images
-- CREATE BUCKET: id_cards
-- CREATE BUCKET: certificates
-- CREATE BUCKET: business_images
