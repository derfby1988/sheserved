-- Phase 21.7.21 — Evidence-Gated Booking groups, payment-slip verification
-- plumbing and manual refund reconciliation.
--
-- Contract highlights (see Match_Sport_PLAN.md 21.7.21):
--   * every new field defaults to "feature off": venues/courts get a NULL
--     evidence policy, so applying this migration changes nothing until an
--     owner opts in
--   * a booking group is the atomic unit for multi-slot evidence booking:
--     all child bookings are created/hold/transitioned all-or-nothing inside
--     one transaction
--   * `instant` + policy on creates an `awaiting_evidence` hold immediately;
--     `owner_approval` stays `pending` (no hold) until an explicit owner
--     pre-approval, after which slots are rechecked and held atomically
--   * payment slips are never implicitly approved: a provider `verified`
--     result or an explicit owner decision is required; provider outages go
--     to the owner queue and time out into `forfeited` + release (no
--     fail-open)
--   * `awaiting_evidence` consumes the slot: it is included in overlap
--     counts and surfaced as `held` in availability
--   * group status widened to VARCHAR(24); booking/event statuses widened to
--     VARCHAR(20) to fit 'awaiting_evidence'
--   * money decisions are owner-only (`is_sports_venue_owner` — admin and
--     invited managers are excluded); V1 refunds are manual external
--     transfers recorded for audit, never automatic money movement
--   * `booking-evidence` is a private bucket: no public URL, INSERT-only for
--     clients; reads go through authorized signed grants (server-side)

-- ===============
-- Status widening + group link
-- ===============
ALTER TABLE public.sports_venue_bookings
  ALTER COLUMN status TYPE VARCHAR(20);
ALTER TABLE public.sports_venue_bookings
  DROP CONSTRAINT IF EXISTS sports_venue_bookings_status_check;
ALTER TABLE public.sports_venue_bookings
  ADD CONSTRAINT sports_venue_bookings_status_check CHECK (status IN (
    'pending','awaiting_evidence','confirmed','completed','cancelled',
    'rejected','expired','forfeited'));

ALTER TABLE public.sports_venue_booking_events
  ALTER COLUMN previous_status TYPE VARCHAR(20),
  ALTER COLUMN new_status TYPE VARCHAR(20);

-- ===============
-- Venue-level evidence policy (all NULL = feature off)
-- ===============
ALTER TABLE public.sports_venues
  ADD COLUMN IF NOT EXISTS evidence_requirements JSONB,
  ADD COLUMN IF NOT EXISTS evidence_deadline_mode VARCHAR(20),
  ADD COLUMN IF NOT EXISTS evidence_minutes INT,
  ADD COLUMN IF NOT EXISTS evidence_deadline_time TIME,
  ADD COLUMN IF NOT EXISTS owner_approval_evidence_deadline_enabled BOOLEAN,
  ADD COLUMN IF NOT EXISTS evidence_min_grace_minutes INT,
  ADD COLUMN IF NOT EXISTS owner_decision_minutes INT,
  ADD COLUMN IF NOT EXISTS evidence_max_holds_per_user INT,
  ADD COLUMN IF NOT EXISTS payment_destination VARCHAR(200),
  -- Admin-only provider policy; never owner-editable.
  ADD COLUMN IF NOT EXISTS verify_scope VARCHAR(20) NOT NULL DEFAULT 'disabled',
  ADD COLUMN IF NOT EXISTS verify_cost_bearer VARCHAR(20) NOT NULL DEFAULT 'platform',
  ADD COLUMN IF NOT EXISTS verify_monthly_quota INT,
  ADD COLUMN IF NOT EXISTS verify_timeout_minutes INT;

-- Checklist shape validator (IMMUTABLE so it can run inside CHECK).
-- Items: {key,label,kind,stage,review_mode,required,note?}
--   kind        = 'document' | 'payment_slip'
--   stage       = 'booking' | 'preapproval' | 'payment'
--   review_mode = document -> 'auto' | 'owner_review'
--                 payment_slip -> 'auto_verify' | 'owner_review'
CREATE OR REPLACE FUNCTION public.sports_venue_evidence_requirements_valid(
  p_requirements JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  IF p_requirements IS NULL OR jsonb_typeof(p_requirements) <> 'array' THEN
    RETURN false;
  END IF;
  v_count := jsonb_array_length(p_requirements);
  IF v_count < 1 OR v_count > 10 THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_requirements) AS e
    WHERE jsonb_typeof(e.value) <> 'object'
       OR NULLIF(btrim(COALESCE(e.value->>'key', '')), '') IS NULL
       OR length(e.value->>'key') > 60
       OR NULLIF(btrim(COALESCE(e.value->>'label', '')), '') IS NULL
       OR length(e.value->>'label') > 60
       OR COALESCE(e.value->>'kind', '') NOT IN ('document', 'payment_slip')
       OR COALESCE(e.value->>'stage', '') NOT IN (
            'booking', 'preapproval', 'payment')
       OR jsonb_typeof(e.value->'required') <> 'boolean'
       OR (e.value->>'kind' = 'payment_slip'
           AND e.value->>'stage' <> 'payment')
       OR (e.value->>'kind' = 'document'
           AND COALESCE(e.value->>'review_mode', '')
             NOT IN ('auto', 'owner_review'))
       OR (e.value->>'kind' = 'payment_slip'
           AND COALESCE(e.value->>'review_mode', '')
             NOT IN ('auto_verify', 'owner_review'))
       OR (e.value->>'note' IS NOT NULL
           AND length(e.value->>'note') > 200)
  ) THEN
    RETURN false;
  END IF;
  IF (SELECT count(DISTINCT e.value->>'key')
      FROM jsonb_array_elements(p_requirements) AS e) <> v_count THEN
    RETURN false;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_requirements) AS e
    WHERE (e.value->>'required')::boolean
  ) THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_evidence_requirements_valid(
  JSONB
) FROM PUBLIC, anon, authenticated;

ALTER TABLE public.sports_venues
  DROP CONSTRAINT IF EXISTS sports_venues_evidence_chk;
ALTER TABLE public.sports_venues
  ADD CONSTRAINT sports_venues_evidence_chk CHECK (
    -- Disabled: every owner-configurable field is NULL.
    (evidence_requirements IS NULL
      AND evidence_deadline_mode IS NULL
      AND evidence_minutes IS NULL
      AND evidence_deadline_time IS NULL
      AND owner_approval_evidence_deadline_enabled IS NULL
      AND evidence_min_grace_minutes IS NULL
      AND owner_decision_minutes IS NULL
      AND evidence_max_holds_per_user IS NULL
      AND payment_destination IS NULL)
    OR (
      public.sports_venue_evidence_requirements_valid(evidence_requirements)
      AND evidence_deadline_mode IN (
        'per_booking', 'after_release', 'release_day_time')
      -- release-based modes require an applicable release rule on the venue
      AND (evidence_deadline_mode = 'per_booking'
           OR booking_release_days IS NOT NULL
           OR booking_release_day_of_week IS NOT NULL)
      AND (evidence_deadline_mode = 'release_day_time'
           OR evidence_minutes IS NOT NULL)
      AND (evidence_minutes IS NULL
           OR evidence_minutes BETWEEN 1 AND 43200)
      AND (evidence_deadline_mode <> 'release_day_time'
           OR (evidence_deadline_time IS NOT NULL
               AND evidence_minutes IS NULL))
      AND (evidence_deadline_mode = 'release_day_time'
           OR evidence_deadline_time IS NULL)
      AND owner_approval_evidence_deadline_enabled IS NOT NULL
      AND evidence_min_grace_minutes IS NOT NULL
      AND evidence_min_grace_minutes BETWEEN 0 AND 10080
      AND owner_decision_minutes IS NOT NULL
      AND owner_decision_minutes BETWEEN 1 AND 43200
      AND evidence_max_holds_per_user IS NOT NULL
      AND evidence_max_holds_per_user BETWEEN 1 AND 100
    )
  );

ALTER TABLE public.sports_venues
  DROP CONSTRAINT IF EXISTS sports_venues_verify_chk;
ALTER TABLE public.sports_venues
  ADD CONSTRAINT sports_venues_verify_chk CHECK (
    verify_scope IN ('disabled', 'whitelist', 'all')
    AND verify_cost_bearer IN ('platform', 'owner')
    AND (verify_monthly_quota IS NULL OR verify_monthly_quota >= 0)
    AND (verify_timeout_minutes IS NULL
         OR verify_timeout_minutes BETWEEN 1 AND 1440)
  );

