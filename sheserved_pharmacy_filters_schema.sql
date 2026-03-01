-- 1. Create table for categories/filters
CREATE TABLE IF NOT EXISTS public.product_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) DEFAULT 'CATEGORY', -- CATEGORY, TAG, etc.
    is_active BOOLEAN DEFAULT true,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 2. Create mapping table
CREATE TABLE IF NOT EXISTS public.medication_category_mappings (
    medication_id UUID REFERENCES public.medications(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.product_categories(id) ON DELETE CASCADE,
    PRIMARY KEY (medication_id, category_id)
);

-- 3. Add price, image, and stock status to medications
ALTER TABLE public.medications ADD COLUMN IF NOT EXISTS price DECIMAL(10,2);
ALTER TABLE public.medications ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.medications ADD COLUMN IF NOT EXISTS in_stock BOOLEAN DEFAULT true;

-- 4. RLS for new tables
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medication_category_mappings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable read access for all users" ON public.product_categories;
CREATE POLICY "Enable read access for all users" ON public.product_categories FOR SELECT USING (true);

DROP POLICY IF EXISTS "Enable all access for all users" ON public.product_categories;
CREATE POLICY "Enable all access for all users" ON public.product_categories FOR ALL USING (true); -- Simplify for MVP management

DROP POLICY IF EXISTS "Enable read access for all users" ON public.medication_category_mappings;
CREATE POLICY "Enable read access for all users" ON public.medication_category_mappings FOR SELECT USING (true);

DROP POLICY IF EXISTS "Enable all access for all users" ON public.medication_category_mappings;
CREATE POLICY "Enable all access for all users" ON public.medication_category_mappings FOR ALL USING (true);

-- Insert some default categories
INSERT INTO public.product_categories (name, display_order) VALUES 
('ยาสามัญประจำบ้าน', 1),
('ยาอันตราย', 2),
('วิตามินและอาหารเสริม', 3),
('อุปกรณ์ทางการแพทย์', 4),
('เวชภัณฑ์สำหรับเด็ก', 5),
('สมุนไพร', 6)
ON CONFLICT DO NOTHING;
