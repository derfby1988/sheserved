-- =====================================================
-- Thai Addresses - ข้อมูลที่อยู่ไทยสำหรับ Autocomplete
-- รองรับ: รหัสไปรษณีย์ → จังหวัด → อำเภอ → ตำบล
-- =====================================================

CREATE TABLE IF NOT EXISTS public.thai_addresses (
  id SERIAL PRIMARY KEY,
  postal_code VARCHAR(5) NOT NULL,
  province VARCHAR(100) NOT NULL,     -- จังหวัด
  district VARCHAR(100) NOT NULL,     -- อำเภอ/เขต
  sub_district VARCHAR(100) NOT NULL  -- ตำบล/แขวง
);

-- Indexes สำหรับ Query Performance
CREATE INDEX idx_thai_addresses_postal_code ON public.thai_addresses(postal_code);
CREATE INDEX idx_thai_addresses_province ON public.thai_addresses(province);
CREATE INDEX idx_thai_addresses_district ON public.thai_addresses(district);
CREATE INDEX idx_thai_addresses_composite ON public.thai_addresses(postal_code, province, district);

-- RLS: อนุญาตให้ทุกคนอ่านได้ (ข้อมูลสาธารณะ)
ALTER TABLE public.thai_addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Thai addresses are viewable by everyone"
  ON public.thai_addresses FOR SELECT USING (true);

-- Comment
COMMENT ON TABLE public.thai_addresses IS 'ข้อมูลที่อยู่ไทยทั่วประเทศ สำหรับ Cascading Address Picker';
