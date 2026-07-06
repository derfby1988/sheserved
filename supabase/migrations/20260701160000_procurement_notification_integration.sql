-- Migration: Procurement Notification Integration (Priority 4)
-- Creates app_notifications table + trigger to consume procurement outbox events
-- and generate in-app notifications for managers/owners in the same profession.
-- Prerequisites: outbox_events, user_group_roles, professions, public.users

-- ============================================================
-- 1. CREATE app_notifications TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.app_notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    recipient_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category        TEXT NOT NULL DEFAULT 'procurement'
                        CHECK (category IN ('procurement','inventory','kpi','hr','system','donation','health')),
    event_type      TEXT NOT NULL,
    title           TEXT NOT NULL,
    body            TEXT,
    payload         JSONB NOT NULL DEFAULT '{}',
    is_read         BOOLEAN NOT NULL DEFAULT false,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_notif_recipient
    ON public.app_notifications(recipient_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_notif_profession
    ON public.app_notifications(profession_id, category, created_at DESC);

-- ============================================================
-- 2. RLS for app_notifications
-- ============================================================
ALTER TABLE public.app_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own notifications" ON public.app_notifications;
CREATE POLICY "Users can view own notifications"
    ON public.app_notifications FOR SELECT
    TO authenticated
    USING (recipient_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own notifications" ON public.app_notifications;
CREATE POLICY "Users can update own notifications"
    ON public.app_notifications FOR UPDATE
    TO authenticated
    USING (recipient_id = auth.uid())
    WITH CHECK (recipient_id = auth.uid());

-- ============================================================
-- 3. TRIGGER FUNCTION: Consume procurement outbox events → app_notifications
-- ============================================================
-- When a procurement outbox event is inserted, create notifications
-- for admin/provider users in the same profession (fallback: all users in profession).
CREATE OR REPLACE FUNCTION public.on_procurement_outbox_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_recipient   RECORD;
    v_title       TEXT;
    v_body        TEXT;
    v_category    TEXT := 'procurement';
    v_notif_count INTEGER := 0;
BEGIN
    -- Only process procurement-related outbox events
    IF NEW.aggregate_type NOT IN ('procurement_pr','procurement_po','procurement_gr','back_order','reorder_suggestion','supplier_invoice') THEN
        RETURN NEW;
    END IF;

    -- Map event_type → title/body
    v_title := CASE NEW.event_type
        WHEN 'procurement.pr_approved'       THEN 'PR ได้รับการอนุมัติ'
        WHEN 'procurement.pr_rejected'       THEN 'PR ถูกปฏิเสธ'
        WHEN 'procurement.pr_converted_to_po' THEN 'PR แปลงเป็น PO แล้ว'
        WHEN 'procurement.po_sent'           THEN 'PO ส่งซัพพลายเออร์แล้ว'
        WHEN 'procurement.goods_receipted'   THEN 'รับสินค้าเข้าคลังแล้ว'
        WHEN 'procurement.po_fully_received' THEN 'รับสินค้าครบแล้ว'
        WHEN 'procurement.back_order_created'  THEN 'มี Back Order ใหม่'
        WHEN 'procurement.back_order_fulfilled' THEN 'Back Order สำเร็จแล้ว'
        WHEN 'procurement.reorder_suggestion_created' THEN 'มีรายการแนะนำการสั่งซื้อใหม่'
        WHEN 'procurement.supplier_invoice_created'  THEN 'มีใบกำกับภาษีซื้อใหม่'
        WHEN 'procurement.invoice_matched'           THEN 'ใบกำกับภาษีตรงสองสามทางแล้ว'
        WHEN 'procurement.invoice_mismatch'          THEN 'ใบกำกับภาษีไม่ตรง (3-Way Mismatch)'
        WHEN 'procurement.invoice_status_changed'    THEN 'สถานะใบกำกับภาษีเปลี่ยนแปลง'
        ELSE NULL
    END;

    IF v_title IS NULL THEN
        RETURN NEW;
    END IF;

    v_body := COALESCE(
        NEW.payload->>'pr_number',
        NEW.payload->>'po_number',
        NEW.payload->>'gr_number',
        NEW.payload->>'product_name',
        NEW.payload->>'invoice_number',
        ''
    );

    -- Find recipients: users in the same profession with admin/provider role
    -- Fallback: if none found, notify all users in that profession
    v_notif_count := 0;

    FOR v_recipient IN
        SELECT DISTINCT u.id
        FROM public.users u
        WHERE u.profession_id = NEW.profession_id
          AND u.role IN ('admin', 'provider')
    LOOP
        BEGIN
            INSERT INTO public.app_notifications (
                profession_id, recipient_id, category, event_type,
                title, body, payload
            )
            VALUES (
                NEW.profession_id, v_recipient.id, v_category, NEW.event_type,
                v_title,
                CASE WHEN v_body != '' THEN v_title || ' — ' || v_body ELSE v_title END,
                NEW.payload
            );
            v_notif_count := v_notif_count + 1;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;

    -- Fallback: if no admin/provider found, notify all users in the profession
    IF v_notif_count = 0 THEN
        FOR v_recipient IN
            SELECT DISTINCT u.id
            FROM public.users u
            WHERE u.profession_id = NEW.profession_id
        LOOP
            BEGIN
                INSERT INTO public.app_notifications (
                    profession_id, recipient_id, category, event_type,
                    title, body, payload
                )
                VALUES (
                    NEW.profession_id, v_recipient.id, v_category, NEW.event_type,
                    v_title,
                    CASE WHEN v_body != '' THEN v_title || ' — ' || v_body ELSE v_title END,
                    NEW.payload
                );
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 4. TRIGGER: Attach to outbox_events
-- ============================================================
DROP TRIGGER IF EXISTS trg_procurement_outbox_notify ON public.outbox_events;
CREATE TRIGGER trg_procurement_outbox_notify
    AFTER INSERT ON public.outbox_events
    FOR EACH ROW
    WHEN (NEW.aggregate_type IN ('procurement_pr','procurement_po','procurement_gr','back_order','reorder_suggestion','supplier_invoice'))
    EXECUTE FUNCTION public.on_procurement_outbox_insert();

-- ============================================================
-- 5. RPC: Mark notification as read
-- ============================================================
CREATE OR REPLACE FUNCTION public.mark_notification_read(
    p_notification_id UUID,
    p_user_id         UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.app_notifications
    SET is_read = true, read_at = NOW()
    WHERE id = p_notification_id AND recipient_id = p_user_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. RPC: Mark all notifications as read for a user
-- ============================================================
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(
    p_user_id         UUID,
    p_category        TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE public.app_notifications
    SET is_read = true, read_at = NOW()
    WHERE recipient_id = p_user_id
      AND is_read = false
      AND (p_category IS NULL OR category = p_category);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 7. RPC: Get unread notification count
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_unread_notification_count(
    p_user_id    UUID,
    p_category   TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.app_notifications
    WHERE recipient_id = p_user_id
      AND is_read = false
      AND (p_category IS NULL OR category = p_category);

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
