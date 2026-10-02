-- Return decided_at to the booker so the app can order rejected bookings
-- by when the owner actually rejected them, not by slot time.
CREATE OR REPLACE FUNCTION public.list_my_sports_venue_bookings(
  p_user_id UUID,
  p_statuses VARCHAR[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
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

NOTIFY pgrst, 'reload schema';
