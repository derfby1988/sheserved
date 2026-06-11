-- Migration: ERP Phase 0 — Reliability Core (inbox + audit), RBAC, Feature Flags
-- Date: 2026-06-11
-- Prerequisites: users, professions, organization_branches, outbox_events, idempotency_keys
--   (outbox_events & idempotency_keys อยู่ใน 20260609180000_create_accounting_core_schema.sql แล้ว)

-- ============================================================
-- 1. RELIABILITY CORE — inbox_events (สำหรับ consumer อ่าน cross-module event)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inbox_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    -- อ้างอิง outbox event ที่ส่งมา (ถ้ามี)
    outbox_event_id UUID REFERENCES public.outbox_events(id) ON DELETE SET NULL,
    aggregate_type  TEXT NOT NULL CHECK (aggregate_type IN ('pos_sale','procurement_gr','hr_payroll','telemedicine','logistics','manual','accounting')),
    aggregate_id    UUID NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL DEFAULT '{}',
    -- สถานะการประมวลผลของ consumer
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','processing','completed','failed','skipped')),
    retry_count     INT NOT NULL DEFAULT 0,
    error_message   TEXT,
    -- consumer ที่รับผิดชอบ (เช่น module_name หรือ worker_id)
    consumer_id     TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    processed_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_inbox_status
    ON public.inbox_events(status, created_at);
CREATE INDEX IF NOT EXISTS idx_inbox_aggregate
    ON public.inbox_events(aggregate_type, aggregate_id);
CREATE INDEX IF NOT EXISTS idx_inbox_consumer
    ON public.inbox_events(consumer_id, status, created_at);

-- ============================================================
-- 2. RELIABILITY CORE — transaction_contexts (audit log สำหรับแต่ละ business transaction)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.transaction_contexts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    -- แท็ก transaction เช่น checkout-uuid หรือ saga-id
    transaction_id  TEXT NOT NULL,
    -- module ที่เริ่ม transaction
    source_module   TEXT NOT NULL
                        CHECK (source_module IN ('pos','inventory','procurement','accounting','hr','crm','his','lis','telemedicine','logistics','commerce','cart','settlement','platform')),
    -- ประเภท operation ภายใน transaction
    operation_type  TEXT NOT NULL,
    -- สถานะของ transaction context นี้
    status          TEXT NOT NULL DEFAULT 'started'
                        CHECK (status IN ('started','committed','rolled_back','compensating','compensated','failed')),
    -- เก็บขั้นตอนย่อย (sub-operations) เป็น JSONB array
    steps           JSONB NOT NULL DEFAULT '[]',
    -- metadata เช่น {user_id, branch_id, ip_address, user_agent}
    metadata        JSONB NOT NULL DEFAULT '{}',
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    ended_at        TIMESTAMPTZ,
    created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_transaction_context_id
    ON public.transaction_contexts(transaction_id, source_module);
CREATE INDEX IF NOT EXISTS idx_transaction_context_status
    ON public.transaction_contexts(status, started_at);

-- ============================================================
-- 3. RBAC — organization_roles (roles ของแต่ละ profession)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.organization_roles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    role_name       TEXT NOT NULL,                            -- เช่น "แคชเชียร์", "ผู้จัดการสาขา"
    role_description TEXT,
    is_system_role  BOOLEAN NOT NULL DEFAULT false,           -- true = ไม่ลบได้ (เช่น owner, admin)
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, role_name)
);

CREATE INDEX IF NOT EXISTS idx_org_roles_profession
    ON public.organization_roles(profession_id);

-- ============================================================
-- 4. RBAC — role_module_permissions (permissions ของแต่ละ role ต่อ module)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.role_module_permissions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id         UUID NOT NULL REFERENCES public.organization_roles(id) ON DELETE CASCADE,
    module_name     TEXT NOT NULL
                        CHECK (module_name IN (
                            'pos','inventory','procurement','accounting',
                            'hr','crm','his','lis','telemedicine','logistics',
                            'commerce','cart','settlement','read_model','reliability'
                        )),
    -- access_level: 0=None, 1=View, 2=Edit, 3=Full (Create/Update/Delete)
    access_level    INTEGER NOT NULL DEFAULT 0
                        CHECK (access_level IN (0, 1, 2, 3)),
    UNIQUE (role_id, module_name)
);

