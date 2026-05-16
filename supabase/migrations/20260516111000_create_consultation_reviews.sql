-- Migration: Create consultation_reviews table
CREATE TABLE IF NOT EXISTS public.consultation_reviews (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id   UUID NOT NULL REFERENCES public.consultation_requests(id) ON DELETE CASCADE,
  patient_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  provider_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rating            INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment           TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE(consultation_id, patient_id, provider_id)
);

-- RLS Policies
ALTER TABLE public.consultation_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view reviews for their own consultations"
  ON public.consultation_reviews FOR SELECT
  USING (auth.uid() = patient_id OR auth.uid() = provider_id);

CREATE POLICY "Patients can insert reviews for their consultations"
  ON public.consultation_reviews FOR INSERT
  WITH CHECK (auth.uid() = patient_id);

-- Indexing
CREATE INDEX IF NOT EXISTS idx_reviews_consultation ON public.consultation_reviews(consultation_id);
CREATE INDEX IF NOT EXISTS idx_reviews_provider ON public.consultation_reviews(provider_id);
