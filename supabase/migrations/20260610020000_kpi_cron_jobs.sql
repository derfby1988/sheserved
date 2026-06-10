-- Migration: KPI Dashboard — Scheduled Refresh Jobs (pg_cron)
-- Prerequisites: kpi schema, refresh_kpi_actuals() function, refresh_kpi_employee_actuals(), refresh_kpi_appointments()
-- NOTE: pg_cron extension must be available on the database. Supabase/PostgreSQL 15+ supports this.

-- ============================================
-- 1. Enable pg_cron extension
-- ============================================
-- If running on Supabase, this may require enabling in the dashboard first.
-- For self-hosted or local dev with pg_cron installed:
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================
-- 2. Scheduled Jobs: KPI Actuals Refresh
-- ============================================
-- These jobs run the refresh functions for all active professions.
-- They are designed to be idempotent (safe to re-run).

-- Daily refresh at 00:15 (after midnight, when all orders/journals should be posted)
SELECT cron.schedule(
  'kpi-refresh-daily',
  '15 0 * * *',
  $$
    SELECT refresh_kpi_actuals(p.id, 'daily', 30)
    FROM public.professions p
    WHERE p.uses_pos_system = true;
  $$
);

-- Weekly refresh at 00:30 every Monday
SELECT cron.schedule(
  'kpi-refresh-weekly',
  '30 0 * * 1',
  $$
    SELECT refresh_kpi_actuals(p.id, 'weekly', 90)
    FROM public.professions p
    WHERE p.uses_pos_system = true;
  $$
);

-- Monthly refresh at 01:00 on the 1st of every month
SELECT cron.schedule(
  'kpi-refresh-monthly',
  '0 1 1 * *',
  $$
    SELECT refresh_kpi_actuals(p.id, 'monthly', 180)
    FROM public.professions p
    WHERE p.uses_pos_system = true;
  $$
);

-- ============================================
-- 3. Scheduled Jobs: Employee Quota Refresh
-- ============================================
-- Daily refresh for individual employee revenue quotas
SELECT cron.schedule(
  'kpi-employee-refresh-daily',
  '20 0 * * *',
  $$
    SELECT refresh_kpi_employee_actuals(p.id, 'daily', 30)
    FROM public.professions p
    WHERE p.uses_pos_system = true;
  $$
);

-- ============================================
-- 4. Scheduled Jobs: Appointments Count Refresh
-- ============================================
-- Daily refresh for completed appointments count
SELECT cron.schedule(
  'kpi-appointments-refresh-daily',
  '25 0 * * *',
  $$
    SELECT refresh_kpi_appointments(p.id, 'daily', 30)
    FROM public.professions p
    WHERE p.uses_pos_system = true;
  $$
);

-- ============================================
-- 5. Log the scheduled jobs in kpi_refresh_log
-- ============================================
INSERT INTO public.kpi_refresh_log (
  profession_id,
  refresh_type,
  target_type,
  period_type,
  records_processed,
  started_at,
  completed_at,
  error_message
)
SELECT
  p.id,
  'scheduled',
  'all',
  'daily',
  0,
  now(),
  now(),
  'Cron jobs initialized: kpi-refresh-daily, kpi-refresh-weekly, kpi-refresh-monthly, kpi-employee-refresh-daily, kpi-appointments-refresh-daily'
FROM public.professions p
WHERE p.uses_pos_system = true
ON CONFLICT DO NOTHING;
