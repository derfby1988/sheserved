-- ============================================================
-- Phase 7: Add is_active to organization_roles
-- ให้สามารถระงับ/เปิดใช้งาน role ได้โดยไม่ต้องลบ
-- ============================================================

-- 1. เพิ่มคอลัมน์ is_active (default true เพื่อให้ role ที่มีอยู่ยังใช้งานได้)
ALTER TABLE public.organization_roles
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- 2. อัปเดต role ที่มีอยู่ให้เป็น active ทั้งหมด
UPDATE public.organization_roles
SET is_active = true
WHERE is_active IS NULL;

-- 3. Index สำหรับกรอง active roles
CREATE INDEX IF NOT EXISTS idx_org_roles_active
    ON public.organization_roles(profession_id, is_active);

-- 4. อัปเดต updated_at อัตโนมัติเมื่อเปลี่ยน is_active
CREATE OR REPLACE FUNCTION public.set_organization_roles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_organization_roles_updated_at ON public.organization_roles;
CREATE TRIGGER trg_organization_roles_updated_at
    BEFORE UPDATE ON public.organization_roles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_organization_roles_updated_at();
