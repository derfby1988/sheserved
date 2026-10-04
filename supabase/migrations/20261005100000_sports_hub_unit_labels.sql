-- Sports Hub venue & resource unit labels (21.7.19)
-- ==================================================
-- Splits the single "unit label" concept into two levels:
--   venueUnitLabel    — what the venue itself is called (สนาม/ยิม/ฟิตเนส/ห้อง)
--   resourceUnitLabel — what is booked inside the venue (คอร์ท/โต๊ะ/เลน)
--
-- - sports_venues: venue_unit_label_override + venue_unit_label_sport_id
--   (reference sport, NOT a composite FK to sports_venue_sports because
--   set_sports_venue_sports uses DELETE+INSERT — membership is validated in
--   the trusted RPCs instead).
-- - sports_venue_unit_defaults(sport_id, locale, singular, plural): a second
--   catalog for venue labels, kept separate from sports_court_unit_defaults
--   (resource labels). Seeded with a curated Thai map joined on the sports
--   rows present at apply time plus a generic 'สนาม' fallback for every row;
--   an AFTER INSERT trigger backfills generic rows for future sports.
-- - sports_venue_courts.unit_label_override: raw per-court override so the
--   effective resource label resolves live (venue+sport default changes now
--   cascade to inheriting courts — the stored unit_label column becomes a
--   compatibility mirror kept in sync by the upsert RPC).
-- - sports_venue_bookings.venue_unit_label_snapshot: nullable; new bookings
--   snapshot both levels, pre-migration rows keep NULL and clients render
--   the neutral term 'สถานที่'.
-- - Resolution helpers are SECURITY DEFINER so security_invoker views can
--   call them without depending on catalog RLS.
-- - New RPC params are declared INT (not SMALLINT) because Postgres cannot
--   resolve integer literals against SMALLINT parameters.

-- ===============
-- Columns
-- ===============
ALTER TABLE public.sports_venues
  ADD COLUMN IF NOT EXISTS venue_unit_label_override VARCHAR(40),
  ADD COLUMN IF NOT EXISTS venue_unit_label_sport_id UUID
    REFERENCES public.sports(id);

ALTER TABLE public.sports_venues
  DROP CONSTRAINT IF EXISTS sports_venues_venue_unit_label_chk;
ALTER TABLE public.sports_venues
  ADD CONSTRAINT sports_venues_venue_unit_label_chk
  CHECK (venue_unit_label_override IS NULL
         OR length(btrim(venue_unit_label_override)) BETWEEN 1 AND 40);

ALTER TABLE public.sports_venue_courts
  ADD COLUMN IF NOT EXISTS unit_label_override VARCHAR(40);
ALTER TABLE public.sports_venue_courts
  DROP CONSTRAINT IF EXISTS sports_venue_courts_unit_label_override_chk;
ALTER TABLE public.sports_venue_courts
  ADD CONSTRAINT sports_venue_courts_unit_label_override_chk
  CHECK (unit_label_override IS NULL
         OR length(btrim(unit_label_override)) BETWEEN 1 AND 40);

ALTER TABLE public.sports_venue_bookings
  ADD COLUMN IF NOT EXISTS venue_unit_label_snapshot VARCHAR(40);

-- ===============
-- Venue-label catalog (separate level from sports_court_unit_defaults)
-- ===============
CREATE TABLE IF NOT EXISTS public.sports_venue_unit_defaults (
  sport_id UUID NOT NULL REFERENCES public.sports(id) ON DELETE CASCADE,
  locale VARCHAR(10) NOT NULL,
  singular VARCHAR(40) NOT NULL,
  plural VARCHAR(40) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (sport_id, locale),
  CHECK (length(btrim(singular)) > 0 AND length(btrim(plural)) > 0)
);

ALTER TABLE public.sports_venue_unit_defaults ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'sports_venue_unit_defaults'
      AND policyname = 'sports_venue_unit_defaults_select_approved'
  ) THEN
    CREATE POLICY sports_venue_unit_defaults_select_approved
      ON public.sports_venue_unit_defaults FOR SELECT
      USING (EXISTS (
        SELECT 1 FROM public.sports s
        WHERE s.id = sport_id AND s.status = 'approved'));
  END IF;
END $$;

