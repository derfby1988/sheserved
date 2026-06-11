-- Migration: Seed Phase 0 Defaults
-- Date: 2026-06-11
-- Prerequisites: organization_roles, role_module_permissions, organization_feature_flags tables exist
-- Note: ต้องรัน AFTER migration 20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql

-- ============================================================
-- 1. Seed System Roles (ไม่ลบได้ — is_system_role = true)
-- ============================================================

-- ใส่ ON CONFLICT เพื่อให้ idempotent (รันได้หลายครั้งไม่ error)
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
  AND NOT EXISTS (
    SELECT 1 FROM public.organization_roles or2
    WHERE or2.profession_id = p.id AND or2.role_name = r.role_name
  )
ON CONFLICT (profession_id, role_name) DO NOTHING;

-- ============================================================
-- 2. Seed Default Permissions สำหรับ System Roles
-- ============================================================

-- Owner: Full access (3) ทุกโมดูล
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

-- Admin: Full access ทุกโมดูลยกเว้น reliability (เหลือ 2 = Edit)
INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
SELECT or2.id, m.module_name, m.access_level
FROM public.organization_roles or2
CROSS JOIN LATERAL (VALUES
    ('pos', 3), ('inventory', 3), ('procurement', 3), ('accounting', 3),
    ('hr', 3), ('crm', 3), ('his', 3), ('lis', 3), ('telemedicine', 3),
    ('logistics', 3), ('commerce', 3), ('cart', 3), ('settlement', 3),
    ('read_model', 3), ('reliability', 2)
) AS m(module_name, access_level)
WHERE or2.role_name = 'admin'
  AND or2.is_system_role = true
  AND NOT EXISTS (
    SELECT 1 FROM public.role_module_permissions rmp
    WHERE rmp.role_id = or2.id AND rmp.module_name = m.module_name
  )
ON CONFLICT (role_id, module_name) DO NOTHING;

-- Manager: Full ทุกโมดูลยกเว้น reliability (0), settlement (2), read_model (2)
INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
SELECT or2.id, m.module_name, m.access_level
FROM public.organization_roles or2
CROSS JOIN LATERAL (VALUES
    ('pos', 3), ('inventory', 3), ('procurement', 2), ('accounting', 2),
    ('hr', 3), ('crm', 3), ('his', 2), ('lis', 2), ('telemedicine', 2),
    ('logistics', 3), ('commerce', 3), ('cart', 3), ('settlement', 2),
    ('read_model', 2), ('reliability', 0)
) AS m(module_name, access_level)
WHERE or2.role_name = 'manager'
  AND or2.is_system_role = true
  AND NOT EXISTS (
    SELECT 1 FROM public.role_module_permissions rmp
    WHERE rmp.role_id = or2.id AND rmp.module_name = m.module_name
  )
ON CONFLICT (role_id, module_name) DO NOTHING;

-- Staff: View/Edit พื้นฐาน ไม่เข้าถึงบัญชี/HR/Settlement/Reliability
INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
SELECT or2.id, m.module_name, m.access_level
FROM public.organization_roles or2
CROSS JOIN LATERAL (VALUES
    ('pos', 2), ('inventory', 2), ('procurement', 0), ('accounting', 0),
    ('hr', 0), ('crm', 2), ('his', 2), ('lis', 1), ('telemedicine', 1),
    ('logistics', 1), ('commerce', 2), ('cart', 2), ('settlement', 0),
    ('read_model', 1), ('reliability', 0)
) AS m(module_name, access_level)
WHERE or2.role_name = 'staff'
  AND or2.is_system_role = true
  AND NOT EXISTS (
    SELECT 1 FROM public.role_module_permissions rmp
    WHERE rmp.role_id = or2.id AND rmp.module_name = m.module_name
  )
ON CONFLICT (role_id, module_name) DO NOTHING;

-- Cashier: POS + Cart เท่านั้น
INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
SELECT or2.id, m.module_name, m.access_level
FROM public.organization_roles or2
CROSS JOIN LATERAL (VALUES
    ('pos', 3), ('inventory', 1), ('procurement', 0), ('accounting', 0),
    ('hr', 0), ('crm', 1), ('his', 0), ('lis', 0), ('telemedicine', 0),
    ('logistics', 1), ('commerce', 2), ('cart', 2), ('settlement', 0),
    ('read_model', 0), ('reliability', 0)
) AS m(module_name, access_level)
WHERE or2.role_name = 'cashier'
  AND or2.is_system_role = true
  AND NOT EXISTS (
    SELECT 1 FROM public.role_module_permissions rmp
    WHERE rmp.role_id = or2.id AND rmp.module_name = m.module_name
  )
ON CONFLICT (role_id, module_name) DO NOTHING;

-- Accountant: Accounting + Read Model เต็มที่
INSERT INTO public.role_module_permissions (role_id, module_name, access_level)
SELECT or2.id, m.module_name, m.access_level
FROM public.organization_roles or2
CROSS JOIN LATERAL (VALUES
    ('pos', 2), ('inventory', 2), ('procurement', 2), ('accounting', 3),
    ('hr', 2), ('crm', 1), ('his', 1), ('lis', 1), ('telemedicine', 0),
    ('logistics', 1), ('commerce', 1), ('cart', 1), ('settlement', 2),
    ('read_model', 3), ('reliability', 0)
) AS m(module_name, access_level)
WHERE or2.role_name = 'accountant'
  AND or2.is_system_role = true
  AND NOT EXISTS (
    SELECT 1 FROM public.role_module_permissions rmp
    WHERE rmp.role_id = or2.id AND rmp.module_name = m.module_name
  )
ON CONFLICT (role_id, module_name) DO NOTHING;

-- ============================================================
-- 3. Seed Default Feature Flags (disabled by default — secure)
-- ============================================================

INSERT INTO public.organization_feature_flags (profession_id, feature_name, status)
SELECT p.id, f.feature_name, 'disabled'
FROM public.professions p
CROSS JOIN LATERAL (VALUES
    ('pos_module'),
    ('inventory_module'),
    ('procurement_module'),
    ('accounting_module'),
    ('hr_module'),
    ('crm_loyalty'),
    ('crm_coupons'),
    ('crm_promotions'),
    ('his_module'),
    ('lis_module'),
    ('telemedicine_module'),
    ('logistics_module'),
    ('commerce_module'),
    ('cart_module'),
    ('settlement_module'),
    ('kpi_dashboard'),
    ('read_model_module')
) AS f(feature_name)
WHERE p.category = 'provider'
  AND NOT EXISTS (
    SELECT 1 FROM public.organization_feature_flags off
    WHERE off.profession_id = p.id AND off.feature_name = f.feature_name
  )
ON CONFLICT (profession_id, feature_name) DO NOTHING;
