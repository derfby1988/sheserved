-- Sports Hub RPC smoke test (Phase 21.7.10 release hardening).
--
-- Verifies the venue/coach booking contracts end-to-end on Postgres:
-- owner onboarding + admin authorization, approved-only public visibility,
-- atomic overlap rejection, idempotency keys, terms-version snapshotting,
-- booking/request lifecycle (pending -> confirmed -> completed), review
-- gating (completed-only, one review per booking), durable
-- app_notifications rows and the 21.7.11 readiness gate (draft ->
-- submit -> review, resubmission, sport/court consistency, manager scope).
--
-- Run against a SCRATCH database only — the script creates minimal stub
-- tables for `sports`, `users`, `app_notifications` and `is_admin_role`
-- when they are missing, then applies the three Phase-21 migrations and
-- exercises the RPCs. Example:
--
--   createdb sports_hub_check
--   psql -d sports_hub_check -f database/sports_hub_rpc_smoke_test.sql
--
-- Expected output: all "PASS:" notices, no "FAIL:" warnings.

\set ON_ERROR_STOP off

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'CREATE ROLE anon NOLOGIN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'CREATE ROLE authenticated NOLOGIN';
  END IF;
END
$roles$;

-- ---------------------------------------------------------------------
-- Prerequisite stubs (skipped automatically on a real Supabase database)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_en text, name_th text, icon text, status text DEFAULT 'approved'
);
-- Pre-21.7.13 scratch stubs may predate the icon column.
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS icon text;
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name text, last_name text, profile_image_url text, role text,
  is_active boolean DEFAULT true
);
-- Stub mirrors the pre-20260921 production shape: profession_id NOT NULL so
-- the notification-delivery migration's DROP NOT NULL is exercised for real.
CREATE TABLE IF NOT EXISTS public.app_notifications (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  profession_id uuid NOT NULL DEFAULT gen_random_uuid(),
  recipient_id uuid, category text, event_type text,
  title text, body text, payload jsonb, is_read boolean DEFAULT false,
  read_at timestamptz, dismissed_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE OR REPLACE FUNCTION public.is_admin_role(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM public.users
    WHERE id = p_user_id AND role = 'admin' AND is_active = true);
END $$;

-- ---------------------------------------------------------------------
-- Apply the migrations under test (idempotent).
-- `security_invoker` view option needs Postgres 15+ (Supabase production).
-- For a local Postgres <15, strip the option into a scratch copy first:
--   mkdir -p /tmp/migcheck
--   for f in supabase/migrations/2026*sports_hub*.sql; do
--     sed 's/WITH (security_invoker = on)//g' "$f" > "/tmp/migcheck/$(basename "$f")"
--   done
-- then point the \ir paths below at /tmp/migcheck instead of ../supabase.
-- ---------------------------------------------------------------------
\ir ../supabase/migrations/20260924100000_sports_hub_venue_supply.sql
\ir ../supabase/migrations/20260924110000_sports_hub_venue_bookings.sql
\ir ../supabase/migrations/20260924120000_sports_hub_coaches.sql
\ir ../supabase/migrations/20260927100000_sports_hub_coach_courses.sql
\ir ../supabase/migrations/20260925100000_sports_hub_owner_contact_fix.sql
\ir ../supabase/migrations/20260925110000_sports_hub_notification_delivery.sql
\ir ../supabase/migrations/20260925130000_sports_hub_venue_review_readiness.sql
\ir ../supabase/migrations/20260926100000_sports_hub_review_scoring_10pt.sql
\ir ../supabase/migrations/20260928120000_sports_hub_sport_usage.sql
\ir ../supabase/migrations/20261001120000_sports_hub_platform_venue_terms.sql
\ir ../supabase/migrations/20261001130000_sports_hub_fail_closed_missing_hours.sql
\ir ../supabase/migrations/20261001140000_sports_hub_booking_venue_timezone.sql
\ir ../supabase/migrations/20261002100000_sports_hub_public_venue_owner_profile.sql
\ir ../supabase/migrations/20261003100000_sports_hub_court_time_pricing.sql
\ir ../supabase/migrations/20261004100000_sports_hub_booking_release.sql
\ir ../supabase/migrations/20261004110000_sports_hub_booking_housekeeping.sql

-- 21.7.19: sports present at apply time receive curated/generic catalog
-- rows; sports inserted later rely on the AFTER INSERT trigger instead.
INSERT INTO public.sports (id, name_en, status) VALUES
  ('eeeeeeee-0000-0000-0000-0000000000f0','Yoga','approved'),
  ('eeeeeeee-0000-0000-0000-0000000000f1','Underwater Basket Weaving','approved'),
  ('eeeeeeee-0000-0000-0000-0000000000f2','Proposed Sport X','pending');
\ir ../supabase/migrations/20261005100000_sports_hub_unit_labels.sql
\ir ../supabase/migrations/20261006100000_sports_hub_booking_release_days.sql
\ir ../supabase/migrations/20261007100000_sports_hub_booking_release_weekday_overrides.sql
\ir ../supabase/migrations/20261008100000_sports_hub_booking_release_venue_fallback_all_days.sql

CREATE OR REPLACE FUNCTION pg_temp.expect(cond boolean, label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF cond THEN RAISE NOTICE 'PASS: %', label;
  ELSE RAISE WARNING 'FAIL: %', label; END IF;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.expect_raise(label text, sql text,
                                                expected text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE sql;
  RAISE WARNING 'FAIL: % (no error raised)', label;
EXCEPTION WHEN OTHERS THEN
  IF expected IS NULL OR position(expected IN SQLERRM) > 0 THEN
    RAISE NOTICE 'PASS: % (%)', label, SQLERRM;
  ELSE
    RAISE WARNING 'FAIL: % (got %, expected %)', label, SQLERRM, expected;
  END IF;
END $$;

-- Variant that also asserts on the exception DETAIL field — the release
-- gate carries opensAt there (Postgres surfaces it in PG_EXCEPTION_DETAIL).
CREATE OR REPLACE FUNCTION pg_temp.expect_raise_detail(label text, sql text,
                                                expected text,
                                                expected_detail text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_detail text;
BEGIN
  EXECUTE sql;
  RAISE WARNING 'FAIL: % (no error raised)', label;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
  IF position(expected IN SQLERRM) > 0
     AND position(expected_detail IN COALESCE(v_detail, '')) > 0 THEN
    RAISE NOTICE 'PASS: % (% | %)', label, SQLERRM, v_detail;
  ELSE
    RAISE WARNING 'FAIL: % (got % detail %, expected % / %)',
      label, SQLERRM, v_detail, expected, expected_detail;
  END IF;
END $$;

-- Venue bookings must land inside the venue's operating hours (08:00–22:00
-- Asia/Bangkok); using now() + N days makes the smoke depend on the
-- time-of-day it runs. This helper returns a deterministic local time.
CREATE OR REPLACE FUNCTION pg_temp.bkk_ts(p_days int, p_time time)
RETURNS timestamptz LANGUAGE sql AS $$
  SELECT (((now() AT TIME ZONE 'Asia/Bangkok')::date + p_days) + p_time)
         AT TIME ZONE 'Asia/Bangkok';
$$;

DO $smoke$
DECLARE
  v_admin uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_owner uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  v_cust  uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_cust2 uuid := 'dddddddd-0000-0000-0000-000000000004';
  v_sport uuid := 'eeeeeeee-0000-0000-0000-000000000005';
  v_mail  uuid := 'ffffffff-0000-0000-0000-000000000006';
  v_mgr   uuid := '99999999-0000-0000-0000-000000000007';
  v_app uuid; v_venue uuid; v_venue2 uuid; v_court uuid; v_court2 uuid;
  v_court3 uuid; v_terms int; v_platform_version int;
  v_platform_terms jsonb; v_platform_booking uuid;
  v_platform_booking2 uuid; v_b1 uuid; v_b2 uuid; v_b3 uuid;
  v_price_court uuid; v_price_booking uuid; v_price_quote jsonb;
  v_price_version bigint; v_pending_price_booking uuid;
  v_b4 uuid; v_b5 uuid; v_review uuid; v_missing text[];
  v_rel_court uuid; v_rel_booking uuid; v_pending_rel uuid;
  v_expiry_my uuid; v_expiry_manager uuid; v_expiry_approval uuid;
  v_expiry_change uuid; v_completion_lazy uuid;
  v_rel_dow smallint; v_rel_dow2 smallint;
  v_slot timestamptz; v_avail jsonb; v_opens_detail text;
  v_booking_rows jsonb; v_housekeeping jsonb; v_cron_scheduled boolean;
  v_decision text;
BEGIN
  INSERT INTO public.users (id, first_name, last_name, role) VALUES
    (v_admin,'Admin','A','admin'), (v_owner,'Owner','O','user'),
    (v_cust,'Cust','C','user'), (v_cust2,'Cust2','C2','user'),
    (v_mail,'Mail','M','user'), (v_mgr,'Mgr','M','user');
  INSERT INTO public.sports (id, name_en, status)
    VALUES (v_sport,'Badminton','approved');

  -- 21.7.3 owner onboarding
  v_app := public.submit_sports_venue_owner_application(
    v_owner, 'Venue Co', 'Owner O', '0812345678');
  PERFORM pg_temp.expect(v_app IS NOT NULL, 'owner application submitted');

  -- contact hotfix: e-mail-only contact accepted, no contact rejected
  PERFORM pg_temp.expect(
    public.submit_sports_venue_owner_application(
      v_mail, 'Mail Co', 'Mail M', NULL, 'mail@example.com') IS NOT NULL,
    'owner application accepted with e-mail-only contact');
  PERFORM pg_temp.expect_raise('application without any contact rejected',
    format('SELECT public.submit_sports_venue_owner_application(%L, %L, %L, %L)',
           gen_random_uuid()::text, 'X', 'X', ''));

  PERFORM pg_temp.expect_raise('non-admin cannot review owner application',
    format('SELECT public.review_sports_venue_owner_application(%L, %L, %L)',
           v_cust, v_app, 'approved'));

  PERFORM public.review_sports_venue_owner_application(v_admin, v_app, 'approved');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_owner_profiles
    WHERE user_id = v_owner AND status = 'approved'),
    'owner profile approved');

  -- 21.7.11: new venues start as 'draft' and stay out of public surfaces
  v_venue := public.upsert_sports_venue(
    v_owner, NULL, 'Test Arena', NULL, 'Bangkok', 'Chatuchak',
    'addr', 13.8, 100.5, 'Asia/Bangkok');
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venues
    WHERE id = v_venue) = 'draft', 'new venue starts as draft');
  PERFORM pg_temp.expect(NOT EXISTS(
    SELECT 1 FROM public.sports_venues_public WHERE id = v_venue),
    'draft venue hidden from public view');
  PERFORM pg_temp.expect_raise('platform terms cannot be selected before admin setup',
    format('SELECT public.confirm_sports_venue_platform_terms(%L, %L)',
      v_owner, v_venue), 'PLATFORM_TERMS_NOT_CONFIGURED');
  v_platform_terms := public.get_sports_venue_platform_terms(v_admin);
  PERFORM pg_temp.expect(
    (v_platform_terms->>'version')::int = 0
      AND (v_platform_terms->>'is_configured')::boolean = false,
    'platform terms start at unconfigured legacy version 0');
  PERFORM pg_temp.expect_raise('non-admin cannot read platform terms',
    format('SELECT public.get_sports_venue_platform_terms(%L)', v_owner),
    'NOT_ADMIN');
  PERFORM pg_temp.expect_raise('legacy placeholder cannot be published as standard terms',
    format('SELECT public.set_sports_venue_platform_terms(%L, %L, 60)',
      v_admin, 'เงื่อนไขการใช้สนามมาตรฐานของแพลตฟอร์ม'),
    'INVALID_PLATFORM_TERMS');
  v_platform_terms := public.set_sports_venue_platform_terms(
    v_admin, 'Standard venue terms v1', 120);
  v_platform_version := (v_platform_terms->>'version')::int;
  PERFORM pg_temp.expect(v_platform_version = 1
      AND (v_platform_terms->>'is_configured')::boolean,
    'admin configures platform terms version 1');
  v_platform_terms := public.set_sports_venue_platform_terms(
    v_admin, 'Standard venue terms v1', 120);
  PERFORM pg_temp.expect((v_platform_terms->>'version')::int = 1,
    'saving unchanged platform terms does not bump version');
  PERFORM pg_temp.expect_raise('non-admin cannot edit platform terms',
    format('SELECT public.set_sports_venue_platform_terms(%L, %L, 120)',
      v_owner, 'unauthorized edit'), 'NOT_ADMIN');

  -- admin cannot approve a draft or an incomplete venue
  PERFORM pg_temp.expect_raise('admin cannot approve a draft venue',
    format('SELECT public.review_sports_venue(%L, %L, %L)',
           v_admin, v_venue, 'approved'));
  PERFORM pg_temp.expect_raise('submit before setup is rejected',
    format('SELECT public.submit_sports_venue_for_review(%L, %L)',
           v_owner, v_venue), 'VENUE_NOT_READY');
  PERFORM pg_temp.expect_raise('non-manager cannot submit venue',
    format('SELECT public.submit_sports_venue_for_review(%L, %L)',
           v_cust, v_venue));

  -- hours must cover all 7 days explicitly
  PERFORM pg_temp.expect_raise('partial hours rejected',
    format($s$SELECT public.set_sports_venue_operating_hours(%L, %L,
      jsonb_build_array(jsonb_build_object(
        'day', 1, 'open', '09:00', 'close', '18:00', 'closed', false)))$s$,
      v_owner, v_venue));
  PERFORM pg_temp.expect_raise('cross-midnight window rejected',
    format($s$SELECT public.set_sports_venue_operating_hours(%L, %L, (
      SELECT jsonb_agg(jsonb_build_object(
        'day', d, 'open', '20:00', 'close', '02:00', 'closed', false))
      FROM generate_series(0, 6) d))$s$, v_owner, v_venue));

  -- complete setup: sports, full hours, amenities confirmation, terms,
  -- one active court
  PERFORM public.set_sports_venue_sports(v_owner, v_venue,
    jsonb_build_array(jsonb_build_object(
      'sport_id', v_sport, 'unit_label_override', 'คอร์ท')));
  PERFORM public.set_sports_venue_operating_hours(v_owner, v_venue, (
    SELECT jsonb_agg(jsonb_build_object(
      'day', d, 'open', '08:00', 'close', '22:00', 'closed', false))
    FROM generate_series(0, 6) d));
  PERFORM public.set_sports_venue_amenities(v_owner, v_venue, '{}');
  PERFORM pg_temp.expect((SELECT amenities_confirmed
    FROM public.sports_venues WHERE id = v_venue),
    'saving empty amenities persists "confirmed none"');
  v_terms := public.publish_sports_venue_terms(v_owner, v_venue, 'No smoking', 60);
  PERFORM pg_temp.expect(v_terms = 1, 'terms v1 published');
  v_court := public.upsert_sports_venue_court(
    v_owner, NULL, v_venue, v_sport, 'Court 1',
    1, 200, 'hour', 'synthetic', true, 'instant', NULL, true);

  DELETE FROM public.sports_venue_operating_hours
  WHERE venue_id = v_venue;
  PERFORM pg_temp.expect(
    public.sports_venue_slot_blocked(
      v_court,
      now() + interval '7 days',
      now() + interval '7 days 1 hour'),
    'venue without operating hours is closed for booking');
  PERFORM public.set_sports_venue_operating_hours(v_owner, v_venue, (
    SELECT jsonb_agg(jsonb_build_object(
      'day', d, 'open', '08:00', 'close', '22:00', 'closed', false))
    FROM generate_series(0, 6) d));

  v_missing := public.sports_venue_setup_missing(v_venue);
  PERFORM pg_temp.expect(COALESCE(array_length(v_missing, 1), 0) = 0,
    'setup complete after all items persisted');

  -- sport/court consistency: bound sport cannot be removed
  PERFORM pg_temp.expect_raise('sport with active court cannot be removed',
    format($s$SELECT public.set_sports_venue_sports(%L, %L, '[]'::jsonb)$s$,
      v_owner, v_venue));

  -- submit -> pending -> approve
  PERFORM public.submit_sports_venue_for_review(v_owner, v_venue);
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venues
    WHERE id = v_venue) = 'pending', 'submit moves venue to pending');
  PERFORM public.review_sports_venue(v_admin, v_venue, 'approved');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venues_public WHERE id = v_venue),
    'approved venue appears in public view');
  UPDATE public.users SET profile_image_url = 'owner-avatar-test'
  WHERE id = v_owner;
  PERFORM pg_temp.expect(
    public.get_public_sports_venue_owner_profile(v_venue) =
      jsonb_build_object(
        'display_name', 'Owner O.',
        'avatar_url', 'owner-avatar-test'),
    'public owner profile only exposes masked name and avatar');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_status_events
    WHERE venue_id = v_venue AND new_status = 'approved'),
    'review transition audited');

  -- manager scope: member without own owner profile manages the venue
  PERFORM public.set_sports_venue_member(v_owner, v_venue, v_mgr, 'manager');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.list_my_sports_venues(v_mgr)
    WHERE id = v_venue AND member_role = 'manager'),
    'assigned manager sees venue in scope with manager role');
  PERFORM pg_temp.expect(
    (public.get_my_sports_venue_detail(v_mgr, v_venue)
      ->> 'member_role') = 'manager',
    'manager reads venue detail without owner profile');
  PERFORM pg_temp.expect_raise('manager cannot create own venue',
    format($s$SELECT public.upsert_sports_venue(
      %L, NULL, 'Mgr Venue', NULL, NULL, NULL, NULL, NULL, NULL)$s$, v_mgr));

  -- 21.7.5 instant booking + atomicity (fixed 10:00–11:00 local slots)
  v_b1 := public.create_sports_venue_booking(
    v_cust, v_court, pg_temp.bkk_ts(2, '10:00'),
    pg_temp.bkk_ts(2, '11:00'), v_terms, 'idem-1');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1
    FROM jsonb_array_elements(
      public.list_my_sports_venue_bookings(v_cust)
    ) AS bookings(booking)
    WHERE booking->>'id' = v_b1::text
      AND booking->>'timezone' = 'Asia/Bangkok'),
    'booking list includes venue timezone');
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venue_bookings
    WHERE id = v_b1) = 'confirmed', 'instant booking confirmed');
  PERFORM pg_temp.expect((SELECT accepted_terms_version FROM public.sports_venue_bookings
    WHERE id = v_b1) = v_terms, 'terms version snapshotted');

  PERFORM pg_temp.expect_raise('overlapping booking rejected',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(2, '10:30'),
      pg_temp.bkk_ts(2, '11:30'), %s, 'idem-2')$$,
      v_cust2, v_court, v_terms));

  PERFORM pg_temp.expect(public.create_sports_venue_booking(
    v_cust, v_court, pg_temp.bkk_ts(2, '10:00'),
    pg_temp.bkk_ts(2, '11:00'), v_terms, 'idem-1') = v_b1,
    'idempotent retry returns same booking id');

  PERFORM pg_temp.expect_raise('stale terms version rejected',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(4, '10:00'), pg_temp.bkk_ts(4, '11:00'),
      99, 'idem-3')$$, v_cust, v_court));

  v_price_court := public.upsert_sports_venue_court(
    v_owner, NULL, v_venue, v_sport, 'Court Price Schedule',
    1, 100, 'hour', 'synthetic', true, 'instant', NULL, true,
    jsonb_build_array(
      jsonb_build_object(
        'day_of_week', NULL, 'start_time', '08:00', 'end_time', '10:00',
        'price_per_hour', 60),
      jsonb_build_object(
        'day_of_week', NULL, 'start_time', '10:00', 'end_time', '22:00',
        'price_per_hour', 120),
      jsonb_build_object(
        'day_of_week', EXTRACT(DOW FROM
          ((now() AT TIME ZONE 'Asia/Bangkok')::date + 13))::SMALLINT,
        'start_time', '09:00', 'end_time', '10:00',
        'price_per_hour', 180)));
  SELECT price_schedule_version INTO v_price_version
  FROM public.sports_venue_courts WHERE id = v_price_court;
  v_price_quote := public.quote_sports_venue_court_price(
    v_price_court, pg_temp.bkk_ts(12, '09:30'),
    pg_temp.bkk_ts(12, '11:00'));
  PERFORM pg_temp.expect(
    (v_price_quote->>'total_amount')::numeric = 150
      AND jsonb_array_length(v_price_quote->'breakdown') = 2,
    'time prices are prorated across rule boundaries');
  v_price_quote := public.quote_sports_venue_court_price(
    v_price_court, pg_temp.bkk_ts(13, '09:30'),
    pg_temp.bkk_ts(13, '10:30'));
  PERFORM pg_temp.expect((v_price_quote->>'total_amount')::numeric = 150,
    'weekday-specific rate overrides the all-day rate');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.quote_sports_venue_prices_for_local_slot(
      ARRAY[v_venue],
      (now() AT TIME ZONE 'Asia/Bangkok')::date + 12,
      '09:30', 60) q
    WHERE q.venue_id = v_venue AND q.total_amount = 90),
    'price filter quotes the selected local time and duration');
  PERFORM pg_temp.expect((SELECT starting_price_amount = 60
    FROM public.sports_venue_price_summary_public
    WHERE venue_id = v_venue),
    'venue starting price is the lowest hourly rate');

  v_price_booking := public.create_sports_venue_booking(
    v_cust, v_price_court, pg_temp.bkk_ts(12, '09:30'),
    pg_temp.bkk_ts(12, '11:00'), v_terms, 'priced-booking-v1',
    v_price_version);
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_bookings
    WHERE id = v_price_booking
      AND price_total_snapshot = 150
      AND jsonb_array_length(price_breakdown_snapshot) = 2
      AND price_schedule_version_snapshot = v_price_version),
    'booking snapshots the authoritative total and breakdown');
  PERFORM pg_temp.expect_raise('scheduled booking requires current price version',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(13, '10:00'), pg_temp.bkk_ts(13, '11:00'),
      %s, 'priced-booking-old-client')$$,
      v_cust, v_price_court, v_terms), 'PRICE_VERSION_REQUIRED');

  PERFORM public.upsert_sports_venue_court(
    v_owner, v_price_court, v_venue, v_sport, 'Court Price Schedule',
    1, 100, 'hour', 'synthetic', true, 'instant', NULL, true,
    jsonb_build_array(
      jsonb_build_object(
        'day_of_week', NULL, 'start_time', '08:00', 'end_time', '10:00',
        'price_per_hour', 70),
      jsonb_build_object(
        'day_of_week', NULL, 'start_time', '10:00', 'end_time', '22:00',
        'price_per_hour', 120)));
  PERFORM pg_temp.expect((SELECT price_total_snapshot = 150
    FROM public.sports_venue_bookings WHERE id = v_price_booking),
    'price edits do not rewrite existing booking snapshots');
  PERFORM pg_temp.expect_raise('stale price quote cannot create booking',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(14, '10:00'), pg_temp.bkk_ts(14, '11:00'),
      %s, 'priced-booking-stale', %s)$$,
      v_cust, v_price_court, v_terms, v_price_version), 'PRICE_CHANGED');
  PERFORM pg_temp.expect_raise('overlapping price rules are rejected',
    format($s$SELECT public.upsert_sports_venue_court(
      %L, %L, %L, %L, %L, 1, 100, 'hour', 'synthetic', true,
      'instant', NULL, true, %L::jsonb)$s$,
      v_owner, v_price_court, v_venue, v_sport, 'Court Price Schedule',
      jsonb_build_array(
        jsonb_build_object('day_of_week', NULL, 'start_time', '08:00',
          'end_time', '12:00', 'price_per_hour', 100),
        jsonb_build_object('day_of_week', NULL, 'start_time', '11:00',
          'end_time', '13:00', 'price_per_hour', 120))::text),
    'OVERLAPPING_PRICE_RULES');

  PERFORM public.upsert_sports_venue_court(
    v_owner, v_price_court, v_venue, v_sport, 'Court Price Schedule',
    1, 100, 'hour', 'synthetic', true, 'owner_approval', NULL, true,
    jsonb_build_array(
      jsonb_build_object(
        'day_of_week', NULL, 'start_time', '08:00', 'end_time', '10:00',
        'price_per_hour', 70),
      jsonb_build_object(
        'day_of_week', NULL, 'start_time', '10:00', 'end_time', '22:00',
        'price_per_hour', 120)));
  SELECT price_schedule_version INTO v_price_version
  FROM public.sports_venue_courts WHERE id = v_price_court;
  v_pending_price_booking := public.create_sports_venue_booking(
    v_cust2, v_price_court, pg_temp.bkk_ts(15, '09:30'),
    pg_temp.bkk_ts(15, '10:30'), v_terms, 'priced-pending-v1',
    v_price_version);
  PERFORM public.change_pending_venue_booking_slot(
    v_cust2, v_pending_price_booking,
    pg_temp.bkk_ts(16, '10:00'), pg_temp.bkk_ts(16, '11:00'),
    v_terms, v_price_version);
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_bookings
    WHERE id = v_pending_price_booking
      AND status = 'pending'
      AND starts_at = pg_temp.bkk_ts(16, '10:00')
      AND price_total_snapshot = 120
      AND price_schedule_version_snapshot = v_price_version),
    'pending reschedule refreshes its price snapshot for the new slot');

  -- authorization
  PERFORM pg_temp.expect_raise('stranger cannot cancel booking',
    format($$SELECT public.cancel_sports_venue_booking(%L, %L, 'not mine')$$,
      v_cust2, v_b1));

  -- 21.7.7 reviews need completed booking
  PERFORM pg_temp.expect_raise('review before completion rejected',
    format($$SELECT public.submit_sports_venue_review(
      %L, %L, 5, 'early', NULL, NULL)$$, v_cust, v_b1));

  UPDATE public.sports_venue_bookings
    SET starts_at = now() - interval '2 hours',
        ends_at = now() - interval '1 hour'
    WHERE id = v_b1;
  PERFORM public.complete_sports_venue_bookings();
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venue_bookings
    WHERE id = v_b1) = 'completed', 'booking auto-completed after slot');

  v_review := public.submit_sports_venue_review(
    v_cust, v_b1, 5, 'great', NULL, NULL);
  PERFORM pg_temp.expect(v_review IS NOT NULL, 'review accepted post-completion');

  PERFORM pg_temp.expect_raise('duplicate review on same booking rejected',
    format($$SELECT public.submit_sports_venue_review(
      %L, %L, 4, 'again', NULL, NULL)$$, v_cust, v_b1));

  -- =============== 21.7.14: 10-point scoring + category scores ===============
  -- The legacy RPC stays live as a compat adapter: rating 5 -> rating_10 = 10.
  PERFORM pg_temp.expect((SELECT rating_10 FROM public.sports_venue_reviews
    WHERE id = v_review) = 10, 'legacy 1-5 submit writes scaled rating_10');

  -- A second completed booking for a fresh v2 review.
  v_b2 := public.create_sports_venue_booking(
    v_cust2, v_court, pg_temp.bkk_ts(5, '10:00'),
    pg_temp.bkk_ts(5, '11:00'), v_terms, 'idem-5');
  UPDATE public.sports_venue_bookings
    SET starts_at = now() - interval '2 hours',
        ends_at = now() - interval '1 hour'
    WHERE id = v_b2;
  PERFORM public.complete_sports_venue_bookings();

  PERFORM pg_temp.expect(public.submit_sports_venue_review_v2(
    v_cust2, v_b2, 9, (SELECT jsonb_object_agg(id::text, 8)
      FROM public.sports_venue_review_category_catalog),
    'ดีมาก',
    ARRAY[(SELECT id FROM public.sports_venue_review_tag_catalog
      ORDER BY display_order LIMIT 1)]::uuid[],
    ARRAY['จอดรถง่าย']) IS NOT NULL,
    'v2 review accepted with all five categories');

  PERFORM pg_temp.expect((SELECT rating_10 FROM public.sports_venue_reviews
    WHERE booking_id = v_b2) = 9, 'v2 stores rating_10 verbatim');
  PERFORM pg_temp.expect((SELECT rating FROM public.sports_venue_reviews
    WHERE booking_id = v_b2) = 5, 'v2 folds legacy rating 9 -> 5');
  PERFORM pg_temp.expect((SELECT count(*) FROM
    public.sports_venue_review_category_scores sc
    JOIN public.sports_venue_reviews r ON r.id = sc.review_id
    WHERE r.booking_id = v_b2) = 5, 'all five category scores written');

  PERFORM pg_temp.expect_raise('v2 duplicate rejected',
    format($$SELECT public.submit_sports_venue_review_v2(%L, %L, 9,
      (SELECT jsonb_object_agg(id::text, 8)
       FROM public.sports_venue_review_category_catalog), NULL)$$,
      v_cust2, v_b2), 'ALREADY_REVIEWED');
  PERFORM pg_temp.expect_raise('v2 missing category rejected',
    format($$SELECT public.submit_sports_venue_review_v2(%L, %L, 9,
      jsonb_build_object((SELECT id::text
        FROM public.sports_venue_review_category_catalog LIMIT 1), 8),
      NULL)$$, v_cust, v_b2), 'MISSING_CATEGORY_SCORES');
  PERFORM pg_temp.expect_raise('v2 out-of-range score rejected',
    format($$SELECT public.submit_sports_venue_review_v2(%L, %L, 9,
      (SELECT jsonb_object_agg(id::text, 11)
       FROM public.sports_venue_review_category_catalog), NULL)$$,
      v_cust, v_b2), 'INVALID_CATEGORY_SCORES');

  -- Helpful votes: one per user, idempotent, no self-vote.
  PERFORM public.set_sports_venue_review_helpful(v_cust2, v_review, true);
  PERFORM public.set_sports_venue_review_helpful(v_cust2, v_review, true);
  PERFORM pg_temp.expect((SELECT count(*)
    FROM public.sports_venue_review_helpful_votes
    WHERE review_id = v_review) = 1, 'helpful vote is idempotent');
  PERFORM pg_temp.expect_raise('self vote rejected',
    format($$SELECT public.set_sports_venue_review_helpful(%L, %L, true)$$,
      v_cust, v_review), 'SELF_VOTE_NOT_ALLOWED');
  PERFORM public.set_sports_venue_review_helpful(v_cust2, v_review, false);
  PERFORM pg_temp.expect((SELECT count(*)
    FROM public.sports_venue_review_helpful_votes
    WHERE review_id = v_review) = 0, 'helpful vote removal idempotent');

  -- Summary + list RPCs (published only, deterministic bands/topics).
  PERFORM pg_temp.expect(
    (public.get_sports_venue_review_summary_v2(v_venue)
      ->> 'review_count')::int = 2, 'summary counts published reviews');
  PERFORM pg_temp.expect(
    (public.get_sports_venue_review_summary_v2(v_venue)
      -> 'band_counts' ->> 'excellent')::int = 2,
    'rating_10 9 and 10 land in the excellent band');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.list_sports_venue_reviews_v2(
      v_venue, NULL, NULL, NULL, NULL, 'helpful', 20, 0, v_cust2)),
    'v2 list returns rows for the venue');
  PERFORM pg_temp.expect((SELECT count(*) FROM
    public.list_sports_venue_reviews_v2(
      v_venue, NULL, NULL, 9, 10, 'newest', 20, 0, NULL)) = 2,
    'rating band filter narrows server-side');
  PERFORM pg_temp.expect((SELECT count(*) FROM
    public.list_sports_venue_reviews_v2(
      v_venue, NULL, NULL, 1, 2, 'newest', 20, 0, NULL)) = 0,
    'empty band returns no rows');

  -- Tag limit/validation: >5 combined tags and non-catalog tags rejected.
  PERFORM pg_temp.expect_raise('v2 more than 5 tags rejected',
    format($$SELECT public.submit_sports_venue_review_v2(%L, %L, 9,
      (SELECT jsonb_object_agg(id::text, 8)
       FROM public.sports_venue_review_category_catalog), NULL, NULL,
      ARRAY['a','b','c','d','e','f'])$$,
      v_cust, v_b2), 'TOO_MANY_TAGS');

  -- Fresh completed bookings for tag validation and the self-review
  -- guard (the already-reviewed bookings would short-circuit earlier).
  v_b3 := public.create_sports_venue_booking(
    v_cust, v_court, pg_temp.bkk_ts(6, '10:00'),
    pg_temp.bkk_ts(6, '11:00'), v_terms, 'idem-4');
  UPDATE public.sports_venue_bookings
    SET starts_at = now() - interval '2 hours',
        ends_at = now() - interval '1 hour'
    WHERE id = v_b3;
  PERFORM public.complete_sports_venue_bookings();

  PERFORM pg_temp.expect_raise('v2 unknown standard tag rejected',
    format($$SELECT public.submit_sports_venue_review_v2(%L, %L, 8,
      (SELECT jsonb_object_agg(id::text, 8)
       FROM public.sports_venue_review_category_catalog), NULL,
      ARRAY[gen_random_uuid()]::uuid[], NULL)$$,
      v_cust, v_b3), 'INVALID_TAG');

  v_b4 := public.create_sports_venue_booking(
    v_owner, v_court, pg_temp.bkk_ts(7, '10:00'),
    pg_temp.bkk_ts(7, '11:00'), v_terms, 'idem-5');
  UPDATE public.sports_venue_bookings
    SET starts_at = now() - interval '2 hours',
        ends_at = now() - interval '1 hour'
    WHERE id = v_b4;
  PERFORM public.complete_sports_venue_bookings();
  PERFORM pg_temp.expect_raise('venue owner self-review rejected',
    format($$SELECT public.submit_sports_venue_review_v2(%L, %L, 8,
      (SELECT jsonb_object_agg(id::text, 8)
       FROM public.sports_venue_review_category_catalog), NULL)$$,
      v_owner, v_b4), 'SELF_REVIEW_NOT_ALLOWED');

  -- 21.7.6 owner-approval flow
  SELECT public.upsert_sports_venue_court(
    v_owner, NULL, v_venue, v_sport, 'Court 2',
    1, 300, 'hour', 'grass', false, 'owner_approval', NULL, true) INTO v_court;
  v_b2 := public.create_sports_venue_booking(
    v_cust2, v_court, pg_temp.bkk_ts(3, '10:00'),
    pg_temp.bkk_ts(3, '11:00'), v_terms, 'idem-4');
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venue_bookings
    WHERE id = v_b2) = 'pending', 'owner-approval court creates pending');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.app_notifications
    WHERE recipient_id = v_owner
      AND category = 'venue_booking'
      AND event_type = 'venue_booking.requested'
      AND payload->>'bookingId' = v_b2::text),
    'pending approval notification is persisted for the venue owner');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.list_app_notifications(
      v_owner, 'venue_booking', 50, false) n
    WHERE n.event_type = 'venue_booking.requested'
      AND n.payload->>'bookingId' = v_b2::text),
    'owner can load pending approval notification in the panel');

  PERFORM pg_temp.expect_raise('non-manager cannot approve booking',
    format($$SELECT public.decide_sports_venue_booking(%L, %L, 'approve')$$,
      v_cust, v_b2));

  PERFORM pg_temp.expect(public.decide_sports_venue_booking(
    v_owner, v_b2, 'approve') = 'confirmed', 'owner approves pending booking');

  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.app_notifications
    WHERE recipient_id = v_cust2 AND category = 'venue_booking'),
    'venue_booking notification persisted');

  -- rejected venue: fix + resubmit -> pending -> approve; suspended venue
  -- cannot resubmit through the normal path.
  v_venue2 := public.upsert_sports_venue(
    v_owner, NULL, 'Second Arena', NULL, 'Bangkok', 'Sathon',
    'addr2', 13.7, 100.5, 'Asia/Bangkok');
  PERFORM public.set_sports_venue_sports(v_owner, v_venue2,
    jsonb_build_array(jsonb_build_object('sport_id', v_sport)));
  PERFORM public.set_sports_venue_operating_hours(v_owner, v_venue2, (
    SELECT jsonb_agg(jsonb_build_object(
      'day', d, 'open', '00:00', 'close', '23:59', 'closed', false))
    FROM generate_series(0, 6) d));
  PERFORM public.set_sports_venue_amenities(
    v_owner, v_venue2, '{parking}');
  PERFORM public.confirm_sports_venue_platform_terms(v_owner, v_venue2);
  PERFORM public.upsert_sports_venue_court(
    v_owner, NULL, v_venue2, v_sport, 'Court A',
    1, NULL, 'hour', NULL, NULL, 'instant', NULL, true);
  PERFORM pg_temp.expect(
    COALESCE(array_length(
      public.sports_venue_setup_missing(v_venue2), 1), 0) = 0,
    'platform terms + explicit 24/7 hours satisfy readiness');
  PERFORM public.submit_sports_venue_for_review(v_owner, v_venue2);
  PERFORM public.review_sports_venue(
    v_admin, v_venue2, 'rejected', 'ข้อมูลไม่ครบ');
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venues
    WHERE id = v_venue2) = 'rejected'
    AND (SELECT rejection_reason FROM public.sports_venues
      WHERE id = v_venue2) = 'ข้อมูลไม่ครบ',
    'rejected keeps reason for owner correction');
  PERFORM public.submit_sports_venue_for_review(v_owner, v_venue2);
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venues
    WHERE id = v_venue2) = 'pending', 'rejected venue resubmits to pending');
  PERFORM public.review_sports_venue(v_admin, v_venue2, 'approved');
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venues
    WHERE id = v_venue2) = 'approved', 'resubmitted venue approved');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_terms_public
    WHERE venue_id = v_venue2
      AND version = v_platform_version
      AND terms_text = 'Standard venue terms v1'
      AND cancellation_cutoff_minutes = 120),
    'public effective-terms view resolves the configured platform version');

  SELECT id INTO v_court2 FROM public.sports_venue_courts
  WHERE venue_id = v_venue2 AND is_active LIMIT 1;
  v_platform_booking := public.create_sports_venue_booking(
    v_cust, v_court2, pg_temp.bkk_ts(8, '10:00'),
    pg_temp.bkk_ts(8, '11:00'), v_platform_version, 'platform-v1');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_bookings
    WHERE id = v_platform_booking
      AND accepted_terms_version = v_platform_version
      AND terms_text_snapshot = 'Standard venue terms v1'
      AND cancellation_cutoff_minutes_snapshot = 120),
    'platform booking stores current standard-terms snapshot');

  v_platform_terms := public.set_sports_venue_platform_terms(
    v_admin, 'Standard venue terms v2', 180);
  v_platform_version := (v_platform_terms->>'version')::int;
  PERFORM pg_temp.expect(v_platform_version = 2,
    'changing standard terms increments global version');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_bookings
    WHERE id = v_platform_booking
      AND accepted_terms_version = 1
      AND terms_text_snapshot = 'Standard venue terms v1'
      AND cancellation_cutoff_minutes_snapshot = 120),
    'existing booking keeps its accepted terms snapshot');
  PERFORM pg_temp.expect_raise('stale platform terms version rejected',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(9, '10:00'), pg_temp.bkk_ts(9, '11:00'),
      1, 'platform-v1-stale')$$, v_cust, v_court2),
    'TERMS_VERSION_CHANGED');
  v_platform_booking2 := public.create_sports_venue_booking(
    v_cust, v_court2, pg_temp.bkk_ts(9, '10:00'),
    pg_temp.bkk_ts(9, '11:00'), v_platform_version, 'platform-v2');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_bookings
    WHERE id = v_platform_booking2
      AND accepted_terms_version = 2
      AND terms_text_snapshot = 'Standard venue terms v2'
      AND cancellation_cutoff_minutes_snapshot = 180),
    'new booking requires and snapshots latest standard terms');

  v_court3 := public.upsert_sports_venue_court(
    v_owner, NULL, v_venue2, v_sport, 'Pending platform court',
    1, NULL, 'hour', NULL, NULL, 'owner_approval', NULL, true);
  v_b5 := public.create_sports_venue_booking(
    v_cust2, v_court3, pg_temp.bkk_ts(10, '10:00'),
    pg_temp.bkk_ts(10, '11:00'), v_platform_version, 'platform-pending');
  v_platform_terms := public.set_sports_venue_platform_terms(
    v_admin, 'Standard venue terms v3', 240);
  v_platform_version := (v_platform_terms->>'version')::int;
  PERFORM pg_temp.expect_raise('pending slot change requires new standard terms consent',
    format($$SELECT public.change_pending_venue_booking_slot(%L, %L,
      pg_temp.bkk_ts(11, '10:00'), pg_temp.bkk_ts(11, '11:00'), 2)$$,
      v_cust2, v_b5), 'TERMS_VERSION_CHANGED');
  PERFORM public.change_pending_venue_booking_slot(
    v_cust2, v_b5, pg_temp.bkk_ts(11, '10:00'),
    pg_temp.bkk_ts(11, '11:00'), v_platform_version);
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_bookings
    WHERE id = v_b5
      AND accepted_terms_version = v_platform_version
      AND terms_text_snapshot = 'Standard venue terms v3'
      AND cancellation_cutoff_minutes_snapshot = 240),
    'pending slot change updates snapshot after new terms consent');

  PERFORM public.review_sports_venue(
    v_admin, v_venue2, 'suspended', 'ผิดนัดตรวจ');
  PERFORM pg_temp.expect_raise('suspended venue cannot resubmit',
    format('SELECT public.submit_sports_venue_for_review(%L, %L)',
           v_owner, v_venue2));
  PERFORM pg_temp.expect_raise('reject without reason rejected',
    format($s$SELECT public.review_sports_venue(%L, %L, 'rejected')$s$,
      v_admin, v_venue));

  -- =============== 21.7.18 recurring booking release ===============
  -- Court 1 on v_venue (instant approval) is the release test court.
  SELECT id INTO v_rel_court FROM public.sports_venue_courts
  WHERE venue_id = v_venue AND name = 'Court 1';

  -- Validation + manager scope for the venue-level setter.
  PERFORM pg_temp.expect_raise('release rule requires a venue manager',
    format($$SELECT public.set_sports_venue_booking_release(
      %L, %L, 1, '09:00', 14)$$, v_cust, v_venue), 'NOT_VENUE_MANAGER');
  PERFORM pg_temp.expect_raise('partial release rule rejected',
    format($$SELECT public.set_sports_venue_booking_release(
      %L, %L, NULL, '09:00', 14)$$, v_owner, v_venue),
    'INVALID_RELEASE_RULE');
  PERFORM pg_temp.expect_raise('release day outside 0-6 rejected',
    format($$SELECT public.set_sports_venue_booking_release(
      %L, %L, 7, '09:00', 14)$$, v_owner, v_venue),
    'INVALID_RELEASE_RULE');
  PERFORM pg_temp.expect_raise('release window below 7 days rejected',
    format($$SELECT public.set_sports_venue_booking_release(
      %L, %L, 1, '09:00', 6)$$, v_owner, v_venue),
    'INVALID_RELEASE_RULE');

  -- Rule: release today at 00:00 venue-local with a 7-day window, so the
  -- open interval is [today 00:00, +7d 00:00) local.
  v_rel_dow := EXTRACT(dow FROM (now() AT TIME ZONE 'Asia/Bangkok')::date)
    ::smallint;
  PERFORM public.set_sports_venue_booking_release(
    v_owner, v_venue, v_rel_dow, '00:00'::time, 7);
  PERFORM pg_temp.expect((SELECT booking_release_day_of_week
    FROM public.sports_venues WHERE id = v_venue) = v_rel_dow
    AND (SELECT booking_release_window_days
      FROM public.sports_venues WHERE id = v_venue) = 7,
    'venue release rule stored');

  -- opensAt helper: first weekly release R with local(R) > S - N and
  -- R <= S. Fixed dates keep these assertions independent of run time.
  v_slot := '2026-10-20 10:00'::timestamp AT TIME ZONE 'Asia/Bangkok';
  v_rel_dow2 := EXTRACT(dow FROM '2026-10-20'::date)::smallint;
  PERFORM pg_temp.expect(public.sports_venue_booking_release_opens_at(
    'Asia/Bangkok', v_rel_dow2, '09:00'::time, 7, v_slot)
    = '2026-10-20 09:00'::timestamp AT TIME ZONE 'Asia/Bangkok',
    'opensAt uses the same-weekday release before the slot');
  PERFORM pg_temp.expect(public.sports_venue_booking_release_opens_at(
    'Asia/Bangkok', v_rel_dow2, '11:00'::time, 7, v_slot)
    = '2026-10-13 11:00'::timestamp AT TIME ZONE 'Asia/Bangkok',
    'opensAt falls back to the previous weekly release');
  -- DST gap: 2026-03-08 02:30 never happens in New York; the helper must
  -- still resolve the skipped local release through the zone rules.
  PERFORM pg_temp.expect(public.sports_venue_booking_release_opens_at(
    'America/New_York', 0, '02:30'::time, 7,
    '2026-03-09 10:00'::timestamp AT TIME ZONE 'America/New_York')
    = '2026-03-08 02:30'::timestamp AT TIME ZONE 'America/New_York',
    'opensAt resolves a release inside the DST gap');

  -- Availability payload gains serverNow, notOpen entries and the
  -- effective rule echo.
  v_avail := public.get_court_availability(
    v_rel_court, now(), now() + interval '14 days');
  PERFORM pg_temp.expect(v_avail->'serverNow' IS NOT NULL,
    'availability carries serverNow');
  PERFORM pg_temp.expect((v_avail->'release'->>'windowDays')::int = 7,
    'availability echoes the effective release rule');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_avail->'notOpen') e
    WHERE (e->>'slotStart')::timestamptz = pg_temp.bkk_ts(7, '10:00')
      AND (e->>'opensAt')::timestamptz = pg_temp.bkk_ts(7, '00:00')),
    'notOpen opensAt matches the release helper');

  -- Gate: released slots book normally; unreleased ones fail with
  -- BOOKING_NOT_OPEN_YET and the opensAt timestamp in the DETAIL.
  v_rel_booking := public.create_sports_venue_booking(
    v_cust, v_rel_court, pg_temp.bkk_ts(6, '10:00'),
    pg_temp.bkk_ts(6, '11:00'), v_terms, 'release-idem-1');
  PERFORM pg_temp.expect(v_rel_booking IS NOT NULL,
    'released slot books normally');
  v_opens_detail := to_char(
    pg_temp.bkk_ts(7, '00:00') AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  PERFORM pg_temp.expect_raise_detail(
    'unreleased slot rejected with opensAt detail',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(7, '10:00'), pg_temp.bkk_ts(7, '11:00'),
      %s, 'release-closed-1')$$, v_cust, v_rel_court, v_terms),
    'BOOKING_NOT_OPEN_YET', v_opens_detail);
  PERFORM pg_temp.expect_raise('release boundary is exclusive',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(7, '00:30'), pg_temp.bkk_ts(7, '01:30'),
      %s, 'release-closed-2')$$, v_cust, v_rel_court, v_terms),
    'BOOKING_NOT_OPEN_YET');
  PERFORM pg_temp.expect_raise(
    'multi-hour booking crossing the release boundary rejected',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(6, '20:00'), pg_temp.bkk_ts(7, '02:00'),
      %s, 'release-closed-3')$$, v_cust, v_rel_court, v_terms),
    'BOOKING_NOT_OPEN_YET');
  -- v_court is 'Court 2' (owner_approval) — approval bookings are gated
  -- the same way as instant bookings.
  PERFORM pg_temp.expect_raise('owner-approval bookings are gated too',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(7, '10:00'), pg_temp.bkk_ts(7, '11:00'),
      %s, 'release-closed-4')$$, v_cust2, v_court, v_terms),
    'BOOKING_NOT_OPEN_YET');

  -- Pending bookings: created while open, then rescheduling into an
  -- unreleased slot is rejected with the same error contract.
  v_pending_rel := public.create_sports_venue_booking(
    v_cust2, v_court, pg_temp.bkk_ts(5, '14:00'),
    pg_temp.bkk_ts(5, '15:00'), v_terms, 'release-pending-1');
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venue_bookings
    WHERE id = v_pending_rel) = 'pending',
    'release test pending booking created');
  PERFORM pg_temp.expect_raise_detail(
    'pending reschedule into unreleased slot rejected',
    format($$SELECT public.change_pending_venue_booking_slot(%L, %L,
      pg_temp.bkk_ts(7, '10:00'), pg_temp.bkk_ts(7, '11:00'), %s)$$,
      v_cust2, v_pending_rel, v_terms),
    'BOOKING_NOT_OPEN_YET', v_opens_detail);

  -- Rule changes apply to future operations only: the existing pending
  -- booking stays approvable and the idempotent retry still resolves.
  v_rel_dow2 := EXTRACT(dow FROM
    ((now() AT TIME ZONE 'Asia/Bangkok')::date + 1))::smallint;
  PERFORM public.set_sports_venue_booking_release(
    v_owner, v_venue, v_rel_dow2, '00:00'::time, 7);
  PERFORM pg_temp.expect_raise('rule change applies to new bookings',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      pg_temp.bkk_ts(1, '12:00'), pg_temp.bkk_ts(1, '13:00'),
      %s, 'release-new-rule')$$, v_cust, v_rel_court, v_terms),
    'BOOKING_NOT_OPEN_YET');
  PERFORM pg_temp.expect(public.decide_sports_venue_booking(
    v_owner, v_pending_rel, 'approve') = 'confirmed',
    'pending booking stays approvable after rule change');
  PERFORM pg_temp.expect(public.create_sports_venue_booking(
    v_cust, v_rel_court, pg_temp.bkk_ts(6, '10:00'),
    pg_temp.bkk_ts(6, '11:00'), v_terms, 'release-idem-1')
    = v_rel_booking,
    'idempotent retry returns the original booking after rule change');

  -- Court-level overrides on Court 1.
  PERFORM pg_temp.expect_raise('court custom release needs full triple',
    format($$SELECT public.upsert_sports_venue_court(
      %L, %L, %L, %L, 'Court 1', 1, 200, 'hour', 'synthetic', true,
      'instant', NULL, true, NULL, 'custom', NULL, '09:00', 14)$$,
      v_owner, v_rel_court, v_venue, v_sport), 'INVALID_RELEASE_RULE');
  PERFORM pg_temp.expect_raise('unknown release mode rejected',
    format($$SELECT public.upsert_sports_venue_court(
      %L, %L, %L, %L, 'Court 1', 1, 200, 'hour', 'synthetic', true,
      'instant', NULL, true, NULL, 'weekly', 1, '09:00', 14)$$,
      v_owner, v_rel_court, v_venue, v_sport), 'INVALID_RELEASE_RULE');
  -- The override applies on its own weekday, where its 14-day window opens a
  -- slot the venue's 7-day rule still seals.
  PERFORM public.upsert_sports_venue_court(
    v_owner, v_rel_court, v_venue, v_sport, 'Court 1',
    1, 200, 'hour', 'synthetic', true, 'instant', NULL, true, NULL,
    'custom', v_rel_dow, '00:00'::time, 14);
  PERFORM pg_temp.expect(public.create_sports_venue_booking(
    v_cust, v_rel_court, pg_temp.bkk_ts(7, '10:00'),
    pg_temp.bkk_ts(7, '11:00'), v_terms, 'release-custom-1') IS NOT NULL,
    'court custom window releases the slot');
  -- NULL release params keep the override (and price rules) untouched.
  PERFORM public.upsert_sports_venue_court(
    v_owner, v_rel_court, v_venue, v_sport, 'Court 1',
    1, 200, 'hour', 'synthetic', true, 'instant', NULL, true);
  PERFORM pg_temp.expect((SELECT booking_release_mode
    FROM public.sports_venue_courts WHERE id = v_rel_court) = 'custom'
    AND (SELECT booking_release_window_days
      FROM public.sports_venue_courts WHERE id = v_rel_court) = 14,
    'upsert without release params keeps the court override');
  PERFORM public.upsert_sports_venue_court(
    v_owner, v_rel_court, v_venue, v_sport, 'Court 1',
    1, 200, 'hour', 'synthetic', true, 'instant', NULL, true, NULL,
    'always_open', NULL, NULL, NULL);
  PERFORM pg_temp.expect((SELECT booking_release_day_of_week IS NULL
    AND booking_release_time IS NULL
    AND booking_release_window_days IS NULL
    FROM public.sports_venue_courts WHERE id = v_rel_court),
    'always_open clears the custom triple');
  PERFORM pg_temp.expect(public.create_sports_venue_booking(
    v_cust, v_rel_court, pg_temp.bkk_ts(60, '10:00'),
    pg_temp.bkk_ts(60, '11:00'), v_terms, 'release-always-1') IS NOT NULL,
    'always_open court books far ahead');
  -- Back to inherit; clearing the venue rule restores unlimited booking.
  PERFORM public.upsert_sports_venue_court(
    v_owner, v_rel_court, v_venue, v_sport, 'Court 1',
    1, 200, 'hour', 'synthetic', true, 'instant', NULL, true, NULL,
    'inherit', NULL, NULL, NULL);
  PERFORM public.set_sports_venue_booking_release(
    v_owner, v_venue, NULL, NULL, NULL);
  PERFORM pg_temp.expect(public.create_sports_venue_booking(
    v_cust, v_rel_court, pg_temp.bkk_ts(400, '10:00'),
    pg_temp.bkk_ts(400, '11:00'), v_terms, 'release-unlimited-1')
    IS NOT NULL, 'no effective rule means unlimited advance booking');

  v_expiry_my := public.create_sports_venue_booking(
    v_cust2, v_court, pg_temp.bkk_ts(2, '12:00'),
    pg_temp.bkk_ts(2, '13:00'), v_terms, 'housekeeping-booker-lazy');
  UPDATE public.sports_venue_bookings
  SET starts_at = now() - interval '2 hours',
      ends_at = now() - interval '1 hour'
  WHERE id = v_expiry_my;
  v_booking_rows := public.list_my_sports_venue_bookings(
    v_cust2, ARRAY['pending']::varchar[]);
  PERFORM pg_temp.expect(
    (SELECT status FROM public.sports_venue_bookings
     WHERE id = v_expiry_my) = 'expired'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_booking_rows) AS bookings(item)
      WHERE item->>'id' = v_expiry_my::text),
    'booker list expires started requests before filtering');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.app_notifications
    WHERE recipient_id = v_cust2
      AND event_type = 'venue_booking.expired'
      AND payload->>'bookingId' = v_expiry_my::text),
    'lazy expiry persists a notification for the booker');

  v_expiry_manager := public.create_sports_venue_booking(
    v_cust, v_court, pg_temp.bkk_ts(2, '14:00'),
    pg_temp.bkk_ts(2, '15:00'), v_terms, 'housekeeping-manager-lazy');
  UPDATE public.sports_venue_bookings
  SET starts_at = now() - interval '2 hours',
      ends_at = now() - interval '1 hour'
  WHERE id = v_expiry_manager;
  v_booking_rows := public.list_sports_venue_bookings_for_manager(
    v_owner, v_venue, ARRAY['pending']::varchar[]);
  PERFORM pg_temp.expect(
    (SELECT status FROM public.sports_venue_bookings
     WHERE id = v_expiry_manager) = 'expired'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_booking_rows) AS bookings(item)
      WHERE item->>'id' = v_expiry_manager::text),
    'manager queue expires started requests before filtering');

  v_expiry_approval := public.create_sports_venue_booking(
    v_cust2, v_court, pg_temp.bkk_ts(3, '12:00'),
    pg_temp.bkk_ts(3, '13:00'), v_terms, 'housekeeping-late-approval');
  UPDATE public.sports_venue_bookings
  SET starts_at = now() - interval '2 hours',
      ends_at = now() - interval '1 hour'
  WHERE id = v_expiry_approval;
  -- The decision must run as its own statement: a sibling scalar subquery
  -- in the same statement keeps the pre-statement snapshot and would still
  -- read 'pending' after the function's lazy expiry UPDATE.
  v_decision := public.decide_sports_venue_booking(
    v_owner, v_expiry_approval, 'approve');
  PERFORM pg_temp.expect(
    v_decision = 'expired'
    AND (SELECT status FROM public.sports_venue_bookings
         WHERE id = v_expiry_approval) = 'expired',
    'owner cannot approve a request after its slot starts');
  PERFORM pg_temp.expect(
    public.decide_sports_venue_booking(
      v_owner, v_expiry_approval, 'approve') = 'expired',
    'decision retry reports an already-expired request');

  v_expiry_change := public.create_sports_venue_booking(
    v_cust2, v_court, pg_temp.bkk_ts(4, '12:00'),
    pg_temp.bkk_ts(4, '13:00'), v_terms, 'housekeeping-late-reschedule');
  UPDATE public.sports_venue_bookings
  SET starts_at = now() - interval '2 hours',
      ends_at = now() - interval '1 hour'
  WHERE id = v_expiry_change;
  PERFORM public.change_pending_venue_booking_slot(
    v_cust2, v_expiry_change, pg_temp.bkk_ts(5, '12:00'),
    pg_temp.bkk_ts(5, '13:00'), v_terms);
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venue_bookings
    WHERE id = v_expiry_change) = 'expired',
    'rescheduling cannot reopen a request after its slot starts');

  v_completion_lazy := public.create_sports_venue_booking(
    v_cust, v_rel_court, pg_temp.bkk_ts(4, '12:00'),
    pg_temp.bkk_ts(4, '13:00'), v_terms, 'housekeeping-completion-lazy');
  UPDATE public.sports_venue_bookings
  SET starts_at = now() - interval '2 hours',
      ends_at = now() - interval '1 hour'
  WHERE id = v_completion_lazy;
  v_booking_rows := public.list_my_sports_venue_bookings(
    v_cust, ARRAY['confirmed']::varchar[]);
  PERFORM pg_temp.expect(
    (SELECT status FROM public.sports_venue_bookings
     WHERE id = v_completion_lazy) = 'completed'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_booking_rows) AS bookings(item)
      WHERE item->>'id' = v_completion_lazy::text),
    'booker list completes ended bookings before filtering');

  v_expiry_my := public.create_sports_venue_booking(
    v_cust, v_court, pg_temp.bkk_ts(6, '12:00'),
    pg_temp.bkk_ts(6, '13:00'), v_terms, 'housekeeping-cron-sweep');
  UPDATE public.sports_venue_bookings
  SET starts_at = now() - interval '2 hours',
      ends_at = now() - interval '1 hour'
  WHERE id = v_expiry_my;
  v_housekeeping := public.housekeep_sports_venue_bookings();
  PERFORM pg_temp.expect(
    (v_housekeeping->>'expiredPending')::int >= 1
    AND (SELECT status FROM public.sports_venue_bookings
         WHERE id = v_expiry_my) = 'expired',
    'global housekeeping expires pending requests');
  v_housekeeping := public.housekeep_sports_venue_bookings();
  PERFORM pg_temp.expect(
    (v_housekeeping->>'expiredPending')::int = 0
    AND (v_housekeeping->>'completedBookings')::int = 0,
    'repeated housekeeping is idempotent');
  PERFORM pg_temp.expect(
    NOT has_function_privilege(
      'anon', 'public.housekeep_sports_venue_bookings()', 'EXECUTE')
    AND NOT has_function_privilege(
      'authenticated', 'public.housekeep_sports_venue_bookings()', 'EXECUTE'),
    'global housekeeping is not exposed to client roles');
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = $1)'
      INTO v_cron_scheduled
      USING 'sports-hub-booking-housekeeping';
    PERFORM pg_temp.expect(v_cron_scheduled,
      'pg_cron registers the recurring booking housekeeping job');
  END IF;

  RAISE NOTICE 'venue smoke test complete';
