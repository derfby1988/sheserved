-- Sport-type proposal notifications without the gateway (Supabase-only).
--
-- The proposal row itself is the single source of truth: whichever path writes
-- it (legacy direct Supabase insert or the gateway route) the trigger below
-- fans the request out to every active admin, and public.sports is published
-- through Supabase Realtime so the admin app can raise the toast card by
-- itself — no websocket-server required.
--
-- Prerequisite: 20260921130000_sport_proposal_notifications.sql must run first
-- (nullable profession_id + the 'sport' category).

-- ============================================================
-- 1) Fan out a pending proposal to every active admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_admins_of_sport_proposal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_proposer TEXT;
  v_body     TEXT;
  v_admin    RECORD;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  -- A failed notification must never roll back the proposal the user just
  -- submitted, so the fan-out is isolated in its own block.
  BEGIN
    SELECT NULLIF(
             TRIM(CONCAT_WS(' ', NULLIF(u.first_name, ''), NULLIF(u.last_name, ''))),
             ''
           )
      INTO v_proposer
      FROM public.users u
     WHERE u.id = NEW.proposed_by;

    v_body := CASE
      WHEN v_proposer IS NULL THEN FORMAT('มีผู้เสนอประเภทกีฬา "%s"', NEW.name_th)
      ELSE FORMAT('%s เสนอประเภทกีฬา "%s"', v_proposer, NEW.name_th)
    END;

    FOR v_admin IN
      SELECT id FROM public.users WHERE role = 'admin' AND is_active = true
    LOOP
      INSERT INTO public.app_notifications (
        recipient_id, category, event_type, title, body, payload
      ) VALUES (
        v_admin.id,
        'sport',
        'sport.proposal_submitted',
        'มีคำขอเพิ่มประเภทกีฬาใหม่',
        v_body,
        JSONB_BUILD_OBJECT(
          'sportId',    NEW.id,
          'sportName',  NEW.name_th,
          'proposedBy', NEW.proposed_by,
          'route',      '/community/sport-club/sport/review'
        )
      );
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_admins_of_sport_proposal failed: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admins_of_sport_proposal ON public.sports;
CREATE TRIGGER trg_notify_admins_of_sport_proposal
  AFTER INSERT ON public.sports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admins_of_sport_proposal();

CREATE INDEX IF NOT EXISTS idx_sports_pending_proposed_at
  ON public.sports(status, proposed_at DESC);

-- ============================================================
-- 2) Publish proposals so the admin app receives them over Realtime
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'sports'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sports;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
