-- Phase 21.7.21 — global verification scope, per-venue allowlist and
-- atomic monthly quota reservation.
--
-- `verify_scope` on sports_venues used to mix global scope and a per-venue
-- switch. Keep it as a compatibility shadow for older owner policy checks;
-- the source of truth is now the singleton scope plus verify_allowlisted.
CREATE TABLE IF NOT EXISTS public.sports_venue_slip_verification_settings (
  singleton_key SMALLINT PRIMARY KEY CHECK (singleton_key = 1),
  scope VARCHAR(20) NOT NULL DEFAULT 'disabled'
    CHECK (scope IN ('disabled', 'whitelist', 'all')),
  updated_by UUID REFERENCES public.users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.sports_venue_slip_verification_settings (
  singleton_key, scope
) VALUES (1, 'disabled')
ON CONFLICT (singleton_key) DO NOTHING;

ALTER TABLE public.sports_venues
  ADD COLUMN IF NOT EXISTS verify_allowlisted BOOLEAN;

UPDATE public.sports_venues
SET verify_allowlisted = (verify_scope IN ('whitelist', 'all'))
WHERE verify_allowlisted IS NULL;

ALTER TABLE public.sports_venues
  ALTER COLUMN verify_allowlisted SET DEFAULT false,
  ALTER COLUMN verify_allowlisted SET NOT NULL;

ALTER TABLE public.slip_verification_usage
  ADD COLUMN IF NOT EXISTS cost_estimate NUMERIC(10,2);

UPDATE public.slip_verification_usage
SET cost_estimate = COALESCE(cost, 0)
WHERE cost_estimate IS NULL;

ALTER TABLE public.slip_verification_usage
  ALTER COLUMN cost_estimate SET DEFAULT 0,
  ALTER COLUMN cost_estimate SET NOT NULL;

ALTER TABLE public.sports_venue_slip_verification_settings
  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sports_venue_slip_verification_settings
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sports_venue_verify_scope_allows(
  p_venue_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT s.scope = 'all'
        OR (s.scope = 'whitelist' AND v.verify_allowlisted)
    FROM public.sports_venue_slip_verification_settings s
    JOIN public.sports_venues v ON v.id = p_venue_id
    WHERE s.singleton_key = 1
  ), false);
$$;
REVOKE EXECUTE ON FUNCTION public.sports_venue_verify_scope_allows(UUID)
  FROM PUBLIC, anon, authenticated;

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

-- Backwards-compatible adapter. Legacy `all` is interpreted as allowing
-- this one venue; only admin_set_sports_venue_verify_global_scope changes
-- the platform-wide scope.
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

-- Apply a consistent per-venue shadow for legacy owner editor/RPC checks.
UPDATE public.sports_venues v
SET verify_scope = CASE s.scope
      WHEN 'disabled' THEN 'disabled'
      WHEN 'all' THEN 'all'
      WHEN 'whitelist' THEN
        CASE WHEN v.verify_allowlisted THEN 'whitelist' ELSE 'disabled' END
    END,
    updated_at = now()
FROM public.sports_venue_slip_verification_settings s
WHERE s.singleton_key = 1;

CREATE OR REPLACE FUNCTION public.sports_venue_guard_auto_verify_policy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue_id UUID;
  v_requirements JSONB;
BEGIN
  IF TG_TABLE_NAME = 'sports_venues' THEN
    v_venue_id := NEW.id;
    v_requirements := NEW.evidence_requirements;
  ELSE
    v_venue_id := NEW.venue_id;
    v_requirements := CASE
      WHEN NEW.evidence_mode = 'custom' THEN NEW.evidence_requirements
      ELSE NULL END;
  END IF;

  IF v_requirements IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_requirements) r
       WHERE r.value->>'review_mode' = 'auto_verify'
     )
     AND NOT public.sports_venue_auto_verify_allowed(v_venue_id) THEN
    RAISE EXCEPTION 'VERIFY_NOT_ENABLED';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sports_venues_auto_verify_guard
  ON public.sports_venues;
