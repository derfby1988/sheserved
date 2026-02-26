-- Migration: Add availability_status and provider_id columns
-- Run this in Supabase SQL Editor

-- 1. Add availability_status to users table
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS availability_status TEXT NOT NULL DEFAULT 'online'
    CHECK (availability_status IN ('online', 'busy', 'offline'));

-- 2. Add provider_id to consultation_requests (FK to users)
ALTER TABLE consultation_requests
  ADD COLUMN IF NOT EXISTS provider_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- 3. Index for fast filtering
CREATE INDEX IF NOT EXISTS idx_users_availability
  ON users (profession_id, availability_status, last_seen_at);

CREATE INDEX IF NOT EXISTS idx_consultation_requests_provider
  ON consultation_requests (provider_id, status);

-- 4. Enable Realtime for consultation_requests (if not already enabled)
ALTER PUBLICATION supabase_realtime ADD TABLE consultation_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE users;
