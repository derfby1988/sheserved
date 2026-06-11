-- Migration: ERP Phase 4 — Clinical & Advanced
-- Date: 2026-06-11
-- Prerequisites: Phase 3 complete (orders, payments, employees, GL)

-- ============================================================
-- 1. HIS CORE — EMR, OPD
-- ============================================================

-- 1.1 EMR Records (Electronic Medical Records)
CREATE TABLE IF NOT EXISTS public.emr_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    record_number   TEXT NOT NULL,                          -- HN-2026-0001
    record_type     TEXT NOT NULL DEFAULT 'general'
                        CHECK (record_type IN ('general', 'allergy', 'chronic', 'surgical', 'family_history')),
    chief_complaint TEXT,
    history_of_present_illness TEXT,
    physical_exam   TEXT,
    assessment      TEXT,
    plan            TEXT,
    icd10_code      TEXT,                                   -- รหัสโรค ICD-10
    icd10_name      TEXT,
    attachments     JSONB DEFAULT '[]',                     -- array of {url, type, description}
    created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_emr_profession
    ON public.emr_records(profession_id, patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_emr_patient
    ON public.emr_records(patient_id, record_type, created_at DESC);

DROP TRIGGER IF EXISTS trg_emr_updated_at ON public.emr_records;
CREATE TRIGGER trg_emr_updated_at
    BEFORE UPDATE ON public.emr_records
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.2 OPD Visits (Outpatient Department)
CREATE TABLE IF NOT EXISTS public.opd_visits (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    emr_record_id   UUID REFERENCES public.emr_records(id) ON DELETE SET NULL,
    doctor_id       UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    visit_number    TEXT NOT NULL,
    visit_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    chief_complaint TEXT,
    diagnosis       TEXT,
    treatment       TEXT,
    follow_up_date  DATE,
    status          TEXT NOT NULL DEFAULT 'checked_in'
                        CHECK (status IN ('checked_in', 'in_consultation', 'completed', 'cancelled', 'no_show')),
    queue_number    INTEGER,
    is_walk_in      BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_opd_profession
    ON public.opd_visits(profession_id, visit_date DESC, status);
CREATE INDEX IF NOT EXISTS idx_opd_patient
    ON public.opd_visits(patient_id, visit_date DESC);
CREATE INDEX IF NOT EXISTS idx_opd_doctor
    ON public.opd_visits(doctor_id, visit_date)
    WHERE status IN ('checked_in', 'in_consultation');

DROP TRIGGER IF EXISTS trg_opd_updated_at ON public.opd_visits;
CREATE TRIGGER trg_opd_updated_at
    BEFORE UPDATE ON public.opd_visits
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.3 Medical Prescriptions (ERP HIS)
CREATE TABLE IF NOT EXISTS public.medical_prescriptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    emr_record_id   UUID REFERENCES public.emr_records(id) ON DELETE SET NULL,
    opd_visit_id    UUID REFERENCES public.opd_visits(id) ON DELETE SET NULL,
    doctor_id       UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    prescription_number TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'confirmed', 'dispensed', 'partially_dispensed', 'cancelled')),
    total_amount    DECIMAL(12,2) DEFAULT 0,
    instructions    TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_medical_prescriptions_profession
    ON public.medical_prescriptions(profession_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_medical_prescriptions_patient
    ON public.medical_prescriptions(patient_id, status);

DROP TRIGGER IF EXISTS trg_medical_prescriptions_updated_at ON public.medical_prescriptions;
CREATE TRIGGER trg_medical_prescriptions_updated_at
    BEFORE UPDATE ON public.medical_prescriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.4 Medical Prescription Items
CREATE TABLE IF NOT EXISTS public.medical_prescription_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prescription_id UUID NOT NULL REFERENCES public.medical_prescriptions(id) ON DELETE CASCADE,
    product_id      UUID REFERENCES public.products(id) ON DELETE SET NULL,
    item_name       TEXT NOT NULL,
    dosage          TEXT,                                   -- 1 tablet, 2 capsules, etc.
    frequency       TEXT,                                   -- TID, BID, QD, PRN
    duration        TEXT,                                   -- 7 days, 14 days
    route           TEXT DEFAULT 'oral'                     -- oral, iv, im, topical, etc.
                        CHECK (route IN ('oral', 'iv', 'im', 'sc', 'topical', 'inhalation', 'rectal', 'ophthalmic')),
    quantity        INTEGER NOT NULL DEFAULT 1,
    unit_price      DECIMAL(12,2) DEFAULT 0,
    line_total      DECIMAL(12,2) DEFAULT 0,
    is_dispensed    BOOLEAN DEFAULT false,
    dispensed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_medical_prescription_items_prescription
    ON public.medical_prescription_items(prescription_id);

-- 1.5 Vitals (สัญญาณชีพ)
CREATE TABLE IF NOT EXISTS public.vitals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    emr_record_id   UUID REFERENCES public.emr_records(id) ON DELETE CASCADE,
    opd_visit_id    UUID REFERENCES public.opd_visits(id) ON DELETE SET NULL,
    recorded_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    temperature     DECIMAL(4,1),                           -- Celsius
    blood_pressure_systolic INTEGER,
    blood_pressure_diastolic INTEGER,
    heart_rate      INTEGER,                                -- bpm
    respiratory_rate INTEGER,                               -- breaths/min
    oxygen_saturation INTEGER,                              -- %
    weight_kg       DECIMAL(5,2),
    height_cm       DECIMAL(5,2),
    bmi             DECIMAL(5,2),
    blood_glucose   DECIMAL(5,2),
    pain_score      INTEGER CHECK (pain_score BETWEEN 0 AND 10),
    notes           TEXT,
    recorded_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vitals_patient
    ON public.vitals(patient_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_vitals_profession
    ON public.vitals(profession_id, recorded_at DESC);

-- ============================================================
-- 2. LIS CORE — Lab Tests & Results
-- ============================================================

-- 2.1 Lab Tests (catalog)
CREATE TABLE IF NOT EXISTS public.lab_tests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    test_code       TEXT NOT NULL,
    test_name       TEXT NOT NULL,
    test_category   TEXT NOT NULL DEFAULT 'blood'
                        CHECK (test_category IN ('blood', 'urine', 'stool', 'imaging', 'microbiology', 'pathology', 'genetic')),
    reference_range TEXT,
    unit            TEXT,
    price           DECIMAL(12,2) DEFAULT 0,
    turnaround_hours INTEGER DEFAULT 24,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lab_tests_profession
    ON public.lab_tests(profession_id, test_category, is_active);

DROP TRIGGER IF EXISTS trg_lab_tests_updated_at ON public.lab_tests;
CREATE TRIGGER trg_lab_tests_updated_at
    BEFORE UPDATE ON public.lab_tests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2.2 Lab Results
CREATE TABLE IF NOT EXISTS public.lab_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    emr_record_id   UUID REFERENCES public.emr_records(id) ON DELETE SET NULL,
    lab_test_id     UUID NOT NULL REFERENCES public.lab_tests(id) ON DELETE RESTRICT,
    result_value    TEXT NOT NULL,                          -- ผลลัพธ์ (อาจเป็นตัวเลขหรือข้อความ)
    numeric_value   DECIMAL(12,4),                          -- ถ้าเป็นตัวเลข
    unit            TEXT,
    reference_range TEXT,
    is_abnormal     BOOLEAN DEFAULT false,
    is_critical     BOOLEAN DEFAULT false,                  -- critical value ต้องแจ้งด่วน
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'processing', 'completed', 'verified', 'cancelled')),
    verified_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    verified_at     TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lab_results_profession
    ON public.lab_results(profession_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lab_results_patient
    ON public.lab_results(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lab_results_critical
    ON public.lab_results(profession_id, is_critical, status)
    WHERE is_critical = true AND status IN ('pending', 'completed');

DROP TRIGGER IF EXISTS trg_lab_results_updated_at ON public.lab_results;
CREATE TRIGGER trg_lab_results_updated_at
    BEFORE UPDATE ON public.lab_results
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2.3 Lab External Requests (ส่งตรวจภายนอก)
CREATE TABLE IF NOT EXISTS public.lab_external_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    lab_test_id     UUID NOT NULL REFERENCES public.lab_tests(id) ON DELETE RESTRICT,
    external_lab    TEXT NOT NULL,                          -- ชื่อห้องแล็บภายนอก
    request_number  TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'requested'
                        CHECK (status IN ('requested', 'sample_collected', 'sent', 'received', 'result_received', 'cancelled')),
    specimen_type   TEXT,
    collected_at    TIMESTAMPTZ,
    sent_at         TIMESTAMPTZ,
    result_received_at TIMESTAMPTZ,
    external_result JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lab_external_profession
    ON public.lab_external_requests(profession_id, status, created_at DESC);

DROP TRIGGER IF EXISTS trg_lab_external_updated_at ON public.lab_external_requests;
CREATE TRIGGER trg_lab_external_updated_at
    BEFORE UPDATE ON public.lab_external_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. TELEMEDICINE (leverages existing consultation_requests + chat_rooms)
-- ============================================================

-- 3.1 Teleconsultations (extends existing consultation_requests)
CREATE TABLE IF NOT EXISTS public.tele_consultations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    doctor_id       UUID REFERENCES public.employees(id) ON DELETE SET NULL,
    consultation_request_id UUID REFERENCES public.consultation_requests(id) ON DELETE SET NULL,
    status          TEXT NOT NULL DEFAULT 'scheduled'
                        CHECK (status IN ('scheduled', 'in_progress', 'completed', 'cancelled', 'no_show')),
    scheduled_at    TIMESTAMPTZ,
    started_at      TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ,
    duration_minutes INTEGER,
    chief_complaint TEXT,
    diagnosis       TEXT,
    treatment_plan  TEXT,
    follow_up_required BOOLEAN DEFAULT false,
    follow_up_date  DATE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tele_profession
    ON public.tele_consultations(profession_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_tele_patient
    ON public.tele_consultations(patient_id, scheduled_at DESC);

DROP TRIGGER IF EXISTS trg_tele_updated_at ON public.tele_consultations;
CREATE TRIGGER trg_tele_updated_at
    BEFORE UPDATE ON public.tele_consultations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. CDP CORE — Customer Cohorts & Analytics
-- ============================================================

-- 4.1 Customer Cohorts
CREATE TABLE IF NOT EXISTS public.customer_cohorts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    cohort_name     TEXT NOT NULL,
    cohort_type     TEXT NOT NULL DEFAULT 'custom'
                        CHECK (cohort_type IN ('age_group', 'condition', 'visit_frequency', 'custom')),
    description     TEXT,
    criteria        JSONB DEFAULT '{}',                     -- {min_age: 30, max_age: 50, conditions: ['diabetes']}
    is_auto_sync    BOOLEAN DEFAULT false,                  -- auto-update members
    member_count    INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cohorts_profession
    ON public.customer_cohorts(profession_id, cohort_type);

DROP TRIGGER IF EXISTS trg_cohorts_updated_at ON public.customer_cohorts;
CREATE TRIGGER trg_cohorts_updated_at
    BEFORE UPDATE ON public.customer_cohorts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4.2 Cohort Members
CREATE TABLE IF NOT EXISTS public.cohort_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cohort_id       UUID NOT NULL REFERENCES public.customer_cohorts(id) ON DELETE CASCADE,
    patient_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    added_reason    TEXT,
    added_at        TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (cohort_id, patient_id)
);

CREATE INDEX IF NOT EXISTS idx_cohort_members_cohort
    ON public.cohort_members(cohort_id);
CREATE INDEX IF NOT EXISTS idx_cohort_members_patient
    ON public.cohort_members(patient_id);

-- 4.3 Analytics Events (event tracking for CDP)
CREATE TABLE IF NOT EXISTS public.analytics_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    patient_id      UUID REFERENCES public.users(id) ON DELETE SET NULL,
    event_type      TEXT NOT NULL,                          -- page_view, purchase, appointment, etc.
    event_name      TEXT NOT NULL,
    event_data      JSONB DEFAULT '{}',
    session_id      TEXT,
    device_type     TEXT,
    recorded_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_analytics_events_profession
    ON public.analytics_events(profession_id, event_type, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_events_patient
    ON public.analytics_events(patient_id, event_type, recorded_at DESC);

-- ============================================================
-- 5. RLS POLICIES
-- ============================================================
ALTER TABLE public.emr_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opd_visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medical_prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medical_prescription_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vitals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_tests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_external_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tele_consultations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_cohorts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cohort_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

-- EMR
DROP POLICY IF EXISTS "emr_select" ON public.emr_records;
CREATE POLICY "emr_select" ON public.emr_records FOR SELECT USING (true);
DROP POLICY IF EXISTS "emr_modify" ON public.emr_records;
CREATE POLICY "emr_modify" ON public.emr_records FOR ALL USING (true);

-- OPD
DROP POLICY IF EXISTS "opd_select" ON public.opd_visits;
CREATE POLICY "opd_select" ON public.opd_visits FOR SELECT USING (true);
DROP POLICY IF EXISTS "opd_modify" ON public.opd_visits;
CREATE POLICY "opd_modify" ON public.opd_visits FOR ALL USING (true);

-- Medical Prescriptions
DROP POLICY IF EXISTS "medical_prescriptions_select" ON public.medical_prescriptions;
CREATE POLICY "medical_prescriptions_select" ON public.medical_prescriptions FOR SELECT USING (true);
DROP POLICY IF EXISTS "medical_prescriptions_modify" ON public.medical_prescriptions;
CREATE POLICY "medical_prescriptions_modify" ON public.medical_prescriptions FOR ALL USING (true);

-- Medical Prescription Items
DROP POLICY IF EXISTS "medical_prescription_items_select" ON public.medical_prescription_items;
CREATE POLICY "medical_prescription_items_select" ON public.medical_prescription_items FOR SELECT USING (true);
DROP POLICY IF EXISTS "medical_prescription_items_modify" ON public.medical_prescription_items;
CREATE POLICY "medical_prescription_items_modify" ON public.medical_prescription_items FOR ALL USING (true);

-- Vitals
DROP POLICY IF EXISTS "vitals_select" ON public.vitals;
CREATE POLICY "vitals_select" ON public.vitals FOR SELECT USING (true);
DROP POLICY IF EXISTS "vitals_modify" ON public.vitals;
CREATE POLICY "vitals_modify" ON public.vitals FOR ALL USING (true);

-- Lab Tests
DROP POLICY IF EXISTS "lab_tests_select" ON public.lab_tests;
CREATE POLICY "lab_tests_select" ON public.lab_tests FOR SELECT USING (true);
DROP POLICY IF EXISTS "lab_tests_modify" ON public.lab_tests;
CREATE POLICY "lab_tests_modify" ON public.lab_tests FOR ALL USING (true);

-- Lab Results
DROP POLICY IF EXISTS "lab_results_select" ON public.lab_results;
CREATE POLICY "lab_results_select" ON public.lab_results FOR SELECT USING (true);
DROP POLICY IF EXISTS "lab_results_modify" ON public.lab_results;
CREATE POLICY "lab_results_modify" ON public.lab_results FOR ALL USING (true);

-- Lab External
DROP POLICY IF EXISTS "lab_external_select" ON public.lab_external_requests;
CREATE POLICY "lab_external_select" ON public.lab_external_requests FOR SELECT USING (true);
DROP POLICY IF EXISTS "lab_external_modify" ON public.lab_external_requests;
CREATE POLICY "lab_external_modify" ON public.lab_external_requests FOR ALL USING (true);

-- Teleconsultations
DROP POLICY IF EXISTS "tele_select" ON public.tele_consultations;
CREATE POLICY "tele_select" ON public.tele_consultations FOR SELECT USING (true);
DROP POLICY IF EXISTS "tele_modify" ON public.tele_consultations;
CREATE POLICY "tele_modify" ON public.tele_consultations FOR ALL USING (true);

-- Cohorts
DROP POLICY IF EXISTS "cohorts_select" ON public.customer_cohorts;
CREATE POLICY "cohorts_select" ON public.customer_cohorts FOR SELECT USING (true);
DROP POLICY IF EXISTS "cohorts_modify" ON public.customer_cohorts;
CREATE POLICY "cohorts_modify" ON public.customer_cohorts FOR ALL USING (true);

-- Cohort Members
DROP POLICY IF EXISTS "cohort_members_select" ON public.cohort_members;
CREATE POLICY "cohort_members_select" ON public.cohort_members FOR SELECT USING (true);
DROP POLICY IF EXISTS "cohort_members_modify" ON public.cohort_members;
CREATE POLICY "cohort_members_modify" ON public.cohort_members FOR ALL USING (true);

-- Analytics Events
DROP POLICY IF EXISTS "analytics_events_select" ON public.analytics_events;
CREATE POLICY "analytics_events_select" ON public.analytics_events FOR SELECT USING (true);
DROP POLICY IF EXISTS "analytics_events_modify" ON public.analytics_events;
CREATE POLICY "analytics_events_modify" ON public.analytics_events FOR ALL USING (true);

-- ============================================================
-- 6. RPC FUNCTIONS
-- ============================================================

-- Create OPD visit with queue number
CREATE OR REPLACE FUNCTION create_opd_visit(
    p_profession_id UUID,
    p_patient_id UUID,
    p_doctor_id UUID,
    p_chief_complaint TEXT,
    p_is_walk_in BOOLEAN DEFAULT true
)
RETURNS UUID AS $$
DECLARE
    v_visit_number TEXT;
    v_queue_number INTEGER;
    v_visit_id UUID;
BEGIN
    -- Generate visit number: OPD-YYYYMMDD-NNNN
    v_visit_number := 'OPD-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || LPAD(nextval('public.order_number_seq')::TEXT, 4, '0');

    -- Get next queue number for today
    SELECT COALESCE(MAX(queue_number), 0) + 1 INTO v_queue_number
    FROM public.opd_visits
    WHERE profession_id = p_profession_id
      AND visit_date = CURRENT_DATE
      AND status IN ('checked_in', 'in_consultation');

    INSERT INTO public.opd_visits (
        profession_id, patient_id, doctor_id, visit_number,
        chief_complaint, queue_number, is_walk_in
    )
    VALUES (
        p_profession_id, p_patient_id, p_doctor_id, v_visit_number,
        p_chief_complaint, v_queue_number, p_is_walk_in
    )
    RETURNING id INTO v_visit_id;

    RETURN v_visit_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add patient to cohort (auto or manual)
CREATE OR REPLACE FUNCTION add_patient_to_cohort(
    p_cohort_id UUID,
    p_patient_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO public.cohort_members (cohort_id, patient_id, added_reason)
    VALUES (p_cohort_id, p_patient_id, p_reason)
    ON CONFLICT (cohort_id, patient_id) DO NOTHING;

    -- Update member count
    UPDATE public.customer_cohorts
    SET member_count = (
        SELECT COUNT(*) FROM public.cohort_members WHERE cohort_id = p_cohort_id
    ),
    updated_at = NOW()
    WHERE id = p_cohort_id;

    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