CREATE INDEX IF NOT EXISTS idx_role_perms_role
    ON public.role_module_permissions(role_id);

-- ============================================================
-- 5. RBAC — employee_roles (mapping user + role ของแต่ละ profession/branch)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.employee_roles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    -- ถ้า NULL = HQ admin ดูแลทุกสาขา
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role_id         UUID NOT NULL REFERENCES public.organization_roles(id) ON DELETE CASCADE,
    assigned_at     TIMESTAMPTZ DEFAULT NOW(),
    assigned_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (profession_id, user_id, role_id, branch_id)
);

CREATE INDEX IF NOT EXISTS idx_emp_roles_user
    ON public.employee_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_emp_roles_profession
    ON public.employee_roles(profession_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_emp_roles_active
    ON public.employee_roles(is_active, profession_id);

-- ============================================================
-- 6. FEATURE FLAGS — organization_feature_flags (เปิด/ปิด module ตาม profession)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.organization_feature_flags (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    feature_name    TEXT NOT NULL,
    -- สถานะ: enabled, disabled, beta, deprecated
    status          TEXT NOT NULL DEFAULT 'disabled'
                        CHECK (status IN ('enabled','disabled','beta','deprecated')),
    -- ใครเปิด/ปิดล่าสุด
    updated_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, feature_name)
);

CREATE INDEX IF NOT EXISTS idx_feature_flags_profession
    ON public.organization_feature_flags(profession_id, status);

-- ============================================================
-- 7. ROW LEVEL SECURITY (RLS) Policies
-- ============================================================
-- ปิด RLS ก่อนเพราะระบบใช้ custom auth (ไม่ใช่ Supabase Auth native)
-- แต่เปิดไว้เพื่อความปลอดภัยในอนาคต

ALTER TABLE public.inbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_contexts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_module_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_feature_flags ENABLE ROW LEVEL SECURITY;

-- สำหรับ Phase 0 ให้ผ่านทั้งหมดก่อน (เพราะใช้ custom auth service)
-- ต้อง migrate เป็น service-role / application-layer check ภายหลัง
DROP POLICY IF EXISTS "inbox_select" ON public.inbox_events;
CREATE POLICY "inbox_select" ON public.inbox_events FOR SELECT USING (true);
DROP POLICY IF EXISTS "inbox_modify" ON public.inbox_events;
CREATE POLICY "inbox_modify" ON public.inbox_events FOR ALL USING (true);

DROP POLICY IF EXISTS "tx_context_select" ON public.transaction_contexts;
CREATE POLICY "tx_context_select" ON public.transaction_contexts FOR SELECT USING (true);
DROP POLICY IF EXISTS "tx_context_modify" ON public.transaction_contexts;
CREATE POLICY "tx_context_modify" ON public.transaction_contexts FOR ALL USING (true);

DROP POLICY IF EXISTS "org_roles_select" ON public.organization_roles;
CREATE POLICY "org_roles_select" ON public.organization_roles FOR SELECT USING (true);
DROP POLICY IF EXISTS "org_roles_modify" ON public.organization_roles;
CREATE POLICY "org_roles_modify" ON public.organization_roles FOR ALL USING (true);

DROP POLICY IF EXISTS "role_perms_select" ON public.role_module_permissions;
CREATE POLICY "role_perms_select" ON public.role_module_permissions FOR SELECT USING (true);
DROP POLICY IF EXISTS "role_perms_modify" ON public.role_module_permissions;
CREATE POLICY "role_perms_modify" ON public.role_module_permissions FOR ALL USING (true);

DROP POLICY IF EXISTS "emp_roles_select" ON public.employee_roles;
CREATE POLICY "emp_roles_select" ON public.employee_roles FOR SELECT USING (true);
DROP POLICY IF EXISTS "emp_roles_modify" ON public.employee_roles;
CREATE POLICY "emp_roles_modify" ON public.employee_roles FOR ALL USING (true);

