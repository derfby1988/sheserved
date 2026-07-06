-- Test script สำหรับ Procurement Step 2
-- สร้าง test data แล้วทดสอบ RPC functions ทั้งหมด

DO $$
DECLARE
    v_profession_id       UUID;
    v_user_id             UUID;
    v_branch_id           UUID;
    v_supplier_id         UUID;
    v_product_id          UUID;
    v_pr_id               UUID;
    v_pr_item_id          UUID;
    v_po_id               UUID;
    v_po_item_id          UUID;
    v_gr_result           JSONB;
    v_po_result           JSONB;
    v_doc_number          TEXT;
    v_gr_count            INTEGER;
    v_bo_count            INTEGER;
    v_lot_count           INTEGER;
    v_sm_count            INTEGER;
    v_outbox_count        INTEGER;
    v_tax_amount          DECIMAL(12,2);
    v_quantity_fulfilled  INTEGER;
    v_bo_id               UUID;
    v_po_status           TEXT;
    v_audit_count         INTEGER;
    v_gr_id               UUID;
    v_tx_step_count       INTEGER;
BEGIN
    -- 1. หา profession ที่มี product และ supplier อยู่แล้ว
    SELECT p.id INTO v_profession_id
    FROM public.professions p
    WHERE EXISTS (SELECT 1 FROM public.products pr WHERE pr.profession_id = p.id)
      AND EXISTS (SELECT 1 FROM public.suppliers s WHERE s.profession_id = p.id)
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RAISE EXCEPTION 'No profession found with both products and suppliers';
    END IF;

    -- Pick a user that belongs to this profession, or assign the first user to this profession
    SELECT id INTO v_user_id FROM public.users WHERE profession_id = v_profession_id LIMIT 1;
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM public.users LIMIT 1;
        IF v_user_id IS NOT NULL THEN
            UPDATE public.users SET profession_id = v_profession_id, role = 'admin' WHERE id = v_user_id;
        END IF;
    END IF;
    SELECT id INTO v_branch_id FROM public.organization_branches WHERE profession_id = v_profession_id LIMIT 1;
    SELECT id INTO v_supplier_id FROM public.suppliers WHERE profession_id = v_profession_id LIMIT 1;
    SELECT id INTO v_product_id FROM public.products WHERE profession_id = v_profession_id LIMIT 1;

    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No user found'; END IF;
    IF v_product_id IS NULL THEN RAISE EXCEPTION 'No product found for profession %', v_profession_id; END IF;
    IF v_supplier_id IS NULL THEN RAISE EXCEPTION 'No supplier found for profession %', v_profession_id; END IF;

    RAISE NOTICE 'Using profession=%, user=%, branch=%, supplier=%, product=%',
        v_profession_id, v_user_id, v_branch_id, v_supplier_id, v_product_id;

    -- 2. Test generate_document_number
    v_doc_number := public.generate_document_number(v_profession_id, v_branch_id, 'GR');
    RAISE NOTICE 'Generated document number: %', v_doc_number;

    -- 3. สร้าง PR (status = pending_approval เพื่อทดสอบ approve flow)
    INSERT INTO public.purchase_requisitions (
        profession_id, branch_id, requester_id, pr_number, status, notes
    )
    VALUES (
        v_profession_id, v_branch_id, v_user_id,
        public.generate_document_number(v_profession_id, v_branch_id, 'PR'),
        'pending_approval', 'Test PR'
    )
    RETURNING id INTO v_pr_id;

    -- 4. สร้าง PR item
    INSERT INTO public.purchase_requisition_items (
        profession_id, requisition_id, product_id, item_name,
        quantity_requested, estimated_unit_price, estimated_total_price
    )
    VALUES (
        v_profession_id, v_pr_id, v_product_id, 'Test Item',
        10, 100.00, 1000.00
    )
    RETURNING id INTO v_pr_item_id;

    -- 5. Test approve_purchase_requisition
    PERFORM public.approve_purchase_requisition(v_pr_id, v_user_id);
    IF (SELECT status FROM public.purchase_requisitions WHERE id = v_pr_id) != 'approved' THEN
        RAISE EXCEPTION 'PR approval failed';
    END IF;
    RAISE NOTICE 'PR approved successfully';

    -- Verify audit log for PR approval
    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'purchase_requisitions' AND record_id = v_pr_id AND action = 'UPDATE';
    IF v_audit_count < 1 THEN
        RAISE EXCEPTION 'Expected audit log for PR approval, got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for PR approval verified';

    -- 6. Test convert_pr_to_po (reads PR items from DB, no p_items parameter)
    v_po_result := public.convert_pr_to_po(
        v_pr_id,
        v_supplier_id,
        v_user_id,
        v_branch_id,
        'Test PO'
    );
    v_po_id := (v_po_result->>'po_id')::UUID;
    RAISE NOTICE 'Converted PR to PO: %', v_po_result;

    -- Verify VAT calculation (7% of 1000 = 70)
    v_tax_amount := (v_po_result->>'tax_amount')::DECIMAL(12,2);
    IF v_tax_amount != 70.00 THEN
        RAISE EXCEPTION 'Expected tax_amount=70.00, got %', v_tax_amount;
    END IF;
    RAISE NOTICE 'VAT calculation verified: %', v_tax_amount;

    -- Verify outbox event for PR conversion
    SELECT COUNT(*) INTO v_outbox_count FROM public.outbox_events 
    WHERE aggregate_id = v_po_id AND event_type = 'procurement.pr_converted_to_po';
    IF v_outbox_count != 1 THEN
        RAISE EXCEPTION 'Expected 1 outbox event for PR conversion, got %', v_outbox_count;
    END IF;
    RAISE NOTICE 'Outbox event for PR conversion verified';

    -- Verify outbox event for PR approval
    SELECT COUNT(*) INTO v_outbox_count FROM public.outbox_events 
    WHERE aggregate_id = v_pr_id AND event_type = 'procurement.pr_approved';
    IF v_outbox_count != 1 THEN
        RAISE EXCEPTION 'Expected 1 outbox event for PR approval, got %', v_outbox_count;
    END IF;
    RAISE NOTICE 'Outbox event for PR approval verified';

    SELECT id INTO v_po_item_id FROM public.purchase_order_items WHERE po_id = v_po_id LIMIT 1;

    -- 7. Test send_purchase_order RPC (updates status + emits po_sent outbox)
    PERFORM public.send_purchase_order(v_po_id, v_user_id);
    IF (SELECT status FROM public.purchase_orders WHERE id = v_po_id) != 'sent' THEN
        RAISE EXCEPTION 'Expected PO status sent, got %',
            (SELECT status FROM public.purchase_orders WHERE id = v_po_id);
    END IF;
    RAISE NOTICE 'PO sent successfully';

    -- Verify outbox event for po_sent
    SELECT COUNT(*) INTO v_outbox_count FROM public.outbox_events
    WHERE aggregate_id = v_po_id AND event_type = 'procurement.po_sent';
    IF v_outbox_count != 1 THEN
        RAISE EXCEPTION 'Expected 1 outbox event for po_sent, got %', v_outbox_count;
    END IF;
    RAISE NOTICE 'Outbox event for po_sent verified';

    -- Verify audit log for PR conversion
    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'purchase_requisitions' AND record_id = v_pr_id AND action = 'UPDATE';
    IF v_audit_count < 2 THEN
        RAISE EXCEPTION 'Expected at least 2 audit logs for PR (approval + conversion), got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for PR conversion verified';

    -- Verify audit log for PO creation
    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'purchase_orders' AND record_id = v_po_id AND action = 'INSERT';
    IF v_audit_count < 1 THEN
        RAISE EXCEPTION 'Expected audit log for PO creation, got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for PO creation verified';

    -- Verify audit log for PO sent
    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'purchase_orders' AND record_id = v_po_id AND action = 'UPDATE';
    IF v_audit_count < 1 THEN
        RAISE EXCEPTION 'Expected audit log for PO sent, got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for PO sent verified';

    -- 8. Test create_goods_receipt (รับ 7 จาก 10 ที่สั่ง)
    v_gr_result := public.create_goods_receipt(
        v_profession_id,
        v_po_id,
        v_user_id,
        v_branch_id,
        'DN-TEST-001',
        jsonb_build_array(jsonb_build_object(
            'purchase_order_item_id', v_po_item_id,
            'quantity_accepted', 7,
            'quantity_rejected', 0,
            'lot_number', 'LOT-TEST-001',
            'expiry_date', '2027-12-31'
        )),
        'Test goods receipt'
    );
    RAISE NOTICE 'Created goods receipt: %', v_gr_result;

    -- 9. Verify results
    SELECT COUNT(*) INTO v_gr_count FROM public.goods_receipts WHERE purchase_order_id = v_po_id;
    SELECT COUNT(*) INTO v_bo_count FROM public.back_orders WHERE purchase_order_id = v_po_id;
    SELECT COUNT(*) INTO v_lot_count FROM public.inventory_lots WHERE po_id = v_po_id;
    SELECT COUNT(*) INTO v_sm_count FROM public.stock_movements WHERE reference_id = v_po_id AND reference_type = 'po';

    RAISE NOTICE 'Verification: gr_count=%, back_order_count=%, lot_count=%, stock_movement_count=%',
        v_gr_count, v_bo_count, v_lot_count, v_sm_count;

    -- 10. Assert expectations
    IF v_gr_count != 1 THEN RAISE EXCEPTION 'Expected 1 goods receipt, got %', v_gr_count; END IF;
    IF v_bo_count != 1 THEN RAISE EXCEPTION 'Expected 1 back order, got %', v_bo_count; END IF;
    IF v_lot_count != 1 THEN RAISE EXCEPTION 'Expected 1 inventory lot, got %', v_lot_count; END IF;
    IF v_sm_count != 1 THEN RAISE EXCEPTION 'Expected 1 stock movement, got %', v_sm_count; END IF;

    -- Verify quantity_fulfilled = 0 (back order should start with 0 fulfilled)
    SELECT quantity_fulfilled INTO v_quantity_fulfilled 
    FROM public.back_orders 
    WHERE purchase_order_id = v_po_id 
    LIMIT 1;
    IF v_quantity_fulfilled != 0 THEN
        RAISE EXCEPTION 'Expected quantity_fulfilled=0, got %', v_quantity_fulfilled;
    END IF;
    RAISE NOTICE 'Back order quantity_fulfilled verified: %', v_quantity_fulfilled;

    -- Verify outbox event for GR
    SELECT COUNT(*) INTO v_outbox_count FROM public.outbox_events 
    WHERE event_type = 'procurement.goods_receipted';
    IF v_outbox_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 outbox event for GR, got %', v_outbox_count;
    END IF;
    RAISE NOTICE 'Outbox event for GR verified';

    -- Verify outbox event for back_order_created
    SELECT COUNT(*) INTO v_outbox_count FROM public.outbox_events 
    WHERE event_type = 'procurement.back_order_created';
    IF v_outbox_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 outbox event for back_order_created, got %', v_outbox_count;
    END IF;
    RAISE NOTICE 'Outbox event for back_order_created verified';

    -- 11. Verify PO status updated to partially_received
    IF (SELECT status FROM public.purchase_orders WHERE id = v_po_id) != 'partially_received' THEN
        RAISE EXCEPTION 'Expected PO status partially_received, got %',
            (SELECT status FROM public.purchase_orders WHERE id = v_po_id);
    END IF;

    -- Verify audit logs after first GR
    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'goods_receipts' AND action = 'INSERT';
    IF v_audit_count < 1 THEN
        RAISE EXCEPTION 'Expected audit log for GR creation, got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for GR creation verified';

    -- Verify transaction context (Saga observability) for first GR
    v_gr_id := (v_gr_result->>'gr_id')::UUID;

    SELECT COUNT(*) INTO v_audit_count
    FROM public.transaction_contexts
    WHERE source_module = 'procurement'
      AND operation_type = 'create_goods_receipt'
      AND status = 'committed'
      AND metadata->>'gr_id' = v_gr_id::TEXT;
    IF v_audit_count < 1 THEN
        RAISE EXCEPTION 'Expected committed transaction context for GR, got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Transaction context for GR #1 verified (status=committed)';

    SELECT jsonb_array_length(steps) INTO v_tx_step_count
    FROM public.transaction_contexts
    WHERE source_module = 'procurement'
      AND operation_type = 'create_goods_receipt'
      AND metadata->>'gr_id' = v_gr_id::TEXT
    LIMIT 1;
    IF v_tx_step_count < 8 THEN
        RAISE EXCEPTION 'Expected at least 8 steps in transaction context, got %', v_tx_step_count;
    END IF;
    RAISE NOTICE 'Transaction context steps verified (%) steps', v_tx_step_count;

    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'purchase_orders' AND record_id = v_po_id AND action = 'UPDATE';
    IF v_audit_count < 2 THEN
        RAISE EXCEPTION 'Expected at least 2 PO update audit logs (sent + partially_received), got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for PO partially_received verified';

    -- 12. Test back order fulfillment: GR #2 รับของค้างที่เหลือ (3 ชิ้น)
    SELECT id INTO v_bo_id FROM public.back_orders WHERE purchase_order_id = v_po_id LIMIT 1;

    v_gr_result := public.create_goods_receipt(
        v_profession_id,
        v_po_id,
        v_user_id,
        v_branch_id,
        'DN-TEST-002',
        jsonb_build_array(jsonb_build_object(
            'purchase_order_item_id', v_po_item_id,
            'quantity_accepted', 3,
            'quantity_rejected', 0,
            'lot_number', 'LOT-TEST-002',
            'expiry_date', '2027-12-31'
        )),
        'Test goods receipt #2 - fulfill back order'
    );
    RAISE NOTICE 'Created GR #2: %', v_gr_result;

    -- 13. Verify back order fulfilled
    SELECT quantity_fulfilled, status INTO v_quantity_fulfilled, v_po_status
    FROM public.back_orders WHERE id = v_bo_id;
    IF v_po_status != 'fulfilled' THEN
        RAISE EXCEPTION 'Expected back order status fulfilled, got %', v_po_status;
    END IF;
    RAISE NOTICE 'Back order fulfilled: status=%, quantity_fulfilled=%', v_po_status, v_quantity_fulfilled;

    -- 14. Verify outbox event for back_order_fulfilled
    SELECT COUNT(*) INTO v_outbox_count FROM public.outbox_events 
    WHERE event_type = 'procurement.back_order_fulfilled';
    IF v_outbox_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 outbox event for back_order_fulfilled, got %', v_outbox_count;
    END IF;
    RAISE NOTICE 'Outbox event for back_order_fulfilled verified';

    -- 15. Verify outbox event for po_fully_received
    SELECT COUNT(*) INTO v_outbox_count FROM public.outbox_events 
    WHERE event_type = 'procurement.po_fully_received' AND aggregate_id = v_po_id;
    IF v_outbox_count != 1 THEN
        RAISE EXCEPTION 'Expected 1 outbox event for po_fully_received, got %', v_outbox_count;
    END IF;
    RAISE NOTICE 'Outbox event for po_fully_received verified';

    -- 16. Verify PO status is fully_received
    IF (SELECT status FROM public.purchase_orders WHERE id = v_po_id) != 'fully_received' THEN
        RAISE EXCEPTION 'Expected PO status fully_received, got %',
            (SELECT status FROM public.purchase_orders WHERE id = v_po_id);
    END IF;

    -- Verify audit logs after second GR
    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'goods_receipts' AND action = 'INSERT';
    IF v_audit_count < 2 THEN
        RAISE EXCEPTION 'Expected at least 2 GR audit logs (2 receipts), got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for GR #2 verified';

    SELECT COUNT(*) INTO v_audit_count FROM public.transaction_audit_log
    WHERE table_name = 'purchase_orders' AND record_id = v_po_id AND action = 'UPDATE';
    IF v_audit_count < 3 THEN
        RAISE EXCEPTION 'Expected at least 3 PO update audit logs (sent + partially_received + fully_received), got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Audit log for PO fully_received verified';

    -- Verify transaction context for GR #2
    v_gr_id := (v_gr_result->>'gr_id')::UUID;

    SELECT COUNT(*) INTO v_audit_count
    FROM public.transaction_contexts
    WHERE source_module = 'procurement'
      AND operation_type = 'create_goods_receipt'
      AND status = 'committed'
      AND metadata->>'gr_id' = v_gr_id::TEXT;
    IF v_audit_count < 1 THEN
        RAISE EXCEPTION 'Expected committed transaction context for GR #2, got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Transaction context for GR #2 verified (status=committed)';

    SELECT jsonb_array_length(steps) INTO v_tx_step_count
    FROM public.transaction_contexts
    WHERE source_module = 'procurement'
      AND operation_type = 'create_goods_receipt'
      AND metadata->>'gr_id' = v_gr_id::TEXT
    LIMIT 1;
    IF v_tx_step_count < 8 THEN
        RAISE EXCEPTION 'Expected at least 8 steps in GR #2 transaction context, got %', v_tx_step_count;
    END IF;
    RAISE NOTICE 'Transaction context steps for GR #2 verified (%) steps', v_tx_step_count;

    -- Verify total transaction contexts created (2 GRs = 2 contexts)
    SELECT COUNT(*) INTO v_audit_count
    FROM public.transaction_contexts
    WHERE source_module = 'procurement'
      AND operation_type = 'create_goods_receipt';
    IF v_audit_count < 2 THEN
        RAISE EXCEPTION 'Expected at least 2 transaction contexts (2 GRs), got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Total transaction contexts verified (%) contexts', v_audit_count;

    -- ============================================================
    -- Verify app_notifications generated from procurement outbox events
    -- ============================================================
    SELECT COUNT(*) INTO v_audit_count FROM public.app_notifications
    WHERE profession_id = v_profession_id AND category = 'procurement';
    IF v_audit_count < 1 THEN
        RAISE EXCEPTION 'Expected at least 1 procurement notification, got %', v_audit_count;
    END IF;
    RAISE NOTICE 'Procurement app_notifications verified (%) notifications', v_audit_count;

    RAISE NOTICE 'All Procurement Step 2 tests passed! (including back order fulfillment, audit trail, notifications, and transaction saga observability)';
END $$;
