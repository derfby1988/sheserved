-- Fitness Buddies: drop visibility column
-- Date: 2026-08-13
--
-- Per updated plan: "ก๊วนส่วนตัว" is defined solely by requires_owner_approval.
-- All groups (including private ones) appear in the open list; the separate
-- visibility field is no longer used.

ALTER TABLE public.fitness_groups DROP COLUMN IF EXISTS visibility;

NOTIFY pgrst, 'reload schema';
