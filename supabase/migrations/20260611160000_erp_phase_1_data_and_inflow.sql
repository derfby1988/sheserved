-- Migration: ERP Phase 1 — Data & Inflow
-- Date: 2026-06-11
-- Prerequisites: users, professions, organization_branches (Phase 0)
-- Modules: CRM + Procurement + Inventory Core + Product/Service Master

-- ============================================================
-- 0. FIX: Ensure prerequisite columns exist on tables from earlier migrations
-- ============================================================

-- product_categories may already exist from earlier migration with different schema
ALTER TABLE public.product_categories
ADD COLUMN IF NOT EXISTS profession_id UUID REFERENCES public.professions(id) ON DELETE CASCADE;
ALTER TABLE public.product_categories
ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.product_categories
ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0;

-- ============================================================
-- 1. PRODUCT / SERVICE MASTER — Shared Catalog
-- ============================================================

-- 1.1 Product Categories
CREATE TABLE IF NOT EXISTS public.product_categories (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    description     TEXT,
    parent_id       UUID REFERENCES public.product_categories(id) ON DELETE SET NULL,
    sort_order      INTEGER DEFAULT 0,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_product_categories_profession
    ON public.product_categories(profession_id, is_active);

DROP TRIGGER IF EXISTS trg_product_categories_updated_at ON public.product_categories;
CREATE TRIGGER trg_product_categories_updated_at
    BEFORE UPDATE ON public.product_categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.2 Products (Shared Master — ใช้ได้ทั้ง POS และ Cart)
CREATE TABLE IF NOT EXISTS public.products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    category_id     UUID REFERENCES public.product_categories(id) ON DELETE SET NULL,
    name            TEXT NOT NULL,
    description     TEXT,
    sku             TEXT,                               -- Stock Keeping Unit
    barcode         TEXT,
    unit_of_measure TEXT NOT NULL DEFAULT 'piece',      -- piece, box, bottle, gram, ml, etc.
    cost_price      DECIMAL(12,2) NOT NULL DEFAULT 0,   -- ต้นทุน (สำหรับ gross profit)
    sale_price      DECIMAL(12,2) NOT NULL DEFAULT 0,
    is_vatable      BOOLEAN DEFAULT false,
    is_active       BOOLEAN DEFAULT true,
    is_stockable    BOOLEAN DEFAULT true,               -- false = service / non-stock item
    -- สำหรับ FEFO tracking
    has_lot_tracking BOOLEAN DEFAULT false,
    shelf_life_days INTEGER,                            -- อายุการเก็บ (วัน)
    reorder_point   INTEGER DEFAULT 0,                  -- จุดสั่งซื้อใหม่
    reorder_qty     INTEGER DEFAULT 0,                  -- จำนวนที่ควรสั่ง
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_profession
    ON public.products(profession_id, is_active, name);
CREATE INDEX IF NOT EXISTS idx_products_sku
    ON public.products(profession_id, sku)
    WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_barcode
    ON public.products(profession_id, barcode)
    WHERE barcode IS NOT NULL;

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. CRM — Customer, Loyalty, Coupon
-- ============================================================

-- 2.1 Loyalty Tiers
CREATE TABLE IF NOT EXISTS public.loyalty_tiers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    tier_name       TEXT NOT NULL,                      -- เช่น Bronze, Silver, Gold
    min_points      INTEGER NOT NULL DEFAULT 0,
    discount_pct    DECIMAL(5,2) NOT NULL DEFAULT 0,   -- % ลดเพิ่ม
    description     TEXT,
    sort_order      INTEGER DEFAULT 0,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_tiers_profession
    ON public.loyalty_tiers(profession_id, is_active, sort_order);

-- 2.2 CRM Customers (link to users แต่มี profession-specific data)
CREATE TABLE IF NOT EXISTS public.customers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES public.users(id) ON DELETE SET NULL,
    customer_code   TEXT,                               -- รหัสลูกค้า (auto หรือ manual)
    customer_type   TEXT NOT NULL DEFAULT 'walk_in'
                        CHECK (customer_type IN ('walk_in', 'member', 'corporate', 'vip')),
    display_name    TEXT NOT NULL,                      -- ชื่อที่แสดงใน POS/CRM
    phone           TEXT,
    email           TEXT,
    birthday        DATE,
    notes           TEXT,
    loyalty_tier_id UUID REFERENCES public.loyalty_tiers(id) ON DELETE SET NULL,
    total_points    INTEGER NOT NULL DEFAULT 0,
    lifetime_value  DECIMAL(15,2) NOT NULL DEFAULT 0,
    visit_count     INTEGER NOT NULL DEFAULT 0,
    last_visit_at   TIMESTAMPTZ,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, customer_code)
);

