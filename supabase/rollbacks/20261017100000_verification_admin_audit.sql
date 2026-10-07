-- Rollback for 20261017100000_verification_admin_audit.sql
-- Restores the post-20261016 function bodies (adapter gate kept, audit
-- writes removed). The verification_admin_audit table is left in place —
-- it is additive and keeps the history already recorded.
-- Apply this BEFORE rolling back 20261016100000.

CREATE OR REPLACE FUNCTION public.admin_set_sports_venue_verify_global_scope(
  p_admin_id UUID,
  p_scope VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_scope NOT IN ('disabled', 'whitelist', 'all') THEN
    RAISE EXCEPTION 'INVALID_VERIFY_POLICY';
  END IF;

  UPDATE public.sports_venue_slip_verification_settings
  SET scope = p_scope, updated_by = p_admin_id, updated_at = now()
  WHERE singleton_key = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VERIFY_SETTINGS_NOT_FOUND';
  END IF;

  UPDATE public.sports_venues v
  SET verify_scope = CASE p_scope
        WHEN 'disabled' THEN 'disabled'
        WHEN 'all' THEN 'all'
        WHEN 'whitelist' THEN
          CASE WHEN v.verify_allowlisted THEN 'whitelist' ELSE 'disabled' END
      END,
      updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_sports_venue_verify_controls(
  p_admin_id UUID,
  p_venue_id UUID,
  p_allowlisted BOOLEAN DEFAULT NULL,
  p_verify_cost_bearer VARCHAR DEFAULT NULL,
  p_verify_monthly_quota INT DEFAULT NULL,
  p_verify_timeout_minutes INT DEFAULT NULL,
  p_clear_quota BOOLEAN DEFAULT false,
  p_clear_timeout BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope VARCHAR(20);
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_verify_cost_bearer IS NOT NULL
     AND p_verify_cost_bearer NOT IN ('platform', 'owner') THEN
    RAISE EXCEPTION 'INVALID_VERIFY_POLICY';
  END IF;
  IF p_verify_monthly_quota IS NOT NULL AND p_verify_monthly_quota < 0 THEN
    RAISE EXCEPTION 'INVALID_VERIFY_POLICY';
  END IF;
  IF p_verify_timeout_minutes IS NOT NULL
     AND p_verify_timeout_minutes NOT BETWEEN 1 AND 1440 THEN
    RAISE EXCEPTION 'INVALID_VERIFY_POLICY';
  END IF;

  SELECT s.scope INTO v_scope
  FROM public.sports_venue_slip_verification_settings s
  WHERE s.singleton_key = 1
  FOR SHARE;
  IF v_scope IS NULL THEN
    RAISE EXCEPTION 'VERIFY_SETTINGS_NOT_FOUND';
  END IF;

  UPDATE public.sports_venues v
  SET verify_allowlisted = COALESCE(p_allowlisted, v.verify_allowlisted),
      verify_cost_bearer = COALESCE(
        p_verify_cost_bearer, v.verify_cost_bearer),
      verify_monthly_quota = CASE
        WHEN p_clear_quota THEN NULL
        ELSE COALESCE(p_verify_monthly_quota, v.verify_monthly_quota) END,
      verify_timeout_minutes = CASE
        WHEN p_clear_timeout THEN NULL
        ELSE COALESCE(p_verify_timeout_minutes, v.verify_timeout_minutes) END,
      verify_scope = CASE v_scope
        WHEN 'disabled' THEN 'disabled'
        WHEN 'all' THEN 'all'
        WHEN 'whitelist' THEN CASE
          WHEN COALESCE(p_allowlisted, v.verify_allowlisted)
            THEN 'whitelist' ELSE 'disabled' END
      END,
      updated_at = now()
  WHERE v.id = p_venue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_sports_venue_verify_policy(
  p_admin_id UUID,
  p_venue_id UUID,
  p_verify_scope VARCHAR DEFAULT NULL,
  p_verify_cost_bearer VARCHAR DEFAULT NULL,
  p_verify_monthly_quota INT DEFAULT NULL,
  p_verify_timeout_minutes INT DEFAULT NULL,
  p_clear_quota BOOLEAN DEFAULT false,
  p_clear_timeout BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowlisted BOOLEAN;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_verify_scope IS NOT NULL
     AND p_verify_scope NOT IN ('disabled', 'whitelist', 'all') THEN
    RAISE EXCEPTION 'INVALID_VERIFY_POLICY';
  END IF;
  v_allowlisted := CASE p_verify_scope
    WHEN 'disabled' THEN false
    WHEN 'whitelist' THEN true
    WHEN 'all' THEN true
    ELSE NULL END;
  PERFORM public.admin_set_sports_venue_verify_controls(
    p_admin_id, p_venue_id, v_allowlisted, p_verify_cost_bearer,
    p_verify_monthly_quota, p_verify_timeout_minutes,
    p_clear_quota, p_clear_timeout);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_slip_verification_provider(
  p_admin_id UUID,
  p_code VARCHAR,
  p_display_name VARCHAR,
  p_endpoint_url VARCHAR DEFAULT NULL,
  p_api_key_ref VARCHAR DEFAULT NULL,
  p_cost_per_check NUMERIC DEFAULT NULL,
  p_verify_timeout_minutes INT DEFAULT NULL,
  p_capabilities JSONB DEFAULT NULL,
  p_is_enabled BOOLEAN DEFAULT NULL,
  p_priority INT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.slip_verification_providers%ROWTYPE;
  v_adapter VARCHAR(40);
  v_enabled BOOLEAN;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF NULLIF(btrim(COALESCE(p_code, '')), '') IS NULL
     OR length(p_code) > 40 THEN
    RAISE EXCEPTION 'INVALID_PROVIDER';
  END IF;
  IF NULLIF(btrim(COALESCE(p_display_name, '')), '') IS NULL
     OR length(p_display_name) > 120 THEN
    RAISE EXCEPTION 'INVALID_PROVIDER';
  END IF;
  IF p_cost_per_check IS NOT NULL AND p_cost_per_check < 0 THEN
    RAISE EXCEPTION 'INVALID_PROVIDER';
  END IF;
  IF p_verify_timeout_minutes IS NOT NULL
     AND p_verify_timeout_minutes NOT BETWEEN 1 AND 1440 THEN
    RAISE EXCEPTION 'INVALID_PROVIDER';
  END IF;

  SELECT p.* INTO v_existing
  FROM public.slip_verification_providers p
  WHERE p.code = p_code;

  v_adapter := COALESCE(v_existing.adapter_code, lower(p_code));
  v_enabled := COALESCE(p_is_enabled, v_existing.is_enabled, false);
  IF v_enabled AND NOT public.verification_adapter_known(v_adapter) THEN
    RAISE EXCEPTION 'ADAPTER_NOT_AVAILABLE';
  END IF;

  INSERT INTO public.slip_verification_providers (
    code, display_name, endpoint_url, api_key_ref, cost_per_check,
    verify_timeout_minutes, capabilities, is_enabled, priority, notes,
    adapter_code
  ) VALUES (
    p_code, p_display_name, p_endpoint_url, p_api_key_ref,
    COALESCE(p_cost_per_check, 0),
    COALESCE(p_verify_timeout_minutes, 15),
    COALESCE(p_capabilities, '{}'::jsonb),
    COALESCE(p_is_enabled, false),
    COALESCE(p_priority, 100),
    p_notes,
    lower(p_code)
  )
  ON CONFLICT (code) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    endpoint_url = COALESCE(EXCLUDED.endpoint_url,
                            slip_verification_providers.endpoint_url),
    api_key_ref = COALESCE(EXCLUDED.api_key_ref,
                           slip_verification_providers.api_key_ref),
    cost_per_check = COALESCE(EXCLUDED.cost_per_check,
                              slip_verification_providers.cost_per_check),
    verify_timeout_minutes = COALESCE(
      EXCLUDED.verify_timeout_minutes,
      slip_verification_providers.verify_timeout_minutes),
    capabilities = COALESCE(EXCLUDED.capabilities,
                            slip_verification_providers.capabilities),
    is_enabled = COALESCE(EXCLUDED.is_enabled,
                          slip_verification_providers.is_enabled),
    priority = COALESCE(EXCLUDED.priority,
                        slip_verification_providers.priority),
    notes = COALESCE(EXCLUDED.notes, slip_verification_providers.notes),
    adapter_code = COALESCE(slip_verification_providers.adapter_code,
                            lower(EXCLUDED.code)),
    updated_at = now();
END;
$$;

DROP FUNCTION IF EXISTS public.admin_list_verification_admin_audit(
  UUID, INT);
DROP FUNCTION IF EXISTS public.record_verification_admin_audit(
  UUID, VARCHAR, VARCHAR, VARCHAR, JSONB, JSONB);

NOTIFY pgrst, 'reload schema';
