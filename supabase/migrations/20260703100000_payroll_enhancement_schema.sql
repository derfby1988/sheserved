-- Migration: Payroll Enhancement Schema (Thai Payroll — Tax, PF, OT Holiday, Employer Cost)
-- Adds: thai_holidays, employee_tax_allowances tables
-- Alters: hr_settings, employees, payroll_runs, payroll_items (CHECK constraint)
-- Prerequisites: 20260701100000_create_hr_payroll_schema.sql, 20260609215000_create_employees_table.sql

-- ============================================================
-- 1. ALTER hr_settings — Add PF, Tax, Late/Absent config
-- ============================================================
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS provident_fund_employee_rate DECIMAL(5,4) DEFAULT 0.0300;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS provident_fund_employer_rate DECIMAL(5,4) DEFAULT 0.0300;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS provident_fund_wage_cap DECIMAL(12,2) DEFAULT 100000.00;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS tax_calculation_enabled BOOLEAN DEFAULT false;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS late_deduction_per_minute DECIMAL(12,4) DEFAULT 0;
ALTER TABLE public.hr_settings ADD COLUMN IF NOT EXISTS absent_deduction_per_day DECIMAL(12,2) DEFAULT 0;

-- ============================================================
-- 2. ALTER employees — Add base_salary, tax, bank, PF fields
-- ============================================================
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS base_salary DECIMAL(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS tax_deductible_expenses DECIMAL(12,2) DEFAULT 0;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS personal_allowance DECIMAL(12,2) DEFAULT 60000;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS provident_fund_rate DECIMAL(5,4) DEFAULT 0.0300;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'bank_transfer'
    CHECK (payment_method IN ('bank_transfer','cash','check'));
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS bank_account_number TEXT;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS bank_name TEXT;

-- ============================================================
-- 3. ALTER payroll_runs — Add employer cost columns
-- ============================================================
ALTER TABLE public.payroll_runs ADD COLUMN IF NOT EXISTS employer_social_security DECIMAL(12,2) DEFAULT 0;
ALTER TABLE public.payroll_runs ADD COLUMN IF NOT EXISTS employer_provident_fund DECIMAL(12,2) DEFAULT 0;
ALTER TABLE public.payroll_runs ADD COLUMN IF NOT EXISTS total_employer_cost DECIMAL(12,2) DEFAULT 0;

-- ============================================================
-- 4. ALTER payroll_items — Expand CHECK constraint for new item types
-- ============================================================
ALTER TABLE public.payroll_items DROP CONSTRAINT IF EXISTS payroll_items_item_type_check;
ALTER TABLE public.payroll_items ADD CONSTRAINT payroll_items_item_type_check
    CHECK (item_type IN (
        'base_salary','commission','overtime','diligence_allowance','bonus','allowance',
        'deduction','social_security','social_security_employer',
        'provident_fund_employee','provident_fund_employer',
        'tax','late_penalty','absent_penalty','other'
    ));

-- ============================================================
-- 4b. ALTER time_attendances — Add late_minutes / absent_days for penalty calculation
-- ============================================================
ALTER TABLE public.time_attendances ADD COLUMN IF NOT EXISTS late_minutes DECIMAL(6,2) DEFAULT 0;
ALTER TABLE public.time_attendances ADD COLUMN IF NOT EXISTS absent_days DECIMAL(4,1) DEFAULT 1;

-- ============================================================
-- 5. CREATE thai_holidays — For OT holiday multiplier lookup
-- ============================================================
CREATE TABLE IF NOT EXISTS public.thai_holidays (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    holiday_date    DATE NOT NULL UNIQUE,
    holiday_name_th TEXT NOT NULL,
    holiday_name_en TEXT,
    holiday_type    TEXT NOT NULL DEFAULT 'public'
        CHECK (holiday_type IN ('public','religious','substitution','special')),
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_thai_holidays_date
    ON public.thai_holidays(holiday_date) WHERE is_active = true;

ALTER TABLE public.thai_holidays ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS thai_holidays_select ON public.thai_holidays;
DROP POLICY IF EXISTS thai_holidays_modify ON public.thai_holidays;
CREATE POLICY thai_holidays_select ON public.thai_holidays FOR SELECT USING (true);
CREATE POLICY thai_holidays_modify ON public.thai_holidays FOR ALL USING (true);

-- ============================================================
-- 6. CREATE employee_tax_allowances — Tax deduction allowances
-- ============================================================
CREATE TABLE IF NOT EXISTS public.employee_tax_allowances (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    employee_id     UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
    allowance_type  TEXT NOT NULL
        CHECK (allowance_type IN ('personal','spouse','child','parent','insurance','donation','housing','education','disability','other')),
    amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    description     TEXT,
    effective_year  INTEGER NOT NULL DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_employee_tax_allowances_emp
    ON public.employee_tax_allowances(profession_id, employee_id, effective_year);

ALTER TABLE public.employee_tax_allowances ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS employee_tax_allowances_select ON public.employee_tax_allowances;
DROP POLICY IF EXISTS employee_tax_allowances_modify ON public.employee_tax_allowances;
CREATE POLICY employee_tax_allowances_select ON public.employee_tax_allowances FOR SELECT USING (true);
CREATE POLICY employee_tax_allowances_modify ON public.employee_tax_allowances FOR ALL USING (true);

-- ============================================================
-- 7. SEED Thai holidays for current year (2026)
-- ============================================================
INSERT INTO public.thai_holidays (holiday_date, holiday_name_th, holiday_name_en, holiday_type)
VALUES
    ('2026-01-01', 'วันปีใหม่', 'New Year''s Day', 'public'),
    ('2026-01-13', 'วันเด็กแห่งชาติ', 'National Children''s Day', 'public'),
    ('2026-02-09', 'วันมาฆบูชา', 'Makha Bucha Day', 'religious'),
    ('2026-04-06', 'วันจักรี', 'Chakri Memorial Day', 'public'),
    ('2026-04-13', 'วันสงกรานต์', 'Songkran Festival Day', 'public'),
    ('2026-04-14', 'วันสงกรานต์', 'Songkran Festival Day', 'public'),
    ('2026-04-15', 'วันสงกรานต์', 'Songkran Festival Day', 'public'),
    ('2026-05-01', 'วันแรงงานแห่งชาติ', 'National Labour Day', 'public'),
    ('2026-05-05', 'วันฉัตรมงคล', 'Coronation Day', 'public'),
    ('2026-05-22', 'วันวิสาขบูชา', 'Visakha Bucha Day', 'religious'),
    ('2026-07-28', 'วันเฉลิมพระชนมพรรษา ร.10', 'King Rama X Birthday', 'public'),
    ('2026-08-12', 'วันแม่แห่งชาติ', 'National Mother''s Day', 'public'),
    ('2026-10-23', 'วันปิยะมหาราช', 'King Chulalongkorn Memorial Day', 'public'),
    ('2026-12-05', 'วันพ่อแห่งชาติ', 'National Father''s Day', 'public'),
    ('2026-12-10', 'วันรัฐธรรมนูญ', 'Constitution Day', 'public'),
    ('2026-12-31', 'วันสิ้นปี', 'New Year''s Eve', 'public')
ON CONFLICT (holiday_date) DO NOTHING;

-- ============================================================
-- 8. UPDATE upsert_hr_settings RPC — Add new parameters
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_hr_settings(
    p_profession_id               UUID,
    p_attendance_mode             TEXT DEFAULT 'manual',
    p_allow_flexible_hours        BOOLEAN DEFAULT false,
    p_default_work_hours_per_day  DECIMAL DEFAULT 8.00,
    p_ot_multiplier_weekday       DECIMAL DEFAULT 1.50,
    p_ot_multiplier_weekend       DECIMAL DEFAULT 2.00,
    p_ot_multiplier_holiday       DECIMAL DEFAULT 3.00,
    p_social_security_rate        DECIMAL DEFAULT 0.0500,
    p_diligence_allowance_amount  DECIMAL DEFAULT 0,
    p_external_hrm_api_url        TEXT DEFAULT NULL,
    p_external_hrm_sync_enabled   BOOLEAN DEFAULT false,
    p_provident_fund_employee_rate DECIMAL DEFAULT 0.0300,
    p_provident_fund_employer_rate DECIMAL DEFAULT 0.0300,
    p_provident_fund_wage_cap     DECIMAL DEFAULT 100000.00,
    p_tax_calculation_enabled     BOOLEAN DEFAULT false,
    p_late_deduction_per_minute   DECIMAL DEFAULT 0,
    p_absent_deduction_per_day    DECIMAL DEFAULT 0
) RETURNS public.hr_settings AS $$
DECLARE
    v_result public.hr_settings%ROWTYPE;
BEGIN
    INSERT INTO public.hr_settings (
        profession_id, attendance_mode, allow_flexible_hours,
        default_work_hours_per_day, ot_multiplier_weekday, ot_multiplier_weekend,
        ot_multiplier_holiday, social_security_rate, diligence_allowance_amount,
        external_hrm_api_url, external_hrm_sync_enabled,
        provident_fund_employee_rate, provident_fund_employer_rate, provident_fund_wage_cap,
        tax_calculation_enabled, late_deduction_per_minute, absent_deduction_per_day
    ) VALUES (
        p_profession_id, p_attendance_mode, p_allow_flexible_hours,
        p_default_work_hours_per_day, p_ot_multiplier_weekday, p_ot_multiplier_weekend,
        p_ot_multiplier_holiday, p_social_security_rate, p_diligence_allowance_amount,
        p_external_hrm_api_url, p_external_hrm_sync_enabled,
        p_provident_fund_employee_rate, p_provident_fund_employer_rate, p_provident_fund_wage_cap,
        p_tax_calculation_enabled, p_late_deduction_per_minute, p_absent_deduction_per_day
    )
    ON CONFLICT (profession_id) DO UPDATE SET
        attendance_mode = EXCLUDED.attendance_mode,
        allow_flexible_hours = EXCLUDED.allow_flexible_hours,
        default_work_hours_per_day = EXCLUDED.default_work_hours_per_day,
        ot_multiplier_weekday = EXCLUDED.ot_multiplier_weekday,
        ot_multiplier_weekend = EXCLUDED.ot_multiplier_weekend,
        ot_multiplier_holiday = EXCLUDED.ot_multiplier_holiday,
        social_security_rate = EXCLUDED.social_security_rate,
        diligence_allowance_amount = EXCLUDED.diligence_allowance_amount,
        external_hrm_api_url = EXCLUDED.external_hrm_api_url,
        external_hrm_sync_enabled = EXCLUDED.external_hrm_sync_enabled,
        provident_fund_employee_rate = EXCLUDED.provident_fund_employee_rate,
        provident_fund_employer_rate = EXCLUDED.provident_fund_employer_rate,
        provident_fund_wage_cap = EXCLUDED.provident_fund_wage_cap,
        tax_calculation_enabled = EXCLUDED.tax_calculation_enabled,
        late_deduction_per_minute = EXCLUDED.late_deduction_per_minute,
        absent_deduction_per_day = EXCLUDED.absent_deduction_per_day,
        updated_at = NOW()
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 9. UPDATE run_payroll_calculation RPC — Full Thai payroll
-- ============================================================
CREATE OR REPLACE FUNCTION public.run_payroll_calculation(
    p_payroll_run_id UUID,
    p_profession_id  UUID,
    p_period_start   DATE,
    p_period_end     DATE
) RETURNS public.payroll_runs AS $$
DECLARE
    v_settings         public.hr_settings%ROWTYPE;
    v_run              public.payroll_runs%ROWTYPE;
    v_emp              public.employees%ROWTYPE;
    v_ot_count         INT;
    v_ot_holiday_count INT;
    v_ot_weekend_count INT;
    v_late_count       INT;
    v_absent_count     INT;
    v_late_minutes     INT;
    v_absent_days      DECIMAL(4,1);
    v_comm_total       DECIMAL(12,2);
    v_base_salary      DECIMAL(12,2);
    v_ot_amount        DECIMAL(12,2);
    v_diligence        DECIMAL(12,2);
    v_ss_emp           DECIMAL(12,2);
    v_ss_employer      DECIMAL(12,2);
    v_pf_base          DECIMAL(12,2);
    v_pf_emp           DECIMAL(12,2);
    v_pf_employer      DECIMAL(12,2);
    v_tax_amount       DECIMAL(12,2);
    v_late_penalty     DECIMAL(12,2);
    v_absent_penalty   DECIMAL(12,2);
    v_gross            DECIMAL(12,2);
    v_deductions       DECIMAL(12,2);
    v_net              DECIMAL(12,2);
    v_hourly_rate      DECIMAL(12,4);
    v_total_gross      DECIMAL(12,2) := 0;
    v_total_ded        DECIMAL(12,2) := 0;
    v_total_ss_employer DECIMAL(12,2) := 0;
    v_total_pf_employer DECIMAL(12,2) := 0;
    v_emp_count        INT := 0;
    v_work_hours       DECIMAL(4,2);
    v_annual_income    DECIMAL(12,2);
    v_taxable_income   DECIMAL(12,2);
    v_tax_annual       DECIMAL(12,2);
    v_tax_allowance_sum DECIMAL(12,2);
BEGIN
    -- Load HR settings
    SELECT * INTO v_settings
    FROM public.hr_settings
    WHERE profession_id = p_profession_id
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'HR settings not found for profession %', p_profession_id;
    END IF;

    -- Load existing payroll run
    SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_payroll_run_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll run % not found', p_payroll_run_id;
    END IF;

    IF v_run.status NOT IN ('draft','calculating') THEN
        RAISE EXCEPTION 'Payroll run % already processed (status=%)', p_payroll_run_id, v_run.status;
    END IF;

    -- Idempotency: delete existing items if re-running
    DELETE FROM public.payroll_items WHERE payroll_run_id = p_payroll_run_id;

    -- Mark as calculating
    UPDATE public.payroll_runs SET status = 'calculating' WHERE id = p_payroll_run_id;

    -- Process each active employee
    FOR v_emp IN
        SELECT * FROM public.employees
        WHERE profession_id = p_profession_id
          AND is_active = true
    LOOP
        v_base_salary := COALESCE(v_emp.base_salary, 0);
        v_ot_count := 0;
        v_ot_holiday_count := 0;
        v_ot_weekend_count := 0;
        v_late_count := 0;
        v_absent_count := 0;
        v_late_minutes := 0;
        v_absent_days := 0;
        v_comm_total := 0;
        v_pf_emp := 0;
        v_pf_employer := 0;
        v_tax_amount := 0;
        v_late_penalty := 0;
        v_absent_penalty := 0;

        -- Count attendance statuses
        SELECT
            COUNT(*) FILTER (WHERE attendance_status = 'overtime'),
            COUNT(*) FILTER (WHERE attendance_status = 'late'),
            COUNT(*) FILTER (WHERE attendance_status = 'absent')
        INTO v_ot_count, v_late_count, v_absent_count
        FROM public.time_attendances
        WHERE profession_id = p_profession_id
          AND employee_id = v_emp.id
          AND clock_in_time >= p_period_start::TIMESTAMPTZ
          AND clock_in_time < (p_period_end + INTERVAL '1 day')::TIMESTAMPTZ;

        -- Sum late minutes and absent days for penalty calculation
        SELECT COALESCE(SUM(late_minutes), 0)
        INTO v_late_minutes
        FROM public.time_attendances
        WHERE profession_id = p_profession_id
          AND employee_id = v_emp.id
          AND attendance_status = 'late'
          AND clock_in_time >= p_period_start::TIMESTAMPTZ
          AND clock_in_time < (p_period_end + INTERVAL '1 day')::TIMESTAMPTZ;

        SELECT COALESCE(SUM(absent_days), 0)
        INTO v_absent_days
        FROM public.time_attendances
        WHERE profession_id = p_profession_id
          AND employee_id = v_emp.id
          AND attendance_status = 'absent'
          AND clock_in_time >= p_period_start::TIMESTAMPTZ
          AND clock_in_time < (p_period_end + INTERVAL '1 day')::TIMESTAMPTZ;

        -- Sum approved commissions
        SELECT COALESCE(SUM(COALESCE(adjusted_amount, calculated_amount)), 0)
        INTO v_comm_total
        FROM public.commissions
        WHERE profession_id = p_profession_id
          AND employee_id = v_emp.id
          AND status = 'approved'
          AND period_start <= p_period_end
          AND period_end >= p_period_start;

        -- Calculate hourly rate (guard against division by zero)
        v_work_hours := COALESCE(v_settings.default_work_hours_per_day, 8.00);
        IF v_work_hours <= 0 THEN
            v_work_hours := 8.00;
        END IF;
        v_hourly_rate := v_base_salary / (v_work_hours * 30);

        -- Calculate OT with holiday/weekend awareness
        -- Check if any OT days fall on holidays
        SELECT COUNT(*) INTO v_ot_holiday_count
        FROM public.time_attendances ta
        WHERE ta.profession_id = p_profession_id
          AND ta.employee_id = v_emp.id
          AND ta.attendance_status = 'overtime'
          AND ta.clock_in_time >= p_period_start::TIMESTAMPTZ
          AND ta.clock_in_time < (p_period_end + INTERVAL '1 day')::TIMESTAMPTZ
          AND EXISTS (
              SELECT 1 FROM public.thai_holidays th
              WHERE th.holiday_date = ta.clock_in_time::DATE
                AND th.is_active = true
          );

        -- Weekend OT count (Saturday=6, Sunday=0)
        SELECT COUNT(*) INTO v_ot_weekend_count
        FROM public.time_attendances ta
        WHERE ta.profession_id = p_profession_id
          AND ta.employee_id = v_emp.id
          AND ta.attendance_status = 'overtime'
          AND ta.clock_in_time >= p_period_start::TIMESTAMPTZ
          AND ta.clock_in_time < (p_period_end + INTERVAL '1 day')::TIMESTAMPTZ
          AND EXTRACT(DOW FROM ta.clock_in_time) IN (0, 6)
          AND NOT EXISTS (
              SELECT 1 FROM public.thai_holidays th
              WHERE th.holiday_date = ta.clock_in_time::DATE
                AND th.is_active = true
          );

        v_ot_count := v_ot_count - v_ot_holiday_count - v_ot_weekend_count;

        v_ot_amount := (v_ot_count * v_hourly_rate * v_settings.ot_multiplier_weekday)
                     + (v_ot_weekend_count * v_hourly_rate * v_settings.ot_multiplier_weekend)
                     + (v_ot_holiday_count * v_hourly_rate * v_settings.ot_multiplier_holiday);

        -- Diligence allowance
        v_diligence := CASE WHEN v_late_count = 0 AND v_absent_count = 0
            THEN v_settings.diligence_allowance_amount ELSE 0 END;

        -- Social Security (employee + employer, same rate)
        v_ss_emp := LEAST(v_base_salary * v_settings.social_security_rate, 750.00);
        v_ss_employer := v_ss_emp; -- Employer pays same as employee

        -- Provident Fund (with wage cap)
        v_pf_base := LEAST(v_base_salary, COALESCE(v_settings.provident_fund_wage_cap, 100000.00));
        v_pf_emp := v_pf_base * COALESCE(v_settings.provident_fund_employee_rate, 0.03);
        v_pf_employer := v_pf_base * COALESCE(v_settings.provident_fund_employer_rate, 0.03);

        -- Tax Withholding (PIT) — only if enabled
        IF v_settings.tax_calculation_enabled THEN
            -- Sum tax allowances for current year
            SELECT COALESCE(SUM(amount), 0) INTO v_tax_allowance_sum
            FROM public.employee_tax_allowances
            WHERE employee_id = v_emp.id
              AND effective_year = EXTRACT(YEAR FROM p_period_start);

            -- Estimated annual income
            v_annual_income := (v_base_salary + v_ot_amount + v_comm_total + v_diligence) * 12;

            -- Taxable income = annual_income - personal_allowance - tax_allowances - SS*12 - PF*12 - deductible expenses
            v_taxable_income := v_annual_income
                - COALESCE(v_emp.personal_allowance, 60000)
                - v_tax_allowance_sum
                - (v_ss_emp * 12)
                - (v_pf_emp * 12)
                - COALESCE(v_emp.tax_deductible_expenses, 0);

            IF v_taxable_income <= 0 THEN
                v_tax_annual := 0;
            ELSIF v_taxable_income <= 150000 THEN
                v_tax_annual := 0;
            ELSIF v_taxable_income <= 300000 THEN
                v_tax_annual := (v_taxable_income - 150000) * 0.05;
            ELSIF v_taxable_income <= 500000 THEN
                v_tax_annual := 7500 + (v_taxable_income - 300000) * 0.10;
            ELSIF v_taxable_income <= 750000 THEN
                v_tax_annual := 27500 + (v_taxable_income - 500000) * 0.15;
            ELSIF v_taxable_income <= 1000000 THEN
                v_tax_annual := 65000 + (v_taxable_income - 750000) * 0.20;
            ELSIF v_taxable_income <= 2000000 THEN
                v_tax_annual := 115000 + (v_taxable_income - 1000000) * 0.25;
            ELSIF v_taxable_income <= 5000000 THEN
                v_tax_annual := 365000 + (v_taxable_income - 2000000) * 0.30;
            ELSE
                v_tax_annual := 1265000 + (v_taxable_income - 5000000) * 0.35;
            END IF;

            v_tax_amount := v_tax_annual / 12.0;
            IF v_tax_amount < 0 THEN
                v_tax_amount := 0;
            END IF;
        END IF;

        -- Late/Absent penalty
        v_late_penalty := v_late_count * COALESCE(v_settings.late_deduction_per_minute, 0);
        v_absent_penalty := v_absent_days * COALESCE(v_settings.absent_deduction_per_day, 0);

        -- Calculate totals
        v_gross := v_base_salary + v_ot_amount + v_diligence + v_comm_total;
        v_deductions := v_ss_emp + v_pf_emp + v_tax_amount + v_late_penalty + v_absent_penalty;
        v_net := v_gross - v_deductions;

        -- Insert payroll items (earnings)
        IF v_base_salary > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'base_salary', v_base_salary, true);
        END IF;

        IF v_ot_amount > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'overtime', v_ot_amount, true);
        END IF;

        IF v_diligence > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'diligence_allowance', v_diligence, true);
        END IF;

        IF v_comm_total > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'commission', v_comm_total, true);
        END IF;

        -- Insert payroll items (deductions)
        IF v_ss_emp > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'social_security', v_ss_emp, false);
        END IF;

        IF v_pf_emp > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'provident_fund_employee', v_pf_emp, false);
        END IF;

        IF v_tax_amount > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'tax', v_tax_amount, false);
        END IF;

        IF v_late_penalty > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'late_penalty', v_late_penalty, false);
        END IF;

        IF v_absent_penalty > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'absent_penalty', v_absent_penalty, false);
        END IF;

        -- Insert employer cost items
        IF v_ss_employer > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'social_security_employer', v_ss_employer, false);
        END IF;

        IF v_pf_employer > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'provident_fund_employer', v_pf_employer, false);
        END IF;

        v_total_gross := v_total_gross + v_gross;
        v_total_ded := v_total_ded + v_deductions;
        v_total_ss_employer := v_total_ss_employer + v_ss_employer;
        v_total_pf_employer := v_total_pf_employer + v_pf_employer;
        v_emp_count := v_emp_count + 1;
    END LOOP;

    -- Update payroll run totals
    UPDATE public.payroll_runs
    SET status = 'pending_approval',
        total_gross = v_total_gross,
        total_deductions = v_total_ded,
        total_net = v_total_gross - v_total_ded,
        employer_social_security = v_total_ss_employer,
        employer_provident_fund = v_total_pf_employer,
        total_employer_cost = v_total_gross + v_total_ss_employer + v_total_pf_employer
    WHERE id = v_run.id;

    -- Insert outbox event
    INSERT INTO public.outbox_events (profession_id, aggregate_type, aggregate_id, event_type, payload)
    VALUES (
        p_profession_id,
        'hr_payroll',
        p_payroll_run_id,
        'hr.payroll_calculated',
        jsonb_build_object(
            'payroll_run_id', p_payroll_run_id,
            'run_name', v_run.run_name,
            'period_start', p_period_start,
            'period_end', p_period_end,
            'total_gross', v_total_gross,
            'total_deductions', v_total_ded,
            'total_net', v_total_gross - v_total_ded,
            'employer_social_security', v_total_ss_employer,
            'employer_provident_fund', v_total_pf_employer,
            'total_employer_cost', v_total_gross + v_total_ss_employer + v_total_pf_employer,
            'employee_count', v_emp_count,
            'status', 'pending_approval'
        )
    );

    -- Return updated run
    SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_payroll_run_id;
    RETURN v_run;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 10. UPDATE approve_payroll_run RPC — Include employer cost in outbox
