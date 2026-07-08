-- Migration: Tighten RLS for employees table + add audit trail support
-- Phase 1: Security & Authorization
-- Created: 2026-07-06
--
-- หมายเหตุ: โปรเจกต์ใช้ custom auth ผ่าน app.get_current_user_id()
-- ไม่ได้ใช้ Supabase auth.uid()
-- App ต้องเรียก SELECT set_config('app.user_id', $userId, true) ก่อน query
-- ถ้า app.user_id ไม่ถูก set จะ fallback เป็น true (backward compatible)
-- เมื่อ App เริ่ม set app.user_id แล้ว RLS จะบังคับอัตโนมัติ

-- =====================================================
-- 1. Helper function: ตรวจสอบว่า user เป็น owner/admin ของ profession หรือไม่
-- =====================================================

CREATE OR REPLACE FUNCTION app.can_manage_employees(p_profession_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id TEXT;
  v_role TEXT;
  v_has_permission BOOLEAN := false;
BEGIN
  v_user_id := app.get_current_user_id();

  -- Backward compat: ถ้า app.user_id ไม่ถูก set ให้อนุญาต (Application Layer ควบคุมแทน)
  IF v_user_id IS NULL OR v_user_id = '' THEN
    RETURN true;
  END IF;

  -- ตรวจสอบว่าเป็น platform admin หรือไม่
  SELECT role INTO v_role FROM public.users WHERE id = v_user_id LIMIT 1;
  IF v_role = 'admin' THEN
    RETURN true;
  END IF;

  -- ตรวจสอบว่ามี employee_roles ที่มี permission จัดการ HR ใน profession นี้หรือไม่
  SELECT EXISTS(
    SELECT 1
    FROM public.employee_roles er
    JOIN public.role_module_permissions rmp ON rmp.role_id = er.role_id
    WHERE er.user_id = v_user_id
      AND er.profession_id = p_profession_id
      AND er.is_active = true
      AND rmp.module_name = 'hr'
      AND rmp.access_level >= 2
  ) INTO v_has_permission;

  RETURN v_has_permission;
EXCEPTION
  WHEN OTHERS THEN
    RETURN false;
END;
$$;

-- =====================================================
-- 2. ปรับ RLS policies ของ employees
-- =====================================================

-- Drop old policies
DROP POLICY IF EXISTS "employees_select" ON public.employees;
DROP POLICY IF EXISTS "employees_modify" ON public.employees;

-- Select: อนุญาตให้ดูได้ (Application Layer กรอง profession_id)
CREATE POLICY "employees_select" ON public.employees
  FOR SELECT USING (true);

-- Modify: ตรวจสอบสิทธิ์ owner/admin ของ profession
-- ใช้ profession_id จาก row ที่กำลัง insert/update/delete
CREATE POLICY "employees_insert" ON public.employees
  FOR INSERT WITH CHECK (app.can_manage_employees(profession_id));

CREATE POLICY "employees_update" ON public.employees
  FOR UPDATE USING (app.can_manage_employees(profession_id))
  WITH CHECK (app.can_manage_employees(profession_id));

CREATE POLICY "employees_delete" ON public.employees
  FOR DELETE USING (app.can_manage_employees(profession_id));

-- =====================================================
-- 3. Trigger: กำหนด created_by/updated_by อัตโนมัติ
-- =====================================================

CREATE OR REPLACE FUNCTION public.set_employee_audit_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id TEXT;
BEGIN
  v_user_id := app.get_current_user_id();

  IF v_user_id IS NOT NULL AND v_user_id != '' THEN
    IF TG_OP = 'INSERT' THEN
      NEW.created_by := v_user_id::UUID;
    END IF;
    NEW.updated_by := v_user_id::UUID;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employees_audit ON public.employees;
CREATE TRIGGER trg_employees_audit
  BEFORE INSERT OR UPDATE ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.set_employee_audit_fields();