END $smoke$;

DO $coach$
DECLARE
  v_admin uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_cust  uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_cust2 uuid := 'dddddddd-0000-0000-0000-000000000004';
  v_sport uuid := 'eeeeeeee-0000-0000-0000-000000000005';
  v_coach uuid; v_req uuid;
BEGIN
  -- 21.7.8 coach profile creation + admin verification
  v_coach := public.upsert_coach_profile(
    v_cust2, 'Coach Bee', 'ex-national player', 'Asia/Bangkok',
    500, 'both', NULL);
  PERFORM pg_temp.expect(v_coach IS NOT NULL, 'coach profile created');

  PERFORM pg_temp.expect_raise('non-admin cannot approve coach',
    format($s$SELECT public.review_coach_profile(%L, %L, 'approved', true)$s$,
      v_cust, v_coach));

  PERFORM public.review_coach_profile(v_admin, v_coach, 'approved', true);
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.coach_profiles
    WHERE id = v_coach AND status = 'approved' AND is_verified),
    'coach approved + verified');

  PERFORM public.set_coach_sports(v_cust2, jsonb_build_array(
    jsonb_build_object('sport_id', v_sport,
      'skill_levels', jsonb_build_array('beginner'),
      'specialties', jsonb_build_array('footwork'))));
  PERFORM public.set_coach_service_areas(v_cust2, jsonb_build_array(
    jsonb_build_object('province', 'Bangkok', 'district', 'Chatuchak',
      'lat', 13.8, 'lng', 100.5, 'radius_km', 20)));
  PERFORM public.set_coach_availability(v_cust2, jsonb_build_array(
    jsonb_build_object('day_of_week',
      extract(isodow from (now() + interval '5 days'))::int,
      'start_time', '18:00', 'end_time', '20:00')));

  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.coach_profiles_public WHERE id = v_coach),
    'approved coach appears in public view');

  -- 21.7.9 coach request lifecycle
  v_req := public.create_coach_booking_request(
    v_cust, v_coach, v_sport, 'onsite',
    now() + interval '5 days 18 hours',
    now() + interval '5 days 19 hours', 'want footwork drills', 'cidem-1');
  PERFORM pg_temp.expect((SELECT status FROM public.coach_booking_requests
    WHERE id = v_req) = 'pending', 'coach request created pending');
  PERFORM pg_temp.expect((SELECT teaching_mode_snapshot IS NOT NULL
    FROM public.coach_booking_requests WHERE id = v_req),
    'request snapshot captured');

  PERFORM pg_temp.expect_raise('requester cannot approve own request',
    format($s$SELECT public.decide_coach_booking_request(%L, %L, 'approve')$s$,
      v_cust, v_req));

  PERFORM public.decide_coach_booking_request(v_cust2, v_req, 'approve');
  PERFORM pg_temp.expect((SELECT status FROM public.coach_booking_requests
    WHERE id = v_req) = 'confirmed', 'coach approves request');

  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.app_notifications
    WHERE recipient_id = v_cust AND category = 'coach_booking'),
    'coach_booking notification persisted');

  PERFORM pg_temp.expect_raise('coach review before completion rejected',
    format($s$SELECT public.submit_coach_review(%L, %L, 5, 'great')$s$,
      v_cust, v_req));

  UPDATE public.coach_booking_requests
    SET starts_at = now() - interval '2 hours',
        ends_at = now() - interval '1 hour'
    WHERE id = v_req;
  PERFORM public.complete_coach_booking_requests();
  PERFORM pg_temp.expect((SELECT status FROM public.coach_booking_requests
    WHERE id = v_req) = 'completed', 'coach request auto-completed');

  PERFORM pg_temp.expect(public.submit_coach_review(
    v_cust, v_req, 5, 'great coach') IS NOT NULL,
    'coach review accepted post-completion');

  PERFORM pg_temp.expect_raise('duplicate coach review rejected',
    format($s$SELECT public.submit_coach_review(%L, %L, 4, 'again')$s$,
      v_cust, v_req));

  RAISE NOTICE 'coach smoke test complete';