-- ===============
-- Court-level override: inherit | off | custom (mirrors booking_release_mode)
-- ===============
ALTER TABLE public.sports_venue_courts
  ADD COLUMN IF NOT EXISTS evidence_mode VARCHAR(20) NOT NULL DEFAULT 'inherit',
  ADD COLUMN IF NOT EXISTS evidence_requirements JSONB,
  ADD COLUMN IF NOT EXISTS evidence_deadline_mode VARCHAR(20),
  ADD COLUMN IF NOT EXISTS evidence_minutes INT,
  ADD COLUMN IF NOT EXISTS evidence_deadline_time TIME,
  ADD COLUMN IF NOT EXISTS owner_approval_evidence_deadline_enabled BOOLEAN,
  ADD COLUMN IF NOT EXISTS evidence_min_grace_minutes INT,
  ADD COLUMN IF NOT EXISTS owner_decision_minutes INT,
  ADD COLUMN IF NOT EXISTS evidence_max_holds_per_user INT,
  ADD COLUMN IF NOT EXISTS payment_destination VARCHAR(200);

ALTER TABLE public.sports_venue_courts
  DROP CONSTRAINT IF EXISTS sports_venue_courts_evidence_mode_chk;
ALTER TABLE public.sports_venue_courts
  ADD CONSTRAINT sports_venue_courts_evidence_mode_chk
  CHECK (evidence_mode IN ('inherit', 'off', 'custom'));

ALTER TABLE public.sports_venue_courts
  DROP CONSTRAINT IF EXISTS sports_venue_courts_evidence_chk;
ALTER TABLE public.sports_venue_courts
  ADD CONSTRAINT sports_venue_courts_evidence_chk CHECK (
    (evidence_mode = 'custom'
      AND public.sports_venue_evidence_requirements_valid(evidence_requirements)
      AND evidence_deadline_mode IN (
        'per_booking', 'after_release', 'release_day_time')
      AND (evidence_deadline_mode = 'release_day_time'
           OR evidence_minutes IS NOT NULL)
      AND (evidence_minutes IS NULL
           OR evidence_minutes BETWEEN 1 AND 43200)
      AND (evidence_deadline_mode <> 'release_day_time'
           OR (evidence_deadline_time IS NOT NULL
               AND evidence_minutes IS NULL))
      AND (evidence_deadline_mode = 'release_day_time'
           OR evidence_deadline_time IS NULL)
      AND owner_approval_evidence_deadline_enabled IS NOT NULL
      AND evidence_min_grace_minutes IS NOT NULL
      AND evidence_min_grace_minutes BETWEEN 0 AND 10080
      AND owner_decision_minutes IS NOT NULL
      AND owner_decision_minutes BETWEEN 1 AND 43200
      AND evidence_max_holds_per_user IS NOT NULL
      AND evidence_max_holds_per_user BETWEEN 1 AND 100)
    OR (evidence_mode IN ('inherit', 'off')
      AND evidence_requirements IS NULL
      AND evidence_deadline_mode IS NULL
      AND evidence_minutes IS NULL
      AND evidence_deadline_time IS NULL
      AND owner_approval_evidence_deadline_enabled IS NULL
      AND evidence_min_grace_minutes IS NULL
      AND owner_decision_minutes IS NULL
      AND evidence_max_holds_per_user IS NULL
      AND payment_destination IS NULL)
  );

