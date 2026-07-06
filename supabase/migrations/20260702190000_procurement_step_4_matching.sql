-- Migration: Procurement Step 4 — 3-Way Matching (PO vs GR vs Supplier Invoice)
-- Date: 2026-07-02
-- Prerequisites: 20260611160000 (PO/PO items), 20260701130000 (GR/GR items), 20260701170000 (outbox constraint)

-- ============================================================
-- 1. supplier_invoices
-- ============================================================
CREATE TABLE IF NOT EXISTS public.supplier_invoices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    supplier_id         UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
    po_id               UUID REFERENCES public.purchase_orders(id) ON DELETE SET NULL,
    invoice_number      TEXT NOT NULL,
    invoice_date        DATE NOT NULL,
    due_date            DATE,
    total_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    grand_total         DECIMAL(12,2) NOT NULL DEFAULT 0,
    status              TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','matched','partially_matched','disputed','paid')),
    matching_status     TEXT NOT NULL DEFAULT 'pending'
        CHECK (matching_status IN ('pending','matched','mismatch_quantity','mismatch_price','mismatch_tax','disputed')),
    mismatch_details    JSONB,
    notes               TEXT,
    created_by          UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, invoice_number)
);

CREATE INDEX IF NOT EXISTS idx_supplier_invoices_profession
    ON public.supplier_invoices(profession_id, status, invoice_date DESC);
CREATE INDEX IF NOT EXISTS idx_supplier_invoices_supplier
    ON public.supplier_invoices(supplier_id, status);
CREATE INDEX IF NOT EXISTS idx_supplier_invoices_po
    ON public.supplier_invoices(po_id)
    WHERE po_id IS NOT NULL;

-- ============================================================
-- 2. supplier_invoice_items
-- ============================================================
CREATE TABLE IF NOT EXISTS public.supplier_invoice_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    supplier_invoice_id UUID NOT NULL REFERENCES public.supplier_invoices(id) ON DELETE CASCADE,
    po_item_id          UUID REFERENCES public.purchase_order_items(id) ON DELETE SET NULL,
    product_id          UUID REFERENCES public.products(id) ON DELETE SET NULL,
    item_name           TEXT NOT NULL DEFAULT '',
    quantity_invoiced   INTEGER NOT NULL DEFAULT 0,
    unit_price          DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_price         DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    matched_quantity    INTEGER NOT NULL DEFAULT 0,
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_supplier_invoice_items_invoice
    ON public.supplier_invoice_items(supplier_invoice_id);
CREATE INDEX IF NOT EXISTS idx_supplier_invoice_items_po_item
    ON public.supplier_invoice_items(po_item_id)
    WHERE po_item_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_supplier_invoice_items_product
    ON public.supplier_invoice_items(product_id)
    WHERE product_id IS NOT NULL;

-- ============================================================
-- 3. updated_at triggers
-- ============================================================
DROP TRIGGER IF EXISTS trg_supplier_invoices_updated_at ON public.supplier_invoices;
CREATE TRIGGER trg_supplier_invoices_updated_at
    BEFORE UPDATE ON public.supplier_invoices
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 4. Add 'supplier_invoice' to outbox_events.aggregate_type CHECK constraint
-- ============================================================
ALTER TABLE public.outbox_events DROP CONSTRAINT IF EXISTS outbox_events_aggregate_type_check;

ALTER TABLE public.outbox_events ADD CONSTRAINT outbox_events_aggregate_type_check
    CHECK (aggregate_type IN (
        'pos_sale','procurement_gr','procurement_po','procurement_pr',
        'back_order','reorder_suggestion','supplier_invoice',
        'hr_payroll','telemedicine','logistics','manual','accounting'
    ));

-- ============================================================
-- 5. RLS Policies
-- ============================================================
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOR tbl IN SELECT unnest(ARRAY['supplier_invoices','supplier_invoice_items'])
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_select ON public.%I;', tbl, tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_modify ON public.%I;', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_select ON public.%I FOR SELECT USING (true);', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_modify ON public.%I FOR ALL USING (true);', tbl, tbl);
    END LOOP;
END $$;
