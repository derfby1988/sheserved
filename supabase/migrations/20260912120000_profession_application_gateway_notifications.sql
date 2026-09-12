-- Profession application notifications through the custom-auth gateway.
-- The gateway writes notifications and delivers the realtime WebSocket event.

ALTER TABLE public.app_notifications
  ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMPTZ;

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
        'health', 'admin'
      ));
  END IF;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END
$$;

CREATE INDEX IF NOT EXISTS idx_app_notifications_admin_recipient
  ON public.app_notifications(recipient_id, category, is_read, created_at DESC);

NOTIFY pgrst, 'reload schema';
