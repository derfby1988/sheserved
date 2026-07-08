-- Migration: Fix sync_role_from_profession search_path bug
-- Date: 2026-07-07
--
-- ปัญหา: function sync_role_from_profession() ตั้ง SET search_path = '' (empty)
-- แต่อ้างตาราง `professions` แบบไม่ qualify schema ทำให้เกิด error
-- 42P01 "relation professions does not exist" เมื่อ user เปลี่ยน profession_id
--
-- แก้: qualify ตารางเป็น public.professions (และ user_categories อ้างอิงถูกต้อง)
-- เพื่อให้ทำงานได้แม้ search_path ว่าง

CREATE OR REPLACE FUNCTION public.sync_role_from_profession()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_category TEXT;
BEGIN
  IF NEW.profession_id IS NOT NULL THEN
    SELECT category INTO v_category
    FROM public.professions
    WHERE id = NEW.profession_id;

    IF v_category IS NOT NULL THEN
      NEW.role = v_category;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
