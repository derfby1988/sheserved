-- Migration: Add user_approver_settings for donation approver preferences
-- Created: 2026-06-24
-- Purpose: Store per-user approval toggles and radius for donation categories
-- NOTE: RLS is intentionally left disabled for now because the current Flutter
-- app does not set app.user_id for owner-scoped policies. This keeps the
-- existing login flow working while preventing the missing-table crash.

CREATE TABLE IF NOT EXISTS public.user_approver_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.donation_categories(id) ON DELETE CASCADE,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    radius_meters INTEGER NOT NULL DEFAULT 500 CHECK (radius_meters BETWEEN 500 AND 100000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT user_approver_settings_user_category_unique UNIQUE (user_id, category_id)
);

CREATE INDEX IF NOT EXISTS idx_user_approver_settings_user_id
    ON public.user_approver_settings(user_id);

CREATE INDEX IF NOT EXISTS idx_user_approver_settings_category_id
    ON public.user_approver_settings(category_id);

CREATE INDEX IF NOT EXISTS idx_user_approver_settings_user_category
    ON public.user_approver_settings(user_id, category_id);

DROP TRIGGER IF EXISTS trg_user_approver_settings_updated_at ON public.user_approver_settings;
CREATE TRIGGER trg_user_approver_settings_updated_at
    BEFORE UPDATE ON public.user_approver_settings
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
