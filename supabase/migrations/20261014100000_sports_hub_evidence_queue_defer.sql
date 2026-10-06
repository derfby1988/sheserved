-- Phase 21.7.21 — personal queue defer, queue filters/pagination,
-- structured rejection reason codes and per-group-atomic bulk reject.
--
-- Defer is a per-manager snooze recorded in
-- `sports_venue_queue_deferrals`: it never changes the booking status or
-- any deadline, it only hides the group from that manager's default
-- queue until `deferred_until`. Structured `reason_code` values keep
-- rejection audit queryable without parsing free text.

CREATE TABLE IF NOT EXISTS public.sports_venue_queue_deferrals (
  booking_group_id UUID NOT NULL
    REFERENCES public.sports_venue_booking_groups(id) ON DELETE CASCADE,
  manager_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  deferred_until TIMESTAMPTZ NOT NULL,
  reason VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (booking_group_id, manager_id)
);
CREATE INDEX IF NOT EXISTS idx_svq_deferrals_manager
  ON public.sports_venue_queue_deferrals(manager_id, deferred_until);

ALTER TABLE public.sports_venue_queue_deferrals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sports_venue_queue_deferrals
  FROM PUBLIC, anon, authenticated;

ALTER TABLE public.sports_venue_booking_groups
  ADD COLUMN IF NOT EXISTS rejection_reason_code VARCHAR(40);
ALTER TABLE public.sports_venue_booking_evidence
  ADD COLUMN IF NOT EXISTS decision_reason_code VARCHAR(40);