END $coach$;

-- ---------------------------------------------------------------------
-- 21.7.12 coach courses/slots/enrollments/favorites/review v2
-- ---------------------------------------------------------------------
DO $courses$
DECLARE
  v_cust  uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_cust2 uuid := 'dddddddd-0000-0000-0000-000000000004';
  v_mgr   uuid := '99999999-0000-0000-0000-000000000007';
  v_sport uuid := 'eeeeeeee-0000-0000-0000-000000000005';
  v_coach uuid;
  v_off uuid; v_sess uuid; v_enr uuid; v_enr2 uuid;
  v_slot uuid; v_req uuid; v_req2 uuid;
  v_review uuid; v_cats jsonb; v_tag uuid;
BEGIN
  SELECT p.id INTO v_coach FROM public.coach_profiles p
    WHERE p.user_id = v_cust2;
  SELECT jsonb_object_agg(c.id::text, 8) INTO v_cats
    FROM public.coach_review_category_catalog c WHERE c.is_active;
  SELECT c.id INTO v_tag FROM public.coach_review_tag_catalog c
    WHERE c.is_active LIMIT 1;

  -- Favorites: toggle on, idempotent list, toggle off.
  PERFORM pg_temp.expect(public.toggle_coach_favorite(v_cust, v_coach),
    'coach favorite toggled on');
  PERFORM pg_temp.expect(v_coach = ANY(
    public.list_my_coach_favorite_ids(v_cust)),
    'favorite ids include coach');
  PERFORM pg_temp.expect(NOT public.toggle_coach_favorite(v_cust, v_coach),
    'coach favorite toggled off');

  -- Course offering: draft -> sessions -> publish.
  v_off := public.upsert_coach_offering(
    v_cust2, NULL, 'course', 'Footwork fundamentals', 'desc', v_sport,
    '{beginner}', 'onsite', NULL, 'สนามกลาง', 'Asia/Bangkok',
    500, 'package', 1, 0, 24, 24, 'cancel', true, false);

  PERFORM pg_temp.expect_raise('publish without sessions rejected',
    format($s$SELECT public.publish_coach_offering(%L, %L)$s$,
      v_cust2, v_off), 'NO_FUTURE_SESSIONS');

  PERFORM public.set_coach_offering_sessions(v_cust2, v_off,
    jsonb_build_array(
      jsonb_build_object('starts_at', now() + interval '3 days',
        'ends_at', now() + interval '3 days 1 hour', 'seq', 1),
      jsonb_build_object('starts_at', now() + interval '4 days',
        'ends_at', now() + interval '4 days 1 hour', 'seq', 2)));
  SELECT s.id INTO v_sess FROM public.coach_offering_sessions s
    WHERE s.offering_id = v_off AND s.seq = 1;

  PERFORM public.publish_coach_offering(v_cust2, v_off);
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.coach_offerings
    WHERE id = v_off AND status = 'published'),
    'course offering published');

  -- Enrollment: consent gate, session selection, idempotency, capacity.
  PERFORM pg_temp.expect_raise('enrollment requires policy consent',
    format($s$SELECT public.create_coach_enrollment(
      %L, %L, ARRAY[%L]::uuid[], false, 'ce-0')$s$,
      v_cust, v_off, v_sess), 'POLICY_CONSENT_REQUIRED');

  -- Course without partial enrollment requires every session.
  PERFORM pg_temp.expect_raise('partial pick rejected for course',
    format($s$SELECT public.create_coach_enrollment(
      %L, %L, ARRAY[%L]::uuid[], true, 'ce-1')$s$,
      v_cust, v_off, v_sess), 'COURSE_REQUIRES_ALL_SESSIONS');

  v_enr := public.create_coach_enrollment(
    v_cust, v_off,
    (SELECT array_agg(s.id) FROM public.coach_offering_sessions s
     WHERE s.offering_id = v_off),
    true, 'ce-2');
  PERFORM pg_temp.expect((SELECT status FROM public.coach_enrollments
    WHERE id = v_enr) = 'confirmed',
    'auto-confirm enrollment confirmed');

  v_enr2 := public.create_coach_enrollment(
    v_cust, v_off,
    (SELECT array_agg(s.id) FROM public.coach_offering_sessions s
     WHERE s.offering_id = v_off),
    true, 'ce-2');
  PERFORM pg_temp.expect(v_enr = v_enr2,
    'enrollment idempotent by key');

  PERFORM pg_temp.expect_raise('capacity 1 rejects second learner',
    format($s$SELECT public.create_coach_enrollment(
      %L, %L,
      (SELECT array_agg(s.id) FROM public.coach_offering_sessions s
       WHERE s.offering_id = %L),
      true, 'ce-3')$s$, v_mgr, v_off, v_off),
    'SESSION_FULL');

  -- 1:1 slot: publish, concurrent pending requests, first approve wins.
  v_off := public.upsert_coach_offering(
    v_cust2, NULL, 'one_on_one', 'Private 1:1', NULL, v_sport,
    '{beginner}', 'onsite', NULL, NULL, 'Asia/Bangkok',
    800, 'per_hour', 1, 0, 24, 24, 'cancel', true, false);
  PERFORM public.publish_coach_offering(v_cust2, v_off);
  v_slot := public.create_coach_slot(
    v_cust2, v_off, now() + interval '6 days', now() + interval '6 days 1 hour', true);

  v_req := public.create_coach_booking_request_v2(
    v_cust, v_slot, 'morning drills', 'slot-idem-1');
  PERFORM pg_temp.expect(
    public.create_coach_booking_request_v2(v_cust, v_slot, 'retry',
      'slot-idem-1') = v_req,
    'slot request idempotent by key');
  PERFORM pg_temp.expect((SELECT status FROM public.coach_slots
    WHERE id = v_slot) = 'published',
    'pending request does not claim the slot');

  v_req2 := public.create_coach_booking_request_v2(
    v_mgr, v_slot, NULL, 'slot-idem-2');
  PERFORM pg_temp.expect(v_req2 IS NOT NULL AND v_req2 <> v_req,
    'second pending request coexists on same slot');
  PERFORM pg_temp.expect_raise('coach cannot request own slot',
    format($s$SELECT public.create_coach_booking_request_v2(
      %L, %L, NULL, 'x')$s$, v_cust2, v_slot), 'SELF_REQUEST_NOT_ALLOWED');

  PERFORM public.decide_coach_booking_request(v_cust2, v_req, 'approve');
  PERFORM pg_temp.expect((SELECT status FROM public.coach_slots
    WHERE id = v_slot) = 'booked', 'first approve claims slot');
  PERFORM pg_temp.expect((SELECT status
    FROM public.coach_booking_requests WHERE id = v_req2) = 'rejected',
    'losing pending request auto-rejected');
  PERFORM pg_temp.expect_raise('new request on booked slot fails',
    format($s$SELECT public.create_coach_booking_request_v2(
      %L, %L, NULL, 'late')$s$, v_cust, v_slot), 'SLOT_UNAVAILABLE');

  -- Review v2 on a completed enrollment session.
  v_off := public.upsert_coach_offering(
    v_cust2, NULL, 'class', 'Morning class', NULL, v_sport,
    '{beginner}', 'onsite', NULL, NULL, 'Asia/Bangkok',
    300, 'per_session', 5, 0, 24, 24, 'cancel', true, true);
  PERFORM public.set_coach_offering_sessions(v_cust2, v_off,
    jsonb_build_array(jsonb_build_object(
      'starts_at', now() + interval '3 days',
      'ends_at', now() + interval '3 days 1 hour', 'seq', 1)));
  SELECT s.id INTO v_sess FROM public.coach_offering_sessions s
    WHERE s.offering_id = v_off;
  PERFORM public.publish_coach_offering(v_cust2, v_off);
  v_enr := public.create_coach_enrollment(
    v_cust, v_off, ARRAY[v_sess]::uuid[], true, 'ce-4');
  UPDATE public.coach_offering_sessions
    SET status = 'completed' WHERE id = v_sess;
  UPDATE public.coach_enrollment_sessions
    SET status = 'completed'
    WHERE enrollment_id = v_enr AND session_id = v_sess;

  PERFORM pg_temp.expect_raise('missing category scores rejected',
    format($s$SELECT public.submit_coach_review_v2(
      %L, '{}'::jsonb, NULL, NULL, NULL, NULL, %L, %L)$s$,
      v_cust, v_enr, v_sess), 'MISSING_CATEGORY_SCORES');

  PERFORM pg_temp.expect_raise('invalid tag rejected',
    format($s$SELECT public.submit_coach_review_v2(
      %L, %L, NULL, ARRAY[%L]::uuid[], NULL, NULL, %L, %L)$s$,
      v_cust, v_cats, gen_random_uuid(), v_enr, v_sess), 'INVALID_TAG');

  v_review := public.submit_coach_review_v2(
    v_cust, v_cats, 'great class', ARRAY[v_tag]::uuid[],
    '{สนุก}'::text[], NULL, v_enr, v_sess);
  PERFORM pg_temp.expect(v_review IS NOT NULL,
    'coach v2 review accepted');
  PERFORM pg_temp.expect((SELECT r.rating_10
    FROM public.coach_reviews r WHERE r.id = v_review) = 8.0,
    'overall is mean of category scores');

  PERFORM pg_temp.expect_raise('duplicate session review rejected',
    format($s$SELECT public.submit_coach_review_v2(
      %L, %L, NULL, NULL, NULL, NULL, %L, %L)$s$,
      v_cust, v_cats, v_enr, v_sess), 'ALREADY_REVIEWED');

  -- Helpful votes are idempotent and self-votes are rejected.
  PERFORM public.set_coach_review_helpful(v_cust2, v_review, true);
  PERFORM public.set_coach_review_helpful(v_cust2, v_review, true);
  PERFORM pg_temp.expect((SELECT COUNT(*)::int
    FROM public.coach_review_helpful_votes
    WHERE review_id = v_review) = 1,
    'helpful vote idempotent');
  PERFORM pg_temp.expect_raise('self helpful vote rejected',
    format($s$SELECT public.set_coach_review_helpful(%L, %L, true)$s$,
      v_cust, v_review), 'SELF_VOTE_NOT_ALLOWED');

  -- Aggregates: published review counts into summary v2.
  PERFORM pg_temp.expect(((public.get_coach_review_summary_v2(v_coach)
    ->>'review_count')::int) >= 1,
    'summary v2 counts published review');

  RAISE NOTICE 'coach courses smoke test complete';