-- Curated Thai suggestions keyed by the seed catalog's name_en/name_th.
-- Rows not in this map fall back to 'สนาม'; every sports row gets a default
-- so coverage is total regardless of which statuses/custom rows exist.
INSERT INTO public.sports_venue_unit_defaults (
  sport_id, locale, singular, plural
)
SELECT s.id, 'th', m.singular, m.singular
FROM public.sports s
JOIN (VALUES
  ('Football','ฟุตบอล','สนาม'), ('Futsal','ฟุตซอล','สนาม'),
  ('Rugby','รักบี้','สนาม'), ('American Football','อเมริกันฟุตบอล','สนาม'),
  ('Basketball','บาสเกตบอล','สนาม'), ('Volleyball','วอลเลย์บอล','สนาม'),
  ('Beach Volleyball','วอลเลย์บอลชายหาด','สนาม'),
  ('Sepak Takraw','ตะกร้อ','สนาม'), ('Baseball','เบสบอล','สนาม'),
  ('Softball','ซอฟต์บอล','สนาม'), ('Cricket','คริกเก็ต','สนาม'),
  ('Field Hockey','ฮอกกี้สนาม','สนาม'), ('Handball','แฮนด์บอล','สนาม'),
  ('Badminton','แบดมินตัน','สนาม'), ('Tennis','เทนนิส','สนาม'),
  ('Table Tennis','ปิงปอง','สนาม'), ('Squash','สควอช','สนาม'),
  ('Pickleball','พิคเคิลบอล','สนาม'),
  ('Golf','กอล์ฟ','สนามกอล์ฟ'),
  ('Ice Hockey','ฮอกกี้น้ำแข็ง','ลานน้ำแข็ง'),
  ('Bowling','โบว์ลิ่ง','ลานโบว์ลิ่ง'),
  ('Billiards/Snooker','บิลเลียด/สนุกเกอร์','ห้องบิลเลียด'),
  ('Darts','ดาร์ท','ห้องดาร์ท'),
  ('Swimming','ว่ายน้ำ','สระว่ายน้ำ'),
  ('Water Polo','โปโลน้ำ','สระว่ายน้ำ'),
  ('Triathlon','ไตรกีฬา','ศูนย์กีฬา'),
  ('Surfing','เซิร์ฟ','ศูนย์โต้คลื่น'),
  ('Kayaking','พายเรือคายัค','ศูนย์พายเรือ'),
  ('Sailing','เรือใบ','ท่าเรือ'),
  ('Diving','ดำน้ำ','ศูนย์ดำน้ำ'),
  ('Fishing','ตกปลา','บ่อตกปลา'),
  ('Running','วิ่ง','สนามวิ่ง'), ('Marathon','มาราธอน','สนามวิ่ง'),
  ('Trail Running','วิ่งเทรล','เส้นทางวิ่งเทรล'),
  ('Cycling','ปั่นจักรยาน','เส้นทางจักรยาน'),
  ('Mountain Biking','จักรยานเสือภูเขา','เส้นทางจักรยานเสือภูเขา'),
  ('Rock Climbing','ปีนผา','ยิมปีนผา'),
  ('Hiking','เดินป่า','เส้นทางเดินป่า'),
  ('Trekking','เดินเทรค','เส้นทางเดินเทรค'),
  ('Yoga','โยคะ','สตูดิโอโยคะ'),
  ('Pilates','พิลาทิส','สตูดิโอพิลาทิส'),
  ('Weight Training','เวทเทรนนิ่ง','ฟิตเนส'),
  ('CrossFit','ครอสฟิต','ยิม'), ('Judo','ยูโด','ยิม'),
  ('Taekwondo','เทควันโด','ยิม'), ('Karate','คาราเต้','ยิม'),
  ('BJJ','บราซิลเลียนยิวยิตสู','ยิม'), ('Fencing','ฟันดาบ','ยิม'),
  ('Wrestling','มวยปล้ำ','ยิม'), ('Gymnastics','ยิมนาสติก','ยิม'),
  ('Aerobics','แอโรบิก','สตูดิโอ'),
  ('Muay Thai','มวยไทย','ค่ายมวย'), ('Boxing','มวยสากล','ค่ายมวย'),
  ('Archery','ยิงธนู','สนามยิงธนู'),
  ('Shooting','ยิงปืน','สนามยิงปืน'),
  ('Motorsport','แข่งรถ','สนามแข่งรถ'),
  ('Motocross','มอเตอร์ไซค์วิบาก','สนามมอเตอร์ครอส'),
  ('Horse Riding','แข่งม้า','สนามขี่ม้า'),
  ('Skateboarding','สเก็ตบอร์ด','ลานสเก็ตบอร์ด'),
  ('Roller Skating','โรลเลอร์สเก็ต','ลานโรลเลอร์สเก็ต'),
  ('Skiing','สกี','ลานสกี'), ('Snowboarding','สโนว์บอร์ด','ลานสกี'),
  ('Chess','หมากรุก','ห้องหมากรุก'),
  ('E-Sports','อีสปอร์ต','ห้องอีสปอร์ต')
) AS m(name_en, name_th, singular)
  ON lower(btrim(s.name_en)) = lower(m.name_en)
  OR (s.name_en IS NULL AND lower(btrim(s.name_th)) = lower(m.name_th))
