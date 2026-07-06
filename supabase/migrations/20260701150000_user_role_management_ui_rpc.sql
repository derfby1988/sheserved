-- ============================================================
-- User-Role & Permission Management UI — Phase 1
-- RPC: get_users_with_roles
-- ดึงรายการ user ทั้งหมดใน profession พร้อม role
-- รวม user ที่ยังไม่มี role เพื่อให้ admin มอบ role ได้
-- สอดคล้องกับ ERP_CORE_ARCHITECTURE.md Phase 0 (RBAC)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_users_with_roles(
    p_profession_id UUID
) RETURNS JSONB AS $$
    SELECT jsonb_agg(jsonb_build_object(
        'user_id', u.id,
        'full_name', COALESCE(
            NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''),
            u.username,
            u.email,
            u.phone
        ),
        'username', u.username,
        'email', u.email,
        'phone', u.phone,
        'roles', COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'employee_role_id', er.id,
                'role_id', er.role_id,
                'role_name', r.role_name,
                'branch_id', er.branch_id,
                'is_active', er.is_active,
                'assigned_at', er.assigned_at,
                'assigned_by', er.assigned_by
            ))
            FROM public.employee_roles er
            JOIN public.organization_roles r ON r.id = er.role_id
            WHERE er.user_id = u.id AND er.profession_id = p_profession_id),
            '[]'::jsonb
        )
    ))
    FROM public.users u
    WHERE u.profession_id = p_profession_id
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ============================================================
-- Optional: permission_requests table
-- สำหรับบันทึกคำขอสิทธิ์จาก user ผ่าน PermissionDeniedWidget
-- ============================================================

CREATE TABLE IF NOT EXISTS public.permission_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    module_name     TEXT NOT NULL,
    requested_level INTEGER NOT NULL CHECK (requested_level BETWEEN 1 AND 3),
    reason          TEXT,
    status          TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected')),
    reviewed_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reviewed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_permission_requests_status
    ON public.permission_requests(profession_id, status);

CREATE INDEX IF NOT EXISTS idx_permission_requests_user
    ON public.permission_requests(user_id, status);