END $courses$;

-- ---------------------------------------------------------------------
-- Notification delivery hotfix (20260925110000)
-- ---------------------------------------------------------------------
DO $notify$
DECLARE
  v_admin uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_cust  uuid := 'cccccccc-0000-0000-0000-000000000003';
BEGIN
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'app_notifications'
      AND column_name = 'profession_id' AND is_nullable = 'YES'),
    'profession_id nullable after delivery migration');

  PERFORM public.sports_hub_notify(
    v_admin, 'venue_supply', 'probe.delivery', 't', 'b', '{}'::jsonb);
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.app_notifications
    WHERE recipient_id = v_admin AND event_type = 'probe.delivery'),
    'sports_hub_notify persists row without profession_id');

  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.list_app_notifications(v_admin, 'venue_supply', 50, false)
    WHERE event_type = 'probe.delivery'),
    'list_app_notifications returns row for recipient');
  PERFORM pg_temp.expect(NOT EXISTS(
    SELECT 1 FROM public.list_app_notifications(v_cust, 'venue_supply', 50, false)
    WHERE event_type = 'probe.delivery'),
    'list_app_notifications isolates other recipients');
  PERFORM pg_temp.expect(NOT EXISTS(
    SELECT 1 FROM public.list_app_notifications(v_admin, 'coach_booking', 50, false)
    WHERE event_type = 'probe.delivery'),
    'list_app_notifications honors category filter');

  RAISE NOTICE 'notification delivery smoke test complete';
