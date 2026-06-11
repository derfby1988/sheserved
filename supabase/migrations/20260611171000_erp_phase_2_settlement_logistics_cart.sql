-- Migration: ERP Phase 2 — Settlement Core + Logistics Core + Cart Core
-- Date: 2026-06-11
-- Prerequisites: Phase 2 Step 1 (checkout_sessions, payment_transactions, delivery_orders)

-- ============================================================
-- 1. SETTLEMENT CORE
-- ============================================================

-- 1.1 Vendor Contracts (fee/payout agreement per profession)
CREATE TABLE IF NOT EXISTS public.vendor_contracts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    vendor_name     TEXT NOT NULL,
    vendor_type     TEXT NOT NULL DEFAULT 'merchant'
                        CHECK (vendor_type IN ('merchant', 'delivery_partner', 'payment_provider', 'platform')),
    contract_code   TEXT UNIQUE,                           -- รหัสสัญญา
    fee_percent     DECIMAL(5,2) NOT NULL DEFAULT 0,       -- % fee ที่ vendor เก็บ
    fixed_fee_per_txn DECIMAL(12,2) DEFAULT 0,             -- fee คงที่ต่อรายการ
    min_fee         DECIMAL(12,2) DEFAULT 0,
    max_fee         DECIMAL(12,2) DEFAULT 0,
    payout_cycle_days INTEGER DEFAULT 7,                   -- จำนวนวัน payout
    is_active       BOOLEAN DEFAULT true,
    effective_from  DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_until DATE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vendor_contracts_profession
    ON public.vendor_contracts(profession_id, is_active, vendor_type);

DROP TRIGGER IF EXISTS trg_vendor_contracts_updated_at ON public.vendor_contracts;
CREATE TRIGGER trg_vendor_contracts_updated_at
    BEFORE UPDATE ON public.vendor_contracts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.2 Merchant Accounts (bank/payment account per profession)
CREATE TABLE IF NOT EXISTS public.merchant_accounts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    account_name    TEXT NOT NULL,                         -- ชื่อบัญชี
    account_number  TEXT NOT NULL,
    bank_code       TEXT NOT NULL,                         -- รหัสธนาคาร
    bank_name       TEXT NOT NULL,
    account_type    TEXT NOT NULL DEFAULT 'savings'
                        CHECK (account_type IN ('savings', 'current', 'corporate')),
    is_primary      BOOLEAN DEFAULT false,                  -- บัญชีหลักสำหรับ payout
    is_verified     BOOLEAN DEFAULT false,
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merchant_accounts_profession
    ON public.merchant_accounts(profession_id, is_primary, is_verified);

DROP TRIGGER IF EXISTS trg_merchant_accounts_updated_at ON public.merchant_accounts;
CREATE TRIGGER trg_merchant_accounts_updated_at
    BEFORE UPDATE ON public.merchant_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.3 Payment Allocations (fee/payout split per transaction)
