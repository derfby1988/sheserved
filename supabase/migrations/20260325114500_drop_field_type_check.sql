-- แก้ไขปัญหา Check Constraint ของคอลัมน์ field_type ที่จำกัดค่าให้เป็นเฉพาะค่าแบบเดิม
-- โดยการลบ constraint ตัวนี้ออก เพื่อให้ระบบรองรับ 'addressPicker' และค่าอื่นๆ ในอนาคต

ALTER TABLE public.registration_field_configs 
DROP CONSTRAINT IF EXISTS registration_field_configs_field_type_check;
