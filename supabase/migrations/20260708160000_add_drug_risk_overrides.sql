-- Migration: Add Drug Risk Overrides, Override History, and RPC Function
-- Date: 2026-07-09
-- Plan: DRUG_RISK_OVERRIDE_PLAN v3.0

-- ============================================================
-- 1. Create drug_risk_overrides table
-- ============================================================
CREATE TABLE IF NOT EXISTS drug_risk_overrides (
    id                                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Scope: ต้องมีอย่างน้อย 1 (แต่ไม่ต้องมีทั้งคู่)
    user_id                             UUID REFERENCES users(id) ON DELETE CASCADE,
    profession_id                       UUID REFERENCES professions(id) ON DELETE CASCADE,
    medication_id                       UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,

    -- Override fields (null = ใช้ค่า tier ที่ต่ำกว่า)
    override_fda_risk_status            TEXT CHECK (override_fda_risk_status IN ('ND', 'D', 'S', 'N', 'P')),
    override_sub_category               TEXT,
    override_custom_risk_code           TEXT,
    override_is_telemedicine_prohibited BOOLEAN,
    override_notes                      TEXT,

    -- Traceability — ON DELETE SET NULL เพื่อไม่ให้ค่า Override หายเมื่อลบ User
    last_modified_by                    UUID REFERENCES users(id) ON DELETE SET NULL,
    last_modified_at                    TIMESTAMPTZ DEFAULT now(),
    created_by                          UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at                          TIMESTAMPTZ DEFAULT now(),

    CONSTRAINT chk_scope_required CHECK (user_id IS NOT NULL OR profession_id IS NOT NULL)
);