-- Stable audit codes are lowercase identifiers; the label lives in the app.
CREATE OR REPLACE FUNCTION public.sports_venue_valid_reason_code(
  p_code VARCHAR
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT p_code IS NULL OR p_code ~ '^[a-z][a-z0-9_]{1,39}$';
$$;

-- Per-manager defer/undefer. p_minutes NULL or <= 0 clears the deferral.
-- Deferring is rejected once the group is terminal or every deadline has
-- already passed (housekeeping may not have run yet).
CREATE OR REPLACE FUNCTION public.defer_sports_venue_queue_item(
  p_user_id UUID,
  p_booking_group_id UUID,
  p_minutes INT DEFAULT NULL,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
  v_until TIMESTAMPTZ;
  v_final_due TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  SELECT g.* INTO v_group
  FROM public.sports_venue_booking_groups g
  WHERE g.id = p_booking_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;
  IF NOT public.is_sports_venue_manager(v_group.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  IF p_minutes IS NULL OR p_minutes <= 0 THEN
    DELETE FROM public.sports_venue_queue_deferrals
    WHERE booking_group_id = p_booking_group_id
      AND manager_id = p_user_id;
    RETURN NULL;
  END IF;

  IF v_group.status NOT IN ('pending', 'awaiting_evidence') THEN
    RAISE EXCEPTION 'GROUP_NOT_OPEN';
  END IF;
  v_final_due := GREATEST(
    COALESCE(v_group.evidence_due_at, '-infinity'::timestamptz),
    COALESCE(v_group.owner_decision_due_at, '-infinity'::timestamptz));
  IF v_final_due <> '-infinity'::timestamptz AND v_final_due < now() THEN
    RAISE EXCEPTION 'GROUP_NOT_OPEN';
  END IF;

  v_until := now() + LEAST(GREATEST(p_minutes, 5), 43200)
             * INTERVAL '1 minute';
  INSERT INTO public.sports_venue_queue_deferrals (
    booking_group_id, manager_id, deferred_until, reason
  ) VALUES (
    p_booking_group_id, p_user_id, v_until, NULLIF(btrim(p_reason), '')
  )
  ON CONFLICT (booking_group_id, manager_id)
  DO UPDATE SET deferred_until = EXCLUDED.deferred_until,
                reason = EXCLUDED.reason,
                updated_at = now();

  PERFORM public.log_sports_venue_booking_event(
    (SELECT b.id FROM public.sports_venue_bookings b
     WHERE b.booking_group_id = v_group.id LIMIT 1),
    'queue_deferred', p_user_id, NULL, NULL,
    NULLIF(btrim(p_reason), ''),
    p_meta := JSONB_BUILD_OBJECT(
      'group_id', v_group.id, 'deferred_until', v_until));
  RETURN v_until;
END;
$$;

-- decide_sports_venue_booking_group gains p_reason_code (optional, audited)
DROP FUNCTION IF EXISTS public.decide_sports_venue_booking_group(
  UUID, UUID, VARCHAR, VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION public.decide_sports_venue_booking_group(
  p_user_id UUID,
  p_booking_group_id UUID,
  p_decision VARCHAR,
  p_reason VARCHAR DEFAULT NULL,
  p_requirement_key VARCHAR DEFAULT NULL,
  p_reason_code VARCHAR DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
  v_evidence RECORD;
  v_court RECORD;
  v_conflict BOOLEAN := false;
  v_state JSONB;
  v_due TIMESTAMPTZ;
  v_destination VARCHAR;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_decision NOT IN ('approve', 'reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;
  IF NOT public.sports_venue_valid_reason_code(p_reason_code) THEN
    RAISE EXCEPTION 'INVALID_REASON_CODE';
  END IF;
  -- Free text wins; a bare code still satisfies REASON_REQUIRED so audit
  -- rows always carry something queryable.
  p_reason := COALESCE(NULLIF(btrim(p_reason), ''), p_reason_code);

  SELECT g.* INTO v_group
  FROM public.sports_venue_booking_groups g
  WHERE g.id = p_booking_group_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;
  IF NOT public.is_sports_venue_manager(v_group.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  -- Per-requirement evidence decision.
  IF p_requirement_key IS NOT NULL THEN
    SELECT e.*, r.value AS requirement INTO v_evidence
    FROM public.sports_venue_booking_evidence e
    JOIN LATERAL (
      SELECT r2.value
      FROM jsonb_array_elements(
        v_group.evidence_policy_snapshot->'requirements') r2
      WHERE r2.value->>'key' = p_requirement_key
    ) r ON true
    WHERE e.booking_group_id = v_group.id
      AND e.requirement_key = p_requirement_key
      AND e.is_current
    FOR UPDATE OF e;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'EVIDENCE_NOT_FOUND';
    END IF;
    IF v_evidence.verification_status NOT IN ('pending', 'verifying') THEN
      RAISE EXCEPTION 'EVIDENCE_NOT_PENDING';
    END IF;
    -- Money decisions are owner-only.
    IF v_evidence.kind = 'payment_slip'
       AND NOT public.is_sports_venue_owner(v_group.venue_id, p_user_id) THEN
      RAISE EXCEPTION 'OWNER_DECISION_REQUIRED';
    END IF;
    IF p_decision = 'reject'
       AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
      RAISE EXCEPTION 'REASON_REQUIRED';
    END IF;

    UPDATE public.sports_venue_booking_evidence
    SET verification_status = CASE WHEN p_decision = 'approve'
                                   THEN 'approved' ELSE 'rejected' END,
        decision_reason_code = CASE WHEN p_decision = 'reject'
                                    THEN p_reason_code ELSE NULL END,
        reviewed_by = p_user_id, reviewed_at = now(), updated_at = now()
    WHERE id = v_evidence.id;

    PERFORM public.log_sports_venue_booking_event(
      (SELECT b.id FROM public.sports_venue_bookings b
       WHERE b.booking_group_id = v_group.id LIMIT 1),
      'evidence_' || p_decision || 'd', p_user_id,
      NULL, NULL, p_reason,
      p_meta := JSONB_BUILD_OBJECT(
        'group_id', v_group.id, 'requirement_key', p_requirement_key,
        'evidence_id', v_evidence.id, 'reason_code', p_reason_code));

    IF p_decision = 'approve' THEN
      IF v_evidence.kind = 'payment_slip' THEN
        UPDATE public.sports_venue_booking_groups
        SET payment_received_status = 'received',
            payment_received_amount = total_amount_snapshot,
            updated_at = now()
        WHERE id = v_group.id;
      END IF;
      v_state := public.sports_venue_booking_group_requirements_state(
        v_group.id);
      IF v_group.status = 'awaiting_evidence'
         AND (v_state->>'satisfied')::BOOLEAN THEN
        PERFORM public.sports_venue_booking_group_transition(
          v_group.id, 'confirmed', 'confirmed', p_user_id);
        UPDATE public.sports_venue_booking_groups
        SET decided_by = p_user_id, decided_at = now()
        WHERE id = v_group.id;
        PERFORM public.sports_hub_notify(
          v_group.user_id, 'venue_booking', 'venue_booking.confirmed',
          'กลุ่มการจองยืนยันแล้ว',
          'เจ้าของสนามอนุมัติหลักฐานครบแล้ว',
          JSONB_BUILD_OBJECT('groupId', v_group.id,
                             'venueId', v_group.venue_id));
        RETURN 'confirmed';
      END IF;
      RETURN 'evidence_approved';
    END IF;
    RETURN 'evidence_rejected';
  END IF;

  -- Group-level decisions.
  IF p_decision = 'reject' THEN
    IF length(btrim(COALESCE(p_reason, ''))) = 0 THEN
      RAISE EXCEPTION 'REASON_REQUIRED';
    END IF;
    IF v_group.status NOT IN ('pending', 'awaiting_evidence') THEN
      RAISE EXCEPTION 'GROUP_NOT_OPEN';
    END IF;
    PERFORM public.sports_venue_booking_group_transition(
      v_group.id, 'rejected', 'rejected', p_user_id, p_reason);
    UPDATE public.sports_venue_booking_groups
    SET decided_by = p_user_id, decided_at = now(),
        rejection_reason = p_reason,
        rejection_reason_code = p_reason_code
    WHERE id = v_group.id;
    PERFORM public.sports_hub_notify(
      v_group.user_id, 'venue_booking', 'venue_booking.group_rejected',
      'กลุ่มการจองถูกปฏิเสธ',
      FORMAT('เหตุผล: %s', p_reason),
      JSONB_BUILD_OBJECT('groupId', v_group.id,
                         'venueId', v_group.venue_id,
                         'reasonCode', p_reason_code));
    RETURN 'rejected';
  END IF;

  -- Approve.
  IF v_group.status = 'pending' THEN
    -- Atomic availability recheck across all children before any hold.
    FOR v_court IN
      SELECT c.id
      FROM public.sports_venue_courts c
      WHERE c.id IN (
        SELECT DISTINCT b.court_id FROM public.sports_venue_bookings b
        WHERE b.booking_group_id = v_group.id)
      ORDER BY c.id
      FOR UPDATE
    LOOP
    END LOOP;

    SELECT bool_or(
      public.sports_venue_slot_blocked(b.court_id, b.starts_at, b.ends_at)
      OR public.sports_venue_confirmed_overlap_count(
           b.court_id, b.starts_at, b.ends_at, b.id) >= c.capacity
    ) INTO v_conflict
    FROM public.sports_venue_bookings b
    JOIN public.sports_venue_courts c ON c.id = b.court_id
    WHERE b.booking_group_id = v_group.id
      AND b.status = 'pending';

    IF v_conflict THEN
      PERFORM public.log_sports_venue_booking_event(
        (SELECT b.id FROM public.sports_venue_bookings b
         WHERE b.booking_group_id = v_group.id LIMIT 1),
        'group_approve_conflict', p_user_id, 'pending', 'pending');
      PERFORM public.sports_hub_notify(
        v_group.user_id, 'venue_booking', 'venue_booking.slot_conflict',
        'ช่วงเวลาที่ขอถูกใช้แล้ว',
        'กรุณาเปลี่ยนเวลาหรือยกเลิกกลุ่มคำขอ',
        JSONB_BUILD_OBJECT('groupId', v_group.id,
                           'venueId', v_group.venue_id));
      RETURN 'conflict';
    END IF;

    -- Payment requirements -> atomic hold at the payment stage; otherwise
    -- docs-only groups confirm immediately on approval.
    IF EXISTS (
      SELECT 1
      FROM jsonb_array_elements(
        v_group.evidence_policy_snapshot->'requirements') r
      WHERE r.value->>'kind' = 'payment_slip'
        AND (r.value->>'required')::boolean
    ) THEN
      v_destination := COALESCE(
        v_group.payment_destination_snapshot,
        (SELECT v.payment_destination FROM public.sports_venues v
         WHERE v.id = v_group.venue_id));
      IF v_destination IS NULL THEN
        RAISE EXCEPTION 'PAYMENT_DESTINATION_REQUIRED';
      END IF;
      SELECT min(public.sports_venue_evidence_slot_deadline(
        v_group.evidence_policy_snapshot->>'deadline_mode',
        NULLIF(v_group.evidence_policy_snapshot->>'minutes', '')::INT,
        NULLIF(v_group.evidence_policy_snapshot->>'deadline_time', '')::TIME,
        (v_group.evidence_policy_snapshot->>'min_grace_minutes')::INT,
        now(),
        public.sports_venue_booking_release_opens_at_for_slot(
          v.timezone,
          c.booking_release_mode,
          COALESCE(c.booking_release_days,
            CASE WHEN c.booking_release_day_of_week IS NULL THEN NULL
                 ELSE ARRAY[c.booking_release_day_of_week] END),
          c.booking_release_time, c.booking_release_window_days,
          COALESCE(v.booking_release_days,
            CASE WHEN v.booking_release_day_of_week IS NULL THEN NULL
                 ELSE ARRAY[v.booking_release_day_of_week] END),
          v.booking_release_time, v.booking_release_window_days,
          b.starts_at),
        b.starts_at,
        v.timezone))
      INTO v_due
      FROM public.sports_venue_bookings b
      JOIN public.sports_venue_courts c ON c.id = b.court_id
      JOIN public.sports_venues v ON v.id = c.venue_id
      WHERE b.booking_group_id = v_group.id;

      PERFORM public.sports_venue_booking_group_transition(
        v_group.id, 'awaiting_evidence', 'awaiting_evidence', p_user_id,
        p_meta := JSONB_BUILD_OBJECT('stage', 'payment'));
      UPDATE public.sports_venue_booking_groups
      SET stage = 'payment',
          stage_started_at = now(),
          evidence_due_at = v_due,
          payment_destination_snapshot = v_destination,
          updated_at = now()
      WHERE id = v_group.id;
      PERFORM public.sports_hub_notify(
        v_group.user_id, 'venue_booking',
        'venue_booking.group_preapproved',
        'คำขออนุมัติแล้ว กรุณาแนบสลิป',
        'ช่องเวลาถูก hold แล้ว โปรดชำระและแนบสลิปภายในเวลาที่กำหนด',
        JSONB_BUILD_OBJECT('groupId', v_group.id,
                           'venueId', v_group.venue_id));
      RETURN 'awaiting_evidence';
    END IF;

    PERFORM public.sports_venue_booking_group_transition(
      v_group.id, 'confirmed', 'confirmed', p_user_id);
    UPDATE public.sports_venue_booking_groups
    SET decided_by = p_user_id, decided_at = now()
    WHERE id = v_group.id;
    PERFORM public.sports_hub_notify(
      v_group.user_id, 'venue_booking', 'venue_booking.confirmed',
      'กลุ่มการจองได้รับการอนุมัติ',
      'เจ้าของสนามอนุมัติคำขอแล้ว',
      JSONB_BUILD_OBJECT('groupId', v_group.id,
                         'venueId', v_group.venue_id));
    RETURN 'confirmed';
  END IF;

  IF v_group.status = 'awaiting_evidence' THEN
    -- Owner approves the whole group despite pending items.
    v_state := public.sports_venue_booking_group_requirements_state(
      v_group.id);
    IF NOT (v_state->>'satisfied')::BOOLEAN
       AND (v_state->>'awaitingSlip')::BOOLEAN
       AND NOT public.is_sports_venue_owner(v_group.venue_id, p_user_id) THEN
      RAISE EXCEPTION 'OWNER_DECISION_REQUIRED';
    END IF;
    PERFORM public.sports_venue_booking_group_transition(
      v_group.id, 'confirmed', 'confirmed', p_user_id);
    UPDATE public.sports_venue_booking_groups
    SET decided_by = p_user_id, decided_at = now(),
        payment_received_status = CASE
          WHEN (v_state->>'hasPaymentSlip')::BOOLEAN
            THEN 'received' ELSE payment_received_status END,
        payment_received_amount = CASE
          WHEN (v_state->>'hasPaymentSlip')::BOOLEAN
            THEN COALESCE(payment_received_amount, total_amount_snapshot)
            ELSE payment_received_amount END
    WHERE id = v_group.id;
    RETURN 'confirmed';
  END IF;

  RAISE EXCEPTION 'GROUP_NOT_OPEN';
END;
$$;

-- Queue listing with personal defer state, server-side filters and
-- deterministic keyset pagination. Claims and refund cases are always
-- included (they are small); only the groups list is filtered/paged.
DROP FUNCTION IF EXISTS public.list_sports_venue_evidence_queue(UUID, UUID);
CREATE OR REPLACE FUNCTION public.list_sports_venue_evidence_queue(
  p_user_id UUID,
  p_venue_id UUID,
  p_filter VARCHAR DEFAULT 'all',
  p_limit INT DEFAULT 50,
  p_cursor_due TIMESTAMPTZ DEFAULT NULL,
  p_cursor_created TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_filter VARCHAR := COALESCE(p_filter, 'all');
  v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_rows JSONB;
  v_count INT;
  v_has_more BOOLEAN := false;
  v_next JSONB;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF v_filter NOT IN (
    'all', 'due_soon', 'overdue', 'payment', 'document', 'deferred'
  ) THEN
    RAISE EXCEPTION 'INVALID_QUEUE_FILTER';
  END IF;
  PERFORM public.housekeep_sports_venue_booking_groups_in_scope(
    NULL, p_venue_id);

  SELECT jsonb_agg(row) INTO v_rows
  FROM (
    SELECT JSONB_BUILD_OBJECT(
      'id', g.id, 'userId', g.user_id,
      'bookerName', NULLIF(btrim(
        CONCAT_WS(' ', u.first_name, u.last_name)), ''),
      'status', g.status, 'stage', g.stage,
      'approvalMode', g.booking_approval_mode_snapshot,
      'totalAmount', g.total_amount_snapshot,
      'currency', g.currency,
      'evidenceDueAt', g.evidence_due_at,
      'ownerDecisionDueAt', g.owner_decision_due_at,
      'paymentReceivedStatus', g.payment_received_status,
      'paymentReceivedAmount', g.payment_received_amount,
      'paymentDestination', g.payment_destination_snapshot,
      'rejectionReasonCode', g.rejection_reason_code,
      'deferredUntil', d.deferred_until,
      'firstStartsAt', (
        SELECT min(b0.starts_at) FROM public.sports_venue_bookings b0
        WHERE b0.booking_group_id = g.id),
      'hasPendingSlip', EXISTS (
        SELECT 1 FROM public.sports_venue_booking_evidence ps
        WHERE ps.booking_group_id = g.id AND ps.is_current
          AND ps.kind = 'payment_slip'
          AND ps.verification_status IN ('pending', 'verifying')),
      'createdAt', g.created_at,
      'bookings', COALESCE((
        SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'id', b.id, 'courtId', b.court_id, 'courtName', c.name,
          'startsAt', b.starts_at, 'endsAt', b.ends_at,
          'status', b.status,
          'priceTotal', b.price_total_snapshot)
          ORDER BY b.starts_at)
        FROM public.sports_venue_bookings b
        JOIN public.sports_venue_courts c ON c.id = b.court_id
        WHERE b.booking_group_id = g.id), '[]'::jsonb),
      'evidence', COALESCE((
        SELECT jsonb_agg(JSONB_BUILD_OBJECT(
          'id', e.id, 'requirementKey', e.requirement_key,
          'kind', e.kind, 'stage', e.stage,
          'revision', e.revision,
          'storagePath', e.storage_path,
          'mime', e.mime, 'sizeBytes', e.size_bytes,
          'verificationStatus', e.verification_status,
          'submittedBy', e.submitted_by,
          'createdAt', e.created_at)
          ORDER BY e.requirement_key)
        FROM public.sports_venue_booking_evidence e
        WHERE e.booking_group_id = g.id AND e.is_current),
        '[]'::jsonb)
    ) AS row
    FROM public.sports_venue_booking_groups g
    LEFT JOIN public.users u ON u.id = g.user_id
    LEFT JOIN public.sports_venue_queue_deferrals d
      ON d.booking_group_id = g.id AND d.manager_id = p_user_id
      AND d.deferred_until > now()
    WHERE g.venue_id = p_venue_id
      AND (g.status IN ('pending', 'awaiting_evidence')
           OR EXISTS (
             SELECT 1
             FROM public.sports_venue_booking_evidence e
             WHERE e.booking_group_id = g.id
               AND e.verification_status IN ('pending', 'verifying')))
      -- Personal defer hides the row everywhere except the deferred list.
      AND (CASE WHEN v_filter = 'deferred'
                THEN d.booking_group_id IS NOT NULL
                ELSE d.booking_group_id IS NULL END)
      AND (v_filter <> 'due_soon'
           OR g.evidence_due_at <= now() + INTERVAL '2 hours'
           OR g.owner_decision_due_at <= now() + INTERVAL '2 hours')
      AND (v_filter <> 'overdue'
           OR g.evidence_due_at < now()
           OR g.owner_decision_due_at < now())
      AND (v_filter <> 'payment'
           OR (g.status = 'awaiting_evidence' AND g.stage = 'payment')
           OR EXISTS (
             SELECT 1 FROM public.sports_venue_booking_evidence pe
             WHERE pe.booking_group_id = g.id AND pe.is_current
               AND pe.kind = 'payment_slip'
               AND pe.verification_status IN ('pending', 'verifying')))
      AND (v_filter <> 'document'
           OR EXISTS (
             SELECT 1 FROM public.sports_venue_booking_evidence de
             WHERE de.booking_group_id = g.id AND de.is_current
               AND de.kind = 'document'
               AND de.verification_status IN ('pending', 'verifying')))
      AND (p_cursor_id IS NULL OR
        (COALESCE(g.evidence_due_at, 'infinity'::timestamptz),
         g.created_at, g.id)
          > (COALESCE(p_cursor_due, 'infinity'::timestamptz),
             COALESCE(p_cursor_created, '-infinity'::timestamptz),
             p_cursor_id))
    ORDER BY COALESCE(g.evidence_due_at, 'infinity'::timestamptz),
             g.created_at, g.id
    LIMIT v_limit + 1
  ) rows;

  v_count := COALESCE(jsonb_array_length(v_rows), 0);
  IF v_count > v_limit THEN
    v_has_more := true;
    SELECT jsonb_agg(x.value ORDER BY x.ord) INTO v_rows
    FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS x(value, ord)
    WHERE x.ord <= v_limit;
    SELECT JSONB_BUILD_OBJECT(
      'due', v_rows -> (v_limit - 1) ->> 'evidenceDueAt',
      'created', v_rows -> (v_limit - 1) ->> 'createdAt',
      'id', v_rows -> (v_limit - 1) ->> 'id'
    ) INTO v_next;
  END IF;

  RETURN JSONB_BUILD_OBJECT(
    'serverNow', now(),
    'groups', COALESCE(v_rows, '[]'::jsonb),
    'hasMore', v_has_more,
    'nextCursor', v_next,
    'deferredCount', (
      SELECT count(*)::INT
      FROM public.sports_venue_queue_deferrals dd
      JOIN public.sports_venue_booking_groups gg
        ON gg.id = dd.booking_group_id
      WHERE dd.manager_id = p_user_id
        AND gg.venue_id = p_venue_id
        AND dd.deferred_until > now()
        AND (gg.status IN ('pending', 'awaiting_evidence')
             OR EXISTS (
               SELECT 1 FROM public.sports_venue_booking_evidence ee
               WHERE ee.booking_group_id = gg.id
                 AND ee.verification_status IN ('pending', 'verifying')))),
    'claims', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
        'id', cl.id, 'groupId', cl.booking_group_id,
        'reportedAmount', cl.reported_amount,
        'transferReference', cl.transfer_reference,
        'evidencePath', cl.evidence_path,
        'status', cl.status, 'createdAt', cl.created_at)
        ORDER BY cl.created_at)
      FROM public.sports_venue_booking_payment_claims cl
      JOIN public.sports_venue_booking_groups g
        ON g.id = cl.booking_group_id
      WHERE g.venue_id = p_venue_id AND cl.status = 'submitted'),
      '[]'::jsonb),
    'refundCases', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
        'id', rc.id, 'groupId', rc.booking_group_id,
        'bookingId', rc.booking_id,
        'allocatedAmount', rc.allocated_amount_snapshot,
        'refundAmount', rc.refund_amount,
        'reason', rc.reason, 'status', rc.status,
        'externalRef', rc.external_ref, 'createdAt', rc.created_at)
        ORDER BY rc.created_at)
      FROM public.sports_venue_booking_refund_cases rc
      JOIN public.sports_venue_booking_groups g
        ON g.id = rc.booking_group_id
      WHERE g.venue_id = p_venue_id
        AND rc.status IN ('open', 'approved', 'processing')),
      '[]'::jsonb));
