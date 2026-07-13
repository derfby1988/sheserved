-- =====================================================
-- Migration: Re-invite, Termination, and Rehire Support
-- Phase C + E prerequisites for rehiring terminated employees
-- Date: 2026-07-13
-- =====================================================

-- =====================================================
-- 1. Termination + rehire eligibility columns on employees
-- =====================================================
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS termination_date DATE,
  ADD COLUMN IF NOT EXISTS termination_reason TEXT,
  ADD COLUMN IF NOT EXISTS terminated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS terminated_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS reinvite_eligible_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS can_reinvite BOOLEAN DEFAULT true;

-- =====================================================
-- 2. Partial unique index: allow one ACTIVE employee per (profession_id, user_id)
--    This is required so a terminated (inactive) employee can be rehired later.
--    Drop the original unique constraint first.
-- =====================================================
ALTER TABLE public.employees
  DROP CONSTRAINT IF EXISTS employees_profession_id_user_id_key;

DROP INDEX IF EXISTS idx_employees_unique_user_profession;

CREATE UNIQUE INDEX IF NOT EXISTS idx_employees_unique_active_user_profession
  ON public.employees (profession_id, user_id)
  WHERE user_id IS NOT NULL AND is_active = true;

-- =====================================================
-- 3. Employment history table for hired / terminated / rehired events
-- =====================================================
CREATE TABLE IF NOT EXISTS public.employee_employment_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  action          TEXT NOT NULL CHECK (action IN ('hired','rehired','terminated')),
  action_date     DATE NOT NULL,
  action_reason   TEXT,
  action_by       UUID REFERENCES public.users(id),
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- RLS: allow read access to all (sensitive data is managed via SECURITY DEFINER RPCs)
ALTER TABLE public.employee_employment_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "employment_history_select" ON public.employee_employment_history;
CREATE POLICY "employment_history_select" ON public.employee_employment_history
  FOR SELECT USING (true);

CREATE INDEX IF NOT EXISTS idx_employee_employment_history_employee ON public.employee_employment_history(employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_employment_history_user ON public.employee_employment_history(user_id, profession_id);

-- =====================================================
-- 4. Add intended_role_name to invitations so accept can assign the correct role
-- =====================================================
ALTER TABLE public.employee_invitations
  ADD COLUMN IF NOT EXISTS intended_role_name TEXT DEFAULT 'staff';

-- =====================================================
-- 5. RPC: Create employee invitation (with rehire + cooldown + can_reinvite checks)
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
  p_expires_at TIMESTAMPTZ DEFAULT NULL,
  p_intended_role_name TEXT DEFAULT 'staff'
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
  v_cooldown_until TIMESTAMPTZ;
  v_can_reinvite BOOLEAN;
BEGIN
  -- Validate: must have at least one target (existing user or email/phone)
  IF p_user_id IS NULL AND p_email IS NULL AND p_phone IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ต้องระบุ user_id หรือ email หรือ phone');
  END IF;

  IF p_full_name IS NULL OR trim(p_full_name) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ต้องระบุชื่อพนักงาน');
  END IF;

  -- Check if user is already an ACTIVE employee in this profession
  IF p_user_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_existing_employee_count
    FROM public.employees
    WHERE profession_id = p_profession_id
      AND user_id = p_user_id
      AND is_active = true;

    IF v_existing_employee_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'ผู้ใช้นี้เป็นพนักงานในองค์กรนี้แล้ว');
    END IF;

    -- Rehire eligibility checks against the (inactive) employee record
    SELECT reinvite_eligible_at, can_reinvite
    INTO v_cooldown_until, v_can_reinvite
    FROM public.employees
    WHERE profession_id = p_profession_id
      AND user_id = p_user_id
      AND is_active = false
    LIMIT 1;

    IF FOUND THEN
      IF v_can_reinvite = false THEN
        RETURN jsonb_build_object('success', false, 'error', 'พนักงานคนนี้ถูกทำเครื่องหมายว่าไม่สามารถรับกลับได้');
      END IF;

      IF v_cooldown_until IS NOT NULL AND v_cooldown_until > now() THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'ยังไม่สามารถรับพนักงานคนนี้กลับได้ (อยู่ในช่วง cooldown)'
        );
      END IF;
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
    status, token, expires_at, intended_role_name
  ) VALUES (
    p_profession_id, p_invited_by, p_user_id, p_email, p_phone,
    p_full_name, p_employee_code, p_department, p_job_title, p_branch_id,
    p_base_salary, p_salary, p_commission_rate, p_provident_fund_rate,
    p_personal_allowance, p_tax_deductible_expenses, p_payment_method,
    p_bank_name, p_bank_account_number,
    'pending', v_token, COALESCE(p_expires_at, now() + interval '7 days'), COALESCE(p_intended_role_name, 'staff')
  ) RETURNING id INTO v_invitation_id;

  RETURN jsonb_build_object(
    'success', true,
    'invitation_id', v_invitation_id,
    'token', v_token
  );
