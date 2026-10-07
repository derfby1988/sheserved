-- Phase 21.7.21 P0.4 — audit trail for verification admin configuration
-- (docs/plans/SHARED_VERIFICATION_CORE_PLAN.md, closes risk R8).
--
-- Every admin mutation of verification config (global scope, per-venue
-- controls, provider registry) appends a before/after row to
-- verification_admin_audit. Secrets are never recorded — the provider row
-- stores only the secret-store ref name. The table is RLS-locked and
-- REVOKEd from client roles; reads go through the admin RPC below.

CREATE TABLE IF NOT EXISTS public.verification_admin_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID REFERENCES public.users(id),
  action VARCHAR(60) NOT NULL,
  target_type VARCHAR(40) NOT NULL,
  target_id VARCHAR(120),
  before JSONB,
  after JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_verification_admin_audit_time
  ON public.verification_admin_audit(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_verification_admin_audit_target
  ON public.verification_admin_audit(target_type, target_id,
                                     created_at DESC);

ALTER TABLE public.verification_admin_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.verification_admin_audit
  FROM PUBLIC, anon, authenticated;

-- Internal append helper — callable only from SECURITY DEFINER admin RPCs
-- (EXECUTE is revoked from client roles).
CREATE OR REPLACE FUNCTION public.record_verification_admin_audit(
  p_admin_id UUID,
  p_action VARCHAR,
  p_target_type VARCHAR,
  p_target_id VARCHAR,
  p_before JSONB,
  p_after JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.verification_admin_audit (
    admin_id, action, target_type, target_id, before, after
  ) VALUES (
    p_admin_id, p_action, p_target_type, p_target_id, p_before, p_after
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.record_verification_admin_audit(
  UUID, VARCHAR, VARCHAR, VARCHAR, JSONB, JSONB
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_sports_venue_verify_global_scope(
  p_admin_id UUID,
  p_scope VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before VARCHAR(20);
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_scope NOT IN ('disabled', 'whitelist', 'all') THEN
    RAISE EXCEPTION 'INVALID_VERIFY_POLICY';
  END IF;

  SELECT s.scope INTO v_before
  FROM public.sports_venue_slip_verification_settings s
  WHERE s.singleton_key = 1;

  UPDATE public.sports_venue_slip_verification_settings
  SET scope = p_scope, updated_by = p_admin_id, updated_at = now()
  WHERE singleton_key = 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VERIFY_SETTINGS_NOT_FOUND';
  END IF;

  PERFORM public.record_verification_admin_audit(
    p_admin_id, 'admin_set_sports_venue_verify_global_scope',
    'global_settings', 'sports_venue_slip_verification_settings',
    JSONB_BUILD_OBJECT('scope', v_before),
    JSONB_BUILD_OBJECT('scope', p_scope));

  -- Keep the legacy owner-editor gate in sync while clients migrate to the
  -- explicit auto_verify_allowed field.
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
  v_before JSONB;
  v_after JSONB;
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

  SELECT JSONB_BUILD_OBJECT(
      'allowlisted', v.verify_allowlisted,
      'costBearer', v.verify_cost_bearer,
      'monthlyQuota', v.verify_monthly_quota,
      'verifyTimeoutMinutes', v.verify_timeout_minutes)
    INTO v_before
  FROM public.sports_venues v
  WHERE v.id = p_venue_id;

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

  SELECT JSONB_BUILD_OBJECT(
      'allowlisted', v.verify_allowlisted,
      'costBearer', v.verify_cost_bearer,
      'monthlyQuota', v.verify_monthly_quota,
      'verifyTimeoutMinutes', v.verify_timeout_minutes)
    INTO v_after
  FROM public.sports_venues v
  WHERE v.id = p_venue_id;

  PERFORM public.record_verification_admin_audit(
    p_admin_id, 'admin_set_sports_venue_verify_controls',
    'venue', p_venue_id::VARCHAR, v_before, v_after);
END;
$$;

-- Backwards-compatible adapter. Legacy `all` is interpreted as allowing
-- this one venue; only admin_set_sports_venue_verify_global_scope changes
-- the platform-wide scope. P0.4: also audits which legacy call was used —
-- the delegated controls call writes its own row with the field-level diff.
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
  PERFORM public.record_verification_admin_audit(
    p_admin_id, 'admin_set_sports_venue_verify_policy',
    'venue', p_venue_id::VARCHAR, NULL,
    JSONB_BUILD_OBJECT(
      'verifyScope', p_verify_scope,
      'costBearer', p_verify_cost_bearer,
      'monthlyQuota', p_verify_monthly_quota,
      'verifyTimeoutMinutes', p_verify_timeout_minutes,
      'clearQuota', p_clear_quota,
      'clearTimeout', p_clear_timeout));
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

-- P0.4 version: same adapter gate as 20261016, plus an audit row capturing
-- the provider before/after. The secret-store ref name is auditable; the
-- secret value itself never reaches the database.
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
  v_before JSONB;
  v_after JSONB;
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
  SELECT to_jsonb(p) INTO v_before
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

  SELECT to_jsonb(p) INTO v_after
  FROM public.slip_verification_providers p
  WHERE p.code = p_code;

  PERFORM public.record_verification_admin_audit(
    p_admin_id, 'admin_upsert_slip_verification_provider',
    'provider', p_code, v_before, v_after);
END;
$$;

-- Admin-only read surface for the audit log. targetType/targetId filter is
-- optional; results are newest-first.
CREATE OR REPLACE FUNCTION public.admin_list_verification_admin_audit(
  p_admin_id UUID,
  p_limit INT DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INT;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
  RETURN COALESCE((
    SELECT jsonb_agg(row_data)
    FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', a.id,
        'adminId', a.admin_id,
        'action', a.action,
        'targetType', a.target_type,
        'targetId', a.target_id,
        'before', a.before,
        'after', a.after,
        'createdAt', a.created_at
      ) AS row_data
      FROM public.verification_admin_audit a
      ORDER BY a.created_at DESC, a.id DESC
      LIMIT v_limit
    ) rows
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_verification_admin_audit(
  UUID, INT
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
