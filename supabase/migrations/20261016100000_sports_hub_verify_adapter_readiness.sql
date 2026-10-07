-- Phase 21.7.21 P0.2 — adapter readiness for the slip provider registry
-- (docs/plans/SHARED_VERIFICATION_CORE_PLAN.md, closes risk R5).
--
-- A provider row may be *enabled* only when the worker ships a matching
-- adapter. Adapter membership is decided by verification_adapter_known(),
-- a compile-time CASE list that only a migration may change — never an
-- admin-editable field. Deploy order rule: the Node adapter ships first,
-- then a migration adds its code here; reversing that order creates a
-- window where the DB selects a provider the worker cannot call.

ALTER TABLE public.slip_verification_providers
  ADD COLUMN IF NOT EXISTS adapter_code VARCHAR(40),
  -- NULL = not bound to any domain yet (P4 routing consumes this).
  ADD COLUMN IF NOT EXISTS supported_domains TEXT[];

-- Existing rows map 1:1 onto the adapter keyed by their registry code.
UPDATE public.slip_verification_providers
SET adapter_code = lower(code)
WHERE adapter_code IS NULL;
UPDATE public.slip_verification_providers
SET supported_domains = ARRAY['sports_booking']
WHERE code = 'slipok' AND supported_domains IS NULL;

