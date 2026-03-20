-- Migration: Create Video System Tables
-- Target: Supabase / PostgreSQL

-- 1. Table for Video Metadata
CREATE TABLE IF NOT EXISTS videos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    type VARCHAR(20) DEFAULT 'normal', -- normal, emergency
    donation_request_id UUID REFERENCES donation_requests(id), -- Linked to existing donation system
    title VARCHAR(255) NOT NULL,
    description TEXT,
    bunny_video_id VARCHAR(255),
    bunny_url TEXT,
    thumbnail_url TEXT,
    duration INTEGER, -- seconds
    file_size BIGINT, -- bytes
    status VARCHAR(50) DEFAULT 'processing', -- processing, ready, error
    progress INTEGER DEFAULT 0, -- 0-100%
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Table for GPS Tracks (Synced with video timestamps for Map playback)
CREATE TABLE IF NOT EXISTS video_gps_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    timestamp_offset INTEGER NOT NULL, -- Seconds from the start of video
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Table for Real-time Interactions (Likes, Gifting, Views)
CREATE TABLE IF NOT EXISTS video_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    type VARCHAR(20), -- like, gift, view
    value INTEGER DEFAULT 0, -- Donation amount or other values
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_videos_user_id ON videos(user_id);
CREATE INDEX IF NOT EXISTS idx_videos_type ON videos(type);
CREATE INDEX IF NOT EXISTS idx_video_gps_tracks_video_id ON video_gps_tracks(video_id);
CREATE INDEX IF NOT EXISTS idx_video_interactions_video_id ON video_interactions(video_id);
