-- ========================================================================
-- Donation System - Complete Migration
-- ระบบรับบริจาคและการจัดการ พร้อม 2-Stage Approval Flow
-- ========================================================================

-- 1. หมวดหมู่การบริจาค
CREATE TABLE IF NOT EXISTS public.donation_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    name_en TEXT,
    icon_name TEXT,
    is_emergency BOOLEAN DEFAULT FALSE,
    display_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. คำร้องขอรับบริจาค
CREATE TABLE IF NOT EXISTS public.donation_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id),
    category_id UUID REFERENCES donation_categories(id),
    title TEXT NOT NULL,
    description TEXT,
    target_amount DECIMAL(12,2),
    current_amount DECIMAL(12,2) DEFAULT 0,
    image_url TEXT,
    is_trending BOOLEAN DEFAULT FALSE,
    status TEXT DEFAULT 'active',
    -- Approval Flow (2 stages)
    approval_status TEXT DEFAULT 'pending_local', -- pending_local -> pending_storage -> active / rejected
    storage_approved_by UUID REFERENCES public.users(id),
    local_verified_at TIMESTAMPTZ,
    local_leader_id UUID REFERENCES public.users(id),
    -- Step 2 Extended Fields
    needed_date TIMESTAMPTZ,
    usage_location TEXT,
    requester_address TEXT,
    community_id UUID, -- จะอ้างอิง communities table ด้านล่าง
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. ประวัติการบริจาค
CREATE TABLE IF NOT EXISTS public.donation_contributions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id),
    request_id UUID REFERENCES donation_requests(id) ON DELETE CASCADE,
    amount DECIMAL(12,2),
    quantity INT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. ชุมชน/พื้นที่ปกครอง (สำหรับ Local Leader Verification)
CREATE TABLE IF NOT EXISTS public.communities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    sub_district TEXT,
    district TEXT,
    province TEXT,
    leader_id UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- เชื่อมโยง FK community_id -> communities
ALTER TABLE public.donation_requests 
ADD CONSTRAINT fk_donation_requests_community 
FOREIGN KEY (community_id) REFERENCES public.communities(id);

-- 5. เพิ่มผู้นำชุมชนในระบบ user_categories (ถ้ายังไม่มี)
INSERT INTO public.user_categories (id, name, name_en, icon_name, display_order) VALUES
('leader', 'ผู้นำชุมชน', 'Local Leader', 'gavel', 2)
ON CONFLICT (id) DO NOTHING;

-- 6. เพิ่มอาชีพผู้นำชุมชน
INSERT INTO public.professions (id, name, name_en, description, icon_name, category, is_built_in, requires_verification, display_order, is_active) VALUES
('00000000-0000-0000-0000-000000000004', 'ผู้นำชุมชน', 'Local Leader', 'ผู้มีอำนาจปกครองและดูแลลูกบ้านในชุมชน', 'gavel', 'leader', true, true, 3, true)
ON CONFLICT (id) DO NOTHING;

-- 7. ข้อมูลเริ่มต้น (Seed Categories)
INSERT INTO public.donation_categories (name, name_en, icon_name, is_emergency, display_order) VALUES 
('อุบัติเหตุ', 'Accident', 'emergency_share', true, 0),
('อาชญากรรม', 'Crime', 'gavel', true, 1),
('ไฟไหม้', 'Fire', 'local_fire_department', true, 2),
('น้ำท่วม', 'Flood', 'water_damage', true, 3),
('เงิน', 'Money', 'payments', false, 4),
('สิ่งของ', 'Items', 'inventory_2', false, 5),
('อาหาร', 'Food', 'restaurant', false, 6),
('อวัยวะ', 'Organ', 'favorite', false, 7),
('ที่พัก', 'Shelter', 'home', false, 8),
('พาหนะ/ขอติดรถ', 'Transport', 'local_shipping', false, 9),
('ดูแลผู้สูงอายุ/ผู้ป่วย', 'Caregiving', 'elderly', false, 10)
ON CONFLICT DO NOTHING;

-- 8. RLS Policies
ALTER TABLE public.donation_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communities ENABLE ROW LEVEL SECURITY;

-- Everyone can read categories
CREATE POLICY "donation_categories_select_all" ON public.donation_categories
FOR SELECT USING (true);

-- All users can manage categories (ระบบ Auth ใช้ ServiceLocator ไม่ใช่ Supabase Auth โดยตรง)
CREATE POLICY "donation_categories_insert_all" ON public.donation_categories
FOR INSERT WITH CHECK (true);

CREATE POLICY "donation_categories_update_all" ON public.donation_categories
FOR UPDATE USING (true);

CREATE POLICY "donation_categories_delete_all" ON public.donation_categories
FOR DELETE USING (true);

-- Everyone can read active requests
CREATE POLICY "donation_requests_select_all" ON public.donation_requests
FOR SELECT USING (true);

-- All users can create/update requests
CREATE POLICY "donation_requests_insert_all" ON public.donation_requests
FOR INSERT WITH CHECK (true);

CREATE POLICY "donation_requests_update_all" ON public.donation_requests
FOR UPDATE USING (true);

CREATE POLICY "donation_requests_delete_all" ON public.donation_requests
FOR DELETE USING (true);

-- Contributions
CREATE POLICY "donation_contributions_select_all" ON public.donation_contributions
FOR SELECT USING (true);

CREATE POLICY "donation_contributions_insert_all" ON public.donation_contributions
FOR INSERT WITH CHECK (true);

-- Communities
CREATE POLICY "communities_select_all" ON public.communities
FOR SELECT USING (true);

CREATE POLICY "communities_manage_all" ON public.communities
FOR ALL USING (true);

-- 9. Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.donation_categories;
ALTER PUBLICATION supabase_realtime ADD TABLE public.donation_requests;
