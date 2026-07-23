-- =====================================================
-- Migration: Fix terminate_employee cooldown default
-- Purpose: When p_reinvite_eligible_at is NULL, set reinvite_eligible_at to NULL
--          (no cooldown) instead of defaulting to now() + 30 days.
--          The admin UI now has a date picker; blank = eligible immediately.
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
      reinvite_eligible_at = p_reinvite_eligible_at,
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
