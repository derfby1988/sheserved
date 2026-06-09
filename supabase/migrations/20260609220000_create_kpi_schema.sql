-- Migration: KPI Dashboard Schema (Phase 1 — Revenue Metric)
-- Tables: kpi_targets, kpi_actuals, kpi_alert_thresholds, kpi_refresh_log
-- Function: refresh_kpi_actuals()
-- Seed: default alert thresholds

-- 0. Ensure updated_at trigger function exists
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1. KPI TARGETS
CREATE TABLE IF NOT EXISTS public.kpi_targets (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  branch_id     UUID REFERENCES public.organization_branches(id) ON DELETE CASCADE,
  employee_id   UUID REFERENCES public.employees(id) ON DELETE CASCADE,
  target_type   TEXT NOT NULL
    CHECK (target_type IN ('revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover')),
  target_amount DECIMAL(15,2) NOT NULL CHECK (target_amount >= 0),
  period_type   TEXT NOT NULL
    CHECK (period_type IN ('daily','weekly','monthly','quarterly','yearly')),
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  created_by    UUID,
  updated_by    UUID,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT check_date_range CHECK (end_date >= start_date),
  CONSTRAINT check_scope CHECK (
    (branch_id IS NULL AND employee_id IS NULL) OR
    (branch_id IS NOT NULL AND employee_id IS NULL) OR
    (employee_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_kpi_targets_lookup
  ON public.kpi_targets(profession_id, branch_id, target_type, period_type, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_kpi_targets_branch ON public.kpi_targets(branch_id);
CREATE INDEX IF NOT EXISTS idx_kpi_targets_employee ON public.kpi_targets(employee_id);

CREATE TRIGGER trg_kpi_targets_updated_at BEFORE UPDATE ON public.kpi_targets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. KPI ACTUALS (Read Model)
CREATE TABLE IF NOT EXISTS public.kpi_actuals (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id    UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  branch_id        UUID REFERENCES public.organization_branches(id) ON DELETE CASCADE,
  employee_id      UUID REFERENCES public.employees(id) ON DELETE CASCADE,
  target_type      TEXT NOT NULL
    CHECK (target_type IN ('revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover')),
  period_type      TEXT NOT NULL
    CHECK (period_type IN ('daily','weekly','monthly','quarterly','yearly')),
  period_start     DATE NOT NULL,
  period_end       DATE NOT NULL,
  actual_amount    DECIMAL(15,2) NOT NULL DEFAULT 0,
  target_amount    DECIMAL(15,2) NOT NULL DEFAULT 0,
  achievement_rate DECIMAL(5,2) GENERATED ALWAYS AS (
    CASE WHEN target_amount > 0 THEN (actual_amount / target_amount * 100) ELSE 0 END
  ) STORED,
  data_source      TEXT NOT NULL DEFAULT 'orders'
    CHECK (data_source IN ('orders','journal_entries','appointments','consultations','manual')),
  refresh_count    INTEGER NOT NULL DEFAULT 1,
  last_refresh_at  TIMESTAMPTZ DEFAULT now(),
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, employee_id, target_type, period_type, period_start)
);

CREATE INDEX IF NOT EXISTS idx_kpi_actuals_lookup
  ON public.kpi_actuals(profession_id, branch_id, target_type, period_type, period_start)
  WHERE last_refresh_at > now() - interval '90 days';
CREATE INDEX IF NOT EXISTS idx_kpi_actuals_achievement
  ON public.kpi_actuals(profession_id, achievement_rate, target_type)
  WHERE target_amount > 0;
CREATE INDEX IF NOT EXISTS idx_kpi_actuals_branch ON public.kpi_actuals(branch_id);
CREATE INDEX IF NOT EXISTS idx_kpi_actuals_employee ON public.kpi_actuals(employee_id);

CREATE TRIGGER trg_kpi_actuals_updated_at BEFORE UPDATE ON public.kpi_actuals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3. KPI ALERT THRESHOLDS
CREATE TABLE IF NOT EXISTS public.kpi_alert_thresholds (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id          UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  target_type            TEXT NOT NULL
    CHECK (target_type IN ('revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover')),
  warning_threshold_pct  DECIMAL(5,2) NOT NULL DEFAULT 80.00,
  critical_threshold_pct DECIMAL(5,2) NOT NULL DEFAULT 60.00,
  alert_enabled          BOOLEAN NOT NULL DEFAULT true,
  notify_roles           TEXT[] NOT NULL DEFAULT ARRAY['owner','manager'],
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ DEFAULT now(),
  updated_at             TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, target_type)
);

CREATE INDEX IF NOT EXISTS idx_kpi_alert_thresholds
  ON public.kpi_alert_thresholds(profession_id, target_type);

CREATE TRIGGER trg_kpi_alert_thresholds_updated_at BEFORE UPDATE ON public.kpi_alert_thresholds
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. KPI REFRESH LOG
CREATE TABLE IF NOT EXISTS public.kpi_refresh_log (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  refresh_type      TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (refresh_type IN ('scheduled','manual','triggered')),
  target_type       TEXT
    CHECK (target_type IN ('revenue','net_profit','gross_profit','appointments','consultations','inventory_turnover')),
  period_type       TEXT
    CHECK (period_type IN ('daily','weekly','monthly','quarterly','yearly')),
  records_processed INTEGER NOT NULL DEFAULT 0,
  records_inserted  INTEGER NOT NULL DEFAULT 0,
  records_updated   INTEGER NOT NULL DEFAULT 0,
  started_at        TIMESTAMPTZ NOT NULL,
  completed_at      TIMESTAMPTZ,
  error_message     TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_kpi_refresh_log_recent
  ON public.kpi_refresh_log(profession_id, refresh_type, started_at DESC)
  WHERE started_at > now() - interval '7 days';

-- 5. REFRESH FUNCTION (Revenue — Phase 1)
CREATE OR REPLACE FUNCTION refresh_kpi_actuals(
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

  RETURN QUERY SELECT v_inserted, v_updated;
END;
$$ LANGUAGE plpgsql;

-- 6. SEED: Default alert thresholds per profession (optional — run manually or via app)
-- Uncomment and run after professions exist:
-- INSERT INTO public.kpi_alert_thresholds (profession_id, target_type)
-- SELECT id, 'revenue' FROM public.professions WHERE uses_pos_system = true
-- ON CONFLICT (profession_id, target_type) DO NOTHING;

-- 7. RLS (Enable but allow all — controlled at Application Layer per auth guidelines)
ALTER TABLE public.kpi_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kpi_actuals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kpi_alert_thresholds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kpi_refresh_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "kpi_targets_select" ON public.kpi_targets FOR SELECT USING (true);
CREATE POLICY "kpi_targets_modify" ON public.kpi_targets FOR ALL USING (true);
CREATE POLICY "kpi_actuals_select" ON public.kpi_actuals FOR SELECT USING (true);
CREATE POLICY "kpi_actuals_modify" ON public.kpi_actuals FOR ALL USING (true);
CREATE POLICY "kpi_alert_select" ON public.kpi_alert_thresholds FOR SELECT USING (true);
CREATE POLICY "kpi_alert_modify" ON public.kpi_alert_thresholds FOR ALL USING (true);
CREATE POLICY "kpi_log_select" ON public.kpi_refresh_log FOR SELECT USING (true);
CREATE POLICY "kpi_log_modify" ON public.kpi_refresh_log FOR ALL USING (true);
