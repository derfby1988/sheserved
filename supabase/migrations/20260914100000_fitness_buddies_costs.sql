-- Migration: Phase 9.1 — Group cost standards + session cost items
-- Date: 2026-09-14
-- Depends: 20260825130000_fitness_buddies_session_capacity.sql,
--          20260903110900_phase_13_0_fitness_public_views.sql
--
-- Two-level expense model per Match_Sport_PLAN.md "ระบบค่าใช้จ่าย 2 ระดับ":
--   Level 1: fitness_group_cost_standards — reusable group_fee / round_expense
--            templates managed from group create/edit.
--   Level 2: fitness_group_session_cost_items — per-session line items that
--            snapshot a standard or are custom (standard_id = NULL).
-- fitness_group_cost_obligations is intentionally NOT created (payment phase).
-- Idempotent, creates no retroactive cost rows, never mutates existing
-- migrations.

-- ===================================================================
-- 1. fitness_group_cost_standards
-- ===================================================================
CREATE TABLE IF NOT EXISTS public.fitness_group_cost_standards (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.fitness_groups(id) ON DELETE CASCADE,
  standard_type   VARCHAR(20) NOT NULL CHECK (standard_type IN ('group_fee','round_expense')),
  category        VARCHAR(20) NOT NULL CHECK (category IN ('membership','venue','equipment','coach','insurance','competition','uniform','other')),
  name            VARCHAR(100) NOT NULL,
  amount          NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
  billing_period  VARCHAR(12) CHECK (billing_period IN ('per_use','per_day','per_week','per_month','per_year','lifetime')),
  pricing_unit    VARCHAR(12) CHECK (pricing_unit IN ('flat','per_item','per_round','per_hour')),
  default_quantity NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (default_quantity > 0),
  payment_timing  VARCHAR(32) NOT NULL DEFAULT 'at_venue'
                  CHECK (payment_timing IN ('before_round_approval','before_group_join','at_venue')),
  currency        CHAR(3) NOT NULL DEFAULT 'THB',
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  -- Cross-field: group_fee uses billing_period (no pricing_unit) and must be
  -- membership; round_expense uses pricing_unit (no billing_period) and must
  -- be an expense category.
  CONSTRAINT fitness_cost_standards_type_fields CHECK (
    (
      standard_type = 'group_fee'
      AND category = 'membership'
      AND billing_period IS NOT NULL
      AND pricing_unit IS NULL
    )
    OR (
      standard_type = 'round_expense'
      AND category IN ('venue','equipment','coach','insurance','competition','uniform','other')
      AND pricing_unit IS NOT NULL
      AND billing_period IS NULL
    )
  )
);

-- ===================================================================
-- 2. fitness_group_session_cost_items
-- ===================================================================
CREATE TABLE IF NOT EXISTS public.fitness_group_session_cost_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID NOT NULL REFERENCES public.fitness_group_sessions(id) ON DELETE CASCADE,
  standard_id     UUID REFERENCES public.fitness_group_cost_standards(id) ON DELETE SET NULL,
  source_type     VARCHAR(10) NOT NULL CHECK (source_type IN ('standard','custom')),
  name            VARCHAR(100) NOT NULL,
  category        VARCHAR(20) NOT NULL CHECK (category IN ('venue','equipment','coach','insurance','competition','uniform','other')),
  pricing_unit    VARCHAR(12) NOT NULL CHECK (pricing_unit IN ('flat','per_item','per_round','per_hour')),
  unit_amount     NUMERIC(10,2) NOT NULL CHECK (unit_amount >= 0),
  quantity        NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  payment_timing  VARCHAR(32) NOT NULL
                  CHECK (payment_timing IN ('before_round_approval','before_group_join','at_venue')),
  currency        CHAR(3) NOT NULL DEFAULT 'THB',
  note            VARCHAR(200),
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  -- Cross-field: standard-sourced rows keep standard_id, custom rows must not.
  -- (Deleting a standard that is still referenced therefore fails instead of
  -- silently detaching — history is preserved, managers disable instead.)
  CONSTRAINT fitness_session_cost_items_source CHECK (
    (source_type = 'standard' AND standard_id IS NOT NULL)
    OR (source_type = 'custom' AND standard_id IS NULL)
  ),
  -- Quantity rules per pricing unit (defense layer; repository validates too).
  CONSTRAINT fitness_session_cost_items_quantity CHECK (
    (pricing_unit IN ('flat','per_round') AND quantity = 1)
    OR (pricing_unit = 'per_item' AND quantity = trunc(quantity))
    OR (pricing_unit = 'per_hour')
  )
);

