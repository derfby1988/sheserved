-- Phase 21.7.21.3–21.7.21.6 — client and worker surface for
-- evidence-gated booking.
--
-- Requires 20261010100000_sports_hub_booking_evidence.sql. Adds:
--   * a sanitized evidence-policy surface for the booking dialog
--     (requirements checklist + deadline knobs; the payment destination is
--     only disclosed inside an owned awaiting_evidence group)
--   * short-lived read tokens so private evidence objects can be fetched
--     through the Node backend (the bucket keeps no SELECT policy)
--   * worker claim/apply RPCs for the slip-verification outbox — callable
--     by the service role only, never by app clients
--   * richer group/listing payloads (claims, refund cases, money ledger)
--     so booker and owner UIs do not need direct table access

-- ===============
-- Worker lease columns on the durable outbox
-- ===============
ALTER TABLE public.slip_verification_usage
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS claimed_by VARCHAR(80);

-- ===============
-- Evidence read tokens
-- ===============
-- Private-bucket objects are read via a Node endpoint that redeems these
-- tokens with the service role; the bucket itself stays INSERT-only.
CREATE TABLE IF NOT EXISTS public.sports_venue_booking_evidence_read_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash VARCHAR(64) NOT NULL UNIQUE,
  evidence_path VARCHAR(500) NOT NULL,
  granted_to UUID NOT NULL REFERENCES public.users(id),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sports_venue_evidence_read_tokens_expiry
  ON public.sports_venue_booking_evidence_read_tokens(expires_at);
ALTER TABLE public.sports_venue_booking_evidence_read_tokens
  ENABLE ROW LEVEL SECURITY;

