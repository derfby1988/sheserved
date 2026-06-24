-- Migration: Add RLS policies for user_categories (with custom auth)
-- Phase 2.6: Role Management Refactor
-- Created: 2026-06-24
--
-- หมายเหตุ: โปรเจกต์นี้ไม่ได้ใช้ Supabase Auth
-- ใช้ custom function app.get_current_user_id() แทน auth.uid()
-- App ต้องเรียก SELECT set_config('app.user_id', $userId, true) ก่อน query ที่ต้องการ RLS

-- =====================================================
-- 0. Create app schema if not exists
-- =====================================================

CREATE SCHEMA IF NOT EXISTS app;

-- =====================================================
-- 1. Custom Auth Helper Functions
-- =====================================================

-- ฟังก์ชันดึง user_id ปัจจุบันจาก session variable
-- App ต้อง set ก่อน query: SELECT set_config('app.user_id', '<user_id>', true);
CREATE OR REPLACE FUNCTION app.get_current_user_id()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- อ่านจาก custom session variable (ตั้งโดย App ก่อน query)
  RETURN current_setting('app.user_id', true);
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- ฟังก์ชันตรวจสอบว่า user ปัจจุบันเป็น admin หรือไม่
CREATE OR REPLACE FUNCTION app.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id TEXT;
  v_role TEXT;
BEGIN
  v_user_id := app.get_current_user_id();
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT role INTO v_role
  FROM users
  WHERE id = v_user_id
  LIMIT 1;

  RETURN v_role = 'admin';
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$$;

-- ฟังก์ชันตรวจสอบว่า user ปัจจุบันเป็น provider หรือไม่
CREATE OR REPLACE FUNCTION app.is_provider()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id TEXT;
  v_role TEXT;
BEGIN
  v_user_id := app.get_current_user_id();
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT role INTO v_role
  FROM users
  WHERE id = v_user_id
  LIMIT 1;

  RETURN v_role IN ('provider', 'admin');
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$$;

-- =====================================================
-- 2. RLS Policies สำหรับ user_categories
-- =====================================================

-- Enable RLS
ALTER TABLE user_categories ENABLE ROW LEVEL SECURITY;

-- ทุกคนสามารถอ่านได้ (public read)
DROP POLICY IF EXISTS "Anyone can read user_categories" ON user_categories;
CREATE POLICY "Anyone can read user_categories"
ON user_categories FOR SELECT
TO public
USING (true);

-- Admin เท่านั้นที่สามารถแก้ไขได้
DROP POLICY IF EXISTS "Only admins can modify user_categories" ON user_categories;
CREATE POLICY "Only admins can modify user_categories"
ON user_categories FOR ALL
TO authenticated
USING (app.is_admin())
WITH CHECK (app.is_admin());