DROP POLICY IF EXISTS "feature_flags_select" ON public.organization_feature_flags;
CREATE POLICY "feature_flags_select" ON public.organization_feature_flags FOR SELECT USING (true);
DROP POLICY IF EXISTS "feature_flags_modify" ON public.organization_feature_flags;
CREATE POLICY "feature_flags_modify" ON public.organization_feature_flags FOR ALL USING (true);

-- ============================================================
-- 8. RPC Functions สำหรับ Phase 0
-- ============================================================

-- 8.1 ดึง roles + permissions ของ user ใน profession
CREATE OR REPLACE FUNCTION public.get_user_roles_and_permissions(
    p_user_id UUID,
    p_profession_id UUID
)
RETURNS TABLE (
    role_id UUID,
    role_name TEXT,
    role_description TEXT,
    is_system_role BOOLEAN,
    branch_id UUID,
    is_active BOOLEAN,
    permissions JSONB
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT
        er.role_id,
        org_r.role_name,
        org_r.role_description,
        org_r.is_system_role,
        er.branch_id,
        er.is_active,
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'module_name', rmp.module_name,
                    'access_level', rmp.access_level
                )
            ) FILTER (WHERE rmp.id IS NOT NULL),
            '[]'::jsonb
        ) AS permissions
    FROM public.employee_roles er
    JOIN public.organization_roles org_r ON org_r.id = er.role_id
    LEFT JOIN public.role_module_permissions rmp ON rmp.role_id = er.role_id
    WHERE er.user_id = p_user_id
      AND er.profession_id = p_profession_id
      AND er.is_active = true
    GROUP BY er.role_id, org_r.role_name, org_r.role_description,
             org_r.is_system_role, er.branch_id, er.is_active;
END;
$$;

-- 8.2 ดึง feature flags ของ profession
CREATE OR REPLACE FUNCTION public.get_profession_feature_flags(
    p_profession_id UUID
)
RETURNS TABLE (
    feature_name TEXT,
    status TEXT,
    updated_at TIMESTAMPTZ
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT
        off.feature_name,
        off.status,
        off.updated_at
    FROM public.organization_feature_flags off
    WHERE off.profession_id = p_profession_id
    ORDER BY off.feature_name;
END;
$$;

-- 8.3 อัปเดต/สร้าง feature flag
CREATE OR REPLACE FUNCTION public.upsert_feature_flag(
    p_profession_id UUID,
    p_feature_name TEXT,
    p_status TEXT,
    p_updated_by UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.organization_feature_flags (
        profession_id, feature_name, status, updated_by, updated_at
    )
    VALUES (p_profession_id, p_feature_name, p_status, p_updated_by, NOW())
    ON CONFLICT (profession_id, feature_name)
    DO UPDATE SET
        status = EXCLUDED.status,
        updated_by = EXCLUDED.updated_by,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- 8.4 สร้าง transaction context
CREATE OR REPLACE FUNCTION public.create_transaction_context(
    p_profession_id UUID,
    p_transaction_id TEXT,
    p_source_module TEXT,
    p_operation_type TEXT,
    p_metadata JSONB DEFAULT '{}',
    p_created_by UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.transaction_contexts (
        profession_id, transaction_id, source_module,
        operation_type, status, metadata, created_by
    )
    VALUES (
        p_profession_id, p_transaction_id, p_source_module,
        p_operation_type, 'started', p_metadata, p_created_by
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- 8.5 อัปเดต transaction context status + steps
CREATE OR REPLACE FUNCTION public.update_transaction_context(
    p_transaction_context_id UUID,
    p_status TEXT,
    p_steps JSONB DEFAULT NULL,
    p_ended_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
    UPDATE public.transaction_contexts
    SET
        status = p_status,
        steps = COALESCE(p_steps, steps),
        ended_at = COALESCE(p_ended_at, ended_at, NOW())
    WHERE id = p_transaction_context_id;

    RETURN FOUND;
END;
$$;