ON CONFLICT (sport_id, locale) DO NOTHING;

-- Generic fallback for every sports row not covered by the curated map,
-- plus a non-Thai locale seed for future locale work.
INSERT INTO public.sports_venue_unit_defaults (
  sport_id, locale, singular, plural
)
SELECT s.id, 'th', 'สนาม', 'สนาม'
FROM public.sports s
ON CONFLICT (sport_id, locale) DO NOTHING;

INSERT INTO public.sports_venue_unit_defaults (
  sport_id, locale, singular, plural
)
SELECT s.id, 'en', 'venue', 'venues'
FROM public.sports s
ON CONFLICT (sport_id, locale) DO NOTHING;

-- Keep coverage total for sports created after this migration.
CREATE OR REPLACE FUNCTION public.sports_venue_unit_defaults_seed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.sports_venue_unit_defaults (
    sport_id, locale, singular, plural
  ) VALUES
    (NEW.id, 'th', 'สนาม', 'สนาม'),
    (NEW.id, 'en', 'venue', 'venues')
  ON CONFLICT (sport_id, locale) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sports_venue_unit_defaults_seed_trg
  ON public.sports;
CREATE TRIGGER sports_venue_unit_defaults_seed_trg
  AFTER INSERT ON public.sports
  FOR EACH ROW
  EXECUTE FUNCTION public.sports_venue_unit_defaults_seed();

-- ===============
-- Resolution helpers — the single source of truth for both levels.
-- SECURITY DEFINER so security_invoker views and RPCs share identical
-- output without relying on catalog RLS (which intentionally exposes only
-- approved-sport rows to direct selects).
-- ===============
CREATE OR REPLACE FUNCTION public.sports_venue_unit_label(p_venue_id UUID)
RETURNS VARCHAR(40)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_label VARCHAR(40);
BEGIN
  SELECT COALESCE(
           NULLIF(btrim(v.venue_unit_label_override), ''),
           (SELECT NULLIF(btrim(d.singular), '')
            FROM public.sports_venue_unit_defaults d
            WHERE d.sport_id = v.venue_unit_label_sport_id
              AND d.locale = 'th'),
           'สนาม')
    INTO v_label
  FROM public.sports_venues v
  WHERE v.id = p_venue_id;
  RETURN v_label;
END;
$$;

CREATE OR REPLACE FUNCTION public.sports_venue_court_unit_label(p_court_id UUID)
RETURNS VARCHAR(40)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_label VARCHAR(40);
BEGIN
  SELECT COALESCE(
           NULLIF(btrim(c.unit_label_override), ''),
           NULLIF(btrim(vs.unit_label_override), ''),
           (SELECT NULLIF(btrim(d.singular), '')
            FROM public.sports_court_unit_defaults d
            WHERE d.sport_id = c.sport_id AND d.locale = 'th'),
           'สนาม')
    INTO v_label
  FROM public.sports_venue_courts c
  LEFT JOIN public.sports_venue_sports vs
    ON vs.venue_id = c.venue_id AND vs.sport_id = c.sport_id
  WHERE c.id = p_court_id;
  RETURN v_label;
END;
$$;

-- ===============
-- Backfill: preserve the currently displayed resource label.
-- Courts whose stored unit_label equals what inheritance would resolve to
-- become inheriting (NULL override); divergent stored values are kept as
-- explicit per-court overrides so nothing the user sees changes.
-- Single-sport venues get that sport as the venue-label reference.
-- ===============
DO $$
DECLARE
  v_inherit INT;
  v_override INT;
BEGIN
  WITH resolved AS (
    SELECT c.id,
           COALESCE(
             NULLIF(btrim(vs.unit_label_override), ''),
             (SELECT NULLIF(btrim(d.singular), '')
              FROM public.sports_court_unit_defaults d
              WHERE d.sport_id = c.sport_id AND d.locale = 'th'),
             'สนาม') AS inherited
    FROM public.sports_venue_courts c
    LEFT JOIN public.sports_venue_sports vs
      ON vs.venue_id = c.venue_id AND vs.sport_id = c.sport_id
  )
  UPDATE public.sports_venue_courts c
  SET unit_label_override = CASE
    WHEN COALESCE(NULLIF(btrim(c.unit_label), ''), 'สนาม')
         = r.inherited THEN NULL
    ELSE NULLIF(btrim(c.unit_label), '')
  END
  FROM resolved r
  WHERE c.id = r.id;
  GET DIAGNOSTICS v_override = ROW_COUNT;

  SELECT count(*) INTO v_inherit
  FROM public.sports_venue_courts
  WHERE unit_label_override IS NULL;

  -- uuid has no ordering; select the sole member by count instead of min().
  UPDATE public.sports_venues v
  SET venue_unit_label_sport_id = (
    SELECT vs.sport_id FROM public.sports_venue_sports vs
    WHERE vs.venue_id = v.id LIMIT 1)
  WHERE v.venue_unit_label_sport_id IS NULL
    AND (SELECT count(*) FROM public.sports_venue_sports x
         WHERE x.venue_id = v.id) = 1;

  -- Keep the compatibility column in sync for any remaining direct readers.
  UPDATE public.sports_venue_courts c
  SET unit_label = public.sports_venue_court_unit_label(c.id);

  RAISE NOTICE '21.7.19 backfill: % courts inheriting, % with explicit override',
    v_inherit, v_override - v_inherit;
