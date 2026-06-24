-- =====================================================
-- Phase 2 Pre-Migration Verification Script
-- ตรวจสอบความพร้อมก่อนรัน migration
-- วิธีใช้: รันผ่าน Supabase SQL Editor หรือ psql
-- =====================================================

-- 1. ตรวจสอบ orphan data: professions.category ที่ไม่มีใน user_categories
SELECT '=== 1. Orphan professions.category ===' AS check_name;
SELECT 
  p.id,
  p.name,
  p.category,
  'NOT IN user_categories' AS status
FROM professions p
WHERE p.category IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM user_categories uc WHERE uc.id = p.category
  );

-- 2. ตรวจสอบ users.role ที่ไม่ใช่ค่าที่ถูกต้อง
SELECT '=== 2. Invalid users.role ===' AS check_name;
SELECT 
  id,
  username,
  role,
  'INVALID ROLE' AS status
FROM users
WHERE role NOT IN ('consumer', 'provider', 'admin')
  AND role IS NOT NULL;

-- 3. ตรวจสอบ users ที่มี role เป็น NULL
SELECT '=== 3. Users with NULL role ===' AS check_name;
SELECT 
  COUNT(*) AS null_role_count
FROM users
WHERE role IS NULL;

-- 4. ตรวจสอบว่า user_categories มี 'admin' อยู่แล้วหรือไม่
SELECT '=== 4. Existing admin in user_categories ===' AS check_name;
SELECT 
  id,
  name,
  is_active
FROM user_categories
WHERE id = 'admin';

-- 5. ตรวจสอบว่า professions มี admin profession อยู่แล้วหรือไม่
SELECT '=== 5. Existing admin profession ===' AS check_name;
SELECT 
  id,
  name,
  category
FROM professions
WHERE id = '00000000-0000-0000-0000-000000000999';

-- 6. ตรวจสอบจำนวน users แยกตาม role
SELECT '=== 6. Users count by role ===' AS check_name;
SELECT 
  role,
  COUNT(*) AS user_count
FROM users
GROUP BY role
ORDER BY role;

-- 7. ตรวจสอบ users ที่มี profession_id แต่ไม่มีใน professions
SELECT '=== 7. Orphan users.profession_id ===' AS check_name;
SELECT 
  u.id,
  u.username,
  u.profession_id,
  'NOT IN professions' AS status
FROM users u
WHERE u.profession_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM professions p WHERE p.id = u.profession_id
  );

-- 8. ตรวจสอบว่า app schema มีอยู่หรือไม่ (สำหรับ RLS functions)
SELECT '=== 8. app schema existence ===' AS check_name;
SELECT 
  schema_name
FROM information_schema.schemata
WHERE schema_name = 'app';

-- =====================================================
-- สรุปผลการตรวจสอบ
-- =====================================================
SELECT '=== VERIFICATION COMPLETE ===' AS status;
SELECT 
  'ถ้าข้อ 1, 2, 3, 7 ไม่มีผลลัพธ์ → ปลอดภัยที่จะรัน migration' AS summary;
SELECT 
  'ถ้าข้อ 4 มีผลลัพธ์ → ข้าม migration 2.1 ได้' AS summary;
SELECT 
  'ถ้าข้อ 5 มีผลลัพธ์ → ข้าม migration 2.4 ได้' AS summary;
