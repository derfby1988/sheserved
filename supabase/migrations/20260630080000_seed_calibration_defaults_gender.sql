-- ============================================================
-- Seed gender-specific calibration defaults
-- ============================================================
-- Male and female anatomical proportions differ:
--   Male: broader shoulders, narrower hips, shorter waist, higher navel
--   Female: narrower shoulders, wider hips, longer waist, lower navel
-- ============================================================

INSERT INTO public.body_region_calibration_defaults (gender, platform, landmarks, is_active)
VALUES
-- ── MALE defaults ───────────────────────────────────────────
('male', 'universal', '[
  {"id":0,"name":"ศีรษะ","nameEn":"Head Top","y2d":0.00,"y3d":0.07,"x2d":0.50,"x3d":0.50,"autoDetected":true},
  {"id":1,"name":"คอ","nameEn":"Neck","y2d":0.12,"y3d":0.16,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":2,"name":"ไหล่","nameEn":"Shoulders","y2d":0.18,"y3d":0.22,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":3,"name":"สะดือ","nameEn":"Navel","y2d":0.50,"y3d":0.48,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":4,"name":"อวัยวะเพศ","nameEn":"Groin","y2d":0.68,"y3d":0.68,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":5,"name":"หัวเข่า","nameEn":"Knees","y2d":0.82,"y3d":0.84,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":6,"name":"เท้า","nameEn":"Feet","y2d":1.00,"y3d":0.93,"x2d":0.50,"x3d":0.50,"autoDetected":true}
]'::jsonb, true),

-- ── FEMALE defaults ─────────────────────────────────────────
('female', 'universal', '[
  {"id":0,"name":"ศีรษะ","nameEn":"Head Top","y2d":0.00,"y3d":0.08,"x2d":0.50,"x3d":0.50,"autoDetected":true},
  {"id":1,"name":"คอ","nameEn":"Neck","y2d":0.12,"y3d":0.17,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":2,"name":"ไหล่","nameEn":"Shoulders","y2d":0.18,"y3d":0.26,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":3,"name":"สะดือ","nameEn":"Navel","y2d":0.50,"y3d":0.54,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":4,"name":"อวัยวะเพศ","nameEn":"Groin","y2d":0.68,"y3d":0.71,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":5,"name":"หัวเข่า","nameEn":"Knees","y2d":0.82,"y3d":0.85,"x2d":0.50,"x3d":0.50,"autoDetected":false},
  {"id":6,"name":"เท้า","nameEn":"Feet","y2d":1.00,"y3d":0.93,"x2d":0.50,"x3d":0.50,"autoDetected":true}
]'::jsonb, true)

ON CONFLICT (gender, platform) DO UPDATE
  SET landmarks = EXCLUDED.landmarks,
      updated_at = NOW();
