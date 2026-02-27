-- Migration: Revise user_categories with RLS and Foreign Key
-- Created at: 2026-02-27 12:25:00

-- 1. สร้างตารางหมวดหมู่ผู้ใช้ (ถ้าไม่มี)
CREATE TABLE IF NOT EXISTS public.user_categories (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_en TEXT,
    description TEXT,
    icon_name TEXT,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. เปิดใช้งาน RLS
ALTER TABLE public.user_categories ENABLE ROW LEVEL SECURITY;

-- 3. สร้างนโยบายการเข้าถึงข้อมูล (Policies)
DROP POLICY IF EXISTS "Allow public read-only access" ON public.user_categories;
CREATE POLICY "Allow public read-only access" ON public.user_categories
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow admin all access" ON public.user_categories;
CREATE POLICY "Allow admin all access" ON public.user_categories
    FOR ALL USING (auth.role() = 'authenticated'); -- ปรับตามระบบสิทธิ์ของคุณ

-- 4. เชื่อมโยงกับตาราง professions เพื่อให้ดึงข้อมูล display_order ข้ามตารางได้
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'professions_category_fkey') THEN
        ALTER TABLE public.professions 
        ADD CONSTRAINT professions_category_fkey 
        FOREIGN KEY (category) REFERENCES public.user_categories(id);
    END IF;
END $$;

-- 5. ย้ายข้อมูลพื้นฐานลงในตารางใหม่ (Seed Data)
INSERT INTO public.user_categories (id, name, name_en, icon_name, display_order) VALUES
('consumer', 'ผู้ซื้อ/ผู้รับบริการ', 'Consumer', 'shopping_cart', 0),
('provider', 'ผู้ให้บริการ', 'Provider', 'medical_services', 1)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, display_order = EXCLUDED.display_order;
