-- Migration: HR Settings RPC + Seed defaults
-- Functions: upsert_hr_settings, get_hr_settings_for_profession
-- Seeds default hr_settings for existing professions

-- ============================================================
-- 1. RPC: Upsert HR Settings
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_hr_settings(
    p_profession_id            UUID,
    p_attendance_mode           TEXT DEFAULT 'manual',
    p_allow_flexible_hours      BOOLEAN DEFAULT false,
    p_default_work_hours_per_day DECIMAL DEFAULT 8.00,
    p_ot_multiplier_weekday     DECIMAL DEFAULT 1.50,
    p_ot_multiplier_weekend     DECIMAL DEFAULT 2.00,
    p_ot_multiplier_holiday     DECIMAL DEFAULT 3.00,
    p_social_security_rate      DECIMAL DEFAULT 0.0500,
    p_diligence_allowance_amount DECIMAL DEFAULT 0,
    p_external_hrm_api_url      TEXT DEFAULT NULL,
    p_external_hrm_sync_enabled BOOLEAN DEFAULT false
) RETURNS public.hr_settings AS $$
DECLARE
    v_result public.hr_settings%ROWTYPE;
BEGIN
    INSERT INTO public.hr_settings (
        profession_id, attendance_mode, allow_flexible_hours,
        default_work_hours_per_day, ot_multiplier_weekday, ot_multiplier_weekend,
        ot_multiplier_holiday, social_security_rate, diligence_allowance_amount,
        external_hrm_api_url, external_hrm_sync_enabled
    ) VALUES (
        p_profession_id, p_attendance_mode, p_allow_flexible_hours,
        p_default_work_hours_per_day, p_ot_multiplier_weekday, p_ot_multiplier_weekend,
        p_ot_multiplier_holiday, p_social_security_rate, p_diligence_allowance_amount,
        p_external_hrm_api_url, p_external_hrm_sync_enabled
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
        updated_at = NOW()
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 2. RPC: Get HR Settings for profession
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_hr_settings_for_profession(
    p_profession_id UUID
) RETURNS public.hr_settings AS $$
DECLARE
    v_result public.hr_settings%ROWTYPE;
BEGIN
    SELECT * INTO v_result
    FROM public.hr_settings
    WHERE profession_id = p_profession_id
    LIMIT 1;

    IF NOT FOUND THEN
        -- Return defaults if no settings exist
        RETURN NULL;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3. RPC: Run Payroll Calculation (server-side)
-- ============================================================
CREATE OR REPLACE FUNCTION public.run_payroll_calculation(
    p_payroll_run_id UUID,
    p_profession_id  UUID,
    p_period_start   DATE,
    p_period_end     DATE
) RETURNS public.payroll_runs AS $$
DECLARE
    v_settings   public.hr_settings%ROWTYPE;
    v_run        public.payroll_runs%ROWTYPE;
    v_emp        public.employees%ROWTYPE;
    v_ot_count   INT;
    v_late_count INT;
    v_absent_count INT;
    v_comm_total DECIMAL(12,2);
    v_base_salary DECIMAL(12,2);
    v_ot_amount  DECIMAL(12,2);
    v_diligence  DECIMAL(12,2);
    v_ss_amount  DECIMAL(12,2);
    v_gross      DECIMAL(12,2);
    v_deductions DECIMAL(12,2);
    v_net        DECIMAL(12,2);
    v_hourly_rate DECIMAL(12,4);
    v_total_gross DECIMAL(12,2) := 0;
    v_total_ded  DECIMAL(12,2) := 0;
    v_emp_count  INT := 0;
    v_work_hours DECIMAL(4,2);
BEGIN
    -- Load HR settings
    SELECT * INTO v_settings
    FROM public.hr_settings
    WHERE profession_id = p_profession_id
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'HR settings not found for profession %', p_profession_id;
    END IF;

    -- Load existing payroll run (must be in 'draft' or 'calculating' status)
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
        v_base_salary := COALESCE(v_emp.salary, 0);
        v_ot_count := 0;
        v_late_count := 0;
        v_absent_count := 0;
        v_comm_total := 0;

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

        -- Sum approved commissions
        SELECT COALESCE(SUM(COALESCE(adjusted_amount, calculated_amount)), 0)
        INTO v_comm_total
        FROM public.commissions
        WHERE profession_id = p_profession_id
          AND employee_id = v_emp.id
          AND status = 'approved'
          AND period_start <= p_period_end
          AND period_end >= p_period_start;

        -- Calculate amounts (guard against division by zero)
        v_work_hours := COALESCE(v_settings.default_work_hours_per_day, 8.00);
        IF v_work_hours <= 0 THEN
            v_work_hours := 8.00;
        END IF;
        v_hourly_rate := v_base_salary / (v_work_hours * 30);
        v_ot_amount := v_ot_count * v_hourly_rate * v_settings.ot_multiplier_weekday;
        v_diligence := CASE WHEN v_late_count = 0 AND v_absent_count = 0
            THEN v_settings.diligence_allowance_amount ELSE 0 END;
        v_ss_amount := LEAST(v_base_salary * v_settings.social_security_rate, 750.00);

        v_gross := v_base_salary + v_ot_amount + v_diligence + v_comm_total;
        v_deductions := v_ss_amount;
        v_net := v_gross - v_deductions;

        -- Insert payroll items
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

        IF v_ss_amount > 0 THEN
            INSERT INTO public.payroll_items (profession_id, payroll_run_id, employee_id, item_type, amount, is_earning)
            VALUES (p_profession_id, v_run.id, v_emp.id, 'social_security', v_ss_amount, false);
        END IF;

        v_total_gross := v_total_gross + v_gross;
        v_total_ded := v_total_ded + v_deductions;
        v_emp_count := v_emp_count + 1;
    END LOOP;

    -- Update payroll run totals
    UPDATE public.payroll_runs
    SET status = 'pending_approval',
        total_gross = v_total_gross,
        total_deductions = v_total_ded,
        total_net = v_total_gross - v_total_ded
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
-- 4. RPC: Approve Payroll Run
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

    -- Insert outbox event (will be auto-processed by trigger to create GL entries)
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
            'total_net', v_run.total_net
        )
    );

    SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_payroll_run_id;
    RETURN v_run;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. Seed default hr_settings for existing professions
-- ============================================================
INSERT INTO public.hr_settings (profession_id)
SELECT p.id FROM public.professions p
WHERE NOT EXISTS (
    SELECT 1 FROM public.hr_settings hs WHERE hs.profession_id = p.id
)
ON CONFLICT (profession_id) DO NOTHING;