-- Compile-time adapter allowlist. Keep in sync with the adapters actually
-- implemented in websocket-server/services/slip-verification-worker.js.
CREATE OR REPLACE FUNCTION public.verification_adapter_known(
  p_adapter_code TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE lower(COALESCE(p_adapter_code, ''))
    WHEN 'slipok' THEN true
    ELSE false
  END;
$$;
REVOKE EXECUTE ON FUNCTION public.verification_adapter_known(TEXT)
  FROM PUBLIC, anon, authenticated;

-- The auto_verify gate must count only providers the worker can actually
-- call — an enabled row without a known adapter must not satisfy it.
CREATE OR REPLACE FUNCTION public.sports_venue_auto_verify_allowed(
  p_venue_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.sports_venue_verify_scope_allows(p_venue_id)
     AND EXISTS (
       SELECT 1 FROM public.slip_verification_providers p
       WHERE p.is_enabled
         AND NULLIF(btrim(p.endpoint_url), '') IS NOT NULL
         AND NULLIF(btrim(p.api_key_ref), '') IS NOT NULL
         AND public.verification_adapter_known(p.adapter_code)
     );
$$;
REVOKE EXECUTE ON FUNCTION public.sports_venue_auto_verify_allowed(UUID)
  FROM PUBLIC, anon, authenticated;

-- Serialize quota check and reservation by locking the venue row. The
-- provider/cost snapshot is written before the transaction releases that
-- lock, so competing workers cannot both pass the monthly hard limit.
-- P0.2: the provider pick additionally requires a known worker adapter.
CREATE OR REPLACE FUNCTION public.worker_claim_sports_venue_slip_verification(
  p_attempt_id VARCHAR,
  p_worker_id VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usage RECORD;
  v_evidence RECORD;
  v_group RECORD;
  v_venue RECORD;
  v_provider RECORD;
  v_global_scope VARCHAR(20);
  v_used INT;
  v_verdict JSONB;
BEGIN
  SELECT u.* INTO v_usage
  FROM public.slip_verification_usage u
  WHERE u.attempt_id = p_attempt_id AND u.result IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  IF v_usage.claimed_at IS NOT NULL
     AND v_usage.claimed_at > now() - INTERVAL '2 minutes' THEN
    RETURN NULL;
  END IF;

  v_verdict := NULL;
  SELECT e.* INTO v_evidence
  FROM public.sports_venue_booking_evidence e
  WHERE e.id = v_usage.evidence_id
  FOR UPDATE;
  IF v_evidence.id IS NULL OR NOT v_evidence.is_current
     OR v_evidence.verification_status <> 'verifying' THEN
    v_verdict := JSONB_BUILD_OBJECT('action', 'skip', 'reason', 'stale');
  ELSE
    SELECT g.* INTO v_group
    FROM public.sports_venue_booking_groups g
    WHERE g.id = v_evidence.booking_group_id
    FOR UPDATE;
    IF v_group.id IS NULL OR v_group.status <> 'awaiting_evidence' THEN
      v_verdict := JSONB_BUILD_OBJECT('action', 'skip', 'reason', 'stale');
    END IF;
  END IF;

  IF v_verdict IS NULL THEN
    -- Keep a consistent lock order: global settings, then venue.
    SELECT s.scope INTO v_global_scope
    FROM public.sports_venue_slip_verification_settings s
    WHERE s.singleton_key = 1
    FOR SHARE;
    SELECT v.* INTO v_venue
    FROM public.sports_venues v
    WHERE v.id = v_group.venue_id
    FOR UPDATE;

    IF COALESCE(v_global_scope, 'disabled') = 'disabled'
       OR (v_global_scope = 'whitelist' AND NOT v_venue.verify_allowlisted)
       OR v_venue.status <> 'approved' THEN
      v_verdict := JSONB_BUILD_OBJECT(
        'action', 'skip', 'reason', 'scope_disabled');
    ELSE
      SELECT p.* INTO v_provider
      FROM public.slip_verification_providers p
      WHERE p.is_enabled
        AND NULLIF(btrim(p.endpoint_url), '') IS NOT NULL
        AND NULLIF(btrim(p.api_key_ref), '') IS NOT NULL
        AND public.verification_adapter_known(p.adapter_code)
      ORDER BY p.priority, p.code
      LIMIT 1;
      IF v_provider.code IS NULL THEN
        v_verdict := JSONB_BUILD_OBJECT(
          'action', 'skip', 'reason', 'no_provider');
      ELSIF v_venue.verify_monthly_quota IS NOT NULL THEN
        SELECT count(*) INTO v_used
        FROM public.slip_verification_usage u
        WHERE u.venue_id = v_group.venue_id
          AND u.provider_code IS NOT NULL
          AND u.created_at >= date_trunc('month', now());
        IF v_used >= v_venue.verify_monthly_quota THEN
          v_verdict := JSONB_BUILD_OBJECT(
            'action', 'skip', 'reason', 'quota_exceeded');
        END IF;
      END IF;
    END IF;
  END IF;

  IF v_verdict IS NOT NULL THEN
    IF v_verdict->>'reason' <> 'stale' THEN
      UPDATE public.sports_venue_booking_evidence
      SET verification_status = 'pending',
          verification_meta = verification_meta
            || JSONB_BUILD_OBJECT('providerSkipped', v_verdict->>'reason'),
          updated_at = now()
      WHERE id = v_evidence.id;
      UPDATE public.slip_verification_usage
      SET result = 'unavailable', finished_at = now()
      WHERE id = v_usage.id;
    ELSE
      UPDATE public.slip_verification_usage
      SET result = 'failed', finished_at = now()
      WHERE id = v_usage.id;
    END IF;
    RETURN v_verdict;
  END IF;

  UPDATE public.slip_verification_usage
  SET claimed_at = now(), claimed_by = p_worker_id,
      provider_code = v_provider.code,
      cost_estimate = COALESCE(v_provider.cost_per_check, 0)
  WHERE id = v_usage.id;

  RETURN JSONB_BUILD_OBJECT(
    'action', 'verify',
    'attemptId', v_usage.attempt_id,
    'evidenceId', v_evidence.id,
    'storagePath', v_evidence.storage_path,
    'mime', v_evidence.mime,
    'groupId', v_group.id,
    'venueId', v_group.venue_id,
    'expectedAmount', v_group.total_amount_snapshot,
    'currency', v_group.currency,
    'provider', JSONB_BUILD_OBJECT(
      'code', v_provider.code,
      'endpointUrl', v_provider.endpoint_url,
      'apiKeyRef', v_provider.api_key_ref,
      'timeoutMinutes', v_provider.verify_timeout_minutes,
      'capabilities', v_provider.capabilities),
    'venueVerifyTimeoutMinutes', v_venue.verify_timeout_minutes);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_sports_venue_verify_global_policy(
  p_admin_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope VARCHAR(20);
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  SELECT s.scope INTO v_scope
  FROM public.sports_venue_slip_verification_settings s
  WHERE s.singleton_key = 1;
  RETURN JSONB_BUILD_OBJECT(
    'scope', COALESCE(v_scope, 'disabled'),
    'approvedVenueCount', (
      SELECT count(*) FROM public.sports_venues v
      WHERE v.status = 'approved'),
    'allowlistedVenueCount', (
      SELECT count(*) FROM public.sports_venues v
      WHERE v.verify_allowlisted),
    'configuredProviderCount', (
      SELECT count(*) FROM public.slip_verification_providers p
      WHERE p.is_enabled
        AND NULLIF(btrim(p.endpoint_url), '') IS NOT NULL
        AND NULLIF(btrim(p.api_key_ref), '') IS NOT NULL
        AND public.verification_adapter_known(p.adapter_code))
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_sports_venue_verify_policies(
  p_admin_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(JSONB_BUILD_OBJECT(
      'venueId', v.id,
      'name', v.name,
      'status', v.status,
      'globalScope', s.scope,
      'isAllowlisted', v.verify_allowlisted,
      'isAutoVerifyAllowed',
        v.status = 'approved'
        AND public.sports_venue_auto_verify_allowed(v.id),
      'costBearer', v.verify_cost_bearer,
      'monthlyQuota', v.verify_monthly_quota,
      'verifyTimeoutMinutes', v.verify_timeout_minutes,
      'hasEvidencePolicy', v.evidence_requirements IS NOT NULL,
      'configuredProviderCount', provider_stats.provider_count,
      'callsThisMonth', COALESCE(usage_stats.calls_this_month, 0),
      'pendingCallsThisMonth', COALESCE(usage_stats.pending_calls, 0),
      'costEstimateThisMonth', COALESCE(usage_stats.cost_estimate, 0),
      'lastCallAt', usage_stats.last_call_at
    ) ORDER BY v.name)
    FROM public.sports_venues v
    CROSS JOIN public.sports_venue_slip_verification_settings s
    CROSS JOIN LATERAL (
      SELECT count(*)::INT AS provider_count
      FROM public.slip_verification_providers p
      WHERE p.is_enabled
        AND NULLIF(btrim(p.endpoint_url), '') IS NOT NULL
        AND NULLIF(btrim(p.api_key_ref), '') IS NOT NULL
        AND public.verification_adapter_known(p.adapter_code)
    ) provider_stats
    LEFT JOIN LATERAL (
      SELECT count(*) FILTER (
               WHERE u.provider_code IS NOT NULL)::INT AS calls_this_month,
             count(*) FILTER (
               WHERE u.provider_code IS NOT NULL AND u.result IS NULL)::INT
               AS pending_calls,
             COALESCE(sum(u.cost_estimate) FILTER (
               WHERE u.provider_code IS NOT NULL), 0)::NUMERIC
               AS cost_estimate,
             max(u.claimed_at) FILTER (
               WHERE u.provider_code IS NOT NULL) AS last_call_at
      FROM public.slip_verification_usage u
      WHERE u.venue_id = v.id
        AND u.created_at >= date_trunc('month', now())
    ) usage_stats ON true
    WHERE s.singleton_key = 1
  ), '[]'::jsonb);
END;
$$;

-- Admin provider registry: API keys are referenced by secret-store name
-- only; disabling every provider freezes auto_verify without touching
-- venue policies (kill switch). P0.2: enabling is refused when no worker
-- adapter knows the provider code (ADAPTER_NOT_AVAILABLE); the row can
-- still be saved disabled so a future provider can be staged in advance.
-- adapter_code derives from the registry code and is never admin-editable
-- — remapping happens via migration only.
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
    -- Preserve an adapter mapping set by migration; self-heal NULLs.
    adapter_code = COALESCE(slip_verification_providers.adapter_code,
                            lower(EXCLUDED.code)),
    updated_at = now();
END;
$$;

-- Admin/provider detail never reaches public views; an authenticated list
-- for admins so the control panel can render state without secret refs.
-- adapterKnown lets the UI disable the toggle instead of letting admins
-- enable a provider the worker cannot call.
CREATE OR REPLACE FUNCTION public.admin_list_slip_verification_providers(
  p_admin_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(JSONB_BUILD_OBJECT(
      'code', p.code,
      'displayName', p.display_name,
      'endpointUrl', p.endpoint_url,
      'hasApiKey', p.api_key_ref IS NOT NULL,
      'costPerCheck', p.cost_per_check,
      'verifyTimeoutMinutes', p.verify_timeout_minutes,
      'capabilities', p.capabilities,
      'isEnabled', p.is_enabled,
      'priority', p.priority,
      'notes', p.notes,
      'adapterCode', p.adapter_code,
      'adapterKnown', public.verification_adapter_known(p.adapter_code),
      'supportedDomains', to_jsonb(p.supported_domains),
      'updatedAt', p.updated_at
    ) ORDER BY p.priority, p.code)
    FROM public.slip_verification_providers p
  ), '[]'::jsonb);
END;
$$;