-- Partial Unique Indexes (รองรับ Postgres ทุกเวอร์ชัน)
CREATE UNIQUE INDEX IF NOT EXISTS idx_dro_user_medication
    ON drug_risk_overrides (user_id, medication_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_dro_profession_medication
    ON drug_risk_overrides (profession_id, medication_id) WHERE profession_id IS NOT NULL;

-- Query Indexes
CREATE INDEX IF NOT EXISTS idx_dro_user       ON drug_risk_overrides(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_dro_profession ON drug_risk_overrides(profession_id) WHERE profession_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_dro_medication ON drug_risk_overrides(medication_id);

-- ============================================================
-- 2. Create drug_risk_override_history table (รองรับทั้ง Org และ Personal)
-- ============================================================
CREATE TABLE IF NOT EXISTS drug_risk_override_history (
    id                                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    override_id                         UUID REFERENCES drug_risk_overrides(id) ON DELETE SET NULL,

    -- Scope: รองรับทั้ง Org และ Personal history
    profession_id                       UUID REFERENCES professions(id),  -- nullable สำหรับ Personal
    user_id                             UUID REFERENCES users(id),        -- nullable สำหรับ Org
    medication_id                       UUID NOT NULL REFERENCES medications(id),

    -- Snapshot ค่าก่อน/หลัง
    fda_risk_status_before              TEXT,
    fda_risk_status_after               TEXT,
    sub_category_before                 TEXT,
    sub_category_after                  TEXT,
    custom_risk_code_before             TEXT,
    custom_risk_code_after              TEXT,
    is_telemedicine_prohibited_before   BOOLEAN,
    is_telemedicine_prohibited_after    BOOLEAN,
    notes_before                        TEXT,
    notes_after                         TEXT,

    -- Audit
    action                              TEXT NOT NULL CHECK (action IN ('create', 'update', 'delete')),
    changed_by                          UUID REFERENCES users(id) ON DELETE SET NULL,
    changed_by_name                     TEXT NOT NULL, -- Text Snapshot ชื่อจริงของผู้แก้ ณ เวลานั้น
    changed_at                          TIMESTAMPTZ DEFAULT now(),
    change_reason                       TEXT,

    CONSTRAINT chk_history_scope CHECK (profession_id IS NOT NULL OR user_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_droh_profession ON drug_risk_override_history(profession_id) WHERE profession_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_droh_user       ON drug_risk_override_history(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_droh_medication ON drug_risk_override_history(medication_id);
CREATE INDEX IF NOT EXISTS idx_droh_changed_at ON drug_risk_override_history(changed_at DESC);

-- ============================================================
-- 3. RPC Function: resolve_effective_modifier (แก้ N+1 Query)
-- ============================================================
CREATE OR REPLACE FUNCTION resolve_effective_modifier(
    p_medication_id UUID,
    p_profession_id UUID DEFAULT NULL,
    p_user_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_override RECORD;
    v_modifier RECORD;
BEGIN
    -- 1. ดึง Override ที่ active
    SELECT dro.last_modified_by, dro.last_modified_at
    INTO v_override
    FROM drug_risk_overrides dro
    WHERE dro.medication_id = p_medication_id
      AND (
        (p_profession_id IS NOT NULL AND dro.profession_id = p_profession_id)
        OR (p_user_id IS NOT NULL AND dro.user_id = p_user_id)
      )
    LIMIT 1;

    -- ไม่มี Override → ใช้ค่าเริ่มต้น
    IF v_override IS NULL THEN
        RETURN json_build_object(
            'name', 'Sheserved Default',
            'status', 'no_override'
        );
    END IF;

    -- 2. ตรวจสอบ User ล่าสุด
    IF v_override.last_modified_by IS NOT NULL THEN
        SELECT u.id, u.name, u.is_active, p.can_manage_drug_risk
        INTO v_modifier
        FROM users u
        LEFT JOIN professions p ON u.profession_id = p.id
        WHERE u.id = v_override.last_modified_by;

        IF v_modifier IS NOT NULL AND v_modifier.is_active = true
           AND v_modifier.can_manage_drug_risk = true THEN
            RETURN json_build_object(
                'id', v_modifier.id,
                'name', v_modifier.name,
                'status', 'active',
                'modified_at', v_override.last_modified_at
            );
        END IF;
    END IF;

    -- 3. ค้นประวัติย้อนหลัง — Single JOIN query แทนวนลูป
    SELECT h.changed_by, h.changed_by_name, u.id AS uid, u.name AS uname,
           u.is_active, p.can_manage_drug_risk
    INTO v_modifier
    FROM drug_risk_override_history h
    JOIN users u ON u.id = h.changed_by
    LEFT JOIN professions p ON u.profession_id = p.id
    WHERE h.medication_id = p_medication_id
      AND (
        (p_profession_id IS NOT NULL AND h.profession_id = p_profession_id)
        OR (p_user_id IS NOT NULL AND h.user_id = p_user_id)
      )
      AND u.is_active = true
      AND p.can_manage_drug_risk = true
    ORDER BY h.changed_at DESC
    LIMIT 1;

    IF v_modifier IS NOT NULL THEN
        RETURN json_build_object(
            'id', v_modifier.uid,
            'name', v_modifier.uname,
            'status', 'fallback_history',
            'snapshot_name', v_modifier.changed_by_name
        );
    END IF;

    -- 4. Fallback → System Admin
    RETURN json_build_object(
        'name', 'System Admin',
        'status', 'fallback_system'
    );
END;
$$;

-- ============================================================
-- 4. Alter drug_risk_admin_logs
-- ============================================================
ALTER TABLE drug_risk_admin_logs
    ADD COLUMN IF NOT EXISTS override_user_id UUID REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS override_profession_id UUID REFERENCES professions(id),
    ADD COLUMN IF NOT EXISTS override_context TEXT DEFAULT 'global'
        CHECK (override_context IN ('global', 'organization', 'personal'));

-- ============================================================
-- 5. Enable RLS (access control delegated to Application Layer)
-- หมายเหตุ: ระบบใช้ custom AuthService (ไม่ใช่ Supabase Auth)
-- จึงใช้ USING (true) เหมือนตารางอื่นๆ ในโปรเจกต์
-- การควบคุมสิทธิ์ทำที่ Dart Repository layer ผ่าน AuthService.instance.currentUser
-- ============================================================
ALTER TABLE drug_risk_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE drug_risk_override_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "drug_risk_overrides_select" ON drug_risk_overrides;
CREATE POLICY "drug_risk_overrides_select" ON drug_risk_overrides FOR SELECT USING (true);

DROP POLICY IF EXISTS "drug_risk_overrides_modify" ON drug_risk_overrides;
CREATE POLICY "drug_risk_overrides_modify" ON drug_risk_overrides FOR ALL USING (true);

DROP POLICY IF EXISTS "drug_risk_override_history_select" ON drug_risk_override_history;
CREATE POLICY "drug_risk_override_history_select" ON drug_risk_override_history FOR SELECT USING (true);

DROP POLICY IF EXISTS "drug_risk_override_history_modify" ON drug_risk_override_history;
CREATE POLICY "drug_risk_override_history_modify" ON drug_risk_override_history FOR ALL USING (true);
