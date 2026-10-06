-- Incident Overview Map (VIDEO_SYSTEM_PLAN.md §22.4.5) — btree indexes only.
-- No PostGIS/spatial extension: evidence from EXPLAIN (ANALYZE, BUFFERS) on the
-- local database showed Seq Scan on video_gps_tracks (first-point subquery used
-- by the emergency list) and Seq Scan on videos (type+category filter), so plain
-- btree indexes are sufficient at the current access pattern:
--   category_id = ANY(...) AND type IN ('emergency','emergency_photo')
--   ORDER BY created_at DESC, id DESC
-- Re-run EXPLAIN after applying; if the plan still scans, revisit before rollout.

-- 1. First GPS point per video (canonical incident location, shared with the
--    emergency list subquery: DISTINCT ON (video_id) ... ORDER BY video_id,
--    timestamp_offset ASC).
CREATE INDEX IF NOT EXISTS idx_video_gps_tracks_video_id_ts
    ON video_gps_tracks (video_id, timestamp_offset);

-- 2. Category-filtered emergency listing/map query (Phase 20 filter and the
--    incident map both filter category + type, newest first).
CREATE INDEX IF NOT EXISTS idx_videos_category_type_created
    ON videos (category_id, type, created_at DESC);

-- 3. Batch safe-thumbnail lookup for map points
--    (video_id = ANY(...) AND blur_status = 'completed' ORDER BY created_at DESC, id DESC).
CREATE INDEX IF NOT EXISTS idx_thai_mhung_photos_video_completed
    ON thai_mhung_photos (video_id, blur_status, created_at DESC, id DESC);
