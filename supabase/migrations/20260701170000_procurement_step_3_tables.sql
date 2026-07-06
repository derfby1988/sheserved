-- Migration: Procurement Step 3 — Auto-Reorder & Price History Tables
-- Date: 2026-07-03
-- Prerequisites: 20260611160000_erp_phase_1_data_and_inflow.sql, 20260701130000_procurement_step_2_tables.sql
-- Tables: reorder_suggestions, supplier_price_history
-- Notes: RLS enabled but allow all (controlled at Application Layer per auth_data_guidelines.md)

-- ============================================================
-- 1. Reorder Suggestions (auto-generated when stock is low)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.reorder_suggestions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id               UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    product_id              UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    current_quantity        INTEGER NOT NULL,
    reorder_point           INTEGER NOT NULL,
    suggested_quantity      INTEGER NOT NULL CHECK (suggested_quantity > 0),
    preferred_supplier_id   UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    reason                  TEXT NOT NULL DEFAULT 'below_reorder_point',
    status                  TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','confirmed','rejected','converted_to_pr')),
    confirmed_by            UUID,
    confirmed_at            TIMESTAMPTZ,
    converted_pr_id         UUID REFERENCES public.purchase_requisitions(id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reorder_pending
    ON public.reorder_suggestions(profession_id, branch_id, status)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_reorder_confirmed
    ON public.reorder_suggestions(profession_id, branch_id, status)
    WHERE status = 'confirmed';

CREATE INDEX IF NOT EXISTS idx_reorder_profession
    ON public.reorder_suggestions(profession_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reorder_product
    ON public.reorder_suggestions(product_id, status);

DROP TRIGGER IF EXISTS trg_reorder_suggestions_updated_at ON public.reorder_suggestions;
CREATE TRIGGER trg_reorder_suggestions_updated_at
    BEFORE UPDATE ON public.reorder_suggestions
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 2. Supplier Price History (mode B — track price per supplier/product)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.supplier_price_history (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    supplier_id             UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
    product_id              UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    unit_price              DECIMAL(12,2) NOT NULL,
    effective_date          DATE NOT NULL DEFAULT CURRENT_DATE,
    po_id                   UUID REFERENCES public.purchase_orders(id) ON DELETE SET NULL,
    po_item_id              UUID REFERENCES public.purchase_order_items(id) ON DELETE SET NULL,
    notes                   TEXT,
    created_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_price_history_supplier_product
    ON public.supplier_price_history(profession_id, supplier_id, product_id, effective_date DESC);

CREATE INDEX IF NOT EXISTS idx_price_history_product
    ON public.supplier_price_history(profession_id, product_id, effective_date DESC);

CREATE INDEX IF NOT EXISTS idx_price_history_supplier
    ON public.supplier_price_history(profession_id, supplier_id, effective_date DESC);

-- ============================================================
-- 3. Add 'reorder_suggestion' to outbox_events.aggregate_type CHECK constraint
-- ============================================================
ALTER TABLE public.outbox_events DROP CONSTRAINT IF EXISTS outbox_events_aggregate_type_check;

ALTER TABLE public.outbox_events ADD CONSTRAINT outbox_events_aggregate_type_check
    CHECK (aggregate_type IN (
        'pos_sale','procurement_gr','procurement_po','procurement_pr',
        'back_order','reorder_suggestion',
        'hr_payroll','telemedicine','logistics','manual','accounting'
    ));

-- ============================================================
-- 4. RLS (Enable but allow all — controlled at Application Layer)
-- ============================================================
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'reorder_suggestions',
        'supplier_price_history'
    ]
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_select ON public.%I;', tbl, tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_modify ON public.%I;', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_select ON public.%I FOR SELECT USING (true);', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_modify ON public.%I FOR ALL USING (true);', tbl, tbl);
    END LOOP;
END $$;
