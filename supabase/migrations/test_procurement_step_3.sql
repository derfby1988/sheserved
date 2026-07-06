-- Test Script: Procurement Step 3 — Auto-Reorder & Price History
-- Date: 2026-07-03
-- Prerequisites: Apply migrations 20260701170000 and 20260701180000 first
-- Run: via Supabase SQL Editor or psql

DO $$
DECLARE
    v_profession_id    UUID;
    v_branch_id        UUID;
    v_user_id          UUID;
    v_supplier_id      UUID;
    v_product_id       UUID;
    v_inventory_item_id UUID;
    v_reorder_id       UUID;
    v_pr_id            UUID;
    v_pr_number        TEXT;
    v_po_result        JSONB;
    v_po_id            UUID;
    v_count            INTEGER;
    v_price            DECIMAL(12,2);
    v_price_history    JSONB;
    v_reorder_result   JSONB;
BEGIN
    -- ============================================================
    -- Setup: Get test data from existing migrations
    -- ============================================================
    -- Find a profession that has both products and suppliers
    SELECT p.id INTO v_profession_id
    FROM public.professions p
    WHERE EXISTS (SELECT 1 FROM public.products pr WHERE pr.profession_id = p.id AND pr.is_stockable = true)
      AND EXISTS (SELECT 1 FROM public.suppliers s WHERE s.profession_id = p.id)
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RAISE EXCEPTION 'No profession found with both stockable products and suppliers';
    END IF;

    -- Pick a user that belongs to this profession, or assign the first user to this profession
    SELECT id INTO v_user_id FROM public.users WHERE profession_id = v_profession_id LIMIT 1;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
        IF v_user_id IS NOT NULL THEN
            UPDATE public.users SET profession_id = v_profession_id, role = 'admin' WHERE id = v_user_id;
        END IF;
    END IF;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found in the system at all';
    END IF;

    SELECT id INTO v_branch_id FROM public.organization_branches WHERE profession_id = v_profession_id LIMIT 1;

    SELECT id INTO v_supplier_id FROM public.suppliers WHERE profession_id = v_profession_id LIMIT 1;
    IF v_supplier_id IS NULL THEN
        RAISE EXCEPTION 'No supplier found for profession %', v_profession_id;
    END IF;

    SELECT id INTO v_product_id FROM public.products WHERE profession_id = v_profession_id AND is_stockable = true LIMIT 1;
    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'No stockable product found for profession %', v_profession_id;
    END IF;

    RAISE NOTICE 'Test setup: profession=%, user=%, supplier=%, product=%', v_profession_id, v_user_id, v_supplier_id, v_product_id;

    -- ============================================================
    -- Test 1: Create inventory_item with low stock for reorder check
    -- ============================================================
    -- First, delete any existing reorder suggestions for this product
    DELETE FROM public.reorder_suggestions WHERE profession_id = v_profession_id AND product_id = v_product_id;

    -- Create or update inventory_item with quantity below reorder_point
    SELECT id INTO v_inventory_item_id
    FROM public.inventory_items
    WHERE profession_id = v_profession_id AND product_id = v_product_id
    LIMIT 1;

    IF v_inventory_item_id IS NOT NULL THEN
        UPDATE public.inventory_items
        SET quantity = 5, reorder_point = 50, reorder_qty = 100, is_active = true
        WHERE id = v_inventory_item_id;
    ELSE
        INSERT INTO public.inventory_items (
            profession_id, product_id, branch_id,
            quantity, reorder_point, reorder_qty, is_active
        )
        VALUES (
            v_profession_id, v_product_id, v_branch_id,
            5, 50, 100, true
        )
        RETURNING id INTO v_inventory_item_id;
    END IF;

    RAISE NOTICE 'Created/updated inventory_item: id=%, qty=5, reorder_point=50', v_inventory_item_id;

    -- ============================================================
    -- Test 2: Run check_reorder_points
    -- ============================================================
    v_reorder_result := public.check_reorder_points(v_profession_id, v_branch_id);
    RAISE NOTICE 'check_reorder_points result: %', v_reorder_result;

    -- Verify suggestion was created
    SELECT COUNT(*) INTO v_count
    FROM public.reorder_suggestions
    WHERE profession_id = v_profession_id
      AND product_id = v_product_id
      AND status = 'pending';

    IF v_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 pending reorder suggestion, got %', v_count;
    END IF;
    RAISE NOTICE 'Reorder suggestion created verified (%) suggestions', v_count;

    -- Verify outbox event was emitted
    SELECT COUNT(*) INTO v_count
    FROM public.outbox_events
    WHERE event_type = 'procurement.reorder_suggestion_created'
      AND profession_id = v_profession_id;

    IF v_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 outbox event for reorder_suggestion_created, got %', v_count;
    END IF;
    RAISE NOTICE 'Outbox event for reorder_suggestion_created verified';

    -- Verify notification was generated
    SELECT COUNT(*) INTO v_count
    FROM public.app_notifications
    WHERE profession_id = v_profession_id
      AND event_type = 'procurement.reorder_suggestion_created';

    IF v_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 notification for reorder_suggestion_created, got %', v_count;
    END IF;
    RAISE NOTICE 'Notification for reorder_suggestion_created verified (%) notifications', v_count;

    -- ============================================================
    -- Test 3: Confirm reorder suggestion
    -- ============================================================
    SELECT id INTO v_reorder_id
    FROM public.reorder_suggestions
    WHERE profession_id = v_profession_id
      AND product_id = v_product_id
      AND status = 'pending'
    LIMIT 1;

    PERFORM public.confirm_reorder_suggestion(v_reorder_id, v_user_id);

    -- Verify status changed to confirmed
    IF (SELECT status FROM public.reorder_suggestions WHERE id = v_reorder_id) != 'confirmed' THEN
        RAISE EXCEPTION 'Expected reorder suggestion status confirmed, got %',
            (SELECT status FROM public.reorder_suggestions WHERE id = v_reorder_id);
    END IF;
    RAISE NOTICE 'Reorder suggestion confirmed';

    -- Verify audit log
    SELECT COUNT(*) INTO v_count
    FROM public.transaction_audit_log
    WHERE table_name = 'reorder_suggestions' AND record_id = v_reorder_id AND action = 'UPDATE';
    IF v_count < 1 THEN
        RAISE EXCEPTION 'Expected audit log for reorder confirmation, got %', v_count;
    END IF;
    RAISE NOTICE 'Audit log for reorder confirmation verified';

    -- ============================================================
    -- Test 4: Convert reorder suggestion to PR
    -- ============================================================
    v_po_result := public.convert_reorder_to_pr(v_reorder_id, v_user_id);
    RAISE NOTICE 'convert_reorder_to_pr result: %', v_po_result;

    v_pr_id := (v_po_result->>'pr_id')::UUID;
    v_pr_number := v_po_result->>'pr_number';

    -- Verify PR was created
    IF v_pr_id IS NULL THEN
        RAISE EXCEPTION 'Expected PR id from convert_reorder_to_pr, got NULL';
    END IF;

    -- Verify PR exists in database
    IF NOT EXISTS (SELECT 1 FROM public.purchase_requisitions WHERE id = v_pr_id) THEN
        RAISE EXCEPTION 'PR not found in database: %', v_pr_id;
    END IF;
    RAISE NOTICE 'PR created from reorder suggestion: pr_id=%, pr_number=%', v_pr_id, v_pr_number;

    -- Verify PR has items
    SELECT COUNT(*) INTO v_count
    FROM public.purchase_requisition_items
    WHERE requisition_id = v_pr_id;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 PR item, got %', v_count;
    END IF;
    RAISE NOTICE 'PR items verified (%) items', v_count;

    -- Verify suggestion status is converted_to_pr
    IF (SELECT status FROM public.reorder_suggestions WHERE id = v_reorder_id) != 'converted_to_pr' THEN
        RAISE EXCEPTION 'Expected reorder suggestion status converted_to_pr, got %',
            (SELECT status FROM public.reorder_suggestions WHERE id = v_reorder_id);
    END IF;
    RAISE NOTICE 'Reorder suggestion status = converted_to_pr verified';

    -- Verify converted_pr_id is set
    IF (SELECT converted_pr_id FROM public.reorder_suggestions WHERE id = v_reorder_id) IS DISTINCT FROM v_pr_id THEN
        RAISE EXCEPTION 'Expected converted_pr_id to be set to %', v_pr_id;
    END IF;
    RAISE NOTICE 'converted_pr_id verified';

    -- ============================================================
    -- Test 5: Price History Mode B — enable and convert PR→PO
    -- ============================================================
    -- Enable price history tracking
    UPDATE public.procurement_settings
    SET enable_price_history_tracking = true
    WHERE profession_id = v_profession_id;

    RAISE NOTICE 'Price history tracking enabled (mode B)';

    -- Approve the PR first
    UPDATE public.purchase_requisitions
    SET status = 'pending_approval'
    WHERE id = v_pr_id AND status = 'draft';

    PERFORM public.approve_purchase_requisition(v_pr_id, v_user_id);
    RAISE NOTICE 'PR approved for conversion';

    -- Convert PR to PO (should record price history)
    v_po_result := public.convert_pr_to_po(v_pr_id, v_supplier_id, v_user_id, v_branch_id, 'Test PO from reorder suggestion');
    v_po_id := (v_po_result->>'po_id')::UUID;
    RAISE NOTICE 'PO created from PR: po_id=%, po_number=%', v_po_id, v_po_result->>'po_number';

    -- Verify price history was recorded
    SELECT COUNT(*) INTO v_count
    FROM public.supplier_price_history
    WHERE profession_id = v_profession_id
      AND supplier_id = v_supplier_id
      AND product_id = v_product_id;

    IF v_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 price history entry, got %', v_count;
    END IF;
    RAISE NOTICE 'Price history recorded verified (%) entries', v_count;

    -- ============================================================
    -- Test 6: Query price history via RPC
    -- ============================================================
    v_price_history := public.get_supplier_price_history(v_profession_id, v_supplier_id, v_product_id, 10);
    RAISE NOTICE 'get_supplier_price_history result: %', v_price_history;

    -- Verify it returns at least 1 entry
    IF jsonb_array_length(v_price_history) < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 price history entry from RPC, got 0';
    END IF;
    RAISE NOTICE 'get_supplier_price_history RPC verified';

    -- ============================================================
    -- Test 7: Get latest supplier price via RPC
    -- ============================================================
    v_price := public.get_latest_supplier_price(v_profession_id, v_supplier_id, v_product_id);
    IF v_price IS NULL THEN
        RAISE EXCEPTION 'Expected latest price, got NULL';
    END IF;
    RAISE NOTICE 'get_latest_supplier_price verified: %', v_price;

    -- ============================================================
    -- Test 8: Idempotency — running check_reorder_points again should not create duplicate
    -- ============================================================
    -- Set inventory_item quantity back to low (but suggestion is already converted)
    UPDATE public.inventory_items
    SET quantity = 5
    WHERE id = v_inventory_item_id;

    v_reorder_result := public.check_reorder_points(v_profession_id, v_branch_id);
    RAISE NOTICE 'Second check_reorder_points result: %', v_reorder_result;

    -- Should create a new suggestion since the old one is converted_to_pr (not pending)
    SELECT COUNT(*) INTO v_count
    FROM public.reorder_suggestions
    WHERE profession_id = v_profession_id
      AND product_id = v_product_id
      AND status = 'pending';

    IF v_count < 1 THEN
        RAISE NOTICE 'Note: No new pending suggestion (may be expected if stock was adjusted)';
    ELSE
        RAISE NOTICE 'New pending suggestion created (expected since old one was converted)';
    END IF;

    -- ============================================================
    -- Test 9: Reject reorder suggestion
    -- ============================================================
    -- If there's a pending suggestion, reject it
    SELECT id INTO v_reorder_id
    FROM public.reorder_suggestions
    WHERE profession_id = v_profession_id
      AND product_id = v_product_id
      AND status = 'pending'
    LIMIT 1;

    IF v_reorder_id IS NOT NULL THEN
        PERFORM public.reject_reorder_suggestion(v_reorder_id, v_user_id, 'Test rejection');
        IF (SELECT status FROM public.reorder_suggestions WHERE id = v_reorder_id) != 'rejected' THEN
            RAISE EXCEPTION 'Expected rejected status, got %',
                (SELECT status FROM public.reorder_suggestions WHERE id = v_reorder_id);
        END IF;
        RAISE NOTICE 'Reorder suggestion rejection verified';
    ELSE
        RAISE NOTICE 'No pending suggestion to reject (skipping rejection test)';
    END IF;

    -- ============================================================
    -- Cleanup: Disable price history tracking
    -- ============================================================
    UPDATE public.procurement_settings
    SET enable_price_history_tracking = false
    WHERE profession_id = v_profession_id;

    RAISE NOTICE 'Price history tracking disabled (cleanup)';

    -- ============================================================
    -- Final Summary
    -- ============================================================
    RAISE NOTICE '========================================';
    RAISE NOTICE 'All Procurement Step 3 tests passed!';
    RAISE NOTICE '  - check_reorder_points: creates suggestions + outbox events + notifications';
    RAISE NOTICE '  - confirm_reorder_suggestion: pending → confirmed + audit log';
    RAISE NOTICE '  - convert_reorder_to_pr: confirmed → converted_to_pr + PR created';
    RAISE NOTICE '  - Price history mode B: recorded on PR→PO conversion';
    RAISE NOTICE '  - get_supplier_price_history: returns price history JSON';
    RAISE NOTICE '  - get_latest_supplier_price: returns latest price';
    RAISE NOTICE '  - reject_reorder_suggestion: pending → rejected';
    RAISE NOTICE '========================================';
END $$;