-- ===============
-- Booking groups
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_booking_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id),
  venue_id UUID NOT NULL REFERENCES public.sports_venues(id),
  status VARCHAR(24) NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending','awaiting_evidence','confirmed','partially_cancelled',
    'forfeited','rejected','expired','cancelled','completed')),
  stage VARCHAR(12) NOT NULL DEFAULT 'booking'
    CHECK (stage IN ('preapproval','booking','payment')),
  booking_approval_mode_snapshot VARCHAR(15) NOT NULL
    CHECK (booking_approval_mode_snapshot IN ('instant','owner_approval')),
  idempotency_key VARCHAR(80),
  total_amount_snapshot NUMERIC(12,2)
    CHECK (total_amount_snapshot IS NULL OR total_amount_snapshot >= 0),
  currency VARCHAR(3) NOT NULL DEFAULT 'THB',
  evidence_policy_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  payment_destination_snapshot VARCHAR(200),
  stage_started_at TIMESTAMPTZ,
  evidence_due_at TIMESTAMPTZ,
  owner_decision_due_at TIMESTAMPTZ,
  -- Money ledger: only the venue owner may set these via RPC.
  payment_received_status VARCHAR(15) NOT NULL DEFAULT 'unknown'
    CHECK (payment_received_status IN ('unknown','received','not_received')),
  payment_received_amount NUMERIC(12,2)
    CHECK (payment_received_amount IS NULL OR payment_received_amount >= 0),
  total_refunded_amount NUMERIC(12,2) NOT NULL DEFAULT 0
    CHECK (total_refunded_amount >= 0),
  total_refund_reserved_amount NUMERIC(12,2) NOT NULL DEFAULT 0
    CHECK (total_refund_reserved_amount >= 0),
  decided_by UUID REFERENCES public.users(id),
  decided_at TIMESTAMPTZ,
  rejection_reason VARCHAR(300),
  cancelled_by UUID REFERENCES public.users(id),
  cancellation_reason VARCHAR(300),
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sports_venue_booking_groups_idem
  ON public.sports_venue_booking_groups(user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_groups_venue
  ON public.sports_venue_booking_groups(venue_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_groups_user
  ON public.sports_venue_booking_groups(user_id, status, created_at);
-- Hold-abuse guard counts groups (not child bookings).
CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_groups_holds
  ON public.sports_venue_booking_groups(venue_id, user_id)
  WHERE status = 'awaiting_evidence';
-- Housekeeping due scans.
CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_groups_evidence_due
  ON public.sports_venue_booking_groups(evidence_due_at)
  WHERE status = 'awaiting_evidence';
CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_groups_decision_due
  ON public.sports_venue_booking_groups(owner_decision_due_at)
  WHERE status = 'awaiting_evidence';

ALTER TABLE public.sports_venue_bookings
  ADD COLUMN IF NOT EXISTS booking_group_id UUID;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sports_venue_bookings_group_fk'
  ) THEN
    ALTER TABLE public.sports_venue_bookings
      ADD CONSTRAINT sports_venue_bookings_group_fk
      FOREIGN KEY (booking_group_id)
      REFERENCES public.sports_venue_booking_groups(id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_group
  ON public.sports_venue_bookings(booking_group_id)
  WHERE booking_group_id IS NOT NULL;
-- Held slots must be found by overlap scans and availability.
CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_held_slot
  ON public.sports_venue_bookings(court_id, starts_at, ends_at)
  WHERE status = 'awaiting_evidence';

-- ===============
-- Evidence revisions (append-only; one current revision per requirement)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_booking_evidence (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_group_id UUID NOT NULL
    REFERENCES public.sports_venue_booking_groups(id) ON DELETE CASCADE,
  requirement_key VARCHAR(60) NOT NULL,
  kind VARCHAR(15) NOT NULL CHECK (kind IN ('document','payment_slip')),
  stage VARCHAR(12) NOT NULL
    CHECK (stage IN ('booking','preapproval','payment')),
  storage_path VARCHAR(500) NOT NULL,
  mime VARCHAR(80),
  size_bytes BIGINT CHECK (size_bytes IS NULL OR size_bytes >= 0),
  revision INT NOT NULL CHECK (revision >= 1),
  is_current BOOLEAN NOT NULL DEFAULT true,
  verification_status VARCHAR(15) NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN (
      'pending','verifying','verified','failed','approved','rejected')),
  provider_code VARCHAR(40),
  provider_ref VARCHAR(200),
  verification_meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  submitted_by UUID NOT NULL REFERENCES public.users(id),
  reviewed_by UUID REFERENCES public.users(id),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (booking_group_id, requirement_key, revision)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sports_venue_booking_evidence_current
  ON public.sports_venue_booking_evidence(booking_group_id, requirement_key)
  WHERE is_current;
CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_evidence_group
  ON public.sports_venue_booking_evidence(booking_group_id);
CREATE INDEX IF NOT EXISTS idx_sports_venue_booking_evidence_queue
  ON public.sports_venue_booking_evidence(verification_status, created_at)
  WHERE verification_status IN ('pending','verifying');

-- ===============
-- Booker-reported payment claims (group-level reconciliation)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_booking_payment_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_group_id UUID NOT NULL
    REFERENCES public.sports_venue_booking_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id),
  reported_amount NUMERIC(12,2)
    CHECK (reported_amount IS NULL OR reported_amount >= 0),
  transfer_reference VARCHAR(200),
  evidence_path VARCHAR(500),
  status VARCHAR(15) NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted','received','not_received')),
  decided_by UUID REFERENCES public.users(id),
  decided_at TIMESTAMPTZ,
  decision_note VARCHAR(300),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One open claim per group; a decided claim can be followed by a new one.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sports_venue_payment_claims_open
  ON public.sports_venue_booking_payment_claims(booking_group_id)
  WHERE status = 'submitted';
CREATE INDEX IF NOT EXISTS idx_sports_venue_payment_claims_group
  ON public.sports_venue_booking_payment_claims(booking_group_id, created_at);

-- ===============
-- Slip verification: transactions, providers, usage ledger
-- ===============
CREATE TABLE IF NOT EXISTS public.slip_verification_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- HMAC/normalized fingerprint of bank code + trans-ref; raw trans-ref is
  -- never stored so a DB dump cannot replay slips.
  fingerprint VARCHAR(128) NOT NULL,
  booking_group_id UUID
    REFERENCES public.sports_venue_booking_groups(id),
  evidence_id UUID
    REFERENCES public.sports_venue_booking_evidence(id),
  provider_code VARCHAR(40),
  amount NUMERIC(12,2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_slip_verification_transactions_fp
  ON public.slip_verification_transactions(fingerprint);
CREATE INDEX IF NOT EXISTS idx_slip_verification_transactions_group
  ON public.slip_verification_transactions(booking_group_id);

CREATE TABLE IF NOT EXISTS public.slip_verification_providers (
  code VARCHAR(40) PRIMARY KEY,
  display_name VARCHAR(120) NOT NULL,
  endpoint_url VARCHAR(500),
  -- Reference into the server secret store; the API key itself is never
  -- stored in the database.
  api_key_ref VARCHAR(200),
  cost_per_check NUMERIC(10,2) NOT NULL DEFAULT 0
    CHECK (cost_per_check >= 0),
  verify_timeout_minutes INT NOT NULL DEFAULT 15
    CHECK (verify_timeout_minutes BETWEEN 1 AND 1440),
  capabilities JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  priority INT NOT NULL DEFAULT 100,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.slip_verification_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Durable outbox idempotency: the worker writes/claims one row per
  -- attempt so retries never double-charge the quota.
  attempt_id VARCHAR(80) NOT NULL UNIQUE,
  venue_id UUID REFERENCES public.sports_venues(id),
  booking_group_id UUID
    REFERENCES public.sports_venue_booking_groups(id),
  evidence_id UUID
    REFERENCES public.sports_venue_booking_evidence(id),
  provider_code VARCHAR(40),
  cost NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
  currency VARCHAR(3) NOT NULL DEFAULT 'THB',
  cost_bearer VARCHAR(20) CHECK (cost_bearer IN ('platform','owner')),
  -- NULL result = queued/in-flight outbox row.
  result VARCHAR(20) CHECK (result IN (
    'verified','failed','unavailable','timeout','rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_slip_verification_usage_pending
  ON public.slip_verification_usage(created_at)
  WHERE result IS NULL;
CREATE INDEX IF NOT EXISTS idx_slip_verification_usage_venue_month
  ON public.slip_verification_usage(venue_id, created_at);

-- ===============
-- Refund cases (V1: owner transfers externally and records the outcome)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_booking_refund_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_group_id UUID NOT NULL
    REFERENCES public.sports_venue_booking_groups(id) ON DELETE CASCADE,
  -- NULL booking_id = group-level overpayment case.
  booking_id UUID REFERENCES public.sports_venue_bookings(id),
  allocated_amount_snapshot NUMERIC(12,2)
    CHECK (allocated_amount_snapshot IS NULL
           OR allocated_amount_snapshot >= 0),
  refund_amount NUMERIC(12,2)
    CHECK (refund_amount IS NULL OR refund_amount >= 0),
  reason VARCHAR(300),
  status VARCHAR(15) NOT NULL DEFAULT 'open' CHECK (status IN (
    'open','approved','processing','completed','not_refundable','failed')),
  decided_by UUID REFERENCES public.users(id),
  decided_at TIMESTAMPTZ,
  external_ref VARCHAR(200),
  receipt_path VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sports_venue_refund_cases_group
  ON public.sports_venue_booking_refund_cases(booking_group_id, status);
CREATE INDEX IF NOT EXISTS idx_sports_venue_refund_cases_open
  ON public.sports_venue_booking_refund_cases(status, created_at)
  WHERE status IN ('open','approved','processing');

-- ===============
-- Private storage bucket (guarded: scratch databases lack the storage
-- schema). No SELECT/UPDATE/DELETE policies -> no public URL; uploads use
-- RPC-vended paths; reads go through authorized signed grants server-side.
-- ===============
DO $$
BEGIN
  IF to_regnamespace('storage') IS NOT NULL
     AND to_regclass('storage.buckets') IS NOT NULL THEN
    INSERT INTO storage.buckets (
      id, name, public, file_size_limit, allowed_mime_types
    ) VALUES (
      'booking-evidence', 'booking-evidence', false, 10485760,
      ARRAY['image/jpeg','image/png','image/webp','image/heic']
    )
    ON CONFLICT (id) DO UPDATE
      SET public = false,
          file_size_limit = EXCLUDED.file_size_limit,
          allowed_mime_types = EXCLUDED.allowed_mime_types;

    IF to_regclass('storage.objects') IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage' AND tablename = 'objects'
          AND policyname = 'booking_evidence_insert'
      ) THEN
        EXECUTE $p$CREATE POLICY booking_evidence_insert
          ON storage.objects FOR INSERT
          WITH CHECK (bucket_id = 'booking-evidence')$p$;
      END IF;
    END IF;
  END IF;
END $$;

-- ===============
-- RLS: no public policies — every read/write goes through SECURITY DEFINER
-- RPCs, matching the bookings convention.
-- ===============
ALTER TABLE public.sports_venue_booking_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_booking_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_booking_payment_claims
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.slip_verification_transactions
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.slip_verification_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.slip_verification_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_booking_refund_cases
  ENABLE ROW LEVEL SECURITY;

-- ===============
-- Authorization helpers
-- ===============

-- Venue-owner only (owner profile or active member role='owner'); admin and
-- manager roles are deliberately excluded — money decisions are owner-only.
CREATE OR REPLACE FUNCTION public.is_sports_venue_owner(
  p_venue_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL OR p_venue_id IS NULL THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.sports_venues v
    JOIN public.sports_venue_owner_profiles op
      ON op.id = v.owner_profile_id
    WHERE v.id = p_venue_id AND op.user_id = p_user_id
  ) THEN
    RETURN true;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.sports_venue_owner_members m
    WHERE m.venue_id = p_venue_id
      AND m.user_id = p_user_id
      AND m.is_active = true
      AND m.role = 'owner'
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.is_sports_venue_owner(UUID, UUID)
  FROM PUBLIC, anon, authenticated;

-- Effective evidence policy for a court: 'off' -> NULL, 'custom' -> the
-- court set, 'inherit' -> the venue set. Returns NULL when disabled.
CREATE OR REPLACE FUNCTION public.sports_venue_court_evidence_policy(
  p_court_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court RECORD;
  v_venue RECORD;
BEGIN
  SELECT c.venue_id, c.evidence_mode,
         c.evidence_requirements, c.evidence_deadline_mode,
         c.evidence_minutes, c.evidence_deadline_time,
         c.owner_approval_evidence_deadline_enabled,
         c.evidence_min_grace_minutes, c.owner_decision_minutes,
         c.evidence_max_holds_per_user, c.payment_destination
  INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id;
  IF v_court.venue_id IS NULL OR v_court.evidence_mode = 'off' THEN
    RETURN NULL;
  END IF;

  IF v_court.evidence_mode = 'custom' THEN
    RETURN JSONB_BUILD_OBJECT(
      'source', 'court',
      'requirements', v_court.evidence_requirements,
      'deadline_mode', v_court.evidence_deadline_mode,
      'minutes', v_court.evidence_minutes,
      'deadline_time', v_court.evidence_deadline_time,
      'owner_approval_deadline_enabled',
        v_court.owner_approval_evidence_deadline_enabled,
      'min_grace_minutes', v_court.evidence_min_grace_minutes,
      'owner_decision_minutes', v_court.owner_decision_minutes,
      'max_holds_per_user', v_court.evidence_max_holds_per_user,
      'payment_destination', v_court.payment_destination);
  END IF;

  SELECT v.evidence_requirements, v.evidence_deadline_mode,
         v.evidence_minutes, v.evidence_deadline_time,
         v.owner_approval_evidence_deadline_enabled,
         v.evidence_min_grace_minutes, v.owner_decision_minutes,
         v.evidence_max_holds_per_user, v.payment_destination,
         v.verify_scope
  INTO v_venue
  FROM public.sports_venues v
  WHERE v.id = v_court.venue_id;
  IF v_venue.evidence_requirements IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN JSONB_BUILD_OBJECT(
    'source', 'venue',
    'requirements', v_venue.evidence_requirements,
    'deadline_mode', v_venue.evidence_deadline_mode,
    'minutes', v_venue.evidence_minutes,
    'deadline_time', v_venue.evidence_deadline_time,
    'owner_approval_deadline_enabled',
      v_venue.owner_approval_evidence_deadline_enabled,
    'min_grace_minutes', v_venue.evidence_min_grace_minutes,
    'owner_decision_minutes', v_venue.owner_decision_minutes,
    'max_holds_per_user', v_venue.evidence_max_holds_per_user,
    'payment_destination', v_venue.payment_destination,
    'verify_scope', v_venue.verify_scope);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_court_evidence_policy(UUID)
  FROM PUBLIC, anon, authenticated;

-- ===============
-- Held slots consume capacity: overlap count includes awaiting_evidence.
-- ===============
CREATE OR REPLACE FUNCTION public.sports_venue_confirmed_overlap_count(
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_exclude_booking_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.sports_venue_bookings b
  WHERE b.court_id = p_court_id
    AND b.status IN ('confirmed', 'awaiting_evidence')
    AND b.starts_at < p_ends_at
    AND b.ends_at > p_starts_at
    AND (p_exclude_booking_id IS NULL OR b.id <> p_exclude_booking_id);
  RETURN COALESCE(v_count, 0);
END;
$$;

-- Availability: 'held' ranges (awaiting_evidence children) reported
-- separately from 'booked'; no user identity or deadlines are exposed.
CREATE OR REPLACE FUNCTION public.get_court_availability(
  p_court_id UUID,
  p_from TIMESTAMPTZ,
  p_to TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue_id UUID;
  v_mode VARCHAR;
  v_timezone VARCHAR;
  v_court_days SMALLINT[];
  v_court_day SMALLINT;
  v_court_time TIME;
  v_court_window SMALLINT;
  v_venue_days SMALLINT[];
  v_venue_day SMALLINT;
  v_venue_time TIME;
  v_venue_window SMALLINT;
  v_selected_day SMALLINT;
  v_selected_date DATE;
  v_selected_time TIME;
  v_selected_window SMALLINT;
  v_selected_opens_at TIMESTAMPTZ;
  v_effective_days SMALLINT[];
  v_next_release_at TIMESTAMPTZ;
BEGIN
  SELECT c.venue_id, c.booking_release_mode,
         c.booking_release_days, c.booking_release_day_of_week,
         c.booking_release_time, c.booking_release_window_days
    INTO v_venue_id, v_mode, v_court_days, v_court_day,
         v_court_time, v_court_window
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id AND c.is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  v_court_days := COALESCE(
    v_court_days,
    CASE WHEN v_court_day IS NULL THEN NULL ELSE ARRAY[v_court_day] END);

  SELECT v.timezone, v.booking_release_days,
         v.booking_release_day_of_week, v.booking_release_time,
         v.booking_release_window_days
    INTO v_timezone, v_venue_days, v_venue_day,
         v_venue_time, v_venue_window
  FROM public.sports_venues v
  WHERE v.id = v_venue_id AND v.status = 'approved';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;
  v_venue_days := COALESCE(
    v_venue_days,
    CASE WHEN v_venue_day IS NULL THEN NULL ELSE ARRAY[v_venue_day] END);

  IF v_mode = 'always_open' THEN
    v_effective_days := NULL;
  ELSE
    SELECT array_agg(d.day ORDER BY d.day)
      INTO v_effective_days
    FROM (
      SELECT unnest(COALESCE(v_venue_days, '{}'::SMALLINT[])) AS day
      UNION
      SELECT unnest(
        CASE WHEN v_mode = 'custom'
          THEN COALESCE(v_court_days, '{}'::SMALLINT[])
          ELSE '{}'::SMALLINT[]
        END) AS day
    ) d;
  END IF;

  v_selected_date := (p_from AT TIME ZONE v_timezone)::DATE;
  v_selected_day := EXTRACT(DOW FROM v_selected_date)::SMALLINT;
  IF v_mode = 'custom'
     AND v_court_days IS NOT NULL
     AND v_selected_day = ANY(v_court_days) THEN
    v_selected_time := v_court_time;
    v_selected_window := v_court_window;
  ELSIF v_mode <> 'always_open'
     AND v_venue_days IS NOT NULL THEN
    v_selected_time := v_venue_time;
    v_selected_window := v_venue_window;
  END IF;

  IF v_effective_days IS NOT NULL THEN
    SELECT max(o.opens_at)
      INTO v_selected_opens_at
    FROM generate_series(0, 23) AS hour_num
    CROSS JOIN LATERAL (
      SELECT public.sports_venue_booking_release_opens_at_for_slot(
        v_timezone, v_mode,
        v_court_days, v_court_time, v_court_window,
        v_venue_days, v_venue_time, v_venue_window,
        (v_selected_date + (hour_num || ' hours')::interval)
          AT TIME ZONE v_timezone) AS opens_at
    ) o;
  END IF;

  v_next_release_at := public.sports_venue_booking_release_next_at(
    v_timezone, now(), v_mode, v_court_days, v_court_time,
    v_venue_days, v_venue_time);

  RETURN JSONB_BUILD_OBJECT(
    'courtId', p_court_id,
    'serverNow', now(),
    'nextReleaseAt', v_next_release_at,
    'booked', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'startsAt', b.starts_at, 'endsAt', b.ends_at))
      FROM public.sports_venue_bookings b
      WHERE b.court_id = p_court_id
        AND b.status = 'confirmed'
        AND b.starts_at < p_to AND b.ends_at > p_from
    ), '[]'::jsonb),
    'held', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'startsAt', b.starts_at, 'endsAt', b.ends_at))
      FROM public.sports_venue_bookings b
      WHERE b.court_id = p_court_id
        AND b.status = 'awaiting_evidence'
        AND b.starts_at < p_to AND b.ends_at > p_from
    ), '[]'::jsonb),
    'blocked', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'startsAt', s.starts_at, 'endsAt', s.ends_at))
      FROM public.sports_venue_availability s
      WHERE s.court_id = p_court_id
        AND s.kind = 'blocked'
        AND s.starts_at < p_to AND s.ends_at > p_from
    ), '[]'::jsonb),
    'hours', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'day', h.day_of_week, 'open', h.open_time,
          'close', h.close_time, 'closed', h.is_closed))
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v_venue_id
    ), '[]'::jsonb),
    'notOpen', CASE WHEN v_effective_days IS NULL THEN '[]'::jsonb ELSE COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'slotStart', o.slot_start, 'opensAt', o.opens_at)
          ORDER BY o.slot_start)
      FROM (
        SELECT s.slot_start,
               public.sports_venue_booking_release_opens_at_for_slot(
                 v_timezone, v_mode,
                 v_court_days, v_court_time, v_court_window,
                 v_venue_days, v_venue_time, v_venue_window,
                 s.slot_start) AS opens_at
        FROM (
          SELECT (gen::date + (hour_num || ' hours')::interval)
                 AT TIME ZONE v_timezone AS slot_start
          FROM generate_series(
            (p_from AT TIME ZONE v_timezone)::date,
            (p_to AT TIME ZONE v_timezone)::date,
            '1 day'::interval) AS gen,
          generate_series(0, 23) AS hour_num
        ) s
        WHERE s.slot_start >= p_from AND s.slot_start < p_to
      ) o
      WHERE o.opens_at > now()
    ), '[]'::jsonb) END,
    'release', CASE WHEN v_effective_days IS NULL THEN NULL
      ELSE JSONB_BUILD_OBJECT(
        'mode', v_mode,
        'dayOfWeek', v_effective_days[1],
        'daysOfWeek', v_effective_days,
        'releaseTime', COALESCE(v_selected_time, v_court_time, v_venue_time),
        'windowDays', COALESCE(v_selected_window,
                               v_court_window, v_venue_window),
        'selectedDayReleaseTime', v_selected_time,
        'selectedDayOpensAt', v_selected_opens_at)
      END
  );
