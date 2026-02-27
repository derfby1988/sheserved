-- ========================================================================
-- Donation System - Custom Fields Support
-- เพิ่มระบบฟิลด์ข้อมูลแบบไดนามิกสำหรับแต่ละหมวดหมู่
-- ========================================================================

-- เพิ่มคอลัมน์ custom_fields ในตาราง donation_categories 
-- เพื่อจัดเก็บฟิลด์ที่ต้องการให้ผู้ใช้กรอกเพิ่มเติมสำหรับหมวดหมู่นั้น (เป็น JSONB)
ALTER TABLE public.donation_categories
ADD COLUMN IF NOT EXISTS custom_fields JSONB DEFAULT '[]'::jsonb;

-- เพิ่มคอลัมน์ custom_data ในตาราง donation_requests
-- เพื่อจัดเก็บคำตอบหรือข้อมูลที่ผู้ใช้กรอกแบบไดนามิก (เป็น JSONB)
ALTER TABLE public.donation_requests
ADD COLUMN IF NOT EXISTS custom_data JSONB DEFAULT '{}'::jsonb;
