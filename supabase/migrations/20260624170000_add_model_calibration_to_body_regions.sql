-- Add per-region 3D model calibration columns to body_regions
-- These values map a region's abstract yRatio (0..1 relative to the body silhouette)
-- to the actual on-screen vertical position of the rendered 3D model.
--
-- Default: model_top_ratio = 0.08, model_bottom_ratio = 0.93
-- (matches the current hardcoded patient page constants)

ALTER TABLE public.body_regions
ADD COLUMN IF NOT EXISTS model_top_ratio DOUBLE PRECISION NOT NULL DEFAULT 0.08,
ADD COLUMN IF NOT EXISTS model_bottom_ratio DOUBLE PRECISION NOT NULL DEFAULT 0.93;

-- Ensure validation: top must be strictly less than bottom
-- (enforced at application layer; guard clause also in _modelYRatio)

-- Backfill existing rows with the current default calibration
UPDATE public.body_regions
SET model_top_ratio = 0.08,
    model_bottom_ratio = 0.93
WHERE model_top_ratio = 0.00 AND model_bottom_ratio = 1.00;

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
