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

-- ---------------------------------------------------------------------
-- Prerequisite stubs (skipped automatically on a real Supabase database)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_en text, name_th text, status text DEFAULT 'approved'
);
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
--   for f in supabase/migrations/20260924*sports_hub*.sql; do
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
  v_app uuid; v_venue uuid; v_venue2 uuid; v_court uuid; v_terms int;
  v_b1 uuid; v_b2 uuid; v_b3 uuid; v_b4 uuid; v_review uuid;
  v_missing text[];
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

  PERFORM public.review_sports_venue(
    v_admin, v_venue2, 'suspended', 'ผิดนัดตรวจ');
  PERFORM pg_temp.expect_raise('suspended venue cannot resubmit',
    format('SELECT public.submit_sports_venue_for_review(%L, %L)',
           v_owner, v_venue2));
  PERFORM pg_temp.expect_raise('reject without reason rejected',
    format($s$SELECT public.review_sports_venue(%L, %L, 'rejected')$s$,
      v_admin, v_venue));

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
