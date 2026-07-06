-- Migration: HR Payroll Schema (Phase 3 Accounting completion)
-- Tables: hr_settings, benefit_policies, shift_templates, work_shifts,
--         attendance_devices, time_attendances, commission_rules, commissions,
--         payroll_runs, payroll_items, payroll_item_details, leave_requests
-- Prerequisites: employees table exists (20260611180000 or 20260609215000)

-- ============================================================
-- 1. HR SETTINGS (per-organization config)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.hr_settings (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id               UUID NOT NULL UNIQUE REFERENCES public.professions(id) ON DELETE CASCADE,
    attendance_mode             TEXT NOT NULL DEFAULT 'manual'
        CHECK (attendance_mode IN ('manual','device','both')),
    allow_flexible_hours        BOOLEAN DEFAULT false,
    default_work_hours_per_day  DECIMAL(4,2) DEFAULT 8.00,
    ot_multiplier_weekday       DECIMAL(3,2) DEFAULT 1.50,
    ot_multiplier_weekend       DECIMAL(3,2) DEFAULT 2.00,
    ot_multiplier_holiday       DECIMAL(3,2) DEFAULT 3.00,
    social_security_rate        DECIMAL(5,4) DEFAULT 0.0500,
    diligence_allowance_amount  DECIMAL(12,2) DEFAULT 0,
    external_hrm_api_url        TEXT,
    external_hrm_sync_enabled   BOOLEAN DEFAULT false,
    created_at                  TIMESTAMPTZ DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_hr_settings_updated_at ON public.hr_settings;
CREATE TRIGGER trg_hr_settings_updated_at
    BEFORE UPDATE ON public.hr_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. BENEFIT POLICIES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.benefit_policies (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    name                    TEXT NOT NULL,
    policy_type             TEXT NOT NULL
        CHECK (policy_type IN ('overtime','diligence','bonus','allowance','deduction','social_security','provident_fund')),
    amount                  DECIMAL(12,2),
    amount_type             TEXT NOT NULL DEFAULT 'fixed'
        CHECK (amount_type IN ('fixed','percentage_of_salary','percentage_of_base')),
    is_active               BOOLEAN DEFAULT true,
    created_by              UUID,
    updated_by              UUID,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_benefit_policies_profession
    ON public.benefit_policies(profession_id, is_active, policy_type);

DROP TRIGGER IF EXISTS trg_benefit_policies_updated_at ON public.benefit_policies;
CREATE TRIGGER trg_benefit_policies_updated_at
    BEFORE UPDATE ON public.benefit_policies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. SHIFT TEMPLATES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.shift_templates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    start_time          TIME NOT NULL,
    end_time            TIME NOT NULL,
    break_duration_minutes INTEGER DEFAULT 60,
    is_flexible         BOOLEAN DEFAULT false,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shift_templates_profession
    ON public.shift_templates(profession_id, is_active);

DROP TRIGGER IF EXISTS trg_shift_templates_updated_at ON public.shift_templates;
CREATE TRIGGER trg_shift_templates_updated_at
    BEFORE UPDATE ON public.shift_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. WORK SHIFTS (roster assignments)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.work_shifts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id           UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    employee_id         UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    shift_template_id   UUID REFERENCES public.shift_templates(id) ON DELETE SET NULL,
    shift_date          DATE NOT NULL,
    scheduled_start     TIMESTAMPTZ,
    scheduled_end       TIMESTAMPTZ,
    status              TEXT NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled','completed','absent','cancelled')),
    notes               TEXT,
    created_by          UUID,
    updated_by          UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_work_shifts_date ON public.work_shifts(profession_id, branch_id, shift_date);
CREATE INDEX IF NOT EXISTS idx_work_shifts_employee ON public.work_shifts(employee_id);

DROP TRIGGER IF EXISTS trg_work_shifts_updated_at ON public.work_shifts;
CREATE TRIGGER trg_work_shifts_updated_at
    BEFORE UPDATE ON public.work_shifts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 5. ATTENDANCE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.attendance_devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id           UUID NOT NULL REFERENCES public.organization_branches(id) ON DELETE CASCADE,
    device_name         TEXT NOT NULL,
    device_serial       TEXT NOT NULL,
    device_type         TEXT NOT NULL DEFAULT 'fingerprint'
        CHECK (device_type IN ('fingerprint','face_recognition','card','mobile_app')),
    last_sync_at        TIMESTAMPTZ,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_attendance_devices_updated_at ON public.attendance_devices;
CREATE TRIGGER trg_attendance_devices_updated_at
    BEFORE UPDATE ON public.attendance_devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.time_attendances (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id               UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    employee_id             UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    shift_id                UUID REFERENCES public.work_shifts(id) ON DELETE SET NULL,
    attendance_device_id    UUID REFERENCES public.attendance_devices(id) ON DELETE SET NULL,
    clock_in_time           TIMESTAMPTZ,
    clock_out_time          TIMESTAMPTZ,
    clock_in_location       JSONB,
    clock_out_location      JSONB,
    attendance_status       TEXT NOT NULL DEFAULT 'on_time'
        CHECK (attendance_status IN ('on_time','late','early_leave','absent','overtime')),
    is_manual_override      BOOLEAN DEFAULT false,
    override_by             UUID,
    override_reason         TEXT,
    source                  TEXT NOT NULL DEFAULT 'manual'
        CHECK (source IN ('manual','device','mobile_app','admin_entry')),
    notes                   TEXT,
    created_by              UUID,
    updated_by              UUID,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_time_attendances_date ON public.time_attendances(profession_id, employee_id, clock_in_time);
CREATE INDEX IF NOT EXISTS idx_time_attendances_shift ON public.time_attendances(shift_id);

DROP TRIGGER IF EXISTS trg_time_attendances_updated_at ON public.time_attendances;
CREATE TRIGGER trg_time_attendances_updated_at
    BEFORE UPDATE ON public.time_attendances
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 6. COMMISSION
-- ============================================================
CREATE TABLE IF NOT EXISTS public.commission_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id           UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    name                TEXT NOT NULL,
    rule_type           TEXT NOT NULL DEFAULT 'percentage_of_sale'
        CHECK (rule_type IN ('percentage_of_sale','fixed_per_sale','tiered')),
    rate_or_amount      DECIMAL(12,4) NOT NULL,
    applies_to          TEXT NOT NULL DEFAULT 'all_services'
        CHECK (applies_to IN ('all_services','specific_service','specific_category','medication_only')),
    service_category_id UUID,
    is_active           BOOLEAN DEFAULT true,
    created_by          UUID,
    updated_by          UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_commission_rules_profession
    ON public.commission_rules(profession_id, is_active);

DROP TRIGGER IF EXISTS trg_commission_rules_updated_at ON public.commission_rules;
CREATE TRIGGER trg_commission_rules_updated_at
    BEFORE UPDATE ON public.commission_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.commissions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id           UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    employee_id         UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    commission_rule_id  UUID REFERENCES public.commission_rules(id) ON DELETE SET NULL,
    sale_transaction_id UUID,
    sale_amount         DECIMAL(12,2) NOT NULL,
    calculated_amount   DECIMAL(12,2) NOT NULL,
    adjusted_amount     DECIMAL(12,2),
    adjustment_reason   TEXT,
    status              TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','paid','rejected')),
    period_start        DATE NOT NULL,
    period_end          DATE NOT NULL,
    approved_by         UUID,
    approved_at         TIMESTAMPTZ,
    created_by          UUID,
    updated_by          UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_commissions_period ON public.commissions(profession_id, employee_id, period_start, period_end)
    WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_commissions_employee ON public.commissions(employee_id);

DROP TRIGGER IF EXISTS trg_commissions_updated_at ON public.commissions;
CREATE TRIGGER trg_commissions_updated_at
    BEFORE UPDATE ON public.commissions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 7. PAYROLL
-- ============================================================
CREATE TABLE IF NOT EXISTS public.payroll_runs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id           UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    run_name            TEXT NOT NULL,
    period_start        DATE NOT NULL,
    period_end          DATE NOT NULL,
    pay_date            DATE,
    status              TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','calculating','pending_approval','approved','paid','cancelled')),
    total_gross         DECIMAL(12,2) DEFAULT 0,
    total_deductions    DECIMAL(12,2) DEFAULT 0,
    total_net           DECIMAL(12,2) DEFAULT 0,
    approved_by         UUID,
    approved_at         TIMESTAMPTZ,
    notes               TEXT,
    created_by          UUID,
    updated_by          UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payroll_runs_status ON public.payroll_runs(profession_id, status)
    WHERE status IN ('draft','calculating','pending_approval');

DROP TRIGGER IF EXISTS trg_payroll_runs_updated_at ON public.payroll_runs;
CREATE TRIGGER trg_payroll_runs_updated_at
    BEFORE UPDATE ON public.payroll_runs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.payroll_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    payroll_run_id      UUID NOT NULL REFERENCES public.payroll_runs(id) ON DELETE CASCADE,
    employee_id         UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    item_type           TEXT NOT NULL
        CHECK (item_type IN ('base_salary','commission','overtime','diligence_allowance','bonus','allowance','deduction','social_security','provident_fund_employee','provident_fund_employer','tax','other')),
    amount              DECIMAL(12,2) NOT NULL,
    is_earning          BOOLEAN NOT NULL DEFAULT true,
    notes               TEXT,
    reference_id        UUID,
    reference_type      TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payroll_items_run ON public.payroll_items(payroll_run_id);
CREATE INDEX IF NOT EXISTS idx_payroll_items_employee ON public.payroll_items(employee_id);

DROP TRIGGER IF EXISTS trg_payroll_items_updated_at ON public.payroll_items;
CREATE TRIGGER trg_payroll_items_updated_at
    BEFORE UPDATE ON public.payroll_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.payroll_item_details (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    payroll_item_id     UUID NOT NULL REFERENCES public.payroll_items(id) ON DELETE CASCADE,
    detail_date         DATE,
    description         TEXT NOT NULL,
    quantity            DECIMAL(10,2) DEFAULT 1,
    unit_amount         DECIMAL(12,2),
    total_amount        DECIMAL(12,2) NOT NULL,
    source_type         TEXT,
    source_id           UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payroll_item_details_item ON public.payroll_item_details(payroll_item_id);

-- ============================================================
-- 8. LEAVE MANAGEMENT
-- ============================================================
CREATE TABLE IF NOT EXISTS public.leave_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id           UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    employee_id         UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    leave_type          TEXT NOT NULL
        CHECK (leave_type IN ('sick','annual','personal','maternity','paternity','bereavement','unpaid','other')),
    start_date          DATE NOT NULL,
    end_date            DATE NOT NULL,
    days_requested      DECIMAL(4,1) NOT NULL,
    reason              TEXT,
    status              TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected','cancelled')),
    approved_by         UUID,
    approved_at         TIMESTAMPTZ,
    approval_notes      TEXT,
    created_by          UUID,
    updated_by          UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leave_pending ON public.leave_requests(profession_id, employee_id, status)
    WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON public.leave_requests(employee_id);

DROP TRIGGER IF EXISTS trg_leave_requests_updated_at ON public.leave_requests;
CREATE TRIGGER trg_leave_requests_updated_at
    BEFORE UPDATE ON public.leave_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 9. RLS (Enable but allow all — controlled at Application Layer)
-- ============================================================
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'hr_settings','benefit_policies',
        'shift_templates','work_shifts',
        'attendance_devices','time_attendances',
        'commission_rules','commissions',
        'payroll_runs','payroll_items','payroll_item_details',
        'leave_requests'
    ]
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_select ON public.%I;', tbl, tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I_modify ON public.%I;', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_select ON public.%I FOR SELECT USING (true);', tbl, tbl);
        EXECUTE format('CREATE POLICY %I_modify ON public.%I FOR ALL USING (true);', tbl, tbl);
    END LOOP;
END $$;
