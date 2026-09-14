-- Migration: Phase 15.6 extension — Field style customization per sport
-- Date: 2026-09-14
-- Depends: 20260914120000_fitness_buddies_positions.sql
--
-- Adds sports.field_style (JSONB) so admins can pick a line-marking preset
-- plus custom surface/line colors per sport. NULL = default generic grass.
--
-- Shape: {"preset": "generic|football|badminton|basketball|volleyball|tennis",
--         "surface": "#RRGGBB", "line": "#RRGGBB"}

ALTER TABLE public.sports
  ADD COLUMN IF NOT EXISTS field_style JSONB NULL;

COMMENT ON COLUMN public.sports.field_style IS
  'Field appearance config: {"preset": "generic|football|badminton|basketball|volleyball|tennis", "surface": "#RRGGBB", "line": "#RRGGBB"}. NULL = default (grass + white lines).';

-- Guard against malformed payloads: allow NULL or object with whitelisted keys
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sports_field_style_check'
      AND conrelid = 'public.sports'::regclass
  ) THEN
    ALTER TABLE public.sports
      ADD CONSTRAINT sports_field_style_check
      CHECK (
        field_style IS NULL
        OR (
          jsonb_typeof(field_style) = 'object'
          AND (field_style->>'preset' IS NULL
               OR field_style->>'preset' IN ('generic','football','badminton','basketball','volleyball','tennis'))
          AND (field_style->>'surface' IS NULL
               OR field_style->>'surface' ~* '^#[0-9a-f]{6}$')
          AND (field_style->>'line' IS NULL
               OR field_style->>'line' ~* '^#[0-9a-f]{6}$')
        )
      );
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