-- ============================================================
CREATE OR REPLACE FUNCTION public.approve_payroll_run(
    p_payroll_run_id UUID,
    p_approved_by    UUID
) RETURNS public.payroll_runs AS $$
DECLARE
    v_run public.payroll_runs%ROWTYPE;
BEGIN
    SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_payroll_run_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll run % not found', p_payroll_run_id;
    END IF;

    IF v_run.status != 'pending_approval' THEN
        RAISE EXCEPTION 'Payroll run % is not pending approval (status=%)', p_payroll_run_id, v_run.status;
    END IF;

    UPDATE public.payroll_runs
    SET status = 'approved',
        approved_by = p_approved_by,
        approved_at = NOW()
    WHERE id = p_payroll_run_id;

    -- Insert outbox event: hr.payroll_approved
    INSERT INTO public.outbox_events (profession_id, aggregate_type, aggregate_id, event_type, payload)
    VALUES (
        v_run.profession_id,
        'hr_payroll',
        p_payroll_run_id,
        'hr.payroll_approved',
        jsonb_build_object(
            'payroll_run_id', p_payroll_run_id,
            'approved_by', p_approved_by,
            'approved_at', NOW(),
            'total_net', v_run.total_net,
            'total_gross', v_run.total_gross,
            'total_deductions', v_run.total_deductions,
            'employer_social_security', v_run.employer_social_security,
            'employer_provident_fund', v_run.employer_provident_fund,
            'total_employer_cost', v_run.total_employer_cost
        )
    );

    -- Insert outbox event: accounting.payroll_expense_posted
    INSERT INTO public.outbox_events (profession_id, aggregate_type, aggregate_id, event_type, payload)
    VALUES (
        v_run.profession_id,
        'hr_payroll',
        p_payroll_run_id,
        'accounting.payroll_expense_posted',
        jsonb_build_object(
            'payroll_run_id', p_payroll_run_id,
            'total_gross', v_run.total_gross,
            'total_deductions', v_run.total_deductions,
            'total_net', v_run.total_net,
            'employer_social_security', v_run.employer_social_security,
            'employer_provident_fund', v_run.employer_provident_fund,
            'gl_entries', jsonb_build_array(
                jsonb_build_object('account_code', '6101', 'debit', v_run.total_gross, 'credit', 0),
                jsonb_build_object('account_code', '2191', 'debit', 0, 'credit', v_run.total_net),
                jsonb_build_object('account_code', '2192', 'debit', 0, 'credit', v_run.total_deductions),
                jsonb_build_object('account_code', '6102', 'debit',
                    v_run.employer_social_security + v_run.employer_provident_fund, 'credit', 0)
            )
        )
    );

    SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_payroll_run_id;
    RETURN v_run;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 11. RPC: CRUD for employee_tax_allowances
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_tax_allowance(
    p_profession_id  UUID,
    p_employee_id    UUID,
    p_allowance_type TEXT,
    p_amount         DECIMAL(12,2),
    p_description    TEXT DEFAULT NULL,
    p_effective_year INTEGER DEFAULT NULL
) RETURNS public.employee_tax_allowances AS $$
DECLARE
    v_result public.employee_tax_allowances%ROWTYPE;
    v_year INTEGER;
