-- ========================================================================
-- Fix local_leader Category
-- Migration: 20260302110000_fix_local_leader_category.sql
-- ========================================================================

BEGIN;

-- 1. ย้ายข้อมูลหมวดหมู่ 'leader' หรือ 'local leader' ไปเป็น 'local_leader' (ถ้ามี)
-- หรือสร้างใหม่ถ้ายังไม่มี
DO $$
BEGIN
    -- กรณีมี ID เก่าเป็น 'leader' หรือ 'local leader' (แบบมีช่องว่าง) ให้เปลี่ยนเป็น 'local_leader'
    IF EXISTS (SELECT 1 FROM public.user_categories WHERE id IN ('leader', 'local leader')) THEN
        -- แทรก ID ใหม่ด้วยข้อมูลเดิม (เลือกอันใดอันหนึ่งมา)
        INSERT INTO public.user_categories (id, name, name_en, icon_name, display_order)
        SELECT 'local_leader', name, name_en, icon_name, display_order
        FROM public.user_categories WHERE id IN ('leader', 'local leader')
        LIMIT 1
        ON CONFLICT (id) DO NOTHING;
        
        -- อัปเดตอาชีพที่เคยผูกกับ ID เก่าให้มาผูกกับ 'local_leader'
        UPDATE public.professions SET category = 'local_leader' WHERE category IN ('leader', 'local leader');
        
        -- ลบหมวดหมู่เก่าทิ้ง
        DELETE FROM public.user_categories WHERE id IN ('leader', 'local leader');
    ELSE
        -- หากไม่มีเลย ให้สร้าง 'local_leader' ขึ้นมาใหม่
        INSERT INTO public.user_categories (id, name, name_en, icon_name, display_order)
        VALUES ('local_leader', 'ผู้นำชุมชน', 'Local Leader', 'gavel', 2)
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;

-- 2. ลบ "ผู้นำชุมชน" ออกจากตาราง "อาชีพ" (เนื่องจากเป็นหมวดหมู่ ไม่ใช่ตัวอาชีพเอง)
DELETE FROM public.professions WHERE category = 'local_leader' AND name = 'ผู้นำชุมชน';

COMMIT;
