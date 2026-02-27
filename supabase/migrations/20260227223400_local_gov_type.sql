-- ====================================================================
-- เพิ่มคอลัมน์ local_gov_type + ตาราง community_leader_roles
-- ====================================================================

-- 1. เพิ่มคอลัมน์ประเภทการปกครองท้องถิ่น
ALTER TABLE public.thai_addresses 
ADD COLUMN IF NOT EXISTS local_gov_type VARCHAR(30) DEFAULT 'sao';

-- 2. สร้างตาราง Reference: ตำแหน่งผู้นำตามรูปแบบ
CREATE TABLE IF NOT EXISTS public.community_leader_roles (
  local_gov_type VARCHAR(30) PRIMARY KEY,
  gov_type_name_th VARCHAR(100) NOT NULL, -- ชื่อรูปแบบ (ไทย)
  gov_type_name_en VARCHAR(100),          -- ชื่อรูปแบบ (อังกฤษ)
  leader_title_th VARCHAR(100) NOT NULL,  -- ตำแหน่งผู้นำ (ไทย)
  leader_title_en VARCHAR(100),           -- ตำแหน่งผู้นำ (อังกฤษ)
  has_village_head BOOLEAN DEFAULT false,  -- มีผู้ใหญ่บ้าน?
  has_kamnan BOOLEAN DEFAULT false         -- มีกำนัน?
);

INSERT INTO public.community_leader_roles VALUES
('sao',            'องค์การบริหารส่วนตำบล',  'Sub-district Administrative Organization', 'ผู้ใหญ่บ้าน / กำนัน',       'Village Head / Sub-district Head', true,  true),
('municipality_t', 'เทศบาลตำบล',            'Sub-district Municipality',                'ผู้ใหญ่บ้าน / กำนัน',       'Village Head / Sub-district Head', true,  true),
('municipality_m', 'เทศบาลเมือง',           'Town Municipality',                         'ประธานชุมชน',              'Community President',              false, false),
('municipality_n', 'เทศบาลนคร',            'City Municipality',                          'ประธานชุมชน',              'Community President',              false, false),
('bma',            'กรุงเทพมหานคร',         'Bangkok Metropolitan Administration',        'ประธานชุมชน / หัวหน้าเขต',  'Community President / District Chief', false, false),
('pattaya',        'เมืองพัทยา',            'Pattaya City',                               'ประธานชุมชน',              'Community President',              false, false)
ON CONFLICT (local_gov_type) DO NOTHING;

-- RLS
ALTER TABLE public.community_leader_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Community leader roles are viewable by everyone"
  ON public.community_leader_roles FOR SELECT USING (true);

-- Index
CREATE INDEX IF NOT EXISTS idx_thai_addresses_local_gov ON public.thai_addresses(local_gov_type);

COMMENT ON COLUMN public.thai_addresses.local_gov_type IS 'ประเภทการปกครองท้องถิ่น: sao, municipality_t, municipality_m, municipality_n, bma, pattaya';
