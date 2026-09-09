-- Migration: Phase 14.3 — Expand fitness_groups address fields
-- Date: 2026-09-08
-- Depends: 20260903110900_phase_13_0_fitness_public_views.sql

-- Add subdistrict and postal_code to fitness_groups
ALTER TABLE public.fitness_groups
  ADD COLUMN IF NOT EXISTS subdistrict TEXT,
  ADD COLUMN IF NOT EXISTS postal_code VARCHAR(5);

-- Update the public browse view to include the new address columns
DROP VIEW IF EXISTS public.fitness_groups_public;

CREATE VIEW public.fitness_groups_public AS
SELECT
  g.id,
  g.sport_id,
  g.name,
  g.description,
  g.province,
  g.district,
  g.subdistrict,
  g.postal_code,
  g.lat,
  g.lng,
  g.gender_preference,
  g.requires_owner_approval,
  g.capacity,
  g.cover_image_url,
  g.venue_photo_url,
  g.created_at,
  (
    SELECT COUNT(*)
    FROM public.fitness_group_sessions s
    WHERE s.group_id = g.id
      AND s.starts_at > now()
  ) AS upcoming_sessions_count,
  (
    SELECT COUNT(*)
    FROM public.fitness_group_sessions s
    JOIN public.fitness_group_bookings b ON b.session_id = s.id
    WHERE s.group_id = g.id
      AND s.starts_at > now()
      AND b.status = 'confirmed'
  ) AS upcoming_confirmed_count,
  (
    SELECT COUNT(*)
    FROM public.fitness_group_sessions s
    JOIN public.fitness_group_bookings b ON b.session_id = s.id
    WHERE s.group_id = g.id
      AND s.starts_at > now()
      AND b.status = 'pending'
  ) AS upcoming_pending_count
FROM public.fitness_groups g
WHERE g.visibility = 'public';

GRANT SELECT ON public.fitness_groups_public TO anon, authenticated;
