-- =====================================================
-- Migration: Revoke personal Drug Risk Overrides on termination
-- Purpose: terminated employees must not retain personal overrides;
--          rehired users can create a new personal override later.
-- =====================================================

CREATE OR REPLACE FUNCTION public.revoke_personal_drug_overrides_on_termination()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.is_active = true AND NEW.is_active = false AND NEW.user_id IS NOT NULL THEN
    INSERT INTO public.drug_risk_override_history (
      override_id,
      user_id,
      medication_id,
      fda_risk_status_before,
      sub_category_before,
      custom_risk_code_before,
      is_telemedicine_prohibited_before,
      notes_before,
      action,
      changed_by,
      changed_by_name,
      change_reason
    )
    SELECT
      dro.id,
      dro.user_id,
      dro.medication_id,
      dro.override_fda_risk_status,
      dro.override_sub_category,
      dro.override_custom_risk_code,
      dro.override_is_telemedicine_prohibited,
      dro.override_notes,
      'delete',
      NEW.terminated_by,
      COALESCE(NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''), NULLIF(TRIM(u.username), ''), u.email, 'ระบบ HR'),
      'ยกเลิก Personal Override อัตโนมัติเมื่อพนักงานถูกให้ออก'
    FROM public.drug_risk_overrides dro
    LEFT JOIN public.users u ON u.id = NEW.terminated_by
    WHERE dro.user_id = NEW.user_id;

    DELETE FROM public.drug_risk_overrides
    WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_revoke_personal_drug_overrides_on_termination
  ON public.employees;

CREATE TRIGGER trigger_revoke_personal_drug_overrides_on_termination
  AFTER UPDATE OF is_active ON public.employees
  FOR EACH ROW
  WHEN (OLD.is_active = true AND NEW.is_active = false)
  EXECUTE FUNCTION public.revoke_personal_drug_overrides_on_termination();

-- Backfill existing terminated employees so historical data follows the same rule.
INSERT INTO public.drug_risk_override_history (
  override_id,
  user_id,
  medication_id,
  fda_risk_status_before,
  sub_category_before,
  custom_risk_code_before,
  is_telemedicine_prohibited_before,
  notes_before,
  action,
  changed_by,
  changed_by_name,
  change_reason
)
SELECT
  dro.id,
  dro.user_id,
  dro.medication_id,
  dro.override_fda_risk_status,
  dro.override_sub_category,
  dro.override_custom_risk_code,
  dro.override_is_telemedicine_prohibited,
  dro.override_notes,
  'delete',
  e.terminated_by,
  COALESCE(NULLIF(TRIM(tu.first_name || ' ' || tu.last_name), ''), NULLIF(TRIM(tu.username), ''), tu.email, 'ระบบ HR'),
  'ยกเลิก Personal Override อัตโนมัติสำหรับพนักงานที่ถูกให้ออกแล้ว'
FROM public.drug_risk_overrides dro
JOIN public.employees e
  ON e.user_id = dro.user_id
 AND e.is_active = false
LEFT JOIN public.users tu ON tu.id = e.terminated_by
WHERE NOT EXISTS (
  SELECT 1
  FROM public.drug_risk_override_history h
  WHERE h.override_id = dro.id
    AND h.action = 'delete'
);

DELETE FROM public.drug_risk_overrides dro
WHERE EXISTS (
  SELECT 1
  FROM public.employees e
  WHERE e.user_id = dro.user_id
    AND e.is_active = false
);
