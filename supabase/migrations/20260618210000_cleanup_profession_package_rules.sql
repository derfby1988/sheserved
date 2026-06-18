-- Cleanup: normalize and deduplicate profession_package_rules
-- Goal: make package rule persistence deterministic across older rows,
-- stale professor mappings, and any orphan data left behind by earlier saves.

BEGIN;

-- 1) Normalize any professor-linked rules to the canonical professor UUID.
--    This is safe even if the row already uses the canonical UUID.
UPDATE public.profession_package_rules ppr
SET profession_id = '00000000-0000-0000-0000-000000000107'
WHERE ppr.profession_id IN (
  SELECT p.id
  FROM public.professions p
  WHERE p.id = '00000000-0000-0000-0000-000000000107'
     OR p.profession_code = 'professor'
     OR lower(p.name) = 'อาจารย์แพทย์'
)
AND ppr.profession_id <> '00000000-0000-0000-0000-000000000107';

-- 2) Remove orphan rules that no longer point to a real profession row.
DELETE FROM public.profession_package_rules ppr
WHERE NOT EXISTS (
  SELECT 1
  FROM public.professions p
  WHERE p.id = ppr.profession_id
);

-- 3) Deduplicate any historical duplicates by keeping the newest row per
--    (package_id, profession_id) pair.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY package_id, profession_id
      ORDER BY updated_at DESC, created_at DESC, id DESC
    ) AS rn
  FROM public.profession_package_rules
)
DELETE FROM public.profession_package_rules ppr
USING ranked r
WHERE ppr.id = r.id
  AND r.rn > 1;

-- 4) Ask PostgREST to reload schema so the API sees the current table shape immediately.
NOTIFY pgrst, 'reload schema';

COMMIT;
