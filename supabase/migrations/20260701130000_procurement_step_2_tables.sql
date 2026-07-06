-- Migration: Procurement Step 2 — Tables
-- Date: 2026-07-01
-- Prerequisites: 20260611160000_erp_phase_1_data_and_inflow.sql
-- Tables: procurement_settings, document_sequences, purchase_requisition_items,
--         goods_receipts, goods_receipt_items, back_orders
-- Notes: RLS enabled but allow all (controlled at Application Layer per auth_data_guidelines.md)

-- ============================================================
-- 1. Procurement Settings (per profession)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.procurement_settings (
    id                                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id                       UUID NOT NULL UNIQUE REFERENCES public.professions(id) ON DELETE CASCADE,
    enable_price_history_tracking       BOOLEAN DEFAULT false,
    default_payment_terms               TEXT DEFAULT 'net_30',
    auto_reorder_threshold_multiplier   DECIMAL(3,2) DEFAULT 1.0,
    approval_amount_threshold           DECIMAL(12,2) DEFAULT 10000,
    created_at                          TIMESTAMPTZ DEFAULT NOW(),
    updated_at                          TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_procurement_settings_updated_at ON public.procurement_settings;
CREATE TRIGGER trg_procurement_settings_updated_at
    BEFORE UPDATE ON public.procurement_settings
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 2. Document Sequences (auto-numbering per profession/branch/year)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.document_sequences (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE CASCADE,
    prefix          TEXT NOT NULL,                      -- 'PR', 'PO', 'GR'
    year            INTEGER NOT NULL,                   -- CE year e.g. 2026
    last_number     INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, branch_id, prefix, year)
);

DROP TRIGGER IF EXISTS trg_document_sequences_updated_at ON public.document_sequences;
CREATE TRIGGER trg_document_sequences_updated_at
    BEFORE UPDATE ON public.document_sequences
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Purchase Requisition Items (line items for PR)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.purchase_requisition_items (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    requisition_id          UUID NOT NULL REFERENCES public.purchase_requisitions(id) ON DELETE CASCADE,
    product_id              UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    item_name               TEXT NOT NULL,
    quantity_requested      INTEGER NOT NULL CHECK (quantity_requested > 0),
    estimated_unit_price    DECIMAL(12,2),
    estimated_total_price   DECIMAL(12,2),
    notes                   TEXT,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pr_items_requisition
    ON public.purchase_requisition_items(requisition_id);
CREATE INDEX IF NOT EXISTS idx_pr_items_product
    ON public.purchase_requisition_items(product_id);
CREATE INDEX IF NOT EXISTS idx_pr_items_profession
    ON public.purchase_requisition_items(profession_id);

DROP TRIGGER IF EXISTS trg_pr_items_updated_at ON public.purchase_requisition_items;
CREATE TRIGGER trg_pr_items_updated_at
    BEFORE UPDATE ON public.purchase_requisition_items
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 4. Goods Receipts (GR)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.goods_receipts (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id               UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    purchase_order_id       UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE RESTRICT,
    gr_number               TEXT NOT NULL,
    receipt_date            TIMESTAMPTZ DEFAULT NOW(),
    supplier_delivery_note  TEXT,
    received_by             UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
    status                  TEXT NOT NULL DEFAULT 'completed'
        CHECK (status IN ('pending','completed','rejected')),
    notes                   TEXT,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, gr_number)
);

CREATE INDEX IF NOT EXISTS idx_gr_profession
    ON public.goods_receipts(profession_id, status, receipt_date DESC);
