-- =========================================================
-- Migration: สร้าง Storage Buckets สำหรับก๊วนกีฬา (Fitness Buddies)
-- Buckets: fitness-group-covers (ภาพปกก๊วน), fitness-group-venues (ภาพถ่ายสนาม)
-- สอดคล้องกับระบบ Custom Auth (ServiceLocator) — ไม่ใช้ 'TO authenticated'
-- =========================================================

-- 1. สร้าง bucket 'fitness-group-covers' (public)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'fitness-group-covers',
  'fitness-group-covers',
  true,
  5242880,       -- 5 MB max per file
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Allow anon upload to fitness-group-covers"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'fitness-group-covers');

CREATE POLICY "Allow public read from fitness-group-covers"
ON storage.objects
FOR SELECT
USING (bucket_id = 'fitness-group-covers');

CREATE POLICY "Allow anon update in fitness-group-covers"
ON storage.objects
FOR UPDATE
USING (bucket_id = 'fitness-group-covers');

CREATE POLICY "Allow anon delete from fitness-group-covers"
ON storage.objects
FOR DELETE
USING (bucket_id = 'fitness-group-covers');

-- 2. สร้าง bucket 'fitness-group-venues' (public)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'fitness-group-venues',
  'fitness-group-venues',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Allow anon upload to fitness-group-venues"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'fitness-group-venues');

CREATE POLICY "Allow public read from fitness-group-venues"
ON storage.objects
FOR SELECT
USING (bucket_id = 'fitness-group-venues');

CREATE POLICY "Allow anon update in fitness-group-venues"
ON storage.objects
FOR UPDATE
USING (bucket_id = 'fitness-group-venues');

CREATE POLICY "Allow anon delete from fitness-group-venues"
ON storage.objects
FOR DELETE
USING (bucket_id = 'fitness-group-venues');
