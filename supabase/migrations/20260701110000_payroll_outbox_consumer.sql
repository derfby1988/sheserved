-- Migration: Outbox Consumer for Payroll → Accounting
-- Function: process_payroll_outbox_events()
-- Consumes hr.payroll_approved events from outbox_events and creates GL entries
-- Prerequisites: outbox_events, gl_entries, chart_of_accounts, payroll_runs, payroll_items

-- ============================================================
-- 1. FUNCTION: Create GL entries from approved payroll
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_gl_from_payroll(
    p_payroll_run_id UUID,
    p_profession_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_run            public.payroll_runs%ROWTYPE;
    v_salary_account public.chart_of_accounts%ROWTYPE;
    v_payable_account public.chart_of_accounts%ROWTYPE;
    v_ss_account     public.chart_of_accounts%ROWTYPE;
    v_ss_payable     public.chart_of_accounts%ROWTYPE;
    v_ot_account     public.chart_of_accounts%ROWTYPE;
    v_entry_number   TEXT;
    v_total_net      DECIMAL(12,2);
    v_total_ss       DECIMAL(12,2);
    v_total_ot       DECIMAL(12,2);
    v_total_base     DECIMAL(12,2);
    v_total_diligence DECIMAL(12,2);
    v_total_commission DECIMAL(12,2);
    v_total_gross    DECIMAL(12,2);
    v_total_dr       DECIMAL(12,2) := 0;
    v_total_cr       DECIMAL(12,2) := 0;
    v_diligence_account public.chart_of_accounts%ROWTYPE;
    v_commission_account public.chart_of_accounts%ROWTYPE;
BEGIN
    -- Load payroll run
    SELECT * INTO v_run FROM public.payroll_runs WHERE id = p_payroll_run_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll run % not found', p_payroll_run_id;
    END IF;

    IF v_run.status NOT IN ('approved','paid') THEN
        RAISE EXCEPTION 'Payroll run % is not approved (status=%)', p_payroll_run_id, v_run.status;
    END IF;

    -- Aggregate amounts by item_type
    SELECT
        COALESCE(SUM(CASE WHEN item_type = 'base_salary' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN item_type = 'overtime' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN item_type = 'social_security' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN item_type = 'diligence_allowance' THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN item_type = 'commission' THEN amount ELSE 0 END), 0)
    INTO v_total_base, v_total_ot, v_total_ss, v_total_diligence, v_total_commission
    FROM public.payroll_items
    WHERE payroll_run_id = p_payroll_run_id;

    v_total_gross := v_total_base + v_total_ot + v_total_diligence + v_total_commission;
    v_total_net := v_run.total_net;

    -- Find salary expense account (5211 — เงินเดือนและค่าจ้างพนักงาน)
    SELECT * INTO v_salary_account
    FROM public.chart_of_accounts
    WHERE profession_id = p_profession_id
      AND account_code = '5211'
      AND is_active = true
    LIMIT 1;

    -- Find overtime expense account (5212 — ค่าล่วงเวลา/โอที)
    SELECT * INTO v_ot_account
    FROM public.chart_of_accounts
    WHERE profession_id = p_profession_id
      AND account_code = '5212'
      AND is_active = true
    LIMIT 1;

    -- IMPORTANT: chart_of_accounts.account_type is SMALLINT (1-5) per 20260609180000,
    -- NOT TEXT as declared in 20260611180000 (which uses IF NOT EXISTS, so it lost).
    -- 1=Asset, 2=Liability, 3=Equity, 4=Revenue, 5=Expense

    -- Find social security expense account (5213 — เงินสมทบกองทุนประกันสังคม)
    SELECT * INTO v_ss_account
    FROM public.chart_of_accounts
    WHERE profession_id = p_profession_id
      AND account_code = '5213'
      AND is_active = true
    LIMIT 1;

    -- Find diligence allowance account (5214 — เบี้ยขยัน/เงินเพิ่ม)
    -- Fallback: 5211 เงินเดือน (เพราะ seed ยังไม่มี 5214)
    SELECT * INTO v_diligence_account
    FROM public.chart_of_accounts
    WHERE profession_id = p_profession_id
      AND account_code = '5214'
      AND is_active = true
    LIMIT 1;

    IF NOT FOUND THEN
        SELECT * INTO v_diligence_account
        FROM public.chart_of_accounts
        WHERE profession_id = p_profession_id
          AND account_code = '5211'
          AND is_active = true
        LIMIT 1;
    END IF;

    -- Find commission/doctor fees account (5121 — ค่าธรรมเนียมแพทย์/ค่ามือแพทย์)
    SELECT * INTO v_commission_account
    FROM public.chart_of_accounts
    WHERE profession_id = p_profession_id
      AND account_code = '5121'
      AND is_active = true
    LIMIT 1;

    -- Find salary payable account (2120 — เงินเดือนค้างจ่าย)
    -- account_type = 2 (Liability)
    SELECT * INTO v_payable_account
    FROM public.chart_of_accounts
    WHERE profession_id = p_profession_id
      AND account_code = '2120'
      AND is_active = true
    LIMIT 1;

    IF NOT FOUND THEN
        SELECT * INTO v_payable_account
        FROM public.chart_of_accounts
        WHERE profession_id = p_profession_id
          AND account_type = 2
          AND account_name LIKE '%เงินเดือนค้างจ่าย%'
          AND is_active = true
        LIMIT 1;
    END IF;

    -- Find social security payable (account_type = 2 Liability)
    SELECT * INTO v_ss_payable
    FROM public.chart_of_accounts
    WHERE profession_id = p_profession_id
      AND account_type = 2
      AND account_name LIKE '%ประกันสังคมค้างจ่าย%'
      AND is_active = true
    LIMIT 1;

    -- Validate required accounts exist
    IF v_total_base > 0 AND v_salary_account.id IS NULL THEN
        RAISE EXCEPTION 'Salary expense account 5211 not found for profession %', p_profession_id;
    END IF;
    IF v_total_ot > 0 AND v_ot_account.id IS NULL THEN
        RAISE EXCEPTION 'Overtime expense account 5212 not found for profession %', p_profession_id;
    END IF;
    IF v_total_diligence > 0 AND v_diligence_account.id IS NULL THEN
        RAISE EXCEPTION 'Diligence allowance account 5214/5211 not found for profession %', p_profession_id;
    END IF;
    IF v_total_commission > 0 AND v_commission_account.id IS NULL THEN
        RAISE EXCEPTION 'Commission account 5121 not found for profession %', p_profession_id;
    END IF;
    IF v_total_net > 0 AND v_payable_account.id IS NULL THEN
        RAISE EXCEPTION 'Salary payable account 2120 not found for profession %', p_profession_id;
    END IF;
    IF v_total_ss > 0 AND v_ss_payable.id IS NULL THEN
        RAISE EXCEPTION 'Social security payable account not found for profession %', p_profession_id;
    END IF;

    -- Generate entry number
    v_entry_number := 'PR-' || v_run.run_name || '-' || EXTRACT(EPOCH FROM NOW())::BIGINT;

    -- 1. Dr เงินเดือนและค่าจ้างพนักงาน (5211)
    IF v_total_base > 0 AND v_salary_account.id IS NOT NULL THEN
        INSERT INTO public.gl_entries (profession_id, entry_date, account_id, debit_amount, credit_amount, description, reference_no)
        VALUES (
            p_profession_id,
            COALESCE(v_run.pay_date, v_run.period_end),
            v_salary_account.id,
            v_total_base,
            0,
            'เงินเดือนพื้นฐาน — ' || v_run.run_name,
            v_entry_number || '-BASE'
        );
    END IF;

    -- 2. Dr ค่าล่วงเวลา (5212)
    IF v_total_ot > 0 AND v_ot_account.id IS NOT NULL THEN
        INSERT INTO public.gl_entries (profession_id, entry_date, account_id, debit_amount, credit_amount, description, reference_no)
        VALUES (
            p_profession_id,
            COALESCE(v_run.pay_date, v_run.period_end),
            v_ot_account.id,
            v_total_ot,
            0,
            'ค่าล่วงเวลา — ' || v_run.run_name,
            v_entry_number || '-OT'
        );
    END IF;

    -- 3. Dr เงินสมทบประกันสังคม (5213) — employer contribution (if any)
    -- Note: In this system, SS is deducted from employee (is_earning=false).
    -- The Dr 5213 is only for employer's matching contribution, which is 0 in current logic.
    -- SS employee deduction is handled by Cr SS payable (line 5) + reduced net pay (line 4).
    -- If employer contribution is added later, insert Dr here.

    -- 3b. Dr เบี้ยขยัน (5214)
    IF v_total_diligence > 0 AND v_diligence_account.id IS NOT NULL THEN
        INSERT INTO public.gl_entries (profession_id, entry_date, account_id, debit_amount, credit_amount, description, reference_no)
        VALUES (
            p_profession_id,
            COALESCE(v_run.pay_date, v_run.period_end),
            v_diligence_account.id,
            v_total_diligence,
            0,
            'เบี้ยขยัน — ' || v_run.run_name,
            v_entry_number || '-DIL'
        );
    END IF;

    -- 3c. Dr ค่าคอมมิชชั่น/ค่ามือแพทย์ (5121)
    IF v_total_commission > 0 AND v_commission_account.id IS NOT NULL THEN
        INSERT INTO public.gl_entries (profession_id, entry_date, account_id, debit_amount, credit_amount, description, reference_no)
        VALUES (
            p_profession_id,
            COALESCE(v_run.pay_date, v_run.period_end),
            v_commission_account.id,
            v_total_commission,
            0,
            'ค่าคอมมิชชั่น — ' || v_run.run_name,
            v_entry_number || '-COMM'
        );
    END IF;

    -- 4. Cr เงินเดือนค้างจ่าย (2120) — net pay (gross - SS deduction)
    IF v_total_net > 0 AND v_payable_account.id IS NOT NULL THEN
        INSERT INTO public.gl_entries (profession_id, entry_date, account_id, debit_amount, credit_amount, description, reference_no)
        VALUES (
            p_profession_id,
            COALESCE(v_run.pay_date, v_run.period_end),
            v_payable_account.id,
            0,
            v_total_net,
            'เงินเดือนค้างจ่าย — ' || v_run.run_name,
            v_entry_number || '-PAY'
        );
    END IF;

    -- 5. Cr ประกันสังคมค้างจ่าย
    IF v_total_ss > 0 AND v_ss_payable.id IS NOT NULL THEN
        INSERT INTO public.gl_entries (profession_id, entry_date, account_id, debit_amount, credit_amount, description, reference_no)
        VALUES (
            p_profession_id,
            COALESCE(v_run.pay_date, v_run.period_end),
            v_ss_payable.id,
            0,
            v_total_ss,
            'ประกันสังคมค้างจ่าย — ' || v_run.run_name,
            v_entry_number || '-SSP'
        );
    END IF;

    -- Compute totals and verify GL balance
    v_total_dr := v_total_base + v_total_ot + v_total_diligence + v_total_commission;
    v_total_cr := v_total_net + v_total_ss;
    IF v_total_dr != v_total_cr THEN
        RAISE EXCEPTION 'GL imbalance for payroll %: Dr=% Cr=%', p_payroll_run_id, v_total_dr, v_total_cr;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 2. FUNCTION: Process pending payroll outbox events
-- ============================================================
CREATE OR REPLACE FUNCTION public.process_payroll_outbox_events(
    p_batch_limit INT DEFAULT 10
) RETURNS TABLE(
    event_id UUID,
    event_type TEXT,
    status TEXT,
    error_message TEXT
) AS $$
DECLARE
    v_event RECORD;
    v_result BOOLEAN;
    v_error TEXT;
BEGIN
    FOR v_event IN
        SELECT id, profession_id, aggregate_id, event_type, payload
        FROM public.outbox_events
        WHERE aggregate_type = 'hr_payroll'
          AND status = 'pending'
          AND event_type IN ('hr.payroll_approved')
        ORDER BY created_at ASC
        LIMIT p_batch_limit
    LOOP
        BEGIN
            -- Mark as processing
            UPDATE public.outbox_events
            SET status = 'processing'
            WHERE id = v_event.id;

            -- Create GL entries
            v_result := public.create_gl_from_payroll(
                v_event.aggregate_id,
                v_event.profession_id
            );

            IF v_result THEN
                UPDATE public.outbox_events
                SET status = 'published', published_at = NOW()
                WHERE id = v_event.id;

                event_id := v_event.id;
                event_type := v_event.event_type;
                status := 'published';
                error_message := NULL;
                RETURN NEXT;
            ELSE
                UPDATE public.outbox_events
                SET status = 'failed', error_message = 'create_gl_from_payroll returned false',
                    retry_count = retry_count + 1
                WHERE id = v_event.id;

                event_id := v_event.id;
                event_type := v_event.event_type;
                status := 'failed';
                error_message := 'create_gl_from_payroll returned false';
                RETURN NEXT;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_error := SQLERRM;
            UPDATE public.outbox_events
            SET status = 'failed', error_message = v_error,
                retry_count = retry_count + 1
            WHERE id = v_event.id;

            event_id := v_event.id;
            event_type := v_event.event_type;
            status := 'failed';
            error_message := v_error;
            RETURN NEXT;
        END;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3. TRIGGER: Auto-process on payroll_approved insert
-- ============================================================
CREATE OR REPLACE FUNCTION public.on_payroll_outbox_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process hr.payroll_approved events
    IF NEW.aggregate_type = 'hr_payroll' AND NEW.event_type = 'hr.payroll_approved' THEN
        -- Attempt immediate processing
        BEGIN
            PERFORM public.create_gl_from_payroll(
                NEW.aggregate_id,
                NEW.profession_id
            );
            -- Mark as published immediately
            NEW.status := 'published';
            NEW.published_at := NOW();
        EXCEPTION WHEN OTHERS THEN
            -- Keep as pending for batch processing
            NEW.error_message := SQLERRM;
        END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_payroll_outbox_auto_process ON public.outbox_events;
CREATE TRIGGER trg_payroll_outbox_auto_process
    BEFORE INSERT ON public.outbox_events
    FOR EACH ROW
    WHEN (NEW.aggregate_type = 'hr_payroll')
    EXECUTE FUNCTION public.on_payroll_outbox_insert();

-- ============================================================
-- 4. SEED missing payroll chart of accounts for professions
-- ============================================================
-- Ensure 2120 (salary payable) and 5214 (diligence allowance) exist
-- for every profession that already has default accounts.
INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order)
SELECT DISTINCT
    c.profession_id,
    '2120',
    'เงินเดือนค้างจ่าย',
    'Salary Payable',
    2,
    true,
    210
