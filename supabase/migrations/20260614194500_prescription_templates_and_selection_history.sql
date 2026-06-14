-- Migration: Prescription Templates, Selection History, and Prescription History Enhancements
-- Date: 2026-06-14

-- 1) Template Master Table
CREATE TABLE IF NOT EXISTS public.prescription_templates (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    consultation_id         UUID REFERENCES public.consultation_requests(id) ON DELETE SET NULL,
    source_prescription_id   UUID REFERENCES public.prescriptions(id) ON DELETE SET NULL,
    template_name           TEXT NOT NULL,
    description             TEXT,
    is_shared_with_patient  BOOLEAN NOT NULL DEFAULT true,
    is_active               BOOLEAN NOT NULL DEFAULT true,
    medications_snapshot    JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prescription_templates_provider
    ON public.prescription_templates(provider_id, is_active, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prescription_templates_consultation
    ON public.prescription_templates(consultation_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_prescription_templates_updated_at ON public.prescription_templates;
CREATE TRIGGER trg_prescription_templates_updated_at
    BEFORE UPDATE ON public.prescription_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2) Normalized template items for auditing and later expansion
CREATE TABLE IF NOT EXISTS public.prescription_template_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id     UUID NOT NULL REFERENCES public.prescription_templates(id) ON DELETE CASCADE,
    item_name       TEXT NOT NULL,
    dosage          TEXT,
    frequency       TEXT,
    duration        TEXT,
    route           TEXT DEFAULT 'oral'
                        CHECK (route IN ('oral', 'iv', 'im', 'sc', 'topical', 'inhalation', 'rectal', 'ophthalmic')),
    quantity        INTEGER NOT NULL DEFAULT 1,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prescription_template_items_template
    ON public.prescription_template_items(template_id, sort_order);

-- 3) Patient-selected choice history, every selection is stored as a new row
CREATE TABLE IF NOT EXISTS public.prescription_selection_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id     UUID NOT NULL REFERENCES public.consultation_requests(id) ON DELETE CASCADE,
    prescription_id     UUID REFERENCES public.prescriptions(id) ON DELETE SET NULL,
    patient_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    provider_id         UUID REFERENCES public.users(id) ON DELETE SET NULL,
    template_id         UUID REFERENCES public.prescription_templates(id) ON DELETE SET NULL,
    template_name       TEXT,
    selection_source    TEXT NOT NULL DEFAULT 'patient'
                        CHECK (selection_source IN ('patient', 'provider', 'system')),
    selected_items      JSONB NOT NULL DEFAULT '[]'::jsonb,
    notes               TEXT,
    selected_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_prescription_selection_history_consultation
    ON public.prescription_selection_history(consultation_id, selected_at DESC);
CREATE INDEX IF NOT EXISTS idx_prescription_selection_history_patient
    ON public.prescription_selection_history(patient_id, selected_at DESC);
CREATE INDEX IF NOT EXISTS idx_prescription_selection_history_provider
    ON public.prescription_selection_history(provider_id, selected_at DESC);

DROP TRIGGER IF EXISTS trg_prescription_selection_history_updated_at ON public.prescription_selection_history;
CREATE TRIGGER trg_prescription_selection_history_updated_at
    BEFORE UPDATE ON public.prescription_selection_history
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4) Enhance prescriptions with template linkage and selection snapshot
ALTER TABLE public.prescriptions
    ADD COLUMN IF NOT EXISTS template_id UUID REFERENCES public.prescription_templates(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS template_name TEXT,
    ADD COLUMN IF NOT EXISTS template_snapshot JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS selected_items_snapshot JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS selection_history_id UUID REFERENCES public.prescription_selection_history(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS selected_by_patient_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_prescriptions_template
    ON public.prescriptions(template_id, issued_at DESC);
CREATE INDEX IF NOT EXISTS idx_prescriptions_selection_history
    ON public.prescriptions(selection_history_id);

-- 5) RLS policies
ALTER TABLE public.prescription_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescription_template_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescription_selection_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Provider can manage prescription templates" ON public.prescription_templates;
CREATE POLICY "Provider can manage prescription templates"
ON public.prescription_templates
FOR ALL
USING (provider_id = auth.uid())
WITH CHECK (provider_id = auth.uid());

DROP POLICY IF EXISTS "Patient can read shared prescription templates" ON public.prescription_templates;
CREATE POLICY "Patient can read shared prescription templates"
ON public.prescription_templates
FOR SELECT
USING (
    is_shared_with_patient = true
    AND EXISTS (
        SELECT 1
        FROM public.consultation_requests cr
        WHERE cr.id = consultation_id
          AND cr.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Provider can manage template items" ON public.prescription_template_items;
CREATE POLICY "Provider can manage template items"
ON public.prescription_template_items
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM public.prescription_templates pt
        WHERE pt.id = template_id
          AND pt.provider_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.prescription_templates pt
        WHERE pt.id = template_id
          AND pt.provider_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Patient can read template items for shared templates" ON public.prescription_template_items;
CREATE POLICY "Patient can read template items for shared templates"
ON public.prescription_template_items
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM public.prescription_templates pt
        JOIN public.consultation_requests cr ON cr.id = pt.consultation_id
        WHERE pt.id = template_id
          AND pt.is_shared_with_patient = true
          AND cr.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Patient can create selection history" ON public.prescription_selection_history;
CREATE POLICY "Patient can create selection history"
ON public.prescription_selection_history
FOR INSERT
WITH CHECK (patient_id = auth.uid());

DROP POLICY IF EXISTS "Patient can read own selection history" ON public.prescription_selection_history;
CREATE POLICY "Patient can read own selection history"
ON public.prescription_selection_history
FOR SELECT
USING (patient_id = auth.uid() OR provider_id = auth.uid());

DROP POLICY IF EXISTS "Provider can manage own selection history" ON public.prescription_selection_history;
CREATE POLICY "Provider can manage own selection history"
ON public.prescription_selection_history
FOR ALL
USING (provider_id = auth.uid())
WITH CHECK (provider_id = auth.uid());
