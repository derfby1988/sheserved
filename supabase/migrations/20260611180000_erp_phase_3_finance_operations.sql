-- Migration: ERP Phase 3 — Finance & Operations + Read Model / Analytics Core
-- Date: 2026-06-11
-- Prerequisites: Phase 2 complete (orders, payments, settlements)

-- ============================================================
-- 1. ACCOUNTING CORE — GL, AP/AR
-- ============================================================

-- 1.1 Chart of Accounts (ผังบัญชี)
CREATE TABLE IF NOT EXISTS public.chart_of_accounts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    account_code    TEXT NOT NULL,                          -- รหัสบัญชี (เช่น 101, 201)
    account_name    TEXT NOT NULL,
    account_type    TEXT NOT NULL                          -- asset, liability, equity, revenue, expense
                        CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
    parent_id       UUID REFERENCES public.chart_of_accounts(id) ON DELETE SET NULL,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, account_code)
);

CREATE INDEX IF NOT EXISTS idx_coa_profession
    ON public.chart_of_accounts(profession_id, account_type, is_active);

DROP TRIGGER IF EXISTS trg_coa_updated_at ON public.chart_of_accounts;
CREATE TRIGGER trg_coa_updated_at
    BEFORE UPDATE ON public.chart_of_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.2 General Ledger Entries (บันทึกบัญชีแยกประเภท)
