-- เพิ่มคอลัมน์ can_approve_donation ใน donation_categories
-- เพื่อกำหนดว่า local leader ที่มีอาชีพเกี่ยวข้องสามารถอนุมัติบริจาคในหมวดหมู่นี้ได้
ALTER TABLE public.donation_categories 
ADD COLUMN IF NOT EXISTS can_approve_donation BOOLEAN DEFAULT FALSE;
