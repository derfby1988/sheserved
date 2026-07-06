-- Migration: Procurement Step 3 — RPC Functions (Auto-Reorder & Price History)
-- Date: 2026-07-03
-- Prerequisites: 20260701170000_procurement_step_3_tables.sql, 20260701140000_procurement_step_2_rpc_functions.sql
-- Functions:
--   1. check_reorder_points(p_profession_id, p_branch_id)
--   2. confirm_reorder_suggestion(p_id, p_confirmed_by)
--   3. convert_reorder_to_pr(p_id, p_created_by)
--   4. record_supplier_price_history(...)
--   5. get_supplier_price_history(p_profession_id, p_supplier_id, p_product_id, p_limit)
--   6. get_latest_supplier_price(p_profession_id, p_supplier_id, p_product_id)
--   7. reject_reorder_suggestion(p_id, p_rejected_by, p_reason)

-- ============================================================
-- 1. check_reorder_points(p_profession_id, p_branch_id)
--    Scans inventory_items for low stock and creates reorder_suggestions.
--    Uses procurement_settings.auto_reorder_threshold_multiplier.
--    Skips products that already have a pending suggestion.
--    Emits outbox event for each new suggestion.
--    Returns JSONB with count of new suggestions.
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_reorder_points(
    p_profession_id  UUID,
    p_branch_id      UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_multiplier    DECIMAL(3,2) := 1.0;
    v_new_count     INTEGER := 0;
    v_suggestion_id UUID;
    v_product_name  TEXT;
    v_rec           RECORD;
BEGIN
    -- Get threshold multiplier from procurement_settings
    SELECT COALESCE(auto_reorder_threshold_multiplier, 1.0)
    INTO v_multiplier
    FROM public.procurement_settings
    WHERE profession_id = p_profession_id;

    IF v_multiplier IS NULL THEN
        v_multiplier := 1.0;
    END IF;

    -- Scan inventory_items for low stock
    FOR v_rec IN
        SELECT
            ii.id AS inventory_item_id,
            ii.product_id,
            ii.branch_id,
            ii.quantity,
            ii.reorder_point,
            ii.reorder_qty,
            COALESCE(p.name, '') AS product_name
        FROM public.inventory_items ii
        LEFT JOIN public.products p ON p.id = ii.product_id
        WHERE ii.profession_id = p_profession_id
          AND ii.is_active = true
          AND ii.product_id IS NOT NULL
          AND ii.quantity <= (ii.reorder_point * v_multiplier)
          AND (p_branch_id IS NULL OR ii.branch_id = p_branch_id)
          -- Skip if there's already a pending suggestion for this product
          AND NOT EXISTS (
              SELECT 1 FROM public.reorder_suggestions rs
              WHERE rs.profession_id = p_profession_id
                AND rs.product_id = ii.product_id
                AND rs.status = 'pending'
                AND (p_branch_id IS NULL OR rs.branch_id = ii.branch_id)
          )
    LOOP
        -- Create reorder suggestion
        INSERT INTO public.reorder_suggestions (
            profession_id, branch_id, product_id,
            current_quantity, reorder_point, suggested_quantity,
            preferred_supplier_id, reason, status
        )
        VALUES (
            p_profession_id, v_rec.branch_id, v_rec.product_id,
            v_rec.quantity, v_rec.reorder_point,
            GREATEST(v_rec.reorder_qty, v_rec.reorder_point - v_rec.quantity),
            NULL, 'below_reorder_point', 'pending'
        )
        RETURNING id INTO v_suggestion_id;

        v_new_count := v_new_count + 1;

        -- Emit outbox event: reorder_suggestion_created
        INSERT INTO public.outbox_events (
            profession_id, aggregate_type, aggregate_id, event_type, payload
        )
        VALUES (
            p_profession_id, 'reorder_suggestion', v_suggestion_id,
            'procurement.reorder_suggestion_created',
            jsonb_build_object(
                'suggestion_id', v_suggestion_id,
                'product_id', v_rec.product_id,
                'product_name', v_rec.product_name,
                'current_quantity', v_rec.quantity,
                'reorder_point', v_rec.reorder_point,
                'suggested_quantity', GREATEST(v_rec.reorder_qty, v_rec.reorder_point - v_rec.quantity),
                'branch_id', v_rec.branch_id
            )
        );
    END LOOP;

    RETURN jsonb_build_object(
        'new_suggestions', v_new_count,
        'profession_id', p_profession_id,
        'branch_id', p_branch_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 2. confirm_reorder_suggestion(p_id, p_confirmed_by)
--    Confirms a pending reorder suggestion.
--    Status: pending → confirmed
-- ============================================================
CREATE OR REPLACE FUNCTION public.confirm_reorder_suggestion(
    p_id            UUID,
    p_confirmed_by  UUID
)
RETURNS VOID AS $$
DECLARE
    v_rs public.reorder_suggestions%ROWTYPE;
BEGIN
    SELECT * INTO v_rs FROM public.reorder_suggestions WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reorder suggestion not found: %', p_id;
    END IF;

    IF v_rs.status != 'pending' THEN
        RAISE EXCEPTION 'Reorder suggestion must be in pending status. Current: %', v_rs.status;
    END IF;

    UPDATE public.reorder_suggestions
    SET status = 'confirmed',
        confirmed_by = p_confirmed_by,
        confirmed_at = NOW()
    WHERE id = p_id AND status = 'pending';

    -- Audit log
    PERFORM record_audit_log(
        'reorder_suggestions', p_id, 'UPDATE',
        jsonb_build_object('status', 'pending'),
        jsonb_build_object('status', 'confirmed', 'confirmed_by', p_confirmed_by),
        p_confirmed_by, 'user', v_rs.profession_id, v_rs.branch_id, NULL,
        'Reorder suggestion confirmed'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3. reject_reorder_suggestion(p_id, p_rejected_by, p_reason)
--    Rejects a pending reorder suggestion.
--    Status: pending → rejected
-- ============================================================
CREATE OR REPLACE FUNCTION public.reject_reorder_suggestion(
    p_id            UUID,
    p_rejected_by   UUID,
    p_reason        TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_rs public.reorder_suggestions%ROWTYPE;
BEGIN
    SELECT * INTO v_rs FROM public.reorder_suggestions WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reorder suggestion not found: %', p_id;
    END IF;

    IF v_rs.status != 'pending' THEN
        RAISE EXCEPTION 'Reorder suggestion must be in pending status. Current: %', v_rs.status;
    END IF;

    UPDATE public.reorder_suggestions
    SET status = 'rejected'
    WHERE id = p_id AND status = 'pending';

    -- Audit log
    PERFORM record_audit_log(
        'reorder_suggestions', p_id, 'UPDATE',
        jsonb_build_object('status', 'pending'),
        jsonb_build_object('status', 'rejected', 'reason', p_reason),
        p_rejected_by, 'user', v_rs.profession_id, v_rs.branch_id, NULL,
        'Reorder suggestion rejected'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 4. convert_reorder_to_pr(p_id, p_created_by)
--    Converts a confirmed reorder suggestion into a Purchase Requisition.
--    Creates PR + PR item, marks suggestion as converted_to_pr.
--    Returns the new PR record as JSON.
-- ============================================================
CREATE OR REPLACE FUNCTION public.convert_reorder_to_pr(
    p_id          UUID,
    p_created_by  UUID
)
RETURNS JSONB AS $$
DECLARE
    v_rs            public.reorder_suggestions%ROWTYPE;
    v_pr_id         UUID;
    v_pr_number     TEXT;
    v_product       public.products%ROWTYPE;
    v_result        JSONB;
BEGIN
    SELECT * INTO v_rs FROM public.reorder_suggestions WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reorder suggestion not found: %', p_id;
    END IF;

    IF v_rs.status != 'confirmed' THEN
        RAISE EXCEPTION 'Reorder suggestion must be confirmed before conversion. Current: %', v_rs.status;
    END IF;

    -- Load product for item name
    SELECT * INTO v_product FROM public.products WHERE id = v_rs.product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found: %', v_rs.product_id;
    END IF;

    -- Generate PR number
    v_pr_number := public.generate_document_number(v_rs.profession_id, v_rs.branch_id, 'PR');

    -- Create PR
    INSERT INTO public.purchase_requisitions (
        profession_id, branch_id, pr_number, status,
        requester_id, notes
    )
    VALUES (
        v_rs.profession_id, v_rs.branch_id, v_pr_number, 'draft',
        p_created_by, 'Auto-generated from reorder suggestion'
    )
    RETURNING id INTO v_pr_id;

    -- Create PR item
    INSERT INTO public.purchase_requisition_items (
        profession_id, requisition_id, product_id,
        item_name, quantity_requested,
        estimated_unit_price, estimated_total_price, notes
    )
    VALUES (
        v_rs.profession_id, v_pr_id, v_rs.product_id,
        v_product.name, v_rs.suggested_quantity,
        v_product.cost_price, v_product.cost_price * v_rs.suggested_quantity,
        'From reorder suggestion (stock was ' || v_rs.current_quantity || ', reorder point ' || v_rs.reorder_point || ')'
    );

    -- Mark suggestion as converted
    UPDATE public.reorder_suggestions
    SET status = 'converted_to_pr',
        converted_pr_id = v_pr_id
    WHERE id = p_id AND status = 'confirmed';

    -- Audit log: PR creation
    PERFORM record_audit_log(
        'purchase_requisitions', v_pr_id, 'INSERT',
        NULL, jsonb_build_object('pr_number', v_pr_number, 'from_reorder_suggestion', p_id),
        p_created_by, 'user', v_rs.profession_id, v_rs.branch_id, NULL,
        'PR created from reorder suggestion'
    );

    -- Audit log: suggestion conversion
    PERFORM record_audit_log(
        'reorder_suggestions', p_id, 'UPDATE',
        jsonb_build_object('status', 'confirmed'),
        jsonb_build_object('status', 'converted_to_pr', 'converted_pr_id', v_pr_id),
        p_created_by, 'user', v_rs.profession_id, v_rs.branch_id, NULL,
        'Reorder suggestion converted to PR'
    );

    -- Return result
    SELECT jsonb_build_object(
        'pr_id', v_pr_id,
        'pr_number', v_pr_number,
        'suggestion_id', p_id,
        'product_id', v_rs.product_id,
        'product_name', v_product.name,
        'suggested_quantity', v_rs.suggested_quantity,
        'status', 'draft'
    ) INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. record_supplier_price_history(...)
--    Records a price entry in supplier_price_history.
--    Called from convert_pr_to_po when mode B is enabled.
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_supplier_price_history(
    p_profession_id  UUID,
    p_supplier_id    UUID,
    p_product_id     UUID,
    p_unit_price     DECIMAL(12,2),
    p_po_id          UUID DEFAULT NULL,
    p_po_item_id     UUID DEFAULT NULL,
    p_notes          TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.supplier_price_history (
        profession_id, supplier_id, product_id,
        unit_price, effective_date, po_id, po_item_id, notes
    )
    VALUES (
        p_profession_id, p_supplier_id, p_product_id,
        p_unit_price, CURRENT_DATE, p_po_id, p_po_item_id, p_notes
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. get_supplier_price_history(p_profession_id, p_supplier_id, p_product_id, p_limit)
--    Returns price history entries for a supplier/product combination.
--    If p_supplier_id is NULL, returns history for all suppliers for that product.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_supplier_price_history(
    p_profession_id  UUID,
    p_supplier_id    UUID DEFAULT NULL,
    p_product_id     UUID DEFAULT NULL,
    p_limit          INTEGER DEFAULT 20
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    INTO v_result
    FROM (
        SELECT
            sph.id,
            sph.supplier_id,
            s.supplier_name,
            sph.product_id,
            p.name AS product_name,
            sph.unit_price,
            sph.effective_date,
            sph.po_id,
            sph.notes,
            sph.created_at
        FROM public.supplier_price_history sph
        LEFT JOIN public.suppliers s ON s.id = sph.supplier_id
        LEFT JOIN public.products p ON p.id = sph.product_id
        WHERE sph.profession_id = p_profession_id
          AND (p_supplier_id IS NULL OR sph.supplier_id = p_supplier_id)
          AND (p_product_id IS NULL OR sph.product_id = p_product_id)
        ORDER BY sph.effective_date DESC, sph.created_at DESC
        LIMIT LEAST(p_limit, 100)
    ) t;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 7. get_latest_supplier_price(p_profession_id, p_supplier_id, p_product_id)
--    Returns the most recent price for a supplier/product combination.
--    Returns NULL if no history exists.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_latest_supplier_price(
    p_profession_id  UUID,
    p_supplier_id    UUID,
    p_product_id     UUID
)
RETURNS DECIMAL(12,2) AS $$
DECLARE
    v_price DECIMAL(12,2);
BEGIN
    SELECT unit_price INTO v_price
    FROM public.supplier_price_history
    WHERE profession_id = p_profession_id
      AND supplier_id = p_supplier_id
      AND product_id = p_product_id
    ORDER BY effective_date DESC, created_at DESC
    LIMIT 1;

    RETURN v_price;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