CREATE INDEX IF NOT EXISTS idx_customers_profession
    ON public.customers(profession_id, is_active, display_name);
CREATE INDEX IF NOT EXISTS idx_customers_user
    ON public.customers(user_id)
    WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customers_phone
    ON public.customers(profession_id, phone)
    WHERE phone IS NOT NULL;

DROP TRIGGER IF EXISTS trg_customers_updated_at ON public.customers;
CREATE TRIGGER trg_customers_updated_at
    BEFORE UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2.3 Loyalty Points Ledger
CREATE TABLE IF NOT EXISTS public.loyalty_points (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    customer_id     UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    points_change   INTEGER NOT NULL,                 -- +earn, -redeem, -expire
    points_balance  INTEGER NOT NULL,                   -- balance หลัง transaction
    transaction_type TEXT NOT NULL
                        CHECK (transaction_type IN ('earn', 'redeem', 'expire', 'adjustment', 'bonus')),
    reference_type  TEXT,                               -- order, campaign, manual
    reference_id    UUID,
    description     TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_points_customer
    ON public.loyalty_points(customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_loyalty_points_profession
    ON public.loyalty_points(profession_id, created_at DESC);

-- 2.4 Coupons
CREATE TABLE IF NOT EXISTS public.coupons (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    code            TEXT NOT NULL,                      -- รหัสคูปอง เช่น SUMMER2026
    coupon_type     TEXT NOT NULL
                        CHECK (coupon_type IN ('percentage', 'fixed_amount', 'free_shipping', 'buy_x_get_y')),
    value           DECIMAL(12,2) NOT NULL DEFAULT 0,   -- % หรือ จำนวนเงิน
    min_order_amount DECIMAL(12,2) DEFAULT 0,
    max_discount    DECIMAL(12,2),                      -- สูงสุดที่ลดได้ (สำหรับ percentage)
    usage_limit     INTEGER,                            -- NULL = ไม่จำกัด
    usage_count     INTEGER NOT NULL DEFAULT 0,
    start_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date        DATE,                               -- NULL = ไม่หมดอายุ
    is_active       BOOLEAN DEFAULT true,
    applicable_categories JSONB DEFAULT '[]',             -- category_ids ที่ใช้ได้ (ว่าง = ทั้งหมด)
    applicable_products   JSONB DEFAULT '[]',             -- product_ids ที่ใช้ได้ (ว่าง = ทั้งหมด)
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coupons_profession
    ON public.coupons(profession_id, is_active, end_date);
CREATE INDEX IF NOT EXISTS idx_coupons_code
    ON public.coupons(profession_id, code);

DROP TRIGGER IF EXISTS trg_coupons_updated_at ON public.coupons;
CREATE TRIGGER trg_coupons_updated_at
    BEFORE UPDATE ON public.coupons
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2.5 Coupon Redemptions
CREATE TABLE IF NOT EXISTS public.coupon_redemptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    coupon_id       UUID NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
    customer_id     UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    order_id        UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (coupon_id, order_id)                        -- 1 คูปอง / 1 order
);

CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_coupon
    ON public.coupon_redemptions(coupon_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_customer
    ON public.coupon_redemptions(customer_id, created_at DESC);

-- ============================================================
-- 3. PROCUREMENT — Suppliers, PR, PO
-- ============================================================

-- 3.1 Suppliers
CREATE TABLE IF NOT EXISTS public.suppliers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    supplier_name   TEXT NOT NULL,
    contact_name    TEXT,
    phone           TEXT,
    email           TEXT,
    address         TEXT,
    tax_id          TEXT,
    payment_terms   TEXT DEFAULT 'net_30',              -- net_30, net_60, cash, etc.
    lead_time_days  INTEGER DEFAULT 7,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suppliers_profession
    ON public.suppliers(profession_id, is_active, supplier_name);

DROP TRIGGER IF EXISTS trg_suppliers_updated_at ON public.suppliers;
CREATE TRIGGER trg_suppliers_updated_at
    BEFORE UPDATE ON public.suppliers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3.2 Purchase Requisitions (PR)
CREATE TABLE IF NOT EXISTS public.purchase_requisitions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    requester_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
    pr_number       TEXT NOT NULL,                      -- PR-20260611-001
    status          TEXT NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'pending_approval', 'approved', 'rejected', 'converted')),
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    approved_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    approved_at     TIMESTAMPTZ,
    UNIQUE (profession_id, pr_number)
);

