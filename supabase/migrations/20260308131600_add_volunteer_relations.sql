-- Migration: Add Volunteer Role and Category Relations
-- Created at: 2026-03-08 13:16:00

-- 1. เพิ่ม is_volunteer ให้กับ Professions
ALTER TABLE public.professions 
ADD COLUMN IF NOT EXISTS is_volunteer BOOLEAN DEFAULT false;

-- 2. เพิ่ม volunteer_profession_ids ให้กับ Donation Categories
-- เก็บเป็น Array ของ UUID หรือ TEXT ที่ตรงกับ id ของ professions
ALTER TABLE public.donation_categories 
ADD COLUMN IF NOT EXISTS volunteer_profession_ids TEXT[] DEFAULT '{}';

-- 3. รีเฟรช Schema แคช (บังคับให้ Supabase รู้จักคอลัมน์ใหม่)
NOTIFY pgrst, 'reload schema';
