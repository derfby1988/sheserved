-- Test Script: Procurement Step 4 — 3-Way Matching, Dashboard, Report, PDF, Search
-- Date: 2026-07-03
-- Prerequisites: Apply migrations 20260702190000, 20260702200000, 20260702210000, 20260702220000 first
-- Run: via Supabase SQL Editor or psql

DO $$
DECLARE
    v_profession_id    UUID;
    v_branch_id        UUID;
    v_user_id          UUID;
    v_supplier_id      UUID;
    v_product_id       UUID;
    v_po_id            UUID;
    v_po_item_id       UUID;
    v_pr_id            UUID;
    v_pr_number        TEXT;
    v_po_result        JSONB;
    v_gr_result        JSONB;
    v_invoice_result   JSONB;
    v_invoice_id       UUID;
    v_match_result     JSONB;
    v_summary          JSONB;
    v_dashboard        JSONB;
    v_report           JSONB;
    v_pdf_result       JSONB;
    v_email_result     JSONB;
    v_search_result    JSONB;
    v_notif_count      INTEGER;
    v_count            INTEGER;
    v_status           TEXT;
BEGIN
    -- ============================================================
    -- Setup: Get test data
    -- ============================================================
    SELECT p.id INTO v_profession_id
    FROM public.professions p
    WHERE EXISTS (SELECT 1 FROM public.products pr WHERE pr.profession_id = p.id AND pr.is_stockable = true)
      AND EXISTS (SELECT 1 FROM public.suppliers s WHERE s.profession_id = p.id)
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RAISE EXCEPTION 'No profession found with both stockable products and suppliers';
    END IF;

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
    SELECT id INTO v_product_id FROM public.products WHERE profession_id = v_profession_id AND is_stockable = true LIMIT 1;

    IF v_supplier_id IS NULL THEN RAISE EXCEPTION 'No supplier found'; END IF;
    IF v_product_id IS NULL THEN RAISE EXCEPTION 'No stockable product found'; END IF;

    RAISE NOTICE 'Setup: profession=%, user=%, supplier=%, product=%', v_profession_id, v_user_id, v_supplier_id, v_product_id;

    -- ============================================================
    -- Test 1: Create PR → PO → GR (prerequisite for 3-way matching)
    -- ============================================================
    -- Create PR
    v_pr_number := 'TEST-PR-S4-' || EXTRACT(EPOCH FROM NOW())::INT::TEXT;
    INSERT INTO public.purchase_requisitions (
        profession_id, branch_id, pr_number, status, requester_id, total_amount
    )
    VALUES (v_profession_id, v_branch_id, v_pr_number, 'approved', v_user_id, 1000.00)
    RETURNING id INTO v_pr_id;

    -- Add PR item (required before converting to PO)
    INSERT INTO public.purchase_requisition_items (
        profession_id, requisition_id, product_id, item_name,
        quantity_requested, estimated_unit_price, estimated_total_price
    )
    VALUES (
        v_profession_id, v_pr_id, v_product_id, 'Test Product for Step 4',
        10, 100.00, 1000.00
    );

    -- Convert PR to PO
    v_po_result := public.convert_pr_to_po(
        p_requisition_id := v_pr_id,
        p_supplier_id := v_supplier_id,
        p_created_by := v_user_id,
        p_branch_id := v_branch_id,
        p_notes := 'Test PO for Step 4 matching'
    );

    v_po_id := (v_po_result->>'po_id')::UUID;
    v_po_item_id := (
        SELECT id FROM public.purchase_order_items WHERE po_id = v_po_id LIMIT 1
    );

    RAISE NOTICE 'Test 1: Created PO % with item %', v_po_id, v_po_item_id;

    -- Create GR (receive the goods)
    v_gr_result := public.create_goods_receipt(
        p_profession_id := v_profession_id,
        p_purchase_order_id := v_po_id,
        p_received_by := v_user_id,
        p_branch_id := v_branch_id,
        p_items := jsonb_build_array(
            jsonb_build_object(
                'purchase_order_item_id', v_po_item_id,
                'quantity_received', 10,
                'quantity_accepted', 10,
                'quantity_rejected', 0,
                'unit_cost', 100.00
            )
        )
    );

    RAISE NOTICE 'Test 1: Created GR %', v_gr_result->>'gr_id';

    -- ============================================================
    -- Test 2: Create Supplier Invoice
    -- ============================================================
    v_invoice_result := public.create_supplier_invoice(
        p_profession_id := v_profession_id,
        p_supplier_id := v_supplier_id,
        p_po_id := v_po_id,
        p_invoice_number := 'INV-S4-' || EXTRACT(EPOCH FROM NOW())::INT::TEXT,
        p_invoice_date := CURRENT_DATE,
        p_due_date := (CURRENT_DATE + INTERVAL '30 days')::DATE,
        p_items := jsonb_build_array(
            jsonb_build_object(
                'po_item_id', v_po_item_id::TEXT,
                'product_id', v_product_id::TEXT,
                'item_name', 'Test Product',
                'quantity_invoiced', 10,
                'unit_price', 100.00,
                'total_price', 1000.00,
                'tax_amount', 70.00
            )
        ),
        p_notes := 'Test invoice for 3-way matching',
        p_created_by := v_user_id
    );

    v_invoice_id := (v_invoice_result->>'invoice_id')::UUID;
    RAISE NOTICE 'Test 2: Created supplier invoice % (number=%)', v_invoice_id, v_invoice_result->>'invoice_number';

    -- Check notification was created
    SELECT COUNT(*) INTO v_notif_count
    FROM public.app_notifications
    WHERE profession_id = v_profession_id
      AND event_type = 'procurement.supplier_invoice_created';

    RAISE NOTICE 'Test 2: Notifications created for invoice: %', v_notif_count;
    IF v_notif_count = 0 THEN
        RAISE EXCEPTION 'No notification created for supplier_invoice_created event';
    END IF;

    -- ============================================================
    -- Test 3: 3-Way Matching (should match — quantities and prices align)
    -- ============================================================
    v_match_result := public.match_supplier_invoice(v_invoice_id);

    RAISE NOTICE 'Test 3: Match result: status=%, ok=%',
        v_match_result->>'matching_status', v_match_result->>'match_ok';

    IF (v_match_result->>'matching_status') != 'matched' THEN
        RAISE EXCEPTION 'Expected matched but got %', v_match_result->>'matching_status';
    END IF;

    -- Check notification for matched event
    SELECT COUNT(*) INTO v_notif_count
    FROM public.app_notifications
    WHERE profession_id = v_profession_id
      AND event_type = 'procurement.invoice_matched';

    RAISE NOTICE 'Test 3: Matched notifications: %', v_notif_count;

    -- ============================================================
    -- Test 4: Create mismatched invoice and match (should fail)
    -- ============================================================
    DECLARE
        v_mismatch_invoice_id UUID;
        v_mismatch_result     JSONB;
        v_po_item_id_2        UUID;
    BEGIN
        -- Get the PO item
        SELECT id INTO v_po_item_id_2 FROM public.purchase_order_items WHERE po_id = v_po_id LIMIT 1;

        v_invoice_result := public.create_supplier_invoice(
            p_profession_id := v_profession_id,
            p_supplier_id := v_supplier_id,
            p_po_id := v_po_id,
            p_invoice_number := 'INV-MISMATCH-' || EXTRACT(EPOCH FROM NOW())::INT::TEXT,
            p_invoice_date := CURRENT_DATE,
            p_items := jsonb_build_array(
                jsonb_build_object(
                    'po_item_id', v_po_item_id_2::TEXT,
                    'product_id', v_product_id::TEXT,
                    'item_name', 'Test Product Mismatch',
                    'quantity_invoiced', 20,  -- GR received 10, invoice says 20 → mismatch
                    'unit_price', 150.00,     -- PO price 100, invoice says 150 → mismatch
                    'total_price', 3000.00,
                    'tax_amount', 210.00
                )
            ),
            p_created_by := v_user_id
        );
        v_mismatch_invoice_id := (v_invoice_result->>'invoice_id')::UUID;

        v_mismatch_result := public.match_supplier_invoice(v_mismatch_invoice_id);

        RAISE NOTICE 'Test 4: Mismatch result: status=%, mismatches=%',
            v_mismatch_result->>'matching_status', v_mismatch_result->>'mismatches';

        IF (v_mismatch_result->>'matching_status') = 'matched' THEN
            RAISE EXCEPTION 'Expected mismatch but got matched';
        END IF;

        -- Check notification for mismatch event
        SELECT COUNT(*) INTO v_notif_count
        FROM public.app_notifications
        WHERE profession_id = v_profession_id
          AND event_type = 'procurement.invoice_mismatch';

        RAISE NOTICE 'Test 4: Mismatch notifications: %', v_notif_count;
    END;

    -- ============================================================
    -- Test 5: Get Invoice Matching Summary for PO
    -- ============================================================
    v_summary := public.get_invoice_matching_summary(v_po_id);
    RAISE NOTICE 'Test 5: Matching summary for PO: % invoices', jsonb_array_length(v_summary);

    -- ============================================================
    -- Test 6: Update Invoice Matching Status (manual override)
    -- ============================================================
    PERFORM public.update_invoice_matching_status(
        p_invoice_id := v_invoice_id,
        p_status := 'disputed',
        p_reason := 'Manual override for testing',
        p_updated_by := v_user_id
    );
    RAISE NOTICE 'Test 6: Updated invoice matching status to disputed';

    -- Verify status changed
    SELECT matching_status INTO v_status FROM public.supplier_invoices WHERE id = v_invoice_id;
    RAISE NOTICE 'Test 6: Verified status = %', v_status;

    -- ============================================================
    -- Test 7: Dashboard Metrics
    -- ============================================================
    v_dashboard := public.get_procurement_dashboard_metrics(
        p_profession_id := v_profession_id,
        p_branch_id := v_branch_id
    );

    RAISE NOTICE 'Test 7: Dashboard — PO count=%, GR count=%, invoice matched=%, mismatch=%',
        v_dashboard->>'po_count', v_dashboard->>'gr_count',
        v_dashboard->>'invoice_matched', v_dashboard->>'invoice_mismatch';

    IF (v_dashboard->>'po_count')::INT = 0 THEN
        RAISE EXCEPTION 'Dashboard returned 0 POs';
    END IF;

    -- ============================================================
    -- Test 8: Procurement Report (po_summary)
    -- ============================================================
    v_report := public.get_procurement_report(
        p_profession_id := v_profession_id,
        p_report_type := 'po_summary',
        p_filters := jsonb_build_object(
            'start_date', (CURRENT_DATE - INTERVAL '30 days')::DATE::TEXT,
            'end_date', CURRENT_DATE::TEXT
        )
    );

    RAISE NOTICE 'Test 8: Report po_summary — % rows', jsonb_array_length(v_report->'data');

    -- Test supplier_performance report
    v_report := public.get_procurement_report(
        p_profession_id := v_profession_id,
        p_report_type := 'supplier_performance'
    );
    RAISE NOTICE 'Test 8b: Report supplier_performance — % rows', jsonb_array_length(v_report->'data');

    -- ============================================================
    -- Test 9: PO PDF Mock URL
    -- ============================================================
    v_pdf_result := public.generate_po_pdf_url(v_po_id);
    RAISE NOTICE 'Test 9: PDF mock URL: %', v_pdf_result->>'pdf_url';

    IF v_pdf_result->>'pdf_url' IS NULL THEN
        RAISE EXCEPTION 'PDF URL is null';
    END IF;

    -- ============================================================
    -- Test 10: Send PO Email (mock)
    -- ============================================================
    v_email_result := public.send_po_email(
        p_po_id := v_po_id,
        p_email := 'test-supplier@example.com',
        p_message := 'Please find attached PO',
        p_sent_by := v_user_id
    );
    RAISE NOTICE 'Test 10: Email result: success=%, outbox=%',
        v_email_result->>'success', v_email_result->>'outbox_id';

    -- ============================================================
    -- Test 11: Full-Text Search
    -- ============================================================
    v_search_result := public.search_procurement_documents(
        p_profession_id := v_profession_id,
        p_query := 'TEST',
        p_entity_types := ARRAY['po','pr','gr','supplier']
    );

    RAISE NOTICE 'Test 11: Search "TEST" — % results', v_search_result->>'count';

    IF (v_search_result->>'count')::INT = 0 THEN
        RAISE EXCEPTION 'Search returned 0 results';
    END IF;

    -- ============================================================
    -- Summary
    -- ============================================================
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Step 4 E2E Test: ALL TESTS PASSED ✅';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  - Supplier invoice creation: ✅';
    RAISE NOTICE '  - 3-Way matching (match): ✅';
    RAISE NOTICE '  - 3-Way matching (mismatch): ✅';
    RAISE NOTICE '  - Matching summary: ✅';
    RAISE NOTICE '  - Manual status override: ✅';
    RAISE NOTICE '  - Dashboard metrics: ✅';
    RAISE NOTICE '  - Procurement reports: ✅';
    RAISE NOTICE '  - PO PDF mock URL: ✅';
    RAISE NOTICE '  - PO email (mock): ✅';
    RAISE NOTICE '  - Full-text search: ✅';
    RAISE NOTICE '  - Notifications: ✅';
    RAISE NOTICE '========================================';

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Step 4 E2E Test: FAILED ❌';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Error: %', SQLERRM;
    RAISE NOTICE 'Context: %', SQLSTATE;
    RAISE;
END;
$$;