END;
$$;

-- ===============
-- Policy RPCs
-- ===============

-- Venue-level evidence policy. p_policy NULL/'null' disables the feature
-- (all columns cleared). Otherwise a complete policy payload is required;
-- auto_verify items additionally require an admin-enabled verify scope and
-- at least one enabled provider.
CREATE OR REPLACE FUNCTION public.set_sports_venue_evidence_policy(
  p_user_id UUID,
  p_venue_id UUID,
  p_policy JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue RECORD;
  v_requirements JSONB;
  v_deadline_mode VARCHAR;
  v_minutes INT;
  v_deadline_time TIME;
  v_oa_deadline_enabled BOOLEAN;
  v_grace INT;
  v_decision_minutes INT;
  v_max_holds INT;
  v_destination VARCHAR;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  SELECT v.id, v.booking_release_days, v.booking_release_day_of_week,
         v.verify_scope
  INTO v_venue
  FROM public.sports_venues v
  WHERE v.id = p_venue_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;

  IF p_policy IS NULL OR p_policy = 'null'::jsonb THEN
    UPDATE public.sports_venues
    SET evidence_requirements = NULL,
        evidence_deadline_mode = NULL,
        evidence_minutes = NULL,
        evidence_deadline_time = NULL,
        owner_approval_evidence_deadline_enabled = NULL,
        evidence_min_grace_minutes = NULL,
        owner_decision_minutes = NULL,
        evidence_max_holds_per_user = NULL,
        payment_destination = NULL,
        updated_at = now()
    WHERE id = p_venue_id;
    RETURN;
  END IF;

  IF jsonb_typeof(p_policy) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;
  v_requirements := p_policy->'requirements';
  v_deadline_mode := NULLIF(p_policy->>'deadline_mode', '');
  v_oa_deadline_enabled :=
    (p_policy->>'owner_approval_deadline_enabled')::BOOLEAN;
  v_destination := NULLIF(btrim(COALESCE(
    p_policy->>'payment_destination', '')), '');

  BEGIN
    v_minutes := NULLIF(p_policy->>'minutes', '')::INT;
    v_deadline_time := NULLIF(p_policy->>'deadline_time', '')::TIME;
    v_grace := NULLIF(p_policy->>'min_grace_minutes', '')::INT;
    v_decision_minutes := NULLIF(p_policy->>'owner_decision_minutes', '')::INT;
    v_max_holds := NULLIF(p_policy->>'max_holds_per_user', '')::INT;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END;

  IF NOT public.sports_venue_evidence_requirements_valid(v_requirements) THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_REQUIREMENTS';
  END IF;
  IF v_deadline_mode IS NULL OR v_deadline_mode NOT IN (
    'per_booking', 'after_release', 'release_day_time') THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;
  IF v_deadline_mode IN ('after_release', 'release_day_time')
     AND v_venue.booking_release_days IS NULL
     AND v_venue.booking_release_day_of_week IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_POLICY_REQUIRES_RELEASE';
  END IF;
  IF v_deadline_mode <> 'release_day_time'
     AND (v_minutes IS NULL OR v_minutes NOT BETWEEN 1 AND 43200) THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;
  IF v_deadline_mode = 'release_day_time' THEN
    IF v_deadline_time IS NULL OR v_minutes IS NOT NULL THEN
      RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
    END IF;
  ELSIF v_deadline_time IS NOT NULL THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;
  IF v_oa_deadline_enabled IS NULL
     OR v_grace IS NULL OR v_grace NOT BETWEEN 0 AND 10080
     OR v_decision_minutes IS NULL OR v_decision_minutes NOT BETWEEN 1 AND 43200
     OR v_max_holds IS NULL OR v_max_holds NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;

  -- A required payment slip needs a payout destination.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_requirements) AS e
    WHERE e.value->>'kind' = 'payment_slip'
      AND (e.value->>'required')::BOOLEAN
  ) AND v_destination IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_DESTINATION_REQUIRED';
  END IF;

  -- auto_verify is gated by the admin-controlled verify scope plus at
  -- least one enabled provider.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_requirements) AS e
    WHERE e.value->>'review_mode' = 'auto_verify'
  ) THEN
    IF v_venue.verify_scope = 'disabled' THEN
      RAISE EXCEPTION 'VERIFY_NOT_ENABLED';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.slip_verification_providers p
      WHERE p.is_enabled
    ) THEN
      RAISE EXCEPTION 'VERIFY_NOT_ENABLED';
    END IF;
  END IF;

  UPDATE public.sports_venues
  SET evidence_requirements = v_requirements,
      evidence_deadline_mode = v_deadline_mode,
      evidence_minutes = v_minutes,
      evidence_deadline_time = v_deadline_time,
      owner_approval_evidence_deadline_enabled = v_oa_deadline_enabled,
      evidence_min_grace_minutes = v_grace,
      owner_decision_minutes = v_decision_minutes,
      evidence_max_holds_per_user = v_max_holds,
      payment_destination = v_destination,
      updated_at = now()
  WHERE id = p_venue_id;
