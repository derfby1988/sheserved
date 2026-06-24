-- Migration: Remove duplicate FK constraint on professions.category
-- Phase 2.5 Fix: ลบ FK ที่ซ้ำซ้อน (มี professions_category_fkey อยู่แล้ว)
-- Created: 2026-06-24

-- ตรวจสอบว่ามี FK ซ้ำหรือไม่
DO $$
DECLARE
  v_existing_fk TEXT;
BEGIN
  -- แสดง FK ทั้งหมดที่เกี่ยวข้องกับ professions.category → user_categories
  SELECT string_agg(conname, ', ')
  INTO v_existing_fk
  FROM pg_constraint
  WHERE conrelid = 'professions'::regclass
    AND confrelid = 'user_categories'::regclass;

  IF v_existing_fk IS NOT NULL THEN
    RAISE NOTICE 'Found FK constraints: %', v_existing_fk;
  END IF;
END $$;

-- ลบ FK ที่สร้างใหม่ (fk_profession_category) ถ้ามี professions_category_fkey อยู่แล้ว
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_profession_category'
      AND conrelid = 'professions'::regclass
  ) AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'professions_category_fkey'
      AND conrelid = 'professions'::regclass
  ) THEN
    -- มี FK เดิมอยู่แล้ว → ลบ FK ที่สร้างใหม่
    ALTER TABLE professions DROP CONSTRAINT fk_profession_category;
    RAISE NOTICE 'Dropped duplicate FK: fk_profession_category (professions_category_fkey already exists)';
  END IF;
END $$;
