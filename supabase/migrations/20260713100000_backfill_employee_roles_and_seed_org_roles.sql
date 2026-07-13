-- Migration: Backfill employee_roles + Seed organization_roles for provider professions
-- Date: 2026-07-13
--
-- ปัญหา: ผู้ใช้ที่สร้างโดยตรง (ไม่ผ่าน registration application flow)
-- มี profession_id แต่ไม่มี employee_roles ทำให้เข้า ERP Dashboard ไม่ได้
-- เช่น apisek ที่มี profession_id แต่ไม่มี record ใน employee_roles
--
-- แก้:
-- 1. Seed organization_roles สำหรับ provider professions ที่ขาด
-- 2. Seed role_module_permissions สำหรับ owner role ที่ขาด
-- 3. Backfill employee_roles สำหรับ users ที่มี profession_id แต่ไม่มี active roles
-- 4. Add trigger เพื่อ seed organization_roles อัตโนมัติสำหรับ profession ใหม่

-- ============================================================
-- 1. Seed organization_roles สำหรับ provider professions ที่ขาด
-- ============================================================

INSERT INTO public.organization_roles (profession_id, role_name, role_description, is_system_role)
SELECT
    p.id AS profession_id,
    r.role_name,
    r.role_description,
    true AS is_system_role
FROM public.professions p
CROSS JOIN LATERAL (VALUES
    ('owner',     'เจ้าขององค์กร — ควบคุมทุกโมดูลและตั้งค่าทั้งหมด'),
    ('admin',     'ผู้ดูแลระบบ — จัดการผู้ใช้ สิทธิ์ และตั้งค่าทั่วไป'),
    ('manager',   'ผู้จัดการสาขา — ดูรายงาน จัดการสต็อกและยอดขาย'),
    ('staff',     'พนักงานทั่วไป — ใช้งาน POS และดูข้อมูลพื้นฐาน'),
    ('cashier',   'แคชเชียร์ — รับชำระเงินและใช้ POS เท่านั้น'),
    ('accountant','นักบัญชี — จัดการบัญชีและรายงานการเงิน')
) AS r(role_name, role_description)
WHERE p.category = 'provider'
  AND p.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM public.organization_roles or2
    WHERE or2.profession_id = p.id AND or2.role_name = r.role_name
  )
ON CONFLICT (profession_id, role_name) DO NOTHING;

-- ============================================================
-- 2. Seed role_module_permissions สำหรับ owner role ที่ขาด
-- ============================================================

INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
SELECT or2.id, m.module_name, 3
FROM public.organization_roles or2
CROSS JOIN LATERAL (VALUES
    ('pos'), ('inventory'), ('procurement'), ('accounting'),
    ('hr'), ('crm'), ('his'), ('lis'), ('telemedicine'),
    ('logistics'), ('commerce'), ('cart'), ('settlement'),
    ('read_model'), ('reliability')
) AS m(module_name)
WHERE or2.role_name = 'owner'
  AND or2.is_system_role = true
  AND NOT EXISTS (
    SELECT 1 FROM public.role_module_permissions rmp
    WHERE rmp.role_id = or2.id AND rmp.module_name = m.module_name
  )
ON CONFLICT (role_id, module_name) DO NOTHING;

-- ============================================================
-- 3. Backfill employee_roles สำหรับ users ที่มี profession_id
--    แต่ไม่มี active employee_roles ใน profession นั้น
-- ============================================================

INSERT INTO public.employee_roles (profession_id, branch_id, user_id, role_id, is_active)
SELECT DISTINCT
    u.profession_id,
    b.id AS branch_id,
    u.id AS user_id,
    or2.id AS role_id,
    true AS is_active
FROM public.users u
JOIN public.professions p ON p.id = u.profession_id
JOIN public.organization_roles or2
    ON or2.profession_id = u.profession_id
    AND or2.role_name = 'owner'
LEFT JOIN LATERAL (
    SELECT id FROM public.organization_branches
    WHERE profession_id = u.profession_id
    ORDER BY is_main_branch DESC, created_at ASC
    LIMIT 1
) b ON true
WHERE p.category = 'provider'
  AND p.is_active = true
  AND u.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_roles er
    WHERE er.user_id = u.id
      AND er.profession_id = u.profession_id
      AND er.is_active = true
  )
ON CONFLICT (profession_id, user_id, role_id, branch_id) DO NOTHING;

-- ============================================================
-- 4. Trigger: seed organization_roles อัตโนมัติสำหรับ profession ใหม่
--    (ป้องกันปัญหานี้ในอนาคต)
-- ============================================================

CREATE OR REPLACE FUNCTION public.seed_organization_roles_for_new_profession()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.category = 'provider' AND NEW.is_active = true THEN
        INSERT INTO public.organization_roles (profession_id, role_name, role_description, is_system_role)
        SELECT
            NEW.id AS profession_id,
            r.role_name,
            r.role_description,
            true AS is_system_role
        FROM (VALUES
            ('owner',     'เจ้าขององค์กร — ควบคุมทุกโมดูลและตั้งค่าทั้งหมด'),
            ('admin',     'ผู้ดูแลระบบ — จัดการผู้ใช้ สิทธิ์ และตั้งค่าทั่วไป'),
            ('manager',   'ผู้จัดการสาขา — ดูรายงาน จัดการสต็อกและยอดขาย'),
            ('staff',     'พนักงานทั่วไป — ใช้งาน POS และดูข้อมูลพื้นฐาน'),
            ('cashier',   'แคชเชียร์ — รับชำระเงินและใช้ POS เท่านั้น'),
            ('accountant','นักบัญชี — จัดการบัญชีและรายงานการเงิน')
        ) AS r(role_name, role_description)
        ON CONFLICT (profession_id, role_name) DO NOTHING;

        -- Seed owner permissions (full access ทุกโมดูล)
        INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
        SELECT or2.id, m.module_name, 3
        FROM public.organization_roles or2
        CROSS JOIN LATERAL (VALUES
            ('pos'), ('inventory'), ('procurement'), ('accounting'),
            ('hr'), ('crm'), ('his'), ('lis'), ('telemedicine'),
            ('logistics'), ('commerce'), ('cart'), ('settlement'),
            ('read_model'), ('reliability')
        ) AS m(module_name)
        WHERE or2.profession_id = NEW.id
          AND or2.role_name = 'owner'
          AND or2.is_system_role = true
        ON CONFLICT (role_id, module_name) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_seed_organization_roles_on_profession_insert
    ON public.professions;

CREATE TRIGGER trg_seed_organization_roles_on_profession_insert
    AFTER INSERT ON public.professions
    FOR EACH ROW
    EXECUTE FUNCTION public.seed_organization_roles_for_new_profession();
