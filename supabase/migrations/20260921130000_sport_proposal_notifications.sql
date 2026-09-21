-- Sport-type proposal notifications for Sheserved admins.
--
-- The custom-auth gateway (websocket-server) writes the notification rows and
-- delivers the realtime WebSocket event, mirroring the profession-application
-- flow. This migration only prepares the storage contract:
--   1. notifications may target admins without a profession context
--   2. 'sport' becomes a valid notification category
--   3. an index that keeps the admin inbox query fast

-- 1) A sport proposal has no profession, so profession_id must be optional.
ALTER TABLE public.app_notifications
  ALTER COLUMN profession_id DROP NOT NULL;

-- 2) Allow the new 'sport' category alongside the existing ones.
DO $$
BEGIN
  ALTER TABLE public.app_notifications
    DROP CONSTRAINT IF EXISTS app_notifications_category_check;
EXCEPTION WHEN undefined_table THEN
  NULL;
END
$$;

DO $$
BEGIN
  IF to_regclass('public.app_notifications') IS NOT NULL THEN
    ALTER TABLE public.app_notifications
      ADD CONSTRAINT app_notifications_category_check
      CHECK (category IN (
        'procurement', 'inventory', 'kpi', 'hr', 'system', 'donation',
        'health', 'admin', 'sport'
      ));
  END IF;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END
$$;

CREATE INDEX IF NOT EXISTS idx_app_notifications_recipient_category
  ON public.app_notifications(recipient_id, category, is_read, created_at DESC);

NOTIFY pgrst, 'reload schema';