-- Mint a read token for a private evidence object. p_path must live under
-- `groups/<group uuid>/…`; the caller must own the group or manage its
-- venue. Returns {token, expiresAt}; the raw token is never stored.
CREATE OR REPLACE FUNCTION public.mint_sports_venue_evidence_read_token(
  p_user_id UUID,
  p_path VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id UUID;
  v_venue_id UUID;
  v_group_owner UUID;
  v_token VARCHAR;
  v_expires TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_path IS NULL OR length(p_path) > 500
     OR p_path NOT LIKE 'groups/%' THEN
    RAISE EXCEPTION 'INVALID_STORAGE_PATH';
  END IF;
  BEGIN
    v_group_id := (split_part(p_path, '/', 2))::UUID;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'INVALID_STORAGE_PATH';
  END;
  SELECT g.user_id, g.venue_id INTO v_group_owner, v_venue_id
  FROM public.sports_venue_booking_groups g
  WHERE g.id = v_group_id;
  IF v_group_owner IS NULL THEN
    RAISE EXCEPTION 'INVALID_STORAGE_PATH';
  END IF;
  IF p_user_id <> v_group_owner
     AND NOT public.is_sports_venue_manager(v_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  -- Opportunistic sweep of expired tokens (bounded work).
  DELETE FROM public.sports_venue_booking_evidence_read_tokens
  WHERE expires_at < now() - INTERVAL '1 day';

  v_token := replace(
    gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_expires := now() + INTERVAL '10 minutes';
  INSERT INTO public.sports_venue_booking_evidence_read_tokens (
    token_hash, evidence_path, granted_to, expires_at
  ) VALUES (md5(v_token), p_path, p_user_id, v_expires);

  RETURN JSONB_BUILD_OBJECT('token', v_token, 'expiresAt', v_expires);
END;
$$;

-- Service-role resolver for the Node read endpoint. SECURITY DEFINER so the
-- service role needs no table grant on the token table.
CREATE OR REPLACE FUNCTION public.get_sports_venue_evidence_object_for_token(
  p_token_hash VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_path VARCHAR;
BEGIN
  SELECT t.evidence_path INTO v_path
  FROM public.sports_venue_booking_evidence_read_tokens t
  WHERE t.token_hash = p_token_hash
    AND t.expires_at > now();
  IF v_path IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN JSONB_BUILD_OBJECT('path', v_path);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_sports_venue_evidence_object_for_token(
  VARCHAR
) FROM PUBLIC, anon, authenticated;

-- ===============
-- Booker-facing policy surface (sanitized: no payment destination, no
-- provider/cost internals). Returns NULL when evidence booking is off.
-- ===============
CREATE OR REPLACE FUNCTION public.get_sports_venue_court_evidence_surface(
  p_court_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_policy JSONB;
  v_approved BOOLEAN;
BEGIN
  SELECT (v.status = 'approved') INTO v_approved
  FROM public.sports_venue_courts c
  JOIN public.sports_venues v ON v.id = c.venue_id
  WHERE c.id = p_court_id AND c.is_active;
  IF NOT COALESCE(v_approved, false) THEN
    RETURN NULL;
  END IF;
  v_policy := public.sports_venue_court_evidence_policy(p_court_id);
  IF v_policy IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN JSONB_BUILD_OBJECT(
    'source', v_policy->>'source',
    'requirements', v_policy->'requirements',
    'deadlineMode', v_policy->>'deadline_mode',
    'minutes',
      NULLIF(v_policy->>'minutes', '')::INT,
    'deadlineTime', v_policy->>'deadline_time',
    'minGraceMinutes',
      NULLIF(v_policy->>'min_grace_minutes', '')::INT,
    'ownerDecisionMinutes',
      NULLIF(v_policy->>'owner_decision_minutes', '')::INT,
    'ownerApprovalDeadlineEnabled',
      (v_policy->>'owner_approval_deadline_enabled')::BOOLEAN,
    'maxHoldsPerUser',
      NULLIF(v_policy->>'max_holds_per_user', '')::INT,
    'requiresPaymentSlip', EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_policy->'requirements') r
      WHERE r.value->>'kind' = 'payment_slip'
        AND (r.value->>'required')::boolean));
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sports_venue_court_evidence_surface(
  UUID
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mint_sports_venue_evidence_read_token(
  UUID, VARCHAR
) TO anon, authenticated;

-- ===============
-- Worker outbox RPCs (service role only)
-- ===============

-- Atomically lease one queued verification attempt. Returns NULL when the
-- row is already finished or freshly claimed; a JSONB skip verdict when the
-- attempt can never be verified (evidence falls back to owner review);
-- otherwise the payload the worker needs for one provider call.
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
  -- Fresh lease held by another worker.
  IF v_usage.claimed_at IS NOT NULL
     AND v_usage.claimed_at > now() - INTERVAL '2 minutes' THEN
    RETURN NULL;
  END IF;

  -- Non-callable verdicts still settle the attempt so it never loops.
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
    SELECT v.verify_scope, v.verify_cost_bearer, v.verify_monthly_quota,
           v.verify_timeout_minutes
      INTO v_venue
    FROM public.sports_venues v
    WHERE v.id = v_group.venue_id;
    IF v_venue.verify_scope NOT IN ('whitelist', 'all') THEN
      v_verdict := JSONB_BUILD_OBJECT(
        'action', 'skip', 'reason', 'scope_disabled');
    ELSE
      SELECT p.* INTO v_provider
      FROM public.slip_verification_providers p
      WHERE p.is_enabled
        AND p.endpoint_url IS NOT NULL AND p.api_key_ref IS NOT NULL
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
        -- Quota counts one billed check per attempt row; worker retries of
        -- the same attempt reuse this row and are not double-counted.
        IF v_used >= v_venue.verify_monthly_quota THEN
          v_verdict := JSONB_BUILD_OBJECT(
            'action', 'skip', 'reason', 'quota_exceeded');
        END IF;
      END IF;
    END IF;
  END IF;

  IF v_verdict IS NOT NULL THEN
    IF v_verdict->>'reason' <> 'stale' THEN
      -- Scope/kill-switch/quota blocks route the slip to owner review.
      UPDATE public.sports_venue_booking_evidence
      SET verification_status = 'pending',
          verification_meta = verification_meta
            || JSONB_BUILD_OBJECT('providerSkipped',
                                  v_verdict->>'reason'),
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
      provider_code = v_provider.code
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

-- Commit a provider outcome. 'verified' additionally requires an exact
-- amount match against the group total snapshot and a unique transaction
-- fingerprint; every non-verified outcome routes the slip to owner review
-- (verification_status 'pending') — provider failures never auto-release.
-- Idempotent: a settled attempt returns 'already_done'.
CREATE OR REPLACE FUNCTION public.worker_apply_sports_venue_slip_verification(
  p_attempt_id VARCHAR,
  p_provider_code VARCHAR,
  p_result VARCHAR,
  p_amount NUMERIC DEFAULT NULL,
  p_fingerprint VARCHAR DEFAULT NULL,
  p_provider_ref VARCHAR DEFAULT NULL,
  p_meta JSONB DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usage RECORD;
  v_evidence RECORD;
  v_group RECORD;
  v_state JSONB;
  v_result VARCHAR;
  v_fp VARCHAR;
  v_duplicate BOOLEAN := false;
  v_cost NUMERIC := 0;
BEGIN
  IF p_result NOT IN ('verified', 'failed', 'unavailable', 'timeout') THEN
    RAISE EXCEPTION 'INVALID_VERIFY_RESULT';
  END IF;

  SELECT u.* INTO v_usage
  FROM public.slip_verification_usage u
  WHERE u.attempt_id = p_attempt_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'unknown_attempt';
  END IF;
  IF v_usage.result IS NOT NULL THEN
    RETURN 'already_done';
  END IF;

  SELECT e.* INTO v_evidence
  FROM public.sports_venue_booking_evidence e
  WHERE e.id = v_usage.evidence_id
  FOR UPDATE;
  IF v_evidence.id IS NULL OR NOT v_evidence.is_current
     OR v_evidence.verification_status <> 'verifying' THEN
    UPDATE public.slip_verification_usage
    SET result = 'failed', finished_at = now()
    WHERE id = v_usage.id;
    RETURN 'evidence_stale';
  END IF;

  SELECT g.* INTO v_group
  FROM public.sports_venue_booking_groups g
  WHERE g.id = v_evidence.booking_group_id
  FOR UPDATE;

  v_result := p_result;
  v_fp := NULLIF(p_fingerprint, '');

  -- A verified verdict requires the provider fingerprint and an exact
  -- aggregate amount match; anything else is downgraded to failed.
  IF v_result = 'verified' THEN
    IF v_fp IS NULL OR length(v_fp) > 128
       OR v_group.total_amount_snapshot IS NULL
       OR p_amount IS NULL
       OR p_amount <> v_group.total_amount_snapshot THEN
      v_result := 'failed';
    END IF;
  END IF;

  IF v_fp IS NULL THEN
    v_fp := 'unverified:' || v_evidence.id::text;
  END IF;

  BEGIN
    INSERT INTO public.slip_verification_transactions (
      fingerprint, booking_group_id, evidence_id, provider_code, amount
    ) VALUES (
      v_fp, v_group.id, v_evidence.id,
      NULLIF(p_provider_code, ''), p_amount
    );
  EXCEPTION WHEN unique_violation THEN
    v_duplicate := true;
  END;
  IF v_duplicate THEN
    v_result := 'failed';
  END IF;

  SELECT COALESCE(p.cost_per_check, 0) INTO v_cost
  FROM public.slip_verification_providers p
  WHERE p.code = p_provider_code;

  IF v_result = 'verified' THEN
    UPDATE public.sports_venue_booking_evidence
    SET verification_status = 'verified',
        provider_code = NULLIF(p_provider_code, ''),
        provider_ref = NULLIF(p_provider_ref, ''),
        verification_meta = COALESCE(p_meta, '{}'::jsonb),
        updated_at = now()
    WHERE id = v_evidence.id;
  ELSE
    -- Provider failure/doubt goes to the owner review queue. The slip is
    -- still decidable; housekeeping still applies the evidence deadline.
    UPDATE public.sports_venue_booking_evidence
    SET verification_status = 'pending',
        provider_code = NULLIF(p_provider_code, ''),
        provider_ref = NULLIF(p_provider_ref, ''),
        verification_meta = COALESCE(p_meta, '{}'::jsonb)
          || JSONB_BUILD_OBJECT(
               'providerOutcome', v_result,
               'duplicateFingerprint', v_duplicate),
        updated_at = now()
    WHERE id = v_evidence.id;
  END IF;

  UPDATE public.slip_verification_usage
  SET result = v_result, provider_code = NULLIF(p_provider_code, ''),
      cost = COALESCE(v_cost, 0), finished_at = now()
  WHERE id = v_usage.id;

  -- Confirm the group when every required item is satisfied.
  IF v_result = 'verified'
     AND v_group.status = 'awaiting_evidence' THEN
    v_state := public.sports_venue_booking_group_requirements_state(
      v_group.id);
    IF (v_state->>'satisfied')::BOOLEAN THEN
      PERFORM public.sports_venue_booking_group_transition(
        v_group.id, 'confirmed', 'confirmed', NULL,
        p_meta := JSONB_BUILD_OBJECT('provider_verified', true));
      UPDATE public.sports_venue_booking_groups
      SET decided_at = now(),
          payment_received_status = CASE
            WHEN (v_state->>'hasPaymentSlip')::BOOLEAN
              THEN 'received' ELSE payment_received_status END,
          payment_received_amount = CASE
            WHEN (v_state->>'hasPaymentSlip')::BOOLEAN
              THEN COALESCE(payment_received_amount,
                            total_amount_snapshot)
              ELSE payment_received_amount END
      WHERE id = v_group.id;
      PERFORM public.sports_hub_notify(
        v_group.user_id, 'venue_booking', 'venue_booking.confirmed',
        'สลิปยืนยันแล้ว การจองสำเร็จ',
        'ระบบตรวจสอบสลิปผ่านแล้ว',
        JSONB_BUILD_OBJECT('groupId', v_group.id,
                           'venueId', v_group.venue_id));
      PERFORM public.notify_sports_venue_managers(
        v_group.venue_id, 'venue_booking.group_confirmed',
        'กลุ่มการจองยืนยันหลักฐานครบแล้ว',
        'ระบบยืนยันสลิปอัตโนมัติ',
        JSONB_BUILD_OBJECT('groupId', v_group.id,
                           'venueId', v_group.venue_id));
      RETURN 'applied_confirmed';
    END IF;
  END IF;

  RETURN 'applied';
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.worker_claim_sports_venue_slip_verification(VARCHAR, VARCHAR)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION
  public.worker_apply_sports_venue_slip_verification(
    VARCHAR, VARCHAR, VARCHAR, NUMERIC, VARCHAR, VARCHAR, JSONB)
  FROM PUBLIC, anon, authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION
      public.worker_claim_sports_venue_slip_verification(VARCHAR, VARCHAR)
      TO service_role';
    EXECUTE 'GRANT EXECUTE ON FUNCTION
      public.worker_apply_sports_venue_slip_verification(
        VARCHAR, VARCHAR, VARCHAR, NUMERIC, VARCHAR, VARCHAR, JSONB)
      TO service_role';
    EXECUTE 'GRANT EXECUTE ON FUNCTION
      public.get_sports_venue_evidence_object_for_token(VARCHAR)
      TO service_role';
  END IF;
END $$;

-- ===============
-- Richer group listing for the booker UI (claims + refund cases + ledger).
-- ===============
CREATE OR REPLACE FUNCTION public.list_my_sports_venue_booking_groups(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  PERFORM public.housekeep_sports_venue_booking_groups_in_scope(
    p_user_id, NULL);
  RETURN JSONB_BUILD_OBJECT(
    'serverNow', now(),
    'groups', COALESCE((
      SELECT jsonb_agg(row ORDER BY row->>'createdAt' DESC) FROM (
        SELECT JSONB_BUILD_OBJECT(
          'id', g.id, 'venueId', g.venue_id, 'venueName', v.name,
          'timezone', v.timezone, 'status', g.status, 'stage', g.stage,
          'approvalMode', g.booking_approval_mode_snapshot,
          'totalAmount', g.total_amount_snapshot,
          'currency', g.currency,
          'evidenceDueAt', g.evidence_due_at,
          'ownerDecisionDueAt', g.owner_decision_due_at,
          'paymentDestination', CASE
            WHEN g.status IN ('awaiting_evidence', 'confirmed',
                              'partially_cancelled', 'completed')
              THEN g.payment_destination_snapshot ELSE NULL END,
          'paymentReceivedStatus', g.payment_received_status,
          'paymentReceivedAmount', g.payment_received_amount,
          'totalRefundedAmount', g.total_refunded_amount,
          'refundReservedAmount', g.total_refund_reserved_amount,
          'rejectionReason', g.rejection_reason,
          'cancellationReason', g.cancellation_reason,
          'decidedAt', g.decided_at,
          'cancelledAt', g.cancelled_at,
          'requirements', g.evidence_policy_snapshot->'requirements',
          'evidence', COALESCE((
            SELECT jsonb_agg(JSONB_BUILD_OBJECT(
              'id', e.id, 'requirementKey', e.requirement_key,
              'kind', e.kind, 'verificationStatus', e.verification_status,
              'revision', e.revision,
              'storagePath', e.storage_path, 'mime', e.mime,
              'providerOutcome',
                e.verification_meta->>'providerOutcome',
              'duplicateFingerprint',
                (e.verification_meta->>'duplicateFingerprint')::BOOLEAN))
            FROM public.sports_venue_booking_evidence e
            WHERE e.booking_group_id = g.id AND e.is_current),
            '[]'::jsonb),
          'claims', COALESCE((
            SELECT jsonb_agg(JSONB_BUILD_OBJECT(
              'id', cl.id, 'reportedAmount', cl.reported_amount,
              'transferReference', cl.transfer_reference,
              'status', cl.status, 'decisionNote', cl.decision_note,
              'createdAt', cl.created_at)
              ORDER BY cl.created_at)
            FROM public.sports_venue_booking_payment_claims cl
            WHERE cl.booking_group_id = g.id), '[]'::jsonb),
          'refundCases', COALESCE((
            SELECT jsonb_agg(JSONB_BUILD_OBJECT(
              'id', rc.id, 'bookingId', rc.booking_id,
              'allocatedAmount', rc.allocated_amount_snapshot,
              'refundAmount', rc.refund_amount,
              'reason', rc.reason, 'status', rc.status,
              'externalRef', rc.external_ref, 'createdAt', rc.created_at)
              ORDER BY rc.created_at)
            FROM public.sports_venue_booking_refund_cases rc
            WHERE rc.booking_group_id = g.id), '[]'::jsonb),
          'bookings', COALESCE((
            SELECT jsonb_agg(JSONB_BUILD_OBJECT(
              'id', b.id, 'courtId', b.court_id, 'courtName', c.name,
              'startsAt', b.starts_at, 'endsAt', b.ends_at,
              'status', b.status,
              'priceTotal', b.price_total_snapshot,
              'unitLabel', b.unit_label_snapshot)
              ORDER BY b.starts_at)
            FROM public.sports_venue_bookings b
            JOIN public.sports_venue_courts c ON c.id = b.court_id
            WHERE b.booking_group_id = g.id), '[]'::jsonb),
          'createdAt', g.created_at
        ) AS row
        FROM public.sports_venue_booking_groups g
        JOIN public.sports_venues v ON v.id = g.venue_id
        WHERE g.user_id = p_user_id
        ORDER BY g.created_at DESC
        LIMIT 100
      ) rows), '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_my_sports_venue_booking_groups(
  UUID
) TO anon, authenticated;

-- ===============
-- bookingGroupId on the flat booking lists so the UI can merge children
-- into their group card and route decisions through group RPCs.
-- ===============
CREATE OR REPLACE FUNCTION public.list_my_sports_venue_bookings(
  p_user_id UUID,
  p_statuses VARCHAR[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  PERFORM public.expire_pending_sports_venue_bookings_in_scope(p_user_id, NULL);
  PERFORM public.complete_sports_venue_bookings_in_scope(p_user_id, NULL);
  PERFORM public.housekeep_sports_venue_booking_groups_in_scope(
    p_user_id, NULL);
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'starts_at' DESC) FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', b.id, 'courtId', b.court_id, 'venueId', b.venue_id,
        'sportId', b.sport_id, 'startsAt', b.starts_at, 'endsAt', b.ends_at,
        'status', b.status, 'venueName', v.name, 'timezone', v.timezone,
        'courtName', c.name,
        'unitLabel', b.unit_label_snapshot,
        'venueUnitLabel', b.venue_unit_label_snapshot,
        'priceAmount', b.price_amount_snapshot,
        'pricingUnit', b.pricing_unit_snapshot,
        'priceTotal', b.price_total_snapshot,
        'priceBreakdown', b.price_breakdown_snapshot,
        'priceScheduleVersion', b.price_schedule_version_snapshot,
        'approvalMode', b.booking_approval_mode_snapshot,
        'termsVersion', b.accepted_terms_version,
        'cancellationCutoffMinutes', b.cancellation_cutoff_minutes_snapshot,
        'rejectionReason', b.rejection_reason,
        'cancellationReason', b.cancellation_reason,
        'decidedAt', b.decided_at,
        'bookingGroupId', b.booking_group_id,
        'createdAt', b.created_at
      ) AS row
      FROM public.sports_venue_bookings b
      JOIN public.sports_venues v ON v.id = b.venue_id
      JOIN public.sports_venue_courts c ON c.id = b.court_id
      WHERE b.user_id = p_user_id
        AND (p_statuses IS NULL OR b.status = ANY(p_statuses))
      ORDER BY b.starts_at DESC
      LIMIT 200
    ) rows
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_sports_venue_bookings_for_manager(
  p_user_id UUID,
  p_venue_id UUID,
  p_statuses VARCHAR[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  PERFORM public.expire_pending_sports_venue_bookings_in_scope(NULL, p_venue_id);
  PERFORM public.complete_sports_venue_bookings_in_scope(NULL, p_venue_id);
  PERFORM public.housekeep_sports_venue_booking_groups_in_scope(
    NULL, p_venue_id);
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'starts_at' ASC) FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', b.id, 'courtId', b.court_id, 'venueId', b.venue_id,
        'sportId', b.sport_id, 'startsAt', b.starts_at, 'endsAt', b.ends_at,
        'status', b.status, 'courtName', c.name, 'timezone', v.timezone,
        'unitLabel', b.unit_label_snapshot,
        'venueUnitLabel', b.venue_unit_label_snapshot,
        'priceAmount', b.price_amount_snapshot,
        'pricingUnit', b.pricing_unit_snapshot,
        'priceTotal', b.price_total_snapshot,
        'priceBreakdown', b.price_breakdown_snapshot,
        'priceScheduleVersion', b.price_schedule_version_snapshot,
        'approvalMode', b.booking_approval_mode_snapshot,
        'bookerName', NULLIF(btrim(
          CONCAT_WS(' ', u.first_name, u.last_name)), ''),
        'bookingGroupId', b.booking_group_id,
        'createdAt', b.created_at
      ) AS row
      FROM public.sports_venue_bookings b
      JOIN public.sports_venue_courts c ON c.id = b.court_id
      JOIN public.sports_venues v ON v.id = b.venue_id
      LEFT JOIN public.users u ON u.id = b.user_id
      WHERE b.venue_id = p_venue_id
        AND (p_statuses IS NULL OR b.status = ANY(p_statuses))
      ORDER BY b.starts_at ASC
      LIMIT 300
    ) rows
  ), '[]'::jsonb);
END;
$$;

NOTIFY pgrst, 'reload schema';
