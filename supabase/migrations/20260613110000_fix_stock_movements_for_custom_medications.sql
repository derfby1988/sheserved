-- Migration: Fix stock_movements and inventory_lots to support custom_medications
-- Date: 2026-06-13
-- Issue: stock_movements.product_id and inventory_lots.product_id were NOT NULL,
--        which broke custom medication support (inventory_items uses custom_medication_id instead of product_id)

-- ============================================================
-- 1. ALTER inventory_lots
-- ============================================================

-- Make product_id nullable
ALTER TABLE public.inventory_lots
    ALTER COLUMN product_id DROP NOT NULL;

-- Add custom_medication_id
ALTER TABLE public.inventory_lots
    ADD COLUMN IF NOT EXISTS custom_medication_id UUID REFERENCES public.custom_medications(id) ON DELETE SET NULL;

-- Add inventory_item_id (convenience FK for quick lookups)
ALTER TABLE public.inventory_lots
    ADD COLUMN IF NOT EXISTS inventory_item_id UUID REFERENCES public.inventory_items(id) ON DELETE SET NULL;

-- Add CHECK constraint: must have product_id OR custom_medication_id (matching inventory_items)
ALTER TABLE public.inventory_lots
    DROP CONSTRAINT IF EXISTS check_lot_source;
ALTER TABLE public.inventory_lots
    ADD CONSTRAINT check_lot_source CHECK (
        (product_id IS NOT NULL AND custom_medication_id IS NULL) OR
        (product_id IS NULL AND custom_medication_id IS NOT NULL)
    );

-- Add index for custom_medication_id
CREATE INDEX IF NOT EXISTS idx_inventory_lots_custom_med
    ON public.inventory_lots(custom_medication_id, status, expiry_date);

-- Add index for inventory_item_id
CREATE INDEX IF NOT EXISTS idx_inventory_lots_inventory_item
    ON public.inventory_lots(inventory_item_id, status);

-- ============================================================
-- 2. ALTER stock_movements
-- ============================================================

-- Make product_id nullable
ALTER TABLE public.stock_movements
    ALTER COLUMN product_id DROP NOT NULL;

-- Add custom_medication_id
ALTER TABLE public.stock_movements
    ADD COLUMN IF NOT EXISTS custom_medication_id UUID REFERENCES public.custom_medications(id) ON DELETE SET NULL;

-- Add inventory_item_id (convenience FK for quick lookups)
ALTER TABLE public.stock_movements
    ADD COLUMN IF NOT EXISTS inventory_item_id UUID REFERENCES public.inventory_items(id) ON DELETE SET NULL;

-- Add CHECK constraint: must have product_id OR custom_medication_id OR inventory_item_id
ALTER TABLE public.stock_movements
    DROP CONSTRAINT IF EXISTS check_movement_source;
ALTER TABLE public.stock_movements
    ADD CONSTRAINT check_movement_source CHECK (
        (product_id IS NOT NULL AND custom_medication_id IS NULL) OR
        (product_id IS NULL AND custom_medication_id IS NOT NULL) OR
        (inventory_item_id IS NOT NULL)
    );

-- Add index for custom_medication_id
CREATE INDEX IF NOT EXISTS idx_stock_movements_custom_med
    ON public.stock_movements(custom_medication_id, created_at DESC);

-- Add index for inventory_item_id
CREATE INDEX IF NOT EXISTS idx_stock_movements_inventory_item
    ON public.stock_movements(inventory_item_id, created_at DESC);

-- Add index for profession_id (needed for querying all movements in a profession)
CREATE INDEX IF NOT EXISTS idx_stock_movements_profession
    ON public.stock_movements(profession_id, created_at DESC);

-- ============================================================
-- 3. UPDATE RPC: deduct_inventory_fefo()
-- ============================================================
-- Now inserts custom_medication_id and inventory_item_id when available