CREATE INDEX IF NOT EXISTS idx_pr_profession
    ON public.purchase_requisitions(profession_id, status, created_at DESC);

DROP TRIGGER IF EXISTS trg_pr_updated_at ON public.purchase_requisitions;
CREATE TRIGGER trg_pr_updated_at
    BEFORE UPDATE ON public.purchase_requisitions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3.3 Purchase Orders (PO)
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    supplier_id     UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE RESTRICT,
    pr_id           UUID REFERENCES public.purchase_requisitions(id) ON DELETE SET NULL,
    po_number       TEXT NOT NULL,                      -- PO-20260611-001
    status          TEXT NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'sent', 'partially_received', 'fully_received', 'cancelled')),
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    grand_total     DECIMAL(12,2) NOT NULL DEFAULT 0,
    notes           TEXT,
    expected_delivery_date DATE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, po_number)
);

CREATE INDEX IF NOT EXISTS idx_po_profession
    ON public.purchase_orders(profession_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_po_supplier
    ON public.purchase_orders(supplier_id, status);

DROP TRIGGER IF EXISTS trg_po_updated_at ON public.purchase_orders;
CREATE TRIGGER trg_po_updated_at
    BEFORE UPDATE ON public.purchase_orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3.4 Purchase Order Items
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id           UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered INTEGER NOT NULL DEFAULT 1 CHECK (quantity_ordered > 0),
    quantity_received INTEGER NOT NULL DEFAULT 0,
    unit_price      DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_price     DECIMAL(12,2) NOT NULL DEFAULT 0,
    expected_delivery_date DATE,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_po_items_po
    ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS idx_po_items_product
    ON public.purchase_order_items(product_id);

-- ============================================================
-- 4. INVENTORY CORE — Lots, Locations, Movements, Reservations
-- ============================================================

-- 4.1 Warehouse Locations
CREATE TABLE IF NOT EXISTS public.warehouse_locations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    location_code   TEXT NOT NULL,                      -- A-01-02
    location_name   TEXT NOT NULL,                      -- ชั้น A ล็อก 01 ชั้น 02
    location_type   TEXT NOT NULL DEFAULT 'shelf'
                        CHECK (location_type IN ('shelf', 'fridge', 'freezer', 'counter', 'receiving', 'dispatch', 'quarantine')),
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_warehouse_locations_profession
    ON public.warehouse_locations(profession_id, branch_id, is_active);

-- 4.2 Inventory Lots (FEFO tracking)
CREATE TABLE IF NOT EXISTS public.inventory_lots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    warehouse_location_id UUID REFERENCES public.warehouse_locations(id) ON DELETE SET NULL,
    lot_number      TEXT NOT NULL,                      -- Lot/Batch number
    expiry_date     DATE,                               -- วันหมดอายุ (NULL = ไม่มี)
    manufacture_date DATE,                              -- วันผลิต
    quantity_received INTEGER NOT NULL DEFAULT 0,       -- จำนวนที่รับเข้า
    quantity_remaining INTEGER NOT NULL DEFAULT 0,     -- จำนวนคงเหลือ
    unit_cost       DECIMAL(12,2) NOT NULL DEFAULT 0, -- ต้นทุนต่อหน่วย
    po_id           UUID REFERENCES public.purchase_orders(id) ON DELETE SET NULL,
    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'expired', 'depleted', 'quarantined', 'returned')),
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_lots_product
    ON public.inventory_lots(product_id, status, expiry_date);
CREATE INDEX IF NOT EXISTS idx_inventory_lots_profession
    ON public.inventory_lots(profession_id, status);
CREATE INDEX IF NOT EXISTS idx_inventory_lots_expiry
    ON public.inventory_lots(expiry_date)
    WHERE expiry_date IS NOT NULL AND status = 'active';

