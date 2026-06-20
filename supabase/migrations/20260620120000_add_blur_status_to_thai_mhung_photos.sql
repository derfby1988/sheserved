-- Migration: Add blur_status to thai_mhung_photos for Phase 6.12 Async Face Blur
-- Description: Track face blur processing status to support async background blur + gallery blocking

-- 1. Add blur_status column
ALTER TABLE thai_mhung_photos ADD COLUMN IF NOT EXISTS blur_status VARCHAR(20) DEFAULT 'blurring';

-- 2. Add comment
COMMENT ON COLUMN thai_mhung_photos.blur_status IS 'Face blur status: blurring | completed | failed (Phase 6.12)';

-- 3. Backfill existing rows (assume already blurred if photo_url exists and created before this migration)
UPDATE thai_mhung_photos SET blur_status = 'completed' WHERE blur_status IS NULL;

-- 4. Set NOT NULL after backfill
ALTER TABLE thai_mhung_photos ALTER COLUMN blur_status SET NOT NULL;
ALTER TABLE thai_mhung_photos ALTER COLUMN blur_status SET DEFAULT 'blurring';
