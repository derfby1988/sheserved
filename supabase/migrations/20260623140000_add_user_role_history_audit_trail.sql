-- Migration: Add user_role_history audit trail table
-- Date: 2026-06-23
-- Purpose: Track all role changes for compliance and security auditing

-- ============================================================
-- 1. Audit Trail Table — user_role_history
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_role_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    old_role        TEXT,
    new_role        TEXT NOT NULL,
    changed_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    changed_at      TIMESTAMPTZ DEFAULT NOW(),
    reason          TEXT,
    source          TEXT DEFAULT 'admin_ui'  -- 'admin_ui', 'migration', 'api', 'system'
);

CREATE INDEX IF NOT EXISTS idx_user_role_history_user
    ON public.user_role_history(user_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_role_history_changed_by
    ON public.user_role_history(changed_by);

-- ============================================================
-- 2. Helper Function — log_role_change
-- ============================================================
CREATE OR REPLACE FUNCTION public.log_role_change(
    p_user_id UUID,
    p_old_role TEXT,
    p_new_role TEXT,
    p_changed_by UUID DEFAULT NULL,
    p_reason TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'admin_ui'
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.user_role_history (
        user_id, old_role, new_role, changed_by, reason, source
    )
    VALUES (p_user_id, p_old_role, p_new_role, p_changed_by, p_reason, p_source)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ============================================================
-- 3. Row Level Security (RLS) Policies
-- ============================================================
ALTER TABLE public.user_role_history ENABLE ROW LEVEL SECURITY;

-- Allow all reads for now (custom auth project)
DROP POLICY IF EXISTS "role_history_select" ON public.user_role_history;
CREATE POLICY "role_history_select" ON public.user_role_history FOR SELECT USING (true);

DROP POLICY IF EXISTS "role_history_modify" ON public.user_role_history;
CREATE POLICY "role_history_modify" ON public.user_role_history FOR ALL USING (true);
