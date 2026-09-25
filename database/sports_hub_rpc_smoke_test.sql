-- Sports Hub RPC smoke test (Phase 21.7.10 release hardening).
--
-- Verifies the venue/coach booking contracts end-to-end on Postgres:
-- owner onboarding + admin authorization, approved-only public visibility,
-- atomic overlap rejection, idempotency keys, terms-version snapshotting,
-- booking/request lifecycle (pending -> confirmed -> completed), review
-- gating (completed-only, one review per booking) and durable
-- app_notifications rows.
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
\ir ../supabase/migrations/20260925100000_sports_hub_owner_contact_fix.sql
\ir ../supabase/migrations/20260925110000_sports_hub_notification_delivery.sql

CREATE OR REPLACE FUNCTION pg_temp.expect(cond boolean, label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF cond THEN RAISE NOTICE 'PASS: %', label;
  ELSE RAISE WARNING 'FAIL: %', label; END IF;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.expect_raise(label text, sql text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE sql;
  RAISE WARNING 'FAIL: % (no error raised)', label;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PASS: % (%)', label, SQLERRM;
END $$;

DO $smoke$
DECLARE
  v_admin uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_owner uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  v_cust  uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_cust2 uuid := 'dddddddd-0000-0000-0000-000000000004';
  v_sport uuid := 'eeeeeeee-0000-0000-0000-000000000005';
  v_mail  uuid := 'ffffffff-0000-0000-0000-000000000006';
  v_app uuid; v_venue uuid; v_court uuid; v_terms int;
  v_b1 uuid; v_b2 uuid; v_review uuid;
BEGIN
  INSERT INTO public.users (id, first_name, last_name, role) VALUES
    (v_admin,'Admin','A','admin'), (v_owner,'Owner','O','user'),
    (v_cust,'Cust','C','user'), (v_cust2,'Cust2','C2','user'),
    (v_mail,'Mail','M','user');
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

  -- supply: venue + court + terms
  v_venue := public.upsert_sports_venue(
    v_owner, NULL, 'Test Arena', NULL, 'Bangkok', 'Chatuchak',
    'addr', 13.8, 100.5, 'Asia/Bangkok');
  PERFORM public.review_sports_venue(v_admin, v_venue, 'approved');
  PERFORM pg_temp.expect(EXISTS(
    SELECT 1 FROM public.sports_venues_public WHERE id = v_venue),
    'approved venue appears in public view');

  PERFORM public.set_sports_venue_sports(v_owner, v_venue,
    jsonb_build_array(jsonb_build_object(
      'sport_id', v_sport, 'unit_label_override', 'คอร์ท')));
  v_court := public.upsert_sports_venue_court(
    v_owner, NULL, v_venue, v_sport, 'Court 1',
    1, 200, 'hour', 'synthetic', true, 'instant', NULL, true);
  v_terms := public.publish_sports_venue_terms(v_owner, v_venue, 'No smoking', 60);
  PERFORM pg_temp.expect(v_terms = 1, 'terms v1 published');

  -- 21.7.5 instant booking + atomicity
  v_b1 := public.create_sports_venue_booking(
    v_cust, v_court, now() + interval '2 days',
    now() + interval '2 days 1 hour', v_terms, 'idem-1');
  PERFORM pg_temp.expect((SELECT status FROM public.sports_venue_bookings
    WHERE id = v_b1) = 'confirmed', 'instant booking confirmed');
  PERFORM pg_temp.expect((SELECT accepted_terms_version FROM public.sports_venue_bookings
    WHERE id = v_b1) = v_terms, 'terms version snapshotted');

  PERFORM pg_temp.expect_raise('overlapping booking rejected',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      now() + interval '2 days 30 minutes',
      now() + interval '2 days 2 hours', %s, 'idem-2')$$,
      v_cust2, v_court, v_terms));

  PERFORM pg_temp.expect(public.create_sports_venue_booking(
    v_cust, v_court, now() + interval '2 days',
    now() + interval '2 days 1 hour', v_terms, 'idem-1') = v_b1,
    'idempotent retry returns same booking id');

  PERFORM pg_temp.expect_raise('stale terms version rejected',
    format($$SELECT public.create_sports_venue_booking(%L, %L,
      now() + interval '4 days', now() + interval '4 days 1 hour',
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

  -- 21.7.6 owner-approval flow
  SELECT public.upsert_sports_venue_court(
    v_owner, NULL, v_venue, v_sport, 'Court 2',
    1, 300, 'hour', 'grass', false, 'owner_approval', NULL, true) INTO v_court;
  v_b2 := public.create_sports_venue_booking(
    v_cust2, v_court, now() + interval '3 days',
    now() + interval '3 days 1 hour', v_terms, 'idem-4');
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
    500, 'both');
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
