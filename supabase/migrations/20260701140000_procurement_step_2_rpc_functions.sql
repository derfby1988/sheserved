-- Migration: Procurement Step 2 — RPC Functions
-- Date: 2026-07-01
-- Prerequisites: 20260701130000_procurement_step_2_tables.sql
-- Functions: generate_document_number, create_goods_receipt, update_po_status_from_receipt

-- ============================================================
-- 1. generate_document_number(p_profession_id, p_branch_id, p_prefix)
--    Returns next sequential document number like 'PR-2026-00001'
--    Uses row-level lock for race condition safety
-- ============================================================
CREATE OR REPLACE FUNCTION public.generate_document_number(
    p_profession_id UUID,
    p_branch_id     UUID DEFAULT NULL,
    p_prefix        TEXT DEFAULT 'PR'
)
RETURNS TEXT AS $$
DECLARE
    v_year           INTEGER := EXTRACT(YEAR FROM NOW());
    v_seq_row        public.document_sequences;
    v_next_number    INTEGER;
    v_doc_number     TEXT;
BEGIN
    -- Try to find existing sequence row
    SELECT * INTO v_seq_row
    FROM public.document_sequences
    WHERE profession_id = p_profession_id
      AND (branch_id IS NOT DISTINCT FROM p_branch_id)
      AND prefix = p_prefix
      AND year = v_year
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Create new sequence row
        INSERT INTO public.document_sequences (profession_id, branch_id, prefix, year, last_number)
        VALUES (p_profession_id, p_branch_id, p_prefix, v_year, 1)
        ON CONFLICT (profession_id, branch_id, prefix, year)
        DO UPDATE SET last_number = public.document_sequences.last_number + 1
        RETURNING * INTO v_seq_row;

        v_next_number := v_seq_row.last_number;
    ELSE
        -- Increment existing
        UPDATE public.document_sequences
        SET last_number = last_number + 1
        WHERE id = v_seq_row.id
        RETURNING last_number INTO v_next_number;
    END IF;

    v_doc_number := p_prefix || '-' || v_year::TEXT || '-' || LPAD(v_next_number::TEXT, 5, '0');

    RETURN v_doc_number;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 2. create_goods_receipt(
--      p_profession_id, p_branch_id, p_purchase_order_id, p_received_by,
--      p_supplier_delivery_note, p_items JSONB, p_notes
--    )
--    Creates a goods receipt with line items, updates PO item quantities,
--    creates inventory lots + stock movements, creates back orders for shortfalls,
--    emits outbox event. Returns the goods_receipt record as JSON.
-- ============================================================
-- Drop old function signature first to avoid overload ambiguity
DROP FUNCTION IF EXISTS public.create_goods_receipt(UUID, UUID, UUID, UUID, TEXT, JSONB, TEXT);

