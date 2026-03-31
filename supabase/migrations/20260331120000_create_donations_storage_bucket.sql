-- =========================================================
-- Migration: สร้าง Storage Bucket สำหรับระบบบริจาค
-- ชื่อ bucket: donations
-- รองรับ: รูปภาพ custom field ของคำร้องขอบริจาค
-- ปรับปรุง: สอดคล้องกับระบบ Custom Auth (ServiceLocator)
-- =========================================================

-- 1. สร้าง bucket 'donations' (public เพื่อให้แสดงรูปได้โดยไม่ต้อง login)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'donations',
  'donations',
  true,          -- public bucket
  5242880,       -- 5 MB max per file
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- หมายเหตุ: เนื่องจากระบบใช้ Custom Auth (ServiceLocator) ไม่ใช่ Supabase Auth 
-- ดังนั้นการใช้ 'TO authenticated' จะทำให้ upload ไม่ได้เพราะ Supabase Client มองเป็น anon

-- 2. Policy: อนุญาตให้ทุกคนอัปโหลดได้ (ควบคุมผ่านหน้าบ้านและ App Logic)
CREATE POLICY "Allow anon upload to donations"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'donations');

-- 3. Policy: ทุกคนอ่าน/ดูรูปได้ (public read)
CREATE POLICY "Allow public read from donations"
ON storage.objects
FOR SELECT
USING (bucket_id = 'donations');

-- 4. Policy: อนุญาตให้ทุกคนลบได้ (ควบคุมผ่าน App Logic)
CREATE POLICY "Allow anon delete from donations"
ON storage.objects
FOR DELETE
USING (bucket_id = 'donations');

-- 5. Policy: อนุญาตให้ทุกคนอัปเดตได้ (upsert)
CREATE POLICY "Allow anon update in donations"
ON storage.objects
FOR UPDATE
USING (bucket_id = 'donations');