-- 4.3 Stock Movements (Ledger)
CREATE TABLE IF NOT EXISTS public.stock_movements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    lot_id          UUID REFERENCES public.inventory_lots(id) ON DELETE SET NULL,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    warehouse_location_id UUID REFERENCES public.warehouse_locations(id) ON DELETE SET NULL,
    movement_type   TEXT NOT NULL
                        CHECK (movement_type IN (
                            'receipt',          -- รับเข้าจาก PO
                            'sale',             -- ขาย (POS)
                            'return_in',        -- ลูกค้าคืน
                            'return_out',       -- คืนผู้จำหน่าย
                            'adjustment',       -- ปรับยอด
                            'transfer_in',      -- รับโอนย้าย
                            'transfer_out',     -- โอนย้ายออก
                            'expired',          -- หมดอายุ
                            'damaged',          -- เสียหาย
                            'initial_stock'     -- ยกยอดมา
                        )),
    quantity        INTEGER NOT NULL,                  -- + = เข้า, - = ออก
    unit_cost       DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_cost      DECIMAL(12,2) NOT NULL DEFAULT 0,
    -- อ้างอิง transaction ที่ก่อให้เกิด movement
    reference_type  TEXT,                               -- order, po, adjustment, transfer
    reference_id    UUID,
    notes           TEXT,
    created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_product
    ON public.stock_movements(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_lot
    ON public.stock_movements(lot_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_reference
    ON public.stock_movements(reference_type, reference_id);

-- 4.4 Inventory Reservations (ป้องกัน oversell)
CREATE TABLE IF NOT EXISTS public.inventory_reservations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    lot_id          UUID REFERENCES public.inventory_lots(id) ON DELETE SET NULL,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    quantity_reserved INTEGER NOT NULL DEFAULT 0 CHECK (quantity_reserved > 0),
    quantity_fulfilled INTEGER NOT NULL DEFAULT 0,
    quantity_cancelled INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'fulfilled', 'cancelled', 'expired')),
    reservation_type TEXT NOT NULL
                        CHECK (reservation_type IN ('cart', 'order', 'hold', 'preorder')),
    reference_id    UUID NOT NULL,                      -- cart_id / order_id / etc.
    expires_at      TIMESTAMPTZ NOT NULL,               -- หมดอายุการจอง
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_reservations_product
    ON public.inventory_reservations(product_id, status, expires_at);