END;
$$;

-- Court-level override. p_mode NULL keeps the current setting; 'inherit'
-- and 'off' clear the per-court fields; 'custom' takes the same policy
-- payload shape as the venue RPC. A release-based deadline additionally
-- needs an effective release rule that can resolve for this court (court
-- custom rule or the venue rule).
CREATE OR REPLACE FUNCTION public.set_sports_venue_court_evidence_policy(
  p_user_id UUID,
  p_court_id UUID,
  p_mode VARCHAR,
  p_policy JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court RECORD;
  v_venue RECORD;
  v_requirements JSONB;
  v_deadline_mode VARCHAR;
  v_minutes INT;
  v_deadline_time TIME;
  v_oa_deadline_enabled BOOLEAN;
  v_grace INT;
  v_decision_minutes INT;
  v_max_holds INT;
  v_destination VARCHAR;
  v_has_release BOOLEAN;
BEGIN
  SELECT c.venue_id, c.booking_release_mode, c.booking_release_days,
         c.booking_release_day_of_week
  INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  IF NOT public.is_sports_venue_manager(v_court.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  IF p_mode IS NULL THEN
    RETURN;
  END IF;
  IF p_mode NOT IN ('inherit', 'off', 'custom') THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;

  IF p_mode <> 'custom' THEN
    UPDATE public.sports_venue_courts
    SET evidence_mode = p_mode,
        evidence_requirements = NULL,
        evidence_deadline_mode = NULL,
        evidence_minutes = NULL,
        evidence_deadline_time = NULL,
        owner_approval_evidence_deadline_enabled = NULL,
        evidence_min_grace_minutes = NULL,
        owner_decision_minutes = NULL,
        evidence_max_holds_per_user = NULL,
        payment_destination = NULL,
        updated_at = now()
    WHERE id = p_court_id;
    RETURN;
  END IF;

  IF p_policy IS NULL OR jsonb_typeof(p_policy) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;
  v_requirements := p_policy->'requirements';
  v_deadline_mode := NULLIF(p_policy->>'deadline_mode', '');
  v_oa_deadline_enabled :=
    (p_policy->>'owner_approval_deadline_enabled')::BOOLEAN;
  v_destination := NULLIF(btrim(COALESCE(
    p_policy->>'payment_destination', '')), '');

  BEGIN
    v_minutes := NULLIF(p_policy->>'minutes', '')::INT;
    v_deadline_time := NULLIF(p_policy->>'deadline_time', '')::TIME;
    v_grace := NULLIF(p_policy->>'min_grace_minutes', '')::INT;
    v_decision_minutes := NULLIF(p_policy->>'owner_decision_minutes', '')::INT;
    v_max_holds := NULLIF(p_policy->>'max_holds_per_user', '')::INT;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END;

  IF NOT public.sports_venue_evidence_requirements_valid(v_requirements) THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_REQUIREMENTS';
  END IF;
  IF v_deadline_mode IS NULL OR v_deadline_mode NOT IN (
    'per_booking', 'after_release', 'release_day_time') THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;

  IF v_deadline_mode IN ('after_release', 'release_day_time') THEN
    v_has_release := (v_court.booking_release_mode = 'custom'
                      AND (v_court.booking_release_days IS NOT NULL
                           OR v_court.booking_release_day_of_week IS NOT NULL));
    IF NOT v_has_release THEN
      SELECT (v.booking_release_days IS NOT NULL
              OR v.booking_release_day_of_week IS NOT NULL)
        INTO v_has_release
      FROM public.sports_venues v
      WHERE v.id = v_court.venue_id;
    END IF;
    IF NOT COALESCE(v_has_release, false) THEN
      RAISE EXCEPTION 'EVIDENCE_POLICY_REQUIRES_RELEASE';
    END IF;
  END IF;

  IF v_deadline_mode <> 'release_day_time'
     AND (v_minutes IS NULL OR v_minutes NOT BETWEEN 1 AND 43200) THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;
  IF v_deadline_mode = 'release_day_time' THEN
    IF v_deadline_time IS NULL OR v_minutes IS NOT NULL THEN
      RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
    END IF;
  ELSIF v_deadline_time IS NOT NULL THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;
  IF v_oa_deadline_enabled IS NULL
     OR v_grace IS NULL OR v_grace NOT BETWEEN 0 AND 10080
     OR v_decision_minutes IS NULL OR v_decision_minutes NOT BETWEEN 1 AND 43200
     OR v_max_holds IS NULL OR v_max_holds NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'INVALID_EVIDENCE_POLICY';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_requirements) AS e
    WHERE e.value->>'kind' = 'payment_slip'
      AND (e.value->>'required')::BOOLEAN
  ) AND v_destination IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_DESTINATION_REQUIRED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_requirements) AS e
    WHERE e.value->>'review_mode' = 'auto_verify'
  ) THEN
    SELECT v.verify_scope INTO v_venue
    FROM public.sports_venues v WHERE v.id = v_court.venue_id;
    IF COALESCE(v_venue.verify_scope, 'disabled') = 'disabled'
       OR NOT EXISTS (
         SELECT 1 FROM public.slip_verification_providers p
         WHERE p.is_enabled
       ) THEN
      RAISE EXCEPTION 'VERIFY_NOT_ENABLED';
    END IF;
  END IF;

  UPDATE public.sports_venue_courts
  SET evidence_mode = 'custom',
      evidence_requirements = v_requirements,
      evidence_deadline_mode = v_deadline_mode,
      evidence_minutes = v_minutes,
      evidence_deadline_time = v_deadline_time,
      owner_approval_evidence_deadline_enabled = v_oa_deadline_enabled,
      evidence_min_grace_minutes = v_grace,
      owner_decision_minutes = v_decision_minutes,
      evidence_max_holds_per_user = v_max_holds,
      payment_destination = v_destination,
      updated_at = now()
  WHERE id = p_court_id;