CREATE OR REPLACE FUNCTION deduct_inventory_fefo(
    p_profession_id UUID,
    p_inventory_item_id UUID,
    p_quantity INTEGER,
    p_reference_type TEXT DEFAULT 'order',
    p_reference_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_lot RECORD;
    v_remaining INTEGER := p_quantity;
    v_total_deducted INTEGER := 0;
    v_lot_deductions JSONB := '[]'::jsonb;
BEGIN
    FOR v_lot IN
        SELECT il.*
        FROM public.inventory_lots il
        WHERE il.inventory_item_id = p_inventory_item_id
          AND il.profession_id = p_profession_id
          AND il.status = 'active'
          AND il.quantity_remaining > 0
        ORDER BY il.expiry_date ASC NULLS LAST, il.created_at ASC
    LOOP
        IF v_remaining <= 0 THEN
            EXIT;
        END IF;

        IF v_lot.quantity_remaining >= v_remaining THEN
            -- Deduct full remaining from this lot
            UPDATE public.inventory_lots
            SET quantity_remaining = quantity_remaining - v_remaining,
                status = CASE WHEN (quantity_remaining - v_remaining) <= 0 THEN 'depleted' ELSE status END,
                updated_at = NOW()
            WHERE id = v_lot.id;

            -- Record stock movement
            INSERT INTO public.stock_movements (
                profession_id, product_id, custom_medication_id, inventory_item_id, lot_id,
                movement_type, quantity, unit_cost,
                reference_type, reference_id, notes
            )
            SELECT
                p_profession_id, ii.product_id, ii.custom_medication_id, ii.id, v_lot.id,
                'sale', v_remaining, il.unit_cost,
                p_reference_type, p_reference_id,
                'FEFO deduction lot ' || il.lot_number
            FROM public.inventory_items ii
            JOIN public.inventory_lots il ON il.id = v_lot.id
            WHERE ii.id = p_inventory_item_id;

            v_total_deducted := v_total_deducted + v_remaining;
            v_remaining := 0;
            EXIT;
        ELSE
            -- Deduct partial from this lot
            UPDATE public.inventory_lots
            SET quantity_remaining = 0,
                status = 'depleted',
                updated_at = NOW()
            WHERE id = v_lot.id;

            -- Record stock movement
            INSERT INTO public.stock_movements (
                profession_id, product_id, custom_medication_id, inventory_item_id, lot_id,
                movement_type, quantity, unit_cost,
                reference_type, reference_id, notes
            )
            SELECT
                p_profession_id, ii.product_id, ii.custom_medication_id, ii.id, v_lot.id,
                'sale', v_lot.quantity_remaining, il.unit_cost,
                p_reference_type, p_reference_id,
                'FEFO deduction lot ' || il.lot_number
            FROM public.inventory_items ii
            JOIN public.inventory_lots il ON il.id = v_lot.id
            WHERE ii.id = p_inventory_item_id;

            v_remaining := v_remaining - v_lot.quantity_remaining;
            v_total_deducted := v_total_deducted + v_lot.quantity_remaining;
        END IF;
    END LOOP;

    -- Update inventory_items quantity
    UPDATE public.inventory_items
    SET quantity = quantity - v_total_deducted,
        updated_at = NOW()
    WHERE id = p_inventory_item_id
      AND profession_id = p_profession_id;

    IF v_remaining > 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'deducted', v_total_deducted,
            'shortage', v_remaining,
            'error', 'insufficient stock'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'deducted', v_total_deducted
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 4. UPDATE RPC: create_stock_adjustment()
-- ============================================================

CREATE OR REPLACE FUNCTION create_stock_adjustment(
    p_profession_id UUID,
    p_inventory_item_id UUID,
    p_adjustment_type TEXT,
    p_quantity_after INTEGER,
    p_reason TEXT DEFAULT NULL,
    p_created_by UUID DEFAULT NULL,
    p_reference_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_quantity_before INTEGER;
    v_adjustment_id UUID;
BEGIN
    SELECT quantity INTO v_quantity_before
    FROM public.inventory_items
    WHERE id = p_inventory_item_id AND profession_id = p_profession_id;

    IF v_quantity_before IS NULL THEN
        RAISE EXCEPTION 'inventory_item not found';
    END IF;

    INSERT INTO public.stock_adjustments (
        profession_id, inventory_item_id, adjustment_type,
        quantity_before, quantity_after, reason, reference_id, created_by
    )
    VALUES (
        p_profession_id, p_inventory_item_id, p_adjustment_type,
        v_quantity_before, p_quantity_after, p_reason, p_reference_id, p_created_by
    )
    RETURNING id INTO v_adjustment_id;

    -- Update inventory item quantity
    UPDATE public.inventory_items
    SET quantity = p_quantity_after,
        updated_at = NOW()
    WHERE id = p_inventory_item_id AND profession_id = p_profession_id;

    -- Record stock movement
    INSERT INTO public.stock_movements (
        profession_id, product_id, custom_medication_id, inventory_item_id,
        movement_type, quantity, unit_cost,
        reference_type, reference_id, notes
    )
    SELECT
        p_profession_id, ii.product_id, ii.custom_medication_id, ii.id,
        CASE WHEN p_quantity_after >= v_quantity_before THEN 'adjustment' ELSE 'adjustment' END,
        ABS(p_quantity_after - v_quantity_before), ii.cost_price,
        'adjustment', v_adjustment_id, p_reason
    FROM public.inventory_items ii
    WHERE ii.id = p_inventory_item_id;

    RETURN v_adjustment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. UPDATE RPC: complete_inventory_transfer()
-- ============================================================
-- Also record stock movements for transfer_in at destination

CREATE OR REPLACE FUNCTION complete_inventory_transfer(
    p_transfer_id UUID,
    p_approved_by UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_transfer RECORD;
    v_line RECORD;
    v_from_ii RECORD;
BEGIN
    SELECT * INTO v_transfer
    FROM public.inventory_transfers WHERE id = p_transfer_id;

    IF v_transfer IS NULL OR v_transfer.transfer_status NOT IN ('pending', 'in_transit') THEN
        RETURN false;
    END IF;

    UPDATE public.inventory_transfers
    SET transfer_status = 'completed',
        approved_by = p_approved_by,
        approved_at = NOW(),
        updated_at = NOW()
    WHERE id = p_transfer_id;

    -- Process each transfer line
    FOR v_line IN
        SELECT * FROM public.inventory_transfer_lines WHERE transfer_id = p_transfer_id
    LOOP
        -- Get inventory item details for movement logging
        SELECT * INTO v_from_ii
        FROM public.inventory_items
        WHERE id = v_line.inventory_item_id AND profession_id = v_transfer.profession_id;

        -- Record transfer_out movement at source
        INSERT INTO public.stock_movements (
            profession_id, product_id, custom_medication_id, inventory_item_id,
            branch_id, warehouse_location_id,
            movement_type, quantity, unit_cost,
            reference_type, reference_id, notes
        )
        SELECT
            v_transfer.profession_id, ii.product_id, ii.custom_medication_id, ii.id,
            v_transfer.from_branch_id, v_transfer.from_warehouse_id,
            'transfer_out', v_line.quantity, ii.cost_price,
            'transfer', p_transfer_id, 'Transfer out to ' || COALESCE(v_transfer.to_branch_id::TEXT, 'destination')
        FROM public.inventory_items ii
        WHERE ii.id = v_line.inventory_item_id;

        -- Record transfer_in movement at destination
        INSERT INTO public.stock_movements (
            profession_id, product_id, custom_medication_id, inventory_item_id,
            branch_id, warehouse_location_id,
            movement_type, quantity, unit_cost,
            reference_type, reference_id, notes
        )
        SELECT
            v_transfer.profession_id, ii.product_id, ii.custom_medication_id, ii.id,
            v_transfer.to_branch_id, v_transfer.to_warehouse_id,
            'transfer_in', v_line.quantity, ii.cost_price,
            'transfer', p_transfer_id, 'Transfer in from ' || COALESCE(v_transfer.from_branch_id::TEXT, 'source')
        FROM public.inventory_items ii
        WHERE ii.id = v_line.inventory_item_id;

        -- Update destination inventory (upsert or insert)
        UPDATE public.inventory_items
        SET quantity = quantity + v_line.quantity,
            updated_at = NOW()
        WHERE id = v_line.inventory_item_id AND profession_id = v_transfer.profession_id;
    END LOOP;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. CREATE RPC: get_stock_movements_by_profession()
-- ============================================================
-- For querying all movements in a profession (needed for StockMovementTrackingPage)

CREATE OR REPLACE FUNCTION get_stock_movements_by_profession(
    p_profession_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    profession_id UUID,
    product_id UUID,
    custom_medication_id UUID,
    inventory_item_id UUID,
    lot_id UUID,
    branch_id UUID,
    warehouse_location_id UUID,
    movement_type TEXT,
    quantity INTEGER,
    unit_cost DECIMAL,
    total_cost DECIMAL,
    reference_type TEXT,
    reference_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sm.id,
        sm.profession_id,
        sm.product_id,
        sm.custom_medication_id,
        sm.inventory_item_id,
        sm.lot_id,
        sm.branch_id,
        sm.warehouse_location_id,
        sm.movement_type,
        sm.quantity,
        sm.unit_cost,
        sm.total_cost,
        sm.reference_type,
        sm.reference_id,
        sm.notes,
        sm.created_at
    FROM public.stock_movements sm
    WHERE sm.profession_id = p_profession_id
    ORDER BY sm.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 7. CREATE RPC: create_stocktake_configuration()
-- ============================================================

CREATE OR REPLACE FUNCTION create_stocktake_configuration(
    p_profession_id UUID,
    p_branch_id UUID DEFAULT NULL,
    p_name TEXT DEFAULT 'Stocktake',
    p_frequency_type TEXT DEFAULT 'MONTHLY',
    p_custom_interval_days INTEGER DEFAULT NULL,
    p_next_stocktake_date DATE DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_config_id UUID;
    v_next_date DATE;
BEGIN
    v_next_date := COALESCE(p_next_stocktake_date, CURRENT_DATE + INTERVAL '1 month');

    INSERT INTO public.stocktake_configurations (
        profession_id, branch_id, name, frequency_type,
        custom_interval_days, next_stocktake_date, is_active
    )
    VALUES (
        p_profession_id, p_branch_id, p_name, p_frequency_type,
        p_custom_interval_days, v_next_date, true
    )
    RETURNING id INTO v_config_id;

    RETURN v_config_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 8. CREATE RPC: update_stocktake_configuration()
-- ============================================================

CREATE OR REPLACE FUNCTION update_stocktake_configuration(
    p_config_id UUID,
    p_name TEXT DEFAULT NULL,
    p_frequency_type TEXT DEFAULT NULL,
    p_custom_interval_days INTEGER DEFAULT NULL,
    p_next_stocktake_date DATE DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.stocktake_configurations
    SET
        name = COALESCE(p_name, name),
        frequency_type = COALESCE(p_frequency_type, frequency_type),
        custom_interval_days = COALESCE(p_custom_interval_days, custom_interval_days),
        next_stocktake_date = COALESCE(p_next_stocktake_date, next_stocktake_date),
        is_active = COALESCE(p_is_active, is_active),
        updated_at = NOW()
    WHERE id = p_config_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 9. CREATE RPC: delete_stocktake_configuration()
-- ============================================================

CREATE OR REPLACE FUNCTION delete_stocktake_configuration(
    p_config_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Only allow deletion if there are no associated sessions
    IF EXISTS (
        SELECT 1 FROM public.stocktake_sessions
        WHERE stocktake_config_id = p_config_id
    ) THEN
        -- Soft delete by setting is_active = false
        UPDATE public.stocktake_configurations
        SET is_active = false, updated_at = NOW()
        WHERE id = p_config_id;
    ELSE
        DELETE FROM public.stocktake_configurations
        WHERE id = p_config_id;
    END IF;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