CREATE TRIGGER sports_venues_auto_verify_guard
BEFORE INSERT OR UPDATE OF evidence_requirements
ON public.sports_venues
FOR EACH ROW EXECUTE FUNCTION public.sports_venue_guard_auto_verify_policy();

DROP TRIGGER IF EXISTS sports_venue_courts_auto_verify_guard
  ON public.sports_venue_courts;
CREATE TRIGGER sports_venue_courts_auto_verify_guard
BEFORE INSERT OR UPDATE OF evidence_mode, evidence_requirements, venue_id
ON public.sports_venue_courts
FOR EACH ROW EXECUTE FUNCTION public.sports_venue_guard_auto_verify_policy();

-- Owner detail retains the existing payload and adds only the computed gate;
-- no provider, quota or cost configuration is exposed to venue owners.
CREATE OR REPLACE FUNCTION public.get_my_sports_venue_detail(
  p_user_id UUID,
  p_venue_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  SELECT JSONB_BUILD_OBJECT(
    'venue', (to_jsonb(v)
      - 'verify_scope'
      - 'verify_cost_bearer'
      - 'verify_monthly_quota'
      - 'verify_timeout_minutes'
      - 'verify_allowlisted') || JSONB_BUILD_OBJECT(
        'venueUnitLabel', public.sports_venue_unit_label(v.id),
        'auto_verify_allowed', public.sports_venue_auto_verify_allowed(v.id)),

    'owner_status', op.status,
    'member_role', CASE
      WHEN op.user_id = p_user_id THEN 'owner'
      ELSE COALESCE(m.role, 'manager') END,
    'setup_missing', public.sports_venue_setup_missing(v.id),
    'sports', COALESCE((
      SELECT jsonb_agg(to_jsonb(vs)) FROM public.sports_venue_sports vs
      WHERE vs.venue_id = v.id), '[]'::jsonb),
    'courts', COALESCE((
      SELECT jsonb_agg(
        to_jsonb(c) || JSONB_BUILD_OBJECT(
          'unit_label', public.sports_venue_court_unit_label(c.id))
        ORDER BY c.name)
      FROM public.sports_venue_courts c WHERE c.venue_id = v.id), '[]'::jsonb),
    'hours', COALESCE((
      SELECT jsonb_agg(to_jsonb(h) ORDER BY h.day_of_week)
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v.id), '[]'::jsonb),
    'amenities', COALESCE((
      SELECT jsonb_agg(a.amenity_key)
      FROM public.sports_venue_amenities a WHERE a.venue_id = v.id), '[]'::jsonb),
    'photos', COALESCE((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.sort_order)
      FROM public.sports_venue_photos p WHERE p.venue_id = v.id), '[]'::jsonb),
    'terms', (
      SELECT to_jsonb(t) FROM public.sports_venue_terms t
      WHERE t.venue_id = v.id AND t.status = 'active')
  ) INTO v_result
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  LEFT JOIN public.sports_venue_owner_members m
    ON m.venue_id = v.id AND m.user_id = p_user_id AND m.is_active
  WHERE v.id = p_venue_id;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
  RETURN v_result;
END;
$$;

-- Serialize quota check and reservation by locking the venue row. The
-- provider/cost snapshot is written before the transaction releases that
-- lock, so competing workers cannot both pass the monthly hard limit.
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

GRANT EXECUTE ON FUNCTION public.admin_get_sports_venue_verify_global_policy(
  UUID
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_sports_venue_verify_global_scope(
  UUID, VARCHAR
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_sports_venue_verify_controls(
  UUID, UUID, BOOLEAN, VARCHAR, INT, INT, BOOLEAN, BOOLEAN
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_sports_venue_verify_policy(
  UUID, UUID, VARCHAR, VARCHAR, INT, INT, BOOLEAN, BOOLEAN
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_sports_venue_verify_policies(
  UUID
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
