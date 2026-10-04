CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_confirmed_completion
  ON public.sports_venue_bookings(ends_at)
  WHERE status = 'confirmed';

CREATE OR REPLACE FUNCTION public.expire_pending_sports_venue_bookings_in_scope(
  p_user_id UUID DEFAULT NULL,
  p_venue_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_count INT := 0;
BEGIN
  FOR r IN
    UPDATE public.sports_venue_bookings
    SET status = 'expired', updated_at = now()
    WHERE status = 'pending'
      AND starts_at <= now()
      AND (p_user_id IS NULL OR user_id = p_user_id)
      AND (p_venue_id IS NULL OR venue_id = p_venue_id)
    RETURNING id, user_id, venue_id
  LOOP
    PERFORM public.log_sports_venue_booking_event(
      r.id, 'expired', NULL, 'pending', 'expired');
    PERFORM public.sports_hub_notify(
      r.user_id, 'venue_booking', 'venue_booking.expired',
      'คำขอจองหมดอายุ',
      'คำขอจองของคุณหมดอายุเนื่องจากถึงเวลาเริ่มแล้ว',
      JSONB_BUILD_OBJECT('bookingId', r.id, 'venueId', r.venue_id));
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_sports_venue_bookings_in_scope(
  p_user_id UUID DEFAULT NULL,
  p_venue_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT := 0;
BEGIN
  UPDATE public.sports_venue_bookings
  SET status = 'completed', updated_at = now()
  WHERE status = 'confirmed'
    AND ends_at <= now()
    AND (p_user_id IS NULL OR user_id = p_user_id)
    AND (p_venue_id IS NULL OR venue_id = p_venue_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_pending_sports_venue_bookings()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.expire_pending_sports_venue_bookings_in_scope();
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_sports_venue_bookings()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.complete_sports_venue_bookings_in_scope();
END;
$$;

CREATE OR REPLACE FUNCTION public.housekeep_sports_venue_bookings()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired INT;
  v_completed INT;
BEGIN
  v_expired := public.expire_pending_sports_venue_bookings();
  v_completed := public.complete_sports_venue_bookings();
  RETURN JSONB_BUILD_OBJECT(
    'expiredPending', v_expired,
    'completedBookings', v_completed);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.expire_pending_sports_venue_bookings_in_scope(
  UUID, UUID
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.complete_sports_venue_bookings_in_scope(
  UUID, UUID
) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_pending_sports_venue_bookings()
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.complete_sports_venue_bookings()
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.housekeep_sports_venue_bookings()
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.decide_sports_venue_booking(
  p_user_id UUID,
  p_booking_id UUID,
  p_decision VARCHAR,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
  v_court RECORD;
  v_booking RECORD;
BEGIN
  SELECT b.court_id INTO v_court_id
  FROM public.sports_venue_bookings b
  WHERE b.id = p_booking_id;
  IF v_court_id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT c.id INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = v_court_id
  FOR UPDATE;
  IF v_court.id IS NULL THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;

  SELECT b.*, c.capacity, c.name AS court_name, v.name AS venue_name
  INTO v_booking
  FROM public.sports_venue_bookings b
  JOIN public.sports_venue_courts c ON c.id = b.court_id
  JOIN public.sports_venues v ON v.id = b.venue_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF NOT public.is_sports_venue_manager(v_booking.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF v_booking.status = 'expired' THEN
    RETURN 'expired';
  END IF;
  IF v_booking.status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;
  IF p_decision NOT IN ('approve','reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;

  IF v_booking.starts_at <= now() THEN
    PERFORM public.expire_pending_sports_venue_bookings_in_scope(
      v_booking.user_id, v_booking.venue_id);
    RETURN 'expired';
  END IF;

  IF p_decision = 'reject' THEN
    IF length(btrim(COALESCE(p_reason, ''))) = 0 THEN
      RAISE EXCEPTION 'REASON_REQUIRED';
    END IF;
    UPDATE public.sports_venue_bookings
    SET status = 'rejected', decided_by = p_user_id, decided_at = now(),
        rejection_reason = p_reason, updated_at = now()
    WHERE id = p_booking_id;

    PERFORM public.log_sports_venue_booking_event(
      p_booking_id, 'rejected', p_user_id, 'pending', 'rejected',
      p_reason := p_reason);
    PERFORM public.sports_hub_notify(
      v_booking.user_id, 'venue_booking', 'venue_booking.rejected',
      'คำขอจองถูกปฏิเสธ',
      FORMAT('%s — %s เหตุผล: %s', v_booking.venue_name,
             v_booking.court_name, p_reason),
      JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                         'venueId', v_booking.venue_id));
    RETURN 'rejected';
  END IF;

  IF public.sports_venue_slot_blocked(
       v_booking.court_id, v_booking.starts_at, v_booking.ends_at)
     OR public.sports_venue_confirmed_overlap_count(
          v_booking.court_id, v_booking.starts_at, v_booking.ends_at,
          p_booking_id) >= v_booking.capacity THEN
    PERFORM public.log_sports_venue_booking_event(
      p_booking_id, 'approve_conflict', p_user_id, 'pending', 'pending');
    PERFORM public.sports_hub_notify(
      v_booking.user_id, 'venue_booking', 'venue_booking.slot_conflict',
      'ช่วงเวลาที่ขอถูกใช้แล้ว',
      FORMAT('%s — %s กรุณาเลือกเวลาใหม่หรือยกเลิกคำขอ',
             v_booking.venue_name, v_booking.court_name),
      JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                         'venueId', v_booking.venue_id,
                         'action', 'change_slot_or_cancel'));
    RETURN 'conflict';
  END IF;

  UPDATE public.sports_venue_bookings
  SET status = 'confirmed', decided_by = p_user_id, decided_at = now(),
      updated_at = now()
  WHERE id = p_booking_id;

  PERFORM public.log_sports_venue_booking_event(
    p_booking_id, 'approved', p_user_id, 'pending', 'confirmed');
  PERFORM public.sports_hub_notify(
    v_booking.user_id, 'venue_booking', 'venue_booking.confirmed',
    'คำขอจองได้รับการอนุมัติ',
    FORMAT('%s — %s', v_booking.venue_name, v_booking.court_name),
    JSONB_BUILD_OBJECT('bookingId', p_booking_id,
                       'venueId', v_booking.venue_id));
  RETURN 'confirmed';
END;
$$;

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
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'starts_at' DESC) FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', b.id, 'courtId', b.court_id, 'venueId', b.venue_id,
        'sportId', b.sport_id, 'startsAt', b.starts_at, 'endsAt', b.ends_at,
        'status', b.status, 'venueName', v.name, 'timezone', v.timezone,
        'courtName', c.name,
        'unitLabel', b.unit_label_snapshot,
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
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'starts_at' ASC) FROM (
      SELECT JSONB_BUILD_OBJECT(
        'id', b.id, 'courtId', b.court_id, 'venueId', b.venue_id,
        'sportId', b.sport_id, 'startsAt', b.starts_at, 'endsAt', b.ends_at,
        'status', b.status, 'courtName', c.name, 'timezone', v.timezone,
        'unitLabel', b.unit_label_snapshot,
        'priceAmount', b.price_amount_snapshot,
        'pricingUnit', b.pricing_unit_snapshot,
        'priceTotal', b.price_total_snapshot,
        'priceBreakdown', b.price_breakdown_snapshot,
        'priceScheduleVersion', b.price_schedule_version_snapshot,
        'approvalMode', b.booking_approval_mode_snapshot,
        'bookerName', NULLIF(btrim(
          CONCAT_WS(' ', u.first_name, u.last_name)), ''),
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

CREATE OR REPLACE FUNCTION public.change_pending_venue_booking_slot(
  p_user_id UUID,
  p_booking_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_terms_version INT DEFAULT NULL,
  p_expected_price_schedule_version BIGINT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
  v_court RECORD;
  v_booking RECORD;
  v_price JSONB;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at
     OR p_ends_at <= now() THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;
  SELECT b.court_id INTO v_court_id
  FROM public.sports_venue_bookings b
  WHERE b.id = p_booking_id;
  IF v_court_id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;

  SELECT c.id INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = v_court_id
  FOR UPDATE;
  IF v_court.id IS NULL THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;

  SELECT b.* INTO v_booking
  FROM public.sports_venue_bookings b
  WHERE b.id = p_booking_id
  FOR UPDATE;
  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.user_id <> p_user_id THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_booking.status = 'expired' THEN
    RETURN;
  END IF;
  IF v_booking.status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;
  IF v_booking.starts_at <= now() THEN
    PERFORM public.expire_pending_sports_venue_bookings_in_scope(
      p_user_id, v_booking.venue_id);
    RETURN;
  END IF;

  PERFORM public.assert_sports_venue_booking_release(
    v_court_id, p_starts_at, p_ends_at);

  v_price := public.sports_venue_court_price_quote_internal(
    v_court_id, p_starts_at, p_ends_at
  );
  IF v_price->>'price_error' IS NOT NULL THEN
    RAISE EXCEPTION '%', v_price->>'price_error';
  END IF;
  IF (v_price->>'has_time_pricing')::BOOLEAN
     AND p_expected_price_schedule_version IS NULL THEN
    RAISE EXCEPTION 'PRICE_VERSION_REQUIRED';
  END IF;
  IF p_expected_price_schedule_version IS NOT NULL
     AND p_expected_price_schedule_version <>
         (v_price->>'price_schedule_version')::BIGINT THEN
    RAISE EXCEPTION 'PRICE_CHANGED';
  END IF;

  PERFORM public.change_pending_venue_booking_slot_legacy(
    p_user_id, p_booking_id, p_starts_at, p_ends_at, p_terms_version
  );
  UPDATE public.sports_venue_bookings
  SET price_amount_snapshot = NULLIF(v_price->>'price_amount', '')::NUMERIC,
      pricing_unit_snapshot = v_price->>'pricing_unit',
      price_total_snapshot = NULLIF(v_price->>'total_amount', '')::NUMERIC,
      price_breakdown_snapshot = COALESCE(v_price->'breakdown', '[]'::jsonb),
      price_schedule_version_snapshot =
        (v_price->>'price_schedule_version')::BIGINT
  WHERE id = p_booking_id AND user_id = p_user_id;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'
  ) THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_cron;
    EXCEPTION
      WHEN insufficient_privilege OR object_not_in_prerequisite_state THEN
        NULL;
    END;
  END IF;
END
$$;

DO $$
DECLARE
  v_job RECORD;
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'cron'
  ) THEN
    FOR v_job IN
      SELECT jobid FROM cron.job
      WHERE jobname = 'sports-hub-booking-housekeeping'
    LOOP
      PERFORM cron.unschedule(v_job.jobid);
    END LOOP;
    PERFORM cron.schedule(
      'sports-hub-booking-housekeeping',
      '* * * * *',
      'SELECT public.housekeep_sports_venue_bookings();'
    );
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