END $notify$;

-- ---------------------------------------------------------------------
-- Shared sport catalog usage ranking (20260928120000, Phase 21.7.13)
-- ---------------------------------------------------------------------
DO $usage$
DECLARE
  v_u1    uuid := 'abababab-0000-0000-0000-0000000000a1';
  v_u2    uuid := 'abababab-0000-0000-0000-0000000000a2';
  v_s1    uuid := 'eeeeeeee-0000-0000-0000-0000000000b1';
  v_s2    uuid := 'eeeeeeee-0000-0000-0000-0000000000b2';
  v_s3    uuid := 'eeeeeeee-0000-0000-0000-0000000000b3';
  v_s4    uuid := 'eeeeeeee-0000-0000-0000-0000000000b4';
  v_bad   uuid := 'eeeeeeee-0000-0000-0000-0000000000b5';
  v_ent_a uuid := 'cccccccc-0000-0000-0000-0000000000a1';
  v_ent_b uuid := 'cccccccc-0000-0000-0000-0000000000a2';
  v_top   uuid;
  v_cnt   int;
BEGIN
  INSERT INTO public.users (id, first_name, role) VALUES
    (v_u1, 'UsageU1', 'user'), (v_u2, 'UsageU2', 'user')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.sports (id, name_th, name_en, icon, status) VALUES
    (v_s1, 'AAUsage1', 'UsageA', '🏐', 'approved'),
    (v_s2, 'AAUsage2', 'UsageB', '🎾', 'approved'),
    (v_s3, 'AAUsage3', 'UsageC', '🏀', 'approved'),
    (v_s4, 'AAUsage4', 'UsageD', '🥏', 'approved'),
    (v_bad, 'AAUsageBad', 'UsageX', '🚫', 'pending')
  ON CONFLICT (id) DO NOTHING;
  DELETE FROM public.sport_detail_open_events WHERE user_id IN (v_u1, v_u2);

  -- First open recorded; idempotent event_id retry does not double count.
  PERFORM pg_temp.expect(
    public.record_sport_detail_open(v_u1, '11111111-0000-0000-0000-000000000001',
      v_s1, 'buddies', v_ent_a),
    'first detail open returns true');
  PERFORM pg_temp.expect(NOT
    public.record_sport_detail_open(v_u1, '11111111-0000-0000-0000-000000000001',
      v_s1, 'buddies', v_ent_a),
    'event_id retry not counted');
  PERFORM pg_temp.expect((SELECT COUNT(*)::int
    FROM public.sport_detail_open_events WHERE user_id = v_u1) = 1,
    'exactly one row after retry');

  -- Same entity within the dedupe window ignored even with a new event_id.
  PERFORM pg_temp.expect(NOT
    public.record_sport_detail_open(v_u1, '11111111-0000-0000-0000-000000000002',
      v_s1, 'buddies', v_ent_a),
    'same entity inside 24h deduped');

  -- Same sport via a different domain is an independent signal.
  PERFORM public.record_sport_detail_open(v_u1, '11111111-0000-0000-0000-000000000003',
    v_s1, 'coaches', v_ent_b);
  -- Different entity in the same domain counts.
  PERFORM public.record_sport_detail_open(v_u1, '11111111-0000-0000-0000-000000000004',
    v_s2, 'coaches', 'cccccccc-0000-0000-0000-0000000000a3');
  PERFORM pg_temp.expect((SELECT COUNT(*)::int
    FROM public.sport_detail_open_events WHERE user_id = v_u1) = 3,
    'cross-domain and different-entity opens counted');

  -- Validation: bad domain, non-approved sport, null user all rejected.
  PERFORM pg_temp.expect_raise('invalid domain rejected',
    format($s$SELECT public.record_sport_detail_open(%L, %L, %L, %L, NULL)$s$,
      v_u1, gen_random_uuid(), v_s1, 'bad_domain'), 'INVALID_DOMAIN');
  PERFORM pg_temp.expect_raise('non-approved sport rejected',
    format($s$SELECT public.record_sport_detail_open(%L, %L, %L, %L, NULL)$s$,
      v_u1, gen_random_uuid(), v_bad, 'buddies'), 'INVALID_SPORT');
  PERFORM pg_temp.expect_raise('null user rejected',
    $s$SELECT public.record_sport_detail_open(NULL, gen_random_uuid(),
      'eeeeeeee-0000-0000-0000-0000000000b1'::uuid, 'buddies', NULL)$s$,
    'UNAUTHORIZED');

  -- Ranking: s1 opened in two domains beats s2 (one domain).
  v_top := (SELECT id FROM public.list_sport_ranking(v_u1)
    ORDER BY score DESC, last_opened_at DESC NULLS LAST, name_th ASC, id
    LIMIT 1);
  PERFORM pg_temp.expect(v_top = v_s1,
    'most-used cross-domain sport ranked first for u1');

  -- Catalog completeness: every approved sport returned, pending excluded.
  PERFORM pg_temp.expect((SELECT COUNT(*)::int
    FROM public.list_sport_ranking(v_u1)
    WHERE id IN (v_s1, v_s2, v_s3, v_s4)) = 4,
    'ranking returns all approved sports');
  PERFORM pg_temp.expect(NOT EXISTS(
    SELECT 1 FROM public.list_sport_ranking(v_u1) WHERE id = v_bad),
    'pending sport excluded from catalog');

  -- Guests get the deterministic catalog; per-user isolation holds.
  PERFORM pg_temp.expect((SELECT COUNT(*)::int
    FROM public.list_sport_ranking(NULL)
    WHERE id IN (v_s1, v_s2, v_s3, v_s4)) = 4,
    'guest ranking returns approved sports');
  PERFORM public.record_sport_detail_open(v_u2, '22222222-0000-0000-0000-000000000001',
    v_s3, 'courts', v_ent_b);
  v_top := (SELECT id FROM public.list_sport_ranking(v_u2)
    ORDER BY score DESC, last_opened_at DESC NULLS LAST, name_th ASC, id
    LIMIT 1);
  PERFORM pg_temp.expect(v_top = v_s3, 'u2 top sport is its own usage');

  DELETE FROM public.sport_detail_open_events WHERE user_id IN (v_u1, v_u2);
  RAISE NOTICE 'sport usage ranking smoke test complete';
