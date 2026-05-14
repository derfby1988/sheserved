-- Migration: Consultation Notes & Prescriptions
-- Date: 2026-05-14

-- 1. Create consultation_notes table
CREATE TABLE IF NOT EXISTS consultation_notes (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id       UUID NOT NULL REFERENCES consultation_requests(id) ON DELETE CASCADE,
  provider_id           UUID NOT NULL REFERENCES users(id),
  patient_id            UUID NOT NULL REFERENCES users(id),
  chief_complaint       TEXT,
  diagnosis             TEXT,
  treatment_plan        TEXT,
  recommendations       TEXT,
  follow_up_date        DATE,
  is_visible_to_patient BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- 2. Create prescriptions table
CREATE TABLE IF NOT EXISTS prescriptions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id UUID NOT NULL REFERENCES consultation_requests(id) ON DELETE CASCADE,
  provider_id     UUID NOT NULL REFERENCES users(id),
  patient_id      UUID NOT NULL REFERENCES users(id),
  room_id         VARCHAR REFERENCES chat_rooms(id) ON DELETE SET NULL,
  medications     JSONB NOT NULL DEFAULT '[]',
  -- Example: [{"name":"Paracetamol","dose":"500mg","frequency":"ทุก 6 ชั่วโมง","duration":"3 วัน","notes":""}]
  notes           TEXT,
  issued_at       TIMESTAMPTZ DEFAULT now(),
  expires_at      TIMESTAMPTZ,
  status          TEXT DEFAULT 'active'
);

-- 3. Create doctor_quick_replies table
CREATE TABLE IF NOT EXISTS doctor_quick_replies (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  content     TEXT NOT NULL,
  category    TEXT DEFAULT 'general',
  sort_order  INT DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- RLS Policies

-- consultation_notes RLS
ALTER TABLE consultation_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Provider can manage their own notes"
ON consultation_notes
FOR ALL
USING (provider_id = auth.uid());

CREATE POLICY "Patient can read visible notes"
ON consultation_notes
FOR SELECT
USING (patient_id = auth.uid() AND is_visible_to_patient = true);

-- prescriptions RLS
ALTER TABLE prescriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Provider can manage their own prescriptions"
ON prescriptions
FOR ALL
USING (provider_id = auth.uid());

CREATE POLICY "Patient can read their own prescriptions"
ON prescriptions
FOR SELECT
USING (patient_id = auth.uid());

-- doctor_quick_replies RLS
ALTER TABLE doctor_quick_replies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Provider can manage their own quick replies"
ON doctor_quick_replies
FOR ALL
USING (provider_id = auth.uid());