END $$;

-- ===============
-- Public views: resolved labels through the helpers.
-- ===============
CREATE OR REPLACE VIEW public.sports_venues_public
WITH (security_invoker = on) AS
SELECT v.id, v.name, v.description, v.province, v.district, v.address,
       v.lat, v.lng, v.timezone, v.created_at,
       public.sports_venue_unit_label(v.id) AS venue_unit_label
FROM public.sports_venues v
WHERE v.status = 'approved';

CREATE OR REPLACE VIEW public.sports_venue_courts_public
WITH (security_invoker = on) AS
SELECT c.id, c.venue_id, c.sport_id, c.name, c.capacity, c.price_amount,
       c.pricing_unit, c.court_type, c.indoor, c.booking_approval_mode,
       -- Cast keeps the pre-existing varchar(40) column type so CREATE OR
       -- REPLACE VIEW can change the expression (function return typmods
       -- are not stored in pg_proc).
       public.sports_venue_court_unit_label(c.id)::varchar(40) AS unit_label,
       c.created_at,
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

-- ===============
-- upsert_sports_venue: label params are NULL-means-keep on update (clearing
-- goes through set_sports_venue_unit_label). A reference sport can never be
-- set on create because the venue has no sports yet.
-- ===============
DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue(uuid,uuid,character varying,character varying,text,text,character varying,double precision,double precision,character varying)'
     ) IS NOT NULL
     AND to_regprocedure(
       'public.upsert_sports_venue_profile(uuid,uuid,character varying,character varying,text,text,character varying,double precision,double precision,character varying)'
     ) IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.upsert_sports_venue(uuid,uuid,character varying,character varying,text,text,character varying,double precision,double precision,character varying) RENAME TO upsert_sports_venue_profile';
  END IF;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue_profile(uuid,uuid,character varying,character varying,text,text,character varying,double precision,double precision,character varying)'
     ) IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.upsert_sports_venue_profile(uuid,uuid,character varying,character varying,text,text,character varying,double precision,double precision,character varying) FROM PUBLIC, anon, authenticated';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_sports_venue(
  p_user_id UUID,
  p_venue_id UUID,
  p_name VARCHAR,
  p_description VARCHAR DEFAULT NULL,
  p_province TEXT DEFAULT NULL,
  p_district TEXT DEFAULT NULL,
  p_address VARCHAR DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lng DOUBLE PRECISION DEFAULT NULL,
  p_timezone VARCHAR DEFAULT 'Asia/Bangkok',
  p_venue_unit_label_override VARCHAR DEFAULT NULL,
  p_venue_unit_label_sport_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id UUID;
  v_id UUID;
BEGIN
  SELECT id INTO v_profile_id
  FROM public.sports_venue_owner_profiles
  WHERE user_id = p_user_id AND status = 'approved';
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'OWNER_NOT_APPROVED';
  END IF;
  IF length(btrim(COALESCE(p_name, ''))) = 0 THEN
    RAISE EXCEPTION 'INVALID_VENUE';
  END IF;
  IF NULLIF(btrim(p_venue_unit_label_override), '') IS NOT NULL
     AND length(btrim(p_venue_unit_label_override)) > 40 THEN
    RAISE EXCEPTION 'INVALID_UNIT_LABEL';
  END IF;

  IF p_venue_id IS NULL THEN
    IF p_venue_unit_label_sport_id IS NOT NULL THEN
      RAISE EXCEPTION 'INVALID_UNIT_LABEL_REFERENCE';
    END IF;
    INSERT INTO public.sports_venues (
      owner_profile_id, name, description, province, district, address,
      lat, lng, timezone, status, venue_unit_label_override
    ) VALUES (
      v_profile_id, p_name, p_description, p_province, p_district,
      p_address, p_lat, p_lng,
      COALESCE(NULLIF(p_timezone, ''), 'Asia/Bangkok'), 'draft',
      NULLIF(btrim(p_venue_unit_label_override), '')
    )
    RETURNING id INTO v_id;

    INSERT INTO public.sports_venue_status_events (
      venue_id, actor_id, event_type, new_status
    ) VALUES (v_id, p_user_id, 'created', 'draft');
  ELSE
    IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
      RAISE EXCEPTION 'NOT_VENUE_MANAGER';
    END IF;
    IF p_venue_unit_label_sport_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.sports_venue_sports vs
      WHERE vs.venue_id = p_venue_id
        AND vs.sport_id = p_venue_unit_label_sport_id
    ) THEN
      RAISE EXCEPTION 'INVALID_UNIT_LABEL_REFERENCE';
    END IF;
    UPDATE public.sports_venues
    SET name = p_name,
        description = p_description,
        province = p_province,
        district = p_district,
        address = p_address,
        lat = p_lat,
        lng = p_lng,
        timezone = COALESCE(NULLIF(p_timezone, ''), timezone),
        venue_unit_label_override = COALESCE(
          NULLIF(btrim(p_venue_unit_label_override), ''),
          venue_unit_label_override),
        venue_unit_label_sport_id = COALESCE(
          p_venue_unit_label_sport_id, venue_unit_label_sport_id),
        updated_at = now()
    WHERE id = p_venue_id;
    v_id := p_venue_id;
  END IF;
  RETURN v_id;
