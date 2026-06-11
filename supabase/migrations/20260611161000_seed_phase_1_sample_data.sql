-- Migration: Seed Phase 1 Sample Data
-- Date: 2026-06-11
-- Prerequisites: Phase 1 tables exist + professions with category='provider' exist
-- Note: ใส่ข้อมูลตัวอย่างสำหรับ zero-mock integration testing

-- ============================================================
-- 1. Seed Product Categories
-- ============================================================
INSERT INTO public.product_categories (profession_id, name, description, sort_order)
SELECT p.id, c.name, c.description, c.sort_order
FROM public.professions p
CROSS JOIN LATERAL (VALUES
    ('ยา', 'ยาสามัญประจำบ้านและยาตามใบสั่งแพทย์', 1),
    ('อุปกรณ์ทางการแพทย์', 'เครื่องมือและอุปกรณ์ทางการแพทย์', 2),
    ('อาหารเสริม', 'วิตามิน อาหารเสริม และผลิตภัณฑ์เพื่อสุขภาพ', 3),
    ('ผลิตภัณฑ์ความงาม', 'เครื่องสำอางและผลิตภัณฑ์ดูแลผิว', 4),
    ('บริการคลินิก', 'บริการตรวจรักษาและปรึกษาสุขภาพ', 5)
) AS c(name, description, sort_order)
WHERE p.category = 'provider'
  AND NOT EXISTS (
    SELECT 1 FROM public.product_categories pc
    WHERE pc.profession_id = p.id AND pc.name = c.name
  )
ON CONFLICT DO NOTHING;

-- ============================================================
-- 2. Seed Sample Products (for testing)
-- ============================================================
-- หมายเหตุ: ใส่เฉพาะ profession แรกที่พบเพื่อลด noise
DO $$
DECLARE
    v_profession_id UUID;
    v_category_id UUID;
BEGIN
    SELECT id INTO v_profession_id
    FROM public.professions
    WHERE category = 'provider'
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RAISE NOTICE 'No provider profession found — skipping sample product seed';
        RETURN;
    END IF;

    -- หา category แรก
    SELECT id INTO v_category_id
    FROM public.product_categories
    WHERE profession_id = v_profession_id
    LIMIT 1;

    -- Sample products
    INSERT INTO public.products (
        profession_id, category_id, name, description, sku, barcode,
        unit_of_measure, cost_price, sale_price, is_vatable, is_active,
        is_stockable, has_lot_tracking, shelf_life_days, reorder_point, reorder_qty
    )
    VALUES
        (v_profession_id, v_category_id, 'พาราเซตามอล 500mg', 'ยาลดไข้ บรรเทาปวด', 'PARA-500', '885123456001', 'box', 25.00, 45.00, true, true, true, true, 730, 50, 200),
        (v_profession_id, v_category_id, 'แอสไพริน 81mg', 'ยาบางลดความเสี่ยงหัวใจ', 'ASPI-81', '885123456002', 'bottle', 18.00, 35.00, true, true, true, true, 1095, 30, 100),
        (v_profession_id, v_category_id, 'เจลล้างมือ 500ml', 'แอลกอฮอล์ 70% ล้างมือ', 'HAND-500', '885123456003', 'bottle', 40.00, 75.00, true, true, true, false, null, 20, 50),
        (v_profession_id, v_category_id, 'หน้ากากอนามัย 50 ชิ้น', 'หน้ากากผ่าตัด 3 ชั้น', 'MASK-50', '885123456004', 'box', 35.00, 65.00, true, true, true, false, null, 20, 100),
        (v_profession_id, v_category_id, 'วิตามินซี 1000mg', 'อาหารเสริมบำรุงภูมิคุ้มกัน', 'VITC-1000', '885123456005', 'bottle', 55.00, 120.00, true, true, true, true, 365, 10, 50)
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'Seeded sample products for profession %', v_profession_id;
END $$;

-- ============================================================
-- 3. Seed Loyalty Tiers
-- ============================================================
INSERT INTO public.loyalty_tiers (profession_id, tier_name, min_points, discount_pct, description, sort_order)
SELECT p.id, t.tier_name, t.min_points, t.discount_pct, t.description, t.sort_order
FROM public.professions p
CROSS JOIN LATERAL (VALUES
    ('Bronze', 0, 0, 'สมาชิกใหม่', 1),
    ('Silver', 500, 3, 'สะสม 500 คะแนน', 2),
    ('Gold', 1500, 5, 'สะสม 1,500 คะแนน', 3),
    ('Platinum', 5000, 10, 'สะสม 5,000 คะแนน — VIP', 4)
) AS t(tier_name, min_points, discount_pct, description, sort_order)
WHERE p.category = 'provider'
  AND NOT EXISTS (
    SELECT 1 FROM public.loyalty_tiers lt
    WHERE lt.profession_id = p.id AND lt.tier_name = t.tier_name
  )
ON CONFLICT DO NOTHING;

-- ============================================================
-- 4. Seed Warehouse Locations
-- ============================================================
DO $$
DECLARE
    v_profession_id UUID;
BEGIN
    SELECT id INTO v_profession_id
    FROM public.professions
    WHERE category = 'provider'
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.warehouse_locations (profession_id, location_code, location_name, location_type)
    VALUES
        (v_profession_id, 'A-01', 'ชั้นวางยาทั่วไป A1', 'shelf'),
        (v_profession_id, 'A-02', 'ชั้นวางยาทั่วไป A2', 'shelf'),
        (v_profession_id, 'B-01', 'ตู้เย็นยา B1', 'fridge'),
        (v_profession_id, 'C-01', 'เคาน์เตอร์หน้าร้าน', 'counter'),
        (v_profession_id, 'R-01', 'จุดรับสินค้า', 'receiving'),
        (v_profession_id, 'D-01', 'จุดจัดส่ง', 'dispatch')
    ON CONFLICT DO NOTHING;
END $$;

-- ============================================================
-- 5. Seed Suppliers
-- ============================================================
DO $$
DECLARE
    v_profession_id UUID;
BEGIN
    SELECT id INTO v_profession_id
    FROM public.professions
    WHERE category = 'provider'
    LIMIT 1;

    IF v_profession_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO public.suppliers (profession_id, supplier_name, contact_name, phone, email, address, tax_id, payment_terms, lead_time_days)
    VALUES
        (v_profession_id, 'บริษัท ยาดี จำกัด', 'คุณสมชาย ใจดี', '02-123-4567', 'sales@yadee.co.th', '123 ถนนสุขุมวิท กรุงเทพฯ 10110', '0105551000001', 'net_30', 7),
        (v_profession_id, 'บริษัท เวลเนส ซัพพลาย', 'คุณสุดา รักดี', '02-987-6543', 'order@wellnesssupply.co.th', '456 ถนนพระราม 9 กรุงเทพฯ 10310', '0105552000002', 'net_15', 5),
        (v_profession_id, 'บริษัท เมดิคอล โปร', 'คุณวิชัย เก่งกาจ', '02-555-7777', 'contact@medicalpro.co.th', '789 ถนนลาดพร้าว กรุงเทพฯ 10230', '0105553000003', 'cash', 3)
    ON CONFLICT DO NOTHING;
END $$;
