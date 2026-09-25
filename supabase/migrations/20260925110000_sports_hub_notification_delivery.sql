-- Sports Hub notification delivery hotfix
-- =======================================
-- Context: on environments where 20260921130000_sport_proposal_notifications.sql
-- was skipped, app_notifications.profession_id is still NOT NULL, so every
-- sports_hub_notify INSERT raised 23502 and was silently swallowed by the
-- guarded helper — the business transaction succeeded but no notification row
-- existed. Additionally the helper persisted rows without publishing any
-- realtime event, and custom-auth (legacy) clients could not read the rows
-- because NotificationRepository keyed off auth.currentUser instead of the
-- public.users id. This migration is idempotent and safe to re-run.

-- 1) Nullable profession_id (same change as 20260921130000 — harmless if that
--    migration is later applied on an environment where this ran first).
ALTER TABLE public.app_notifications
  ALTER COLUMN profession_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_app_notifications_recipient_category
  ON public.app_notifications(recipient_id, category, is_read, created_at DESC);

-- 2) Persist + publish. The inserted row is emitted on the
--    'sports_hub_notifications' channel so websocket-server can fan it out via
--    the existing application-notification socket event. pg_notify only fires
--    after COMMIT, so listeners never see rolled-back inserts. Delivery stays
--    guarded — a realtime failure must never abort the business transaction.
CREATE OR REPLACE FUNCTION public.sports_hub_notify(
  p_recipient_id UUID,
  p_category TEXT,
  p_event_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.app_notifications%ROWTYPE;
BEGIN
  IF p_recipient_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.app_notifications (
    recipient_id, category, event_type, title, body, payload
  ) VALUES (
    p_recipient_id, p_category, p_event_type, p_title, p_body,
    COALESCE(p_payload, '{}'::jsonb)
  )
  RETURNING * INTO v_row;

  PERFORM pg_notify('sports_hub_notifications', row_to_json(v_row)::text);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'sports_hub_notify failed: %', SQLERRM;
END;
$$;

-- 3) Custom-auth read path. The existing get_unread_notification_count /
--    mark_notification_read / dismiss_notification / mark_all_notifications_read
--    RPCs already take p_user_id (public.users.id) explicitly; this adds the
--    missing list counterpart so clients without a Supabase Auth session can
--    still render the notification panel.
CREATE OR REPLACE FUNCTION public.list_app_notifications(
  p_user_id UUID,
  p_category TEXT DEFAULT NULL,
  p_limit INT DEFAULT 50,
  p_unread_only BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.app_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT n.*
      FROM public.app_notifications n
     WHERE n.recipient_id = p_user_id
       AND n.dismissed_at IS NULL
       AND (p_category IS NULL OR n.category = p_category)
       AND (NOT p_unread_only OR n.is_read = FALSE)
     ORDER BY n.created_at DESC
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
END;
$$;

NOTIFY pgrst, 'reload schema';