CREATE TABLE IF NOT EXISTS public.payment_allocations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    payment_txn_id  UUID NOT NULL REFERENCES public.payment_transactions(id) ON DELETE CASCADE,
    vendor_contract_id UUID REFERENCES public.vendor_contracts(id) ON DELETE SET NULL,
    gross_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,       -- ยอดรวมก่อนหัก
    fee_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,     -- ค่าธรรมเนียม
    net_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,     -- ยอดสุทธิ
    platform_fee    DECIMAL(12,2) NOT NULL DEFAULT 0,      -- fee ของแพลตฟอร์ม
    merchant_payout DECIMAL(12,2) NOT NULL DEFAULT 0,     -- เงินที่ merchant ได้
    allocation_status TEXT NOT NULL DEFAULT 'pending'
                        CHECK (allocation_status IN ('pending', 'calculated', 'paid_out', 'failed')),
    paid_out_at     TIMESTAMPTZ,
    payout_reference TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_allocations_profession
    ON public.payment_allocations(profession_id, allocation_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_allocations_order
    ON public.payment_allocations(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_allocations_txn
    ON public.payment_allocations(payment_txn_id);

-- ============================================================
-- 2. LOGISTICS CORE
-- ============================================================

-- 2.1 Riders
CREATE TABLE IF NOT EXISTS public.riders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES public.users(id) ON DELETE SET NULL,
    rider_code      TEXT NOT NULL,                          -- รหัสไรเดอร์
    full_name       TEXT NOT NULL,
    phone           TEXT NOT NULL,
    email           TEXT,
    vehicle_type    TEXT NOT NULL DEFAULT 'motorcycle'
                        CHECK (vehicle_type IN ('motorcycle', 'car', 'bicycle', 'van')),
    license_plate   TEXT,
    is_active       BOOLEAN DEFAULT true,
    is_available    BOOLEAN DEFAULT true,                  -- ว่าง/ไม่ว่างตอนนี้
    current_lat     DECIMAL(10,8),
    current_lng     DECIMAL(11,8),
    current_location_updated_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_riders_profession
    ON public.riders(profession_id, is_active, is_available);

DROP TRIGGER IF EXISTS trg_riders_updated_at ON public.riders;
CREATE TRIGGER trg_riders_updated_at
    BEFORE UPDATE ON public.riders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2.2 Delivery Runs (batch assignment of orders to a rider)
CREATE TABLE IF NOT EXISTS public.delivery_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    rider_id        UUID NOT NULL REFERENCES public.riders(id) ON DELETE RESTRICT,
    run_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    status          TEXT NOT NULL DEFAULT 'preparing'
                        CHECK (status IN (
                            'preparing',      -- เตรียมรายการ
                            'ready',          -- พร้อมให้ไรเดอร์มารับ
                            'in_progress',    -- ไรเดอร์กำลังส่ง
                            'completed',      -- ส่งครบทุกรายการ
                            'cancelled'       -- ยกเลิก
                        )),
    total_orders    INTEGER NOT NULL DEFAULT 0,
    completed_orders INTEGER NOT NULL DEFAULT 0,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_runs_profession
    ON public.delivery_runs(profession_id, status, run_date DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_runs_rider
    ON public.delivery_runs(rider_id, status);

DROP TRIGGER IF EXISTS trg_delivery_runs_updated_at ON public.delivery_runs;
CREATE TRIGGER trg_delivery_runs_updated_at
    BEFORE UPDATE ON public.delivery_runs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2.3 Route Stops (sequence of deliveries in a run)
CREATE TABLE IF NOT EXISTS public.route_stops (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_run_id UUID NOT NULL REFERENCES public.delivery_runs(id) ON DELETE CASCADE,
    delivery_order_id UUID NOT NULL REFERENCES public.delivery_orders(id) ON DELETE CASCADE,
    stop_sequence   INTEGER NOT NULL DEFAULT 1,           -- ลำดับการส่ง
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'arrived', 'delivered', 'failed', 'skipped')),
    estimated_arrival TIMESTAMPTZ,
    actual_arrival  TIMESTAMPTZ,
    delivery_photo_url TEXT,
    signature_url   TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_route_stops_run
    ON public.route_stops(delivery_run_id, stop_sequence);
CREATE INDEX IF NOT EXISTS idx_route_stops_delivery
    ON public.route_stops(delivery_order_id);

DROP TRIGGER IF EXISTS trg_route_stops_updated_at ON public.route_stops;
CREATE TRIGGER trg_route_stops_updated_at
    BEFORE UPDATE ON public.route_stops
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. CART CORE (normalized cart — แทน JSONB ในอนาคต)
-- ============================================================

-- 3.1 Cart Sessions
CREATE TABLE IF NOT EXISTS public.cart_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    customer_id     UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    session_type    TEXT NOT NULL DEFAULT 'self_service'
                        CHECK (session_type IN ('self_service', 'counter_pos', 'clinic_pos')),
    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'checked_out', 'abandoned', 'expired')),
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    vat_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    net_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    item_count      INTEGER NOT NULL DEFAULT 0,
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cart_sessions_profession
    ON public.cart_sessions(profession_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cart_sessions_user
    ON public.cart_sessions(user_id, status)
    WHERE status = 'active';

DROP TRIGGER IF EXISTS trg_cart_sessions_updated_at ON public.cart_sessions;
CREATE TRIGGER trg_cart_sessions_updated_at
    BEFORE UPDATE ON public.cart_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3.2 Cart Items (normalized line items)
CREATE TABLE IF NOT EXISTS public.cart_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_session_id UUID NOT NULL REFERENCES public.cart_sessions(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity        INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price      DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    vat_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    line_total      DECIMAL(12,2) NOT NULL DEFAULT 0,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cart_items_session
    ON public.cart_items(cart_session_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product
    ON public.cart_items(product_id);

DROP TRIGGER IF EXISTS trg_cart_items_updated_at ON public.cart_items;
CREATE TRIGGER trg_cart_items_updated_at
    BEFORE UPDATE ON public.cart_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3.3 Cart Merchant Groups (split logic for multi-merchant)
CREATE TABLE IF NOT EXISTS public.cart_merchant_groups (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_session_id UUID NOT NULL REFERENCES public.cart_sessions(id) ON DELETE CASCADE,
    merchant_type   TEXT NOT NULL DEFAULT 'profession'
                        CHECK (merchant_type IN ('profession', 'external_vendor', 'platform')),
    merchant_id     UUID,                                   -- profession_id หรือ vendor_id
    subtotal        DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    vat_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    net_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cart_merchant_groups_session
    ON public.cart_merchant_groups(cart_session_id);

-- ============================================================
-- 4. RLS POLICIES (Idempotent)
-- ============================================================
ALTER TABLE public.vendor_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.riders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_merchant_groups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vendor_contracts_select" ON public.vendor_contracts;
CREATE POLICY "vendor_contracts_select" ON public.vendor_contracts FOR SELECT USING (true);
DROP POLICY IF EXISTS "vendor_contracts_modify" ON public.vendor_contracts;
CREATE POLICY "vendor_contracts_modify" ON public.vendor_contracts FOR ALL USING (true);

DROP POLICY IF EXISTS "merchant_accounts_select" ON public.merchant_accounts;
CREATE POLICY "merchant_accounts_select" ON public.merchant_accounts FOR SELECT USING (true);
DROP POLICY IF EXISTS "merchant_accounts_modify" ON public.merchant_accounts;
CREATE POLICY "merchant_accounts_modify" ON public.merchant_accounts FOR ALL USING (true);

DROP POLICY IF EXISTS "payment_allocations_select" ON public.payment_allocations;
CREATE POLICY "payment_allocations_select" ON public.payment_allocations FOR SELECT USING (true);
DROP POLICY IF EXISTS "payment_allocations_modify" ON public.payment_allocations;
CREATE POLICY "payment_allocations_modify" ON public.payment_allocations FOR ALL USING (true);

DROP POLICY IF EXISTS "riders_select" ON public.riders;
CREATE POLICY "riders_select" ON public.riders FOR SELECT USING (true);
DROP POLICY IF EXISTS "riders_modify" ON public.riders;
CREATE POLICY "riders_modify" ON public.riders FOR ALL USING (true);

DROP POLICY IF EXISTS "delivery_runs_select" ON public.delivery_runs;
CREATE POLICY "delivery_runs_select" ON public.delivery_runs FOR SELECT USING (true);
DROP POLICY IF EXISTS "delivery_runs_modify" ON public.delivery_runs;
CREATE POLICY "delivery_runs_modify" ON public.delivery_runs FOR ALL USING (true);

DROP POLICY IF EXISTS "route_stops_select" ON public.route_stops;
CREATE POLICY "route_stops_select" ON public.route_stops FOR SELECT USING (true);
DROP POLICY IF EXISTS "route_stops_modify" ON public.route_stops;
CREATE POLICY "route_stops_modify" ON public.route_stops FOR ALL USING (true);

DROP POLICY IF EXISTS "cart_sessions_select" ON public.cart_sessions;
CREATE POLICY "cart_sessions_select" ON public.cart_sessions FOR SELECT USING (true);
DROP POLICY IF EXISTS "cart_sessions_modify" ON public.cart_sessions;
CREATE POLICY "cart_sessions_modify" ON public.cart_sessions FOR ALL USING (true);

DROP POLICY IF EXISTS "cart_items_select" ON public.cart_items;
CREATE POLICY "cart_items_select" ON public.cart_items FOR SELECT USING (true);
DROP POLICY IF EXISTS "cart_items_modify" ON public.cart_items;
CREATE POLICY "cart_items_modify" ON public.cart_items FOR ALL USING (true);

DROP POLICY IF EXISTS "cart_merchant_groups_select" ON public.cart_merchant_groups;
CREATE POLICY "cart_merchant_groups_select" ON public.cart_merchant_groups FOR SELECT USING (true);
DROP POLICY IF EXISTS "cart_merchant_groups_modify" ON public.cart_merchant_groups;
CREATE POLICY "cart_merchant_groups_modify" ON public.cart_merchant_groups FOR ALL USING (true);

-- ============================================================
-- 5. RPC FUNCTIONS
-- ============================================================

-- Calculate payment allocation based on vendor contract
CREATE OR REPLACE FUNCTION calculate_payment_allocation(
    p_order_id UUID,
    p_payment_txn_id UUID,
    p_gross_amount DECIMAL(12,2)
)
RETURNS UUID AS $$
DECLARE
    v_profession_id UUID;
    v_contract RECORD;
    v_fee_amount DECIMAL(12,2);
    v_net_amount DECIMAL(12,2);
    v_platform_fee DECIMAL(12,2);
    v_merchant_payout DECIMAL(12,2);
    v_allocation_id UUID;
BEGIN
    -- Get profession_id from order
    SELECT profession_id INTO v_profession_id
    FROM public.orders WHERE id = p_order_id;

    -- Find active vendor contract for the profession
    SELECT * INTO v_contract
    FROM public.vendor_contracts
    WHERE profession_id = v_profession_id
      AND is_active = true
      AND effective_from <= CURRENT_DATE
      AND (effective_until IS NULL OR effective_until >= CURRENT_DATE)
    ORDER BY fee_percent DESC
    LIMIT 1;

    -- Calculate fees
    IF v_contract IS NOT NULL THEN
        v_fee_amount := LEAST(
            GREATEST(
                (p_gross_amount * v_contract.fee_percent / 100) + v_contract.fixed_fee_per_txn,
                v_contract.min_fee
            ),
            CASE WHEN v_contract.max_fee > 0 THEN v_contract.max_fee ELSE p_gross_amount END
        );
    ELSE
        v_fee_amount := 0;
    END IF;

    v_platform_fee := v_fee_amount * 0.3;  -- 30% of fee goes to platform
    v_merchant_payout := p_gross_amount - v_fee_amount;
    v_net_amount := p_gross_amount - v_fee_amount;

    INSERT INTO public.payment_allocations (
        profession_id, order_id, payment_txn_id, vendor_contract_id,
        gross_amount, fee_amount, net_amount, platform_fee, merchant_payout,
        allocation_status
    )
    VALUES (
        v_profession_id, p_order_id, p_payment_txn_id, v_contract.id,
        p_gross_amount, v_fee_amount, v_net_amount, v_platform_fee, v_merchant_payout,
        'calculated'
    )
    RETURNING id INTO v_allocation_id;

    RETURN v_allocation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Assign delivery order to rider + create route stop
CREATE OR REPLACE FUNCTION assign_delivery_to_rider(
    p_delivery_order_id UUID,
    p_rider_id UUID,
    p_stop_sequence INTEGER DEFAULT 1
)
RETURNS UUID AS $$
DECLARE
    v_run_id UUID;
    v_profession_id UUID;
    v_route_stop_id UUID;
BEGIN
    -- Get profession_id
    SELECT profession_id INTO v_profession_id
    FROM public.delivery_orders WHERE id = p_delivery_order_id;

    -- Create or find active delivery run for rider today
    SELECT id INTO v_run_id
    FROM public.delivery_runs
    WHERE rider_id = p_rider_id
      AND run_date = CURRENT_DATE
      AND status IN ('preparing', 'ready', 'in_progress')
    LIMIT 1;

    IF v_run_id IS NULL THEN
        INSERT INTO public.delivery_runs (
            profession_id, rider_id, run_date, status
        )
        VALUES (v_profession_id, p_rider_id, CURRENT_DATE, 'preparing')
        RETURNING id INTO v_run_id;
    END IF;

    -- Create route stop
    INSERT INTO public.route_stops (
        delivery_run_id, delivery_order_id, stop_sequence, status
    )
    VALUES (v_run_id, p_delivery_order_id, p_stop_sequence, 'pending')
    RETURNING id INTO v_route_stop_id;

    -- Update delivery order status
    UPDATE public.delivery_orders
    SET delivery_status = 'preparing', updated_at = NOW()
    WHERE id = p_delivery_order_id;

    -- Update run total
    UPDATE public.delivery_runs
    SET total_orders = total_orders + 1, updated_at = NOW()
    WHERE id = v_run_id;

    RETURN v_route_stop_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add item to cart and recalculate totals
CREATE OR REPLACE FUNCTION add_item_to_cart(
    p_cart_session_id UUID,
    p_product_id UUID,
    p_quantity INTEGER,
    p_unit_price DECIMAL(12,2)
)
RETURNS BOOLEAN AS $$
DECLARE
    v_line_total DECIMAL(12,2);
    v_vat_rate DECIMAL(5,2) := 7.0;  -- 7% VAT default
BEGIN
    v_line_total := p_quantity * p_unit_price;

    INSERT INTO public.cart_items (
        cart_session_id, product_id, quantity, unit_price,
        line_total, vat_amount
    )
    VALUES (
        p_cart_session_id, p_product_id, p_quantity, p_unit_price,
        v_line_total, (v_line_total * v_vat_rate / 100)
    );

    -- Recalculate cart session totals
    UPDATE public.cart_sessions
    SET total_amount = (
        SELECT COALESCE(SUM(line_total), 0) FROM public.cart_items WHERE cart_session_id = p_cart_session_id
    ),
    vat_amount = (
        SELECT COALESCE(SUM(vat_amount), 0) FROM public.cart_items WHERE cart_session_id = p_cart_session_id
    ),
    net_amount = (
        SELECT COALESCE(SUM(line_total + vat_amount), 0) FROM public.cart_items WHERE cart_session_id = p_cart_session_id
    ),
    item_count = (
        SELECT COUNT(*) FROM public.cart_items WHERE cart_session_id = p_cart_session_id
    ),
    updated_at = NOW()
    WHERE id = p_cart_session_id;

    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