END;
$$;

-- =====================================================
-- 6. Helper: assign employee role from intended_role_name
--    Cleans up inactive roles for the user in this profession first.
-- =====================================================
CREATE OR REPLACE FUNCTION public.assign_employee_role_from_invitation(
  p_profession_id UUID,
  p_user_id UUID,
  p_branch_id UUID,
  p_intended_role_name TEXT,
  p_assigned_by UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role_id UUID;
  v_role_name TEXT;
BEGIN
  -- Find intended role, fallback to staff
  v_role_name := COALESCE(p_intended_role_name, 'staff');

  SELECT or2.id INTO v_role_id
  FROM public.organization_roles or2
  WHERE or2.profession_id = p_profession_id
    AND or2.role_name = v_role_name
  LIMIT 1;

  IF v_role_id IS NULL THEN
    SELECT or2.id INTO v_role_id
    FROM public.organization_roles or2
    WHERE or2.profession_id = p_profession_id
      AND or2.role_name = 'staff'
    LIMIT 1;
    v_role_name := 'staff';
  END IF;

  IF v_role_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ไม่พบ role ที่เหมาะสมในองค์กร');
  END IF;

  -- Clean up inactive roles for this user/profession to avoid piling up stale inactive rows
  DELETE FROM public.employee_roles
  WHERE profession_id = p_profession_id
    AND user_id = p_user_id
    AND is_active = false;

  -- Safety check: do not insert if an active role already exists
  IF EXISTS (
    SELECT 1 FROM public.employee_roles
    WHERE profession_id = p_profession_id
      AND user_id = p_user_id
      AND is_active = true
  ) THEN
    RETURN jsonb_build_object('success', true, 'role_id', v_role_id, 'role_name', v_role_name, 'note', 'active role already exists');
  END IF;

  INSERT INTO public.employee_roles (
    profession_id, user_id, role_id, branch_id, is_active, assigned_by
  ) VALUES (
    p_profession_id, p_user_id, v_role_id, p_branch_id, true, p_assigned_by
  );

  RETURN jsonb_build_object('success', true, 'role_id', v_role_id, 'role_name', v_role_name);
END;
$$;

-- =====================================================
-- 7. RPC: Accept employee invitation (supports reactivation/rehire)
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
  v_existing_employee public.employees%ROWTYPE;
  v_role_result JSONB;
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

  -- Check for existing employee record (active or inactive)
  SELECT * INTO v_existing_employee
  FROM public.employees
  WHERE profession_id = v_invitation.profession_id AND user_id = v_user_id
  LIMIT 1;

  IF FOUND AND v_existing_employee.is_active = true THEN
    RETURN jsonb_build_object('success', false, 'error', 'ผู้ใช้นี้เป็นพนักงานในองค์กรนี้แล้ว');
  END IF;

  IF FOUND AND v_existing_employee.is_active = false THEN
    -- REHIRE: reactivate existing record and clear termination fields
    UPDATE public.employees
    SET is_active = true,
        hire_date = now()::DATE,
        termination_date = NULL,
        termination_reason = NULL,
        terminated_at = NULL,
        terminated_by = NULL,
        reinvite_eligible_at = NULL,
        updated_by = v_user_id,
        updated_at = now()
    WHERE id = v_existing_employee.id
    RETURNING id INTO v_employee_id;

    INSERT INTO public.employee_employment_history
      (employee_id, profession_id, user_id, action, action_date, action_by, notes)
    VALUES
      (v_employee_id, v_invitation.profession_id, v_user_id, 'rehired', now()::DATE, v_invitation.invited_by, 'Re-invited after termination');
  ELSE
    -- NEW HIRE
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

    INSERT INTO public.employee_employment_history
      (employee_id, profession_id, user_id, action, action_date, action_by)
    VALUES
      (v_employee_id, v_invitation.profession_id, v_user_id, 'hired', now()::DATE, v_invitation.invited_by);
  END IF;

  -- Assign role based on intended_role_name (clean inactive roles first)
  v_role_result := public.assign_employee_role_from_invitation(
    v_invitation.profession_id,
    v_user_id,
    v_invitation.branch_id,
    v_invitation.intended_role_name,
    v_invitation.invited_by
  );

  -- Update invitation status
  UPDATE public.employee_invitations
  SET status = 'accepted', user_id = v_user_id, updated_at = now()
  WHERE id = v_invitation.id;

  RETURN jsonb_build_object(
    'success', true,
    'employee_id', v_employee_id,
    'role_result', v_role_result
  );
END;
$$;

-- =====================================================
-- 8. RPC: Terminate employee
-- =====================================================
CREATE OR REPLACE FUNCTION public.terminate_employee(
  p_employee_id UUID,
  p_terminated_by UUID,
  p_termination_reason TEXT DEFAULT NULL,
  p_termination_date DATE DEFAULT NULL,
  p_can_reinvite BOOLEAN DEFAULT true,
  p_reinvite_eligible_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_employee public.employees%ROWTYPE;
BEGIN
  SELECT * INTO v_employee FROM public.employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ไม่พบพนักงาน');
  END IF;

  IF v_employee.is_active = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'พนักงานคนนี้ถูกให้ออกไปแล้ว');
  END IF;

  UPDATE public.employees
  SET is_active = false,
      termination_date = COALESCE(p_termination_date, now()::DATE),
      termination_reason = p_termination_reason,
      terminated_at = now(),
      terminated_by = p_terminated_by,
      can_reinvite = COALESCE(p_can_reinvite, true),
      reinvite_eligible_at = COALESCE(
        p_reinvite_eligible_at,
        now() + interval '30 days'
      ),
      updated_at = now()
  WHERE id = p_employee_id;

  -- Revoke employee_roles
  UPDATE public.employee_roles
  SET is_active = false
  WHERE profession_id = v_employee.profession_id
    AND user_id = v_employee.user_id
    AND is_active = true;

  INSERT INTO public.employee_employment_history
    (employee_id, profession_id, user_id, action, action_date, action_reason, action_by, notes)
  VALUES
    (v_employee.id, v_employee.profession_id, v_employee.user_id, 'terminated', COALESCE(p_termination_date, now()::DATE), p_termination_reason, p_terminated_by, 'Terminated');

  RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================
-- 9. RPC: List available Sheserved users for invite (include terminated employees)
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
      'role', u.role,
      'previous_employee_status', CASE
        WHEN EXISTS (
          SELECT 1 FROM public.employees e
          WHERE e.profession_id = p_profession_id
            AND e.user_id = u.id
            AND e.is_active = false
        ) THEN 'terminated'
        ELSE NULL
      END,
      'termination_date', (SELECT e.termination_date FROM public.employees e
                          WHERE e.profession_id = p_profession_id AND e.user_id = u.id AND e.is_active = false LIMIT 1),
      'termination_reason', (SELECT e.termination_reason FROM public.employees e
                            WHERE e.profession_id = p_profession_id AND e.user_id = u.id AND e.is_active = false LIMIT 1),
      'reinvite_eligible_at', (SELECT e.reinvite_eligible_at FROM public.employees e
                              WHERE e.profession_id = p_profession_id AND e.user_id = u.id AND e.is_active = false LIMIT 1),
      'can_reinvite', (SELECT e.can_reinvite FROM public.employees e
                      WHERE e.profession_id = p_profession_id AND e.user_id = u.id AND e.is_active = false LIMIT 1)
    ))
    FROM public.users u
    WHERE u.is_active = true
      AND NOT EXISTS (
        SELECT 1 FROM public.employees e
        WHERE e.profession_id = p_profession_id
          AND e.user_id = u.id
          AND e.is_active = true
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

-- =====================================================
-- 10. RPC: Invitation history for a user/email/phone
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_invitation_history_for_user(
  p_profession_id UUID,
  p_user_id UUID DEFAULT NULL,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(jsonb_build_object(
      'id', ei.id,
      'status', ei.status,
      'full_name', ei.full_name,
      'job_title', ei.job_title,
      'rejection_reason', ei.rejection_reason,
      'rejected_at', ei.rejected_at,
      'created_at', ei.created_at,
      'expires_at', ei.expires_at,
      'invited_by_name', COALESCE(NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''), u.username, u.email)
    ) ORDER BY ei.created_at DESC)
    FROM public.employee_invitations ei
    LEFT JOIN public.users u ON u.id = ei.invited_by
    WHERE ei.profession_id = p_profession_id
      AND (
        (p_user_id IS NOT NULL AND ei.user_id = p_user_id) OR
        (p_email IS NOT NULL AND ei.email IS NOT NULL AND lower(ei.email) = lower(p_email)) OR
        (p_phone IS NOT NULL AND ei.phone IS NOT NULL AND ei.phone = p_phone)
      )
  );
