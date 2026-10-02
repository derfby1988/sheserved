ALTER TABLE public.sports_venue_courts
  ADD COLUMN IF NOT EXISTS price_schedule_version BIGINT NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS public.sports_venue_court_price_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id UUID NOT NULL
    REFERENCES public.sports_venue_courts(id) ON DELETE CASCADE,
  day_of_week SMALLINT CHECK (day_of_week IS NULL OR day_of_week BETWEEN 0 AND 6),
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  price_per_hour NUMERIC(10,2) NOT NULL CHECK (price_per_hour >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_sports_venue_court_price_rules_court_day
  ON public.sports_venue_court_price_rules(court_id, day_of_week, start_time);

ALTER TABLE public.sports_venue_court_price_rules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sports_venue_court_price_rules_public_read
  ON public.sports_venue_court_price_rules;
CREATE POLICY sports_venue_court_price_rules_public_read
  ON public.sports_venue_court_price_rules FOR SELECT
  USING (EXISTS (
    SELECT 1
    FROM public.sports_venue_courts c
    JOIN public.sports_venues v ON v.id = c.venue_id
    WHERE c.id = sports_venue_court_price_rules.court_id
      AND c.is_active
      AND v.status = 'approved'
  ));

CREATE OR REPLACE FUNCTION public.bump_sports_venue_court_price_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.price_amount IS DISTINCT FROM OLD.price_amount
     OR NEW.pricing_unit IS DISTINCT FROM OLD.pricing_unit THEN
    NEW.price_schedule_version := OLD.price_schedule_version + 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sports_venue_courts_price_version
  ON public.sports_venue_courts;
CREATE TRIGGER sports_venue_courts_price_version
BEFORE UPDATE OF price_amount, pricing_unit
ON public.sports_venue_courts
FOR EACH ROW
EXECUTE FUNCTION public.bump_sports_venue_court_price_version();

ALTER TABLE public.sports_venue_bookings
  ADD COLUMN IF NOT EXISTS price_total_snapshot NUMERIC(10,2)
    CHECK (price_total_snapshot IS NULL OR price_total_snapshot >= 0),
  ADD COLUMN IF NOT EXISTS price_breakdown_snapshot JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS price_schedule_version_snapshot BIGINT;

CREATE OR REPLACE VIEW public.sports_venue_court_price_rules_public
WITH (security_invoker = on) AS
SELECT r.id, r.court_id, r.day_of_week, r.start_time, r.end_time,
       r.price_per_hour
FROM public.sports_venue_court_price_rules r
JOIN public.sports_venue_courts c ON c.id = r.court_id
JOIN public.sports_venues v ON v.id = c.venue_id
WHERE c.is_active AND v.status = 'approved';

CREATE OR REPLACE VIEW public.sports_venue_price_summary_public
WITH (security_invoker = on) AS
SELECT rates.venue_id, MIN(rates.price_per_hour) AS starting_price_amount
FROM (
  SELECT c.venue_id, c.price_amount AS price_per_hour
  FROM public.sports_venue_courts c
  JOIN public.sports_venues v ON v.id = c.venue_id
  WHERE c.is_active AND v.status = 'approved'
    AND c.pricing_unit = 'hour' AND c.price_amount IS NOT NULL
  UNION ALL
  SELECT c.venue_id, r.price_per_hour
  FROM public.sports_venue_court_price_rules r
  JOIN public.sports_venue_courts c ON c.id = r.court_id
  JOIN public.sports_venues v ON v.id = c.venue_id
  WHERE c.is_active AND v.status = 'approved'
) rates
GROUP BY rates.venue_id;

CREATE OR REPLACE VIEW public.sports_venue_courts_public
WITH (security_invoker = on) AS
SELECT c.id, c.venue_id, c.sport_id, c.name, c.capacity, c.price_amount,
       c.pricing_unit, c.court_type, c.indoor, c.booking_approval_mode,
       c.unit_label, c.created_at,
       CASE
         WHEN c.pricing_unit = 'hour' AND c.price_amount IS NOT NULL
           THEN LEAST(c.price_amount, COALESCE(rates.min_rule_price, c.price_amount))
         ELSE rates.min_rule_price
       END AS starting_price_amount,
       rates.has_time_pricing
FROM public.sports_venue_courts c
JOIN public.sports_venues v ON v.id = c.venue_id
LEFT JOIN LATERAL (
  SELECT MIN(r.price_per_hour) AS min_rule_price, count(*) > 0 AS has_time_pricing
  FROM public.sports_venue_court_price_rules r
  WHERE r.court_id = c.id
) rates ON true
WHERE c.is_active AND v.status = 'approved';

GRANT SELECT ON public.sports_venue_courts_public TO anon, authenticated;
GRANT SELECT ON public.sports_venue_court_price_rules TO anon, authenticated;
GRANT SELECT ON public.sports_venue_court_price_rules_public TO anon, authenticated;
GRANT SELECT ON public.sports_venue_price_summary_public TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.sports_venue_court_price_quote_internal(
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court RECORD;
  v_duration_minutes INT;
  v_minute_count INT;
  v_has_missing_rate BOOLEAN;
  v_total_unrounded NUMERIC;
  v_total NUMERIC(10,2);
  v_average_rate NUMERIC(10,2);
  v_breakdown JSONB := '[]'::jsonb;
BEGIN
  IF p_court_id IS NULL OR p_starts_at IS NULL OR p_ends_at IS NULL
     OR p_ends_at <= p_starts_at
     OR date_trunc('minute', p_starts_at) <> p_starts_at
     OR date_trunc('minute', p_ends_at) <> p_ends_at
     OR p_ends_at - p_starts_at > INTERVAL '24 hours' THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;

  SELECT c.id, c.price_amount, c.pricing_unit, c.price_schedule_version,
         c.is_active, v.status AS venue_status, v.timezone,
         (SELECT count(*) FROM public.sports_venue_court_price_rules r
          WHERE r.court_id = c.id) AS rule_count
  INTO v_court
  FROM public.sports_venue_courts c
  JOIN public.sports_venues v ON v.id = c.venue_id
  WHERE c.id = p_court_id;

  IF v_court.id IS NULL OR NOT v_court.is_active
     OR v_court.venue_status <> 'approved' THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;

  v_duration_minutes :=
    (EXTRACT(EPOCH FROM (p_ends_at - p_starts_at)) / 60)::INT;

  IF v_court.rule_count = 0 THEN
    IF v_court.price_amount IS NULL THEN
      RETURN jsonb_build_object(
        'total_amount', NULL, 'price_amount', NULL,
        'pricing_unit', v_court.pricing_unit,
        'price_schedule_version', v_court.price_schedule_version,
        'has_time_pricing', false, 'price_error', NULL,
        'breakdown', '[]'::jsonb
      );
    END IF;

    IF v_court.pricing_unit <> 'hour' THEN
      RETURN jsonb_build_object(
        'total_amount', NULL, 'price_amount', v_court.price_amount,
        'pricing_unit', v_court.pricing_unit,
        'price_schedule_version', v_court.price_schedule_version,
        'has_time_pricing', false, 'price_error', NULL,
        'breakdown', '[]'::jsonb
      );
    END IF;

    v_total_unrounded := v_court.price_amount * v_duration_minutes / 60;
    v_total := round(v_total_unrounded, 2);
    v_breakdown := jsonb_build_array(jsonb_build_object(
      'starts_at', p_starts_at,
      'ends_at', p_ends_at,
      'rate_per_hour', v_court.price_amount,
      'minutes', v_duration_minutes,
      'price_rule_id', NULL
    ));
    RETURN jsonb_build_object(
      'total_amount', v_total, 'price_amount', v_court.price_amount,
      'pricing_unit', 'hour',
      'price_schedule_version', v_court.price_schedule_version,
      'has_time_pricing', false, 'price_error', NULL,
      'breakdown', v_breakdown
    );
  END IF;

  IF v_court.pricing_unit <> 'hour' THEN
    RETURN jsonb_build_object(
      'total_amount', NULL, 'price_amount', NULL,
      'pricing_unit', v_court.pricing_unit,
      'price_schedule_version', v_court.price_schedule_version,
      'has_time_pricing', true, 'price_error', 'PRICE_RULES_REQUIRE_HOURLY',
      'breakdown', '[]'::jsonb
    );
  END IF;

  WITH minute_rates AS (
    SELECT gs.segment_start,
           COALESCE(matched.price_per_hour, v_court.price_amount)
             AS rate_per_hour,
           matched.id AS price_rule_id
    FROM generate_series(
      p_starts_at,
      p_ends_at - INTERVAL '1 minute',
      INTERVAL '1 minute'
    ) AS gs(segment_start)
    LEFT JOIN LATERAL (
      SELECT r.id, r.price_per_hour
      FROM public.sports_venue_court_price_rules r
      WHERE r.court_id = p_court_id
        AND (r.day_of_week IS NULL OR r.day_of_week =
             EXTRACT(DOW FROM (gs.segment_start AT TIME ZONE v_court.timezone))::SMALLINT)
        AND r.start_time <= (gs.segment_start AT TIME ZONE v_court.timezone)::TIME
        AND r.end_time > (gs.segment_start AT TIME ZONE v_court.timezone)::TIME
      ORDER BY (r.day_of_week IS NOT NULL) DESC, r.id
      LIMIT 1
    ) matched ON true
  )
  SELECT count(*)::INT,
         COALESCE(bool_or(rate_per_hour IS NULL), false),
         COALESCE(sum(rate_per_hour / 60), 0)
  INTO v_minute_count, v_has_missing_rate, v_total_unrounded
  FROM minute_rates;

  IF v_minute_count <> v_duration_minutes OR v_has_missing_rate THEN
    RETURN jsonb_build_object(
      'total_amount', NULL, 'price_amount', NULL,
      'pricing_unit', 'hour',
      'price_schedule_version', v_court.price_schedule_version,
      'has_time_pricing', true, 'price_error', 'PRICE_NOT_CONFIGURED',
      'breakdown', '[]'::jsonb
    );
  END IF;

  v_total := round(v_total_unrounded, 2);
  v_average_rate := round(v_total_unrounded * 60 / v_duration_minutes, 2);

  WITH minute_rates AS (
    SELECT gs.segment_start,
           COALESCE(matched.price_per_hour, v_court.price_amount)
             AS rate_per_hour,
           matched.id AS price_rule_id
    FROM generate_series(
      p_starts_at,
      p_ends_at - INTERVAL '1 minute',
      INTERVAL '1 minute'
    ) AS gs(segment_start)
    LEFT JOIN LATERAL (
      SELECT r.id, r.price_per_hour
      FROM public.sports_venue_court_price_rules r
      WHERE r.court_id = p_court_id
        AND (r.day_of_week IS NULL OR r.day_of_week =
             EXTRACT(DOW FROM (gs.segment_start AT TIME ZONE v_court.timezone))::SMALLINT)
        AND r.start_time <= (gs.segment_start AT TIME ZONE v_court.timezone)::TIME
        AND r.end_time > (gs.segment_start AT TIME ZONE v_court.timezone)::TIME
      ORDER BY (r.day_of_week IS NOT NULL) DESC, r.id
      LIMIT 1
    ) matched ON true
  ), ordered_rates AS (
    SELECT *,
      lag(segment_start + INTERVAL '1 minute') OVER (ORDER BY segment_start)
        AS previous_end,
      lag(rate_per_hour) OVER (ORDER BY segment_start) AS previous_rate,
      lag(price_rule_id) OVER (ORDER BY segment_start) AS previous_rule_id
    FROM minute_rates
  ), grouped_rates AS (
    SELECT *, sum(CASE
      WHEN previous_end = segment_start
       AND previous_rate IS NOT DISTINCT FROM rate_per_hour
       AND previous_rule_id IS NOT DISTINCT FROM price_rule_id
      THEN 0 ELSE 1 END) OVER (ORDER BY segment_start) AS segment_group
    FROM ordered_rates
  ), segments AS (
    SELECT min(segment_start) AS starts_at,
           max(segment_start) + INTERVAL '1 minute' AS ends_at,
           rate_per_hour, price_rule_id, count(*)::INT AS minutes
    FROM grouped_rates
    GROUP BY segment_group, rate_per_hour, price_rule_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'starts_at', starts_at,
    'ends_at', ends_at,
    'rate_per_hour', rate_per_hour,
    'minutes', minutes,
    'price_rule_id', price_rule_id
  ) ORDER BY starts_at), '[]'::jsonb)
  INTO v_breakdown
  FROM segments;

  RETURN jsonb_build_object(
    'total_amount', v_total, 'price_amount', v_average_rate,
    'pricing_unit', 'hour',
    'price_schedule_version', v_court.price_schedule_version,
    'has_time_pricing', true, 'price_error', NULL,
    'breakdown', v_breakdown
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sports_venue_court_price_quote_internal(
  UUID, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.quote_sports_venue_court_price(
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.sports_venue_court_price_quote_internal(
    p_court_id, p_starts_at, p_ends_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.quote_sports_venue_prices_for_local_slot(
  p_venue_ids UUID[],
  p_local_date DATE,
  p_start_time TIME,
  p_duration_minutes INT,
  p_sport_id UUID DEFAULT NULL
)
RETURNS TABLE (venue_id UUID, total_amount NUMERIC)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_local_date IS NULL OR p_start_time IS NULL
     OR p_duration_minutes IS NULL OR p_duration_minutes < 1
     OR p_duration_minutes > 1440
     OR EXTRACT(HOUR FROM p_start_time)::INT * 60
        + EXTRACT(MINUTE FROM p_start_time)::INT + p_duration_minutes > 1440 THEN
    RAISE EXCEPTION 'INVALID_PRICE_FILTER_SLOT';
  END IF;

  RETURN QUERY
  SELECT v.id,
         (price_result.price_quote->>'total_amount')::NUMERIC AS total_amount
  FROM public.sports_venues v
  JOIN public.sports_venue_courts c ON c.venue_id = v.id AND c.is_active
  CROSS JOIN LATERAL (
    SELECT public.sports_venue_court_price_quote_internal(
      c.id,
      (p_local_date + p_start_time) AT TIME ZONE v.timezone,
      ((p_local_date + p_start_time) AT TIME ZONE v.timezone)
        + make_interval(mins => p_duration_minutes)
    ) AS price_quote
  ) AS price_result
  WHERE v.id = ANY(p_venue_ids)
    AND v.status = 'approved'
    AND (p_sport_id IS NULL OR c.sport_id = p_sport_id)
    AND price_result.price_quote->>'price_error' IS NULL
    AND price_result.price_quote->>'total_amount' IS NOT NULL;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean)'
     ) IS NOT NULL
     AND to_regprocedure(
       'public.upsert_sports_venue_court_legacy(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean)'
     ) IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean) RENAME TO upsert_sports_venue_court_legacy';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upsert_sports_venue_court_legacy(
  UUID, UUID, UUID, UUID, VARCHAR, INT, NUMERIC, VARCHAR, VARCHAR,
  BOOLEAN, VARCHAR, VARCHAR, BOOLEAN
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.upsert_sports_venue_court(
  p_user_id UUID,
  p_court_id UUID,
  p_venue_id UUID,
  p_sport_id UUID,
  p_name VARCHAR,
  p_capacity INT DEFAULT 1,
  p_price_amount NUMERIC DEFAULT NULL,
  p_pricing_unit VARCHAR DEFAULT 'hour',
  p_court_type VARCHAR DEFAULT NULL,
  p_indoor BOOLEAN DEFAULT NULL,
  p_booking_approval_mode VARCHAR DEFAULT 'instant',
  p_unit_label VARCHAR DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT true,
  p_price_rules JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
  v_pricing_unit VARCHAR;
  v_rule_count INT;
BEGIN
  v_court_id := public.upsert_sports_venue_court_legacy(
    p_user_id, p_court_id, p_venue_id, p_sport_id, p_name, p_capacity,
    p_price_amount, p_pricing_unit, p_court_type, p_indoor,
    p_booking_approval_mode, p_unit_label, p_is_active
  );

  IF p_price_rules IS NULL THEN
    RETURN v_court_id;
  END IF;
  IF jsonb_typeof(p_price_rules) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_PRICE_RULES';
  END IF;
  v_rule_count := jsonb_array_length(p_price_rules);
  IF v_rule_count > 100 THEN
    RAISE EXCEPTION 'TOO_MANY_PRICE_RULES';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_price_rules) AS r(
      day_of_week SMALLINT,
      start_time TIME,
      end_time TIME,
      price_per_hour NUMERIC
    )
    WHERE (day_of_week IS NOT NULL AND day_of_week NOT BETWEEN 0 AND 6)
       OR start_time IS NULL OR end_time IS NULL OR end_time <= start_time
       OR price_per_hour IS NULL OR price_per_hour < 0
       OR price_per_hour > 99999999.99
       OR round(price_per_hour, 2) <> price_per_hour
  ) THEN
    RAISE EXCEPTION 'INVALID_PRICE_RULE';
  END IF;

  IF EXISTS (
    WITH rules AS (
      SELECT ordinality,
             NULLIF(value->>'day_of_week', '')::SMALLINT AS day_of_week,
             (value->>'start_time')::TIME AS start_time,
             (value->>'end_time')::TIME AS end_time
      FROM jsonb_array_elements(p_price_rules) WITH ORDINALITY
    )
    SELECT 1
    FROM rules a
    JOIN rules b ON a.ordinality < b.ordinality
    WHERE a.day_of_week IS NOT DISTINCT FROM b.day_of_week
      AND a.start_time < b.end_time
      AND b.start_time < a.end_time
  ) THEN
    RAISE EXCEPTION 'OVERLAPPING_PRICE_RULES';
  END IF;

  SELECT c.pricing_unit INTO v_pricing_unit
  FROM public.sports_venue_courts c
  WHERE c.id = v_court_id AND c.venue_id = p_venue_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  IF v_rule_count > 0 AND v_pricing_unit <> 'hour' THEN
    RAISE EXCEPTION 'PRICE_RULES_REQUIRE_HOURLY';
  END IF;

  DELETE FROM public.sports_venue_court_price_rules
  WHERE court_id = v_court_id;
  INSERT INTO public.sports_venue_court_price_rules (
    court_id, day_of_week, start_time, end_time, price_per_hour
  )
  SELECT v_court_id, r.day_of_week, r.start_time, r.end_time, r.price_per_hour
  FROM jsonb_to_recordset(p_price_rules) AS r(
    day_of_week SMALLINT,
    start_time TIME,
    end_time TIME,
    price_per_hour NUMERIC
  );

  UPDATE public.sports_venue_courts
  SET price_schedule_version = price_schedule_version + 1,
      updated_at = now()
  WHERE id = v_court_id;
  RETURN v_court_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_sports_venue_court_price_rules(
  p_user_id UUID,
  p_court_id UUID
)
RETURNS TABLE (
  id UUID,
  day_of_week SMALLINT,
  start_time TIME,
  end_time TIME,
  price_per_hour NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venue_id UUID;
BEGIN
  SELECT c.venue_id INTO v_venue_id
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id;
  IF v_venue_id IS NULL THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  IF NOT public.is_sports_venue_manager(v_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  RETURN QUERY
  SELECT r.id, r.day_of_week, r.start_time, r.end_time, r.price_per_hour
  FROM public.sports_venue_court_price_rules r
  WHERE r.court_id = p_court_id
  ORDER BY r.day_of_week NULLS FIRST, r.start_time;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure(
       'public.create_sports_venue_booking(uuid,uuid,timestamptz,timestamptz,integer,character varying)'
     ) IS NOT NULL
     AND to_regprocedure(
       'public.create_sports_venue_booking_legacy(uuid,uuid,timestamptz,timestamptz,integer,character varying)'
     ) IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.create_sports_venue_booking(uuid,uuid,timestamptz,timestamptz,integer,character varying) RENAME TO create_sports_venue_booking_legacy';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_sports_venue_booking_legacy(
  UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ, INT, VARCHAR
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_sports_venue_booking(
  p_user_id UUID,
  p_court_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_terms_version INT,
  p_idempotency_key VARCHAR DEFAULT NULL,
  p_expected_price_schedule_version BIGINT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court RECORD;
  v_price JSONB;
  v_booking_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;
  IF p_ends_at <= now() THEN
    RAISE EXCEPTION 'SLOT_IN_PAST';
  END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT b.id INTO v_booking_id
    FROM public.sports_venue_bookings b
    WHERE b.user_id = p_user_id AND b.idempotency_key = p_idempotency_key;
    IF v_booking_id IS NOT NULL THEN
      RETURN v_booking_id;
    END IF;
  END IF;

  SELECT c.id INTO v_court
  FROM public.sports_venue_courts c
  WHERE c.id = p_court_id
  FOR UPDATE;
  IF v_court.id IS NULL THEN
    RAISE EXCEPTION 'COURT_NOT_FOUND';
  END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT b.id INTO v_booking_id
    FROM public.sports_venue_bookings b
    WHERE b.user_id = p_user_id AND b.idempotency_key = p_idempotency_key;
    IF v_booking_id IS NOT NULL THEN
      RETURN v_booking_id;
    END IF;
  END IF;

  v_price := public.sports_venue_court_price_quote_internal(
    p_court_id, p_starts_at, p_ends_at
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

  v_booking_id := public.create_sports_venue_booking_legacy(
    p_user_id, p_court_id, p_starts_at, p_ends_at,
    p_terms_version, p_idempotency_key
  );
  UPDATE public.sports_venue_bookings
  SET price_amount_snapshot = NULLIF(v_price->>'price_amount', '')::NUMERIC,
      pricing_unit_snapshot = v_price->>'pricing_unit',
      price_total_snapshot = NULLIF(v_price->>'total_amount', '')::NUMERIC,
      price_breakdown_snapshot = COALESCE(v_price->'breakdown', '[]'::jsonb),
      price_schedule_version_snapshot =
        (v_price->>'price_schedule_version')::BIGINT
  WHERE id = v_booking_id AND user_id = p_user_id;
  RETURN v_booking_id;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure(
       'public.change_pending_venue_booking_slot(uuid,uuid,timestamptz,timestamptz,integer)'
     ) IS NOT NULL
     AND to_regprocedure(
       'public.change_pending_venue_booking_slot_legacy(uuid,uuid,timestamptz,timestamptz,integer)'
     ) IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.change_pending_venue_booking_slot(uuid,uuid,timestamptz,timestamptz,integer) RENAME TO change_pending_venue_booking_slot_legacy';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.change_pending_venue_booking_slot_legacy(
  UUID, UUID, TIMESTAMPTZ, TIMESTAMPTZ, INT
) FROM PUBLIC, anon, authenticated;

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
  IF v_booking.status <> 'pending' THEN
    RAISE EXCEPTION 'BOOKING_NOT_PENDING';
  END IF;
  IF p_decision NOT IN ('approve','reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
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
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
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

NOTIFY pgrst, 'reload schema';