END $usage$;

-- =====================================================================
-- 21.7.19 — two-level unit labels (venue & resource)
-- =====================================================================
DO $labels$
DECLARE
  v_admin uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_owner uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  v_cust  uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_yoga  uuid := 'eeeeeeee-0000-0000-0000-0000000000f0';
  v_unknown uuid := 'eeeeeeee-0000-0000-0000-0000000000f1';
  v_pending_sport uuid := 'eeeeeeee-0000-0000-0000-0000000000f2';
  v_badminton uuid := 'eeeeeeee-0000-0000-0000-000000000005';
  v_new_sport uuid := 'eeeeeeee-0000-0000-0000-0000000000f3';
  v_venue uuid; v_venue2 uuid; v_court uuid; v_booking uuid;
  v_detail jsonb; v_rows jsonb; v_terms int;
BEGIN
  -- Catalog coverage: every sports row (any status) has a 'th' default,
  -- curated rows win over the generic 'สนาม' fallback.
  PERFORM pg_temp.expect(NOT EXISTS(
    SELECT 1 FROM public.sports s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.sports_venue_unit_defaults d
      WHERE d.sport_id = s.id AND d.locale = 'th')),
    'every sports row has a th venue-label default');
  PERFORM pg_temp.expect((SELECT singular
    FROM public.sports_venue_unit_defaults
    WHERE sport_id = v_yoga AND locale = 'th') = 'สตูดิโอโยคะ',
    'curated venue label applied for Yoga');
  PERFORM pg_temp.expect((SELECT singular
    FROM public.sports_venue_unit_defaults
    WHERE sport_id = v_unknown AND locale = 'th') = 'สนาม',
    'uncurated sport falls back to generic สนาม');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_unit_defaults
    WHERE sport_id = v_pending_sport AND locale = 'th'),
    'pending sport still has a fallback row');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM pg_policies
    WHERE tablename = 'sports_venue_unit_defaults'
      AND policyname = 'sports_venue_unit_defaults_select_approved'),
    'catalog select restricted to approved sports via policy');

  -- Future sports get generic defaults through the AFTER INSERT trigger.
  INSERT INTO public.sports (id, name_en, status)
    VALUES (v_new_sport, 'Brand New Sport', 'approved');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venue_unit_defaults
    WHERE sport_id = v_new_sport AND locale = 'th' AND singular = 'สนาม'),
    'trigger seeds generic defaults for sports created after migration');

  -- Admin-only catalog maintenance.
  PERFORM pg_temp.expect_raise('non-admin cannot edit venue catalog',
    format($s$SELECT public.upsert_sports_venue_unit_default(
      %L, %L, 'th', 'x', 'x')$s$, v_cust, v_yoga), 'NOT_ADMIN');
  PERFORM public.upsert_sports_venue_unit_default(
    v_admin, v_unknown, 'th', 'สนามทดลอง', NULL);
  PERFORM pg_temp.expect((SELECT singular
    FROM public.sports_venue_unit_defaults
    WHERE sport_id = v_unknown AND locale = 'th') = 'สนามทดลอง',
    'admin mapping RPC updates catalog rows');

  -- Venue label: create cannot carry a reference (no sports yet).
  v_venue := public.upsert_sports_venue(
    v_owner, NULL, 'Label Studio', NULL, 'Bangkok', 'Chatuchak',
    'addr', 13.8, 100.5, 'Asia/Bangkok');
  PERFORM pg_temp.expect_raise('create cannot set label reference',
    format($s$SELECT public.upsert_sports_venue(
      %L, NULL, 'X', NULL, NULL, NULL, NULL, 1, 1,
      'Asia/Bangkok', NULL, %L)$s$, v_owner, v_yoga),
    'INVALID_UNIT_LABEL_REFERENCE');

  -- Single sport is auto-picked as the venue-label reference.
  PERFORM public.set_sports_venue_sports(v_owner, v_venue,
    jsonb_build_array(jsonb_build_object('sport_id', v_yoga)));
  PERFORM pg_temp.expect((SELECT venue_unit_label_sport_id
    FROM public.sports_venues WHERE id = v_venue) = v_yoga,
    'single sport auto-picked as label reference');
  PERFORM pg_temp.expect(public.sports_venue_unit_label(v_venue)
    = 'สตูดิโอโยคะ', 'venue label resolves from reference sport catalog');

  -- Explicit setter: custom override wins; clearing returns to sport-derived.
  PERFORM public.set_sports_venue_unit_label(
    v_owner, v_venue, 'ยิมสตู', v_yoga);
  PERFORM pg_temp.expect(public.sports_venue_unit_label(v_venue) = 'ยิมสตู',
    'custom venue override wins over catalog');
  PERFORM public.set_sports_venue_unit_label(
    v_owner, v_venue, NULL, v_yoga);
  PERFORM pg_temp.expect(public.sports_venue_unit_label(v_venue)
    = 'สตูดิโอโยคะ', 'clearing override returns to sport-derived label');
  PERFORM pg_temp.expect_raise('reference must be a venue sport',
    format($s$SELECT public.set_sports_venue_unit_label(
      %L, %L, NULL, %L)$s$, v_owner, v_venue, v_badminton),
    'INVALID_UNIT_LABEL_REFERENCE');
  PERFORM pg_temp.expect_raise('non-manager cannot set venue label',
    format($s$SELECT public.set_sports_venue_unit_label(
      %L, %L, 'x', NULL)$s$, v_cust, v_venue), 'NOT_VENUE_MANAGER');
  PERFORM pg_temp.expect_raise('overlong venue label rejected',
    format($s$SELECT public.set_sports_venue_unit_label(
      %L, %L, %L, NULL)$s$, v_owner, v_venue, repeat('x', 41)),
    'INVALID_UNIT_LABEL');

  -- Resource label: live resolution cascades venue+sport defaults.
  v_court := public.upsert_sports_venue_court(
    v_owner, NULL, v_venue, v_yoga, 'Zone 1', 1, 100, 'hour', NULL, NULL,
    'instant', NULL, true, NULL);
  PERFORM pg_temp.expect(public.sports_venue_court_unit_label(v_court)
    = 'สนาม', 'court without override uses generic resource label');
  PERFORM public.set_sports_venue_sports(v_owner, v_venue,
    jsonb_build_array(jsonb_build_object(
      'sport_id', v_yoga, 'unit_label_override', 'เสื่อ')));
  PERFORM pg_temp.expect(public.sports_venue_court_unit_label(v_court)
    = 'เสื่อ', 'venue+sport resource override cascades to inheriting court');

  -- Three-state override contract via upsert_sports_venue_court.
  v_court := public.upsert_sports_venue_court(
    v_owner, v_court, v_venue, v_yoga, 'Zone 1', 1, 100, 'hour', NULL, NULL,
    'instant', NULL, true, NULL,
    NULL, NULL, NULL, NULL, 'custom', 'โซน A');
  PERFORM pg_temp.expect(public.sports_venue_court_unit_label(v_court)
    = 'โซน A', 'custom mode sets a per-court resource override');
  v_court := public.upsert_sports_venue_court(
    v_owner, v_court, v_venue, v_yoga, 'Zone 1', 1, 100, 'hour', NULL, NULL,
    'instant', NULL, true, NULL,
    NULL, NULL, NULL, NULL, 'inherit', NULL);
  PERFORM pg_temp.expect(public.sports_venue_court_unit_label(v_court)
    = 'เสื่อ', 'inherit mode returns to the venue+sport default');
  PERFORM pg_temp.expect_raise('custom mode requires label text',
    format($s$SELECT public.upsert_sports_venue_court(
      %L, %L, %L, %L, 'Zone 1', 1, 100, 'hour', NULL, NULL,
      'instant', NULL, true, NULL,
      NULL, NULL, NULL, NULL, 'custom', NULL)$s$,
      v_owner, v_court, v_venue, v_yoga), 'INVALID_UNIT_LABEL');
  PERFORM pg_temp.expect_raise('unknown unit label mode rejected',
    format($s$SELECT public.upsert_sports_venue_court(
      %L, %L, %L, %L, 'Zone 1', 1, 100, 'hour', NULL, NULL,
      'instant', NULL, true, NULL,
      NULL, NULL, NULL, NULL, 'bogus', NULL)$s$,
      v_owner, v_court, v_venue, v_yoga), 'INVALID_UNIT_LABEL_MODE');

  -- Legacy callers (no mode params) keep the old semantics: non-empty
  -- p_unit_label becomes the stored label, empty means inherit.
  v_court := public.upsert_sports_venue_court(
    v_owner, v_court, v_venue, v_yoga, 'Zone 1', 1, 100, 'hour', NULL, NULL,
    'instant', 'เลน B', true, NULL);
  PERFORM pg_temp.expect(public.sports_venue_court_unit_label(v_court)
    = 'เลน B', 'legacy p_unit_label text maps to a per-court override');
  v_court := public.upsert_sports_venue_court(
    v_owner, v_court, v_venue, v_yoga, 'Zone 1', 1, 100, 'hour', NULL, NULL,
    'instant', NULL, true, NULL);
  PERFORM pg_temp.expect(public.sports_venue_court_unit_label(v_court)
    = 'เสื่อ', 'legacy empty p_unit_label inherits again');
  PERFORM pg_temp.expect_raise('update cannot set a non-member reference',
    format($s$SELECT public.upsert_sports_venue(
      %L, %L, 'X', NULL, NULL, NULL, NULL, 1, 1,
      'Asia/Bangkok', NULL, %L)$s$, v_owner, v_venue, v_badminton),
    'INVALID_UNIT_LABEL_REFERENCE');

  -- Full venue setup so public views and bookings can be exercised
  -- (the court must exist before submit or VENUE_NOT_READY is raised).
  PERFORM public.set_sports_venue_operating_hours(v_owner, v_venue, (
    SELECT jsonb_agg(jsonb_build_object(
      'day', d, 'open', '08:00', 'close', '22:00', 'closed', false))
    FROM generate_series(0, 6) d));
  PERFORM public.set_sports_venue_amenities(v_owner, v_venue, '{}');
  v_terms := public.publish_sports_venue_terms(
    v_owner, v_venue, 'Label terms', 60);
  PERFORM public.submit_sports_venue_for_review(v_owner, v_venue);
  PERFORM public.review_sports_venue(v_admin, v_venue, 'approved');
  PERFORM pg_temp.expect((SELECT venue_unit_label
    FROM public.sports_venues_public WHERE id = v_venue) = 'สตูดิโอโยคะ',
    'public venue view exposes resolved venue label');
  PERFORM pg_temp.expect((SELECT unit_label
    FROM public.sports_venue_courts_public WHERE id = v_court) = 'เสื่อ',
    'public court view returns live-resolved resource label');

  -- A stored column that drifts must never leak through the public view.
  PERFORM public.set_sports_venue_sports(v_owner, v_venue,
    jsonb_build_array(jsonb_build_object(
      'sport_id', v_yoga, 'unit_label_override', 'เสื่อใหม่')));
  PERFORM pg_temp.expect((SELECT unit_label
    FROM public.sports_venue_courts_public WHERE id = v_court) = 'เสื่อใหม่',
    'public view resolves live, not the stale stored column');
  PERFORM pg_temp.expect((SELECT unit_label
    FROM public.sports_venue_courts WHERE id = v_court) = 'เสื่อ',
    'compat column stays stale until the next court write');
  PERFORM public.set_sports_venue_sports(v_owner, v_venue,
    jsonb_build_array(jsonb_build_object(
      'sport_id', v_yoga, 'unit_label_override', 'เสื่อ')));

  -- Reference lifecycle on a second venue: explicit reference, keep when
  -- still a member, heal to the single member when it is removed.
  v_venue2 := public.upsert_sports_venue(
    v_owner, NULL, 'Multi Sport Hub', NULL, 'Bangkok', 'Chatuchak',
    'addr', 13.8, 100.5, 'Asia/Bangkok');
  PERFORM public.set_sports_venue_sports(v_owner, v_venue2,
    jsonb_build_array(
      jsonb_build_object('sport_id', v_yoga),
      jsonb_build_object('sport_id', v_badminton)),
    v_yoga);
  PERFORM pg_temp.expect(public.sports_venue_unit_label(v_venue2)
    = 'สตูดิโอโยคะ', 'explicit reference sport drives venue label');
  PERFORM public.set_sports_venue_sports(v_owner, v_venue2,
    jsonb_build_array(
      jsonb_build_object('sport_id', v_yoga),
      jsonb_build_object('sport_id', v_badminton)));
  PERFORM pg_temp.expect((SELECT venue_unit_label_sport_id
    FROM public.sports_venues WHERE id = v_venue2) = v_yoga,
    'omitted reference kept while it is still a member');
  PERFORM pg_temp.expect_raise('non-member reference rejected',
    format($s$SELECT public.set_sports_venue_sports(
      %L, %L, jsonb_build_array(
        jsonb_build_object('sport_id', %L)), %L)$s$,
      v_owner, v_venue2, v_badminton, v_yoga),
    'INVALID_UNIT_LABEL_REFERENCE');
  PERFORM pg_temp.expect((SELECT count(*)::int
    FROM public.sports_venue_sports WHERE venue_id = v_venue2) = 2,
    'rejected reference leaves the sport set unchanged');
  PERFORM public.set_sports_venue_sports(v_owner, v_venue2,
    jsonb_build_array(jsonb_build_object('sport_id', v_badminton)));
  PERFORM pg_temp.expect((SELECT venue_unit_label_sport_id
    FROM public.sports_venues WHERE id = v_venue2) = v_badminton,
    'removed reference heals to the single remaining member');
  PERFORM pg_temp.expect(public.sports_venue_unit_label(v_venue2) = 'สนาม',
    'healed reference resolves through its own catalog row');

  -- Booking snapshots capture both levels and stay immutable afterwards.
  PERFORM public.set_sports_venue_unit_label(
    v_owner, v_venue, 'ยิมสตู', v_yoga);
  v_booking := public.create_sports_venue_booking(
    v_cust, v_court, pg_temp.bkk_ts(30, '10:00'),
    pg_temp.bkk_ts(30, '11:00'), v_terms, 'label-booking-1');
  PERFORM pg_temp.expect((SELECT venue_unit_label_snapshot
    FROM public.sports_venue_bookings WHERE id = v_booking) = 'ยิมสตู',
    'booking snapshots the venue label');
  PERFORM pg_temp.expect((SELECT unit_label_snapshot
    FROM public.sports_venue_bookings WHERE id = v_booking) = 'เสื่อ',
    'booking snapshots the resource label');
  PERFORM pg_temp.expect((SELECT title FROM public.app_notifications
    WHERE payload->>'bookingId' = v_booking::text
      AND recipient_id = v_cust
    ORDER BY created_at DESC LIMIT 1) = 'การจองยิมสตูยืนยันแล้ว',
    'new notification titles use the venue label');
  PERFORM public.set_sports_venue_unit_label(
    v_owner, v_venue, 'ยิมใหม่', v_yoga);
  PERFORM pg_temp.expect((SELECT venue_unit_label_snapshot
    FROM public.sports_venue_bookings WHERE id = v_booking) = 'ยิมสตู',
    'snapshots are immutable when the venue label changes');

  -- Booking lists expose both levels; legacy rows keep a NULL venue label.
  v_rows := public.list_my_sports_venue_bookings(v_cust);
  PERFORM pg_temp.expect((SELECT r->>'venueUnitLabel'
    FROM jsonb_array_elements(v_rows) r
    WHERE (r->>'id')::uuid = v_booking) = 'ยิมสตู',
    'booking list exposes the venue snapshot');
  UPDATE public.sports_venue_bookings
  SET venue_unit_label_snapshot = NULL WHERE id = v_booking;
  v_rows := public.list_my_sports_venue_bookings(v_cust);
  PERFORM pg_temp.expect((SELECT r->>'venueUnitLabel'
    FROM jsonb_array_elements(v_rows) r
    WHERE (r->>'id')::uuid = v_booking) IS NULL,
    'legacy bookings keep a NULL venue snapshot for neutral copy');
  UPDATE public.sports_venue_bookings
  SET venue_unit_label_snapshot = 'ยิมสตู' WHERE id = v_booking;
  v_rows := public.list_sports_venue_bookings_for_manager(v_owner, v_venue);
  PERFORM pg_temp.expect((SELECT r->>'venueUnitLabel'
    FROM jsonb_array_elements(v_rows) r
    WHERE (r->>'id')::uuid = v_booking) = 'ยิมสตู',
    'manager booking list exposes the venue snapshot');

  -- Owner/admin detail surfaces carry the resolved labels.
  v_detail := public.get_my_sports_venue_detail(v_owner, v_venue);
  PERFORM pg_temp.expect(v_detail->'venue'->>'venueUnitLabel' = 'ยิมใหม่',
    'owner detail exposes resolved venue label');
  PERFORM pg_temp.expect(v_detail->'venue'->>'venue_unit_label_override'
    = 'ยิมใหม่', 'owner detail exposes the raw venue override');
  PERFORM pg_temp.expect((SELECT c->>'unit_label'
    FROM jsonb_array_elements(v_detail->'courts') c
    WHERE (c->>'id')::uuid = v_court) = 'เสื่อ',
    'owner detail exposes live-resolved resource label');
  v_detail := public.get_sports_venue_admin_review_detail(v_admin, v_venue);
  PERFORM pg_temp.expect(v_detail->'venue'->>'venueUnitLabel' = 'ยิมใหม่',
    'admin review detail exposes resolved venue label');
  PERFORM pg_temp.expect((SELECT venue_unit_label
    FROM public.list_my_sports_venues(v_owner)
    WHERE id = v_venue) = 'ยิมใหม่',
    'owner venue list exposes resolved venue label');
  PERFORM pg_temp.expect((SELECT venue_unit_label
    FROM public.sports_venues_public WHERE id = v_venue) = 'ยิมใหม่',
    'public view tracks the current venue label');

  RAISE NOTICE 'unit labels smoke test complete';
