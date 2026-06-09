-- Migration: Employees Table (Prerequisite for KPI Phase 2 Individual Quota)
-- Links platform users (public.users) to profession employees
-- Referenced by: kpi_targets.employee_id, kpi_actuals.employee_id

CREATE TABLE IF NOT EXISTS public.employees (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  branch_id     UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,

  employee_code TEXT,
  full_name     TEXT NOT NULL,
  position      TEXT,
  department    TEXT,
  phone         TEXT,
  email         TEXT,

  is_active     BOOLEAN DEFAULT true,
  hired_at      DATE,

  created_by    UUID,
  updated_by    UUID,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),

  UNIQUE (profession_id, user_id)
);

-- Indexes for KPI join performance (orders.served_by -> employees.user_id)
CREATE INDEX IF NOT EXISTS idx_employees_profession ON public.employees(profession_id, is_active)
  WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS idx_employees_branch ON public.employees(branch_id);

-- Trigger
CREATE TRIGGER trg_employees_updated_at BEFORE UPDATE ON public.employees
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS (Enable but allow all — controlled at Application Layer)
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "employees_select" ON public.employees FOR SELECT USING (true);
CREATE POLICY "employees_modify" ON public.employees FOR ALL USING (true);
