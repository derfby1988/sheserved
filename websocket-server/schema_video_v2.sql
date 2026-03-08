-- schema_video_v2.sql

-- 1. Main Video Table
CREATE TABLE IF NOT EXISTS videos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    type VARCHAR(20) DEFAULT 'normal', -- 'normal', 'emergency'
    title VARCHAR(255) NOT NULL,
    description TEXT,
    bunny_video_id VARCHAR(255),
    bunny_url TEXT,
    thumbnail_url TEXT,
    photo_urls JSONB, -- Array of photo URLs if the report contains images instead of video
    duration INTEGER,
    file_size BIGINT,
    category_id UUID, -- Links to donation_categories
    donation_request_id UUID, -- Optional link to a donation goal
    status VARCHAR(50) DEFAULT 'processing', -- 'processing', 'uploading', 'ready', 'error'
    progress INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. GPS Tracks for Map Synchronization
CREATE TABLE IF NOT EXISTS video_gps_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    timestamp_offset INTEGER NOT NULL, -- Seconds from video start
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Interaction Table (Likes, Gifts, Views)
CREATE TABLE IF NOT EXISTS video_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    type VARCHAR(20), -- 'like', 'gift', 'view'
    value INTEGER DEFAULT 0, -- Amount for gifts
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_video_gps_tracks_video_id ON video_gps_tracks(video_id);
CREATE INDEX IF NOT EXISTS idx_video_interactions_video_id ON video_interactions(video_id);