FROM public.chart_of_accounts c
WHERE c.is_default = true
  AND NOT EXISTS (
      SELECT 1 FROM public.chart_of_accounts x
      WHERE x.profession_id = c.profession_id AND x.account_code = '2120'
  )
ON CONFLICT (profession_id, account_code) DO NOTHING;

INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order)
SELECT DISTINCT
    c.profession_id,
    '5214',
    'เบี้ยขยัน / เงินพิเศษ',
    'Diligence Allowance',
    5,
    true,
    506
FROM public.chart_of_accounts c
WHERE c.is_default = true
  AND NOT EXISTS (
      SELECT 1 FROM public.chart_of_accounts x
      WHERE x.profession_id = c.profession_id AND x.account_code = '5214'
  )
ON CONFLICT (profession_id, account_code) DO NOTHING;

-- Ensure a social security payable liability account exists
INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order)
SELECT DISTINCT
    c.profession_id,
    '2130',
    'เงินสมทบประกันสังคมค้างจ่าย',
    'Social Security Payable',
    2,
    true,
    220
FROM public.chart_of_accounts c
WHERE c.is_default = true
  AND NOT EXISTS (
      SELECT 1 FROM public.chart_of_accounts x
      WHERE x.profession_id = c.profession_id
        AND x.account_type = 2
        AND x.account_name LIKE '%ประกันสังคมค้างจ่าย%'
  )
ON CONFLICT (profession_id, account_code) DO NOTHING;