END;
$$;

-- Explicit label setter for the owner manage card: writes both columns
-- exactly as sent (override NULL = sport-derived mode; reference NULL =
-- generic fallback), mirroring set_sports_venue_booking_release.
CREATE OR REPLACE FUNCTION public.set_sports_venue_unit_label(
  p_user_id UUID,
  p_venue_id UUID,
  p_venue_unit_label_override VARCHAR DEFAULT NULL,
  p_reference_sport_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  IF NULLIF(btrim(p_venue_unit_label_override), '') IS NOT NULL
     AND length(btrim(p_venue_unit_label_override)) > 40 THEN
    RAISE EXCEPTION 'INVALID_UNIT_LABEL';
  END IF;
  IF p_reference_sport_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.sports_venue_sports vs
    WHERE vs.venue_id = p_venue_id AND vs.sport_id = p_reference_sport_id
  ) THEN
    RAISE EXCEPTION 'INVALID_UNIT_LABEL_REFERENCE';
  END IF;
  UPDATE public.sports_venues
  SET venue_unit_label_override =
        NULLIF(btrim(p_venue_unit_label_override), ''),
      venue_unit_label_sport_id = p_reference_sport_id,
      updated_at = now()
  WHERE id = p_venue_id;
END;
$$;

-- ===============
-- set_sports_venue_sports: reference evaluated after the DELETE+INSERT swap.
-- Omitted/NULL reference = keep the previous one if it is still a member,
-- otherwise heal to the single member or NULL — old clients that send only
-- p_sports never silently lose their reference, and a reference can never
-- point outside the member set.
-- ===============
DO $$
BEGIN
  IF to_regprocedure('public.set_sports_venue_sports(uuid,uuid,jsonb)') IS NOT NULL
     AND to_regprocedure('public.set_sports_venue_sports_legacy(uuid,uuid,jsonb)') IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.set_sports_venue_sports(uuid,uuid,jsonb) RENAME TO set_sports_venue_sports_legacy';
  END IF;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure('public.set_sports_venue_sports_legacy(uuid,uuid,jsonb)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.set_sports_venue_sports_legacy(uuid,uuid,jsonb) FROM PUBLIC, anon, authenticated';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_sports_venue_sports(
  p_user_id UUID,
  p_venue_id UUID,
  p_sports JSONB,  -- [{"sport_id": uuid, "unit_label_override": text?}]
  p_reference_sport_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_blocked UUID;
  v_count INT;
  v_single UUID;
BEGIN
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;

  SELECT vs.sport_id INTO v_blocked
  FROM public.sports_venue_sports vs
  WHERE vs.venue_id = p_venue_id
    AND EXISTS (
      SELECT 1 FROM public.sports_venue_courts c
      WHERE c.venue_id = p_venue_id
        AND c.sport_id = vs.sport_id
        AND c.is_active
    )
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(p_sports, '[]'::jsonb)) item
      WHERE (item->>'sport_id')::uuid = vs.sport_id
    )
  LIMIT 1;
  IF v_blocked IS NOT NULL THEN
    RAISE EXCEPTION 'SPORT_IN_USE';
  END IF;

  DELETE FROM public.sports_venue_sports WHERE venue_id = p_venue_id;

  INSERT INTO public.sports_venue_sports (
    venue_id, sport_id, unit_label_override
  )
  SELECT p_venue_id,
         (item->>'sport_id')::uuid,
         NULLIF(btrim(item->>'unit_label_override'), '')
  FROM jsonb_array_elements(COALESCE(p_sports, '[]'::jsonb)) AS item
  WHERE (item->>'sport_id') IS NOT NULL
  ON CONFLICT (venue_id, sport_id) DO UPDATE
    SET unit_label_override = EXCLUDED.unit_label_override;

  -- 21.7.19: evaluate the venue-label reference against the NEW member set.
  IF p_reference_sport_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.sports_venue_sports vs
    WHERE vs.venue_id = p_venue_id AND vs.sport_id = p_reference_sport_id
  ) THEN
    RAISE EXCEPTION 'INVALID_UNIT_LABEL_REFERENCE';
  END IF;

  -- uuid has no ordering, so min() cannot pick the single member.
  SELECT count(*) INTO v_count
  FROM public.sports_venue_sports vs
  WHERE vs.venue_id = p_venue_id;
  IF v_count = 1 THEN
    SELECT vs.sport_id INTO v_single
    FROM public.sports_venue_sports vs
    WHERE vs.venue_id = p_venue_id;
  END IF;

  UPDATE public.sports_venues v
  SET venue_unit_label_sport_id = CASE
        WHEN p_reference_sport_id IS NOT NULL THEN p_reference_sport_id
        WHEN v.venue_unit_label_sport_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.sports_venue_sports vs
          WHERE vs.venue_id = v.id
            AND vs.sport_id = v.venue_unit_label_sport_id
        ) THEN v.venue_unit_label_sport_id
        WHEN v_count = 1 THEN v_single
        ELSE NULL
      END,
      updated_at = now()
  WHERE v.id = p_venue_id;
