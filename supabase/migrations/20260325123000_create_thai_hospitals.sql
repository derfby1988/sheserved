-- Create table for Thai Hospitals and Health Centers (รพ., รพ.สต., etc.)
-- Combining data structured points from data.go.th, OD Mekong, and DLA transferred status
-- Prepared for future updates via API from NHSO (สปสช.)

CREATE TABLE IF NOT EXISTS public.thai_hospitals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hcode TEXT UNIQUE NOT NULL, -- รหัสสถานพยาบาล (H Code 5 หลัก หรือ 9 หลัก ของกระทรวงสาธารณสุข)
    name_th TEXT NOT NULL, -- ชื่อสถานพยาบาลภาษาไทย
    name_en TEXT, -- ชื่อสถานพยาบาลภาษาอังกฤษ 
    
    hospital_type TEXT, -- ประเภทโรงพยาบาล (เช่น รพ.ศูนย์, รพ.ทั่วไป, รพ.ชุมชน, รพ.สต., คลินิกเอกชน)
    bed_count INTEGER DEFAULT 0, -- จำนวนเตียง
    
    -- ข้อมูลสังกัด
    department TEXT, -- หน่วยงานต้นสังกัด (เช่น สำนักงานปลัดกระทรวงสาธารณสุข, กรมส่งเสริมการปกครองท้องถิ่น)
    ministry TEXT, -- กระทรวงต้นสังกัด (เช่น กระทรวงสาธารณสุข, กระทรวงมหาดไทย, กระทรวงกลาโหม)
    
    -- ข้อมูลการถ่ายโอน รพ.สต. (อ้างอิงแหล่งข้อมูล 3 DLA)
    is_transferred BOOLEAN DEFAULT false, -- สถานะว่าถ่ายโอนให้ อปท. หรือยัง
    transferred_to_name TEXT, -- โอนให้ที่ใด (เช่น อบจ.เชียงใหม่, สมุย, อบต...)
    
    -- ข้อมูลพิกัดทางภูมิศาสตร์จาก OD Mekong (แหล่งข้อมูล 2)
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    
    -- ข้อมูลที่ตั้ง
    address TEXT,
    province_id INTEGER, -- เชื่อมกับตาราง thai_provinces ถ้ามี
    district_id INTEGER, -- เชื่อมกับตาราง thai_districts
    subdistrict_id INTEGER, -- เชื่อมกับตาราง thai_subdistricts
    zip_code TEXT,
    phone TEXT,
    
    -- ข้อมูลระบบเพื่อใช้งาน สปสช. API ในอนาคต (แหล่งข้อมูล 4)
    api_raw_data JSONB, -- เก็บก้อนข้อมูลดิบที่ได้จาก API เผื่อ สปสช เพิ่มฟิลด์แปลกๆ มา
    last_sync_at TIMESTAMP WITH TIME ZONE, -- วันที่ sync ข้อมูลล่าสุดจาก API สปสช.
    
    is_active BOOLEAN DEFAULT true, -- เปิดให้บริการอยู่หรือไม่
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for fast searching by name and code
CREATE INDEX IF NOT EXISTS thai_hospitals_name_th_idx ON public.thai_hospitals(name_th);
CREATE INDEX IF NOT EXISTS thai_hospitals_hcode_idx ON public.thai_hospitals(hcode);
CREATE INDEX IF NOT EXISTS thai_hospitals_province_id_idx ON public.thai_hospitals(province_id);
CREATE INDEX IF NOT EXISTS thai_hospitals_hospital_type_idx ON public.thai_hospitals(hospital_type);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_thai_hospitals_updated_at()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_thai_hospitals_updated_at ON public.thai_hospitals;
CREATE TRIGGER tr_thai_hospitals_updated_at
BEFORE UPDATE ON public.thai_hospitals
FOR EACH ROW
EXECUTE FUNCTION update_thai_hospitals_updated_at();

-- ROW LEVEL SECURITY (RLS)
ALTER TABLE public.thai_hospitals ENABLE ROW LEVEL SECURITY;

-- 1. ทุกคนสามารถอ่านข้อมูลและค้นหาคลินิกได้แบบ Public
CREATE POLICY "Public selectable" 
ON public.thai_hospitals FOR SELECT 
TO public USING (true);

-- 2. อนุญาตให้ Insert / Update เฉพาะ authenticated หรือ public ถ้าคุณต้องการให้ระบบ backend / admin เรียกอัพเดตข้อมูล
CREATE POLICY "Insertable authenticated/admin" 
ON public.thai_hospitals FOR INSERT 
TO public WITH CHECK (true);

CREATE POLICY "Updatable authenticated/admin" 
ON public.thai_hospitals FOR UPDATE 
TO public USING (true) WITH CHECK (true);
