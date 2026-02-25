-- =====================================================
-- Migration: Create consultation_packages table
-- วันที่: 2026-02-25
-- =====================================================

-- Enable UUID extension (ถ้ายังไม่ได้เปิด)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- สร้างตาราง consultation_packages
CREATE TABLE IF NOT EXISTS public.consultation_packages (
  id TEXT PRIMARY KEY DEFAULT 'pkg_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
  name TEXT NOT NULL,
  short_name TEXT NOT NULL,
  description TEXT DEFAULT '',
  price NUMERIC(10, 2) NOT NULL DEFAULT 0.0,
  includes_ai BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  expert_groups JSONB DEFAULT '[]',  -- รายการกลุ่มผู้เชี่ยวชาญ
  display_order INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index สำหรับการ query
CREATE INDEX IF NOT EXISTS idx_consultation_packages_is_active ON public.consultation_packages(is_active);
CREATE INDEX IF NOT EXISTS idx_consultation_packages_display_order ON public.consultation_packages(display_order);

-- Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION update_consultation_packages_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_consultation_packages_updated_at ON public.consultation_packages;
CREATE TRIGGER trg_consultation_packages_updated_at
  BEFORE UPDATE ON public.consultation_packages
  FOR EACH ROW EXECUTE FUNCTION update_consultation_packages_updated_at();

-- Enable Row Level Security
ALTER TABLE public.consultation_packages ENABLE ROW LEVEL SECURITY;

-- Policy: ทุกคนอ่านได้ (เฉพาะ active)
DROP POLICY IF EXISTS "Public read active packages" ON public.consultation_packages;
CREATE POLICY "Public read active packages"
ON public.consultation_packages FOR SELECT
USING (is_active = true);

-- Policy: Admin จัดการได้ทั้งหมด (รวม inactive)
-- หมายเหตุ: ในระบบจริงควรเพิ่มการตรวจสอบ role ของ admin
DROP POLICY IF EXISTS "Service role manage packages" ON public.consultation_packages;
CREATE POLICY "Service role manage packages"
ON public.consultation_packages FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Policy: ทั้ง Authenticated และ Anonymous จัดการได้ (สำหรับช่วงพัฒนา)
DROP POLICY IF EXISTS "Manage packages for all" ON public.consultation_packages;
CREATE POLICY "Manage packages for all"
ON public.consultation_packages FOR ALL
USING (true)
WITH CHECK (true);

-- ─── Seed initial data ─────────────────────────────────────────────────────────
INSERT INTO public.consultation_packages (id, name, short_name, description, price, includes_ai, is_active, display_order, expert_groups)
VALUES 
  (
    'pkg_001',
    'แพ็คเกจ ปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์ + AI',
    'อาจารย์หมอ + AI',
    'รับผลวิเคราะห์เบื้องต้นจาก Vega AI ก่อนพบอาจารย์หมอ',
    3290.0, true, true, 0,
    '[{"id": "eg_001", "name": "อาจารย์แพทย์", "role": "professor", "maxExperts": 1, "isRequired": true},
      {"id": "eg_002", "name": "แพทย์ผู้ช่วย", "role": "doctor", "maxExperts": 2, "isRequired": false}]'::jsonb
  ),
  (
    'pkg_002',
    'แพ็คเกจ สำหรับปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์',
    'อาจารย์หมอ',
    'ปรึกษาโดยตรงกับอาจารย์แพทย์ผู้เชี่ยวชาญ',
    2990.0, false, true, 1,
    '[{"id": "eg_003", "name": "อาจารย์แพทย์", "role": "professor", "maxExperts": 1, "isRequired": true}]'::jsonb
  ),
  (
    'pkg_003',
    'แพ็คเกจ สำหรับปรึกษาแพทย์เฉพาะทาง',
    'หมอเฉพาะทาง',
    'ปรึกษาแพทย์เฉพาะทางตามอาการที่ระบุ',
    799.0, false, true, 2,
    '[{"id": "eg_004", "name": "แพทย์เฉพาะทาง", "role": "specialist", "maxExperts": 1, "isRequired": true}]'::jsonb
  ),
  (
    'pkg_004',
    'แพ็คเกจ สำหรับปรึกษาแพทย์ทั่วไป/เภสัช',
    'หมอ/เภสัช',
    'ปรึกษาแพทย์ทั่วไปหรือเภสัชกร',
    299.0, false, true, 3,
    '[{"id": "eg_005", "name": "แพทย์ทั่วไป", "role": "doctor", "maxExperts": 2, "isRequired": false},
      {"id": "eg_006", "name": "เภสัชกร", "role": "pharmacist", "maxExperts": 2, "isRequired": false}]'::jsonb
  )
ON CONFLICT (id) DO NOTHING;