END;
$$;

-- ===============
-- upsert_sports_venue_court: adds p_unit_label_mode/p_unit_label_override.
-- The previous signature is renamed to *_release (legacy wrapper pattern);
-- calls without the new params keep the pre-21.7.19 semantics where
-- p_unit_label text is the stored label (text = override, empty = inherit).
-- ===============
DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer)'
     ) IS NOT NULL
     AND to_regprocedure(
       'public.upsert_sports_venue_court_release(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer)'
     ) IS NULL THEN
    EXECUTE 'ALTER FUNCTION public.upsert_sports_venue_court(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer) RENAME TO upsert_sports_venue_court_release';
  END IF;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure(
       'public.upsert_sports_venue_court_release(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer)'
     ) IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.upsert_sports_venue_court_release(uuid,uuid,uuid,uuid,character varying,integer,numeric,character varying,character varying,boolean,character varying,character varying,boolean,jsonb,character varying,integer,time without time zone,integer) FROM PUBLIC, anon, authenticated';
  END IF;
END;
$$;

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
  p_price_rules JSONB DEFAULT NULL,
  p_booking_release_mode VARCHAR DEFAULT NULL,
  p_booking_release_day_of_week INT DEFAULT NULL,
  p_booking_release_time TIME DEFAULT NULL,
  p_booking_release_window_days INT DEFAULT NULL,
  p_unit_label_mode VARCHAR DEFAULT NULL,
  p_unit_label_override VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_court_id UUID;
  v_label VARCHAR;
BEGIN
  v_court_id := public.upsert_sports_venue_court_pricing(
    p_user_id, p_court_id, p_venue_id, p_sport_id, p_name, p_capacity,
    p_price_amount, p_pricing_unit, p_court_type, p_indoor,
    p_booking_approval_mode, p_unit_label, p_is_active, p_price_rules);

  IF p_booking_release_mode IS NOT NULL THEN
    IF p_booking_release_mode NOT IN ('inherit', 'always_open', 'custom') THEN
      RAISE EXCEPTION 'INVALID_RELEASE_RULE';
    END IF;
    IF p_booking_release_mode = 'custom' THEN
      IF p_booking_release_day_of_week IS NULL
         OR p_booking_release_day_of_week NOT BETWEEN 0 AND 6
         OR p_booking_release_time IS NULL
         OR p_booking_release_window_days IS NULL
         OR p_booking_release_window_days < 7 THEN
        RAISE EXCEPTION 'INVALID_RELEASE_RULE';
      END IF;
      UPDATE public.sports_venue_courts
      SET booking_release_mode = 'custom',
          booking_release_day_of_week = p_booking_release_day_of_week,
          booking_release_time = p_booking_release_time,
          booking_release_window_days = p_booking_release_window_days
      WHERE id = v_court_id;
    ELSE
      UPDATE public.sports_venue_courts
      SET booking_release_mode = p_booking_release_mode,
          booking_release_day_of_week = NULL,
          booking_release_time = NULL,
          booking_release_window_days = NULL
      WHERE id = v_court_id;
    END IF;
  END IF;

  -- 21.7.19: raw per-court resource override. NULL mode keeps the legacy
  -- p_unit_label semantics (non-empty text = override, empty = inherit);
  -- 'inherit'/'custom' are the explicit new-client modes.
  IF p_unit_label_mode IS NOT NULL THEN
    IF p_unit_label_mode = 'inherit' THEN
      UPDATE public.sports_venue_courts
      SET unit_label_override = NULL
      WHERE id = v_court_id;
    ELSIF p_unit_label_mode = 'custom' THEN
      v_label := COALESCE(NULLIF(btrim(p_unit_label_override), ''),
                          NULLIF(btrim(p_unit_label), ''));
      IF v_label IS NULL OR length(v_label) > 40 THEN
        RAISE EXCEPTION 'INVALID_UNIT_LABEL';
      END IF;
      UPDATE public.sports_venue_courts
      SET unit_label_override = v_label
      WHERE id = v_court_id;
    ELSE
      RAISE EXCEPTION 'INVALID_UNIT_LABEL_MODE';
    END IF;
  ELSE
    UPDATE public.sports_venue_courts
    SET unit_label_override = NULLIF(btrim(p_unit_label), '')
    WHERE id = v_court_id;
  END IF;

  -- Keep the compatibility column in sync with live resolution.
  UPDATE public.sports_venue_courts
  SET unit_label = public.sports_venue_court_unit_label(v_court_id),
      updated_at = now()
  WHERE id = v_court_id;
  RETURN v_court_id;
