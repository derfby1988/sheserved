-- Phase 21.7.14 — Book Court review experience: 1–10 overall score,
-- five mandatory category scores, popular topics from standard tags,
-- helpful votes and a server-side filtered/sorted review list.
--
-- Contract changes:
--   * sports_venue_reviews gains rating_10 (authoritative, 1–10);
--     backfilled once with rating_10 = rating * 2. The legacy rating
--     (1–5) column and submit_sports_venue_review RPC keep working for
--     old clients and write the scaled rating_10 — legacy p_rating is
--     never reinterpreted as a 10-point value.
--   * new reviews go through submit_sports_venue_review_v2 which
--     requires an overall 1–10 score plus a score for every active
--     category (surface/equipment/location/service/value), written
--     atomically with tags.
--   * sports_venue_review_helpful_votes is unique per (review, user);
--     self-votes and votes on non-published reviews are rejected.
--   * summaries/topics/list reads stay server-side and count only
--     published reviews; category averages use only reviews that carry
--     real category scores (legacy rows are never fabricated).

-- ===============
-- Schema
-- ===============

ALTER TABLE public.sports_venue_reviews
  ADD COLUMN IF NOT EXISTS rating_10 SMALLINT;

UPDATE public.sports_venue_reviews
SET rating_10 = rating * 2
WHERE rating_10 IS NULL;

ALTER TABLE public.sports_venue_reviews
  ALTER COLUMN rating_10 SET NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sports_venue_reviews_rating_10_check'
  ) THEN
    ALTER TABLE public.sports_venue_reviews
      ADD CONSTRAINT sports_venue_reviews_rating_10_check
      CHECK (rating_10 BETWEEN 1 AND 10);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.sports_venue_review_category_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key VARCHAR(40) NOT NULL UNIQUE,
  label_th VARCHAR(60) NOT NULL,
  label_en VARCHAR(60),
  is_active BOOLEAN NOT NULL DEFAULT true,
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.sports_venue_review_category_catalog
  (key, label_th, label_en, display_order)
SELECT * FROM (VALUES
  ('surface',   'สภาพพื้น/คุณภาพสนาม', 'Court surface & quality', 1),
  ('equipment', 'อุปกรณ์และสิ่งอำนวยความสะดวก', 'Equipment & facilities', 2),
  ('location',  'ทำเล/การเดินทาง', 'Location & access', 3),
  ('service',   'การบริการ', 'Service', 4),
  ('value',     'ความคุ้มค่า', 'Value for money', 5)
) AS seed(key, label_th, label_en, display_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sports_venue_review_category_catalog
);

CREATE TABLE IF NOT EXISTS public.sports_venue_review_category_scores (
  review_id UUID NOT NULL
    REFERENCES public.sports_venue_reviews(id) ON DELETE CASCADE,
  category_id UUID NOT NULL
    REFERENCES public.sports_venue_review_category_catalog(id),
  score SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 10),
  PRIMARY KEY (review_id, category_id)
);

