-- Migration: Procurement Step 4 — RPC Functions (3-Way Matching)
-- Date: 2026-07-02
-- Prerequisites: 20260702190000_procurement_step_4_matching.sql
-- Functions:
--   1. create_supplier_invoice(...)
--   2. match_supplier_invoice(p_invoice_id)
--   3. update_invoice_matching_status(p_invoice_id, p_status, p_reason)
--   4. get_invoice_matching_summary(p_po_id)

-- ============================================================
-- 1. create_supplier_invoice
--    Creates a supplier invoice with line items.
--    Emits outbox event: procurement.supplier_invoice_created
--    Returns JSONB with invoice_id.
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_supplier_invoice(
    p_profession_id   UUID,
    p_supplier_id     UUID,
    p_invoice_number  TEXT,
    p_invoice_date    DATE,
    p_po_id           UUID DEFAULT NULL,
    p_due_date        DATE DEFAULT NULL,
    p_items           JSONB DEFAULT '[]'::jsonb,
    p_notes           TEXT DEFAULT NULL,
    p_created_by      UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_invoice_id    UUID;
    v_total_amount  DECIMAL(12,2) := 0;
    v_tax_amount    DECIMAL(12,2) := 0;
    v_grand_total   DECIMAL(12,2) := 0;
    v_item          JSONB;
    v_po            RECORD;
    v_product_name  TEXT;
BEGIN
    -- Validate PO if provided
    IF p_po_id IS NOT NULL THEN
        SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Purchase order not found: %', p_po_id;
        END IF;
        IF v_po.profession_id != p_profession_id THEN
            RAISE EXCEPTION 'PO does not belong to profession %', p_profession_id;
        END IF;
    END IF;

    -- Calculate totals from items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_total_amount := v_total_amount + COALESCE((v_item->>'total_price')::DECIMAL(12,2), 0);
        v_tax_amount := v_tax_amount + COALESCE((v_item->>'tax_amount')::DECIMAL(12,2), 0);
    END LOOP;
    v_grand_total := v_total_amount + v_tax_amount;

    -- Create supplier invoice
    INSERT INTO public.supplier_invoices (
        profession_id, supplier_id, po_id,
        invoice_number, invoice_date, due_date,
        total_amount, tax_amount, grand_total,
        status, matching_status, notes, created_by
    )
    VALUES (
        p_profession_id, p_supplier_id, p_po_id,
        p_invoice_number, p_invoice_date, p_due_date,
        v_total_amount, v_tax_amount, v_grand_total,
        'pending', 'pending', p_notes, p_created_by
    )
    RETURNING id INTO v_invoice_id;

    -- Create invoice items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT name INTO v_product_name FROM public.products
        WHERE id = (v_item->>'product_id')::UUID;

        INSERT INTO public.supplier_invoice_items (
            profession_id, supplier_invoice_id, po_item_id, product_id,
            item_name, quantity_invoiced, unit_price, total_price, tax_amount, notes
        )
        VALUES (
            p_profession_id, v_invoice_id,
            NULLIF(v_item->>'po_item_id', '')::UUID,
            NULLIF(v_item->>'product_id', '')::UUID,
            COALESCE(v_product_name, v_item->>'item_name', ''),
            COALESCE((v_item->>'quantity_invoiced')::INTEGER, 0),
            COALESCE((v_item->>'unit_price')::DECIMAL(12,2), 0),
            COALESCE((v_item->>'total_price')::DECIMAL(12,2), 0),
            COALESCE((v_item->>'tax_amount')::DECIMAL(12,2), 0),
            v_item->>'notes'
        );
    END LOOP;

    -- Emit outbox event
    INSERT INTO public.outbox_events (
        profession_id, aggregate_type, aggregate_id, event_type, payload
    )
    VALUES (
        p_profession_id, 'supplier_invoice', v_invoice_id,
        'procurement.supplier_invoice_created',
        jsonb_build_object(
            'invoice_id', v_invoice_id,
            'invoice_number', p_invoice_number,
            'supplier_id', p_supplier_id,
            'po_id', p_po_id,
            'grand_total', v_grand_total
        )
    );

    RETURN jsonb_build_object(
        'invoice_id', v_invoice_id,
        'invoice_number', p_invoice_number,
        'total_amount', v_total_amount,
        'tax_amount', v_tax_amount,
        'grand_total', v_grand_total
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 2. match_supplier_invoice
--    Performs 3-way matching: PO (expected) vs GR (received) vs Invoice (billed).
--    Tolerance: quantity ±1 unit, price ±0.5%, tax must match vat_rate.
--    Updates matching_status and status on the invoice.
--    Emits outbox event: procurement.invoice_matched or procurement.invoice_mismatch
--    Returns JSONB with matching result.
-- ============================================================
CREATE OR REPLACE FUNCTION public.match_supplier_invoice(
    p_invoice_id  UUID
)
RETURNS JSONB AS $$
DECLARE
    v_invoice        public.supplier_invoices%ROWTYPE;
    v_mismatches     JSONB := '[]'::jsonb;
    v_match_ok       BOOLEAN := true;
    v_po_item        RECORD;
    v_gr_qty         INTEGER;
    v_inv_item       RECORD;
    v_po_vat_rate    DECIMAL(5,4) := 0.0700;
    v_expected_tax   DECIMAL(12,2);
    v_price_diff     DECIMAL(12,2);
    v_price_tol      DECIMAL(12,2);
    v_qty_ok         BOOLEAN;
    v_price_ok       BOOLEAN;
    v_tax_ok         BOOLEAN;
    v_final_status   TEXT;
BEGIN
    SELECT * INTO v_invoice FROM public.supplier_invoices WHERE id = p_invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier invoice not found: %', p_invoice_id;
    END IF;

    -- If no PO linked, can only do 2-way (GR vs Invoice)
    IF v_invoice.po_id IS NULL THEN
        v_final_status := 'matched';
        -- Simple: just mark as matched if no PO to compare
        UPDATE public.supplier_invoices
        SET matching_status = 'matched', status = 'matched',
            mismatch_details = jsonb_build_object('note', 'No PO linked — 2-way match only')
        WHERE id = p_invoice_id;

        INSERT INTO public.outbox_events (
            profession_id, aggregate_type, aggregate_id, event_type, payload
        )
        VALUES (
            v_invoice.profession_id, 'supplier_invoice', p_invoice_id,
            'procurement.invoice_matched',
            jsonb_build_object('invoice_id', p_invoice_id, 'match_type', '2_way')
        );

        RETURN jsonb_build_object('matching_status', 'matched', 'mismatches', '[]'::jsonb);
    END IF;

    -- 3-way matching: compare each invoice item against PO item + GR items
    FOR v_inv_item IN
        SELECT * FROM public.supplier_invoice_items
        WHERE supplier_invoice_id = p_invoice_id
    LOOP
        -- Get PO item if linked
        IF v_inv_item.po_item_id IS NOT NULL THEN
            SELECT * INTO v_po_item FROM public.purchase_order_items
            WHERE id = v_inv_item.po_item_id;

            -- Get total received quantity from GR items for this PO item
            SELECT COALESCE(SUM(quantity_accepted), 0) INTO v_gr_qty
            FROM public.goods_receipt_items
            WHERE purchase_order_item_id = v_inv_item.po_item_id;

            -- Check quantity: invoiced vs received (tolerance: ±1 unit)
            v_qty_ok := ABS(v_inv_item.quantity_invoiced - v_gr_qty) <= 1;

            -- Check price: invoiced vs PO (tolerance: ±0.5%)
            v_price_diff := ABS(v_inv_item.unit_price - v_po_item.unit_price);
            v_price_tol := v_po_item.unit_price * 0.005;
            v_price_ok := v_price_diff <= v_price_tol;

            -- Check tax: calculated vs invoiced
            v_expected_tax := v_inv_item.total_price * v_po_vat_rate;
            v_tax_ok := ABS(v_inv_item.tax_amount - v_expected_tax) <= 1.00;

            IF NOT v_qty_ok THEN
                v_mismatches := v_mismatches || jsonb_build_object(
                    'item_id', v_inv_item.id,
                    'type', 'quantity',
                    'invoiced', v_inv_item.quantity_invoiced,
                    'received', v_gr_qty,
                    'po_ordered', v_po_item.quantity_ordered
                );
                v_match_ok := false;
            END IF;

            IF NOT v_price_ok THEN
                v_mismatches := v_mismatches || jsonb_build_object(
                    'item_id', v_inv_item.id,
                    'type', 'price',
                    'invoiced_price', v_inv_item.unit_price,
                    'po_price', v_po_item.unit_price,
                    'diff', v_price_diff
                );
                v_match_ok := false;
            END IF;

            IF NOT v_tax_ok THEN
                v_mismatches := v_mismatches || jsonb_build_object(
                    'item_id', v_inv_item.id,
                    'type', 'tax',
                    'invoiced_tax', v_inv_item.tax_amount,
                    'expected_tax', v_expected_tax
                );
                v_match_ok := false;
            END IF;

            -- Update matched_quantity on invoice item
            UPDATE public.supplier_invoice_items
            SET matched_quantity = LEAST(v_inv_item.quantity_invoiced, v_gr_qty)
            WHERE id = v_inv_item.id;
        END IF;
    END LOOP;

    -- Determine final status
    IF v_match_ok THEN
        v_final_status := 'matched';
        UPDATE public.supplier_invoices
        SET matching_status = 'matched', status = 'matched',
            mismatch_details = NULL
        WHERE id = p_invoice_id;

        INSERT INTO public.outbox_events (
            profession_id, aggregate_type, aggregate_id, event_type, payload
        )
        VALUES (
            v_invoice.profession_id, 'supplier_invoice', p_invoice_id,
            'procurement.invoice_matched',
            jsonb_build_object('invoice_id', p_invoice_id, 'match_type', '3_way')
        );
    ELSE
        -- Determine primary mismatch type
        IF v_mismatches @? '$[*] ? (@.type == "quantity")' THEN
            v_final_status := 'mismatch_quantity';
        ELSIF v_mismatches @? '$[*] ? (@.type == "price")' THEN
            v_final_status := 'mismatch_price';
        ELSIF v_mismatches @? '$[*] ? (@.type == "tax")' THEN
            v_final_status := 'mismatch_tax';
        ELSE
            v_final_status := 'disputed';
        END IF;

        UPDATE public.supplier_invoices
        SET matching_status = v_final_status, status = 'disputed',
            mismatch_details = v_mismatches
        WHERE id = p_invoice_id;

        INSERT INTO public.outbox_events (
            profession_id, aggregate_type, aggregate_id, event_type, payload
        )
        VALUES (
            v_invoice.profession_id, 'supplier_invoice', p_invoice_id,
            'procurement.invoice_mismatch',
            jsonb_build_object(
                'invoice_id', p_invoice_id,
                'mismatch_type', v_final_status,
                'mismatches', v_mismatches
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'matching_status', v_final_status,
        'mismatches', v_mismatches,
        'match_ok', v_match_ok
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 3. update_invoice_matching_status
--    Manually update matching status (e.g., resolve dispute, mark as paid).
--    Emits outbox event for status change.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_invoice_matching_status(
    p_invoice_id  UUID,
    p_status      TEXT,
    p_reason      TEXT DEFAULT NULL,
    p_updated_by  UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_profession_id UUID;
    v_old_status    TEXT;
BEGIN
    SELECT profession_id, matching_status INTO v_profession_id, v_old_status
    FROM public.supplier_invoices WHERE id = p_invoice_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier invoice not found: %', p_invoice_id;
    END IF;

    -- Validate status
    IF p_status NOT IN ('pending','matched','mismatch_quantity','mismatch_price','mismatch_tax','disputed') THEN
        RAISE EXCEPTION 'Invalid matching status: %', p_status;
    END IF;

    UPDATE public.supplier_invoices
    SET matching_status = p_status,
        status = CASE WHEN p_status = 'matched' THEN 'matched'
                      WHEN p_status IN ('mismatch_quantity','mismatch_price','mismatch_tax','disputed') THEN 'disputed'
                      ELSE status END,
        mismatch_details = CASE WHEN p_reason IS NOT NULL
                                THEN jsonb_build_object('manual_override', p_reason, 'overridden_by', p_updated_by)
                                ELSE mismatch_details END
    WHERE id = p_invoice_id;

    -- Emit outbox event
    INSERT INTO public.outbox_events (
        profession_id, aggregate_type, aggregate_id, event_type, payload
    )
    VALUES (
        v_profession_id, 'supplier_invoice', p_invoice_id,
        'procurement.invoice_status_changed',
        jsonb_build_object(
            'invoice_id', p_invoice_id,
            'old_status', v_old_status,
            'new_status', p_status,
            'reason', p_reason,
            'updated_by', p_updated_by
        )
    );

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 4. get_invoice_matching_summary
--    Returns matching summary for a PO: all invoices linked to it
--    with their matching status and mismatch details.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_invoice_matching_summary(
    p_po_id  UUID
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_agg(
        jsonb_build_object(
            'invoice_id', si.id,
            'invoice_number', si.invoice_number,
            'invoice_date', si.invoice_date,
            'supplier_id', si.supplier_id,
            'total_amount', si.total_amount,
            'tax_amount', si.tax_amount,
            'grand_total', si.grand_total,
            'status', si.status,
            'matching_status', si.matching_status,
            'mismatch_details', si.mismatch_details,
            'item_count', (
                SELECT COUNT(*) FROM public.supplier_invoice_items
                WHERE supplier_invoice_id = si.id
            )
        )
    )
    INTO v_result
    FROM public.supplier_invoices si
    WHERE si.po_id = p_po_id;

    IF v_result IS NULL THEN
        v_result := '[]'::jsonb;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
