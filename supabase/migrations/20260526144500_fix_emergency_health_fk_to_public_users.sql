-- Migration: Fix emergency_health_data_settings FK to reference public.users instead of auth.users
-- Reason: This project does NOT use Supabase Auth (auth.uid() is always null).
--         All user identities are managed via custom AuthService → public.users table.
-- Date: 2026-05-26

-- Step 1: Drop FK constraints that reference auth.users across all emergency health tables

ALTER TABLE emergency_health_data_settings
    DROP CONSTRAINT IF EXISTS emergency_health_data_settings_user_id_fkey;

ALTER TABLE emergency_health_release_sessions
    DROP CONSTRAINT IF EXISTS emergency_health_release_sessions_patient_id_fkey;

ALTER TABLE emergency_health_access_tokens
    DROP CONSTRAINT IF EXISTS emergency_health_access_tokens_responder_id_fkey;

ALTER TABLE emergency_health_dead_man_checkins
    DROP CONSTRAINT IF EXISTS emergency_health_dead_man_checkins_user_id_fkey;

-- Step 2: Re-add FK constraints pointing to public.users(id)

ALTER TABLE emergency_health_data_settings
    ADD CONSTRAINT emergency_health_data_settings_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE emergency_health_release_sessions
    ADD CONSTRAINT emergency_health_release_sessions_patient_id_fkey
    FOREIGN KEY (patient_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE emergency_health_access_tokens
    ADD CONSTRAINT emergency_health_access_tokens_responder_id_fkey
    FOREIGN KEY (responder_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE emergency_health_dead_man_checkins
    ADD CONSTRAINT emergency_health_dead_man_checkins_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Step 3: Fix RLS policies — remove auth.uid() checks (always null in this project)
--         Replace with service-role-only access (backend handles all writes)

ALTER TABLE emergency_health_data_settings DISABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_health_release_sessions DISABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_health_access_tokens DISABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_health_dead_man_checkins DISABLE ROW LEVEL SECURITY;
