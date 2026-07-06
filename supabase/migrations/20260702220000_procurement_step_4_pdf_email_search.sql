-- Migration: Procurement Step 4 — PO PDF Mock & Email RPCs + Full-Text Search
-- Date: 2026-07-02
-- Prerequisites: 20260702190000 (matching tables), 20260611160000 (PO tables)
-- Functions:
--   1. generate_po_pdf_url(p_po_id) — returns a mock signed URL for PO PDF
--   2. send_po_email(p_po_id, p_email, p_message) — records email request + emits outbox event
--   3. search_procurement_documents(p_profession_id, p_query, p_entity_types) — full-text search

-- ============================================================
-- 1. generate_po_pdf_url
--    Returns a mock signed URL for the PO PDF.
--    In production, this would call Supabase Storage / Edge Function.
--    For now, returns a mock URL with PO data encoded.
-- ============================================================
CREATE OR REPLACE FUNCTION public.generate_po_pdf_url(
    p_po_id  UUID
)
RETURNS JSONB AS $$
DECLARE
    v_po         public.purchase_orders%ROWTYPE;
    v_supplier   public.suppliers%ROWTYPE;
    v_items      JSONB;
    v_mock_url   TEXT;
BEGIN
    SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Purchase order not found: %', p_po_id;
    END IF;

    SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_po.supplier_id;

    -- Get PO items as JSON
    SELECT jsonb_agg(
        jsonb_build_object(
            'product_id', poi.product_id,
            'product_name', p.name,
            'quantity_ordered', poi.quantity_ordered,
            'unit_price', poi.unit_price,
            'total_price', poi.total_price
        )
    )
    INTO v_items
    FROM public.purchase_order_items poi
    LEFT JOIN public.products p ON p.id = poi.product_id
    WHERE poi.po_id = p_po_id;

    IF v_items IS NULL THEN v_items := '[]'::jsonb; END IF;

    -- Mock URL (in production: Supabase Storage signed URL or Edge Function endpoint)
    v_mock_url := '/po-pdf/' || p_po_id::TEXT || '?t=' || EXTRACT(EPOCH FROM NOW())::INT::TEXT;

    RETURN jsonb_build_object(
        'po_id', p_po_id,
        'po_number', v_po.po_number,
        'supplier_name', v_supplier.supplier_name,
        'grand_total', v_po.grand_total,
        'items', v_items,
        'pdf_url', v_mock_url,
        'note', 'Mock URL — implement Edge Function for actual PDF generation'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 2. send_po_email
--    Records an email request and emits an outbox event.
--    In production, an email consumer would pick up the event and send via Resend/SendGrid.
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_po_email(
    p_po_id    UUID,
    p_email    TEXT,
    p_message  TEXT DEFAULT NULL,
    p_sent_by  UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_po           public.purchase_orders%ROWTYPE;
    v_profession_id UUID;
    v_outbox_id    UUID;
BEGIN
    SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Purchase order not found: %', p_po_id;
    END IF;

    v_profession_id := v_po.profession_id;

    -- Emit outbox event for email consumer
    INSERT INTO public.outbox_events (
        profession_id, aggregate_type, aggregate_id, event_type, payload
    )
    VALUES (
        v_profession_id, 'procurement_po', p_po_id,
        'procurement.po_email_requested',
        jsonb_build_object(
            'po_id', p_po_id,
            'po_number', v_po.po_number,
            'email', p_email,
            'message', p_message,
            'sent_by', p_sent_by
        )
    )
    RETURNING id INTO v_outbox_id;

    RETURN jsonb_build_object(
        'success', true,
        'outbox_id', v_outbox_id,
        'po_number', v_po.po_number,
        'email', p_email,
        'note', 'Email request queued — implement email consumer for actual sending'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 3. search_procurement_documents
--    Full-text search across procurement documents.
--    Uses ILIKE for broad matching (tsvector can be added later for performance).
--    Searches: purchase_orders, purchase_requisitions, goods_receipts, suppliers
-- ============================================================
CREATE OR REPLACE FUNCTION public.search_procurement_documents(
    p_profession_id  UUID,
    p_query          TEXT,
    p_entity_types   TEXT[] DEFAULT ARRAY['po','pr','gr','supplier'],
    p_limit          INTEGER DEFAULT 50
)
RETURNS JSONB AS $$
DECLARE
    v_results JSONB := '[]'::jsonb;
    v_q       TEXT := '%' || LOWER(TRIM(p_query)) || '%';
    v_partial JSONB;
BEGIN
    IF TRIM(p_query) = '' THEN
        RETURN jsonb_build_object('query', p_query, 'results', '[]'::jsonb);
    END IF;

    -- Search Purchase Orders
    IF 'po' = ANY(p_entity_types) THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'entity_type', 'po',
                'id', po.id,
                'number', po.po_number,
                'title', 'ใบสั่งซื้อ ' || po.po_number,
                'subtitle', COALESCE(s.supplier_name, ''),
                'status', po.status,
                'amount', po.grand_total,
                'created_at', po.created_at
            )
        ), '[]'::jsonb)
        INTO v_partial
        FROM public.purchase_orders po
        LEFT JOIN public.suppliers s ON s.id = po.supplier_id
        WHERE po.profession_id = p_profession_id
          AND (LOWER(po.po_number) LIKE v_q OR LOWER(COALESCE(s.supplier_name, '')) LIKE v_q
               OR LOWER(COALESCE(po.notes, '')) LIKE v_q);
        v_results := v_results || v_partial;
    END IF;

    -- Search Purchase Requisitions
    IF 'pr' = ANY(p_entity_types) THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'entity_type', 'pr',
                'id', pr.id,
                'number', pr.pr_number,
                'title', 'ใบขอซื้อ ' || pr.pr_number,
                'subtitle', COALESCE(pr.notes, ''),
                'status', pr.status,
                'amount', pr.total_amount,
                'created_at', pr.created_at
            )
        ), '[]'::jsonb)
        INTO v_partial
        FROM public.purchase_requisitions pr
        WHERE pr.profession_id = p_profession_id
          AND (LOWER(pr.pr_number) LIKE v_q OR LOWER(COALESCE(pr.notes, '')) LIKE v_q);
        v_results := v_results || v_partial;
    END IF;

    -- Search Goods Receipts
    IF 'gr' = ANY(p_entity_types) THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'entity_type', 'gr',
                'id', gr.id,
                'number', gr.gr_number,
                'title', 'ใบรับของ ' || gr.gr_number,
                'subtitle', COALESCE(gr.notes, ''),
                'status', gr.status,
                'created_at', gr.created_at
            )
        ), '[]'::jsonb)
        INTO v_partial
        FROM public.goods_receipts gr
        WHERE gr.profession_id = p_profession_id
          AND (LOWER(gr.gr_number) LIKE v_q OR LOWER(COALESCE(gr.notes, '')) LIKE v_q);
        v_results := v_results || v_partial;
    END IF;

    -- Search Suppliers
    IF 'supplier' = ANY(p_entity_types) THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'entity_type', 'supplier',
                'id', s.id,
                'number', '',
                'title', s.supplier_name,
                'subtitle', COALESCE(s.contact_name, '') || ' — ' || COALESCE(s.phone, ''),
                'status', CASE WHEN s.is_active THEN 'active' ELSE 'inactive' END,
                'created_at', s.created_at
            )
        ), '[]'::jsonb)
        INTO v_partial
        FROM public.suppliers s
        WHERE s.profession_id = p_profession_id
          AND (LOWER(s.supplier_name) LIKE v_q OR LOWER(COALESCE(s.contact_name, '')) LIKE v_q
               OR LOWER(COALESCE(s.email, '')) LIKE v_q OR LOWER(COALESCE(s.phone, '')) LIKE v_q);
        v_results := v_results || v_partial;
    END IF;

    IF v_results IS NULL THEN v_results := '[]'::jsonb; END IF;

    -- Limit results
    v_results := (
        SELECT jsonb_agg(elem)
        FROM (
            SELECT elem
            FROM jsonb_array_elements(v_results) AS elem
            LIMIT p_limit
        ) sub
    );

    RETURN jsonb_build_object(
        'query', p_query,
        'entity_types', p_entity_types,
        'count', jsonb_array_length(COALESCE(v_results, '[]'::jsonb)),
        'results', COALESCE(v_results, '[]'::jsonb)
    );
END;
$$ LANGUAGE plpgsql;
