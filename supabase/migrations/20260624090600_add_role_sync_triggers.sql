-- Migration: Add sync triggers for role data consistency
-- Phase 2.7: Role Management Refactor
-- Created: 2026-06-24

-- =====================================================
-- Trigger 1: เมื่อ user_category_id เปลี่ยน → sync กับ role
-- =====================================================
CREATE OR REPLACE FUNCTION sync_role_from_category()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- Sync role จาก user_category_id (ถ้ามี)
  IF NEW.user_category_id IS NOT NULL THEN
    NEW.role = NEW.user_category_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_sync_role_from_category ON users;
CREATE TRIGGER trigger_sync_role_from_category
BEFORE UPDATE OF user_category_id ON users
FOR EACH ROW
WHEN (NEW.user_category_id IS DISTINCT FROM OLD.user_category_id)
EXECUTE FUNCTION sync_role_from_category();

-- =====================================================
-- Trigger 2: เมื่อ profession_id เปลี่ยน → sync กับ role (สำหรับแนวทาง B)
-- =====================================================
CREATE OR REPLACE FUNCTION sync_role_from_profession()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_category TEXT;
BEGIN
  IF NEW.profession_id IS NOT NULL THEN
    SELECT category INTO v_category
    FROM professions
    WHERE id = NEW.profession_id;

    IF v_category IS NOT NULL THEN
      NEW.role = v_category;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_sync_role_from_profession ON users;
CREATE TRIGGER trigger_sync_role_from_profession
BEFORE UPDATE OF profession_id ON users
FOR EACH ROW
WHEN (NEW.profession_id IS DISTINCT FROM OLD.profession_id)
EXECUTE FUNCTION sync_role_from_profession();
