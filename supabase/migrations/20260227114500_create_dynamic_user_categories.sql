-- Migration: Create user_categories table for dynamic scaling
-- Created at: 2026-02-27 11:45:00

-- 1. สร้างตารางหมวดหมู่ผู้ใช้
CREATE TABLE IF NOT EXISTS public.user_categories (
    id TEXT PRIMARY KEY, -- เช่น 'consumer', 'provider', 'volunteer'
    name TEXT NOT NULL,
    name_en TEXT,
    description TEXT,
    icon_name TEXT,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. ย้ายข้อมูลพื้นฐานลงในตารางใหม่ (Seed Data)
INSERT INTO public.user_categories (id, name, name_en, icon_name, display_order) VALUES
('consumer', 'ผู้ซื้อ/ผู้รับบริการ', 'Consumer', 'shopping_cart', 0),
('provider', 'ผู้ให้บริการ', 'Provider', 'medical_services', 1)
ON CONFLICT (id) DO NOTHING;

-- 3. ปรับปรุงตาราง professions (อนุญาตให้ขยายหมวดหมู่ได้)
-- ลบ CHECK constraint เดิมออก (ถ้ามี) เพื่อให้รองรับค่าใหม่ๆ
DO $$
BEGIN
    -- สำหรับ Postgres ทั่วไปที่มี CHECK constraint
    EXECUTE 'ALTER TABLE public.professions DROP CONSTRAINT IF EXISTS professions_category_check';
END $$;

-- 4. ตั้งค่า Foreign Key (ทางเลือก: เพื่อความแม่นยำของข้อมูล)
-- ALTER TABLE public.professions ADD CONSTRAINT professions_category_fkey 
-- FOREIGN KEY (category) REFERENCES public.user_categories(id);