END;
$$;

-- ===============
-- Owner/admin detail: merge resolved labels into the row payloads.
-- ===============
CREATE OR REPLACE FUNCTION public.get_my_sports_venue_detail(
  p_user_id UUID,
  p_venue_id UUID
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
  IF NOT public.is_sports_venue_manager(p_venue_id, p_user_id) THEN
    RAISE EXCEPTION 'NOT_VENUE_MANAGER';
  END IF;
  SELECT JSONB_BUILD_OBJECT(
    'venue', to_jsonb(v) || JSONB_BUILD_OBJECT(
      'venueUnitLabel', public.sports_venue_unit_label(v.id)),
    'owner_status', op.status,
    'member_role', CASE
      WHEN op.user_id = p_user_id THEN 'owner'
      ELSE COALESCE(m.role, 'manager') END,
    'setup_missing', public.sports_venue_setup_missing(v.id),
    'sports', COALESCE((
      SELECT jsonb_agg(to_jsonb(vs)) FROM public.sports_venue_sports vs
      WHERE vs.venue_id = v.id), '[]'::jsonb),
    'courts', COALESCE((
      SELECT jsonb_agg(
        to_jsonb(c) || JSONB_BUILD_OBJECT(
          'unit_label', public.sports_venue_court_unit_label(c.id))
        ORDER BY c.name)
      FROM public.sports_venue_courts c WHERE c.venue_id = v.id), '[]'::jsonb),
    'hours', COALESCE((
      SELECT jsonb_agg(to_jsonb(h) ORDER BY h.day_of_week)
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v.id), '[]'::jsonb),
    'amenities', COALESCE((
      SELECT jsonb_agg(a.amenity_key)
      FROM public.sports_venue_amenities a WHERE a.venue_id = v.id),
      '[]'::jsonb),
    'photos', COALESCE((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.sort_order)
      FROM public.sports_venue_photos p WHERE p.venue_id = v.id), '[]'::jsonb),
    'terms', (
      SELECT to_jsonb(t) FROM public.sports_venue_terms t
      WHERE t.venue_id = v.id AND t.status = 'active')
  ) INTO v_result
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  LEFT JOIN public.sports_venue_owner_members m
    ON m.venue_id = v.id AND m.user_id = p_user_id AND m.is_active
  WHERE v.id = p_venue_id;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_sports_venue_admin_review_detail(
  p_admin_id UUID,
  p_venue_id UUID
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
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  SELECT JSONB_BUILD_OBJECT(
    'venue', to_jsonb(v) || JSONB_BUILD_OBJECT(
      'venueUnitLabel', public.sports_venue_unit_label(v.id)),
    'owner_business_name', op.business_name,
    'setup_missing', public.sports_venue_setup_missing(v.id),
    'sports', COALESCE((
      SELECT jsonb_agg(JSONB_BUILD_OBJECT(
        'sport_id', vs.sport_id,
        'unit_label_override', vs.unit_label_override))
      FROM public.sports_venue_sports vs
      WHERE vs.venue_id = v.id), '[]'::jsonb),
    'court_count', (
      SELECT count(*) FROM public.sports_venue_courts c
      WHERE c.venue_id = v.id),
    'active_court_count', (
      SELECT count(*) FROM public.sports_venue_courts c
      WHERE c.venue_id = v.id AND c.is_active),
    'hours_count', (
      SELECT count(DISTINCT h.day_of_week)
      FROM public.sports_venue_operating_hours h
      WHERE h.venue_id = v.id AND h.day_of_week BETWEEN 0 AND 6),
    'amenities_confirmed', v.amenities_confirmed,
    'uses_platform_terms', v.uses_platform_terms,
    'terms_version', (
      SELECT t.version FROM public.sports_venue_terms t
      WHERE t.venue_id = v.id AND t.status = 'active'),
    'status_history', COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC)
      FROM public.sports_venue_status_events e
      WHERE e.venue_id = v.id), '[]'::jsonb)
  ) INTO v_result
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  WHERE v.id = p_venue_id;
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'VENUE_NOT_FOUND';
  END IF;
  RETURN v_result;