BEGIN
    v_year := COALESCE(p_effective_year, EXTRACT(YEAR FROM CURRENT_DATE))::INTEGER;

    INSERT INTO public.employee_tax_allowances (
        profession_id, employee_id, allowance_type, amount, description, effective_year
    ) VALUES (
        p_profession_id, p_employee_id, p_allowance_type, p_amount, p_description, v_year
    )
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_tax_allowances(
    p_employee_id   UUID,
    p_effective_year INTEGER DEFAULT NULL
) RETURNS SETOF public.employee_tax_allowances AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM public.employee_tax_allowances
    WHERE employee_id = p_employee_id
      AND effective_year = COALESCE(p_effective_year, EXTRACT(YEAR FROM CURRENT_DATE))
    ORDER BY allowance_type;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.delete_tax_allowance(
    p_allowance_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM public.employee_tax_allowances WHERE id = p_allowance_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 12. RPC: CRUD for thai_holidays
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_thai_holiday(
    p_holiday_date    DATE,
    p_holiday_name_th TEXT,
    p_holiday_name_en TEXT DEFAULT NULL,
    p_holiday_type    TEXT DEFAULT 'public'
) RETURNS public.thai_holidays AS $$
DECLARE
    v_result public.thai_holidays%ROWTYPE;
BEGIN
    INSERT INTO public.thai_holidays (holiday_date, holiday_name_th, holiday_name_en, holiday_type)
    VALUES (p_holiday_date, p_holiday_name_th, p_holiday_name_en, p_holiday_type)
    ON CONFLICT (holiday_date) DO UPDATE SET
        holiday_name_th = EXCLUDED.holiday_name_th,
        holiday_name_en = EXCLUDED.holiday_name_en,
        holiday_type = EXCLUDED.holiday_type,
        is_active = true
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_thai_holidays(
    p_year INTEGER DEFAULT NULL
) RETURNS SETOF public.thai_holidays AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM public.thai_holidays
    WHERE is_active = true
      AND (p_year IS NULL OR EXTRACT(YEAR FROM holiday_date) = p_year)
    ORDER BY holiday_date;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.delete_thai_holiday(
    p_holiday_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.thai_holidays SET is_active = false WHERE id = p_holiday_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
