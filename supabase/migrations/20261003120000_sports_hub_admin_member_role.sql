-- ===============
-- Distinguish admin-override access in list_my_sports_venues.member_role.
--
-- is_sports_venue_manager() returns true for Sheserved admins on every
-- venue, so the "เป็นเจ้าของ" quick filter surfaced all venues to admins
-- even when they neither own nor were invited to manage them. The RPC now
-- reports member_role='admin' for that path (real owner/member rows keep
-- 'owner'/'manager'), letting the client scope the personal filter to
-- actual memberships while dashboards keep the full admin scope.
-- ===============

DROP FUNCTION IF EXISTS public.list_my_sports_venues(uuid);
CREATE OR REPLACE FUNCTION public.list_my_sports_venues(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  name VARCHAR,
  province TEXT,
  district TEXT,
  timezone VARCHAR,
  status VARCHAR,
  rejection_reason VARCHAR,
  court_count BIGINT,
  member_role VARCHAR,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN QUERY
  SELECT v.id, v.name, v.province, v.district, v.timezone, v.status,
         v.rejection_reason,
         (SELECT count(*) FROM public.sports_venue_courts c
           WHERE c.venue_id = v.id),
         CASE
           WHEN op.user_id = p_user_id THEN 'owner'::varchar
           WHEN m.user_id IS NOT NULL THEN COALESCE(m.role, 'manager')::varchar
           ELSE 'admin'::varchar
         END AS member_role,
         v.created_at
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  LEFT JOIN public.sports_venue_owner_members m
    ON m.venue_id = v.id AND m.user_id = p_user_id AND m.is_active
  WHERE public.is_sports_venue_manager(v.id, p_user_id)
  ORDER BY v.created_at DESC;
END;
$$;
