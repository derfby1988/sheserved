-- Database Schema for Location Tracking
-- PostgreSQL Database Schema

-- Create database
-- CREATE DATABASE sheserved;

-- Users table (if not using existing user table)
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255),
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Locations table
CREATE TABLE IF NOT EXISTS locations (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    accuracy DECIMAL(10, 2),
    speed DECIMAL(10, 2),
    heading DECIMAL(5, 2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    -- Removed FOREIGN KEY constraint to allow flexibility
    -- FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_locations_user_id ON locations(user_id);
CREATE INDEX IF NOT EXISTS idx_locations_created_at ON locations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_locations_user_created ON locations(user_id, created_at DESC);

-- Function to get latest location for each user
CREATE OR REPLACE FUNCTION get_latest_locations()
RETURNS TABLE (
    user_id VARCHAR(255),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    created_at TIMESTAMP
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
    p_user_id VARCHAR(255),
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    id INTEGER,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    accuracy DECIMAL(10, 2),
    speed DECIMAL(10, 2),
    heading DECIMAL(5, 2),
    created_at TIMESTAMP
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
