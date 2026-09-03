-- Migration: Phase 13.0 — Public data contract: Fitness browse views
-- Date: 2026-09-03
-- Depends: 20260803111500_fitness_buddies_schema.sql
--
-- Expose only columns safe for public/anon browse.  Private groups are hidden.
-- Aggregates for groups are intentionally non-identifying (counts only).

DROP VIEW IF EXISTS public.fitness_groups_public;
CREATE VIEW public.fitness_groups_public AS
SELECT
  g.id,
  g.sport_id,
  g.name,
  g.description,
  g.province,
  g.district,
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

CREATE OR REPLACE VIEW public.fitness_sessions_public AS
SELECT
  s.id,
  s.group_id,
  s.starts_at,
  s.ends_at,
  g.capacity,
  s.place_name,
  s.lat,
  s.lng,
  s.note,
  COALESCE(confirmed.count, 0) AS confirmed_count,
  GREATEST(g.capacity - COALESCE(confirmed.count, 0), 0) AS available_count
FROM public.fitness_group_sessions s
JOIN public.fitness_groups g ON g.id = s.group_id
LEFT JOIN LATERAL (
  SELECT COUNT(*) AS count
  FROM public.fitness_group_bookings b
  WHERE b.session_id = s.id
    AND b.status = 'confirmed'
) confirmed ON true
WHERE g.visibility = 'public';

-- Public/anonymous SELECT is allowed only through these views in Phase 13.0.
-- Revoke of base-table SELECT for anon happens in the 13.5 cutover migration.
GRANT SELECT ON public.fitness_groups_public TO anon, authenticated;
GRANT SELECT ON public.fitness_sessions_public TO anon, authenticated;
