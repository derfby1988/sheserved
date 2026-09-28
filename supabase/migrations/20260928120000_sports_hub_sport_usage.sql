-- ===============
-- Sports Hub 21.7.13 — shared sport usage events and ranked catalog
--
-- Records real user detail-opens per (sport, source domain) so the shared
-- sport bar can order the approved catalog by personal usage. Page-balanced
-- smoothing keeps a page with many entities from dominating, and retrying
-- with the same event_id never double counts.
-- ===============

CREATE TABLE IF NOT EXISTS public.sport_detail_open_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sport_id UUID NOT NULL REFERENCES public.sports(id) ON DELETE CASCADE,
  source_domain TEXT NOT NULL CHECK (
    source_domain IN ('buddies', 'courts', 'coaches')
  ),
  entity_id UUID,
  signal_type TEXT NOT NULL DEFAULT 'detail_open' CHECK (
    signal_type = 'detail_open'
  ),
  weight NUMERIC NOT NULL DEFAULT 1 CHECK (weight > 0),
  event_id UUID NOT NULL,
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, event_id)
);

CREATE INDEX IF NOT EXISTS sport_detail_open_events_user_domain_idx
  ON public.sport_detail_open_events (user_id, source_domain, sport_id);

CREATE INDEX IF NOT EXISTS sport_detail_open_events_dedupe_idx
  ON public.sport_detail_open_events
  (user_id, source_domain, entity_id, sport_id, opened_at);

ALTER TABLE public.sport_detail_open_events ENABLE ROW LEVEL SECURITY;
-- Events carry user identity -> no SELECT/INSERT/UPDATE policies; all access
-- goes through the authorized RPCs below (same pattern as venue bookings).

-- Records one detail-open event. Returns true when a row was inserted.
-- Retries with the same p_event_id return false without counting again, and
-- re-opening the same entity for the same sport inside 24h is ignored.
CREATE OR REPLACE FUNCTION public.record_sport_detail_open(
  p_user_id UUID,
  p_event_id UUID,
  p_sport_id UUID,
  p_source_domain TEXT,
  p_entity_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_source_domain NOT IN ('buddies', 'courts', 'coaches') THEN
    RAISE EXCEPTION 'INVALID_DOMAIN';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.sports
    WHERE id = p_sport_id AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'INVALID_SPORT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.sport_detail_open_events e
    WHERE e.user_id = p_user_id
      AND e.source_domain = p_source_domain
      AND e.sport_id = p_sport_id
      AND e.entity_id IS NOT DISTINCT FROM p_entity_id
      AND e.opened_at > now() - interval '24 hours'
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO public.sport_detail_open_events (
    user_id,
    sport_id,
    source_domain,
    entity_id,
    event_id
  )
  VALUES (p_user_id, p_sport_id, p_source_domain, p_entity_id, p_event_id)
  ON CONFLICT (user_id, event_id) DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id IS NOT NULL;
END;
$$;

-- Returns the full approved sport catalog ordered for the given user.
-- For each domain the user has data in, a sport's share is the Laplace
-- smoothed (alpha = 1) share of that domain's opens, so a page with few or
-- zero samples cannot dominate. The score is the average share across the
-- domains that have events. Users with no events get the deterministic
-- Thai-name order. Usage data itself is never exposed — only ordering.
DROP FUNCTION IF EXISTS public.list_sport_ranking(UUID);
CREATE OR REPLACE FUNCTION public.list_sport_ranking(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  name_th TEXT,
  name_en TEXT,
  icon TEXT,
  score NUMERIC,
  last_opened_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH counts AS (
    SELECT e.source_domain, e.sport_id,
           SUM(e.weight) AS cnt, MAX(e.opened_at) AS last_at
    FROM public.sport_detail_open_events e
    WHERE e.user_id = p_user_id
    GROUP BY e.source_domain, e.sport_id
  ),
  totals AS (
    SELECT source_domain, SUM(cnt) AS total
    FROM counts
    GROUP BY source_domain
  ),
  sport_count AS (
    SELECT GREATEST(count(*), 1)::numeric AS k
    FROM public.sports
    WHERE status = 'approved'
  ),
  shares AS (
    SELECT c.sport_id, c.last_at,
           (c.cnt + 1) / (t.total + sc.k) AS share
    FROM counts c
    JOIN totals t ON t.source_domain = c.source_domain
    CROSS JOIN sport_count sc
  ),
  scored AS (
    SELECT sport_id, AVG(share) AS score, MAX(last_at) AS last_at
    FROM shares
    GROUP BY sport_id
  )
  SELECT s.id,
         s.name_th, s.name_en, s.icon,
         COALESCE(sc.score, 0)::numeric AS score,
         sc.last_at AS last_opened_at
  FROM public.sports s
  LEFT JOIN scored sc ON sc.sport_id = s.id
  WHERE s.status = 'approved'
  ORDER BY score DESC, last_opened_at DESC NULLS LAST, s.name_th ASC, s.id;
$$;

GRANT EXECUTE ON FUNCTION public.record_sport_detail_open(UUID, UUID, UUID, TEXT, UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_sport_ranking(UUID)
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
