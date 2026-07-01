-- Phase 6.13 v2.0: Multi-Point Calibration with Gender + Platform + Expandable Landmarks + xRatio
-- Creates:
--   1. body_region_calibration_defaults (gender-aware, platform-aware global defaults)
--   2. Adds landmarks JSONB + calibration_gender + calibration_platform to body_regions

-- ============================================================
-- 1. Global Calibration Defaults Table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.body_region_calibration_defaults (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gender TEXT NOT NULL DEFAULT 'both',       -- 'male' | 'female' | 'both'
  platform TEXT NOT NULL DEFAULT 'universal', -- 'mobile' | 'web' | 'tablet' | 'universal'
  landmarks JSONB NOT NULL DEFAULT '[]'::jsonb,
  -- [{"id":0,"name":"ศีรษะ","y2d":0.0,"y3d":0.08,"x2d":0.5,"x3d":0.5,"autoDetected":false}, ...]
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(gender, platform)
);

CREATE INDEX IF NOT EXISTS idx_calibration_defaults_lookup
  ON public.body_region_calibration_defaults(gender, platform, is_active);

COMMENT ON TABLE public.body_region_calibration_defaults IS
  'Global multi-point calibration defaults per gender and platform. Landmarks stored as JSONB array for expandable, schema-less landmarks.';

-- ============================================================
-- 2. Per-Region Override columns on body_regions (JSONB approach)
-- ============================================================
ALTER TABLE public.body_regions
  ADD COLUMN IF NOT EXISTS landmarks JSONB,
  ADD COLUMN IF NOT EXISTS calibration_gender TEXT DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS calibration_platform TEXT DEFAULT 'universal';

COMMENT ON COLUMN public.body_regions.landmarks IS
  'Optional per-region landmark override. NULL = use global calibration_defaults. JSONB array of BodyLandmark objects.';
COMMENT ON COLUMN public.body_regions.calibration_gender IS
  'Target gender for this regions calibration lookup (male/female/both). Used when resolving global defaults.';
COMMENT ON COLUMN public.body_regions.calibration_platform IS
  'Target platform for this regions calibration lookup (mobile/web/tablet/universal). Used when resolving global defaults.';

-- ============================================================
-- 3. Seed universal defaults (both genders, all platforms)
-- ============================================================
INSERT INTO public.body_region_calibration_defaults (gender, platform, landmarks)
VALUES (
  'both',
  'universal',
  '[
    {"id":0,"name":"ศีรษะ","nameEn":"Head Top","y2d":0.00,"y3d":0.08,"x2d":0.50,"x3d":0.50,"autoDetected":true},
    {"id":1,"name":"คอ","nameEn":"Neck","y2d":0.12,"y3d":0.18,"x2d":0.50,"x3d":0.50,"autoDetected":false},
    {"id":2,"name":"ไหล่","nameEn":"Shoulders","y2d":0.18,"y3d":0.25,"x2d":0.50,"x3d":0.50,"autoDetected":false},
    {"id":3,"name":"สะดือ","nameEn":"Navel","y2d":0.50,"y3d":0.52,"x2d":0.50,"x3d":0.50,"autoDetected":false},
    {"id":4,"name":"อวัยวะเพศ","nameEn":"Groin","y2d":0.68,"y3d":0.70,"x2d":0.50,"x3d":0.50,"autoDetected":false},
    {"id":5,"name":"หัวเข่า","nameEn":"Knees","y2d":0.82,"y3d":0.85,"x2d":0.50,"x3d":0.50,"autoDetected":false},
    {"id":6,"name":"เท้า","nameEn":"Feet","y2d":1.00,"y3d":0.93,"x2d":0.50,"x3d":0.50,"autoDetected":true}
  ]'::jsonb
)
ON CONFLICT (gender, platform) DO UPDATE
  SET landmarks = EXCLUDED.landmarks,
      updated_at = NOW();

-- ============================================================
-- 4. Enable RLS on calibration_defaults (admin + app read)
-- ============================================================
ALTER TABLE public.body_region_calibration_defaults ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'body_region_calibration_defaults'
      AND policyname = 'Allow public read on calibration_defaults'
  ) THEN
    CREATE POLICY "Allow public read on calibration_defaults"
      ON public.body_region_calibration_defaults
      FOR SELECT TO public, authenticated
      USING (is_active = true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'body_region_calibration_defaults'
      AND policyname = 'Allow admin write on calibration_defaults'
  ) THEN
    CREATE POLICY "Allow admin write on calibration_defaults"
      ON public.body_region_calibration_defaults
      FOR ALL TO authenticated
      USING ( EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid() AND role = 'admin'
      ));
  END IF;
END $$;

-- ============================================================
-- 5. Backfill body_regions calibration columns
-- ============================================================
UPDATE public.body_regions
SET calibration_gender = COALESCE(gender, 'both'),
    calibration_platform = 'universal'
WHERE calibration_gender IS NULL;

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
