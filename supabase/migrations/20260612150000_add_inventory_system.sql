-- Migration: ERP Inventory System
-- Date: 2026-06-12
-- Prerequisites: Phase 1 inventory tables (inventory_lots, stock_movements, warehouse_locations, products)

-- ============================================================
-- 1. CUSTOM MEDICATIONS (Tenant-specific products not in master DB)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.custom_medications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    description     TEXT,
    category_id     UUID REFERENCES public.product_categories(id) ON DELETE SET NULL,
    price           DECIMAL(12,2) NOT NULL DEFAULT 0,
    cost_price      DECIMAL(12,2) NOT NULL DEFAULT 0,
    sku             TEXT,
    barcode         TEXT,
    image_url       TEXT,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, name)
);

CREATE INDEX IF NOT EXISTS idx_custom_medications_profession
    ON public.custom_medications(profession_id, is_active, name);

DROP TRIGGER IF EXISTS trg_custom_medications_updated_at ON public.custom_medications;
CREATE TRIGGER trg_custom_medications_updated_at
    BEFORE UPDATE ON public.custom_medications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. INVENTORY ITEMS (Tenant-level stock summary per product/custom_medication)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inventory_items (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    product_id              UUID REFERENCES public.products(id) ON DELETE SET NULL,
    custom_medication_id    UUID REFERENCES public.custom_medications(id) ON DELETE SET NULL,
    branch_id             UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    warehouse_location_id UUID REFERENCES public.warehouse_locations(id) ON DELETE SET NULL,
    quantity              INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    cost_price            DECIMAL(12,2) NOT NULL DEFAULT 0,
    selling_price         DECIMAL(12,2) NOT NULL DEFAULT 0,
    is_vatable            BOOLEAN DEFAULT false,
    reorder_point         INTEGER NOT NULL DEFAULT 0,
    reorder_qty           INTEGER NOT NULL DEFAULT 1,
    is_active             BOOLEAN DEFAULT true,
    created_at            TIMESTAMPTZ DEFAULT NOW(),
    updated_at            TIMESTAMPTZ DEFAULT NOW(),

    -- ต้องมี product_id หรือ custom_medication_id อย่างใดอย่างหนึ่ง
    CONSTRAINT check_item_source CHECK (
        (product_id IS NOT NULL AND custom_medication_id IS NULL) OR
        (product_id IS NULL AND custom_medication_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_inventory_items_profession
    ON public.inventory_items(profession_id, is_active, quantity);
CREATE INDEX IF NOT EXISTS idx_inventory_items_low_stock
    ON public.inventory_items(profession_id, quantity, reorder_point)
    WHERE quantity <= reorder_point;

DROP TRIGGER IF EXISTS trg_inventory_items_updated_at ON public.inventory_items;
CREATE TRIGGER trg_inventory_items_updated_at
    BEFORE UPDATE ON public.inventory_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. STOCKTAKE CONFIGURATIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.stocktake_configurations (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id        UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id            UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    name                 TEXT NOT NULL DEFAULT 'Stocktake',
    frequency_type       TEXT NOT NULL DEFAULT 'MONTHLY'
                            CHECK (frequency_type IN ('WEEKLY', 'MONTHLY', 'QUARTERLY', 'YEARLY', 'CUSTOM')),
    custom_interval_days INTEGER,
    next_stocktake_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    is_active            BOOLEAN DEFAULT true,
    created_at           TIMESTAMPTZ DEFAULT NOW(),
    updated_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stocktake_config_profession
    ON public.stocktake_configurations(profession_id, is_active, next_stocktake_date);

DROP TRIGGER IF EXISTS trg_stocktake_config_updated_at ON public.stocktake_configurations;
CREATE TRIGGER trg_stocktake_config_updated_at
    BEFORE UPDATE ON public.stocktake_configurations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. STOCKTAKE SESSIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.stocktake_sessions (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id        UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    stocktake_config_id  UUID REFERENCES public.stocktake_configurations(id) ON DELETE SET NULL,
    branch_id            UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    status               TEXT NOT NULL DEFAULT 'in_progress'
                            CHECK (status IN ('in_progress', 'completed', 'cancelled', 'approved')),
    started_at           TIMESTAMPTZ DEFAULT NOW(),
    completed_at         TIMESTAMPTZ,
    approved_by          UUID REFERENCES public.users(id) ON DELETE SET NULL,
    approved_at          TIMESTAMPTZ,
    notes                TEXT,
    created_at           TIMESTAMPTZ DEFAULT NOW(),
    updated_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stocktake_sessions_profession
    ON public.stocktake_sessions(profession_id, status, created_at DESC);

DROP TRIGGER IF EXISTS trg_stocktake_sessions_updated_at ON public.stocktake_sessions;
CREATE TRIGGER trg_stocktake_sessions_updated_at
    BEFORE UPDATE ON public.stocktake_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 5. STOCKTAKE LINES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.stocktake_lines (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stocktake_session_id UUID NOT NULL REFERENCES public.stocktake_sessions(id) ON DELETE CASCADE,
    inventory_item_id   UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    system_quantity     INTEGER NOT NULL DEFAULT 0,
    counted_quantity    INTEGER NOT NULL DEFAULT 0,
    variance            INTEGER GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED,
    reason              TEXT,  -- หมายเหตุกรณี variance
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stocktake_lines_session
    ON public.stocktake_lines(stocktake_session_id);

-- ============================================================
-- 6. STOCK ADJUSTMENTS (standalone adjustment records)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.stock_adjustments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    inventory_item_id   UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    adjustment_type     TEXT NOT NULL
                            CHECK (adjustment_type IN ('count', 'damage', 'expired', 'found', 'lost', 'other')),
    quantity_before     INTEGER NOT NULL DEFAULT 0,
    quantity_after      INTEGER NOT NULL DEFAULT 0,
    variance            INTEGER GENERATED ALWAYS AS (quantity_after - quantity_before) STORED,
    reason              TEXT,
    reference_id        UUID,  -- FK ไป stocktake_session_id หรืออื่น
    created_by          UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_adjustments_profession
    ON public.stock_adjustments(profession_id, adjustment_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_adjustments_item
    ON public.stock_adjustments(inventory_item_id, created_at DESC);

-- ============================================================
-- 7. INVENTORY TRANSFERS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inventory_transfers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    from_branch_id      UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    from_warehouse_id   UUID REFERENCES public.warehouse_locations(id) ON DELETE SET NULL,
    to_branch_id        UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    to_warehouse_id     UUID REFERENCES public.warehouse_locations(id) ON DELETE SET NULL,
    transfer_status     TEXT NOT NULL DEFAULT 'pending'
                            CHECK (transfer_status IN ('pending', 'in_transit', 'completed', 'rejected', 'cancelled')),
    requested_by        UUID REFERENCES public.users(id) ON DELETE SET NULL,
    approved_by         UUID REFERENCES public.users(id) ON DELETE SET NULL,
    approved_at         TIMESTAMPTZ,
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_transfers_profession
    ON public.inventory_transfers(profession_id, transfer_status, created_at DESC);

DROP TRIGGER IF EXISTS trg_inventory_transfers_updated_at ON public.inventory_transfers;
CREATE TRIGGER trg_inventory_transfers_updated_at
    BEFORE UPDATE ON public.inventory_transfers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 8. INVENTORY TRANSFER LINES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inventory_transfer_lines (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_id         UUID NOT NULL REFERENCES public.inventory_transfers(id) ON DELETE CASCADE,
    inventory_item_id   UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    quantity            INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    quantity_received   INTEGER DEFAULT 0,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transfer_lines_transfer
    ON public.inventory_transfer_lines(transfer_id);

-- ============================================================
-- 9. INVENTORY ALERTS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inventory_alerts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    inventory_item_id   UUID REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    alert_type          TEXT NOT NULL
                            CHECK (alert_type IN ('low_stock', 'expiry_warning', 'expired', 'reorder', 'overstock')),
    severity            TEXT NOT NULL DEFAULT 'medium'
                            CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    message             TEXT NOT NULL,
    is_resolved         BOOLEAN DEFAULT false,
    resolved_by         UUID REFERENCES public.users(id) ON DELETE SET NULL,
    resolved_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_alerts_unresolved
    ON public.inventory_alerts(profession_id, is_resolved, alert_type)
    WHERE is_resolved = false;
CREATE INDEX IF NOT EXISTS idx_inventory_alerts_profession
    ON public.inventory_alerts(profession_id, created_at DESC);

-- ============================================================
-- 10. RLS POLICIES
-- ============================================================
ALTER TABLE public.custom_medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stocktake_configurations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stocktake_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stocktake_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transfer_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "custom_medications_select" ON public.custom_medications;
CREATE POLICY "custom_medications_select" ON public.custom_medications FOR SELECT USING (true);
DROP POLICY IF EXISTS "custom_medications_modify" ON public.custom_medications;
CREATE POLICY "custom_medications_modify" ON public.custom_medications FOR ALL USING (true);

DROP POLICY IF EXISTS "inventory_items_select" ON public.inventory_items;
CREATE POLICY "inventory_items_select" ON public.inventory_items FOR SELECT USING (true);
DROP POLICY IF EXISTS "inventory_items_modify" ON public.inventory_items;
CREATE POLICY "inventory_items_modify" ON public.inventory_items FOR ALL USING (true);

DROP POLICY IF EXISTS "stocktake_config_select" ON public.stocktake_configurations;
CREATE POLICY "stocktake_config_select" ON public.stocktake_configurations FOR SELECT USING (true);
DROP POLICY IF EXISTS "stocktake_config_modify" ON public.stocktake_configurations;
CREATE POLICY "stocktake_config_modify" ON public.stocktake_configurations FOR ALL USING (true);

DROP POLICY IF EXISTS "stocktake_sessions_select" ON public.stocktake_sessions;
CREATE POLICY "stocktake_sessions_select" ON public.stocktake_sessions FOR SELECT USING (true);
DROP POLICY IF EXISTS "stocktake_sessions_modify" ON public.stocktake_sessions;
CREATE POLICY "stocktake_sessions_modify" ON public.stocktake_sessions FOR ALL USING (true);

DROP POLICY IF EXISTS "stocktake_lines_select" ON public.stocktake_lines;
CREATE POLICY "stocktake_lines_select" ON public.stocktake_lines FOR SELECT USING (true);
DROP POLICY IF EXISTS "stocktake_lines_modify" ON public.stocktake_lines;
CREATE POLICY "stocktake_lines_modify" ON public.stocktake_lines FOR ALL USING (true);

DROP POLICY IF EXISTS "stock_adjustments_select" ON public.stock_adjustments;
CREATE POLICY "stock_adjustments_select" ON public.stock_adjustments FOR SELECT USING (true);
DROP POLICY IF EXISTS "stock_adjustments_modify" ON public.stock_adjustments;
CREATE POLICY "stock_adjustments_modify" ON public.stock_adjustments FOR ALL USING (true);

DROP POLICY IF EXISTS "inventory_transfers_select" ON public.inventory_transfers;
CREATE POLICY "inventory_transfers_select" ON public.inventory_transfers FOR SELECT USING (true);
DROP POLICY IF EXISTS "inventory_transfers_modify" ON public.inventory_transfers;
CREATE POLICY "inventory_transfers_modify" ON public.inventory_transfers FOR ALL USING (true);

DROP POLICY IF EXISTS "inventory_transfer_lines_select" ON public.inventory_transfer_lines;
CREATE POLICY "inventory_transfer_lines_select" ON public.inventory_transfer_lines FOR SELECT USING (true);
DROP POLICY IF EXISTS "inventory_transfer_lines_modify" ON public.inventory_transfer_lines;
CREATE POLICY "inventory_transfer_lines_modify" ON public.inventory_transfer_lines FOR ALL USING (true);

DROP POLICY IF EXISTS "inventory_alerts_select" ON public.inventory_alerts;
CREATE POLICY "inventory_alerts_select" ON public.inventory_alerts FOR SELECT USING (true);
DROP POLICY IF EXISTS "inventory_alerts_modify" ON public.inventory_alerts;
CREATE POLICY "inventory_alerts_modify" ON public.inventory_alerts FOR ALL USING (true);

-- ============================================================
-- 11. RPC FUNCTIONS
-- ============================================================

-- 11.1 Deduct inventory FEFO (auto pick lots by expiry date)
CREATE OR REPLACE FUNCTION deduct_inventory_fefo(
    p_profession_id UUID,
    p_inventory_item_id UUID,
    p_quantity INTEGER,
    p_reference_type TEXT DEFAULT 'sale',  -- 'sale', 'transfer', 'adjustment', 'prescription'
    p_reference_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_lot RECORD;
    v_remaining INTEGER := p_quantity;
    v_lot_deductions JSONB := '[]'::JSONB;
    v_total_deducted INTEGER := 0;
BEGIN
    IF p_quantity <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'quantity must be > 0');
    END IF;

    -- Lock lots in FEFO order (expiry date ASC, created_at ASC)
    FOR v_lot IN
        SELECT id, quantity_remaining, expiry_date
        FROM public.inventory_lots
        WHERE profession_id = p_profession_id
          AND product_id = (
              SELECT product_id FROM public.inventory_items WHERE id = p_inventory_item_id
          )
          AND status = 'active'
          AND quantity_remaining > 0
        ORDER BY COALESCE(expiry_date, '9999-12-31'::DATE) ASC, created_at ASC
        FOR UPDATE
    LOOP
        EXIT WHEN v_remaining <= 0;

        DECLARE
            v_deduct INTEGER;
        BEGIN
            v_deduct := LEAST(v_lot.quantity_remaining, v_remaining);
            v_remaining := v_remaining - v_deduct;
            v_total_deducted := v_total_deducted + v_deduct;

            -- Deduct from lot
            UPDATE public.inventory_lots
            SET quantity_remaining = quantity_remaining - v_deduct,
                status = CASE WHEN (quantity_remaining - v_deduct) <= 0 THEN 'depleted' ELSE status END,
                updated_at = NOW()
            WHERE id = v_lot.id;

            -- Record stock movement
            INSERT INTO public.stock_movements (
                profession_id, product_id, lot_id,
                movement_type, quantity, unit_cost,
                reference_type, reference_id, notes
            )
            SELECT
                p_profession_id, ii.product_id, v_lot.id,
                'out', v_deduct, il.unit_cost,
                p_reference_type, p_reference_id,
                'FEFO deduction lot ' || il.lot_number
            FROM public.inventory_items ii
            JOIN public.inventory_lots il ON il.id = v_lot.id
            WHERE ii.id = p_inventory_item_id;

            v_lot_deductions := v_lot_deductions || jsonb_build_object(
                'lot_id', v_lot.id,
                'quantity_deducted', v_deduct,
                'expiry_date', v_lot.expiry_date
            );
        END;
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
            'lots', v_lot_deductions,
            'error', 'insufficient stock'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'deducted', v_total_deducted,
        'lots', v_lot_deductions
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11.2 Create stock adjustment + update inventory
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
        profession_id, product_id,
        movement_type, quantity, unit_cost,
        reference_type, reference_id, notes
    )
    SELECT
        p_profession_id, ii.product_id,
        CASE WHEN p_quantity_after >= v_quantity_before THEN 'in' ELSE 'out' END,
        ABS(p_quantity_after - v_quantity_before), ii.cost_price,
        'adjustment', v_adjustment_id, p_reason
    FROM public.inventory_items ii
    WHERE ii.id = p_inventory_item_id;

    RETURN v_adjustment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11.3 Create inventory transfer
CREATE OR REPLACE FUNCTION create_inventory_transfer(
    p_profession_id UUID,
    p_from_branch_id UUID,
    p_from_warehouse_id UUID,
    p_to_branch_id UUID,
    p_to_warehouse_id UUID,
    p_items JSONB, -- [{inventory_item_id, quantity}, ...]
    p_requested_by UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_transfer_id UUID;
    v_item RECORD;
    v_from_qty INTEGER;
BEGIN
    -- Create transfer header
    INSERT INTO public.inventory_transfers (
        profession_id, from_branch_id, from_warehouse_id,
        to_branch_id, to_warehouse_id, requested_by, notes
    )
    VALUES (
        p_profession_id, p_from_branch_id, p_from_warehouse_id,
        p_to_branch_id, p_to_warehouse_id, p_requested_by, p_notes
    )
    RETURNING id INTO v_transfer_id;

    -- Create transfer lines + reserve stock
    FOR v_item IN
        SELECT
            (elem->>'inventory_item_id')::UUID AS inventory_item_id,
            (elem->>'quantity')::INTEGER AS quantity
        FROM jsonb_array_elements(p_items) AS elem
    LOOP
        -- Check sufficient stock
        SELECT quantity INTO v_from_qty
        FROM public.inventory_items
        WHERE id = v_item.inventory_item_id AND profession_id = p_profession_id;

        IF v_from_qty IS NULL OR v_from_qty < v_item.quantity THEN
            RAISE EXCEPTION 'insufficient stock for item %', v_item.inventory_item_id;
        END IF;

        INSERT INTO public.inventory_transfer_lines (
            transfer_id, inventory_item_id, quantity
        )
        VALUES (v_transfer_id, v_item.inventory_item_id, v_item.quantity);

        -- Reserve quantity (soft hold)
        UPDATE public.inventory_items
        SET quantity = quantity - v_item.quantity,
            updated_at = NOW()
        WHERE id = v_item.inventory_item_id AND profession_id = p_profession_id;
    END LOOP;

    RETURN v_transfer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11.4 Complete transfer (receive at destination)
CREATE OR REPLACE FUNCTION complete_inventory_transfer(
    p_transfer_id UUID,
    p_approved_by UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_transfer RECORD;
    v_line RECORD;
BEGIN
    SELECT * INTO v_transfer
    FROM public.inventory_transfers WHERE id = p_transfer_id;

    IF v_transfer IS NULL OR v_transfer.transfer_status != 'in_transit' THEN
        RETURN false;
    END IF;

    UPDATE public.inventory_transfers
    SET transfer_status = 'completed',
        approved_by = p_approved_by,
        approved_at = NOW(),
        updated_at = NOW()
    WHERE id = p_transfer_id;

    -- Update destination inventory (upsert or insert)
    FOR v_line IN
        SELECT * FROM public.inventory_transfer_lines WHERE transfer_id = p_transfer_id
    LOOP
        UPDATE public.inventory_items
        SET quantity = quantity + v_line.quantity,
            updated_at = NOW()
        WHERE id = v_line.inventory_item_id AND profession_id = v_transfer.profession_id;
    END LOOP;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11.5 Check reorder and expiry alerts
CREATE OR REPLACE FUNCTION check_inventory_alerts(p_profession_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_rows  INTEGER;
BEGIN
    -- Low stock alerts
    INSERT INTO public.inventory_alerts (
        profession_id, inventory_item_id, alert_type, severity, message
    )
    SELECT
        p_profession_id, ii.id, 'low_stock', 'high',
        'สินค้า ' || COALESCE(p.name, cm.name) || ' เหลือ ' || ii.quantity || ' (จุดสั่งซื้อ ' || ii.reorder_point || ')'
    FROM public.inventory_items ii
    LEFT JOIN public.products p ON p.id = ii.product_id
    LEFT JOIN public.custom_medications cm ON cm.id = ii.custom_medication_id
    WHERE ii.profession_id = p_profession_id
      AND ii.is_active = true
      AND ii.quantity <= ii.reorder_point
      AND ii.quantity > 0
      AND NOT EXISTS (
          SELECT 1 FROM public.inventory_alerts ia
          WHERE ia.inventory_item_id = ii.id
            AND ia.alert_type = 'low_stock'
            AND ia.is_resolved = false
            AND ia.created_at > NOW() - INTERVAL '24 hours'
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Expiry warning (within 30 days)
    INSERT INTO public.inventory_alerts (
        profession_id, inventory_item_id, alert_type, severity, message
    )
    SELECT DISTINCT
        p_profession_id, ii.id, 'expiry_warning', 'medium',
        'ยา ' || COALESCE(p.name, cm.name) || ' lot ' || il.lot_number || ' ใกล้หมดอายุ (' || il.expiry_date || ')'
    FROM public.inventory_items ii
    JOIN public.inventory_lots il ON il.product_id = ii.product_id
    LEFT JOIN public.products p ON p.id = ii.product_id
    LEFT JOIN public.custom_medications cm ON cm.id = ii.custom_medication_id
    WHERE ii.profession_id = p_profession_id
      AND ii.is_active = true
      AND il.status = 'active'
      AND il.expiry_date IS NOT NULL
      AND il.expiry_date <= CURRENT_DATE + INTERVAL '30 days'
      AND il.expiry_date > CURRENT_DATE
      AND il.quantity_remaining > 0
      AND NOT EXISTS (
          SELECT 1 FROM public.inventory_alerts ia
          WHERE ia.inventory_item_id = ii.id
            AND ia.alert_type = 'expiry_warning'
            AND ia.is_resolved = false
            AND ia.created_at > NOW() - INTERVAL '24 hours'
      );

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_count := v_count + v_rows;

    -- Expired
    INSERT INTO public.inventory_alerts (
        profession_id, inventory_item_id, alert_type, severity, message
    )
    SELECT DISTINCT
        p_profession_id, ii.id, 'expired', 'critical',
        'ยา ' || COALESCE(p.name, cm.name) || ' lot ' || il.lot_number || ' หมดอายุแล้ว (' || il.expiry_date || ')'
    FROM public.inventory_items ii
    JOIN public.inventory_lots il ON il.product_id = ii.product_id
    LEFT JOIN public.products p ON p.id = ii.product_id
    LEFT JOIN public.custom_medications cm ON cm.id = ii.custom_medication_id
    WHERE ii.profession_id = p_profession_id
      AND ii.is_active = true
      AND il.status = 'active'
      AND il.expiry_date IS NOT NULL
      AND il.expiry_date <= CURRENT_DATE
      AND il.quantity_remaining > 0
      AND NOT EXISTS (
          SELECT 1 FROM public.inventory_alerts ia
          WHERE ia.inventory_item_id = ii.id
            AND ia.alert_type = 'expired'
            AND ia.is_resolved = false
            AND ia.created_at > NOW() - INTERVAL '24 hours'
      );

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_count := v_count + v_rows;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11.6 Complete stocktake session + create adjustments
CREATE OR REPLACE FUNCTION complete_stocktake_session(
    p_session_id UUID,
    p_approved_by UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_line RECORD;
BEGIN
    -- Validate all lines counted
    IF EXISTS (
        SELECT 1 FROM public.stocktake_lines
        WHERE stocktake_session_id = p_session_id AND counted_quantity IS NULL
    ) THEN
        RAISE EXCEPTION 'some items not counted';
    END IF;

    -- Create stock adjustments for variances
    FOR v_line IN
        SELECT * FROM public.stocktake_lines
        WHERE stocktake_session_id = p_session_id AND variance <> 0
    LOOP
        PERFORM create_stock_adjustment(
            (SELECT profession_id FROM public.stocktake_sessions WHERE id = p_session_id),
            v_line.inventory_item_id,
            'count',
            v_line.counted_quantity,
            'Stocktake variance: ' || v_line.variance,
            p_approved_by,
            p_session_id
        );
        v_count := v_count + 1;
    END LOOP;

    UPDATE public.stocktake_sessions
    SET status = 'completed',
        completed_at = NOW(),
        approved_by = p_approved_by,
        approved_at = NOW(),
        updated_at = NOW()
    WHERE id = p_session_id;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
