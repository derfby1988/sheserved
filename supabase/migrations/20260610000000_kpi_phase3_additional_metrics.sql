-- Migration: KPI Dashboard Phase 3 — Additional Metrics
-- Metrics: consultations, appointments, gross_profit, inventory_turnover
-- Prerequisites:
--   - consultation_requests table (for consultations metric)
--   - clinic_appointments table (for appointments metric) — NOT YET AVAILABLE
--   - order_items with cost_price (for gross_profit) — NOT YET AVAILABLE
--   - inventory_items table (for inventory_turnover) — NOT YET AVAILABLE

-- ============================================
-- 1. EXTEND refresh_kpi_actuals() — consultations
-- ============================================
DROP FUNCTION IF EXISTS refresh_kpi_actuals(UUID, TEXT, INTEGER, TEXT);

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

  -- =====================================================
  -- A. CONSULTATIONS (COUNT from consultation_requests)
  -- =====================================================
  IF p_target_type = 'consultations' THEN
    WITH computed AS (
      SELECT
        p_profession_id AS profession_id,
        NULL::UUID AS branch_id,
        NULL::UUID AS employee_id,
        'consultations'::TEXT AS target_type,
        p_period_type AS period_type,
        CASE p_period_type
          WHEN 'daily' THEN cr.created_at::DATE
          WHEN 'weekly' THEN DATE_TRUNC('week', cr.created_at)::DATE
          WHEN 'monthly' THEN DATE_TRUNC('month', cr.created_at)::DATE
          WHEN 'quarterly' THEN DATE_TRUNC('quarter', cr.created_at)::DATE
          WHEN 'yearly' THEN DATE_TRUNC('year', cr.created_at)::DATE
        END AS period_start,
        CASE p_period_type
          WHEN 'daily' THEN cr.created_at::DATE
          WHEN 'weekly' THEN (DATE_TRUNC('week', cr.created_at) + INTERVAL '6 days')::DATE
          WHEN 'monthly' THEN (DATE_TRUNC('month', cr.created_at) + INTERVAL '1 month - 1 day')::DATE
          WHEN 'quarterly' THEN (DATE_TRUNC('quarter', cr.created_at) + INTERVAL '3 months - 1 day')::DATE
          WHEN 'yearly' THEN (DATE_TRUNC('year', cr.created_at) + INTERVAL '1 year - 1 day')::DATE
        END AS period_end,
        COUNT(*)::DECIMAL AS actual_amount
      FROM public.consultation_requests cr
      WHERE cr.status IN ('completed', 'assigned')
        AND cr.created_at >= v_start_date
      GROUP BY period_start, period_end
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
        'consultations', 1, v_now
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
        data_source = 'consultations',
        refresh_count = public.kpi_actuals.refresh_count + 1,
        last_refresh_at = v_now,
        updated_at = v_now
      RETURNING (xmax = 0) AS is_insert
    )
    SELECT
      COUNT(*) FILTER (WHERE is_insert) INTO v_inserted,
      COUNT(*) FILTER (WHERE NOT is_insert) INTO v_updated
    FROM upserted;

  -- =====================================================
  -- B. NET PROFIT (from journal_entries — Phase 2)
  -- =====================================================
  ELSIF p_target_type = 'net_profit' THEN
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

  -- =====================================================
  -- C. REVENUE (from orders — Phase 1)
  -- =====================================================
  ELSE
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
-- 2. refresh_kpi_appointments() — ENABLED
-- ============================================
-- clinic_appointments table now available (20260610010000_create_pos_core_schema.sql)
CREATE OR REPLACE FUNCTION refresh_kpi_appointments(
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
      ca.profession_id,
      NULL::UUID AS branch_id,
      NULL::UUID AS employee_id,
      'appointments'::TEXT AS target_type,
      p_period_type AS period_type,
      CASE p_period_type
        WHEN 'daily' THEN ca.scheduled_at::DATE
        WHEN 'weekly' THEN DATE_TRUNC('week', ca.scheduled_at)::DATE
        WHEN 'monthly' THEN DATE_TRUNC('month', ca.scheduled_at)::DATE
        WHEN 'quarterly' THEN DATE_TRUNC('quarter', ca.scheduled_at)::DATE
        WHEN 'yearly' THEN DATE_TRUNC('year', ca.scheduled_at)::DATE
      END AS period_start,
      CASE p_period_type
        WHEN 'daily' THEN ca.scheduled_at::DATE
        WHEN 'weekly' THEN (DATE_TRUNC('week', ca.scheduled_at) + INTERVAL '6 days')::DATE
        WHEN 'monthly' THEN (DATE_TRUNC('month', ca.scheduled_at) + INTERVAL '1 month - 1 day')::DATE
        WHEN 'quarterly' THEN (DATE_TRUNC('quarter', ca.scheduled_at) + INTERVAL '3 months - 1 day')::DATE
        WHEN 'yearly' THEN (DATE_TRUNC('year', ca.scheduled_at) + INTERVAL '1 year - 1 day')::DATE
      END AS period_end,
      COUNT(*)::DECIMAL AS actual_amount
    FROM public.clinic_appointments ca
    WHERE ca.profession_id = p_profession_id
      AND ca.status = 'completed'
      AND ca.scheduled_at >= v_start_date
    GROUP BY ca.profession_id, period_start, period_end
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
      'appointments', 1, v_now
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
      data_source = 'appointments',
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
-- 3. PLACEHOLDER: refresh_kpi_gross_profit()
-- ============================================
-- PREREQUISITE: order_items must have cost_price column
-- OR inventory_items table with cost tracking
-- Gross Profit = Revenue - COGS (Cost of Goods Sold)
-- COGS can be calculated as: SUM(order_items.quantity * products.cost_price)
-- Uncomment and implement when inventory/cost tracking is available:

/*
CREATE OR REPLACE FUNCTION refresh_kpi_gross_profit(
  p_profession_id UUID,
  p_period_type TEXT DEFAULT 'daily',
  p_lookback_days INTEGER DEFAULT 30
)
RETURNS TABLE (inserted INTEGER, updated INTEGER) AS $$
-- Implementation requires:
-- 1. order_items.cost_price column, OR
-- 2. products table with cost_price, OR
-- 3. inventory_movements table for COGS calculation
--
-- Formula:
--   gross_profit = SUM(orders.final_amount)
--                  - SUM(order_items.quantity * COALESCE(products.cost_price, 0))
-- WHERE orders.status IN ('paid','completed')
END;
$$ LANGUAGE plpgsql;
*/

-- ============================================
-- 4. PLACEHOLDER: refresh_kpi_inventory_turnover()
-- ============================================
-- PREREQUISITE: inventory_items and inventory_movements tables
-- Formula: Inventory Turnover = COGS / Average Inventory Value
-- Uncomment and implement when inventory system is available:

/*
CREATE OR REPLACE FUNCTION refresh_kpi_inventory_turnover(
  p_profession_id UUID,
  p_period_type TEXT DEFAULT 'monthly',
  p_lookback_days INTEGER DEFAULT 90
)
RETURNS TABLE (inserted INTEGER, updated INTEGER) AS $$
-- Implementation requires:
-- 1. inventory_items table (product stock levels)
-- 2. inventory_movements table (in/out transactions)
-- 3. COGS calculation from sales
--
-- Formula:
--   turnover = COGS / ((beginning_inventory + ending_inventory) / 2)
END;
$$ LANGUAGE plpgsql;
*/

-- ============================================
-- 5. Seed alert thresholds for consultations
-- ============================================
INSERT INTO public.kpi_alert_thresholds (profession_id, target_type)
SELECT p.id, 'consultations'
FROM public.professions p
WHERE p.uses_pos_system = true
  AND NOT EXISTS (
    SELECT 1 FROM public.kpi_alert_thresholds t
    WHERE t.profession_id = p.id AND t.target_type = 'consultations'
  )
ON CONFLICT (profession_id, target_type) DO NOTHING;

-- ============================================
-- 6. Seed alert thresholds for appointments
-- ============================================
INSERT INTO public.kpi_alert_thresholds (profession_id, target_type)
SELECT p.id, 'appointments'
FROM public.professions p
WHERE p.uses_pos_system = true
  AND NOT EXISTS (
    SELECT 1 FROM public.kpi_alert_thresholds t
    WHERE t.profession_id = p.id AND t.target_type = 'appointments'
  )
ON CONFLICT (profession_id, target_type) DO NOTHING;