CREATE INDEX IF NOT EXISTS idx_inventory_reservations_reference
    ON public.inventory_reservations(reservation_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_inventory_reservations_expiry
    ON public.inventory_reservations(expires_at)
    WHERE status = 'active';

-- ============================================================
-- 5. RLS Policies
-- ============================================================
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_requisitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.warehouse_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_reservations ENABLE ROW LEVEL SECURITY;

-- Allow all for now (application-layer auth)
DROP POLICY IF EXISTS "product_categories_select" ON public.product_categories;
CREATE POLICY "product_categories_select" ON public.product_categories FOR SELECT USING (true);
DROP POLICY IF EXISTS "product_categories_modify" ON public.product_categories;
CREATE POLICY "product_categories_modify" ON public.product_categories FOR ALL USING (true);
DROP POLICY IF EXISTS "products_select" ON public.products;
CREATE POLICY "products_select" ON public.products FOR SELECT USING (true);
DROP POLICY IF EXISTS "products_modify" ON public.products;
CREATE POLICY "products_modify" ON public.products FOR ALL USING (true);
DROP POLICY IF EXISTS "loyalty_tiers_select" ON public.loyalty_tiers;
CREATE POLICY "loyalty_tiers_select" ON public.loyalty_tiers FOR SELECT USING (true);
DROP POLICY IF EXISTS "loyalty_tiers_modify" ON public.loyalty_tiers;
CREATE POLICY "loyalty_tiers_modify" ON public.loyalty_tiers FOR ALL USING (true);
DROP POLICY IF EXISTS "customers_select" ON public.customers;
CREATE POLICY "customers_select" ON public.customers FOR SELECT USING (true);
DROP POLICY IF EXISTS "customers_modify" ON public.customers;
CREATE POLICY "customers_modify" ON public.customers FOR ALL USING (true);
DROP POLICY IF EXISTS "loyalty_points_select" ON public.loyalty_points;
CREATE POLICY "loyalty_points_select" ON public.loyalty_points FOR SELECT USING (true);
DROP POLICY IF EXISTS "loyalty_points_modify" ON public.loyalty_points;
CREATE POLICY "loyalty_points_modify" ON public.loyalty_points FOR ALL USING (true);
DROP POLICY IF EXISTS "coupons_select" ON public.coupons;
CREATE POLICY "coupons_select" ON public.coupons FOR SELECT USING (true);
DROP POLICY IF EXISTS "coupons_modify" ON public.coupons;
CREATE POLICY "coupons_modify" ON public.coupons FOR ALL USING (true);
DROP POLICY IF EXISTS "coupon_redemptions_select" ON public.coupon_redemptions;
CREATE POLICY "coupon_redemptions_select" ON public.coupon_redemptions FOR SELECT USING (true);
DROP POLICY IF EXISTS "coupon_redemptions_modify" ON public.coupon_redemptions;
CREATE POLICY "coupon_redemptions_modify" ON public.coupon_redemptions FOR ALL USING (true);
DROP POLICY IF EXISTS "suppliers_select" ON public.suppliers;
CREATE POLICY "suppliers_select" ON public.suppliers FOR SELECT USING (true);
DROP POLICY IF EXISTS "suppliers_modify" ON public.suppliers;
CREATE POLICY "suppliers_modify" ON public.suppliers FOR ALL USING (true);
DROP POLICY IF EXISTS "pr_select" ON public.purchase_requisitions;
CREATE POLICY "pr_select" ON public.purchase_requisitions FOR SELECT USING (true);
DROP POLICY IF EXISTS "pr_modify" ON public.purchase_requisitions;
CREATE POLICY "pr_modify" ON public.purchase_requisitions FOR ALL USING (true);
DROP POLICY IF EXISTS "po_select" ON public.purchase_orders;
CREATE POLICY "po_select" ON public.purchase_orders FOR SELECT USING (true);
DROP POLICY IF EXISTS "po_modify" ON public.purchase_orders;
CREATE POLICY "po_modify" ON public.purchase_orders FOR ALL USING (true);
DROP POLICY IF EXISTS "po_items_select" ON public.purchase_order_items;
CREATE POLICY "po_items_select" ON public.purchase_order_items FOR SELECT USING (true);
DROP POLICY IF EXISTS "po_items_modify" ON public.purchase_order_items;
CREATE POLICY "po_items_modify" ON public.purchase_order_items FOR ALL USING (true);
DROP POLICY IF EXISTS "warehouse_locations_select" ON public.warehouse_locations;
CREATE POLICY "warehouse_locations_select" ON public.warehouse_locations FOR SELECT USING (true);
DROP POLICY IF EXISTS "warehouse_locations_modify" ON public.warehouse_locations;
CREATE POLICY "warehouse_locations_modify" ON public.warehouse_locations FOR ALL USING (true);
DROP POLICY IF EXISTS "inventory_lots_select" ON public.inventory_lots;
CREATE POLICY "inventory_lots_select" ON public.inventory_lots FOR SELECT USING (true);
DROP POLICY IF EXISTS "inventory_lots_modify" ON public.inventory_lots;
CREATE POLICY "inventory_lots_modify" ON public.inventory_lots FOR ALL USING (true);
DROP POLICY IF EXISTS "stock_movements_select" ON public.stock_movements;
CREATE POLICY "stock_movements_select" ON public.stock_movements FOR SELECT USING (true);
DROP POLICY IF EXISTS "stock_movements_modify" ON public.stock_movements;
CREATE POLICY "stock_movements_modify" ON public.stock_movements FOR ALL USING (true);
DROP POLICY IF EXISTS "inventory_reservations_select" ON public.inventory_reservations;
CREATE POLICY "inventory_reservations_select" ON public.inventory_reservations FOR SELECT USING (true);
DROP POLICY IF EXISTS "inventory_reservations_modify" ON public.inventory_reservations;
CREATE POLICY "inventory_reservations_modify" ON public.inventory_reservations FOR ALL USING (true);

-- ============================================================
-- 6. Helper RPC Functions
-- ============================================================

-- 6.1 ดึง stock คงเหลือต่อ product (รวม lot)
CREATE OR REPLACE FUNCTION public.get_product_stock_summary(
    p_product_id UUID,
    p_branch_id UUID DEFAULT NULL
)
RETURNS TABLE (
    lot_id UUID,
    lot_number TEXT,
    expiry_date DATE,
    quantity_remaining INTEGER,
    unit_cost DECIMAL(12,2),
    warehouse_location_id UUID,
    warehouse_location_name TEXT
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT
        il.id AS lot_id,
        il.lot_number,
        il.expiry_date,
        il.quantity_remaining,
        il.unit_cost,
        il.warehouse_location_id,
        wl.location_name AS warehouse_location_name
    FROM public.inventory_lots il
    LEFT JOIN public.warehouse_locations wl ON wl.id = il.warehouse_location_id
    WHERE il.product_id = p_product_id
      AND il.status = 'active'
      AND (p_branch_id IS NULL OR il.branch_id = p_branch_id)
    ORDER BY il.expiry_date NULLS LAST, il.created_at;
END;
$$;

-- 6.2 ดึง stock รวมทั้งหมดต่อ product (ไม่แยก lot)
CREATE OR REPLACE FUNCTION public.get_product_total_stock(
    p_product_id UUID,
    p_branch_id UUID DEFAULT NULL
)
RETURNS INTEGER LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_total INTEGER;
BEGIN
    SELECT COALESCE(SUM(il.quantity_remaining), 0)
    INTO v_total
    FROM public.inventory_lots il
    WHERE il.product_id = p_product_id
      AND il.status = 'active'
      AND (p_branch_id IS NULL OR il.branch_id = p_branch_id);

    RETURN v_total;
END;
$$;

-- 6.3 ดึง reserved quantity ต่อ product
CREATE OR REPLACE FUNCTION public.get_product_reserved_quantity(
    p_product_id UUID,
    p_branch_id UUID DEFAULT NULL
)
RETURNS INTEGER LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_reserved INTEGER;
BEGIN
    SELECT COALESCE(SUM(ir.quantity_reserved - ir.quantity_fulfilled - ir.quantity_cancelled), 0)
    INTO v_reserved
    FROM public.inventory_reservations ir
    WHERE ir.product_id = p_product_id
      AND ir.status = 'active'
      AND ir.expires_at > NOW()
      AND (p_branch_id IS NULL OR ir.branch_id = p_branch_id);

    RETURN v_reserved;
END;
$$;

-- 6.4 ดึง available stock (total - reserved)
CREATE OR REPLACE FUNCTION public.get_product_available_stock(
    p_product_id UUID,
    p_branch_id UUID DEFAULT NULL
)
RETURNS INTEGER LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_total INTEGER;
    v_reserved INTEGER;
BEGIN
    v_total := public.get_product_total_stock(p_product_id, p_branch_id);
    v_reserved := public.get_product_reserved_quantity(p_product_id, p_branch_id);
    RETURN GREATEST(v_total - v_reserved, 0);
END;
$$;

-- 6.5 สร้าง reservation (ใช้ตอน add to cart)
CREATE OR REPLACE FUNCTION public.create_inventory_reservation(
    p_profession_id UUID,
    p_product_id UUID,
    p_branch_id UUID,
    p_quantity INTEGER,
    p_reservation_type TEXT,
    p_reference_id UUID,
    p_expires_at TIMESTAMPTZ,
    p_lot_id UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_id UUID;
    v_available INTEGER;
BEGIN
    -- ตรวจสอบว่ามีของพอหรือไม่
    v_available := public.get_product_available_stock(p_product_id, p_branch_id);
    IF v_available < p_quantity THEN
        RAISE EXCEPTION 'Insufficient stock: available %, requested %', v_available, p_quantity;
    END IF;

    INSERT INTO public.inventory_reservations (
        profession_id, product_id, lot_id, branch_id,
        quantity_reserved, reservation_type, reference_id, expires_at
    )
    VALUES (
        p_profession_id, p_product_id, p_lot_id, p_branch_id,
        p_quantity, p_reservation_type, p_reference_id, p_expires_at
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- 6.6 อัปเดต customer lifetime value + visit count + points
CREATE OR REPLACE FUNCTION public.update_customer_stats(
    p_customer_id UUID,
    p_add_lifetime_value DECIMAL(12,2) DEFAULT 0,
    p_add_visit_count INTEGER DEFAULT 1,
    p_add_points INTEGER DEFAULT 0
)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE public.customers
    SET
        lifetime_value = lifetime_value + p_add_lifetime_value,
        visit_count = visit_count + p_add_visit_count,
        total_points = total_points + p_add_points,
        last_visit_at = NOW(),
        updated_at = NOW()
    WHERE id = p_customer_id;
END;
$$;
