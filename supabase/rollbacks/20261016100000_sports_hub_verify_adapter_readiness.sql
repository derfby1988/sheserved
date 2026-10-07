-- Rollback for 20261016100000_sports_hub_verify_adapter_readiness.sql
-- Restores the pre-adapter-gate function bodies (20261013/20261010
-- definitions). The adapter_code/supported_domains columns are left in
-- place — they are additive and harmless once nothing reads them.
-- If 20261017100000 was applied, roll it back FIRST.

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
     );
$$;
REVOKE EXECUTE ON FUNCTION public.sports_venue_auto_verify_allowed(UUID)
  FROM PUBLIC, anon, authenticated;

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
        AND NULLIF(btrim(p.api_key_ref), '') IS NOT NULL)
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

  INSERT INTO public.slip_verification_providers (
    code, display_name, endpoint_url, api_key_ref, cost_per_check,
    verify_timeout_minutes, capabilities, is_enabled, priority, notes
  ) VALUES (
    p_code, p_display_name, p_endpoint_url, p_api_key_ref,
    COALESCE(p_cost_per_check, 0),
    COALESCE(p_verify_timeout_minutes, 15),
    COALESCE(p_capabilities, '{}'::jsonb),
    COALESCE(p_is_enabled, false),
    COALESCE(p_priority, 100),
    p_notes
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
    updated_at = now();
END;
$$;

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
      'updatedAt', p.updated_at
    ) ORDER BY p.priority, p.code)
    FROM public.slip_verification_providers p
  ), '[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.verification_adapter_known(TEXT);

NOTIFY pgrst, 'reload schema';
