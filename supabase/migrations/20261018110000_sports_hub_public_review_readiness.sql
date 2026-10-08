CREATE INDEX IF NOT EXISTS idx_sports_venue_bookings_review_readiness
  ON public.sports_venue_bookings(venue_id, ends_at)
  WHERE status IN ('confirmed', 'completed');

CREATE OR REPLACE FUNCTION public.list_public_sports_venue_review_readiness(
  p_venue_ids UUID[]
)
RETURNS TABLE (venue_id UUID, has_reviewable_booking BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_venue_ids IS NULL OR cardinality(p_venue_ids) = 0 THEN
    RETURN;
  END IF;
  IF cardinality(p_venue_ids) > 100 THEN
    RAISE EXCEPTION 'TOO_MANY_VENUES';
  END IF;

  RETURN QUERY
  SELECT v.id,
         EXISTS (
           SELECT 1
           FROM public.sports_venue_bookings b
           WHERE b.venue_id = v.id
             AND b.status IN ('confirmed', 'completed')
             AND b.ends_at <= now()
             AND NOT public.is_sports_venue_manager(v.id, b.user_id)
             AND NOT EXISTS (
               SELECT 1 FROM public.sports_venue_reviews r
               WHERE r.booking_id = b.id
             )
         )
  FROM public.sports_venues v
  WHERE v.id = ANY(p_venue_ids)
    AND v.status = 'approved';
END;
$$;

REVOKE ALL ON FUNCTION public.list_public_sports_venue_review_readiness(UUID[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_public_sports_venue_review_readiness(UUID[])
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
