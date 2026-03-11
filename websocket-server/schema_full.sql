-- MASTER SCHEMA FOR LOCAL WEBSOCKET SERVER
-- This file consolidates all necessary tables for real-time alerts and video system.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables to ensure clean schema (Dev only)
DROP TABLE IF EXISTS incident_responses CASCADE;
DROP TABLE IF EXISTS video_interactions CASCADE;
DROP TABLE IF EXISTS video_gps_tracks CASCADE;
DROP TABLE IF EXISTS videos CASCADE;
DROP TABLE IF EXISTS donation_categories CASCADE;
DROP TABLE IF EXISTS user_group_roles CASCADE;
DROP TABLE IF EXISTS consumer_profiles CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS professions CASCADE;
DROP TABLE IF EXISTS locations CASCADE;

-- 1. Professions
CREATE TABLE IF NOT EXISTS professions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    name_en VARCHAR(100),
    description TEXT,
    icon_name VARCHAR(100),
    category VARCHAR(20) NOT NULL,
    is_built_in BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    is_volunteer BOOLEAN DEFAULT FALSE,
    requires_verification BOOLEAN DEFAULT TRUE,
    display_order INTEGER DEFAULT 0,
    color_hex VARCHAR(7),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Users (Consistent with v2.1)
-- Drop existing users table if it has old schema
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.columns 
        WHERE table_name = 'users' AND column_name = 'first_name' AND is_nullable = 'NO'
    ) THEN
        -- Table exists and seems okay
    ELSE
        DROP TABLE IF EXISTS users CASCADE;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    profession_id UUID,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255),
    password_hash VARCHAR(255),
    phone VARCHAR(20),
    profile_image_url TEXT,
    social_provider VARCHAR(20),
    social_id VARCHAR(255),
    verification_status VARCHAR(20) DEFAULT 'verified',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Consumer Profiles
CREATE TABLE IF NOT EXISTS consumer_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    birthday DATE,
    address TEXT,
    is_volunteer_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. User Group Roles
CREATE TABLE IF NOT EXISTS user_group_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profession_id UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Donation Categories
CREATE TABLE IF NOT EXISTS donation_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    name_en TEXT,
    icon_name TEXT,
    is_emergency BOOLEAN DEFAULT FALSE,
    display_order INT DEFAULT 0,
    volunteer_profession_ids TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Videos
CREATE TABLE IF NOT EXISTS videos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL, -- No FK to allow guest uploads if needed
    type VARCHAR(20) DEFAULT 'normal',
    title VARCHAR(255) NOT NULL,
    description TEXT,
    bunny_video_id VARCHAR(255),
    bunny_url TEXT,
    thumbnail_url TEXT,
    photo_urls JSONB,
    duration INTEGER,
    file_size BIGINT,
    category_id UUID,
    donation_request_id UUID,
    status VARCHAR(50) DEFAULT 'processing',
    progress INTEGER DEFAULT 0,
    address TEXT,
    road TEXT,
    soi TEXT,
    alley TEXT,
    village TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. Video GPS Tracks
CREATE TABLE IF NOT EXISTS video_gps_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    timestamp_offset INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 8. Incident Responses
CREATE TABLE IF NOT EXISTS incident_responses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    volunteer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'accepted',
    accepted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    arrived_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    volunteer_start_lat DOUBLE PRECISION,
    volunteer_start_lng DOUBLE PRECISION,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (video_id, volunteer_id)
);

-- 9. Video Interactions (Likes, Views, Gifts)
CREATE TABLE IF NOT EXISTS video_interactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    user_id UUID, -- Optional user_id
    type VARCHAR(20), -- 'like', 'gift', 'view'
    value INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 10. Locations (for real-time tracking)
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

-- 11. Seed Data
-- Add default professions
INSERT INTO professions (id, name, name_en, category, is_built_in, is_volunteer, color_hex) VALUES
('00000000-0000-0000-0000-000000000001', 'กู้ภัย', 'Rescue', 'provider', true, true, '#FF0000'),
('00000000-0000-0000-0000-000000000002', 'พยาบาล', 'Nurse', 'provider', true, true, '#00FF00'),
('00000000-0000-0000-0000-000000000003', 'พลเมืองดี', 'Good Samaritan', 'consumer', true, true, '#0000FF')
ON CONFLICT (id) DO NOTHING;

-- Add default categories
INSERT INTO donation_categories (id, name, is_emergency, volunteer_profession_ids) VALUES
('2b0eb15f-1126-4ef2-bbc4-497591c59a9c', 'อุบัติเหตุ', true, '{"00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002", "00000000-0000-0000-0000-000000000003"}'),
('e3e3e3e3-e3e3-e3e3-e3e3-e3e3e3e3e3e3', 'ไฟไหม้', true, '{"00000000-0000-0000-0000-000000000001"}')
ON CONFLICT (id) DO NOTHING;
