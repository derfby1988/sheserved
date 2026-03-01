-- ==========================================
-- Add FDA Risk Status to medications
-- ==========================================

-- เพิ่ม Column fda_risk_status สำหรับบอกประเภทความอันตรายตาม อย.
-- (เช่น ND=ยาสามัญประจำบ้าน, D=ยาอันตราย, S=ยาควบคุมพิเศษ, ฯลฯ)
ALTER TABLE public.medications ADD COLUMN IF NOT EXISTS fda_risk_status VARCHAR(50);

-- สร้างตารางอ้างอิงประเภทของอย. (Optional - ถ้าอยากทำเป็น Master Data ให้แอดมินจัดการ)
CREATE TABLE IF NOT EXISTS public.fda_risk_types (
    code VARCHAR(50) PRIMARY KEY,
    name_th VARCHAR(255) NOT NULL,
    name_en VARCHAR(255),
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.fda_risk_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Enable read access for all users" ON public.fda_risk_types FOR SELECT USING (true);
CREATE POLICY "Enable all access for all users" ON public.fda_risk_types FOR ALL USING (true);

-- ใส่ข้อมูลเบื้องต้น
INSERT INTO public.fda_risk_types (code, name_th, name_en) VALUES 
('ND', 'ยาสามัญประจำบ้าน', 'Non-Dangerous Drug / Household Remedy'),
('D', 'ยาอันตราย', 'Dangerous Drug'),
('S', 'ยาควบคุมพิเศษ', 'Specially Controlled Drug'),
('N', 'ยาเสพติดให้โทษ', 'Narcotic Drug'),
('P', 'วัตถุออกฤทธิ์ต่อจิตและประสาท', 'Psychotropic Substance'),
('SUP', 'ผลิตภัณฑ์เสริมอาหาร', 'Dietary Supplement'),
('MED', 'เครื่องมือแพทย์', 'Medical Device'),
('COS', 'เครื่องสำอาง', 'Cosmetic')
ON CONFLICT DO NOTHING;

-- สร้าง View หรือ Trigger เพื่อทำ Auto-Mapping อันตรายตามอย. (fda_risk_status)
-- เข้ามาอยู่ในหมวดหมู่เชิงการค้าแบบอัตโนมัติ (ถ้ายานั้นๆ มีการระบุ fda_risk_status ไว้)
-- *ต้องมีตาราง product_categories และ medication_category_mappings แล้ว*

-- ฟังก์ชันสำหรับทำ Auto Mappings
CREATE OR REPLACE FUNCTION auto_map_fda_status_to_category()
RETURNS TRIGGER AS $$
DECLARE
    category_id_home_remedy UUID;
    category_id_dangerous UUID;
BEGIN
    -- หากมีการระบุประเภท อย. ให้ดักจับแล้ว Map อัตโนมัติ
    IF NEW.fda_risk_status IS NOT NULL THEN
        -- ถ้ายาสามัญประจำบ้าน
        IF NEW.fda_risk_status = 'ND' THEN
            SELECT id INTO category_id_home_remedy FROM public.product_categories WHERE name = 'ยาสามัญประจำบ้าน' LIMIT 1;
            IF category_id_home_remedy IS NOT NULL THEN
                INSERT INTO public.medication_category_mappings (medication_id, category_id)
                VALUES (NEW.id, category_id_home_remedy)
                ON CONFLICT DO NOTHING;
            END IF;
        -- ถ้ายาอันตราย
        ELSIF NEW.fda_risk_status = 'D' THEN
            SELECT id INTO category_id_dangerous FROM public.product_categories WHERE name = 'ยาอันตราย' LIMIT 1;
            IF category_id_dangerous IS NOT NULL THEN
                INSERT INTO public.medication_category_mappings (medication_id, category_id)
                VALUES (NEW.id, category_id_dangerous)
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- สร้าง Trigger เมื่อ Insert หรือ Update ตำรับยา
DROP TRIGGER IF EXISTS trigger_auto_map_fda_status ON public.medications;
CREATE TRIGGER trigger_auto_map_fda_status
AFTER INSERT OR UPDATE OF fda_risk_status ON public.medications
FOR EACH ROW
EXECUTE FUNCTION auto_map_fda_status_to_category();