END;
$$;

-- Admin-only provider-cost policy per venue. NULL params keep the current
-- value (NULL-means-keep); the venue owner never touches these columns.
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
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_verify_scope IS NOT NULL
     AND p_verify_scope NOT IN ('disabled', 'whitelist', 'all') THEN
    RAISE EXCEPTION 'INVALID_VERIFY_POLICY';
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

  UPDATE public.sports_venues
  SET verify_scope = COALESCE(p_verify_scope, verify_scope),
      verify_cost_bearer =
        COALESCE(p_verify_cost_bearer, verify_cost_bearer),
      verify_monthly_quota = CASE
        WHEN p_clear_quota THEN NULL
        ELSE COALESCE(p_verify_monthly_quota, verify_monthly_quota) END,
      verify_timeout_minutes = CASE
        WHEN p_clear_timeout THEN NULL
        ELSE COALESCE(p_verify_timeout_minutes, verify_timeout_minutes) END,
      updated_at = now()
  WHERE id = p_venue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
END;
$$;

-- Admin provider registry: API keys are referenced by secret-store name
-- only; disabling every provider freezes auto_verify without touching
-- venue policies (kill switch).
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

-- Admin/provider detail never reaches public views; an authenticated list
-- for admins so the control panel can render state without secret refs.
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

-- ===============
-- Grants (public RPC surface)
-- ===============
GRANT EXECUTE ON FUNCTION public.set_sports_venue_evidence_policy(
  UUID, UUID, JSONB
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_sports_venue_court_evidence_policy(
  UUID, UUID, VARCHAR, JSONB
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_sports_venue_verify_policy(
  UUID, UUID, VARCHAR, VARCHAR, INT, INT, BOOLEAN, BOOLEAN
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_slip_verification_provider(
  UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMERIC, INT, JSONB, BOOLEAN,
  INT, TEXT
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_slip_verification_providers(
  UUID
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 21.7.21.2 — Atomic group lifecycle
-- ============================================================

-- Deadline for one slot under an evidence policy snapshot.
--   per_booking      -> stage_start + minutes
--   after_release    -> opens_at + minutes
--   release_day_time -> local day of opens_at at deadline_time
-- then max(computed, stage_start + grace) clamped to the slot start.
CREATE OR REPLACE FUNCTION public.sports_venue_evidence_slot_deadline(
  p_deadline_mode VARCHAR,
  p_minutes INT,
  p_deadline_time TIME,
  p_min_grace_minutes INT,
  p_stage_started_at TIMESTAMPTZ,
  p_slot_opens_at TIMESTAMPTZ,
  p_slot_starts_at TIMESTAMPTZ,
  p_timezone VARCHAR
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_deadline TIMESTAMPTZ;
BEGIN
  IF p_deadline_mode = 'release_day_time' THEN
    IF p_slot_opens_at IS NULL THEN
      -- No resolvable release moment: fall back to the grace floor only.
      v_deadline := p_stage_started_at;
    ELSE
      v_deadline := (
        (p_slot_opens_at AT TIME ZONE p_timezone)::DATE + p_deadline_time
      ) AT TIME ZONE p_timezone;
    END IF;
  ELSIF p_deadline_mode = 'after_release' AND p_slot_opens_at IS NOT NULL THEN
    v_deadline := p_slot_opens_at + (p_minutes || ' minutes')::interval;
  ELSE
    v_deadline := p_stage_started_at + (p_minutes || ' minutes')::interval;
  END IF;
  v_deadline := greatest(
    v_deadline,
    p_stage_started_at + (COALESCE(p_min_grace_minutes, 0) || ' minutes')::interval);
  RETURN least(v_deadline, p_slot_starts_at);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_evidence_slot_deadline(
  VARCHAR, INT, TIME, INT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, VARCHAR
) FROM PUBLIC, anon, authenticated;

-- Required-requirement state for a group, evaluated against the policy
-- snapshot and current evidence revisions.
CREATE OR REPLACE FUNCTION public.sports_venue_booking_group_requirements_state(
  p_booking_group_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_policy JSONB;
  v_state JSONB;
BEGIN
  SELECT g.evidence_policy_snapshot INTO v_policy
  FROM public.sports_venue_booking_groups g
  WHERE g.id = p_booking_group_id;

  SELECT JSONB_BUILD_OBJECT(
    'satisfied', NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_policy->'requirements') r
      WHERE (r.value->>'required')::boolean
        AND NOT EXISTS (
          SELECT 1 FROM public.sports_venue_booking_evidence e
          WHERE e.booking_group_id = p_booking_group_id
            AND e.requirement_key = r.value->>'key'
            AND e.is_current
            AND e.verification_status IN ('verified', 'approved'))),
    'missing', COALESCE((
      SELECT jsonb_agg(r.value->>'key')
      FROM jsonb_array_elements(v_policy->'requirements') r
      WHERE (r.value->>'required')::boolean
        AND NOT EXISTS (
          SELECT 1 FROM public.sports_venue_booking_evidence e
          WHERE e.booking_group_id = p_booking_group_id
            AND e.requirement_key = r.value->>'key'
            AND e.is_current)),
      '[]'::jsonb),
    'awaitingReview', COALESCE((
      SELECT jsonb_agg(r.value->>'key')
      FROM jsonb_array_elements(v_policy->'requirements') r
      WHERE (r.value->>'required')::boolean
        AND EXISTS (
          SELECT 1 FROM public.sports_venue_booking_evidence e
          WHERE e.booking_group_id = p_booking_group_id
            AND e.requirement_key = r.value->>'key'
            AND e.is_current
            AND e.verification_status IN ('pending', 'verifying'))),
      '[]'::jsonb),
    'hasPaymentSlip', EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_policy->'requirements') r
      WHERE (r.value->>'required')::boolean
        AND r.value->>'kind' = 'payment_slip'),
    'awaitingSlip', EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_policy->'requirements') r
      JOIN public.sports_venue_booking_evidence e
        ON e.booking_group_id = p_booking_group_id
       AND e.requirement_key = r.value->>'key' AND e.is_current
      WHERE (r.value->>'required')::boolean
        AND r.value->>'kind' = 'payment_slip'
        AND e.verification_status IN ('pending', 'verifying')),
    'awaitingDocs', EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_policy->'requirements') r
      JOIN public.sports_venue_booking_evidence e
        ON e.booking_group_id = p_booking_group_id
       AND e.requirement_key = r.value->>'key' AND e.is_current
      WHERE (r.value->>'required')::boolean
        AND r.value->>'kind' = 'document'
        AND e.verification_status = 'pending')
  ) INTO v_state;
  RETURN v_state;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_group_requirements_state(
  UUID
) FROM PUBLIC, anon, authenticated;

