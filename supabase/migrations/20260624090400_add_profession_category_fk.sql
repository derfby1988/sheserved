-- Migration: Add FK between professions.category → user_categories.id
-- Phase 2.5: Role Management Refactor (สำหรับแนวทาง B)
-- Created: 2026-06-24

-- ตรวจสอบว่าข้อมูล professions.category ทั้งหมดมีอยู่ใน user_categories
DO $$
DECLARE
  orphan_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO orphan_count
  FROM professions p
  WHERE p.category IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM user_categories uc WHERE uc.id = p.category);

  IF orphan_count > 0 THEN
    RAISE NOTICE 'Found % professions with categories not in user_categories', orphan_count;
  END IF;
END $$;

-- เพิ่ม FK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_profession_category'
  ) THEN
    ALTER TABLE professions ADD CONSTRAINT fk_profession_category
      FOREIGN KEY (category) REFERENCES user_categories(id);
  END IF;
END $$;
