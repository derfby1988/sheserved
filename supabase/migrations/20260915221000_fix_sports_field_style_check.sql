-- Migration: 20260915221000_fix_sports_field_style_check.sql
-- Description: Expand sports_field_style_check to allow all sports presets in the app

ALTER TABLE public.sports
  DROP CONSTRAINT IF EXISTS sports_field_style_check;

ALTER TABLE public.sports
  ADD CONSTRAINT sports_field_style_check
  CHECK (
    field_style IS NULL
    OR (
      jsonb_typeof(field_style) = 'object'
      AND (
        field_style->>'preset' IS NULL
        OR field_style->>'preset' ~* '^[a-z0-9_]{2,50}$'
      )
      AND (
        field_style->>'surface' IS NULL
        OR field_style->>'surface' ~* '^#[0-9a-f]{6}$'
      )
      AND (
        field_style->>'line' IS NULL
        OR field_style->>'line' ~* '^#[0-9a-f]{6}$'
      )
    )
  );

COMMENT ON CONSTRAINT sports_field_style_check ON public.sports IS
  'Ensures field_style is valid JSON object with safe preset identifier and hex colors';

NOTIFY pgrst, 'reload schema';
