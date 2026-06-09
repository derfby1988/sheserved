-- =====================================================
-- Migration: Fix Default Consumer Profession
-- Date: 2026-06-09
-- Purpose:
--   1. Rename built-in consumer profession to "ผู้ใช้งานทั่วไป"
--   2. Backfill users with NULL profession_id to point to built-in UUID
--   3. Prevent deletion of built-in professions (soft-delete only)
-- =====================================================

-- =====================================================
-- PART 1: Rename built-in consumer profession
-- =====================================================

UPDATE public.professions
SET
    name = 'ผู้ใช้งานทั่วไป',
    name_en = 'Consumer',
    description = 'ผู้ใช้ทั่วไปที่ต้องการซื้อสินค้า รับบริการ หรือใช้งานแอปพลิเคชัน',
    updated_at = NOW()
WHERE id = '00000000-0000-0000-0000-000000000001';

-- =====================================================
-- PART 2: Backfill users with NULL profession_id
-- ผู้ใช้ที่ไม่มี profession_id (ระบบเก่า) ถือว่าเป็น consumer
-- ให้ชี้ไปที่ built-in UUID อย่างชัดเจน
-- =====================================================

UPDATE public.users
SET
    profession_id = '00000000-0000-0000-0000-000000000001',
    updated_at = NOW()
WHERE profession_id IS NULL;

-- =====================================================
-- PART 3: Prevent hard-deletion of built-in professions
-- ใช้ trigger block DELETE สำหรับ built-in professions
-- หากต้องการ "ลบ" ให้ใช้ is_active = false (soft delete) แทน
-- =====================================================

CREATE OR REPLACE FUNCTION public.prevent_built_in_profession_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF OLD.id IN (
        '00000000-0000-0000-0000-000000000001',  -- ผู้ใช้งานทั่วไป
        '00000000-0000-0000-0000-000000000002',  -- ผู้เชี่ยวชาญ/ผู้ขาย
        '00000000-0000-0000-0000-000000000003',  -- คลินิก/ศูนย์
        '00000000-0000-0000-0000-000000000004'   -- ผู้นำชุมชน
    ) THEN
        RAISE EXCEPTION 'Cannot delete built-in profession "%". Use soft delete (is_active = false) or rename instead.', OLD.name;
    END IF;
    RETURN OLD;
END;
$$;

-- Drop existing trigger if exists (idempotent)
DROP TRIGGER IF EXISTS trg_prevent_built_in_profession_delete ON public.professions;

CREATE TRIGGER trg_prevent_built_in_profession_delete
    BEFORE DELETE ON public.professions
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_built_in_profession_delete();

-- =====================================================
-- PART 4: Ensure built-in professions are always active
-- =====================================================

UPDATE public.professions
SET is_active = true
WHERE id IN (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000004'
);

-- =====================================================
-- PART 5: Add comment explaining the convention
-- =====================================================

COMMENT ON TABLE public.professions IS
    'Professions table. Built-in professions (IDs starting with 00000000-) are protected from deletion by trigger. Use is_active = false for soft-delete. The default consumer profession (00000000-0000-0000-0000-000000000001) is renamed to "ผู้ใช้งานทั่วไป" and serves as the fallback for all users without an explicit profession.';