END;
$$;

-- Bulk reject with per-group atomicity: each group is decided through the
-- single-group RPC inside its own savepoint, so one failure never blocks
-- the rest and reruns are safe (decided groups report their error inline
-- instead of aborting the batch). Bulk is reject-only by design — approve
-- and money decisions stay per-group with the evidence in view.
CREATE OR REPLACE FUNCTION public.decide_sports_venue_booking_groups_bulk(
  p_user_id UUID,
  p_venue_id UUID,
  p_group_ids UUID[],
  p_reason VARCHAR DEFAULT NULL,
  p_reason_code VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gid UUID;
  v_result TEXT;
  v_reason VARCHAR;
  v_results JSONB := '[]'::jsonb;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF NOT public.sports_venue_valid_reason_code(p_reason_code) THEN
    RAISE EXCEPTION 'INVALID_REASON_CODE';
  END IF;
  v_reason := COALESCE(NULLIF(btrim(p_reason), ''), p_reason_code);
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;
  IF p_group_ids IS NULL OR cardinality(p_group_ids) = 0 THEN
    RAISE EXCEPTION 'NO_GROUPS';
  END IF;
  IF cardinality(p_group_ids) > 50 THEN
    RAISE EXCEPTION 'TOO_MANY_GROUPS';
  END IF;

  FOREACH v_gid IN ARRAY p_group_ids LOOP
    BEGIN
      v_result := public.decide_sports_venue_booking_group(
        p_user_id, v_gid, 'reject', v_reason, NULL, p_reason_code);
      v_results := v_results || JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
        'groupId', v_gid, 'result', v_result));
    EXCEPTION WHEN OTHERS THEN
      v_results := v_results || JSONB_BUILD_ARRAY(JSONB_BUILD_OBJECT(
        'groupId', v_gid, 'error', SQLERRM));
    END;
  END LOOP;
  RETURN v_results;
