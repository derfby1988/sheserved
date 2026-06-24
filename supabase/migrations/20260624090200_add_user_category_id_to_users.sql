-- Migration: Add user_category_id to users + migrate existing data
-- Phase 2.3: Role Management Refactor
-- Created: 2026-06-24

-- เพิ่ม column user_category_id
ALTER TABLE users ADD COLUMN IF NOT EXISTS user_category_id TEXT;

-- เพิ่ม FK constraint (หลังจาก migrate ข้อมูล)
-- หมายเหตุ: ยังไม่เพิ่ม FK ทันที เพราะอาจมีข้อมูลที่ไม่ตรงกัน

-- Migrate ข้อมูลเดิมจาก users.role → users.user_category_id
UPDATE users SET user_category_id = 'admin' WHERE role = 'admin' AND user_category_id IS NULL;
UPDATE users SET user_category_id = 'provider' WHERE role = 'provider' AND user_category_id IS NULL;
UPDATE users SET user_category_id = 'consumer' WHERE role = 'consumer' AND user_category_id IS NULL;

-- เพิ่ม FK constraint หลังจาก migrate ข้อมูล
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_user_category_id'
  ) THEN
    ALTER TABLE users ADD CONSTRAINT fk_users_user_category_id
      FOREIGN KEY (user_category_id) REFERENCES user_categories(id);
  END IF;
END $$;
