-- Migration: Employee Invitations Table + Owner Auto-create + user_id nullable
-- Phase 3: Invite-Based Onboarding
-- Created: 2026-07-06

-- =====================================================
-- 1. Make employees.user_id nullable for backward compatibility
-- =====================================================

ALTER TABLE public.employees
  ALTER COLUMN user_id DROP NOT NULL;

-- Add partial unique index: one active employee per user per profession
DROP INDEX IF EXISTS idx_employees_unique_user_profession;
CREATE UNIQUE INDEX idx_employees_unique_user_profession
  ON public.employees (profession_id, user_id)
  WHERE user_id IS NOT NULL;

-- =====================================================
-- 2. Create employee_invitations table
-- =====================================================

CREATE TABLE IF NOT EXISTS public.employee_invitations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  invited_by      UUID NOT NULL REFERENCES public.users(id),
  -- user_id is set when inviting an existing Sheserved user
  user_id         UUID REFERENCES public.users(id) ON DELETE CASCADE,
  -- email/phone used when inviting external user (not yet registered)
  email           TEXT,
  phone           TEXT,
  -- employee info to be created upon acceptance
  full_name       TEXT NOT NULL,
  employee_code   TEXT,
  department      TEXT,
  job_title       TEXT,
  branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
  base_salary     DECIMAL(12,2) DEFAULT 0,
  salary          DECIMAL(12,2),
  commission_rate DECIMAL(5,2) DEFAULT 0,
  provident_fund_rate DECIMAL(5,4) DEFAULT 0.03,
  personal_allowance  DECIMAL(12,2) DEFAULT 60000,
  tax_deductible_expenses DECIMAL(12,2) DEFAULT 0,
  payment_method  TEXT DEFAULT 'bank_transfer' CHECK (payment_method IN ('bank_transfer','cash','check')),
  bank_name       TEXT,
  bank_account_number TEXT,

  -- invitation status
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','expired')),
  token           TEXT UNIQUE NOT NULL DEFAULT gen_random_uuid()::text,
  expires_at      TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),

  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),

  -- Constraints
  CONSTRAINT chk_invitation_target CHECK (
    (user_id IS NOT NULL) OR (email IS NOT NULL) OR (phone IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_employee_invitations_profession ON public.employee_invitations(profession_id, status);
CREATE INDEX IF NOT EXISTS idx_employee_invitations_token ON public.employee_invitations(token);
CREATE INDEX IF NOT EXISTS idx_employee_invitations_user ON public.employee_invitations(user_id);

-- Enable RLS
ALTER TABLE public.employee_invitations ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "employee_invitations_select" ON public.employee_invitations;
DROP POLICY IF EXISTS "employee_invitations_insert" ON public.employee_invitations;
DROP POLICY IF EXISTS "employee_invitations_update" ON public.employee_invitations;
DROP POLICY IF EXISTS "employee_invitations_delete" ON public.employee_invitations;

-- Select: anyone in profession can see pending invites (Application Layer filters further)
CREATE POLICY "employee_invitations_select" ON public.employee_invitations
  FOR SELECT USING (true);

-- Insert/Update/Delete: only HR manager/admin of the profession
CREATE POLICY "employee_invitations_insert" ON public.employee_invitations
  FOR INSERT WITH CHECK (app.can_manage_employees(profession_id));

CREATE POLICY "employee_invitations_update" ON public.employee_invitations
  FOR UPDATE USING (app.can_manage_employees(profession_id))
  WITH CHECK (app.can_manage_employees(profession_id));

CREATE POLICY "employee_invitations_delete" ON public.employee_invitations
  FOR DELETE USING (app.can_manage_employees(profession_id));

-- =====================================================
-- 3. Trigger: update updated_at on employee_invitations
-- =====================================================

CREATE OR REPLACE FUNCTION public.set_invitation_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employee_invitations_updated_at ON public.employee_invitations;
CREATE TRIGGER trg_employee_invitations_updated_at
  BEFORE UPDATE ON public.employee_invitations
  FOR EACH ROW EXECUTE FUNCTION public.set_invitation_updated_at();

-- =====================================================
-- 4. RPC: Create employee invitation
-- =====================================================

CREATE OR REPLACE FUNCTION public.invite_employee(
  p_profession_id UUID,
  p_invited_by UUID,
  p_user_id UUID DEFAULT NULL,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_full_name TEXT DEFAULT NULL,
  p_employee_code TEXT DEFAULT NULL,
  p_department TEXT DEFAULT NULL,
  p_job_title TEXT DEFAULT NULL,
  p_branch_id UUID DEFAULT NULL,
  p_base_salary DECIMAL(12,2) DEFAULT 0,
  p_salary DECIMAL(12,2) DEFAULT NULL,
  p_commission_rate DECIMAL(5,2) DEFAULT 0,
  p_provident_fund_rate DECIMAL(5,4) DEFAULT 0.03,
  p_personal_allowance DECIMAL(12,2) DEFAULT 60000,
  p_tax_deductible_expenses DECIMAL(12,2) DEFAULT 0,
  p_payment_method TEXT DEFAULT 'bank_transfer',
  p_bank_name TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_invitation_id UUID;
  v_token UUID;
  v_existing_employee_count INT;
BEGIN
  -- Validate: must have at least one target (existing user or email/phone)
  IF p_user_id IS NULL AND p_email IS NULL AND p_phone IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ต้องระบุ user_id หรือ email หรือ phone');
  END IF;

  IF p_full_name IS NULL OR trim(p_full_name) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ต้องระบุชื่อพนักงาน');
  END IF;

  -- Check if user is already an employee in this profession
  IF p_user_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_existing_employee_count
    FROM public.employees
    WHERE profession_id = p_profession_id AND user_id = p_user_id;

    IF v_existing_employee_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'ผู้ใช้นี้เป็นพนักงานในองค์กรนี้แล้ว');
    END IF;
  END IF;

  -- Check duplicate pending invite for same user/email/phone
  IF EXISTS (
    SELECT 1 FROM public.employee_invitations
    WHERE profession_id = p_profession_id
      AND status = 'pending'
      AND (
        (p_user_id IS NOT NULL AND user_id = p_user_id) OR
        (p_email IS NOT NULL AND email IS NOT NULL AND lower(email) = lower(p_email)) OR
        (p_phone IS NOT NULL AND phone IS NOT NULL AND phone = p_phone)
      )
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'มีคำเชิญที่ค้างอยู่สำหรับผู้ใช้นี้แล้ว');
  END IF;

  v_token := gen_random_uuid();

  INSERT INTO public.employee_invitations (
    profession_id, invited_by, user_id, email, phone,
    full_name, employee_code, department, job_title, branch_id,
    base_salary, salary, commission_rate, provident_fund_rate,
    personal_allowance, tax_deductible_expenses, payment_method,
    bank_name, bank_account_number,
    status, token, expires_at
  ) VALUES (
    p_profession_id, p_invited_by, p_user_id, p_email, p_phone,
    p_full_name, p_employee_code, p_department, p_job_title, p_branch_id,
    p_base_salary, p_salary, p_commission_rate, p_provident_fund_rate,
    p_personal_allowance, p_tax_deductible_expenses, p_payment_method,
    p_bank_name, p_bank_account_number,
    'pending', v_token, COALESCE(p_expires_at, now() + interval '7 days')
  ) RETURNING id INTO v_invitation_id;

  RETURN jsonb_build_object(
    'success', true,
    'invitation_id', v_invitation_id,
    'token', v_token
  );
END;
$$;

-- =====================================================
-- 5. RPC: Accept employee invitation
-- =====================================================

CREATE OR REPLACE FUNCTION public.accept_employee_invitation(
  p_token TEXT,
  p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_invitation public.employee_invitations%ROWTYPE;
  v_user_id UUID;
  v_employee_id UUID;
BEGIN
  SELECT * INTO v_invitation
  FROM public.employee_invitations
  WHERE token = p_token AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'คำเชิญไม่ถูกต้องหรือหมดอายุ');
  END IF;

  IF v_invitation.expires_at < now() THEN
    UPDATE public.employee_invitations
    SET status = 'expired', updated_at = now()
    WHERE id = v_invitation.id;
    RETURN jsonb_build_object('success', false, 'error', 'คำเชิญหมดอายุ');
  END IF;

  -- Determine the user_id
  v_user_id := COALESCE(p_user_id, v_invitation.user_id);
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ต้องระบุ user_id เพื่อยอมรับคำเชิญ');
  END IF;

  -- Check if already an employee
  IF EXISTS (
    SELECT 1 FROM public.employees
    WHERE profession_id = v_invitation.profession_id AND user_id = v_user_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ผู้ใช้นี้เป็นพนักงานในองค์กรนี้แล้ว');
  END IF;

  -- Create employee record
  INSERT INTO public.employees (
    profession_id, user_id, employee_code, full_name,
    department, job_title, branch_id, hire_date,
    salary, base_salary, commission_rate, provident_fund_rate,
    personal_allowance, tax_deductible_expenses, payment_method,
    bank_name, bank_account_number,
    is_active, created_by, updated_by
  ) VALUES (
    v_invitation.profession_id, v_user_id,
    v_invitation.employee_code, v_invitation.full_name,
    v_invitation.department, v_invitation.job_title, v_invitation.branch_id, now()::DATE,
    v_invitation.salary, v_invitation.base_salary, v_invitation.commission_rate, v_invitation.provident_fund_rate,
    v_invitation.personal_allowance, v_invitation.tax_deductible_expenses, v_invitation.payment_method,
    v_invitation.bank_name, v_invitation.bank_account_number,
    true, v_invitation.invited_by, v_user_id
  ) RETURNING id INTO v_employee_id;

  -- Update invitation status
  UPDATE public.employee_invitations
  SET status = 'accepted', user_id = v_user_id, updated_at = now()
  WHERE id = v_invitation.id;

  RETURN jsonb_build_object('success', true, 'employee_id', v_employee_id);
END;
$$;

-- =====================================================
-- 6. RPC: Reject employee invitation
-- =====================================================

CREATE OR REPLACE FUNCTION public.reject_employee_invitation(
  p_token TEXT,
  p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_invitation public.employee_invitations%ROWTYPE;
BEGIN
  SELECT * INTO v_invitation
  FROM public.employee_invitations
  WHERE token = p_token AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'คำเชิญไม่ถูกต้อง');
  END IF;

  IF v_invitation.expires_at < now() THEN
    UPDATE public.employee_invitations
    SET status = 'expired', updated_at = now()
    WHERE id = v_invitation.id;
    RETURN jsonb_build_object('success', false, 'error', 'คำเชิญหมดอายุ');
  END IF;

  UPDATE public.employee_invitations
  SET status = 'rejected',
      rejection_reason = p_rejection_reason,
      rejected_at = now(),
      updated_at = now()
  WHERE id = v_invitation.id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================
-- 7. RPC: Auto-create owner as first employee
-- =====================================================

CREATE OR REPLACE FUNCTION public.ensure_owner_as_employee(
  p_profession_id UUID,
  p_current_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_owner_id UUID;
  v_owner_email TEXT;
  v_owner_phone TEXT;
  v_owner_name TEXT;
  v_employee_id UUID;
BEGIN
  -- Get owner: try employee_roles with 'owner' role first, then registration_applications
  SELECT er.user_id INTO v_owner_id
  FROM public.employee_roles er
  JOIN public.organization_roles or2 ON or2.id = er.role_id
  WHERE er.profession_id = p_profession_id
    AND er.is_active = true
    AND or2.role_name = 'owner'
  LIMIT 1;

  -- Fallback 1: get from registration_applications with is_owner_request
  IF v_owner_id IS NULL THEN
    SELECT ra.user_id INTO v_owner_id
    FROM public.registration_applications ra
    WHERE ra.profession_id = p_profession_id
      AND ra.status = 'approved'
      AND COALESCE((ra.registration_data->>'is_owner_request')::boolean, false) = true
    ORDER BY ra.updated_at DESC
    LIMIT 1;
  END IF;

  -- Fallback 2: use current user (passed explicitly from app) if they have HR management permission
  IF v_owner_id IS NULL THEN
    v_owner_id := COALESCE(p_current_user_id, NULLIF(app.get_current_user_id(), '')::UUID);

    IF v_owner_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.employee_roles er
      JOIN public.organization_roles or2 ON or2.id = er.role_id
      JOIN public.role_module_permissions rmp ON rmp.role_id = or2.id
      WHERE er.user_id = v_owner_id
        AND er.profession_id = p_profession_id
        AND er.is_active = true
        AND rmp.module_name = 'hr'
        AND rmp.access_level >= 2
    ) THEN
      v_owner_id := NULL;
    END IF;
  END IF;

  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ไม่พบเจ้าขององค์กร');
  END IF;

  -- Already an employee?
  IF EXISTS (
    SELECT 1 FROM public.employees
    WHERE profession_id = p_profession_id AND user_id = v_owner_id
  ) THEN
    RETURN jsonb_build_object('success', true, 'employee_id', NULL, 'note', 'owner is already employee');
  END IF;

  SELECT email, phone,
         COALESCE(NULLIF(TRIM(first_name || ' ' || last_name), ''), username, email)
  INTO v_owner_email, v_owner_phone, v_owner_name
  FROM public.users
  WHERE id = v_owner_id;

  INSERT INTO public.employees (
    profession_id, user_id, employee_code, full_name, email, phone,
    hire_date, base_salary, payment_method, is_active,
    created_by, updated_by
  ) VALUES (
    p_profession_id, v_owner_id, 'OWNER001', COALESCE(v_owner_name, 'Owner'),
    v_owner_email, v_owner_phone,
    now()::DATE, 0, 'bank_transfer', true,
    v_owner_id, v_owner_id
  ) RETURNING id INTO v_employee_id;

  RETURN jsonb_build_object('success', true, 'employee_id', v_employee_id);
END;
$$;

-- =====================================================
-- 8. RPC: List available Sheserved users for invite
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_available_users_for_invite(
  p_profession_id UUID,
  p_search TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(jsonb_build_object(
      'id', u.id,
      'full_name', COALESCE(NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''), u.username, u.email),
      'email', u.email,
      'phone', u.phone,
      'role', u.role
    ))
    FROM public.users u
    WHERE u.is_active = true
      AND NOT EXISTS (
        SELECT 1 FROM public.employees e
        WHERE e.profession_id = p_profession_id AND e.user_id = u.id
      )
      AND (
        p_search IS NULL OR
        COALESCE(NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''), '') ILIKE '%' || p_search || '%' OR
        u.username ILIKE '%' || p_search || '%' OR
        u.email ILIKE '%' || p_search || '%' OR
        u.phone ILIKE '%' || p_search || '%'
      )
  );
END;
$$;
