CREATE OR REPLACE FUNCTION public.get_public_sports_venue_owner_profile(
  p_venue_id UUID
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT JSONB_BUILD_OBJECT(
    'display_name', NULLIF(
      BTRIM(CONCAT_WS(
        ' ',
        NULLIF(BTRIM(u.first_name), ''),
        CASE
          WHEN NULLIF(BTRIM(u.last_name), '') IS NOT NULL
          THEN LEFT(BTRIM(u.last_name), 1) || '.'
        END
      )),
      ''
    ),
    'avatar_url', NULLIF(BTRIM(u.profile_image_url), '')
  )
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id AND op.status = 'approved'
  JOIN public.users u ON u.id = op.user_id
  WHERE v.id = p_venue_id AND v.status = 'approved';
$$;

REVOKE ALL ON FUNCTION public.get_public_sports_venue_owner_profile(UUID)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_sports_venue_owner_profile(UUID)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