END $labels$;

DO $release_days$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_profile UUID := gen_random_uuid();
  v_venue UUID := gen_random_uuid();
  v_sport UUID;
  v_court UUID;
  v_availability JSONB;
BEGIN
  SELECT id INTO v_sport
  FROM public.sports
  WHERE status = 'approved'
  ORDER BY id
  LIMIT 1;
  IF v_sport IS NULL THEN
    INSERT INTO public.sports (name_en, status)
    VALUES ('Release Days Smoke', 'approved')
    RETURNING id INTO v_sport;
  END IF;

  INSERT INTO public.users (id, first_name, last_name, role)
  VALUES (v_owner, 'Release', 'Days', 'owner');
  INSERT INTO public.sports_venue_owner_profiles (
    id, user_id, business_name, contact_name, contact_phone, status
  ) VALUES (
    v_profile, v_owner, 'Release Days Smoke', 'Release Days', '0000000000',
    'approved');
  INSERT INTO public.sports_venues (
    id, owner_profile_id, name, timezone, status
  ) VALUES (
    v_venue, v_profile, 'Release Days Smoke', 'Asia/Bangkok', 'approved');
  INSERT INTO public.sports_venue_sports (venue_id, sport_id)
  VALUES (v_venue, v_sport);

  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_min_window(
      ARRAY[0,1,2,3,4,5,6]::SMALLINT[]) = 1,
    'daily release allows a one-day window');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_min_window(
      ARRAY[1]::SMALLINT[]) = 7,
    'one weekly release requires a seven-day window');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_min_window(
      ARRAY[1,3]::SMALLINT[]) = 5,
    'multi-day minimum covers the longest weekly gap');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_opens_at_for_days(
      'Asia/Bangkok', ARRAY[0,1,2,3,4,5,6]::SMALLINT[],
      '09:00', 1,
      '2026-10-20 10:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok')
      = '2026-10-20 09:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    'daily release opens every day at the shared local time');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_opens_at_for_days(
      'Asia/Bangkok', ARRAY[1,3]::SMALLINT[], '09:00', 5,
      '2026-10-23 10:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok')
      = '2026-10-19 09:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    'multi-day releases select the earliest covering weekday');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_opens_at_for_days(
      'America/New_York', ARRAY[0,2,4]::SMALLINT[], '02:30', 3,
      '2026-03-09 10:00'::TIMESTAMP AT TIME ZONE 'America/New_York')
      = '2026-03-08 02:30'::TIMESTAMP AT TIME ZONE 'America/New_York',
    'multi-day release resolves a local DST gap');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_opens_at_for_days(
      'America/New_York', ARRAY[0,1,2,3,4,5,6]::SMALLINT[],
      '01:30', 1, '2026-11-01 01:45:00-04'::TIMESTAMPTZ)
      = '2026-10-31 01:30'::TIMESTAMP AT TIME ZONE 'America/New_York',
    'daily release resolves a local DST overlap before the slot');

  PERFORM public.set_sports_venue_booking_release_days(
    v_owner, v_venue, '[0,1,2,3,4,5,6]'::JSONB, '09:00', 1);
  PERFORM pg_temp.expect((SELECT booking_release_days
      FROM public.sports_venues WHERE id = v_venue)
      = ARRAY[0,1,2,3,4,5,6]::SMALLINT[]
    AND (SELECT booking_release_day_of_week
      FROM public.sports_venues WHERE id = v_venue) = 0
    AND (SELECT booking_release_window_days
      FROM public.sports_venues WHERE id = v_venue) = 1,
    'venue setter stores all selected days and legacy first-day alias');
  PERFORM pg_temp.expect_raise(
    'selected-day window below its maximum gap is rejected',
    format($s$SELECT public.set_sports_venue_booking_release_days(
      %L, %L, '[1,3]'::JSONB, '09:00', 4)$s$, v_owner, v_venue),
    'INVALID_RELEASE_RULE');
  PERFORM pg_temp.expect_raise(
    'duplicate release weekdays are rejected',
    format($s$SELECT public.set_sports_venue_booking_release_days(
      %L, %L, '[1,1]'::JSONB, '09:00', 7)$s$, v_owner, v_venue),
    'INVALID_RELEASE_RULE');
  PERFORM pg_temp.expect_raise(
    'table constraint rejects duplicate stored weekdays',
    format($s$UPDATE public.sports_venues
      SET booking_release_days = ARRAY[1,1]::SMALLINT[] WHERE id = %L$s$,
      v_venue),
    'sports_venues_booking_release_chk');
  PERFORM pg_temp.expect_raise(
    'release weekday outside 0-6 is rejected',
    format($s$SELECT public.set_sports_venue_booking_release_days(
      %L, %L, '[7]'::JSONB, '09:00', 7)$s$, v_owner, v_venue),
    'INVALID_RELEASE_RULE');
  PERFORM public.set_sports_venue_booking_release_days(
    v_owner, v_venue, '[3,1]'::JSONB, '09:00', 5);
  PERFORM pg_temp.expect((SELECT booking_release_days
      FROM public.sports_venues WHERE id = v_venue)
      = ARRAY[1,3]::SMALLINT[],
    'venue setter persists a selected multi-day schedule');
  PERFORM public.set_sports_venue_booking_release(
    v_owner, v_venue, 2, '09:00', 7);
  PERFORM pg_temp.expect((SELECT booking_release_days
      FROM public.sports_venues WHERE id = v_venue)
      = ARRAY[2]::SMALLINT[],
    'legacy venue setter still writes a single-day schedule');

  v_court := public.upsert_sports_venue_court_with_release_days(
    p_user_id => v_owner,
    p_court_id => NULL,
    p_venue_id => v_venue,
    p_sport_id => v_sport,
    p_name => 'Daily release resource',
    p_price_amount => 100,
    p_pricing_unit => 'hour',
    p_court_type => 'synthetic',
    p_indoor => true,
    p_booking_approval_mode => 'instant',
    p_booking_release_mode => 'custom',
    p_booking_release_time => '09:00',
    p_booking_release_window_days => 1,
    p_booking_release_days => '[0,1,2,3,4,5,6]'::JSONB);
  PERFORM pg_temp.expect((SELECT booking_release_days
      FROM public.sports_venue_courts WHERE id = v_court)
      = ARRAY[0,1,2,3,4,5,6]::SMALLINT[]
    AND (SELECT booking_release_window_days
      FROM public.sports_venue_courts WHERE id = v_court) = 1,
    'court override supports every day with a one-day window');
  PERFORM pg_temp.expect_raise(
    'court rejects a window below the selected-day gap',
    format($s$SELECT public.upsert_sports_venue_court_with_release_days(
      p_user_id => %L, p_court_id => %L, p_venue_id => %L,
      p_sport_id => %L, p_name => 'Invalid multi-day rule',
      p_booking_release_mode => 'custom', p_booking_release_time => '09:00',
      p_booking_release_window_days => 4,
      p_booking_release_days => '[1,3]'::JSONB)$s$,
      v_owner, v_court, v_venue, v_sport),
    'INVALID_RELEASE_RULE');
  PERFORM public.upsert_sports_venue_court_with_release_days(
    p_user_id => v_owner,
    p_court_id => v_court,
    p_venue_id => v_venue,
    p_sport_id => v_sport,
    p_name => 'Multi-day release resource',
    p_price_amount => 100,
    p_pricing_unit => 'hour',
    p_court_type => 'synthetic',
    p_indoor => true,
    p_booking_approval_mode => 'instant',
    p_booking_release_mode => 'custom',
    p_booking_release_time => '09:00',
    p_booking_release_window_days => 5,
    p_booking_release_days => '[3,1]'::JSONB);
  PERFORM pg_temp.expect((SELECT booking_release_days
      FROM public.sports_venue_courts WHERE id = v_court)
      = ARRAY[1,3]::SMALLINT[]
    AND (SELECT booking_release_window_days
      FROM public.sports_venue_courts WHERE id = v_court) = 5,
    'court override supports selected weekdays and canonical order');
  PERFORM public.upsert_sports_venue_court_with_release_days(
    p_user_id => v_owner,
    p_court_id => v_court,
    p_venue_id => v_venue,
    p_sport_id => v_sport,
    p_name => 'Daily release resource',
    p_price_amount => 100,
    p_pricing_unit => 'hour',
    p_court_type => 'synthetic',
    p_indoor => true,
    p_booking_approval_mode => 'instant',
    p_booking_release_mode => 'custom',
    p_booking_release_time => '09:00',
    p_booking_release_window_days => 1,
    p_booking_release_days => '[0,1,2,3,4,5,6]'::JSONB);

  v_availability := public.get_court_availability(
    v_court, now(), now() + INTERVAL '3 days');
  PERFORM pg_temp.expect(
    v_availability->'release'->'daysOfWeek' = '[0,1,2,3,4,5,6]'::JSONB,
    'availability echoes selected release weekdays');
  PERFORM pg_temp.expect(
    jsonb_array_length(v_availability->'notOpen') > 0
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_availability->'notOpen') AS e(value)
      WHERE (e.value->>'opensAt')::TIMESTAMPTZ <>
        public.sports_venue_booking_release_opens_at_for_days(
          'Asia/Bangkok', ARRAY[0,1,2,3,4,5,6]::SMALLINT[],
          '09:00', 1, (e.value->>'slotStart')::TIMESTAMPTZ)),
    'availability opensAt uses the shared multi-day helper');
  PERFORM pg_temp.expect_raise(
    'daily court rule gates unreleased future slots',
    format($s$SELECT public.assert_sports_venue_booking_release(
      %L, now() + INTERVAL '20 days', now() + INTERVAL '21 days')$s$,
      v_court),
    'BOOKING_NOT_OPEN_YET');

  PERFORM public.upsert_sports_venue_court(
    v_owner, v_court, v_venue, v_sport, 'Legacy single-day resource',
    1, 100, 'hour', 'synthetic', true, 'instant', NULL, true, NULL,
    'custom', 2, '09:00', 7, 'inherit', NULL);
  PERFORM pg_temp.expect((SELECT booking_release_days
      FROM public.sports_venue_courts WHERE id = v_court)
      = ARRAY[2]::SMALLINT[],
    'legacy court upsert replaces multi-day schedule with one weekday');
  PERFORM public.upsert_sports_venue_court(
    v_owner, v_court, v_venue, v_sport, 'Always-open resource',
    1, 100, 'hour', 'synthetic', true, 'instant', NULL, true, NULL,
    'always_open', NULL, NULL, NULL, 'inherit', NULL);
  PERFORM pg_temp.expect((SELECT booking_release_mode
      FROM public.sports_venue_courts WHERE id = v_court) = 'always_open'
    AND (SELECT booking_release_days IS NULL
      FROM public.sports_venue_courts WHERE id = v_court),
    'legacy court upsert clears selected days for always_open');
  PERFORM public.upsert_sports_venue_court(
    v_owner, v_court, v_venue, v_sport, 'Inherited resource',
    1, 100, 'hour', 'synthetic', true, 'instant', NULL, true, NULL,
    'inherit', NULL, NULL, NULL, 'inherit', NULL);
  PERFORM pg_temp.expect((SELECT booking_release_mode
      FROM public.sports_venue_courts WHERE id = v_court) = 'inherit'
    AND (SELECT booking_release_days IS NULL
      FROM public.sports_venue_courts WHERE id = v_court),
    'legacy court upsert clears selected days for inherit');

  PERFORM public.set_sports_venue_booking_release_days(
    v_owner, v_venue, '[1,2,3,4,5]'::JSONB, '09:00', 7);
  PERFORM public.upsert_sports_venue_court_with_release_days(
    p_user_id => v_owner,
    p_court_id => v_court,
    p_venue_id => v_venue,
    p_sport_id => v_sport,
    p_name => 'Weekday venue schedule with Saturday override',
    p_price_amount => 100,
    p_pricing_unit => 'hour',
    p_court_type => 'synthetic',
    p_indoor => true,
    p_booking_approval_mode => 'instant',
    p_booking_release_mode => 'custom',
    p_booking_release_time => '10:00',
    p_booking_release_window_days => 7,
    p_booking_release_days => '[6]'::JSONB);
  PERFORM pg_temp.expect(to_char(
      public.sports_venue_booking_release_opens_at_for_slot(
        'Asia/Bangkok', 'custom', ARRAY[6]::SMALLINT[], '10:00', 7,
        ARRAY[1,2,3,4,5]::SMALLINT[], '09:00', 7,
        '2026-10-05 12:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok'
      ) AT TIME ZONE 'Asia/Bangkok', 'HH24:MI') = '09:00',
    'normal weekdays use the venue release time');
  PERFORM pg_temp.expect(to_char(
      public.sports_venue_booking_release_opens_at_for_slot(
        'Asia/Bangkok', 'custom', ARRAY[6]::SMALLINT[], '10:00', 7,
        ARRAY[1,2,3,4,5]::SMALLINT[], '09:00', 7,
        '2026-10-10 12:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok'
      ) AT TIME ZONE 'Asia/Bangkok', 'HH24:MI') = '10:00',
    'court custom weekday uses the court release time');
  PERFORM pg_temp.expect(to_char(
      public.sports_venue_booking_release_opens_at_for_slot(
        'Asia/Bangkok', 'custom', ARRAY[6]::SMALLINT[], '10:00', 7,
        ARRAY[1,2,3,4,5]::SMALLINT[], '09:00', 7,
        '2026-10-11 12:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok'
      ) AT TIME ZONE 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI') = '2026-10-05 09:00',
    'venue rule covers a weekday outside the court custom days');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_opens_at_for_slot(
      'Asia/Bangkok', 'custom', ARRAY[6]::SMALLINT[], '10:00', 7,
      NULL::SMALLINT[], '09:00', 7,
      '2026-10-11 12:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok'
    ) IS NULL,
    'weekday without any venue or court rule has no release gate');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_next_at(
      'Asia/Bangkok', '2026-10-04 18:00'::TIMESTAMP
        AT TIME ZONE 'Asia/Bangkok',
      'custom', ARRAY[6]::SMALLINT[], '10:00',
      ARRAY[1,2,3,4,5]::SMALLINT[], '09:00')
      = '2026-10-05 09:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    'next release selects the nearest venue weekday and time');
  PERFORM pg_temp.expect(
    public.sports_venue_booking_release_next_at(
      'Asia/Bangkok', '2026-10-10 11:00'::TIMESTAMP
        AT TIME ZONE 'Asia/Bangkok',
      'custom', ARRAY[6]::SMALLINT[], '10:00',
      ARRAY[1,2,3,4,5]::SMALLINT[], '09:00')
      = '2026-10-12 09:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    'next release skips a passed court override and selects the venue rule');

  v_availability := public.get_court_availability(
    v_court,
    '2030-01-07 00:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    '2030-01-08 00:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok');
  PERFORM pg_temp.expect(
    left(v_availability->'release'->>'selectedDayReleaseTime', 5) = '09:00',
    'availability returns venue time for a normal booking weekday');
  PERFORM pg_temp.expect(
    to_char((v_availability->'release'->>'selectedDayOpensAt')::TIMESTAMPTZ
      AT TIME ZONE 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI') = '2030-01-01 09:00',
    'availability dates the release that governs the selected weekday');
  v_availability := public.get_court_availability(
    v_court,
    '2030-01-05 00:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    '2030-01-06 00:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok');
  PERFORM pg_temp.expect(
    left(v_availability->'release'->>'selectedDayReleaseTime', 5) = '10:00',
    'availability returns court time for its custom booking weekday');
  PERFORM pg_temp.expect(
    to_char((v_availability->'release'->>'selectedDayOpensAt')::TIMESTAMPTZ
      AT TIME ZONE 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI') = '2030-01-05 10:00',
    'court custom weekday opens on its own release date');
  v_availability := public.get_court_availability(
    v_court,
    '2030-01-06 00:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    '2030-01-07 00:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok');
  PERFORM pg_temp.expect(
    left(v_availability->'release'->>'selectedDayReleaseTime', 5) = '09:00'
    AND v_availability->>'nextReleaseAt' IS NOT NULL,
    'venue rule also covers a weekday outside every selected day set');
  PERFORM pg_temp.expect(
    to_char((v_availability->'release'->>'selectedDayOpensAt')::TIMESTAMPTZ
      AT TIME ZONE 'Asia/Bangkok', 'YYYY-MM-DD HH24:MI') = '2029-12-31 09:00',
    'the governing release may fall on an earlier date than the booking date');
  PERFORM pg_temp.expect_raise(
    'booking gate uses venue rule for a normal weekday',
    format($s$SELECT public.assert_sports_venue_booking_release(
      %L, '2030-01-07 10:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
      '2030-01-07 11:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok')$s$,
      v_court),
    'BOOKING_NOT_OPEN_YET');
  PERFORM pg_temp.expect_raise(
    'booking gate uses court rule on its custom weekday',
    format($s$SELECT public.assert_sports_venue_booking_release(
      %L, '2030-01-05 11:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
      '2030-01-05 12:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok')$s$,
      v_court),
    'BOOKING_NOT_OPEN_YET');
  PERFORM pg_temp.expect_raise(
    'booking gate also covers a weekday outside every selected day set',
    format($s$SELECT public.assert_sports_venue_booking_release(
      %L, '2030-01-06 10:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
      '2030-01-06 11:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok')$s$,
      v_court),
    'BOOKING_NOT_OPEN_YET');
  PERFORM public.upsert_sports_venue_court_with_release_days(
    p_user_id => v_owner,
    p_court_id => v_court,
    p_venue_id => v_venue,
    p_sport_id => v_sport,
    p_name => 'Custom-only schedule',
    p_price_amount => 100,
    p_pricing_unit => 'hour',
    p_court_type => 'synthetic',
    p_indoor => true,
    p_booking_approval_mode => 'instant',
    p_booking_release_mode => 'custom',
    p_booking_release_time => '10:00',
    p_booking_release_window_days => 7,
    p_booking_release_days => '[6]'::JSONB);
  PERFORM public.set_sports_venue_booking_release_days(
    v_owner, v_venue, NULL, NULL, NULL);
  PERFORM public.assert_sports_venue_booking_release(
    v_court,
    '2030-01-06 10:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok',
    '2030-01-06 11:00'::TIMESTAMP AT TIME ZONE 'Asia/Bangkok');
  PERFORM pg_temp.expect(true,
    'booking gate does not apply without any venue or court rule');
END $release_days$;
