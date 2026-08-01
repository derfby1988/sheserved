-- ============================================================
-- Migration: RLS Audit & Hardening (Plan 07 K2)
-- Date: 2026-07-28
-- Description: Enable RLS on tables missing it.
--              Uses USING(true) policies matching existing pattern
--              because the app uses custom AuthService (not Supabase Auth).
--              auth.uid() would return NULL and block all access.
--              Phase 2 tightening (auth.uid()-based policies) deferred
--              to Plan 09 when Supabase Auth native is adopted.
--              This migration is idempotent and can be re-run safely.
-- ============================================================

-- ============================================================
-- 1. TABLES MISSING RLS ENTIRELY
-- ============================================================

-- 1.1 chat_room_members — contains user IDs and read state
ALTER TABLE IF EXISTS public.chat_room_members ENABLE ROW LEVEL SECURITY;
-- NOTE: Using USING(true) because app uses custom AuthService, not Supabase Auth.
-- auth.uid() returns NULL without Supabase Auth session.
-- Access control is enforced at the Dart Repository layer via AuthService.instance.currentUser.
-- Phase 2: Replace with auth.uid()-based policies after Plan 09 adopts Supabase Auth.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'chat_room_members'
      AND policyname = 'chat_room_members_select'
  ) THEN
    CREATE POLICY chat_room_members_select ON public.chat_room_members
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'chat_room_members'
      AND policyname = 'chat_room_members_modify'
  ) THEN
    CREATE POLICY chat_room_members_modify ON public.chat_room_members
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 1.2 videos — contains user-generated video metadata
ALTER TABLE IF EXISTS public.videos ENABLE ROW LEVEL SECURITY;
-- NOTE: Using USING(true) because app uses custom AuthService, not Supabase Auth.
-- Access control is enforced at the Dart Repository layer.
-- Phase 2: Replace with owner-based policies after Plan 09 adopts Supabase Auth.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'videos'
      AND policyname = 'videos_select'
  ) THEN
    CREATE POLICY videos_select ON public.videos
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'videos'
      AND policyname = 'videos_modify'
  ) THEN
    CREATE POLICY videos_modify ON public.videos
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 1.3 video_gps_tracks — linked to videos, same owner
ALTER TABLE IF EXISTS public.video_gps_tracks ENABLE ROW LEVEL SECURITY;
-- NOTE: Using USING(true) — access control at application layer.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'video_gps_tracks'
      AND policyname = 'video_gps_tracks_select'
  ) THEN
    CREATE POLICY video_gps_tracks_select ON public.video_gps_tracks
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'video_gps_tracks'
      AND policyname = 'video_gps_tracks_modify'
  ) THEN
    CREATE POLICY video_gps_tracks_modify ON public.video_gps_tracks
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 1.4 video_interactions — user activity on videos
ALTER TABLE IF EXISTS public.video_interactions ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'video_interactions'
      AND policyname = 'video_interactions_select_all'
  ) THEN
    -- Interactions are public (likes, views, gifts are visible)
    CREATE POLICY video_interactions_select_all ON public.video_interactions
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- NOTE: Using USING(true) — access control at application layer.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'video_interactions'
      AND policyname = 'video_interactions_modify'
  ) THEN
    CREATE POLICY video_interactions_modify ON public.video_interactions
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 1.5 medications — master drug database (read-only for all)
ALTER TABLE IF EXISTS public.medications ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'medications'
      AND policyname = 'medications_select_all'
  ) THEN
    CREATE POLICY medications_select_all ON public.medications
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- 1.6 consultation_requests — already has RLS with USING(true) policies
-- No changes needed at this time; existing policies remain as-is.
-- Phase 2: Add owner-based policies after Plan 09 adopts Supabase Auth.

-- ============================================================
-- 2. TABLES WITH RLS BUT USING(true) — DOCUMENT FOR FUTURE TIGHTENING
-- ============================================================
-- The following tables have RLS enabled but use USING(true) policies.
-- They are controlled at the application layer (AuthService).
-- Future migration should replace these with auth.uid()-based policies
-- once Supabase Auth native is adopted (Plan 09).
--
-- Tables with USING(true) policies (not changed in this migration):
--   - chat_rooms (Dev access)
--   - chat_messages (Dev access)
--   - consultation_requests (Allow all)
--   - donation_categories (all)
--   - donation_requests (all)
--   - donation_contributions (all)
--   - communities (all)
--   - professions (all)
--   - checkout_sessions (all)
--   - payment_transactions (all)
--   - delivery_orders (all)
--   - inbox_events (all)
--   - transaction_contexts (all)
--   - organization_roles (all)
--   - role_module_permissions (all)
--   - employee_roles (all)
--   - organization_feature_flags (all)
--   - provider_profiles (all)
--   - provider_credentials (all)
--   - registration_application_attachments (all)
--   - drug_risk_overrides (all)
--   - drug_risk_override_history (all)
--   - incident_responses (all)
--   - employees (select all)
--
-- These are documented in the RLS audit report (docs/secure/rls_audit_report.md)
-- and will be tightened in a phased approach after staging environment is ready (K3).

-- ============================================================
-- 3. STORAGE BUCKETS — VERIFY POLICIES
-- ============================================================
-- Storage bucket policies are managed in Supabase Dashboard.
-- Audit checklist (to be verified manually):
--   - donations: public read, authenticated write
--   - avatars: owner read/write, public read
--   - video-thumbnails: owner read/write, public read
--   - consultation-attachments: participant-only read/write

-- ============================================================
-- 4. EDGE FUNCTIONS — VERIFY AUTHORIZATION
-- ============================================================
-- Edge functions that use service_role key must verify:
--   - Authorization header is validated
--   - Rate limiting is applied
--   - Input validation is performed
--   - No P2/P3 secrets are embedded in function code

-- ============================================================
-- End of migration
-- ============================================================
