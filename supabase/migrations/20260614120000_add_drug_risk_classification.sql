-- Migration: Add Drug Risk Classification tables and permissions
-- Date: 2026-06-14

-- 1. Add can_manage_drug_risk to professions
ALTER TABLE professions
    ADD COLUMN IF NOT EXISTS can_manage_drug_risk BOOLEAN DEFAULT false;

-- 2. Add custom_risk_level to custom_medications
ALTER TABLE custom_medications
    ADD COLUMN IF NOT EXISTS custom_risk_level TEXT
    CHECK (custom_risk_level IN ('low', 'medium', 'high', 'very_high', 'prohibited'));

-- 3. Add dangerous_sub_category to medications
ALTER TABLE medications
    ADD COLUMN IF NOT EXISTS dangerous_sub_category TEXT;

-- 4. Create dangerous_drug_subcategories master table
CREATE TABLE IF NOT EXISTS dangerous_drug_subcategories (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            TEXT NOT NULL UNIQUE,
    name_th         TEXT NOT NULL,
    name_en         TEXT,
    description     TEXT,
    is_telemedicine_prohibited BOOLEAN DEFAULT false,
    sort_order      INTEGER DEFAULT 0,
    is_active       BOOLEAN DEFAULT true,
    deleted_at      TIMESTAMPTZ,          -- Soft delete timestamp
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_dangerous_drug_subcategories_updated_at ON dangerous_drug_subcategories;
CREATE TRIGGER trg_dangerous_drug_subcategories_updated_at
    BEFORE UPDATE ON dangerous_drug_subcategories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 5. Create custom_risk_levels master table
CREATE TABLE IF NOT EXISTS custom_risk_levels (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            TEXT NOT NULL UNIQUE,
    name_th         TEXT NOT NULL,
    name_en         TEXT,
    description     TEXT,
    is_telemedicine_prohibited BOOLEAN DEFAULT false,
    sort_order      INTEGER DEFAULT 0,
    is_active       BOOLEAN DEFAULT true,
    deleted_at      TIMESTAMPTZ,          -- Soft delete timestamp
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_custom_risk_levels_updated_at ON custom_risk_levels;
CREATE TRIGGER trg_custom_risk_levels_updated_at
    BEFORE UPDATE ON custom_risk_levels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 6. Create medication_risk_override_logs audit table
CREATE TABLE IF NOT EXISTS medication_risk_override_logs (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    medication_id         UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
    old_fda_risk_status   TEXT,
    new_fda_risk_status   TEXT,
    old_sub_category      TEXT,
    new_sub_category      TEXT,
    reason                TEXT NOT NULL,
    overridden_by         UUID REFERENCES users(id),
    created_at            TIMESTAMPTZ DEFAULT now()
);

-- 7. Seed default dangerous drug subcategories
INSERT INTO dangerous_drug_subcategories (code, name_th, name_en, is_telemedicine_prohibited, sort_order) VALUES
    ('hormone_injection', 'ฮอร์โมนฉีด', 'Hormone Injection', true, 1),
    ('chemotherapy', 'ยาเคมีบำบัด', 'Chemotherapy', true, 2),
    ('abortifacient', 'ยาขับเลือด/ยาทำแท้ง', 'Abortifacient', true, 3),
    ('antibiotic_injection', 'ยาปฏิชีวนะฉีด', 'Antibiotic Injection', false, 4),
    ('contrast_media', 'สารทึบรังสี', 'Contrast Media', false, 5)
ON CONFLICT (code) DO NOTHING;

-- 8. Seed default custom risk levels
INSERT INTO custom_risk_levels (code, name_th, name_en, is_telemedicine_prohibited, sort_order) VALUES
    ('low', 'ความเสี่ยงต่ำ', 'Low Risk', false, 1),
    ('medium', 'ความเสี่ยงปานกลาง', 'Medium Risk', false, 2),
    ('high', 'ความเสี่ยงสูง', 'High Risk', true, 3),
    ('very_high', 'ความเสี่ยงสูงมาก', 'Very High Risk', true, 4),
    ('prohibited', 'ห้ามใช้', 'Prohibited', true, 5)
ON CONFLICT (code) DO NOTHING;

-- 9. Update built-in professions to have can_manage_drug_risk
UPDATE professions
    SET can_manage_drug_risk = true
    WHERE id IN (
        '00000000-0000-0000-0000-000000000002', -- expert
        '00000000-0000-0000-0000-000000000003'  -- clinic
    );

-- 10. Create drug_risk_admin_logs audit table (for master table CRUD)
CREATE TABLE IF NOT EXISTS drug_risk_admin_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name      TEXT NOT NULL,          -- 'dangerous_drug_subcategories' | 'custom_risk_levels'
    record_id       UUID NOT NULL,
    action          TEXT NOT NULL,           -- 'create' | 'update' | 'soft_delete' | 'reactivate' | 'reset_seed'
    old_data        JSONB,
    new_data        JSONB,
    performed_by    UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- 11. RLS (Enable but allow all — controlled at Application Layer per auth guidelines)
ALTER TABLE dangerous_drug_subcategories ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_risk_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_risk_override_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE drug_risk_admin_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "dangerous_drug_subcategories_select" ON dangerous_drug_subcategories FOR SELECT USING (true);
CREATE POLICY "dangerous_drug_subcategories_modify" ON dangerous_drug_subcategories FOR ALL USING (true);
CREATE POLICY "custom_risk_levels_select" ON custom_risk_levels FOR SELECT USING (true);
CREATE POLICY "custom_risk_levels_modify" ON custom_risk_levels FOR ALL USING (true);
CREATE POLICY "medication_risk_override_logs_select" ON medication_risk_override_logs FOR SELECT USING (true);
CREATE POLICY "medication_risk_override_logs_modify" ON medication_risk_override_logs FOR ALL USING (true);
CREATE POLICY "drug_risk_admin_logs_select" ON drug_risk_admin_logs FOR SELECT USING (true);
CREATE POLICY "drug_risk_admin_logs_modify" ON drug_risk_admin_logs FOR ALL USING (true);
