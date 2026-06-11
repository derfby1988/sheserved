-- Migration: ERP Phase 5 — Commerce Polish + Loyalty + Reports
-- Date: 2026-06-11
-- Prerequisites: Phase 4 complete (orders, customers, employees, KPI)

-- ============================================================
-- 1. POS REFUND REQUESTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.refund_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    order_number    TEXT NOT NULL,                          -- denormalized
    customer_id     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    requested_by    UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    amount          DECIMAL(12,2) NOT NULL,
    reason          TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'cancelled')),
    notes           TEXT,
    requested_at    TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refunds_profession
    ON public.refund_requests(profession_id, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_refunds_order
    ON public.refund_requests(order_id);
CREATE INDEX IF NOT EXISTS idx_refunds_customer
    ON public.refund_requests(customer_id, status);

DROP TRIGGER IF EXISTS trg_refunds_updated_at ON public.refund_requests;
CREATE TRIGGER trg_refunds_updated_at
    BEFORE UPDATE ON public.refund_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. CRM LOYALTY POINT RULES (auto-calculation config)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.loyalty_point_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    rule_name           TEXT NOT NULL DEFAULT 'Default Rule',
    points_per_baht     DECIMAL(10,4) NOT NULL DEFAULT 0.01,    -- 1 แต้มต่อ 100 บาท
    bonus_multiplier    DECIMAL(5,2) NOT NULL DEFAULT 1.0,      -- x2, x3 สำหรับโปรโมชั่น
    min_purchase        DECIMAL(12,2) DEFAULT 0,                  -- ยอดขั้นต่ำถึงจะได้แต้ม
    applies_to          TEXT DEFAULT 'all'
                            CHECK (applies_to IN ('all', 'products', 'services', 'consultation')),
    is_active           BOOLEAN DEFAULT true,
    valid_from          DATE DEFAULT CURRENT_DATE,
    valid_until         DATE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_rules_profession
    ON public.loyalty_point_rules(profession_id, is_active, valid_from, valid_until);

DROP TRIGGER IF EXISTS trg_loyalty_rules_updated_at ON public.loyalty_point_rules;
CREATE TRIGGER trg_loyalty_rules_updated_at
    BEFORE UPDATE ON public.loyalty_point_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. KPI SCHEDULED REPORTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.scheduled_reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    report_name     TEXT NOT NULL,
    report_type     TEXT NOT NULL
                        CHECK (report_type IN ('sales_summary', 'inventory_status', 'employee_performance', 'customer_activity', 'financial_gl')),
    frequency       TEXT NOT NULL DEFAULT 'daily'
                        CHECK (frequency IN ('daily', 'weekly', 'monthly', 'quarterly')),
    format          TEXT NOT NULL DEFAULT 'pdf'
                        CHECK (format IN ('pdf', 'excel', 'csv')),
    parameters      JSONB DEFAULT '{}',                     -- {start_date, end_date, branch_id, ...}
    is_active       BOOLEAN DEFAULT true,
    last_run_at     TIMESTAMPTZ,
    next_run_at     TIMESTAMPTZ,
    last_run_status TEXT,                                   -- success, failed
    last_run_error  TEXT,
    created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scheduled_reports_profession
    ON public.scheduled_reports(profession_id, is_active, next_run_at);

DROP TRIGGER IF EXISTS trg_scheduled_reports_updated_at ON public.scheduled_reports;
CREATE TRIGGER trg_scheduled_reports_updated_at
    BEFORE UPDATE ON public.scheduled_reports
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. RLS POLICIES
-- ============================================================
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_point_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scheduled_reports ENABLE ROW LEVEL SECURITY;

-- Refunds
DROP POLICY IF EXISTS "refunds_select" ON public.refund_requests;
CREATE POLICY "refunds_select" ON public.refund_requests FOR SELECT USING (true);
DROP POLICY IF EXISTS "refunds_modify" ON public.refund_requests;
CREATE POLICY "refunds_modify" ON public.refund_requests FOR ALL USING (true);

-- Loyalty Rules
DROP POLICY IF EXISTS "loyalty_rules_select" ON public.loyalty_point_rules;
CREATE POLICY "loyalty_rules_select" ON public.loyalty_point_rules FOR SELECT USING (true);
DROP POLICY IF EXISTS "loyalty_rules_modify" ON public.loyalty_point_rules;
CREATE POLICY "loyalty_rules_modify" ON public.loyalty_point_rules FOR ALL USING (true);

-- Scheduled Reports
DROP POLICY IF EXISTS "scheduled_reports_select" ON public.scheduled_reports;
CREATE POLICY "scheduled_reports_select" ON public.scheduled_reports FOR SELECT USING (true);
DROP POLICY IF EXISTS "scheduled_reports_modify" ON public.scheduled_reports;
CREATE POLICY "scheduled_reports_modify" ON public.scheduled_reports FOR ALL USING (true);

-- ============================================================
-- 5. RPC FUNCTIONS
-- ============================================================

-- Request refund
CREATE OR REPLACE FUNCTION request_refund(
    p_profession_id UUID,
    p_order_id UUID,
    p_customer_id UUID,
    p_amount DECIMAL(12,2),
    p_reason TEXT,
    p_requested_by UUID
)
RETURNS UUID AS $$
DECLARE
    v_order_number TEXT;
    v_refund_id UUID;
BEGIN
    SELECT order_number INTO v_order_number FROM public.orders WHERE id = p_order_id;

    INSERT INTO public.refund_requests (
        profession_id, order_id, order_number, customer_id,
        amount, reason, requested_by, status
    )
    VALUES (
        p_profession_id, p_order_id, v_order_number, p_customer_id,
        p_amount, p_reason, p_requested_by, 'pending'
    )
    RETURNING id INTO v_refund_id;

    RETURN v_refund_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Review refund (approve/reject)
CREATE OR REPLACE FUNCTION review_refund(
    p_refund_id UUID,
    p_status TEXT,
    p_reviewed_by UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_status NOT IN ('approved', 'rejected') THEN
        RETURN false;
    END IF;

    UPDATE public.refund_requests
    SET status = p_status,
        reviewed_by = p_reviewed_by,
        notes = COALESCE(p_notes, notes),
        reviewed_at = NOW(),
        completed_at = CASE WHEN p_status = 'approved' THEN NOW() ELSE completed_at END,
        updated_at = NOW()
    WHERE id = p_refund_id AND status = 'pending';

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Calculate loyalty points from order total
CREATE OR REPLACE FUNCTION calculate_loyalty_points(
    p_profession_id UUID,
    p_order_total DECIMAL(12,2),
    p_item_type TEXT DEFAULT 'all'
)
RETURNS INTEGER AS $$
DECLARE
    v_rule RECORD;
    v_points INTEGER;
BEGIN
    SELECT * INTO v_rule
    FROM public.loyalty_point_rules
    WHERE profession_id = p_profession_id
      AND is_active = true
      AND valid_from <= CURRENT_DATE
      AND (valid_until IS NULL OR valid_until >= CURRENT_DATE)
      AND (applies_to = 'all' OR applies_to = p_item_type)
    ORDER BY min_purchase DESC
    LIMIT 1;

    IF NOT FOUND OR p_order_total < v_rule.min_purchase THEN
        RETURN 0;
    END IF;

    v_points := FLOOR(p_order_total * v_rule.points_per_baht * v_rule.bonus_multiplier)::INTEGER;
    RETURN v_points;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Generate report payload (JSON)
CREATE OR REPLACE FUNCTION generate_report_payload(
    p_profession_id UUID,
    p_report_type TEXT,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    CASE p_report_type
        WHEN 'sales_summary' THEN
            SELECT jsonb_build_object(
                'report_type', p_report_type,
                'period', jsonb_build_object('from', p_start_date, 'to', p_end_date),
                'total_revenue', COALESCE(SUM(final_amount), 0),
                'total_orders', COUNT(*),
                'total_items', (SELECT COUNT(*) FROM public.order_items oi JOIN public.orders o ON oi.order_id = o.id WHERE o.profession_id = p_profession_id AND o.created_at BETWEEN p_start_date AND p_end_date)
            ) INTO v_result
            FROM public.orders
            WHERE profession_id = p_profession_id
              AND status IN ('paid', 'completed')
              AND created_at BETWEEN p_start_date AND p_end_date + INTERVAL '1 day';

        WHEN 'inventory_status' THEN
            SELECT jsonb_build_object(
                'report_type', p_report_type,
                'generated_at', NOW(),
                'products', (
                    SELECT jsonb_agg(jsonb_build_object(
                        'product_id', p.id,
                        'name', p.name,
                        'stock_quantity', COALESCE((
                            SELECT SUM(quantity)
                            FROM public.inventory_lots il
                            WHERE il.product_id = p.id AND il.status = 'active'
                        ), 0)
                    ))
                    FROM public.products p
                    WHERE p.profession_id = p_profession_id
                )
            ) INTO v_result;

        WHEN 'employee_performance' THEN
            SELECT jsonb_build_object(
                'report_type', p_report_type,
                'period', jsonb_build_object('from', p_start_date, 'to', p_end_date),
                'active_employees', COALESCE((
                    SELECT COUNT(*)
                    FROM public.employees e
                    WHERE e.profession_id = p_profession_id
                      AND e.is_active = true
                ), 0),
                'top_employees', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'employee_id', ranked.employee_id,
                        'full_name', ranked.full_name,
                        'order_count', ranked.order_count,
                        'sales_amount', ranked.sales_amount
                    ))
                    FROM (
                        SELECT
                            e.id AS employee_id,
                            e.full_name,
                            COUNT(o.id) AS order_count,
                            COALESCE(SUM(o.final_amount), 0) AS sales_amount
                        FROM public.employees e
                        LEFT JOIN public.orders o
                            ON o.served_by = e.user_id
                           AND o.profession_id = p_profession_id
                           AND o.status IN ('paid', 'completed')
                           AND o.created_at BETWEEN p_start_date AND p_end_date + INTERVAL '1 day'
                        WHERE e.profession_id = p_profession_id
                          AND e.is_active = true
                        GROUP BY e.id, e.full_name
                        ORDER BY sales_amount DESC, order_count DESC
                        LIMIT 10
                    ) ranked
                ), '[]'::jsonb)
            ) INTO v_result;

        WHEN 'customer_activity' THEN
            SELECT jsonb_build_object(
                'report_type', p_report_type,
                'period', jsonb_build_object('from', p_start_date, 'to', p_end_date),
                'unique_customers', COALESCE((
                    SELECT COUNT(DISTINCT o.user_id)
                    FROM public.orders o
                    WHERE o.profession_id = p_profession_id
                      AND o.status IN ('paid', 'completed')
                      AND o.created_at BETWEEN p_start_date AND p_end_date + INTERVAL '1 day'
                ), 0),
                'total_orders', COALESCE((
                    SELECT COUNT(*)
                    FROM public.orders o
                    WHERE o.profession_id = p_profession_id
                      AND o.status IN ('paid', 'completed')
                      AND o.created_at BETWEEN p_start_date AND p_end_date + INTERVAL '1 day'
                ), 0),
                'top_customers', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'user_id', ranked.user_id,
                        'order_count', ranked.order_count,
                        'total_amount', ranked.total_amount
                    ))
                    FROM (
                        SELECT
                            o.user_id,
                            COUNT(*) AS order_count,
                            COALESCE(SUM(o.final_amount), 0) AS total_amount
                        FROM public.orders o
                        WHERE o.profession_id = p_profession_id
                          AND o.status IN ('paid', 'completed')
                          AND o.created_at BETWEEN p_start_date AND p_end_date + INTERVAL '1 day'
                        GROUP BY o.user_id
                        ORDER BY total_amount DESC, order_count DESC
                        LIMIT 10
                    ) ranked
                ), '[]'::jsonb)
            ) INTO v_result;

        WHEN 'financial_gl' THEN
            SELECT jsonb_build_object(
                'report_type', p_report_type,
                'period', jsonb_build_object('from', p_start_date, 'to', p_end_date),
                'debit_total', COALESCE(SUM(debit_amount), 0),
                'credit_total', COALESCE(SUM(credit_amount), 0),
                'net_total', COALESCE(SUM(credit_amount - debit_amount), 0),
                'entry_count', COUNT(*)
            ) INTO v_result
            FROM public.gl_entries
            WHERE profession_id = p_profession_id
              AND entry_date BETWEEN p_start_date AND p_end_date;

        ELSE
            v_result := jsonb_build_object('report_type', p_report_type, 'error', 'Unknown report type');
    END CASE;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
