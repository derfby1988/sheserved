-- Migration: Procurement Step 4 — Dashboard & Reporting RPCs
-- Date: 2026-07-02
-- Prerequisites: 20260702190000 (matching tables), 20260702200000 (matching RPCs)
-- Functions:
--   1. get_procurement_dashboard_metrics(p_profession_id, p_branch_id, p_start_date, p_end_date)
--   2. get_procurement_report(p_profession_id, p_report_type, p_filters)

-- ============================================================
-- 1. get_procurement_dashboard_metrics
--    Returns KPI summary for procurement dashboard.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_procurement_dashboard_metrics(
    p_profession_id  UUID,
    p_branch_id      UUID DEFAULT NULL,
    p_start_date     DATE DEFAULT NULL,
    p_end_date       DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_start_date  DATE := COALESCE(p_start_date, CURRENT_DATE - INTERVAL '30 days');
    v_end_date    DATE := COALESCE(p_end_date, CURRENT_DATE);
    v_po_total    DECIMAL(12,2) := 0;
    v_po_count    INTEGER := 0;
    v_pr_pending  INTEGER := 0;
    v_gr_count    INTEGER := 0;
    v_bo_open     INTEGER := 0;
    v_inv_matched INTEGER := 0;
    v_inv_mismatch INTEGER := 0;
    v_inv_pending INTEGER := 0;
    v_reorder_pending INTEGER := 0;
    v_monthly     JSONB := '[]'::jsonb;
    v_top_products JSONB := '[]'::jsonb;
BEGIN
    -- PO total amount and count in date range
    SELECT COALESCE(SUM(grand_total), 0), COUNT(*)
    INTO v_po_total, v_po_count
    FROM public.purchase_orders
    WHERE profession_id = p_profession_id
      AND (p_branch_id IS NULL OR branch_id = p_branch_id)
      AND created_at::DATE BETWEEN v_start_date AND v_end_date;

    -- PR pending approval
    SELECT COUNT(*) INTO v_pr_pending
    FROM public.purchase_requisitions
    WHERE profession_id = p_profession_id
      AND status = 'pending_approval';

    -- GR count in date range
    SELECT COUNT(*) INTO v_gr_count
    FROM public.goods_receipts
    WHERE profession_id = p_profession_id
      AND (p_branch_id IS NULL OR branch_id = p_branch_id)
      AND receipt_date::DATE BETWEEN v_start_date AND v_end_date;

    -- Open back orders
    SELECT COUNT(*) INTO v_bo_open
    FROM public.back_orders
    WHERE profession_id = p_profession_id
      AND status = 'open';

    -- Invoice matching stats
    SELECT
        COUNT(*) FILTER (WHERE matching_status = 'matched'),
        COUNT(*) FILTER (WHERE matching_status IN ('mismatch_quantity','mismatch_price','mismatch_tax','disputed')),
        COUNT(*) FILTER (WHERE matching_status = 'pending')
    INTO v_inv_matched, v_inv_mismatch, v_inv_pending
    FROM public.supplier_invoices
    WHERE profession_id = p_profession_id;

    -- Pending reorder suggestions
    SELECT COUNT(*) INTO v_reorder_pending
    FROM public.reorder_suggestions
    WHERE profession_id = p_profession_id
      AND status = 'pending';

    -- Monthly PO totals (last 6 months)
    SELECT jsonb_agg(
        jsonb_build_object(
            'month', TO_CHAR(d.month, 'YYYY-MM'),
            'total', d.total,
            'count', d.cnt
        )
    )
    INTO v_monthly
    FROM (
        SELECT
            DATE_TRUNC('month', created_at)::DATE AS month,
            COALESCE(SUM(grand_total), 0) AS total,
            COUNT(*) AS cnt
        FROM public.purchase_orders
        WHERE profession_id = p_profession_id
          AND (p_branch_id IS NULL OR branch_id = p_branch_id)
          AND created_at >= CURRENT_DATE - INTERVAL '6 months'
        GROUP BY DATE_TRUNC('month', created_at)
        ORDER BY month
    ) d;

    IF v_monthly IS NULL THEN v_monthly := '[]'::jsonb; END IF;

    -- Top 10 products by PO quantity
    SELECT jsonb_agg(
        jsonb_build_object(
            'product_id', t.product_id,
            'product_name', t.product_name,
            'total_qty', t.total_qty,
            'total_amount', t.total_amount
        )
    )
    INTO v_top_products
    FROM (
        SELECT
            poi.product_id,
            COALESCE(p.name, 'Unknown') AS product_name,
            SUM(poi.quantity_ordered) AS total_qty,
            SUM(poi.total_price) AS total_amount
        FROM public.purchase_order_items poi
        JOIN public.purchase_orders po ON po.id = poi.po_id
        LEFT JOIN public.products p ON p.id = poi.product_id
        WHERE po.profession_id = p_profession_id
          AND (p_branch_id IS NULL OR po.branch_id = p_branch_id)
          AND po.created_at::DATE BETWEEN v_start_date AND v_end_date
        GROUP BY poi.product_id, p.name
        ORDER BY total_qty DESC
        LIMIT 10
    ) t;

    IF v_top_products IS NULL THEN v_top_products := '[]'::jsonb; END IF;

    RETURN jsonb_build_object(
        'date_range', jsonb_build_object('start', v_start_date, 'end', v_end_date),
        'po_total_amount', v_po_total,
        'po_count', v_po_count,
        'pr_pending_approval', v_pr_pending,
        'gr_count', v_gr_count,
        'back_order_open', v_bo_open,
        'invoice_matched', v_inv_matched,
        'invoice_mismatch', v_inv_mismatch,
        'invoice_pending', v_inv_pending,
        'reorder_pending', v_reorder_pending,
        'monthly_po_totals', v_monthly,
        'top_products', v_top_products
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 2. get_procurement_report
--    Returns report data based on report_type.
--    Supported: po_summary, gr_summary, back_order_summary, price_variance, supplier_performance
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_procurement_report(
    p_profession_id  UUID,
    p_report_type    TEXT,
    p_filters        JSONB DEFAULT '{}'::jsonb,
    p_limit          INTEGER DEFAULT 100
)
RETURNS JSONB AS $$
DECLARE
    v_start_date  DATE;
    v_end_date    DATE;
    v_supplier_id UUID;
    v_result      JSONB;
BEGIN
    v_start_date := COALESCE((p_filters->>'start_date')::DATE, CURRENT_DATE - INTERVAL '30 days');
    v_end_date := COALESCE((p_filters->>'end_date')::DATE, CURRENT_DATE);
    v_supplier_id := NULLIF(p_filters->>'supplier_id', '')::UUID;

    CASE p_report_type

    -- PO Summary
    WHEN 'po_summary' THEN
        SELECT jsonb_agg(
            jsonb_build_object(
                'po_id', po.id,
                'po_number', po.po_number,
                'supplier_name', po.supplier_name,
                'status', po.status,
                'grand_total', po.grand_total,
                'created_at', po.created_at,
                'branch_name', po.branch_name
            )
        )
        INTO v_result
        FROM (
            SELECT po.id, po.po_number, po.status, po.grand_total, po.created_at, s.supplier_name, ob.branch_name
            FROM public.purchase_orders po
            LEFT JOIN public.suppliers s ON s.id = po.supplier_id
            LEFT JOIN public.organization_branches ob ON ob.id = po.branch_id
            WHERE po.profession_id = p_profession_id
              AND (v_supplier_id IS NULL OR po.supplier_id = v_supplier_id)
              AND po.created_at::DATE BETWEEN v_start_date AND v_end_date
            ORDER BY po.created_at DESC
            LIMIT p_limit
        ) po;

    -- GR Summary
    WHEN 'gr_summary' THEN
        SELECT jsonb_agg(
            jsonb_build_object(
                'gr_id', gr.id,
                'gr_number', gr.gr_number,
                'po_number', gr.po_number,
                'supplier_name', gr.supplier_name,
                'receipt_date', gr.receipt_date,
                'status', gr.status,
                'total_accepted', gr.total_accepted
            )
        )
        INTO v_result
        FROM (
            SELECT gr.id, gr.gr_number, gr.receipt_date, gr.status, gr.total_accepted, po.po_number, s.supplier_name
            FROM public.goods_receipts gr
            LEFT JOIN public.purchase_orders po ON po.id = gr.purchase_order_id
            LEFT JOIN public.suppliers s ON s.id = po.supplier_id
            WHERE gr.profession_id = p_profession_id
              AND gr.receipt_date::DATE BETWEEN v_start_date AND v_end_date
            ORDER BY gr.receipt_date DESC
            LIMIT p_limit
        ) gr;

    -- Back Order Summary
    WHEN 'back_order_summary' THEN
        SELECT jsonb_agg(
            jsonb_build_object(
                'bo_id', bo.id,
                'po_number', bo.po_number,
                'supplier_name', bo.supplier_name,
                'product_name', bo.name,
                'quantity_remaining', bo.quantity_remaining,
                'status', bo.status,
                'expected_delivery_date', bo.expected_delivery_date
            )
        )
        INTO v_result
        FROM (
            SELECT bo.id, bo.quantity_remaining, bo.status, bo.expected_delivery_date, po.po_number, s.supplier_name, p.name
            FROM public.back_orders bo
            LEFT JOIN public.purchase_orders po ON po.id = bo.purchase_order_id
            LEFT JOIN public.suppliers s ON s.id = bo.supplier_id
            LEFT JOIN public.purchase_order_items poi ON poi.id = bo.purchase_order_item_id
            LEFT JOIN public.products p ON p.id = poi.product_id
            WHERE bo.profession_id = p_profession_id
              AND (v_supplier_id IS NULL OR bo.supplier_id = v_supplier_id)
            ORDER BY bo.created_at DESC
            LIMIT p_limit
        ) bo;

    -- Price Variance
    WHEN 'price_variance' THEN
        SELECT jsonb_agg(
            jsonb_build_object(
                'product_id', sph.product_id,
                'product_name', sph.name,
                'supplier_id', sph.supplier_id,
                'supplier_name', sph.supplier_name,
                'unit_price', sph.unit_price,
                'effective_date', sph.effective_date
            )
        )
        INTO v_result
        FROM (
            SELECT sph.product_id, sph.supplier_id, sph.unit_price, sph.effective_date, p.name, s.supplier_name
            FROM public.supplier_price_history sph
            LEFT JOIN public.products p ON p.id = sph.product_id
            LEFT JOIN public.suppliers s ON s.id = sph.supplier_id
            WHERE sph.profession_id = p_profession_id
              AND (v_supplier_id IS NULL OR sph.supplier_id = v_supplier_id)
              AND sph.effective_date BETWEEN v_start_date AND v_end_date
            ORDER BY sph.effective_date DESC
            LIMIT p_limit
        ) sph;

    -- Supplier Performance
    WHEN 'supplier_performance' THEN
        SELECT jsonb_agg(
            jsonb_build_object(
                'supplier_id', s.id,
                'supplier_name', s.supplier_name,
                'po_count', s.po_count,
                'total_amount', s.total_amount,
                'gr_count', s.gr_count,
                'bo_count', s.bo_count,
                'lead_time_days', s.lead_time_days
            )
        )
        INTO v_result
        FROM (
            SELECT s.id, s.supplier_name, s.lead_time_days, stats.po_count, stats.total_amount, gr_stats.gr_count, bo_stats.bo_count
            FROM public.suppliers s
            LEFT JOIN LATERAL (
                SELECT
                    COUNT(DISTINCT po.id) AS po_count,
                    COALESCE(SUM(po.grand_total), 0) AS total_amount
                FROM public.purchase_orders po
                WHERE po.supplier_id = s.id
                  AND po.profession_id = p_profession_id
                  AND po.created_at::DATE BETWEEN v_start_date AND v_end_date
            ) stats ON true
            LEFT JOIN LATERAL (
                SELECT COUNT(DISTINCT gr.id) AS gr_count
                FROM public.goods_receipts gr
                JOIN public.purchase_orders po ON po.id = gr.purchase_order_id
                WHERE po.supplier_id = s.id
                  AND gr.profession_id = p_profession_id
                  AND gr.receipt_date::DATE BETWEEN v_start_date AND v_end_date
            ) gr_stats ON true
            LEFT JOIN LATERAL (
                SELECT COUNT(*) AS bo_count
                FROM public.back_orders bo
                WHERE bo.supplier_id = s.id
                  AND bo.profession_id = p_profession_id
                  AND bo.status = 'open'
            ) bo_stats ON true
            WHERE s.profession_id = p_profession_id
              AND s.is_active = true
              AND (v_supplier_id IS NULL OR s.id = v_supplier_id)
            ORDER BY stats.total_amount DESC NULLS LAST
            LIMIT p_limit
        ) s;

    ELSE
        v_result := jsonb_build_object('error', 'Unknown report type: ' || p_report_type);
    END CASE;

    IF v_result IS NULL THEN v_result := '[]'::jsonb; END IF;

    RETURN jsonb_build_object(
        'report_type', p_report_type,
        'filters', p_filters,
        'data', v_result
    );
END;
$$ LANGUAGE plpgsql;