CREATE OR REPLACE FUNCTION public.create_goods_receipt(
    p_profession_id         UUID,
    p_purchase_order_id     UUID,
    p_received_by           UUID,
    p_branch_id             UUID DEFAULT NULL,
    p_supplier_delivery_note TEXT DEFAULT NULL,
    p_items                 JSONB DEFAULT '[]'::jsonb,
    p_notes                 TEXT DEFAULT NULL,
    p_idempotency_key       TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_gr_id              UUID;
    v_gr_number          TEXT;
    v_po                 public.purchase_orders%ROWTYPE;
    v_item               JSONB;
    v_po_item            public.purchase_order_items%ROWTYPE;
    v_new_qty_received   INTEGER;
    v_remaining          INTEGER;
    v_lot_id             UUID;
    v_accepted           INTEGER;
    v_rejected           INTEGER;
    v_unit_cost          DECIMAL(12,2);
    v_total_accepted     INTEGER := 0;
    v_result             JSONB;
    v_existing_response  JSONB;
    v_bo                 public.back_orders%ROWTYPE;
    v_bo_id              UUID;
    v_bo_fulfilled_count INTEGER := 0;
    v_po_fully_received  BOOLEAN;
    v_po_new_status      TEXT;
    v_tx_context_id      UUID;
    v_steps              JSONB := '[]'::jsonb;
    v_step_start         TIMESTAMPTZ;
BEGIN
    -- Idempotency check: if p_idempotency_key provided, check for existing response
    IF p_idempotency_key IS NOT NULL THEN
        SELECT response_body INTO v_existing_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key
          AND scope = 'procurement_gr'
          AND expires_at > NOW()
        LIMIT 1;

        IF v_existing_response IS NOT NULL THEN
            -- Return cached response for duplicate request
            RETURN v_existing_response;
        END IF;
    END IF;

    -- Create transaction context for Saga observability
    v_tx_context_id := public.create_transaction_context(
        p_profession_id,
        'gr-' || p_purchase_order_id::TEXT || '-' || EXTRACT(EPOCH FROM NOW())::TEXT,
        'procurement',
        'create_goods_receipt',
        jsonb_build_object('po_id', p_purchase_order_id, 'received_by', p_received_by, 'branch_id', p_branch_id),
        p_received_by
    );

    -- Load PO
    SELECT * INTO v_po
    FROM public.purchase_orders
    WHERE id = p_purchase_order_id AND profession_id = p_profession_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Purchase order not found: %', p_purchase_order_id;
    END IF;

    IF v_po.status = 'cancelled' THEN
        RAISE EXCEPTION 'Cannot create goods receipt for cancelled PO: %', p_purchase_order_id;
    END IF;

    -- Generate GR number
    v_gr_number := public.generate_document_number(p_profession_id, p_branch_id, 'GR');

    -- Create goods_receipts record
    INSERT INTO public.goods_receipts (
        profession_id, branch_id, purchase_order_id, gr_number,
        receipt_date, supplier_delivery_note, received_by, status, notes
    )
    VALUES (
        p_profession_id, p_branch_id, p_purchase_order_id, v_gr_number,
        NOW(), p_supplier_delivery_note, p_received_by, 'completed', p_notes
    )
    RETURNING id INTO v_gr_id;

    -- Update transaction context metadata with gr_id
    UPDATE public.transaction_contexts
    SET metadata = metadata || jsonb_build_object('gr_id', v_gr_id, 'gr_number', v_gr_number)
    WHERE id = v_tx_context_id;

    -- Step 1: gr_created
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'gr_created', 'status', 'completed',
        'record_id', v_gr_id,
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Audit log: GR creation
    PERFORM record_audit_log(
        'goods_receipts', v_gr_id, 'INSERT',
        NULL, jsonb_build_object('gr_number', v_gr_number, 'po_id', p_purchase_order_id, 'status', 'completed'),
        p_received_by, 'user', p_profession_id, p_branch_id, NULL,
        'Goods receipt created'
    );

    -- Process each item
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        -- Validate PO item exists
        SELECT * INTO v_po_item
        FROM public.purchase_order_items
        WHERE id = (v_item->>'purchase_order_item_id')::UUID
          AND po_id = p_purchase_order_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'PO item not found: %', v_item->>'purchase_order_item_id';
        END IF;

        v_accepted := COALESCE((v_item->>'quantity_accepted')::INTEGER, 0);
        v_rejected := COALESCE((v_item->>'quantity_rejected')::INTEGER, 0);
        v_unit_cost := COALESCE((v_item->>'unit_cost')::DECIMAL(12,2), v_po_item.unit_price);

        -- Insert goods_receipt_items
        INSERT INTO public.goods_receipt_items (
            profession_id, goods_receipt_id, purchase_order_item_id,
            quantity_received, quantity_accepted, quantity_rejected,
            lot_number, expiry_date, unit_cost, notes
        )
        VALUES (
            p_profession_id, v_gr_id, v_po_item.id,
            v_accepted + v_rejected, v_accepted, v_rejected,
            v_item->>'lot_number',
            NULLIF(v_item->>'expiry_date', '')::DATE,
            v_unit_cost,
            v_item->>'notes'
        );

        -- Update PO item quantity_received (cumulative)
        v_new_qty_received := v_po_item.quantity_received + v_accepted + v_rejected;
        UPDATE public.purchase_order_items
        SET quantity_received = v_new_qty_received
        WHERE id = v_po_item.id;

        -- Create inventory lot for accepted quantity
        IF v_accepted > 0 THEN
            INSERT INTO public.inventory_lots (
                profession_id, product_id, branch_id,
                lot_number, expiry_date,
                quantity_received, quantity_remaining,
                unit_cost, po_id, status
            )
            VALUES (
                p_profession_id, v_po_item.product_id, p_branch_id,
                COALESCE(v_item->>'lot_number', v_gr_number),
                NULLIF(v_item->>'expiry_date', '')::DATE,
                v_accepted, v_accepted,
                v_unit_cost, p_purchase_order_id, 'active'
            )
            RETURNING id INTO v_lot_id;

            -- Create stock movement (receipt)
            INSERT INTO public.stock_movements (
                profession_id, product_id, lot_id, branch_id,
                movement_type, quantity, unit_cost, total_cost,
                reference_type, reference_id, created_by
            )
            VALUES (
                p_profession_id, v_po_item.product_id, v_lot_id, p_branch_id,
                'receipt', v_accepted, v_unit_cost, v_accepted * v_unit_cost,
                'po', p_purchase_order_id, p_received_by
            );
        END IF;

        -- Create back order for remaining unfulfilled quantity
        v_remaining := v_po_item.quantity_ordered - v_new_qty_received;
        IF v_remaining > 0 THEN
            -- Check if back order already exists for this PO item
            IF NOT EXISTS (
                SELECT 1 FROM public.back_orders
                WHERE purchase_order_id = p_purchase_order_id
                  AND purchase_order_item_id = v_po_item.id
                  AND status IN ('open', 'partially_fulfilled')
            ) THEN
                INSERT INTO public.back_orders (
                    profession_id, purchase_order_id, purchase_order_item_id,
                    supplier_id, quantity_back_ordered, quantity_fulfilled,
                    expected_delivery_date, status
                )
                VALUES (
                    p_profession_id, p_purchase_order_id, v_po_item.id,
                    v_po.supplier_id, v_remaining, 0,
                    NULLIF(v_item->>'expected_delivery_date', '')::DATE,
                    CASE
                        WHEN v_new_qty_received > 0 THEN 'partially_fulfilled'
                        ELSE 'open'
                    END
                )
                RETURNING id INTO v_bo_id;

                -- Emit outbox event: back_order_created
                INSERT INTO public.outbox_events (
                    profession_id, aggregate_type, aggregate_id, event_type, payload
                )
                VALUES (
                    p_profession_id, 'back_order', v_bo_id,
                    'procurement.back_order_created',
                    jsonb_build_object(
                        'po_id', p_purchase_order_id,
                        'po_number', v_po.po_number,
                        'po_item_id', v_po_item.id,
                        'supplier_id', v_po.supplier_id,
                        'quantity_back_ordered', v_remaining,
                        'quantity_fulfilled', 0,
                        'status', CASE WHEN v_new_qty_received > 0 THEN 'partially_fulfilled' ELSE 'open' END
                    )
                );
            END IF;
        ELSE
            -- All items received — fulfill existing back order if any
            SELECT * INTO v_bo
            FROM public.back_orders
            WHERE purchase_order_id = p_purchase_order_id
              AND purchase_order_item_id = v_po_item.id
              AND status IN ('open', 'partially_fulfilled')
            LIMIT 1;

            IF FOUND THEN
                UPDATE public.back_orders
                SET quantity_fulfilled = v_bo.quantity_back_ordered,
                    status = 'fulfilled'
                WHERE id = v_bo.id;

                v_bo_fulfilled_count := v_bo_fulfilled_count + 1;

                -- Emit outbox event: back_order_fulfilled
                INSERT INTO public.outbox_events (
                    profession_id, aggregate_type, aggregate_id, event_type, payload
                )
                VALUES (
                    p_profession_id, 'back_order', v_bo.id,
                    'procurement.back_order_fulfilled',
                    jsonb_build_object(
                        'back_order_id', v_bo.id,
                        'po_id', p_purchase_order_id,
                        'po_number', v_po.po_number,
                        'po_item_id', v_po_item.id,
                        'supplier_id', v_po.supplier_id,
                        'quantity_back_ordered', v_bo.quantity_back_ordered,
                        'quantity_fulfilled', v_bo.quantity_back_ordered
                    )
                );
            END IF;
        END IF;

        v_total_accepted := v_total_accepted + v_accepted;
    END LOOP;

    -- Step 2: gr_items_created
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'gr_items_created', 'status', 'completed',
        'count', jsonb_array_length(p_items),
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Step 3: po_items_updated
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'po_items_updated', 'status', 'completed',
        'count', jsonb_array_length(p_items),
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Step 4: inventory_lots_created
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'inventory_lots_created', 'status', 'completed',
        'count', v_total_accepted,
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Step 5: stock_movements_created
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'stock_movements_created', 'status', 'completed',
        'count', v_total_accepted,
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Step 6: back_orders_processed
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'back_orders_processed', 'status', 'completed',
        'count', v_bo_fulfilled_count,
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Update PO status based on receipt totals
    PERFORM public.update_po_status_from_receipt(p_purchase_order_id);

    -- Capture new PO status and check if fully received
    SELECT status, status = 'fully_received'
    INTO v_po_new_status, v_po_fully_received
    FROM public.purchase_orders WHERE id = p_purchase_order_id;

    -- Step 7: po_status_updated
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'po_status_updated', 'status', 'completed',
        'new_status', v_po_new_status,
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Audit log: PO status change (if any)
    IF v_po_new_status IS DISTINCT FROM v_po.status THEN
        PERFORM record_audit_log(
            'purchase_orders', p_purchase_order_id, 'UPDATE',
            jsonb_build_object('status', v_po.status),
            jsonb_build_object('status', v_po_new_status, 'gr_id', v_gr_id),
            p_received_by, 'user', p_profession_id, p_branch_id, NULL,
            'PO status updated from goods receipt'
        );
    END IF;

    -- Emit outbox event: goods_receipted
    INSERT INTO public.outbox_events (
        profession_id, aggregate_type, aggregate_id, event_type, payload
    )
    VALUES (
        p_profession_id, 'procurement_gr', v_gr_id,
        'procurement.goods_receipted',
        jsonb_build_object(
            'gr_id', v_gr_id,
            'gr_number', v_gr_number,
            'po_id', p_purchase_order_id,
            'po_number', v_po.po_number,
            'total_accepted', v_total_accepted,
            'received_by', p_received_by,
            'receipt_date', NOW(),
            'back_orders_fulfilled', v_bo_fulfilled_count
        )
    );

    -- Emit outbox event: po_fully_received (if applicable)
    IF v_po_fully_received THEN
        INSERT INTO public.outbox_events (
            profession_id, aggregate_type, aggregate_id, event_type, payload
        )
        VALUES (
            p_profession_id, 'procurement_po', p_purchase_order_id,
            'procurement.po_fully_received',
            jsonb_build_object(
                'po_id', p_purchase_order_id,
                'po_number', v_po.po_number,
                'gr_id', v_gr_id,
                'gr_number', v_gr_number,
                'total_accepted', v_total_accepted
            )
        );
    END IF;

    -- Step 8: outbox_events_emitted
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'outbox_events_emitted', 'status', 'completed',
        'count', 1 + CASE WHEN v_po_fully_received THEN 1 ELSE 0 END + v_bo_fulfilled_count,
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'started', v_steps);

    -- Return result
    SELECT jsonb_build_object(
        'gr_id', v_gr_id,
        'gr_number', v_gr_number,
        'po_id', p_purchase_order_id,
        'po_number', v_po.po_number,
        'total_accepted', v_total_accepted,
        'status', 'completed'
    ) INTO v_result;

    -- Store idempotency key with response for duplicate prevention
    IF p_idempotency_key IS NOT NULL THEN
        INSERT INTO public.idempotency_keys (idempotency_key, scope, profession_id, response_body)
        VALUES (p_idempotency_key, 'procurement_gr', p_profession_id, v_result)
        ON CONFLICT (idempotency_key, scope) DO NOTHING;
    END IF;

    -- Step 9: idempotency_stored
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'idempotency_stored', 'status', 'completed',
        'started_at', v_step_start, 'completed_at', NOW()
    );

    -- Step 10: audit_logs_recorded + finalize
    v_step_start := NOW();
    v_steps := v_steps || jsonb_build_object(
        'step', 'audit_logs_recorded', 'status', 'completed',
        'count', 2,
        'started_at', v_step_start, 'completed_at', NOW()
    );
    PERFORM public.update_transaction_context(v_tx_context_id, 'committed', v_steps, NOW());

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    IF v_tx_context_id IS NOT NULL THEN
        PERFORM public.update_transaction_context(v_tx_context_id, 'failed', v_steps, NOW());
    END IF;
    RAISE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3. update_po_status_from_receipt(p_purchase_order_id)
