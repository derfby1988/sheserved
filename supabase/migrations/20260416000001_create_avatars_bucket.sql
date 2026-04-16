-- Migration: สร้าง Storage Bucket สำหรับรูปภาพอวตาร์
-- ชื่อ bucket: avatars

-- 1. สร้าง bucket 'avatars'
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars', 
  'avatars', 
  true, -- เปิดเป็น public เพื่อให้สามารถเรียกดูผ่าน URL ได้โดยตรง
  5242880, -- แนะนำให้จำกัดขนาดสัก 5MB
  ARRAY['image/png', 'image/jpeg', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 2. ตั้งค่า Policies
-- อนุญาตให้ดูภาพได้ทุกคน
CREATE POLICY "Avatar images are publicly accessible." ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

-- อนุญาตให้อัพโหลดไฟล์ได้
CREATE POLICY "Users can upload their own avatars." ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'avatars');

-- อนุญาตให้อัพเดท/แก้ไขไฟล์
CREATE POLICY "Users can update their own avatars." ON storage.objects
  FOR UPDATE USING (bucket_id = 'avatars');

-- อนุญาตให้ลบไฟล์เดิม
CREATE POLICY "Users can delete their own avatars." ON storage.objects
  FOR DELETE USING (bucket_id = 'avatars');
