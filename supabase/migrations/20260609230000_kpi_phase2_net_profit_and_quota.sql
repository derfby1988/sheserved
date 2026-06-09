-- Migration: KPI Dashboard Phase 2 — Net Profit & Individual Employee Quota
-- Prerequisites: employees table (20260609215000), accounting schema (20260609180000), orders table (POS)
-- Extends refresh_kpi_actuals() for net_profit; adds refresh_kpi_employee_actuals() for individual quota

-- ============================================
-- 1. EXTEND refresh_kpi_actuals() — support net_profit
-- ============================================
DROP FUNCTION IF EXISTS refresh_kpi_actuals(UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION refresh_kpi_actuals(
  p_profession_id UUID,
  p_period_type TEXT DEFAULT 'daily',
  p_lookback_days INTEGER DEFAULT 30,
  p_target_type TEXT DEFAULT 'revenue'
)
RETURNS TABLE (inserted INTEGER, updated INTEGER) AS $$
DECLARE
  v_inserted INTEGER := 0;
  v_updated INTEGER := 0;
  v_now TIMESTAMPTZ := now();
  v_start_date DATE;
BEGIN
  v_start_date := CURRENT_DATE - p_lookback_days;

  IF p_target_type = 'net_profit' THEN
    -- Net Profit from posted journal entries
    -- Revenue (account_type=4) credits minus Expenses (account_type=5) debits
    WITH computed AS (
      SELECT
        je.profession_id,
        je.branch_id,
        NULL::UUID AS employee_id,
        'net_profit'::TEXT AS target_type,
        p_period_type AS period_type,
        CASE p_period_type
          WHEN 'daily' THEN je.entry_date
          WHEN 'weekly' THEN DATE_TRUNC('week', je.entry_date)::DATE
          WHEN 'monthly' THEN DATE_TRUNC('month', je.entry_date)::DATE
          WHEN 'quarterly' THEN DATE_TRUNC('quarter', je.entry_date)::DATE
          WHEN 'yearly' THEN DATE_TRUNC('year', je.entry_date)::DATE
        END AS period_start,
        CASE p_period_type
          WHEN 'daily' THEN je.entry_date
          WHEN 'weekly' THEN (DATE_TRUNC('week', je.entry_date) + INTERVAL '6 days')::DATE
          WHEN 'monthly' THEN (DATE_TRUNC('month', je.entry_date) + INTERVAL '1 month - 1 day')::DATE
          WHEN 'quarterly' THEN (DATE_TRUNC('quarter', je.entry_date) + INTERVAL '3 months - 1 day')::DATE
          WHEN 'yearly' THEN (DATE_TRUNC('year', je.entry_date) + INTERVAL '1 year - 1 day')::DATE
        END AS period_end,
        COALESCE(SUM(CASE WHEN coa.account_type = 4 THEN jel.credit_amount ELSE 0 END), 0)
          - COALESCE(SUM(CASE WHEN coa.account_type = 5 THEN jel.debit_amount ELSE 0 END), 0)
          AS actual_amount
      FROM public.journal_entries je
      JOIN public.journal_entry_lines jel ON jel.journal_entry_id = je.id
      JOIN public.chart_of_accounts coa ON coa.id = jel.account_id
      WHERE je.profession_id = p_profession_id
        AND je.status = 'posted'
        AND coa.account_type IN (4, 5)
        AND je.entry_date >= v_start_date
        AND je.entry_date <= CURRENT_DATE
      GROUP BY je.profession_id, je.branch_id, period_start, period_end
    ),
    upserted AS (
      INSERT INTO public.kpi_actuals (
        profession_id, branch_id, employee_id,
        target_type, period_type, period_start, period_end,
        actual_amount, target_amount, data_source,
        refresh_count, last_refresh_at
      )
      SELECT
        c.profession_id, c.branch_id, c.employee_id,
        c.target_type, c.period_type, c.period_start, c.period_end,
        c.actual_amount,
        COALESCE(kt.target_amount, 0),
        'journal_entries', 1, v_now
      FROM computed c
      LEFT JOIN public.kpi_targets kt ON kt.profession_id = c.profession_id
        AND kt.branch_id IS NOT DISTINCT FROM c.branch_id
        AND kt.employee_id IS NOT DISTINCT FROM c.employee_id
        AND kt.target_type = c.target_type
        AND kt.period_type = c.period_type
        AND kt.start_date <= c.period_end
        AND kt.end_date >= c.period_start
      ON CONFLICT (profession_id, branch_id, employee_id, target_type, period_type, period_start)
      DO UPDATE SET
        actual_amount = EXCLUDED.actual_amount,
        target_amount = EXCLUDED.target_amount,
        data_source = 'journal_entries',
        refresh_count = public.kpi_actuals.refresh_count + 1,
        last_refresh_at = v_now,
        updated_at = v_now
      RETURNING (xmax = 0) AS is_insert
    )
    SELECT
      COUNT(*) FILTER (WHERE is_insert) INTO v_inserted,
      COUNT(*) FILTER (WHERE NOT is_insert) INTO v_updated
    FROM upserted;

  ELSE
    -- Default: revenue from orders (Phase 1 logic preserved)
    WITH computed AS (
      SELECT
        o.profession_id,
        o.branch_id,
        NULL::UUID AS employee_id,
        'revenue'::TEXT AS target_type,
        p_period_type AS period_type,
        CASE p_period_type
          WHEN 'daily' THEN o.created_at::DATE
          WHEN 'weekly' THEN DATE_TRUNC('week', o.created_at)::DATE
          WHEN 'monthly' THEN DATE_TRUNC('month', o.created_at)::DATE
          WHEN 'quarterly' THEN DATE_TRUNC('quarter', o.created_at)::DATE
          WHEN 'yearly' THEN DATE_TRUNC('year', o.created_at)::DATE
        END AS period_start,
        CASE p_period_type
          WHEN 'daily' THEN o.created_at::DATE
          WHEN 'weekly' THEN (DATE_TRUNC('week', o.created_at) + INTERVAL '6 days')::DATE
          WHEN 'monthly' THEN (DATE_TRUNC('month', o.created_at) + INTERVAL '1 month - 1 day')::DATE
          WHEN 'quarterly' THEN (DATE_TRUNC('quarter', o.created_at) + INTERVAL '3 months - 1 day')::DATE
          WHEN 'yearly' THEN (DATE_TRUNC('year', o.created_at) + INTERVAL '1 year - 1 day')::DATE
        END AS period_end,
        COALESCE(SUM(o.final_amount), 0) AS actual_amount
      FROM public.orders o
      WHERE o.profession_id = p_profession_id
        AND o.status IN ('paid', 'completed')
        AND o.created_at >= v_start_date
      GROUP BY o.profession_id, o.branch_id, period_start, period_end
    ),
    upserted AS (
      INSERT INTO public.kpi_actuals (
        profession_id, branch_id, employee_id,
        target_type, period_type, period_start, period_end,
        actual_amount, target_amount, data_source,
        refresh_count, last_refresh_at
      )
      SELECT
        c.profession_id, c.branch_id, c.employee_id,
        c.target_type, c.period_type, c.period_start, c.period_end,
        c.actual_amount,
        COALESCE(kt.target_amount, 0),
        'orders', 1, v_now
      FROM computed c
      LEFT JOIN public.kpi_targets kt ON kt.profession_id = c.profession_id
        AND kt.branch_id IS NOT DISTINCT FROM c.branch_id
        AND kt.employee_id IS NOT DISTINCT FROM c.employee_id
        AND kt.target_type = c.target_type
        AND kt.period_type = c.period_type
        AND kt.start_date <= c.period_end
        AND kt.end_date >= c.period_start
      ON CONFLICT (profession_id, branch_id, employee_id, target_type, period_type, period_start)
      DO UPDATE SET
        actual_amount = EXCLUDED.actual_amount,
        target_amount = EXCLUDED.target_amount,
        data_source = 'orders',
        refresh_count = public.kpi_actuals.refresh_count + 1,
        last_refresh_at = v_now,
        updated_at = v_now
      RETURNING (xmax = 0) AS is_insert
    )
    SELECT
      COUNT(*) FILTER (WHERE is_insert) INTO v_inserted,
      COUNT(*) FILTER (WHERE NOT is_insert) INTO v_updated
    FROM upserted;
  END IF;

  RETURN QUERY SELECT v_inserted, v_updated;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 2. Individual Employee Revenue (Quota)
-- ============================================
CREATE OR REPLACE FUNCTION refresh_kpi_employee_actuals(
  p_profession_id UUID,
  p_period_type TEXT DEFAULT 'daily',
  p_lookback_days INTEGER DEFAULT 30
)
RETURNS TABLE (inserted INTEGER, updated INTEGER) AS $$
DECLARE
  v_inserted INTEGER := 0;
  v_updated INTEGER := 0;
  v_now TIMESTAMPTZ := now();
  v_start_date DATE;
BEGIN
  v_start_date := CURRENT_DATE - p_lookback_days;

  WITH computed AS (
    SELECT
      o.profession_id,
      o.branch_id,
      e.id AS employee_id,
      'revenue'::TEXT AS target_type,
      p_period_type AS period_type,
      CASE p_period_type
        WHEN 'daily' THEN o.created_at::DATE
        WHEN 'weekly' THEN DATE_TRUNC('week', o.created_at)::DATE
        WHEN 'monthly' THEN DATE_TRUNC('month', o.created_at)::DATE
        WHEN 'quarterly' THEN DATE_TRUNC('quarter', o.created_at)::DATE
        WHEN 'yearly' THEN DATE_TRUNC('year', o.created_at)::DATE
      END AS period_start,
      CASE p_period_type
        WHEN 'daily' THEN o.created_at::DATE
        WHEN 'weekly' THEN (DATE_TRUNC('week', o.created_at) + INTERVAL '6 days')::DATE
        WHEN 'monthly' THEN (DATE_TRUNC('month', o.created_at) + INTERVAL '1 month - 1 day')::DATE
        WHEN 'quarterly' THEN (DATE_TRUNC('quarter', o.created_at) + INTERVAL '3 months - 1 day')::DATE
        WHEN 'yearly' THEN (DATE_TRUNC('year', o.created_at) + INTERVAL '1 year - 1 day')::DATE
      END AS period_end,
      COALESCE(SUM(o.final_amount), 0) AS actual_amount
    FROM public.orders o
    JOIN public.employees e ON e.user_id = o.served_by AND e.profession_id = o.profession_id
    WHERE o.profession_id = p_profession_id
      AND o.status IN ('paid', 'completed')
      AND o.served_by IS NOT NULL
      AND o.created_at >= v_start_date
    GROUP BY o.profession_id, o.branch_id, e.id, period_start, period_end
  ),
  upserted AS (
    INSERT INTO public.kpi_actuals (
      profession_id, branch_id, employee_id,
      target_type, period_type, period_start, period_end,
      actual_amount, target_amount, data_source,
      refresh_count, last_refresh_at
    )
    SELECT
      c.profession_id, c.branch_id, c.employee_id,
      c.target_type, c.period_type, c.period_start, c.period_end,
      c.actual_amount,
      COALESCE(kt.target_amount, 0),
      'orders', 1, v_now
    FROM computed c
    LEFT JOIN public.kpi_targets kt ON kt.profession_id = c.profession_id
      AND kt.branch_id IS NOT DISTINCT FROM c.branch_id
      AND kt.employee_id IS NOT DISTINCT FROM c.employee_id
      AND kt.target_type = c.target_type
      AND kt.period_type = c.period_type
      AND kt.start_date <= c.period_end
      AND kt.end_date >= c.period_start
    ON CONFLICT (profession_id, branch_id, employee_id, target_type, period_type, period_start)
    DO UPDATE SET
      actual_amount = EXCLUDED.actual_amount,
      target_amount = EXCLUDED.target_amount,
      data_source = 'orders',
      refresh_count = public.kpi_actuals.refresh_count + 1,
      last_refresh_at = v_now,
      updated_at = v_now
    RETURNING (xmax = 0) AS is_insert
  )
  SELECT
    COUNT(*) FILTER (WHERE is_insert) INTO v_inserted,
    COUNT(*) FILTER (WHERE NOT is_insert) INTO v_updated
  FROM upserted;

  RETURN QUERY SELECT v_inserted, v_updated;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 3. Net Profit Alert Threshold (seed for existing professions)
-- ============================================
INSERT INTO public.kpi_alert_thresholds (profession_id, target_type)
SELECT p.id, 'net_profit'
FROM public.professions p
WHERE p.uses_pos_system = true
  AND NOT EXISTS (
    SELECT 1 FROM public.kpi_alert_thresholds t
    WHERE t.profession_id = p.id AND t.target_type = 'net_profit'
  )
ON CONFLICT (profession_id, target_type) DO NOTHING;
