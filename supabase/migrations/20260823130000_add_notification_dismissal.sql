ALTER TABLE public.app_notifications
  ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_app_notifications_recipient_dismissed
  ON public.app_notifications(recipient_id, dismissed_at, created_at DESC);

CREATE OR REPLACE FUNCTION public.dismiss_notification(
    p_notification_id UUID,
    p_user_id         UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
        RETURN FALSE;
    END IF;

    UPDATE public.app_notifications
    SET is_read = true,
        read_at = COALESCE(read_at, NOW()),
        dismissed_at = NOW()
    WHERE id = p_notification_id
      AND recipient_id = p_user_id
      AND dismissed_at IS NULL;

    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(
    p_user_id   UUID,
    p_category  TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
        RETURN 0;
    END IF;

    UPDATE public.app_notifications
    SET is_read = true,
        read_at = NOW()
    WHERE recipient_id = p_user_id
      AND is_read = false
      AND dismissed_at IS NULL
      AND (p_category IS NULL OR category = p_category);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_unread_notification_count(
    p_user_id   UUID,
    p_category  TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.app_notifications
    WHERE recipient_id = p_user_id
      AND is_read = false
      AND dismissed_at IS NULL
      AND (p_category IS NULL OR category = p_category);

    RETURN v_count;
END;
$$;
