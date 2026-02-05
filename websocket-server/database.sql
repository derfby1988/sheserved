-- =====================================================
-- WebSocket Server - Database Schema (Compatible with v2.1)
-- =====================================================
-- 
-- สำหรับ WebSocket Server ที่ต้องการเฉพาะ users และ locations
-- ใช้ร่วมกับ main schema ได้ (database/schema.sql)
--
-- ถ้าต้องการ full schema ให้ใช้: database/schema.sql
-- ถ้าต้องการเฉพาะ WebSocket features ให้ใช้ไฟล์นี้
-- =====================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- Users table (simplified for WebSocket)
-- =====================================================
-- หมายเหตุ: ตาราง users นี้จะถูก override โดย main schema
-- ถ้าใช้ร่วมกับ database/schema.sql ไม่ต้อง run ส่วนนี้

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- =====================================================
-- Locations table (for WebSocket location tracking)
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

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_locations_user_id ON locations(user_id);
CREATE INDEX IF NOT EXISTS idx_locations_created_at ON locations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_locations_user_created ON locations(user_id, created_at DESC);

-- =====================================================
-- Functions for Location Tracking
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
-- Auto-update timestamp trigger
-- =====================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