--    Recalculates PO status by comparing ordered vs received quantities
--    across all PO items. Updates PO status accordingly.
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_po_status_from_receipt(
    p_purchase_order_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_all_received BOOLEAN;
    v_any_received BOOLEAN;
    v_po_status    TEXT;
BEGIN
    -- Check if all items are fully received
    SELECT
        BOOL_AND(quantity_ordered <= quantity_received),
        BOOL_OR(quantity_received > 0)
    INTO v_all_received, v_any_received
    FROM public.purchase_order_items
    WHERE po_id = p_purchase_order_id;

    -- Determine new status
    IF v_all_received THEN
        v_po_status := 'fully_received';
    ELSIF v_any_received THEN
        v_po_status := 'partially_received';
    ELSE
        -- No items received yet — keep current status (don't downgrade)
        RETURN;
    END IF;

    -- Update PO status (only upgrade, never downgrade from fully_received)
    UPDATE public.purchase_orders
    SET status = v_po_status
    WHERE id = p_purchase_order_id
      AND status NOT IN ('cancelled', 'fully_received');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 4. approve_purchase_requisition(p_requisition_id, p_approved_by)
--    Approves a PR: changes status from pending_approval → approved
-- ============================================================
CREATE OR REPLACE FUNCTION public.approve_purchase_requisition(
    p_requisition_id UUID,
    p_approved_by    UUID
)
RETURNS VOID AS $$
DECLARE
    v_pr public.purchase_requisitions%ROWTYPE;
BEGIN
    SELECT * INTO v_pr FROM public.purchase_requisitions WHERE id = p_requisition_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PR not found: %', p_requisition_id;
    END IF;

    IF v_pr.status != 'pending_approval' THEN
        RAISE EXCEPTION 'PR must be in pending_approval status. Current status: %', v_pr.status;
    END IF;

    UPDATE public.purchase_requisitions
    SET status = 'approved',
        approved_by = p_approved_by,
        approved_at = NOW()
    WHERE id = p_requisition_id
      AND status = 'pending_approval';

    -- Emit outbox event: pr_approved
    INSERT INTO public.outbox_events (
        profession_id, aggregate_type, aggregate_id, event_type, payload
    )
    VALUES (
        v_pr.profession_id, 'procurement_pr', p_requisition_id,
        'procurement.pr_approved',
        jsonb_build_object(
            'pr_id', p_requisition_id,
            'pr_number', v_pr.pr_number,
            'approved_by', p_approved_by,
            'approved_at', NOW(),
            'total_amount', v_pr.total_amount
        )
    );

    -- Audit log
    PERFORM record_audit_log(
        'purchase_requisitions', p_requisition_id, 'UPDATE',
        jsonb_build_object('status', v_pr.status),
        jsonb_build_object('status', 'approved', 'approved_by', p_approved_by),
        p_approved_by, 'user', v_pr.profession_id, v_pr.branch_id, NULL,
        'PR approved'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. reject_purchase_requisition(p_requisition_id, p_rejected_by, p_reason)
--    Rejects a PR: changes status to rejected
-- ============================================================
CREATE OR REPLACE FUNCTION public.reject_purchase_requisition(
    p_requisition_id UUID,
    p_rejected_by    UUID,
    p_reason         TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_pr public.purchase_requisitions%ROWTYPE;
BEGIN
    SELECT * INTO v_pr FROM public.purchase_requisitions WHERE id = p_requisition_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PR not found: %', p_requisition_id;
    END IF;

    IF v_pr.status NOT IN ('draft', 'pending_approval') THEN
        RAISE EXCEPTION 'PR must be in draft or pending_approval status. Current status: %', v_pr.status;
    END IF;

    UPDATE public.purchase_requisitions
    SET status = 'rejected',
        approved_by = p_rejected_by,
        approved_at = NOW(),
        notes = COALESCE(p_reason, notes)
    WHERE id = p_requisition_id
      AND status IN ('draft', 'pending_approval');

    -- Audit log
    PERFORM record_audit_log(
        'purchase_requisitions', p_requisition_id, 'UPDATE',
        jsonb_build_object('status', v_pr.status),
        jsonb_build_object('status', 'rejected', 'reason', p_reason),
        p_rejected_by, 'user', v_pr.profession_id, v_pr.branch_id, NULL,
        'PR rejected'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. convert_pr_to_po(p_requisition_id, p_supplier_id, p_created_by)
--    Converts an approved PR into a PO with line items.
--    Reads PR items from purchase_requisition_items table.
--    Returns the new PO record as JSON.
-- ============================================================
DROP FUNCTION IF EXISTS public.convert_pr_to_po(UUID, UUID, UUID, JSONB, UUID, TEXT);

CREATE OR REPLACE FUNCTION public.convert_pr_to_po(
    p_requisition_id UUID,
    p_supplier_id    UUID,
    p_created_by     UUID,
    p_branch_id      UUID DEFAULT NULL,
    p_notes          TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_pr                  public.purchase_requisitions%ROWTYPE;
    v_po_id               UUID;
    v_po_number           TEXT;
    v_pr_item             public.purchase_requisition_items%ROWTYPE;
    v_total_amount        DECIMAL(12,2) := 0;
    v_tax_amount          DECIMAL(12,2) := 0;
    v_grand_total         DECIMAL(12,2) := 0;
    v_line_total          DECIMAL(12,2);
    v_result              JSONB;
    v_enable_price_history BOOLEAN := false;
    v_po_item_id          UUID;
BEGIN
    -- Load PR
    SELECT * INTO v_pr
    FROM public.purchase_requisitions
    WHERE id = p_requisition_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PR not found: %', p_requisition_id;
    END IF;

    IF v_pr.status != 'approved' THEN
        RAISE EXCEPTION 'PR must be approved before conversion. Current status: %', v_pr.status;
    END IF;

    -- Check PR has items
    IF NOT EXISTS (SELECT 1 FROM public.purchase_requisition_items WHERE requisition_id = p_requisition_id) THEN
        RAISE EXCEPTION 'PR has no items. Add items before converting to PO.';
    END IF;

    -- Check if price history tracking is enabled (mode B)
    SELECT COALESCE(enable_price_history_tracking, false)
    INTO v_enable_price_history
    FROM public.procurement_settings
    WHERE profession_id = v_pr.profession_id;

    -- Generate PO number
    v_po_number := public.generate_document_number(v_pr.profession_id, p_branch_id, 'PO');

    -- Calculate totals from PR items in DB
    FOR v_pr_item IN
        SELECT * FROM public.purchase_requisition_items
        WHERE requisition_id = p_requisition_id
        ORDER BY created_at
    LOOP
        v_line_total := COALESCE(v_pr_item.quantity_requested, 0) *
                        COALESCE(v_pr_item.estimated_unit_price, 0);
        v_total_amount := v_total_amount + v_line_total;
    END LOOP;

    -- Calculate VAT (7% by default)
    v_tax_amount := v_total_amount * 0.07;
    v_grand_total := v_total_amount + v_tax_amount;

    -- Create PO
    INSERT INTO public.purchase_orders (
        profession_id, branch_id, supplier_id, pr_id,
        po_number, status, total_amount, tax_amount, grand_total, notes
    )
    VALUES (
        v_pr.profession_id, COALESCE(p_branch_id, v_pr.branch_id), p_supplier_id, p_requisition_id,
        v_po_number, 'draft', v_total_amount, v_tax_amount, v_grand_total, p_notes
    )
    RETURNING id INTO v_po_id;

    -- Create PO items from PR items in DB
    FOR v_pr_item IN
        SELECT * FROM public.purchase_requisition_items
        WHERE requisition_id = p_requisition_id
        ORDER BY created_at
    LOOP
        v_line_total := COALESCE(v_pr_item.quantity_requested, 0) *
                        COALESCE(v_pr_item.estimated_unit_price, 0);

        INSERT INTO public.purchase_order_items (
            po_id, product_id, quantity_ordered, quantity_received,
            unit_price, total_price, notes
        )
        VALUES (
            v_po_id,
            v_pr_item.product_id,
            v_pr_item.quantity_requested,
            0,
            COALESCE(v_pr_item.estimated_unit_price, 0),
            v_line_total,
            v_pr_item.notes
        )
        RETURNING id INTO v_po_item_id;

        -- Record price history if mode B is enabled
        IF v_enable_price_history AND v_pr_item.estimated_unit_price IS NOT NULL THEN
            PERFORM public.record_supplier_price_history(
                v_pr.profession_id,
                p_supplier_id,
                v_pr_item.product_id,
                v_pr_item.estimated_unit_price,
                v_po_id,
                v_po_item_id,
                'Recorded from PR→PO conversion'
            );
        END IF;
    END LOOP;

    -- Mark PR as converted
    UPDATE public.purchase_requisitions
    SET status = 'converted'
    WHERE id = p_requisition_id;

    -- Audit log: PR status change
    PERFORM record_audit_log(
        'purchase_requisitions', p_requisition_id, 'UPDATE',
        jsonb_build_object('status', 'approved'),
        jsonb_build_object('status', 'converted'),
        p_created_by, 'user', v_pr.profession_id, NULL, NULL,
        'PR converted to PO'
    );

    -- Audit log: PO creation
    PERFORM record_audit_log(
        'purchase_orders', v_po_id, 'INSERT',
        NULL, jsonb_build_object('po_number', v_po_number, 'pr_id', p_requisition_id, 'total_amount', v_total_amount),
        p_created_by, 'user', v_pr.profession_id, NULL, NULL,
        'PO created from PR'
    );

    -- Emit outbox event for PR conversion
    INSERT INTO public.outbox_events (
        profession_id, aggregate_type, aggregate_id, event_type, payload
    )
    VALUES (
        v_pr.profession_id, 'procurement_po', v_po_id,
        'procurement.pr_converted_to_po',
        jsonb_build_object(
            'pr_id', p_requisition_id,
            'pr_number', v_pr.pr_number,
            'po_id', v_po_id,
            'po_number', v_po_number,
            'supplier_id', p_supplier_id,
            'total_amount', v_total_amount,
            'grand_total', v_grand_total,
            'created_by', p_created_by
        )
    );

    -- Return result
    SELECT jsonb_build_object(
        'po_id', v_po_id,
        'po_number', v_po_number,
        'pr_id', p_requisition_id,
        'pr_number', v_pr.pr_number,
        'total_amount', v_total_amount,
        'tax_amount', v_tax_amount,
        'grand_total', v_grand_total,
        'status', 'draft'
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 7. send_purchase_order(p_po_id, p_sent_by)
--    Updates PO status to 'sent' and emits outbox event.
--    Returns TRUE on success.
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_purchase_order(
    p_po_id    UUID,
    p_sent_by  UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_po public.purchase_orders%ROWTYPE;
BEGIN
    SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'PO not found: %', p_po_id;
    END IF;

    IF v_po.status NOT IN ('draft', 'approved') THEN
        RAISE EXCEPTION 'PO must be in draft or approved status to send. Current: %', v_po.status;
    END IF;

    UPDATE public.purchase_orders
    SET status = 'sent', updated_at = NOW()
    WHERE id = p_po_id;

    -- Audit log: PO sent
    PERFORM record_audit_log(
        'purchase_orders', p_po_id, 'UPDATE',
        jsonb_build_object('status', v_po.status),
        jsonb_build_object('status', 'sent'),
        p_sent_by, 'user', v_po.profession_id, NULL, NULL,
        'PO sent to supplier'
    );

    INSERT INTO public.outbox_events (
        profession_id, aggregate_type, aggregate_id, event_type, payload
    )
    VALUES (
        v_po.profession_id, 'procurement_po', p_po_id,
        'procurement.po_sent',
        jsonb_build_object(
            'po_id', p_po_id,
            'po_number', v_po.po_number,
            'supplier_id', v_po.supplier_id,
            'sent_by', p_sent_by,
            'sent_at', NOW(),
            'total_amount', v_po.total_amount,
            'grand_total', v_po.grand_total
        )
    );

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