-- Atomic group + children transition helper. Every lifecycle path funnels
-- through this so group/child states can never diverge.
CREATE OR REPLACE FUNCTION public.sports_venue_booking_group_transition(
  p_group_id UUID,
  p_new_status VARCHAR,
  p_child_status VARCHAR,
  p_actor UUID DEFAULT NULL,
  p_reason VARCHAR DEFAULT NULL,
  p_meta JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
BEGIN
  UPDATE public.sports_venue_booking_groups g
  SET status = p_new_status,
      updated_at = now()
  WHERE g.id = p_group_id;

  FOR v_booking IN
    SELECT b.id, b.user_id, b.status
    FROM public.sports_venue_bookings b
    WHERE b.booking_group_id = p_group_id
      AND b.status IN ('pending', 'awaiting_evidence', 'confirmed')
    FOR UPDATE
  LOOP
    IF v_booking.status <> p_child_status THEN
      UPDATE public.sports_venue_bookings
      SET status = p_child_status, updated_at = now()
      WHERE id = v_booking.id;
      INSERT INTO public.sports_venue_booking_events (
        booking_id, actor_id, previous_status, new_status, meta
      ) VALUES (
        v_booking.id, p_actor, v_booking.status, p_child_status,
        JSONB_BUILD_OBJECT('group_id', p_group_id,
                           'group_status', p_new_status,
                           'reason', p_reason)
          || COALESCE(p_meta, '{}'::jsonb));
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_booking_group_transition(
  UUID, VARCHAR, VARCHAR, UUID, VARCHAR, JSONB
) FROM PUBLIC, anon, authenticated;

-- Create an atomic booking group. p_items:
--   [{court_id, starts_at, ends_at, expected_price_schedule_version}]
-- Returns the group id; idempotent on p_idempotency_key.
CREATE OR REPLACE FUNCTION public.create_sports_venue_booking_group(
  p_user_id UUID,
  p_items JSONB,
  p_terms_version INT,
  p_idempotency_key VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item JSONB;
  v_group_id UUID;
  v_court RECORD;
  v_venue RECORD;
  v_terms RECORD;
  v_court_ids UUID[];
  v_venue_id UUID;
  v_timezone VARCHAR;
  v_policy JSONB;
  v_policy_prev JSONB;
  v_approval_mode VARCHAR;
  v_mode VARCHAR;
  v_hold_count INT;
  v_total NUMERIC := 0;
  v_price NUMERIC;
  v_breakdown JSONB;
  v_version VARCHAR;
  v_expected_version VARCHAR;
  v_opens_at TIMESTAMPTZ;
  v_slots JSONB := '[]'::jsonb;
  v_due TIMESTAMPTZ;
  v_stage_start TIMESTAMPTZ;
  v_booking_id UUID;
  v_overlap INT;
  v_all_priced BOOLEAN := true;
  v_needs_payment BOOLEAN;
  v_court_id UUID;
  v_starts TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 24 THEN
    RAISE EXCEPTION 'INVALID_GROUP_ITEMS';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT g.id INTO v_group_id
    FROM public.sports_venue_booking_groups g
    WHERE g.user_id = p_user_id AND g.idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN v_group_id;
    END IF;
  END IF;

  -- Item shape validation.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    BEGIN
      v_court_id := (v_item->>'court_id')::UUID;
      v_starts := (v_item->>'starts_at')::TIMESTAMPTZ;
      v_ends := (v_item->>'ends_at')::TIMESTAMPTZ;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'INVALID_GROUP_ITEMS';
    END;
    IF v_court_id IS NULL OR v_ends <= v_starts OR v_starts <= now() THEN
      RAISE EXCEPTION 'INVALID_GROUP_ITEMS';
    END IF;
  END LOOP;

  -- Same-court items in a group may not overlap each other.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_items) WITH ORDINALITY a
    JOIN jsonb_array_elements(p_items) WITH ORDINALITY b
      ON b.ordinality > a.ordinality
    WHERE (a.value->>'court_id')::UUID = (b.value->>'court_id')::UUID
      AND (a.value->>'starts_at')::TIMESTAMPTZ
          < (b.value->>'ends_at')::TIMESTAMPTZ
      AND (a.value->>'ends_at')::TIMESTAMPTZ
          > (b.value->>'starts_at')::TIMESTAMPTZ
  ) THEN
    RAISE EXCEPTION 'INVALID_GROUP_ITEMS';
  END IF;

  SELECT array_agg(DISTINCT (i->>'court_id')::UUID
                   ORDER BY (i->>'court_id')::UUID)
    INTO v_court_ids
  FROM jsonb_array_elements(p_items) i;

  -- Lock every involved court in a stable order before checks/inserts.
  FOR v_court IN
    SELECT c.id, c.venue_id, c.capacity, c.is_active,
           c.booking_approval_mode,
           c.booking_release_mode, c.booking_release_days,
           c.booking_release_day_of_week, c.booking_release_time,
           c.booking_release_window_days
    FROM public.sports_venue_courts c
    WHERE c.id = ANY(v_court_ids)
    ORDER BY c.id
    FOR UPDATE
  LOOP
    IF NOT v_court.is_active THEN
      RAISE EXCEPTION 'COURT_NOT_FOUND';
    END IF;
    IF v_venue_id IS NULL THEN
      v_venue_id := v_court.venue_id;
    ELSIF v_court.venue_id <> v_venue_id THEN
      RAISE EXCEPTION 'GROUP_VENUE_MISMATCH';
    END IF;
    IF v_approval_mode IS NULL THEN
      v_approval_mode := v_court.booking_approval_mode;
    ELSIF v_court.booking_approval_mode <> v_approval_mode THEN
      RAISE EXCEPTION 'GROUP_MODE_MISMATCH';
    END IF;

    v_policy := public.sports_venue_court_evidence_policy(v_court.id);
    IF v_policy IS NULL THEN
      RAISE EXCEPTION 'EVIDENCE_NOT_ENABLED';
    END IF;
    IF v_policy_prev IS NULL THEN
      v_policy_prev := v_policy;
    ELSIF v_policy <> v_policy_prev THEN
      RAISE EXCEPTION 'GROUP_POLICY_MISMATCH';
    END IF;
  END LOOP;

  SELECT v.id, v.status, v.timezone,
         v.booking_release_days, v.booking_release_day_of_week,
         v.booking_release_time, v.booking_release_window_days,
         v.payment_destination
  INTO v_venue
  FROM public.sports_venues v
  WHERE v.id = v_venue_id
  FOR UPDATE;
  IF NOT FOUND OR v_venue.status <> 'approved' THEN
    RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
  END IF;
  v_timezone := v_venue.timezone;

  IF public.is_sports_venue_manager(v_venue.id, p_user_id) THEN
    RAISE EXCEPTION 'SELF_BOOKING_BLOCKED';
  END IF;

  v_terms := public.sports_venue_current_terms(v_venue.id);
  IF v_terms.id IS NOT NULL AND v_terms.version <> p_terms_version THEN
    RAISE EXCEPTION 'TERMS_VERSION_CHANGED';
  END IF;

  v_needs_payment := EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_policy->'requirements') r
    WHERE r.value->>'kind' = 'payment_slip'
      AND (r.value->>'required')::boolean);

  -- Per-item validation + price resolution.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_court_id := (v_item->>'court_id')::UUID;
    v_starts := (v_item->>'starts_at')::TIMESTAMPTZ;
    v_ends := (v_item->>'ends_at')::TIMESTAMPTZ;
    v_expected_version := NULLIF(v_item->>'expected_price_schedule_version', '');

    SELECT c.booking_release_mode, c.booking_release_days,
           c.booking_release_day_of_week, c.booking_release_time,
           c.booking_release_window_days, c.capacity
    INTO v_court
    FROM public.sports_venue_courts c
    WHERE c.id = v_court_id;

    v_opens_at := public.sports_venue_booking_release_opens_at_for_slot(
      v_timezone,
      v_court.booking_release_mode,
      COALESCE(v_court.booking_release_days,
        CASE WHEN v_court.booking_release_day_of_week IS NULL THEN NULL
             ELSE ARRAY[v_court.booking_release_day_of_week] END),
      v_court.booking_release_time, v_court.booking_release_window_days,
      COALESCE(v_venue.booking_release_days,
        CASE WHEN v_venue.booking_release_day_of_week IS NULL THEN NULL
             ELSE ARRAY[v_venue.booking_release_day_of_week] END),
      v_venue.booking_release_time, v_venue.booking_release_window_days,
      v_starts);
    IF v_opens_at IS NOT NULL AND v_opens_at > now() THEN
      RAISE EXCEPTION 'NOT_OPEN_YET';
    END IF;
    IF public.sports_venue_slot_is_blocked(v_court_id, v_starts, v_ends) THEN
      RAISE EXCEPTION 'SLOT_UNAVAILABLE';
    END IF;

    v_breakdown := public.sports_venue_price_quote(v_court_id, v_starts, v_ends);
    v_price := NULLIF(v_breakdown->>'total', '')::NUMERIC;
    v_version := NULLIF(v_breakdown->>'schedule_version', '');
    IF v_version IS NOT NULL
       AND v_expected_version IS NOT NULL
       AND v_expected_version <> v_version THEN
      RAISE EXCEPTION 'PRICE_CHANGED';
    END IF;
    IF v_price IS NULL THEN
      v_all_priced := false;
    ELSE
      v_total := v_total + v_price;
    END IF;

    v_slots := v_slots || JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
      'court_id', v_court_id,
      'starts_at', v_starts,
      'ends_at', v_ends,
      'opens_at', v_opens_at,
      'price', v_price,
      'breakdown', v_breakdown,
      'schedule_version', v_version,
      'capacity', v_court.capacity));
  END LOOP;

  IF v_needs_payment AND (NOT v_all_priced OR v_total <= 0) THEN
    RAISE EXCEPTION 'GROUP_PRICE_REQUIRED';
  END IF;
  IF v_needs_payment AND v_venue.payment_destination IS NULL
     AND NULLIF(v_policy->>'payment_destination', '') IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_DESTINATION_REQUIRED';
  END IF;

  v_stage_start := now();
  v_due := NULL;
  SELECT min(public.sports_venue_evidence_slot_deadline(
    v_policy->>'deadline_mode',
    NULLIF(v_policy->>'minutes', '')::INT,
    NULLIF(v_policy->>'deadline_time', '')::TIME,
    (v_policy->>'min_grace_minutes')::INT,
    v_stage_start,
    NULLIF(s.value->>'opens_at', '')::TIMESTAMPTZ,
    (s.value->>'starts_at')::TIMESTAMPTZ,
    v_timezone))
  INTO v_due
  FROM jsonb_array_elements(v_slots) s;
  IF v_due IS NULL OR v_due <= v_stage_start THEN
    RAISE EXCEPTION 'EVIDENCE_DEADLINE_PASSED';
  END IF;

  IF v_approval_mode = 'instant' THEN
    -- Hold-abuse limit counts evidence groups, not child bookings.
    v_hold_count := (v_policy->>'max_holds_per_user')::INT;
    PERFORM 1
    FROM public.sports_venue_booking_groups g
    WHERE g.venue_id = v_venue.id AND g.user_id = p_user_id
      AND g.status = 'awaiting_evidence'
    HAVING count(*) >= v_hold_count;
    IF FOUND THEN
      RAISE EXCEPTION 'HOLD_LIMIT_REACHED';
    END IF;

    -- Atomic capacity check for every item (held slots consume capacity).
    FOR v_item IN SELECT value FROM jsonb_array_elements(v_slots) LOOP
      v_overlap := public.sports_venue_confirmed_overlap_count(
        (v_item->>'court_id')::UUID,
        (v_item->>'starts_at')::TIMESTAMPTZ,
        (v_item->>'ends_at')::TIMESTAMPTZ);
      IF v_overlap >= COALESCE((v_item->>'capacity')::INT, 1) THEN
        RAISE EXCEPTION 'SLOT_FULL';
      END IF;
    END LOOP;
  END IF;

  INSERT INTO public.sports_venue_booking_groups (
    user_id, venue_id, status, stage, booking_approval_mode_snapshot,
    idempotency_key, total_amount_snapshot,
    evidence_policy_snapshot, payment_destination_snapshot,
    stage_started_at, evidence_due_at
  ) VALUES (
    p_user_id, v_venue.id,
    CASE WHEN v_approval_mode = 'instant'
      THEN 'awaiting_evidence' ELSE 'pending' END,
    CASE WHEN v_approval_mode = 'instant'
      THEN 'booking' ELSE 'preapproval' END,
    v_approval_mode,
    p_idempotency_key,
    CASE WHEN v_all_priced THEN v_total END,
    v_policy,
    CASE WHEN v_approval_mode = 'instant'
      THEN COALESCE(v_policy->>'payment_destination',
                    v_venue.payment_destination)
      ELSE NULL END,
    CASE WHEN v_approval_mode = 'instant'
         OR (v_policy->>'owner_approval_deadline_enabled')::BOOLEAN
      THEN v_stage_start ELSE NULL END,
    CASE WHEN v_approval_mode = 'instant'
         OR (v_policy->>'owner_approval_deadline_enabled')::BOOLEAN
      THEN v_due ELSE NULL END
  )
  RETURNING id INTO v_group_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_slots) LOOP
    INSERT INTO public.sports_venue_bookings (
      venue_id, court_id, user_id, starts_at, ends_at, status,
      terms_version, terms_id, booking_group_id,
      price_total_snapshot, price_breakdown_snapshot,
      price_schedule_version_snapshot
    ) VALUES (
      v_venue.id,
      (v_item->>'court_id')::UUID,
      p_user_id,
      (v_item->>'starts_at')::TIMESTAMPTZ,
      (v_item->>'ends_at')::TIMESTAMPTZ,
      CASE WHEN v_approval_mode = 'instant'
        THEN 'awaiting_evidence' ELSE 'pending' END,
      p_terms_version,
      v_terms.id,
      v_group_id,
      NULLIF(v_item->>'price', '')::NUMERIC,
      v_item->'breakdown',
      NULLIF(v_item->>'schedule_version', '')
    )
    RETURNING id INTO v_booking_id;

    INSERT INTO public.sports_venue_booking_events (
      booking_id, actor_id, previous_status, new_status, meta
    ) VALUES (
      v_booking_id, p_user_id, NULL,
      CASE WHEN v_approval_mode = 'instant'
        THEN 'awaiting_evidence' ELSE 'pending' END,
      JSONB_BUILD_OBJECT('group_id', v_group_id, 'group_created', true));
  END LOOP;

  RETURN v_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_sports_venue_booking_group(
  UUID, JSONB, INT, VARCHAR
) TO anon, authenticated;
