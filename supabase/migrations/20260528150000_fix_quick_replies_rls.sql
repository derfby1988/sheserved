-- Migration: Fix RLS and constraints for doctor_quick_replies
-- Problem: 
--   1. App uses custom AuthService (not Supabase Auth), so auth.uid() is always null.
--      All client-side queries are anonymous (role anon), which violates "TO authenticated" RLS policies.
--   2. The doctor_quick_replies schema has "title TEXT NOT NULL", but the Flutter app only
--      manages "content" and does not supply a "title" when saving, causing NOT NULL constraint violations.
-- Solution:
--   1. Disable Row Level Security (RLS) entirely for doctor_quick_replies, matching the approach
--      used for emergency health tables in 20260526144500_fix_emergency_health_fk_to_public_users.sql.
--   2. Drop the NOT NULL constraint on the title column so insertions succeed without a title.
-- Date: 2026-05-28

-- 1. Disable Row Level Security on doctor_quick_replies
ALTER TABLE doctor_quick_replies DISABLE ROW LEVEL SECURITY;

-- 2. Drop the NOT NULL constraint on the title column
ALTER TABLE doctor_quick_replies ALTER COLUMN title DROP NOT NULL;

