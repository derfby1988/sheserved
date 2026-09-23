-- Notify the proposer when an admin approves or rejects a sport proposal.
-- The existing app_notifications table is the durable notification channel;
-- Supabase Realtime on `sports` is used by the legacy client for an immediate
-- badge update without introducing another paid delivery service.

CREATE OR REPLACE FUNCTION public.notify_sport_proposal_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title TEXT;
  v_body  TEXT;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status
     OR OLD.status IS DISTINCT FROM 'pending'
     OR NEW.status NOT IN ('approved', 'rejected')
     OR NEW.proposed_by IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'approved' THEN
    v_title := 'คำขอเพิ่มประเภทกีฬาได้รับการอนุมัติ';
    v_body := FORMAT('ประเภทกีฬา "%s" พร้อมใช้งานแล้ว', NEW.name_th);
  ELSE
    v_title := 'คำขอเพิ่มประเภทกีฬาถูกปฏิเสธ';
    v_body := FORMAT(
      'เหตุผล: %s',
      COALESCE(NULLIF(NEW.rejection_reason, ''), 'ไม่ระบุ')
    );
  END IF;

  BEGIN
    INSERT INTO public.app_notifications (
      recipient_id,
      category,
      event_type,
      title,
      body,
      payload
    ) VALUES (
      NEW.proposed_by,
      'sport',
      CASE
        WHEN NEW.status = 'approved' THEN 'sport.proposal_approved'
        ELSE 'sport.proposal_rejected'
      END,
      v_title,
      v_body,
      JSONB_BUILD_OBJECT(
        'route', '/community/sport-club',
        'sportId', NEW.id,
        'sportName', NEW.name_th,
        'status', NEW.status,
        'rejectionReason', NEW.rejection_reason
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_sport_proposal_review failed: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_sport_proposal_review ON public.sports;
CREATE TRIGGER trg_notify_sport_proposal_review
  AFTER UPDATE OF status ON public.sports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_sport_proposal_review();

NOTIFY pgrst, 'reload schema';
