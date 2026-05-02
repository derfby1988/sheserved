-- =====================================================
-- Yield Way System Migration
-- Created: 2026-04-30
-- =====================================================

-- 1. เพิ่มฟิลด์ yield_way_radius ในตาราง users
--    (ใช้ is_thai_mhung_enabled เป็น opt-in แทนการสร้าง field ใหม่)
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS yield_way_radius INTEGER NOT NULL DEFAULT 1000;

-- 2. เพิ่ม route_polyline ในตาราง incident_responses
--    เก็บ encoded polyline string (Google Maps overview_polyline format)
ALTER TABLE incident_responses
  ADD COLUMN IF NOT EXISTS route_polyline TEXT,
  ADD COLUMN IF NOT EXISTS route_from_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS route_from_lng DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS route_to_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS route_to_lng DOUBLE PRECISION;

-- 3. สร้างตาราง yield_way_histories สำหรับเก็บประวัติการให้ทาง
CREATE TABLE IF NOT EXISTS yield_way_histories (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL,
  video_id            UUID NOT NULL,
  incident_response_id UUID,               -- อ้างอิงจิตอาสาที่ให้ทาง (อาจ null ถ้า route ของทุกคน)
  user_lat            DOUBLE PRECISION,    -- ตำแหน่งของผู้กดให้ทาง ณ เวลานั้น
  user_lng            DOUBLE PRECISION,
  yielded_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index สำหรับ query เร็วขึ้น
CREATE INDEX IF NOT EXISTS idx_yield_way_histories_video_id ON yield_way_histories (video_id);
CREATE INDEX IF NOT EXISTS idx_yield_way_histories_user_id  ON yield_way_histories (user_id);
CREATE INDEX IF NOT EXISTS idx_incident_responses_video_id  ON incident_responses (video_id);

-- Comment อธิบาย
COMMENT ON TABLE yield_way_histories IS 'ประวัติการให้ทางของผู้ใช้งาน สำหรับสะสมแต้มบุญ';
COMMENT ON COLUMN users.yield_way_radius IS 'รัศมีการรับแจ้งเตือนให้ทาง (เมตร) ค่าเริ่มต้น 1000 ม.';
COMMENT ON COLUMN incident_responses.route_polyline IS 'Encoded polyline string ของเส้นทางจิตอาสา → จุดเกิดเหตุ';
