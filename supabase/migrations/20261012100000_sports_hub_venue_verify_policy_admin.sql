-- Phase 21.7.21.6 — admin venue verify-policy control surface (read half).
--
-- `admin_set_sports_venue_verify_policy` already writes the admin-only
-- scope/cost columns, but nothing let the admin control panel read them
-- back: `list_sports_venues_for_review` only returns *pending* venues and
-- carries no provider/quota signal. This RPC lists every venue with the
-- settings the admin owns plus the signals that decide whether turning
-- `auto_verify` on is actually usable:
--
--   enabledProviderCount  how many providers are enabled in the registry
--                         (0 = enabling scope still routes slips to the
--                         owner, never to a provider)
--   usedThisMonth         provider calls consumed this calendar month
--   costThisMonth         cost accrued this month under the bearer
--   lastUsageAt           last attempt for the venue
--
-- Reads are admin-gated; the owner never sees provider/cost configuration.
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
      'verifyScope', COALESCE(v.verify_scope, 'disabled'),
      'costBearer', COALESCE(v.verify_cost_bearer, 'platform'),
      'monthlyQuota', v.verify_monthly_quota,
      'verifyTimeoutMinutes', v.verify_timeout_minutes,
      'hasEvidencePolicy', v.evidence_requirements IS NOT NULL,
      'enabledProviderCount', (
        SELECT count(*) FROM public.slip_verification_providers p
        WHERE p.is_enabled
      ),
      'usedThisMonth', (
        SELECT count(*) FROM public.slip_verification_usage u
        WHERE u.venue_id = v.id
          AND u.created_at >= date_trunc('month', now())
      ),
      'costThisMonth', (
        SELECT COALESCE(sum(u.cost), 0)
        FROM public.slip_verification_usage u
        WHERE u.venue_id = v.id
          AND u.created_at >= date_trunc('month', now())
      ),
      'lastUsageAt', (
        SELECT max(u.created_at) FROM public.slip_verification_usage u
        WHERE u.venue_id = v.id
      )
    ) ORDER BY v.name)
    FROM public.sports_venues v
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_sports_venue_verify_policies(
  UUID
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