-- ===================================================================
-- 3. updated_at trigger for standards
-- ===================================================================
CREATE OR REPLACE FUNCTION public.set_fitness_cost_standard_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fitness_cost_standards_updated_at
  ON public.fitness_group_cost_standards;
CREATE TRIGGER trg_fitness_cost_standards_updated_at
  BEFORE UPDATE ON public.fitness_group_cost_standards
  FOR EACH ROW EXECUTE FUNCTION public.set_fitness_cost_standard_updated_at();

-- ===================================================================
-- 4. Indexes (per plan)
-- ===================================================================
CREATE INDEX IF NOT EXISTS idx_fitness_group_cost_standards_group_active
  ON public.fitness_group_cost_standards(group_id, standard_type)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_fitness_session_cost_items_session
  ON public.fitness_group_session_cost_items(session_id, created_at);

CREATE INDEX IF NOT EXISTS idx_fitness_session_cost_items_standard
  ON public.fitness_group_session_cost_items(standard_id)
  WHERE standard_id IS NOT NULL;

-- ===================================================================
-- 5. RLS — Phase 1 compatibility: app layer enforces authorization
--    (same pattern as the other fitness_* tables; manager checks live in
--    FitnessBuddiesRepository._requireGroupManager)
-- ===================================================================
ALTER TABLE public.fitness_group_cost_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fitness_group_session_cost_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS fitness_group_cost_standards_all
  ON public.fitness_group_cost_standards;
CREATE POLICY fitness_group_cost_standards_all
  ON public.fitness_group_cost_standards
  FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS fitness_group_session_cost_items_all
  ON public.fitness_group_session_cost_items;
CREATE POLICY fitness_group_session_cost_items_all
  ON public.fitness_group_session_cost_items
  FOR ALL USING (true) WITH CHECK (true);

-- ===================================================================
-- 6. Public views (Phase 13.0 contract)
--    - fitness_group_fees_public: active group_fee standards only
--    - fitness_session_cost_items_public: line items of public sessions,
--      including a computed estimated_amount for display
--    - fitness_sessions_public: fix capacity to come from the session
--      (s.capacity), not the legacy fitness_groups.capacity
-- ===================================================================
CREATE OR REPLACE VIEW public.fitness_group_fees_public AS
SELECT
  c.id,
  c.group_id,
  c.name,
  c.amount,
  c.billing_period,
  c.payment_timing,
  c.currency
FROM public.fitness_group_cost_standards c
JOIN public.fitness_groups g ON g.id = c.group_id
WHERE c.standard_type = 'group_fee'
  AND c.is_active = true
  AND g.visibility = 'public';

CREATE OR REPLACE VIEW public.fitness_session_cost_items_public AS
SELECT
  i.id,
  i.session_id,
  s.group_id,
  i.name,
  i.category,
  i.pricing_unit,
  i.unit_amount,
  i.quantity,
  (i.unit_amount * i.quantity) AS estimated_amount,
  i.payment_timing,
  i.currency,
  i.note,
  i.created_at
FROM public.fitness_group_session_cost_items i
JOIN public.fitness_group_sessions s ON s.id = i.session_id
JOIN public.fitness_groups g ON g.id = s.group_id
WHERE g.visibility = 'public';

CREATE OR REPLACE VIEW public.fitness_sessions_public AS
SELECT
  s.id,
  s.group_id,
  s.starts_at,
  s.ends_at,
  s.capacity,
  s.place_name,
  s.lat,
  s.lng,
  s.note,
  COALESCE(confirmed.count, 0) AS confirmed_count,
  GREATEST(s.capacity - COALESCE(confirmed.count, 0), 0) AS available_count
FROM public.fitness_group_sessions s
JOIN public.fitness_groups g ON g.id = s.group_id
LEFT JOIN LATERAL (
  SELECT COUNT(*) AS count
  FROM public.fitness_group_bookings b
  WHERE b.session_id = s.id
    AND b.status = 'confirmed'
) confirmed ON true
WHERE g.visibility = 'public';

GRANT SELECT ON public.fitness_group_fees_public TO anon, authenticated;
GRANT SELECT ON public.fitness_session_cost_items_public TO anon, authenticated;
GRANT SELECT ON public.fitness_sessions_public TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