CREATE INDEX IF NOT EXISTS idx_gr_po
    ON public.goods_receipts(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_gr_recent
    ON public.goods_receipts(profession_id, branch_id, receipt_date DESC);

DROP TRIGGER IF EXISTS trg_goods_receipts_updated_at ON public.goods_receipts;
CREATE TRIGGER trg_goods_receipts_updated_at
    BEFORE UPDATE ON public.goods_receipts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 5. Goods Receipt Items (line items for GR)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.goods_receipt_items (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    goods_receipt_id        UUID NOT NULL REFERENCES public.goods_receipts(id) ON DELETE CASCADE,
    purchase_order_item_id  UUID NOT NULL REFERENCES public.purchase_order_items(id) ON DELETE RESTRICT,
    quantity_received       INTEGER NOT NULL CHECK (quantity_received > 0),
    quantity_accepted       INTEGER NOT NULL CHECK (quantity_accepted >= 0),
    quantity_rejected       INTEGER NOT NULL DEFAULT 0 CHECK (quantity_rejected >= 0),
    lot_number              TEXT,
    expiry_date             DATE,
    unit_cost               DECIMAL(12,2),
    notes                   TEXT,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT check_accepted_plus_rejected
        CHECK (quantity_accepted + quantity_rejected = quantity_received)
);

CREATE INDEX IF NOT EXISTS idx_gr_items_receipt
    ON public.goods_receipt_items(goods_receipt_id);
CREATE INDEX IF NOT EXISTS idx_gr_items_po_item
    ON public.goods_receipt_items(purchase_order_item_id);
CREATE INDEX IF NOT EXISTS idx_gr_items_profession
    ON public.goods_receipt_items(profession_id);

DROP TRIGGER IF EXISTS trg_gr_items_updated_at ON public.goods_receipt_items;
CREATE TRIGGER trg_gr_items_updated_at
    BEFORE UPDATE ON public.goods_receipt_items
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 6. Back Orders (tracking remaining quantities)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.back_orders (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    purchase_order_id       UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE RESTRICT,
    purchase_order_item_id  UUID NOT NULL REFERENCES public.purchase_order_items(id) ON DELETE RESTRICT,
    supplier_id             UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE RESTRICT,
    quantity_back_ordered   INTEGER NOT NULL CHECK (quantity_back_ordered > 0),
    quantity_fulfilled      INTEGER NOT NULL DEFAULT 0 CHECK (quantity_fulfilled >= 0),
    expected_delivery_date  DATE,
    status                  TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open','partially_fulfilled','fulfilled','cancelled')),
    notes                   TEXT,
    notified_requester      BOOLEAN DEFAULT false,
    notified_approver       BOOLEAN DEFAULT false,
    notified_receiver       BOOLEAN DEFAULT false,
    notified_supplier       BOOLEAN DEFAULT false,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_back_order_profession
    ON public.back_orders(profession_id, status);
CREATE INDEX IF NOT EXISTS idx_back_order_open
    ON public.back_orders(profession_id, status)
    WHERE status IN ('open','partially_fulfilled');
CREATE INDEX IF NOT EXISTS idx_back_order_po
    ON public.back_orders(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_back_order_supplier
    ON public.back_orders(supplier_id, status);

DROP TRIGGER IF EXISTS trg_back_orders_updated_at ON public.back_orders;
CREATE TRIGGER trg_back_orders_updated_at
    BEFORE UPDATE ON public.back_orders
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 7. RLS (Enable but allow all — controlled at Application Layer)
-- ============================================================
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'procurement_settings',
        'document_sequences',
        'purchase_requisition_items',
        'goods_receipts',
        'goods_receipt_items',
        'back_orders'
    ]
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_select ON public.%I;', tbl, tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_modify ON public.%I;', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_select ON public.%I FOR SELECT USING (true);', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_modify ON public.%I FOR ALL USING (true);', tbl, tbl);
    END LOOP;
END $$;

-- ============================================================
-- 8. Seed default procurement_settings for existing professions
-- ============================================================
INSERT INTO public.procurement_settings (profession_id)
SELECT p.id FROM public.professions p
WHERE NOT EXISTS (
    SELECT 1 FROM public.procurement_settings ps WHERE ps.profession_id = p.id
)
ON CONFLICT (profession_id) DO NOTHING;