CREATE TABLE IF NOT EXISTS public.sports_venue_review_helpful_votes (
  review_id UUID NOT NULL
    REFERENCES public.sports_venue_reviews(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (review_id, user_id)
);

-- ===============
-- Views (kept compatible: legacy 1–5 columns remain, *_10 columns added)
-- ===============

CREATE OR REPLACE VIEW public.sports_venue_reviews_public
WITH (security_invoker = on) AS
SELECT r.id, r.venue_id, r.court_id, r.booking_id, r.user_id,
       NULLIF(btrim(CONCAT_WS(' ', u.first_name, u.last_name)), '')
         AS user_display_name,
       u.profile_image_url AS user_avatar_url,
       r.rating, r.comment, r.created_at, r.rating_10
FROM public.sports_venue_reviews r
LEFT JOIN public.users u ON u.id = r.user_id
WHERE r.status = 'published';

-- average_rating keeps the legacy 1–5 meaning; average_rating_10 is the
-- new authoritative 1–10 aggregate used by the updated client.
CREATE OR REPLACE VIEW public.sports_venue_review_summary
WITH (security_invoker = on) AS
SELECT venue_id,
       ROUND(AVG(rating)::numeric, 2) AS average_rating,
       COUNT(*) AS review_count,
       ROUND(AVG(rating_10)::numeric, 2) AS average_rating_10
FROM public.sports_venue_reviews
WHERE status = 'published'
GROUP BY venue_id;

-- Category score rows are public only for published reviews.
CREATE OR REPLACE VIEW public.sports_venue_review_category_scores_public
WITH (security_invoker = on) AS
SELECT s.review_id, s.category_id, s.score
FROM public.sports_venue_review_category_scores s
JOIN public.sports_venue_reviews r ON r.id = s.review_id
WHERE r.status = 'published';

-- ===============
-- RPCs
-- ===============

-- Legacy 1–5 submit kept as a compatibility adapter: writes the scaled
-- rating_10 so old clients keep working until the contract is retired.
CREATE OR REPLACE FUNCTION public.submit_sports_venue_review(
  p_user_id UUID,
  p_booking_id UUID,
  p_rating INT,
  p_comment VARCHAR DEFAULT NULL,
  p_tag_ids UUID[] DEFAULT NULL,
  p_custom_tags TEXT[] DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_review_id UUID;
  v_tag_count INT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'INVALID_RATING';
  END IF;
  IF p_comment IS NOT NULL AND length(p_comment) > 500 THEN
    RAISE EXCEPTION 'COMMENT_TOO_LONG';
  END IF;

  v_tag_count := COALESCE(array_length(p_tag_ids, 1), 0)
               + COALESCE(array_length(p_custom_tags, 1), 0);
  IF v_tag_count > 5 THEN
    RAISE EXCEPTION 'TOO_MANY_TAGS';
  END IF;

  SELECT b.* INTO v_booking
  FROM public.sports_venue_bookings b
  WHERE b.id = p_booking_id
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.user_id <> p_user_id THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.status <> 'completed' THEN
    RAISE EXCEPTION 'BOOKING_NOT_COMPLETED';
  END IF;
  -- Owners/managers may not review their own venue.
  IF public.is_sports_venue_manager(v_booking.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'SELF_REVIEW_NOT_ALLOWED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.sports_venue_reviews r
    WHERE r.booking_id = p_booking_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_REVIEWED';
  END IF;

  -- Standard tags must come from the catalog.
  IF p_tag_ids IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_tag_ids) t
    WHERE NOT EXISTS (
      SELECT 1 FROM public.sports_venue_review_tag_catalog c
      WHERE c.id = t AND c.is_active
    )
  ) THEN
    RAISE EXCEPTION 'INVALID_TAG';
  END IF;

  -- Review + tags are written atomically in this transaction. The
  -- 10-point score is the scaled legacy value, never a reinterpretation.
  INSERT INTO public.sports_venue_reviews (
    venue_id, court_id, booking_id, user_id, rating, rating_10, comment
  ) VALUES (
    v_booking.venue_id, v_booking.court_id, p_booking_id, p_user_id,
    p_rating, p_rating * 2,
    NULLIF(btrim(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;

  INSERT INTO public.sports_venue_review_tags (review_id, tag_id)
  SELECT v_review_id, t FROM unnest(COALESCE(p_tag_ids, ARRAY[]::uuid[])) t
  ON CONFLICT DO NOTHING;

  INSERT INTO public.sports_venue_review_custom_tags (review_id, label)
  SELECT v_review_id, btrim(label)
  FROM unnest(COALESCE(p_custom_tags, ARRAY[]::text[])) AS label
  WHERE length(btrim(label)) BETWEEN 1 AND 60;

  RETURN v_review_id;
END;
$$;

-- v2 submit: overall 1–10 plus a 1–10 score for every active category.
-- p_category_scores is a JSONB object keyed by category id (uuid text)
-- with integer scores.
CREATE OR REPLACE FUNCTION public.submit_sports_venue_review_v2(
  p_user_id UUID,
  p_booking_id UUID,
  p_rating_10 INT,
  p_category_scores JSONB,
  p_comment VARCHAR DEFAULT NULL,
  p_tag_ids UUID[] DEFAULT NULL,
  p_custom_tags TEXT[] DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_review_id UUID;
  v_tag_count INT;
  v_category RECORD;
  v_score NUMERIC;
  v_seen UUID[];
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_rating_10 IS NULL OR p_rating_10 < 1 OR p_rating_10 > 10 THEN
    RAISE EXCEPTION 'INVALID_RATING';
  END IF;
  IF p_comment IS NOT NULL AND length(p_comment) > 500 THEN
    RAISE EXCEPTION 'COMMENT_TOO_LONG';
  END IF;
  IF p_category_scores IS NULL OR jsonb_typeof(p_category_scores) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_CATEGORY_SCORES';
  END IF;

  -- Every active category must be present exactly once with a 1–10 score.
  v_seen := ARRAY[]::uuid[];
  FOR v_category IN
    SELECT key, value FROM jsonb_each(p_category_scores)
  LOOP
    BEGIN
      v_score := (v_category.value)::numeric;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'INVALID_CATEGORY_SCORES';
    END;
    IF v_score <> trunc(v_score) OR v_score < 1 OR v_score > 10 THEN
      RAISE EXCEPTION 'INVALID_CATEGORY_SCORES';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.sports_venue_review_category_catalog c
      WHERE c.id = v_category.key::uuid AND c.is_active
    ) THEN
      RAISE EXCEPTION 'INVALID_CATEGORY';
    END IF;
    v_seen := v_seen || v_category.key::uuid;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM public.sports_venue_review_category_catalog c
    WHERE c.is_active AND NOT (c.id = ANY(v_seen))
  ) THEN
    RAISE EXCEPTION 'MISSING_CATEGORY_SCORES';
  END IF;

  v_tag_count := COALESCE(array_length(p_tag_ids, 1), 0)
               + COALESCE(array_length(p_custom_tags, 1), 0);
  IF v_tag_count > 5 THEN
    RAISE EXCEPTION 'TOO_MANY_TAGS';
  END IF;

  SELECT b.* INTO v_booking
  FROM public.sports_venue_bookings b
  WHERE b.id = p_booking_id
  FOR UPDATE;

  IF v_booking.id IS NULL OR v_booking.user_id <> p_user_id THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND';
  END IF;
  IF v_booking.status <> 'completed' THEN
    RAISE EXCEPTION 'BOOKING_NOT_COMPLETED';
  END IF;
  -- Owners/managers may not review their own venue.
  IF public.is_sports_venue_manager(v_booking.venue_id, p_user_id) THEN
    RAISE EXCEPTION 'SELF_REVIEW_NOT_ALLOWED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.sports_venue_reviews r
    WHERE r.booking_id = p_booking_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_REVIEWED';
  END IF;

  -- Standard tags must come from the catalog.
  IF p_tag_ids IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_tag_ids) t
    WHERE NOT EXISTS (
      SELECT 1 FROM public.sports_venue_review_tag_catalog c
      WHERE c.id = t AND c.is_active
    )
  ) THEN
    RAISE EXCEPTION 'INVALID_TAG';
  END IF;

  -- The review targets the court on the completed booking; the legacy
  -- 1–5 column stores the folded value for old readers.
  INSERT INTO public.sports_venue_reviews (
    venue_id, court_id, booking_id, user_id, rating, rating_10, comment
  ) VALUES (
    v_booking.venue_id, v_booking.court_id, p_booking_id, p_user_id,
    GREATEST(1, LEAST(5, CEIL(p_rating_10::numeric / 2)))::int,
    p_rating_10,
    NULLIF(btrim(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;

  INSERT INTO public.sports_venue_review_category_scores (
    review_id, category_id, score
  )
  SELECT v_review_id, key::uuid, (value)::int
  FROM jsonb_each(p_category_scores);

  INSERT INTO public.sports_venue_review_tags (review_id, tag_id)
  SELECT v_review_id, t FROM unnest(COALESCE(p_tag_ids, ARRAY[]::uuid[])) t
  ON CONFLICT DO NOTHING;

  INSERT INTO public.sports_venue_review_custom_tags (review_id, label)
  SELECT v_review_id, btrim(label)
  FROM unnest(COALESCE(p_custom_tags, ARRAY[]::text[])) AS label
  WHERE length(btrim(label)) BETWEEN 1 AND 60;

  RETURN v_review_id;
END;
$$;

-- Helpful vote toggle: one vote per (review, user), idempotent, only on
-- published reviews, never on the reviewer's own review.
CREATE OR REPLACE FUNCTION public.set_sports_venue_review_helpful(
  p_user_id UUID,
  p_review_id UUID,
  p_helpful BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_review RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT id, user_id INTO v_review
  FROM public.sports_venue_reviews
  WHERE id = p_review_id AND status = 'published';
  IF v_review.id IS NULL THEN
    RAISE EXCEPTION 'REVIEW_NOT_FOUND';
  END IF;
  IF v_review.user_id = p_user_id THEN
    RAISE EXCEPTION 'SELF_VOTE_NOT_ALLOWED';
  END IF;

  IF COALESCE(p_helpful, false) THEN
    INSERT INTO public.sports_venue_review_helpful_votes (review_id, user_id)
    VALUES (p_review_id, p_user_id)
    ON CONFLICT (review_id, user_id) DO NOTHING;
  ELSE
    DELETE FROM public.sports_venue_review_helpful_votes
    WHERE review_id = p_review_id AND user_id = p_user_id;
  END IF;
END;
$$;

-- Category catalog for the review form.
CREATE OR REPLACE FUNCTION public.list_sports_venue_review_categories()
RETURNS SETOF public.sports_venue_review_category_catalog
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.sports_venue_review_category_catalog
  WHERE is_active
  ORDER BY display_order, label_th;
END;
$$;

-- Aggregated review summary for one venue (optionally scoped to one
-- court). Everything counts published reviews only; category averages
-- use real per-category scores — legacy reviews without scores never
-- enter the denominator.
CREATE OR REPLACE FUNCTION public.get_sports_venue_review_summary_v2(
  p_venue_id UUID,
  p_court_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'average_rating', ROUND(AVG(r.rating_10)::numeric, 2),
    'review_count', COUNT(*),
    'band_counts', jsonb_build_object(
      'excellent', COUNT(*) FILTER (WHERE r.rating_10 >= 9),
      'good',      COUNT(*) FILTER (WHERE r.rating_10 BETWEEN 7 AND 8),
      'fair',      COUNT(*) FILTER (WHERE r.rating_10 BETWEEN 5 AND 6),
      'poor',      COUNT(*) FILTER (WHERE r.rating_10 BETWEEN 3 AND 4),
      'very_poor', COUNT(*) FILTER (WHERE r.rating_10 <= 2)
    ),
    'categories', COALESCE((
      SELECT jsonb_agg(cat ORDER BY (cat->>'display_order')::int)
      FROM (
        SELECT jsonb_build_object(
          'category_id', c.id,
          'key', c.key,
          'label_th', c.label_th,
          'label_en', c.label_en,
          'display_order', c.display_order,
          'average', ROUND(
            AVG(s.score) FILTER (WHERE r2.id IS NOT NULL)::numeric, 2),
          'sample_count', COUNT(r2.id)
        ) AS cat
        FROM public.sports_venue_review_category_catalog c
        LEFT JOIN public.sports_venue_review_category_scores s
          ON s.category_id = c.id
        LEFT JOIN public.sports_venue_reviews r2
          ON r2.id = s.review_id
         AND r2.status = 'published'
         AND r2.venue_id = p_venue_id
         AND (p_court_id IS NULL OR r2.court_id = p_court_id)
        WHERE c.is_active
        GROUP BY c.id, c.key, c.label_th, c.label_en, c.display_order
      ) cats
    ), '[]'::jsonb),
    'topics', COALESCE((
      SELECT jsonb_agg(t ORDER BY (t->>'review_count')::int DESC, t->>'label_th')
      FROM (
        SELECT jsonb_build_object(
          'tag_id', tc.id,
          'label_th', tc.label_th,
          'label_en', tc.label_en,
          'review_count', COUNT(*)
        ) AS t
        FROM public.sports_venue_review_tags rt
        JOIN public.sports_venue_review_tag_catalog tc
          ON tc.id = rt.tag_id AND tc.is_active
        JOIN public.sports_venue_reviews r3 ON r3.id = rt.review_id
        WHERE r3.status = 'published'
          AND r3.venue_id = p_venue_id
          AND (p_court_id IS NULL OR r3.court_id = p_court_id)
        GROUP BY tc.id, tc.label_th, tc.label_en
      ) topics
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.sports_venue_reviews r
  WHERE r.status = 'published'
    AND r.venue_id = p_venue_id
    AND (p_court_id IS NULL OR r.court_id = p_court_id);

  RETURN COALESCE(v_result, jsonb_build_object(
    'average_rating', NULL,
    'review_count', 0,
    'band_counts', '{}'::jsonb,
    'categories', '[]'::jsonb,
    'topics', '[]'::jsonb
  ));
END;
$$;

-- Server-side filtered/sorted/paginated review list for one venue.
-- p_sort: 'helpful' (default) | 'newest' | 'highest' | 'lowest'.
CREATE OR REPLACE FUNCTION public.list_sports_venue_reviews_v2(
  p_venue_id UUID,
  p_court_id UUID DEFAULT NULL,
  p_tag_id UUID DEFAULT NULL,
  p_min_rating_10 INT DEFAULT NULL,
  p_max_rating_10 INT DEFAULT NULL,
  p_sort VARCHAR DEFAULT 'helpful',
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0,
  p_viewer_id UUID DEFAULT NULL
)
RETURNS TABLE(
  id UUID,
  venue_id UUID,
  court_id UUID,
  user_id UUID,
  court_name VARCHAR,
  sport_name TEXT,
  user_display_name TEXT,
  user_avatar_url TEXT,
  rating_10 SMALLINT,
  comment VARCHAR,
  created_at TIMESTAMPTZ,
  helpful_count INT,
  viewer_voted BOOLEAN,
  tag_labels TEXT[],
  total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH filtered AS (
    SELECT
      r.id,
      r.venue_id,
      r.court_id,
      r.user_id,
      c.name AS court_name,
      s.name_th AS sport_name,
      NULLIF(btrim(CONCAT_WS(' ', u.first_name, u.last_name)), '')
        AS user_display_name,
      u.profile_image_url AS user_avatar_url,
      r.rating_10,
      r.comment,
      r.created_at,
      (SELECT COUNT(*)::int
         FROM public.sports_venue_review_helpful_votes hv
        WHERE hv.review_id = r.id) AS helpful_count,
      (p_viewer_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.sports_venue_review_helpful_votes hv
        WHERE hv.review_id = r.id AND hv.user_id = p_viewer_id
      )) AS viewer_voted,
      (
        SELECT array_agg(label ORDER BY label)
        FROM (
          SELECT tc.label_th::text AS label
          FROM public.sports_venue_review_tags rt
          JOIN public.sports_venue_review_tag_catalog tc
            ON tc.id = rt.tag_id
          WHERE rt.review_id = r.id
          UNION ALL
          SELECT ct.label::text
          FROM public.sports_venue_review_custom_tags ct
          WHERE ct.review_id = r.id
        ) labels
      ) AS tag_labels
    FROM public.sports_venue_reviews r
    JOIN public.sports_venue_courts c ON c.id = r.court_id
    LEFT JOIN public.sports s ON s.id = c.sport_id
    LEFT JOIN public.users u ON u.id = r.user_id
    WHERE r.status = 'published'
      AND r.venue_id = p_venue_id
      AND (p_court_id IS NULL OR r.court_id = p_court_id)
      AND (p_min_rating_10 IS NULL OR r.rating_10 >= p_min_rating_10)
      AND (p_max_rating_10 IS NULL OR r.rating_10 <= p_max_rating_10)
      AND (p_tag_id IS NULL OR EXISTS (
        SELECT 1 FROM public.sports_venue_review_tags rt
        WHERE rt.review_id = r.id AND rt.tag_id = p_tag_id
      ))
  )
  SELECT
    f.id, f.venue_id, f.court_id, f.user_id, f.court_name, f.sport_name,
    f.user_display_name, f.user_avatar_url, f.rating_10, f.comment,
    f.created_at, f.helpful_count, f.viewer_voted,
    COALESCE(f.tag_labels, ARRAY[]::text[]) AS tag_labels,
    COUNT(*) OVER () AS total_count
  FROM filtered f
  ORDER BY
    CASE WHEN p_sort = 'helpful' OR p_sort IS NULL
      THEN f.helpful_count END DESC NULLS LAST,
    CASE WHEN p_sort = 'highest'
      THEN f.rating_10 END DESC NULLS LAST,
    CASE WHEN p_sort = 'lowest'
      THEN f.rating_10 END ASC NULLS LAST,
    f.created_at DESC,
    f.id
  LIMIT COALESCE(p_limit, 20)
  OFFSET COALESCE(p_offset, 0);
END;
$$;

-- ===============
-- RLS
-- ===============

ALTER TABLE public.sports_venue_review_category_catalog
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_review_category_scores
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_venue_review_helpful_votes
  ENABLE ROW LEVEL SECURITY;

-- Category catalog is public-readable; scores and votes are read through
-- the views/RPCs above and written only by SECURITY DEFINER functions, so
-- no direct read/write policies are opened on them.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'sports_venue_review_category_catalog'
      AND policyname = 'sports_venue_review_category_catalog_select_all'
  ) THEN
    CREATE POLICY sports_venue_review_category_catalog_select_all
      ON public.sports_venue_review_category_catalog
      FOR SELECT USING (true);
  END IF;
  -- Category scores are readable only for published reviews; writes go
  -- through the SECURITY DEFINER RPCs above.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'sports_venue_review_category_scores'
      AND policyname = 'sports_venue_review_category_scores_select_published'
  ) THEN
    CREATE POLICY sports_venue_review_category_scores_select_published
      ON public.sports_venue_review_category_scores
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.sports_venue_reviews r
          WHERE r.id = review_id AND r.status = 'published'
        )
      );
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