CREATE TABLE IF NOT EXISTS public.gl_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    entry_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    account_id      UUID NOT NULL REFERENCES public.chart_of_accounts(id) ON DELETE RESTRICT,
    order_id        UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    payment_txn_id  UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
    debit_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
    credit_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
    description     TEXT,
    reference_no    TEXT,
    created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gl_entries_profession
    ON public.gl_entries(profession_id, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_gl_entries_account
    ON public.gl_entries(account_id, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_gl_entries_order
    ON public.gl_entries(order_id)
    WHERE order_id IS NOT NULL;

-- 1.3 Accounts Receivable (ลูกหนี้)
CREATE TABLE IF NOT EXISTS public.accounts_receivable (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    customer_id     UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    invoice_number  TEXT,
    amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    paid_amount     DECIMAL(12,2) NOT NULL DEFAULT 0,
    balance         DECIMAL(12,2) NOT NULL DEFAULT 0,
    due_date        DATE,
    status          TEXT NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open', 'partial', 'paid', 'overdue', 'written_off')),
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ar_profession
    ON public.accounts_receivable(profession_id, status, due_date);
CREATE INDEX IF NOT EXISTS idx_ar_customer
    ON public.accounts_receivable(customer_id, status);

DROP TRIGGER IF EXISTS trg_ar_updated_at ON public.accounts_receivable;
CREATE TRIGGER trg_ar_updated_at
    BEFORE UPDATE ON public.accounts_receivable
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.4 Accounts Payable (เจ้าหนี้)
CREATE TABLE IF NOT EXISTS public.accounts_payable (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    supplier_id     UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
    po_id           UUID REFERENCES public.purchase_orders(id) ON DELETE SET NULL,
    invoice_number  TEXT,
    amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    paid_amount     DECIMAL(12,2) NOT NULL DEFAULT 0,
    balance         DECIMAL(12,2) NOT NULL DEFAULT 0,
    due_date        DATE,
    status          TEXT NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open', 'partial', 'paid', 'overdue', 'written_off')),
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ap_profession
    ON public.accounts_payable(profession_id, status, due_date);
CREATE INDEX IF NOT EXISTS idx_ap_supplier
    ON public.accounts_payable(supplier_id, status);

DROP TRIGGER IF EXISTS trg_ap_updated_at ON public.accounts_payable;
CREATE TRIGGER trg_ap_updated_at
    BEFORE UPDATE ON public.accounts_payable
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. HR CORE — Employee, Shift
-- ============================================================

-- 2.1 Employees (พนักงาน)
CREATE TABLE IF NOT EXISTS public.employees (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES public.users(id) ON DELETE SET NULL,
    employee_code   TEXT NOT NULL,
    full_name       TEXT NOT NULL,
    email           TEXT,
    phone           TEXT,
    department      TEXT,                                   -- pharmacy, nursing, admin, etc.
    job_title       TEXT,
    hire_date       DATE,
    salary          DECIMAL(12,2),
    commission_rate DECIMAL(5,2) DEFAULT 0,              -- % commission จากยอดขาย
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, employee_code)
);

CREATE INDEX IF NOT EXISTS idx_employees_profession
    ON public.employees(profession_id, is_active, department);

DROP TRIGGER IF EXISTS trg_employees_updated_at ON public.employees;
CREATE TRIGGER trg_employees_updated_at
    BEFORE UPDATE ON public.employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2.2 Shifts (กะงาน)
CREATE TABLE IF NOT EXISTS public.shifts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    employee_id     UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    shift_date      DATE NOT NULL,
    start_time      TIMESTAMPTZ NOT NULL,
    end_time        TIMESTAMPTZ,
    shift_type      TEXT NOT NULL DEFAULT 'regular'
                        CHECK (shift_type IN ('regular', 'overtime', 'holiday', 'on_call')),
    status          TEXT NOT NULL DEFAULT 'scheduled'
                        CHECK (status IN ('scheduled', 'checked_in', 'checked_out', 'absent', 'approved')),
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shifts_profession
    ON public.shifts(profession_id, shift_date, status);
CREATE INDEX IF NOT EXISTS idx_shifts_employee
    ON public.shifts(employee_id, shift_date DESC);

DROP TRIGGER IF EXISTS trg_shifts_updated_at ON public.shifts;
CREATE TRIGGER trg_shifts_updated_at
    BEFORE UPDATE ON public.shifts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. SETTLEMENT CORE — Payout Batches
-- ============================================================

-- 3.1 Settlement Ledgers
CREATE TABLE IF NOT EXISTS public.settlement_ledgers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    vendor_contract_id UUID NOT NULL REFERENCES public.vendor_contracts(id) ON DELETE CASCADE,
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,
    total_gross     DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_fee       DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_net       DECIMAL(12,2) NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open', 'processing', 'paid', 'failed')),
    paid_at         TIMESTAMPTZ,
    payout_reference TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_settlement_ledgers_profession
    ON public.settlement_ledgers(profession_id, status, period_end DESC);

DROP TRIGGER IF EXISTS trg_settlement_ledgers_updated_at ON public.settlement_ledgers;
CREATE TRIGGER trg_settlement_ledgers_updated_at
    BEFORE UPDATE ON public.settlement_ledgers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3.2 Payout Batches
CREATE TABLE IF NOT EXISTS public.payout_batches (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    batch_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
    processed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payout_batches_profession
    ON public.payout_batches(profession_id, status, batch_date DESC);

-- 3.3 Payout Batch Lines
CREATE TABLE IF NOT EXISTS public.payout_batch_lines (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_batch_id UUID NOT NULL REFERENCES public.payout_batches(id) ON DELETE CASCADE,
    allocation_id   UUID NOT NULL REFERENCES public.payment_allocations(id) ON DELETE RESTRICT,
    merchant_account_id UUID REFERENCES public.merchant_accounts(id) ON DELETE SET NULL,
    amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    processed_at    TIMESTAMPTZ,
    failure_reason  TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payout_batch_lines_batch
    ON public.payout_batch_lines(payout_batch_id, status);

-- ============================================================
-- 4. READ MODEL / ANALYTICS CORE
-- ============================================================

-- 4.1 Projection Checkpoints (สำหรับ CQRS read model)
CREATE TABLE IF NOT EXISTS public.projection_checkpoints (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    projection_name TEXT NOT NULL,                         -- เช่น daily_sales, monthly_revenue
    last_event_id   UUID,
    last_event_seq  BIGINT NOT NULL DEFAULT 0,
    state_snapshot  JSONB DEFAULT '{}',
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, projection_name)
);

-- 4.2 Dashboard Snapshots (pre-aggregated KPI data)
CREATE TABLE IF NOT EXISTS public.dashboard_snapshots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    snapshot_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    snapshot_type   TEXT NOT NULL                          -- daily, weekly, monthly
                        CHECK (snapshot_type IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly')),
    metrics         JSONB NOT NULL DEFAULT '{}',           -- {revenue: 10000, orders: 50, avg_order_value: 200}
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, snapshot_date, snapshot_type)
);

CREATE INDEX IF NOT EXISTS idx_dashboard_snapshots_profession
    ON public.dashboard_snapshots(profession_id, snapshot_date DESC, snapshot_type);

-- 4.3 KPI Aggregations
CREATE TABLE IF NOT EXISTS public.kpi_aggregations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    kpi_name        TEXT NOT NULL,                          -- revenue, order_count, customer_count, etc.
    kpi_category    TEXT NOT NULL                          -- sales, finance, operations, customer
                        CHECK (kpi_category IN ('sales', 'finance', 'operations', 'customer', 'inventory')),
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,
    value           DECIMAL(12,2) NOT NULL DEFAULT 0,
    target_value    DECIMAL(12,2),
    unit            TEXT DEFAULT 'count',                  -- count, amount, percent, days
    is_better_higher BOOLEAN DEFAULT true,                 -- true = ยิ่งสูงยิ่งดี
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, kpi_name, period_start, period_end)
);

CREATE INDEX IF NOT EXISTS idx_kpi_aggregations_profession
    ON public.kpi_aggregations(profession_id, kpi_category, period_end DESC);

-- ============================================================
-- 5. RLS POLICIES
-- ============================================================
ALTER TABLE public.chart_of_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts_receivable ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts_payable ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_ledgers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payout_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payout_batch_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dashboard_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kpi_aggregations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "coa_select" ON public.chart_of_accounts;
CREATE POLICY "coa_select" ON public.chart_of_accounts FOR SELECT USING (true);
DROP POLICY IF EXISTS "coa_modify" ON public.chart_of_accounts;
CREATE POLICY "coa_modify" ON public.chart_of_accounts FOR ALL USING (true);

DROP POLICY IF EXISTS "gl_select" ON public.gl_entries;
CREATE POLICY "gl_select" ON public.gl_entries FOR SELECT USING (true);
DROP POLICY IF EXISTS "gl_modify" ON public.gl_entries;
CREATE POLICY "gl_modify" ON public.gl_entries FOR ALL USING (true);

DROP POLICY IF EXISTS "ar_select" ON public.accounts_receivable;
CREATE POLICY "ar_select" ON public.accounts_receivable FOR SELECT USING (true);
DROP POLICY IF EXISTS "ar_modify" ON public.accounts_receivable;
CREATE POLICY "ar_modify" ON public.accounts_receivable FOR ALL USING (true);

DROP POLICY IF EXISTS "ap_select" ON public.accounts_payable;
CREATE POLICY "ap_select" ON public.accounts_payable FOR SELECT USING (true);
DROP POLICY IF EXISTS "ap_modify" ON public.accounts_payable;
CREATE POLICY "ap_modify" ON public.accounts_payable FOR ALL USING (true);

DROP POLICY IF EXISTS "employees_select" ON public.employees;
CREATE POLICY "employees_select" ON public.employees FOR SELECT USING (true);
DROP POLICY IF EXISTS "employees_modify" ON public.employees;
CREATE POLICY "employees_modify" ON public.employees FOR ALL USING (true);

DROP POLICY IF EXISTS "shifts_select" ON public.shifts;
CREATE POLICY "shifts_select" ON public.shifts FOR SELECT USING (true);
DROP POLICY IF EXISTS "shifts_modify" ON public.shifts;
CREATE POLICY "shifts_modify" ON public.shifts FOR ALL USING (true);

DROP POLICY IF EXISTS "settlement_ledgers_select" ON public.settlement_ledgers;
CREATE POLICY "settlement_ledgers_select" ON public.settlement_ledgers FOR SELECT USING (true);
DROP POLICY IF EXISTS "settlement_ledgers_modify" ON public.settlement_ledgers;
CREATE POLICY "settlement_ledgers_modify" ON public.settlement_ledgers FOR ALL USING (true);

DROP POLICY IF EXISTS "payout_batches_select" ON public.payout_batches;
CREATE POLICY "payout_batches_select" ON public.payout_batches FOR SELECT USING (true);
DROP POLICY IF EXISTS "payout_batches_modify" ON public.payout_batches;
CREATE POLICY "payout_batches_modify" ON public.payout_batches FOR ALL USING (true);

DROP POLICY IF EXISTS "dashboard_snapshots_select" ON public.dashboard_snapshots;
CREATE POLICY "dashboard_snapshots_select" ON public.dashboard_snapshots FOR SELECT USING (true);
DROP POLICY IF EXISTS "dashboard_snapshots_modify" ON public.dashboard_snapshots;
CREATE POLICY "dashboard_snapshots_modify" ON public.dashboard_snapshots FOR ALL USING (true);

DROP POLICY IF EXISTS "kpi_aggregations_select" ON public.kpi_aggregations;
CREATE POLICY "kpi_aggregations_select" ON public.kpi_aggregations FOR SELECT USING (true);
DROP POLICY IF EXISTS "kpi_aggregations_modify" ON public.kpi_aggregations;
CREATE POLICY "kpi_aggregations_modify" ON public.kpi_aggregations FOR ALL USING (true);

-- ============================================================
-- 6. RPC FUNCTIONS
-- ============================================================

-- Auto-create GL entries from order
CREATE OR REPLACE FUNCTION create_gl_from_order(
    p_order_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_order RECORD;
    v_cash_account UUID;
    v_revenue_account UUID;
BEGIN
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
    IF v_order IS NULL THEN RETURN false; END IF;

    -- Get default accounts (fallback: first matching)
    SELECT id INTO v_cash_account FROM public.chart_of_accounts
    WHERE profession_id = v_order.profession_id AND account_type = 'asset' AND is_active = true
    LIMIT 1;

    SELECT id INTO v_revenue_account FROM public.chart_of_accounts
    WHERE profession_id = v_order.profession_id AND account_type = 'revenue' AND is_active = true
    LIMIT 1;

    -- Debit cash
    IF v_cash_account IS NOT NULL THEN
        INSERT INTO public.gl_entries (
            profession_id, entry_date, account_id, order_id,
            debit_amount, credit_amount, description
        )
        VALUES (
            v_order.profession_id, CURRENT_DATE, v_cash_account, p_order_id,
            v_order.grand_total, 0, 'Order ' || v_order.order_number
        );
    END IF;

    -- Credit revenue
    IF v_revenue_account IS NOT NULL THEN
        INSERT INTO public.gl_entries (
            profession_id, entry_date, account_id, order_id,
            debit_amount, credit_amount, description
        )
        VALUES (
            v_order.profession_id, CURRENT_DATE, v_revenue_account, p_order_id,
            0, v_order.grand_total, 'Revenue from order ' || v_order.order_number
        );
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Upsert dashboard snapshot (idempotent)
CREATE OR REPLACE FUNCTION upsert_dashboard_snapshot(
    p_profession_id UUID,
    p_snapshot_type TEXT,
    p_metrics JSONB
)
RETURNS UUID AS $$
DECLARE
    v_snapshot_date DATE;
    v_id UUID;
BEGIN
    v_snapshot_date := CASE p_snapshot_type
        WHEN 'daily' THEN CURRENT_DATE
        WHEN 'weekly' THEN DATE_TRUNC('week', CURRENT_DATE)::DATE
        WHEN 'monthly' THEN DATE_TRUNC('month', CURRENT_DATE)::DATE
        ELSE CURRENT_DATE
    END;

    INSERT INTO public.dashboard_snapshots (
        profession_id, snapshot_date, snapshot_type, metrics
    )
    VALUES (p_profession_id, v_snapshot_date, p_snapshot_type, p_metrics)
    ON CONFLICT (profession_id, snapshot_date, snapshot_type)
    DO UPDATE SET metrics = EXCLUDED.metrics, created_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