END;
$$;

-- list_my_sports_venues gains a resolved venue_unit_label column; the return
-- type change requires a drop (same pattern as the 21.7.13 rewrite).
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
  created_at TIMESTAMPTZ,
  venue_unit_label VARCHAR
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
           ELSE COALESCE(m.role, 'manager')::varchar
         END AS member_role,
         v.created_at,
         public.sports_venue_unit_label(v.id)
  FROM public.sports_venues v
  JOIN public.sports_venue_owner_profiles op
    ON op.id = v.owner_profile_id
  LEFT JOIN public.sports_venue_owner_members m
    ON m.venue_id = v.id AND m.user_id = p_user_id AND m.is_active
  WHERE public.is_sports_venue_manager(v.id, p_user_id)
  ORDER BY v.created_at DESC;
END;
$$;

-- ===============
-- create_sports_venue_booking: same signature — post-insert UPDATE now also
-- writes both label snapshots, and new notification rows get the venue label
-- substituted for the generic สนาม wording (historical rows untouched).
-- ===============
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
  v_venue_label VARCHAR;
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

  SELECT c.id, c.venue_id INTO v_court
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

  PERFORM public.assert_sports_venue_booking_release(
    p_court_id, p_starts_at, p_ends_at);

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
  v_venue_label := public.sports_venue_unit_label(v_court.venue_id);
  UPDATE public.sports_venue_bookings
  SET price_amount_snapshot = NULLIF(v_price->>'price_amount', '')::NUMERIC,
      pricing_unit_snapshot = v_price->>'pricing_unit',
      price_total_snapshot = NULLIF(v_price->>'total_amount', '')::NUMERIC,
      price_breakdown_snapshot = COALESCE(v_price->'breakdown', '[]'::jsonb),
      price_schedule_version_snapshot =
        (v_price->>'price_schedule_version')::BIGINT,
      unit_label_snapshot = public.sports_venue_court_unit_label(p_court_id),
      venue_unit_label_snapshot = v_venue_label
  WHERE id = v_booking_id AND user_id = p_user_id;

  -- New notification rows refer to the venue by its own label; rows for
  -- earlier bookings keep their persisted wording.
  UPDATE public.app_notifications n
  SET title = replace(n.title, 'สนาม', v_venue_label)
  WHERE n.category = 'venue_booking'
    AND n.payload->>'bookingId' = v_booking_id::text
    AND n.title LIKE '%สนาม%';
  RETURN v_booking_id;
END;
$$;

-- ===============
-- Booking lists: expose the venue-level snapshot alongside the resource one.
-- ===============
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
        'venueUnitLabel', b.venue_unit_label_snapshot,
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
        'venueUnitLabel', b.venue_unit_label_snapshot,
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

-- ===============
-- Admin-only catalog maintenance.
-- ===============
CREATE OR REPLACE FUNCTION public.upsert_sports_venue_unit_default(
  p_admin_id UUID,
  p_sport_id UUID,
  p_locale VARCHAR,
  p_singular VARCHAR,
  p_plural VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_sport_id IS NULL
     OR NULLIF(btrim(COALESCE(p_locale, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_singular, '')), '') IS NULL
     OR length(btrim(p_singular)) > 40
     OR length(btrim(COALESCE(p_plural, p_singular))) > 40 THEN
    RAISE EXCEPTION 'INVALID_UNIT_LABEL';
  END IF;
  INSERT INTO public.sports_venue_unit_defaults (
    sport_id, locale, singular, plural
  ) VALUES (
    p_sport_id, btrim(p_locale), btrim(p_singular),
    btrim(COALESCE(NULLIF(p_plural, ''), p_singular))
  )
  ON CONFLICT (sport_id, locale) DO UPDATE
    SET singular = EXCLUDED.singular,
        plural = EXCLUDED.plural,
        updated_at = now();
END;
$$;

NOTIFY pgrst, 'reload schema';
