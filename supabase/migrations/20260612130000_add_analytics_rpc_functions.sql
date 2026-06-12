-- Migration: Analytics RPC Functions
-- Date: 2026-06-12
-- Prerequisites: Phase 3 analytics tables (projection_checkpoints, dashboard_snapshots, kpi_aggregations)

-- ============================================================
-- 1. UPSERT DASHBOARD SNAPSHOT
-- ============================================================
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

-- ============================================================
-- 2. UPSERT KPI AGGREGATION
-- ============================================================
CREATE OR REPLACE FUNCTION upsert_kpi_aggregation(
    p_profession_id UUID,
    p_kpi_name TEXT,
    p_kpi_category TEXT,
    p_period_start DATE,
    p_period_end DATE,
    p_value DECIMAL(12,2),
    p_target_value DECIMAL(12,2) DEFAULT NULL,
    p_unit TEXT DEFAULT 'count',
    p_is_better_higher BOOLEAN DEFAULT true
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.kpi_aggregations (
        profession_id, kpi_name, kpi_category,
        period_start, period_end, value,
        target_value, unit, is_better_higher
    )
    VALUES (
        p_profession_id, p_kpi_name, p_kpi_category,
        p_period_start, p_period_end, p_value,
        p_target_value, p_unit, p_is_better_higher
    )
    ON CONFLICT (profession_id, kpi_name, period_start, period_end)
    DO UPDATE SET
        value = EXCLUDED.value,
        target_value = COALESCE(EXCLUDED.target_value, public.kpi_aggregations.target_value),
        unit = EXCLUDED.unit,
        is_better_higher = EXCLUDED.is_better_higher,
        created_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3. ADVANCE PROJECTION CHECKPOINT
-- ============================================================
CREATE OR REPLACE FUNCTION advance_projection_checkpoint(
    p_profession_id UUID,
    p_projection_name TEXT,
    p_last_event_id UUID,
    p_last_event_seq BIGINT,
    p_state_snapshot JSONB DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.projection_checkpoints (
        profession_id, projection_name,
        last_event_id, last_event_seq, state_snapshot
    )
    VALUES (
        p_profession_id, p_projection_name,
        p_last_event_id, p_last_event_seq, p_state_snapshot
    )
    ON CONFLICT (profession_id, projection_name)
    DO UPDATE SET
        last_event_id = EXCLUDED.last_event_id,
        last_event_seq = EXCLUDED.last_event_seq,
        state_snapshot = EXCLUDED.state_snapshot,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 4. GENERATE DAILY SNAPSHOT (auto-calculate from orders)
-- ============================================================
CREATE OR REPLACE FUNCTION generate_daily_snapshot(p_profession_id UUID)
RETURNS UUID AS $$
DECLARE
    v_revenue DECIMAL(12,2);
    v_order_count INTEGER;
    v_avg_order_value DECIMAL(12,2);
    v_customer_count INTEGER;
    v_id UUID;
BEGIN
    -- Revenue from paid orders today
    SELECT COALESCE(SUM(grand_total), 0), COUNT(*)
    INTO v_revenue, v_order_count
    FROM public.orders
    WHERE profession_id = p_profession_id
      AND status = 'paid'
      AND DATE(created_at) = CURRENT_DATE;

    v_avg_order_value := CASE WHEN v_order_count > 0 THEN v_revenue / v_order_count ELSE 0 END;

    -- Unique customers today
    SELECT COUNT(DISTINCT customer_id)
    INTO v_customer_count
    FROM public.orders
    WHERE profession_id = p_profession_id
      AND DATE(created_at) = CURRENT_DATE;

    INSERT INTO public.dashboard_snapshots (
        profession_id, snapshot_date, snapshot_type, metrics
    )
    VALUES (
        p_profession_id,
        CURRENT_DATE,
        'daily',
        jsonb_build_object(
            'revenue', v_revenue,
            'order_count', v_order_count,
            'avg_order_value', v_avg_order_value,
            'customer_count', v_customer_count
        )
    )
    ON CONFLICT (profession_id, snapshot_date, snapshot_type)
    DO UPDATE SET metrics = EXCLUDED.metrics, created_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. GET SNAPSHOT COMPARISON (today vs yesterday)
-- ============================================================
CREATE OR REPLACE FUNCTION get_snapshot_comparison(
    p_profession_id UUID,
    p_snapshot_type TEXT DEFAULT 'daily'
)
RETURNS JSONB AS $$
DECLARE
    v_current JSONB;
    v_previous JSONB;
BEGIN
    SELECT metrics INTO v_current
    FROM public.dashboard_snapshots
    WHERE profession_id = p_profession_id AND snapshot_type = p_snapshot_type
    ORDER BY snapshot_date DESC
    LIMIT 1;

    SELECT metrics INTO v_previous
    FROM public.dashboard_snapshots
    WHERE profession_id = p_profession_id AND snapshot_type = p_snapshot_type
    ORDER BY snapshot_date DESC
    OFFSET 1 LIMIT 1;

    RETURN jsonb_build_object(
        'current', COALESCE(v_current, '{}'),
        'previous', COALESCE(v_previous, '{}')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