END;
$$;

-- =====================================================
-- 11. RPC: Ensure owner as employee — also assign owner role if missing
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
  v_owner_role_id UUID;
BEGIN
  -- Get owner: try employee_roles with 'owner' role first, then registration_applications
  SELECT er.user_id INTO v_owner_id
  FROM public.employee_roles er
  JOIN public.organization_roles or2 ON or2.id = er.role_id
  WHERE er.profession_id = p_profession_id
    AND er.is_active = true
    AND or2.role_name = 'owner'
  LIMIT 1;

  IF v_owner_id IS NULL THEN
    SELECT ra.user_id INTO v_owner_id
    FROM public.registration_applications ra
    WHERE ra.profession_id = p_profession_id
      AND ra.status = 'approved'
      AND COALESCE((ra.registration_data->>'is_owner_request')::boolean, false) = true
    ORDER BY ra.updated_at DESC
    LIMIT 1;
  END IF;

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

  -- Already an active employee?
  IF EXISTS (
    SELECT 1 FROM public.employees
    WHERE profession_id = p_profession_id AND user_id = v_owner_id AND is_active = true
  ) THEN
    RETURN jsonb_build_object('success', true, 'employee_id', NULL, 'note', 'owner is already active employee');
  END IF;

  -- Reactivate inactive owner employee record if exists
  SELECT id INTO v_employee_id
  FROM public.employees
  WHERE profession_id = p_profession_id AND user_id = v_owner_id AND is_active = false
  LIMIT 1;

  SELECT email, phone,
         COALESCE(NULLIF(TRIM(first_name || ' ' || last_name), ''), username, email)
  INTO v_owner_email, v_owner_phone, v_owner_name
  FROM public.users
  WHERE id = v_owner_id;

  IF v_employee_id IS NOT NULL THEN
    UPDATE public.employees
    SET is_active = true,
        full_name = COALESCE(v_owner_name, full_name),
        email = COALESCE(v_owner_email, email),
        phone = COALESCE(v_owner_phone, phone),
        termination_date = NULL,
        termination_reason = NULL,
        terminated_at = NULL,
        terminated_by = NULL,
        reinvite_eligible_at = NULL,
        can_reinvite = true,
        updated_at = now()
    WHERE id = v_employee_id;
  ELSE
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
  END IF;

  -- Ensure owner role exists
  SELECT or2.id INTO v_owner_role_id
  FROM public.organization_roles or2
  WHERE or2.profession_id = p_profession_id AND or2.role_name = 'owner'
  LIMIT 1;

  IF v_owner_role_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.employee_roles er
    WHERE er.profession_id = p_profession_id
      AND er.user_id = v_owner_id
      AND er.role_id = v_owner_role_id
      AND er.is_active = true
  ) THEN
    INSERT INTO public.employee_roles (profession_id, user_id, role_id, is_active, assigned_by)
    VALUES (p_profession_id, v_owner_id, v_owner_role_id, true, v_owner_id);
  END IF;

  RETURN jsonb_build_object('success', true, 'employee_id', v_employee_id);
END;
$$;

-- =====================================================
-- 12. Seed default module permissions for staff role
-- =====================================================
INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
SELECT or2.id, m.module_name, 1
FROM public.organization_roles or2
CROSS JOIN LATERAL (VALUES
  ('pos'), ('inventory'), ('hr'), ('crm'), ('read_model')
) AS m(module_name)
WHERE or2.role_name = 'staff'
  AND NOT EXISTS (
    SELECT 1 FROM public.role_module_permissions rmp
    WHERE rmp.role_id = or2.id AND rmp.module_name = m.module_name
  );
