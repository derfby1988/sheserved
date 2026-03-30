-- แก้ไข RLS อีกครั้งโดยลบ 'TO authenticated' ออก เนื่องจากโปรเจกต์ไม่ได้ใช้ Supabase Auth ตาม auth_data_guidelines.md
-- ทำให้ตอนนี้ผู้ใช้กำลังทำงานด้วยสถานะ 'anon' หรือ 'public'

-- Drop policies ที่เพิ่งสร้างไปก่อนหน้า
DROP POLICY IF EXISTS "Insertable authenticated" ON public.registration_field_configs;
DROP POLICY IF EXISTS "Updatable authenticated" ON public.registration_field_configs;
DROP POLICY IF EXISTS "Deletable authenticated" ON public.registration_field_configs;

DROP POLICY IF EXISTS "Insertable authenticated roles" ON public.user_group_roles;
DROP POLICY IF EXISTS "Updatable authenticated roles" ON public.user_group_roles;
DROP POLICY IF EXISTS "Deletable authenticated roles" ON public.user_group_roles;

-- 1. สร้าง Policies ใหม่สำหรับ registration_field_configs ให้เป็น public เพื่อให้ App (ที่ใช้ custom auth) บันทึกข้อมูลได้
CREATE POLICY "Insertable public" 
ON public.registration_field_configs FOR INSERT 
TO public WITH CHECK (true);

CREATE POLICY "Updatable public" 
ON public.registration_field_configs FOR UPDATE 
TO public USING (true) WITH CHECK (true);

CREATE POLICY "Deletable public" 
ON public.registration_field_configs FOR DELETE 
TO public USING (true);


-- 2. สร้าง Policies ใหม่สำหรับ user_group_roles ให้เป็น public
CREATE POLICY "Insertable public roles" 
ON public.user_group_roles FOR INSERT 
TO public WITH CHECK (true);

CREATE POLICY "Updatable public roles" 
ON public.user_group_roles FOR UPDATE 
TO public USING (true) WITH CHECK (true);

CREATE POLICY "Deletable public roles" 
ON public.user_group_roles FOR DELETE 
TO public USING (true);