END;
$$;

GRANT EXECUTE ON FUNCTION public.defer_sports_venue_queue_item(
  UUID, UUID, INT, VARCHAR
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decide_sports_venue_booking_group(
  UUID, UUID, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decide_sports_venue_booking_groups_bulk(
  UUID, UUID, UUID[], VARCHAR, VARCHAR
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_sports_venue_evidence_queue(
  UUID, UUID, VARCHAR, INT, TIMESTAMPTZ, TIMESTAMPTZ, UUID
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ===============
-- Claim evidence path hardening
-- ===============
-- The claim form can attach a slip image; the path must live under the
-- group's own claim prefix so a booker cannot alias another group's files.
CREATE OR REPLACE FUNCTION public.report_sports_venue_booking_payment_claim(
  p_user_id UUID,
  p_booking_group_id UUID,
  p_reported_amount NUMERIC DEFAULT NULL,
  p_transfer_reference VARCHAR DEFAULT NULL,
  p_evidence_path VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group RECORD;
  v_claim_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  SELECT g.* INTO v_group
  FROM public.sports_venue_booking_groups g
  WHERE g.id = p_booking_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;
  IF v_group.user_id <> p_user_id THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_group.status NOT IN (
    'forfeited', 'rejected', 'cancelled', 'expired', 'confirmed',
    'partially_cancelled', 'completed') THEN
    RAISE EXCEPTION 'GROUP_CLAIM_NOT_ALLOWED';
  END IF;
  IF p_reported_amount IS NOT NULL
     AND (p_reported_amount < 0 OR p_reported_amount > 99999999.99) THEN
    RAISE EXCEPTION 'INVALID_CLAIM_AMOUNT';
  END IF;
  IF NULLIF(p_evidence_path, '') IS NOT NULL
     AND (length(p_evidence_path) > 500
          OR p_evidence_path
             NOT LIKE ('groups/' || v_group.id::text || '/claim/%')) THEN
    RAISE EXCEPTION 'INVALID_STORAGE_PATH';
  END IF;

  INSERT INTO public.sports_venue_booking_payment_claims (
    booking_group_id, user_id, reported_amount, transfer_reference,
    evidence_path
  ) VALUES (
    v_group.id, p_user_id, p_reported_amount,
    NULLIF(p_transfer_reference, ''), NULLIF(p_evidence_path, '')
  )
  RETURNING id INTO v_claim_id;

  PERFORM public.notify_sports_venue_managers(
    v_group.venue_id, 'venue_booking.payment_claim',
    'ผู้จองรายงานการชำระเงิน',
    'มีการรายงานยอดชำระที่ต้องตรวจสอบ',
    JSONB_BUILD_OBJECT('groupId', v_group.id,
                       'claimId', v_claim_id,
                       'venueId', v_group.venue_id));
  RETURN v_claim_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.report_sports_venue_booking_payment_claim(
  UUID, UUID, NUMERIC, VARCHAR, VARCHAR
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
