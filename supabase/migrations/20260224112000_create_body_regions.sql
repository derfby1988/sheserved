CREATE TABLE IF NOT EXISTS body_regions (
  id TEXT PRIMARY KEY,
  name_th TEXT NOT NULL,
  name_en TEXT NOT NULL,
  y_ratio REAL NOT NULL,
  x_ratio REAL NOT NULL DEFAULT 0.50,
  icon_name TEXT,
  has_sides BOOLEAN DEFAULT false,
  gender TEXT DEFAULT 'both',
  image_2d_url TEXT,
  model_3d_url TEXT,
  display_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Seed defaults (based on existing data)
INSERT INTO body_regions (id, name_th, name_en, y_ratio, x_ratio, icon_name, has_sides, display_order)
VALUES 
  ('top_head', 'ศีรษะด้านบน', 'Top of Head', 0.04, 0.50, 'face', false, 1),
  ('forehead', 'หน้าผาก', 'Forehead', 0.07, 0.50, 'face_retouching_natural', false, 2),
  ('eyes', 'ดวงตา', 'Eyes', 0.09, 0.50, 'remove_red_eye_outlined', true, 3),
  ('nose_ears', 'จมูก/หู', 'Nose/Ears', 0.11, 0.50, 'hearing_outlined', true, 4),
  ('mouth_jaw', 'ปาก/กราม', 'Mouth/Jaw', 0.13, 0.50, 'record_voice_over_outlined', false, 5),
  ('neck', 'ลำคอ', 'Neck', 0.17, 0.50, 'compress', false, 6),
  ('shoulder', 'หัวไหล่', 'Shoulder', 0.22, 0.38, 'accessibility_new', true, 7),
  ('collarbone', 'ไหปลาร้า', 'Collarbone', 0.25, 0.42, 'horizontal_rule', true, 8),
  ('upper_chest', 'หน้าอกส่วนบน', 'Upper Chest', 0.29, 0.50, 'monitor_heart_outlined', true, 9),
  ('upper_arm', 'ต้นแขน', 'Upper Arm', 0.33, 0.28, 'fitness_center', true, 10),
  ('lower_chest', 'หน้าอกส่วนล่าง', 'Lower Chest', 0.36, 0.50, 'favorite_border', true, 11),
  ('upper_abd', 'ท้องส่วนบน', 'Upper Abdomen', 0.40, 0.50, 'restaurant_menu', false, 12),
  ('elbow', 'ข้อศอก', 'Elbow', 0.44, 0.22, 'adjust', true, 13),
  ('middle_abd', 'รอบสะดือ', 'Navel Area', 0.47, 0.50, 'radio_button_checked', false, 14),
  ('lower_arm', 'แขนท่อนล่าง', 'Forearm', 0.50, 0.20, 'pan_tool_alt_outlined', true, 15),
  ('lower_abd', 'ท้องส่วนล่าง', 'Lower Abdomen', 0.53, 0.50, 'water_drop_outlined', false, 16),
  ('wrist', 'ข้อมือ', 'Wrist', 0.56, 0.18, 'watch_outlined', true, 17),
  ('pelvis', 'เชิงกราน/ก้น', 'Pelvis/Glutes', 0.59, 0.50, 'trip_origin', false, 18),
  ('hand', 'มือ/นิ้วมือ', 'Hand/Fingers', 0.62, 0.15, 'back_hand_outlined', true, 19),
  ('upper_thigh', 'ต้นขาส่วนบน', 'Upper Thigh', 0.66, 0.40, 'directions_walk', true, 20),
  ('mid_thigh', 'ต้นขาส่วนกลาง', 'Mid Thigh', 0.71, 0.38, 'directions_run', true, 21),
  ('knee', 'หัวเข่า', 'Knee', 0.77, 0.42, 'lens_outlined', true, 22),
  ('upper_shin', 'หน้าแข้ง/น่อง', 'Shin/Calf', 0.83, 0.42, 'linear_scale', true, 23),
  ('lower_shin', 'ข้อเท้าด้านบน', 'Lower Shin', 0.88, 0.42, 'align_vertical_bottom', true, 24),
  ('ankle', 'ข้อเท้า', 'Ankle', 0.93, 0.42, 'radio_button_unchecked', true, 25),
  ('foot', 'หลังเท้า', 'Foot', 0.96, 0.42, 'run_circle_outlined', true, 26),
  ('toes', 'นิ้วเท้า', 'Toes', 0.99, 0.42, 'linear_scale_outlined', true, 27)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS
ALTER TABLE body_regions ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view body regions
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'body_regions' AND policyname = 'Everyone can view body regions'
    ) THEN
        CREATE POLICY "Everyone can view body regions" 
        ON body_regions FOR SELECT USING (true);
    END IF;
END
$$;

-- Policy: Admin can manage body regions (assuming true for now or auth.role() = 'authenticated')
-- In a real prod this would be tighter
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'body_regions' AND policyname = 'Admins can manage body regions'
    ) THEN
        CREATE POLICY "Admins can manage body regions" 
        ON body_regions USING (auth.role() = 'authenticated');
    END IF;
END
$$;

-- Insert into Storage for images if necessary (requires bucket setup)
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public) 
  VALUES ('body_region_images', 'body_region_images', true)
  ON CONFLICT (id) DO NOTHING;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Public Access for body_region_images'
    ) THEN
        CREATE POLICY "Public Access for body_region_images"
        ON storage.objects FOR SELECT
        USING (bucket_id = 'body_region_images');
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Authenticated users can upload to body_region_images'
    ) THEN
        CREATE POLICY "Authenticated users can upload to body_region_images"
        ON storage.objects FOR INSERT
        WITH CHECK (bucket_id = 'body_region_images' AND auth.role() = 'authenticated');
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Authenticated users can update body_region_images'
    ) THEN
        CREATE POLICY "Authenticated users can update body_region_images"
        ON storage.objects FOR UPDATE
        USING (bucket_id = 'body_region_images' AND auth.role() = 'authenticated');
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND policyname = 'Authenticated users can delete body_region_images'
    ) THEN
        CREATE POLICY "Authenticated users can delete body_region_images"
        ON storage.objects FOR DELETE
        USING (bucket_id = 'body_region_images' AND auth.role() = 'authenticated');
    END IF;
END
$$;
