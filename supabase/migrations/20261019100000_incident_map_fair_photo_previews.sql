CREATE OR REPLACE FUNCTION public.get_emergency_incident_map(
  p_category_id UUID,
  p_south NUMERIC,
  p_west NUMERIC,
  p_north NUMERIC,
  p_east NUMERIC,
  p_zoom INT,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 300
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_mode TEXT;
  v_result JSONB;
BEGIN
  IF p_category_id IS NULL THEN
    RAISE EXCEPTION 'CATEGORY_REQUIRED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM donation_categories c
    WHERE c.id = p_category_id AND c.is_emergency = true
  ) THEN
    RAISE EXCEPTION 'CATEGORY_NOT_EMERGENCY';
  END IF;
  IF p_zoom IS NULL OR p_zoom < 0 OR p_zoom > 22 THEN
    RAISE EXCEPTION 'INVALID_ZOOM';
  END IF;
  IF p_south IS NULL OR p_west IS NULL OR p_north IS NULL OR p_east IS NULL
     OR p_south > p_north OR p_west > p_east
     OR p_south < -90 OR p_south > 90 OR p_north < -90 OR p_north > 90
     OR p_west < -180 OR p_west > 180 OR p_east < -180 OR p_east > 180 THEN
    RAISE EXCEPTION 'INVALID_BOUNDS';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'INVALID_LIMIT';
  END IF;

  v_mode := CASE WHEN p_zoom >= 12 THEN 'points' ELSE 'clusters' END;

  WITH fp AS (
    SELECT v.id, v.category_id, v.created_at, t.latitude, t.longitude
    FROM videos v
    CROSS JOIN LATERAL (
      SELECT t.latitude, t.longitude
      FROM video_gps_tracks t
      WHERE t.video_id = v.id
      ORDER BY t.timestamp_offset ASC
      LIMIT 1
    ) t
    WHERE v.type IN ('emergency', 'emergency_photo')
      AND v.category_id = p_category_id
  ),
  vp AS (
    SELECT fp.*,
           CASE WHEN fp.created_at IS NULL OR fp.created_at > now()
                THEN NULL ELSE now() - fp.created_at END AS age
    FROM fp
    WHERE fp.latitude IS NOT NULL AND fp.longitude IS NOT NULL
      AND fp.latitude BETWEEN p_south AND p_north
      AND fp.longitude BETWEEN p_west AND p_east
  ),
  agg AS (
    SELECT
      COUNT(*) FILTER (WHERE age <= interval '24 hours') AS red,
      COUNT(*) FILTER (WHERE age >  interval '24 hours' AND age <= interval '7 days') AS orange,
      COUNT(*) FILTER (WHERE age >  interval '7 days'  AND age <= interval '35 days') AS gold,
      COUNT(*) FILTER (WHERE age >  interval '35 days' AND age <= interval '365 days') AS gray,
      COUNT(*) FILTER (WHERE age >  interval '365 days') AS black,
      COUNT(*) FILTER (WHERE age IS NULL) AS invalid_time,
      (
        SELECT COUNT(*) FROM videos v2
        WHERE v2.type IN ('emergency', 'emergency_photo')
          AND v2.category_id = p_category_id
          AND NOT EXISTS (
            SELECT 1 FROM (
              SELECT t.latitude, t.longitude
              FROM video_gps_tracks t
              WHERE t.video_id = v2.id
              ORDER BY t.timestamp_offset ASC
              LIMIT 1
            ) c
            WHERE c.latitude IS NOT NULL AND c.longitude IS NOT NULL
              AND c.latitude BETWEEN -90 AND 90
              AND c.longitude BETWEEN -180 AND 180
              AND (c.latitude <> 0 OR c.longitude <> 0)
          )
      ) AS no_usable_coordinate
    FROM vp
  ),
  cell AS (SELECT 180.0 / pow(2, p_zoom) AS deg),
  clusters AS (
    SELECT avg(vp.latitude) AS lat,
           avg(vp.longitude) AS lng,
           count(*) AS cnt,
           count(*) FILTER (WHERE age <= interval '24 hours') AS red,
           count(*) FILTER (WHERE age >  interval '24 hours' AND age <= interval '7 days') AS orange,
           count(*) FILTER (WHERE age >  interval '7 days'  AND age <= interval '35 days') AS gold,
           count(*) FILTER (WHERE age >  interval '35 days' AND age <= interval '365 days') AS gray,
           count(*) FILTER (WHERE age >  interval '365 days') AS black
    FROM vp, cell
    GROUP BY floor(vp.latitude / cell.deg), floor(vp.longitude / cell.deg)
  ),
  page AS (
    SELECT vp.*
    FROM vp
    WHERE (p_cursor_created_at IS NULL
           OR (vp.created_at, vp.id) < (p_cursor_created_at, p_cursor_id))
    ORDER BY vp.created_at DESC, vp.id DESC
    LIMIT p_limit + 1
  ),
  numbered AS (
    SELECT page.*,
           row_number() OVER (ORDER BY page.created_at DESC, page.id DESC) AS rn
    FROM page
  ),
  kept AS (SELECT * FROM numbered WHERE rn <= p_limit),
  has_more AS (SELECT EXISTS (SELECT 1 FROM numbered WHERE rn > p_limit) AS v),
  last_kept AS (
    SELECT created_at, id FROM kept
    ORDER BY created_at DESC, id DESC
    LIMIT 1
  ),
  photos AS (
    SELECT k.id AS video_id,
           COALESCE(
             jsonb_agg(
               jsonb_build_object(
                 'id', ph.id,
                 'url', CASE WHEN ph.blur_status = 'completed'
                             THEN ph.photo_url ELSE '' END,
                 'blurStatus', ph.blur_status,
                 'createdAt', to_char(ph.created_at AT TIME ZONE 'UTC',
                                      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
               )
               ORDER BY ph.sender_rank, ph.created_at DESC NULLS LAST, ph.id DESC
             ),
             '[]'::jsonb
           ) AS photo_list
    FROM kept k
    JOIN LATERAL (
      SELECT id, photo_url, blur_status, created_at, sender_rank
      FROM (
        SELECT id, photo_url, blur_status, created_at,
               row_number() OVER (
                 PARTITION BY user_id
                 ORDER BY created_at DESC NULLS LAST, id DESC
               ) AS sender_rank
        FROM thai_mhung_photos
        WHERE video_id = k.id AND blur_status IN ('completed', 'blurring')
      ) sender_photos
      WHERE sender_rank <= 15
      ORDER BY sender_rank, created_at DESC NULLS LAST, id DESC
      LIMIT 15
    ) ph ON true
    GROUP BY k.id
  )
  SELECT jsonb_build_object(
    'mode', v_mode,
    'zoom', p_zoom,
    'truncated', false,
    'legend', jsonb_build_object(
      'red', agg.red, 'orange', agg.orange, 'gold', agg.gold,
      'gray', agg.gray, 'black', agg.black,
      'total', agg.red + agg.orange + agg.gold + agg.gray + agg.black
    ),
    'excluded', jsonb_build_object(
      'noUsableCoordinate', agg.no_usable_coordinate,
      'invalidTime', agg.invalid_time
    ),
    'items', CASE
      WHEN v_mode = 'clusters' THEN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'kind', 'cluster', 'lat', cl.lat, 'lng', cl.lng, 'count', cl.cnt,
          'byBucket', jsonb_build_object(
            'red', cl.red, 'orange', cl.orange, 'gold', cl.gold,
            'gray', cl.gray, 'black', cl.black
          )
        ) ORDER BY cl.cnt DESC, cl.lat, cl.lng), '[]'::jsonb)
        FROM clusters cl
      )
      ELSE (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'kind', 'point',
            'id', k.id,
            'categoryId', k.category_id,
            'createdAt', to_char(k.created_at AT TIME ZONE 'UTC',
                                 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'bucket', CASE
              WHEN k.age <= interval '24 hours' THEN 'red'
              WHEN k.age <= interval '7 days' THEN 'orange'
              WHEN k.age <= interval '35 days' THEN 'gold'
              WHEN k.age <= interval '365 days' THEN 'gray'
              ELSE 'black'
            END,
            'lat', k.latitude,
            'lng', k.longitude,
            'photos', COALESCE(p.photo_list, '[]'::jsonb)
          )
          ORDER BY k.created_at DESC, k.id DESC
        ), '[]'::jsonb)
        FROM kept k
        LEFT JOIN photos p ON p.video_id = k.id
      )
    END,
    'nextCursor', CASE
      WHEN (SELECT v FROM has_more) AND v_mode = 'points' THEN
        translate(
          encode(
            convert_to(
              '{"c":"' || to_char(
                (SELECT created_at FROM last_kept) AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
              ) || '","i":"' || (SELECT id::text FROM last_kept) || '"}',
              'utf8'
            ),
            'base64'
          ),
          '+/=',
          '-_'
        )
      ELSE NULL
    END
  )
  INTO v_result
  FROM agg;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_emergency_incident_map(UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INT, TIMESTAMPTZ, UUID, INT)
  TO anon, authenticated;
