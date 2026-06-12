-- ============================================================
-- Migration: Inventory Runtime Functions
-- ปิด gap ระหว่าง schema (Phase 1) กับ checkout/payment flow
-- Functions: release_stock_reservation, deduct_stock, cleanup_expired_reservations
-- ============================================================

-- ============================================
-- 1. RELEASE STOCK RESERVATION
--    ใช้เมื่อ: payment ล้ม, cart abandon, หรือ user ยกเลิก
-- ============================================
CREATE OR REPLACE FUNCTION public.release_stock_reservation(
    p_reservation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.inventory_reservations
    SET
        status = 'cancelled',
        quantity_cancelled = quantity_reserved,
        updated_at = NOW()
    WHERE id = p_reservation_id
      AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % not found or not active', p_reservation_id;
    END IF;
END;
$$;

-- ============================================
-- 2. DEDUCT STOCK (after payment success)
--    เปลี่ยน reservation → fulfilled + ลด quantity_remaining + บันทึก ledger
-- ============================================
CREATE OR REPLACE FUNCTION public.deduct_stock(
    p_reservation_id UUID,
    p_order_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_reservation RECORD;
    v_lot RECORD;
    v_profession_id UUID;
    v_branch_id UUID;
    v_warehouse_location_id UUID;
BEGIN
    -- Lock reservation
    SELECT *
    INTO v_reservation
    FROM public.inventory_reservations
    WHERE id = p_reservation_id
      AND status = 'active'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active reservation % not found', p_reservation_id;
    END IF;

    -- Mark reservation fulfilled
    UPDATE public.inventory_reservations
    SET
        status = 'fulfilled',
        quantity_fulfilled = quantity_reserved,
        updated_at = NOW()
    WHERE id = p_reservation_id;

    -- Deduct from lot if lot_id specified
    IF v_reservation.lot_id IS NOT NULL THEN
        SELECT id, profession_id, branch_id, warehouse_location_id, unit_cost
        INTO v_lot
        FROM public.inventory_lots
        WHERE id = v_reservation.lot_id
        FOR UPDATE;

        UPDATE public.inventory_lots
        SET
            quantity_remaining = GREATEST(quantity_remaining - v_reservation.quantity_reserved, 0),
            updated_at = NOW()
        WHERE id = v_reservation.lot_id;
    END IF;

    -- Insert stock movement (sale)
    INSERT INTO public.stock_movements (
        profession_id,
        product_id,
        lot_id,
        branch_id,
        warehouse_location_id,
        movement_type,
        quantity,
        unit_cost,
        total_cost,
        reference_type,
        reference_id,
        notes,
        created_at
    )
    VALUES (
        v_reservation.profession_id,
        v_reservation.product_id,
        v_reservation.lot_id,
        v_reservation.branch_id,
        COALESCE(v_lot.warehouse_location_id, v_reservation.branch_id),
        'sale',
        -v_reservation.quantity_reserved,
        COALESCE(v_lot.unit_cost, 0),
        COALESCE(v_lot.unit_cost, 0) * v_reservation.quantity_reserved,
        'order',
        p_order_id,
        'Stock deducted after successful payment (reservation ' || p_reservation_id || ')',
        NOW()
    );
END;
$$;

-- ============================================
-- 3. CLEANUP EXPIRED RESERVATIONS
--    รันเป็น cron job ทุก 5 นาที
-- ============================================
CREATE OR REPLACE FUNCTION public.cleanup_expired_reservations()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    WITH expired AS (
        SELECT id, quantity_reserved
        FROM public.inventory_reservations
        WHERE status = 'active'
          AND expires_at < NOW()
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.inventory_reservations ir
    SET
        status = 'expired',
        quantity_cancelled = quantity_reserved,
        updated_at = NOW()
    FROM expired e
    WHERE ir.id = e.id;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;
