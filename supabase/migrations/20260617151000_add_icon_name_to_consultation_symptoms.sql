-- Migration: Add icon_name to consultation_symptoms for denormalized body region icon lookup
-- Description: Phase 6.6 BodyMap Chat Bar — store icon_name directly in symptoms to avoid DB joins

-- 1. Add column
ALTER TABLE consultation_symptoms ADD COLUMN IF NOT EXISTS icon_name TEXT;

-- 2. Backfill existing rows from body_regions
UPDATE consultation_symptoms cs
SET icon_name = br.icon_name
FROM body_regions br
WHERE cs.region_id = br.id
  AND cs.icon_name IS NULL;

-- 3. Index for fast lookup (optional, since symptoms table is small)
CREATE INDEX IF NOT EXISTS idx_consultation_symptoms_icon_name ON consultation_symptoms(icon_name);

-- 4. Add comment
COMMENT ON COLUMN consultation_symptoms.icon_name IS 'Material icon name from body_regions (e.g. lens_outlined, face) denormalized for fast UI lookup';
