-- Phase 21.7.12 — Find Coach completion: coach-published 1:1 slots,
-- class/course offerings with sessions, enrollments with capacity +
-- minimum-enrollment handling, schedule-change proposals, private
-- favorites, contact channels, per-credential review, and the 1–10
-- five-category review system (parity with the venue review scoring).
--
-- Same conventions as the earlier sports_hub migrations: explicit actor
-- ids, SELECT-only RLS, all mutations through SECURITY DEFINER RPCs,
-- durable notifications via sports_hub_notify (never aborts the
-- business transaction).

-- ===============
-- coach_profiles: lifecycle + new profile fields
-- ===============

ALTER TABLE public.coach_profiles
  DROP CONSTRAINT IF EXISTS coach_profiles_status_check;
ALTER TABLE public.coach_profiles
  ADD CONSTRAINT coach_profiles_status_check
  CHECK (status IN ('pending','approved','rejected','suspended'));

ALTER TABLE public.coach_profiles
  ADD COLUMN IF NOT EXISTS experience TEXT,
  ADD COLUMN IF NOT EXISTS accepting_students BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS cover_url VARCHAR(500);

-- ===============
-- Private coach contact channels (never on the public view)
-- ===============
CREATE TABLE IF NOT EXISTS public.coach_contacts (
  coach_id UUID PRIMARY KEY REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  phone VARCHAR(40),
  line_id VARCHAR(80),
  facebook_url VARCHAR(300),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===============
-- Per-credential review status; is_verified derives from approved creds
-- ===============
ALTER TABLE public.coach_certifications
  ADD COLUMN IF NOT EXISTS status VARCHAR(10) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected')),
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason VARCHAR(300);

-- Existing credentials of already-verified coaches count as approved.
UPDATE public.coach_certifications c
SET status = 'approved'
FROM public.coach_profiles p
WHERE p.id = c.coach_id AND p.is_verified AND c.status = 'pending';

-- ===============
-- Teaching locations: approved Book Court venue or custom place
-- ===============
CREATE TABLE IF NOT EXISTS public.coach_teaching_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  kind VARCHAR(8) NOT NULL CHECK (kind IN ('venue','custom')),
  venue_id UUID REFERENCES public.sports_venues(id),
  name VARCHAR(160) NOT NULL,
  address VARCHAR(300),
  lat DOUBLE PRECISION CHECK (lat BETWEEN -90 AND 90),
  lng DOUBLE PRECISION CHECK (lng BETWEEN -180 AND 180),
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coach_teaching_locations_coach
  ON public.coach_teaching_locations(coach_id);

-- ===============
-- Offerings: 1:1 products, single-session classes, multi-session courses
-- ===============
CREATE TABLE IF NOT EXISTS public.coach_offerings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  offering_type VARCHAR(12) NOT NULL
    CHECK (offering_type IN ('one_on_one','class','course')),
  title VARCHAR(160) NOT NULL,
  description VARCHAR(2000),
  sport_id UUID REFERENCES public.sports(id),
  learner_levels VARCHAR(10)[] NOT NULL DEFAULT '{}',
  teaching_mode VARCHAR(10) NOT NULL DEFAULT 'onsite'
    CHECK (teaching_mode IN ('onsite','online')),
  location_id UUID REFERENCES public.coach_teaching_locations(id)
    ON DELETE SET NULL,
  location_label VARCHAR(200),
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  price NUMERIC(10,2) CHECK (price >= 0),
  pricing_unit VARCHAR(12) NOT NULL DEFAULT 'per_hour'
    CHECK (pricing_unit IN
      ('per_hour','per_person','per_group','per_session','package')),
  capacity INT CHECK (capacity IS NULL OR capacity > 0),
  min_enrollment INT NOT NULL DEFAULT 0 CHECK (min_enrollment >= 0),
  enrollment_cutoff_hours INT NOT NULL DEFAULT 24
    CHECK (enrollment_cutoff_hours >= 0),
  cancellation_cutoff_hours INT NOT NULL DEFAULT 24
    CHECK (cancellation_cutoff_hours >= 0),
  cancellation_policy_version VARCHAR(20) NOT NULL DEFAULT 'platform-v1',
  -- What happens to a learner who declines or ignores a schedule-change
  -- proposal: 'cancel' frees the seat, 'keep' retains the original times.
  schedule_no_response VARCHAR(8) NOT NULL DEFAULT 'cancel'
    CHECK (schedule_no_response IN ('cancel','keep')),
  auto_confirm BOOLEAN NOT NULL DEFAULT false,
  -- course only: learners may pick a subset of sessions.
  allow_partial_enrollment BOOLEAN NOT NULL DEFAULT true,
  status VARCHAR(10) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','published','closed','cancelled','completed')),
  min_decision VARCHAR(10) CHECK (min_decision IN ('proceed','cancelled')),
  reopen_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coach_offerings_coach
  ON public.coach_offerings(coach_id, status);

CREATE TABLE IF NOT EXISTS public.coach_offering_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id UUID NOT NULL REFERENCES public.coach_offerings(id)
    ON DELETE CASCADE,
  seq INT NOT NULL DEFAULT 0,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  location_label VARCHAR(200),
  capacity INT CHECK (capacity IS NULL OR capacity > 0),
  price NUMERIC(10,2) CHECK (price IS NULL OR price >= 0),
  status VARCHAR(10) NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','cancelled','completed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_coach_offering_sessions_offering
  ON public.coach_offering_sessions(offering_id, starts_at);

-- ===============
-- Coach-published 1:1 slots (draft → published → booked/cancelled/expired)
-- ===============
CREATE TABLE IF NOT EXISTS public.coach_slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  offering_id UUID NOT NULL REFERENCES public.coach_offerings(id)
    ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  price_snapshot NUMERIC(10,2),
  status VARCHAR(10) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','published','booked','cancelled','expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_coach_slots_coach
  ON public.coach_slots(coach_id, status, starts_at);

ALTER TABLE public.coach_booking_requests
  ADD COLUMN IF NOT EXISTS slot_id UUID REFERENCES public.coach_slots(id);

CREATE INDEX IF NOT EXISTS idx_coach_booking_requests_slot
  ON public.coach_booking_requests(slot_id) WHERE slot_id IS NOT NULL;

-- ===============
-- Enrollments for classes/courses (separate from 1:1 booking requests)
-- ===============
CREATE TABLE IF NOT EXISTS public.coach_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id UUID NOT NULL REFERENCES public.coach_offerings(id),
  user_id UUID NOT NULL REFERENCES public.users(id),
  -- 'course' = whole course, 'sessions' = explicit session subset.
  scope VARCHAR(10) NOT NULL DEFAULT 'sessions'
    CHECK (scope IN ('course','sessions')),
  status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN
    ('pending','confirmed','rejected','cancelled','expired','completed')),
  price_total NUMERIC(10,2),
  pricing_unit VARCHAR(12),
  -- Accepted policy snapshot: cutoff/version/text frozen at consent time
  -- so later offering edits never rewrite agreed terms.
  cancellation_cutoff_hours INT,
  cancellation_policy_version VARCHAR(20),
  cancellation_policy_text TEXT,
  consent_at TIMESTAMPTZ,
  decided_by UUID REFERENCES public.users(id),
  decided_at TIMESTAMPTZ,
  rejection_reason VARCHAR(300),
  cancelled_by UUID REFERENCES public.users(id),
  cancelled_at TIMESTAMPTZ,
  cancellation_reason VARCHAR(300),
  idempotency_key VARCHAR(80),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_coach_enrollments_idem
  ON public.coach_enrollments(user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
-- One live enrollment per learner per offering.
CREATE UNIQUE INDEX IF NOT EXISTS idx_coach_enrollments_active
  ON public.coach_enrollments(offering_id, user_id)
  WHERE status IN ('pending','confirmed');
CREATE INDEX IF NOT EXISTS idx_coach_enrollments_user
  ON public.coach_enrollments(user_id, status);
CREATE INDEX IF NOT EXISTS idx_coach_enrollments_offering
  ON public.coach_enrollments(offering_id, status);

CREATE TABLE IF NOT EXISTS public.coach_enrollment_sessions (
  enrollment_id UUID NOT NULL REFERENCES public.coach_enrollments(id)
    ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.coach_offering_sessions(id),
  status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN
    ('pending','confirmed','cancelled','completed','expired')),
  -- Applied schedule change for THIS learner only; the shared session row
  -- keeps the original times until each learner accepts.
  override_starts_at TIMESTAMPTZ,
  override_ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (enrollment_id, session_id)
);

CREATE INDEX IF NOT EXISTS idx_coach_enrollment_sessions_session
  ON public.coach_enrollment_sessions(session_id, status);

-- ===============
-- Schedule-change proposals: per-enrollment accept/decline responses
-- ===============
CREATE TABLE IF NOT EXISTS public.coach_schedule_proposals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.coach_offering_sessions(id)
    ON DELETE CASCADE,
  proposed_by UUID NOT NULL REFERENCES public.users(id),
  reason VARCHAR(300),
  old_starts_at TIMESTAMPTZ NOT NULL,
  old_ends_at TIMESTAMPTZ NOT NULL,
  old_location VARCHAR(200),
  new_starts_at TIMESTAMPTZ NOT NULL,
  new_ends_at TIMESTAMPTZ NOT NULL,
  new_location VARCHAR(200),
  status VARCHAR(8) NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (new_ends_at > new_starts_at)
);

-- Doubles as the schedule-change event record once the learner responds.
CREATE TABLE IF NOT EXISTS public.coach_schedule_change_responses (
  proposal_id UUID NOT NULL REFERENCES public.coach_schedule_proposals(id)
    ON DELETE CASCADE,
  enrollment_id UUID NOT NULL REFERENCES public.coach_enrollments(id)
    ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id),
  response VARCHAR(8) CHECK (response IN ('accepted','declined')),
  responded_at TIMESTAMPTZ,
  PRIMARY KEY (proposal_id, enrollment_id)
);

-- ===============
-- Private favorites
-- ===============
CREATE TABLE IF NOT EXISTS public.coach_favorites (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  coach_id UUID NOT NULL REFERENCES public.coach_profiles(id)
    ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, coach_id)
);

-- ===============
-- Coach reviews → 1–10 five-category model
-- ===============
ALTER TABLE public.coach_reviews
  ADD COLUMN IF NOT EXISTS rating_10 NUMERIC(3,1),
  ADD COLUMN IF NOT EXISTS is_legacy BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS enrollment_id UUID
    REFERENCES public.coach_enrollments(id),
  ADD COLUMN IF NOT EXISTS session_id UUID
    REFERENCES public.coach_offering_sessions(id),
  ADD COLUMN IF NOT EXISTS rubric_version VARCHAR(10) NOT NULL DEFAULT 'v1';

ALTER TABLE public.coach_reviews ALTER COLUMN booking_id DROP NOT NULL;
ALTER TABLE public.coach_reviews ALTER COLUMN rating DROP NOT NULL;

UPDATE public.coach_reviews
SET rating_10 = rating * 2, is_legacy = true
WHERE rating_10 IS NULL AND rating IS NOT NULL;

ALTER TABLE public.coach_reviews ALTER COLUMN rating_10 SET NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coach_reviews_rating_10_check'
  ) THEN
    ALTER TABLE public.coach_reviews
      ADD CONSTRAINT coach_reviews_rating_10_check
      CHECK (rating_10 BETWEEN 1 AND 10);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'coach_reviews_source_check'
  ) THEN
    ALTER TABLE public.coach_reviews
      ADD CONSTRAINT coach_reviews_source_check CHECK (
        (booking_id IS NOT NULL AND enrollment_id IS NULL
         AND session_id IS NULL)
        OR (booking_id IS NULL AND enrollment_id IS NOT NULL
            AND session_id IS NOT NULL)
      );
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_coach_reviews_enrollment_session
  ON public.coach_reviews(enrollment_id, session_id)
  WHERE enrollment_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.coach_review_category_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key VARCHAR(40) NOT NULL UNIQUE,
  label_th VARCHAR(80) NOT NULL,
  label_en VARCHAR(80),
  anchors JSONB NOT NULL DEFAULT '{}'::jsonb,
  rubric_version INT NOT NULL DEFAULT 1,
  is_active BOOLEAN NOT NULL DEFAULT true,
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.coach_review_category_catalog
  (key, label_th, label_en, anchors, display_order)
SELECT * FROM (VALUES
  ('expertise_safety', 'ความเชี่ยวชาญและความปลอดภัย',
   'Expertise & safety',
   '{"1-2":"คำแนะนำผิดหรือไม่ปลอดภัยซ้ำ/มองไม่เห็นความเสี่ยงชัด","3-4":"มีจุดผิดหรือปรับความปลอดภัยไม่สม่ำเสมอ","5-6":"พื้นฐานถูกและปลอดภัย มีพลาดเล็กน้อยแต่แก้ได้","7-8":"สาธิต/แก้ได้ถูก สังเกตความเสี่ยงและปรับทัน","9-10":"แม่นยำและป้องกันความเสี่ยงเชิงรุกตามผู้เรียน"}'::jsonb, 1),
  ('explanation_feedback', 'อธิบายและ feedback',
   'Explanation & feedback',
   '{"1-2":"สับสน/ขัดแย้งและไม่มี feedback ที่นำไปใช้ได้","3-4":"อธิบายคลุมเครือหรือ feedback ช้า/กว้างเกินไป","5-6":"เข้าใจได้และมีคำแนะนำที่ใช้ได้เป็นบางครั้ง","7-8":"อธิบายเป็นขั้นและให้ feedback เฉพาะจุดทันเวลา","9-10":"สาธิต/อธิบายชัดมากและ feedback ช่วยให้แก้ทักษะได้ทันที"}'::jsonb, 2),
  ('personalization', 'ปรับให้เหมาะรายคน',
   'Personalization',
   '{"1-2":"มองข้ามระดับ/เป้าหมาย/ข้อจำกัดชัดเจน","3-4":"ปรับน้อยแม้เนื้อหาไม่เหมาะหรือผู้เรียนขอ","5-6":"เนื้อหาโดยรวมเหมาะและปรับได้เมื่อร้องขอ","7-8":"ปรับความยากและความสนใจตามระดับ/เป้าหมาย","9-10":"เช็กความเข้าใจและปรับอย่างต่อเนื่องให้ท้าทายพอดีและเหมาะกับผู้เรียน"}'::jsonb, 3),
  ('punctuality_preparedness', 'ตรงเวลาและเตรียมพร้อม',
   'Punctuality & preparedness',
   '{"1-2":"มาสาย/ไม่พร้อมจนเสียเวลาเรียนมาก","3-4":"สายหรือขาดการเตรียมตัวบ่อย","5-6":"ส่วนใหญ่ตรงเวลาและพร้อมแต่มีสะดุดเล็กน้อย","7-8":"ตรงเวลา เตรียมพร้อม และใช้เวลาเรียนได้ดี","9-10":"พร้อมสม่ำเสมอและจัดเวลา session ได้เต็มประสิทธิภาพ"}'::jsonb, 4),
  ('value', 'ความคุ้มค่าราคา',
   'Value for money',
   '{"1-2":"สิ่งที่ได้รับต่ำกว่าราคา/ขอบเขตที่แจ้งมาก","3-4":"ได้ประโยชน์จำกัดเมื่อเทียบกับราคาและเวลาสอน","5-6":"คุ้มค่าระดับเหมาะสมและได้บริการหลักตามที่แจ้ง","7-8":"คุณภาพ/การเตรียมตัว/ประโยชน์สูงเมื่อเทียบกับราคา","9-10":"คุ้มค่าโดดเด่นและราคา/สิ่งที่รวมโปร่งใส"}'::jsonb, 5)
) AS seed(key, label_th, label_en, anchors, display_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.coach_review_category_catalog
);

CREATE TABLE IF NOT EXISTS public.coach_review_category_scores (
  review_id UUID NOT NULL REFERENCES public.coach_reviews(id)
    ON DELETE CASCADE,
  category_id UUID NOT NULL
    REFERENCES public.coach_review_category_catalog(id),
  score SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 10),
  PRIMARY KEY (review_id, category_id)
);

CREATE TABLE IF NOT EXISTS public.coach_review_tag_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key VARCHAR(40) NOT NULL UNIQUE,
  label_th VARCHAR(60) NOT NULL,
  label_en VARCHAR(60),
  is_active BOOLEAN NOT NULL DEFAULT true,
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.coach_review_tag_catalog
  (key, label_th, label_en, display_order)
SELECT * FROM (VALUES
  ('easy_to_follow',  'สอนเข้าใจง่าย',   'Easy to follow', 1),
  ('on_time',         'ตรงเวลา',         'On time', 2),
  ('caring',          'ใส่ใจผู้เรียน',    'Caring', 3),
  ('clear_comms',     'สื่อสารชัดเจน',    'Clear communication', 4),
  ('listens',         'รับฟังผู้เรียน',   'Listens to learners', 5),
  ('respects_bounds', 'เคารพขอบเขต',     'Respects boundaries', 6)
) AS seed(key, label_th, label_en, display_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.coach_review_tag_catalog
);

CREATE TABLE IF NOT EXISTS public.coach_review_tags (
  review_id UUID NOT NULL REFERENCES public.coach_reviews(id)
    ON DELETE CASCADE,
  tag_id UUID NOT NULL
    REFERENCES public.coach_review_tag_catalog(id),
  PRIMARY KEY (review_id, tag_id)
);

CREATE TABLE IF NOT EXISTS public.coach_review_custom_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id UUID NOT NULL REFERENCES public.coach_reviews(id)
    ON DELETE CASCADE,
  label VARCHAR(60) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.coach_review_helpful_votes (
  review_id UUID NOT NULL REFERENCES public.coach_reviews(id)
    ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (review_id, user_id)
);

-- ===============
-- Views
-- ===============

-- Approved coaches only; now also exposes experience, cover, accepting
-- flag and a computed "has bookable future slot/offering" flag used by
-- the เปิดรับสอน quick filter.
-- Existing columns keep their original order; new fields are appended.
CREATE OR REPLACE VIEW public.coach_profiles_public
WITH (security_invoker = on) AS
SELECT p.id, p.user_id, p.display_name, p.bio, p.timezone,
       p.hourly_rate, p.teaching_mode, p.is_verified, p.created_at,
       u.profile_image_url AS avatar_url,
       p.experience, p.cover_url, p.accepting_students,
       (p.accepting_students AND (
         EXISTS (
           SELECT 1 FROM public.coach_slots s
           WHERE s.coach_id = p.id AND s.status = 'published'
             AND s.starts_at > now()
         ) OR EXISTS (
           SELECT 1 FROM public.coach_offerings o
           WHERE o.coach_id = p.id
             AND o.status IN ('published','closed')
             AND EXISTS (
               SELECT 1 FROM public.coach_offering_sessions os
               WHERE os.offering_id = o.id AND os.status = 'scheduled'
                 AND os.starts_at > now()
             )
         )
       )) AS has_open_availability
FROM public.coach_profiles p
LEFT JOIN public.users u ON u.id = p.user_id
WHERE p.status = 'approved';

-- Approved credentials are safe to show; document paths stay private.
CREATE OR REPLACE VIEW public.coach_certifications_public
WITH (security_invoker = on) AS
SELECT c.id, c.coach_id, c.name, c.issuer, c.issued_year
FROM public.coach_certifications c
JOIN public.coach_profiles p ON p.id = c.coach_id
WHERE p.status = 'approved' AND c.status = 'approved';

CREATE OR REPLACE VIEW public.coach_teaching_locations_public
WITH (security_invoker = on) AS
SELECT l.id, l.coach_id, l.kind, l.venue_id, l.name, l.address,
       l.lat, l.lng, l.timezone
FROM public.coach_teaching_locations l
JOIN public.coach_profiles p ON p.id = l.coach_id
WHERE p.status = 'approved';

-- Offerings keep showing once published even after intake closes.
CREATE OR REPLACE VIEW public.coach_offerings_public
WITH (security_invoker = on) AS
SELECT o.id, o.coach_id, o.offering_type, o.title, o.description,
       o.sport_id, o.learner_levels, o.teaching_mode, o.location_id,
       o.location_label, o.timezone, o.price, o.pricing_unit, o.capacity,
       o.min_enrollment, o.enrollment_cutoff_hours,
       o.cancellation_cutoff_hours, o.cancellation_policy_version,
       o.auto_confirm, o.allow_partial_enrollment, o.status,
       o.created_at
FROM public.coach_offerings o
JOIN public.coach_profiles p ON p.id = o.coach_id
WHERE p.status = 'approved'
  AND o.status IN ('published','closed','completed');

CREATE OR REPLACE VIEW public.coach_offering_sessions_public
WITH (security_invoker = on) AS
SELECT s.id, s.offering_id, s.seq, s.starts_at, s.ends_at, s.timezone,
       s.location_label, s.capacity, s.price, s.status
FROM public.coach_offering_sessions s
JOIN public.coach_offerings o ON o.id = s.offering_id
JOIN public.coach_profiles p ON p.id = o.coach_id
WHERE p.status = 'approved'
  AND o.status IN ('published','closed','completed');

-- Learners see only published, still-bookable slots.
CREATE OR REPLACE VIEW public.coach_slots_public
WITH (security_invoker = on) AS
SELECT s.id, s.coach_id, s.offering_id, s.starts_at, s.ends_at,
       s.timezone, s.price_snapshot, s.status
FROM public.coach_slots s
JOIN public.coach_profiles p ON p.id = s.coach_id
WHERE p.status = 'approved'
  AND s.status = 'published'
  AND s.starts_at > now();

-- v1 review surface stays compatible: `rating` keeps its 1–5 meaning via
-- the folded value, new columns are additive for the migrated client.
CREATE OR REPLACE VIEW public.coach_reviews_public
WITH (security_invoker = on) AS
SELECT r.id, r.coach_id, r.booking_id, r.user_id,
       NULLIF(btrim(CONCAT_WS(' ', u.first_name, u.last_name)), '')
         AS user_display_name,
       u.profile_image_url AS user_avatar_url,
       COALESCE(r.rating, ROUND(r.rating_10 / 2)::smallint) AS rating,
       r.comment, r.created_at,
       r.enrollment_id, r.session_id, r.rating_10, r.is_legacy
FROM public.coach_reviews r
LEFT JOIN public.users u ON u.id = r.user_id
WHERE r.status = 'published';

CREATE OR REPLACE VIEW public.coach_review_summary
WITH (security_invoker = on) AS
SELECT coach_id,
       ROUND(AVG(rating_10) / 2, 2) AS average_rating,
       COUNT(*) AS review_count,
       ROUND(AVG(rating_10)::numeric, 2) AS average_rating_10
FROM public.coach_reviews
WHERE status = 'published'
GROUP BY coach_id;

-- ===============
-- Profile/contact/certification RPCs
-- ===============

-- upsert_coach_profile gains optional fields; existing positional
-- callers keep working because new params default to NULL.
CREATE OR REPLACE FUNCTION public.upsert_coach_profile(
  p_user_id UUID,
  p_display_name VARCHAR,
  p_bio VARCHAR DEFAULT NULL,
  p_timezone VARCHAR DEFAULT 'Asia/Bangkok',
  p_hourly_rate NUMERIC DEFAULT NULL,
  p_teaching_mode VARCHAR DEFAULT 'onsite',
  p_experience TEXT DEFAULT NULL,
  p_accepting_students BOOLEAN DEFAULT NULL,
  p_cover_url VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_status VARCHAR(10);
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF length(btrim(COALESCE(p_display_name, ''))) = 0 THEN
    RAISE EXCEPTION 'INVALID_PROFILE';
  END IF;
  IF p_teaching_mode NOT IN ('onsite','online','both') THEN
    RAISE EXCEPTION 'INVALID_TEACHING_MODE';
  END IF;

  SELECT id, status INTO v_id, v_status
  FROM public.coach_profiles WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_status = 'suspended' THEN
    RAISE EXCEPTION 'COACH_SUSPENDED';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.coach_profiles (
      user_id, display_name, bio, experience, timezone, hourly_rate,
      teaching_mode, cover_url, accepting_students, status
    ) VALUES (
      p_user_id, p_display_name, p_bio, p_experience,
      COALESCE(NULLIF(p_timezone, ''), 'Asia/Bangkok'),
      p_hourly_rate, p_teaching_mode, p_cover_url,
      COALESCE(p_accepting_students, true), 'pending'
    )
    RETURNING id INTO v_id;
  ELSE
    -- Post-approval profile edits publish immediately; only credential
    -- changes trigger re-review (handled per certification row).
    UPDATE public.coach_profiles
    SET display_name = p_display_name,
        bio = p_bio,
        experience = COALESCE(p_experience, experience),
        timezone = COALESCE(NULLIF(p_timezone, ''), timezone),
        hourly_rate = p_hourly_rate,
        teaching_mode = p_teaching_mode,
        cover_url = COALESCE(p_cover_url, cover_url),
        accepting_students =
          COALESCE(p_accepting_students, accepting_students),
        updated_at = now()
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_coach_contacts(
  p_user_id UUID,
  p_phone VARCHAR DEFAULT NULL,
  p_line_id VARCHAR DEFAULT NULL,
  p_facebook_url VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT id INTO v_coach_id FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  INSERT INTO public.coach_contacts (
    coach_id, phone, line_id, facebook_url, updated_at
  ) VALUES (
    v_coach_id, NULLIF(btrim(COALESCE(p_phone, '')), ''),
    NULLIF(btrim(COALESCE(p_line_id, '')), ''),
    NULLIF(btrim(COALESCE(p_facebook_url, '')), ''), now()
  )
  ON CONFLICT (coach_id) DO UPDATE
  SET phone = EXCLUDED.phone, line_id = EXCLUDED.line_id,
      facebook_url = EXCLUDED.facebook_url, updated_at = now();
END;
$$;

-- Contact channels are readable only by the coach, an admin, or a
-- learner with a confirmed/completed booking or enrollment.
CREATE OR REPLACE FUNCTION public.get_coach_contacts(
  p_user_id UUID,
  p_coach_id UUID
)
RETURNS SETOF public.coach_contacts
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_user UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  SELECT user_id INTO v_coach_user FROM public.coach_profiles
  WHERE id = p_coach_id;
  IF v_coach_user IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  IF p_user_id <> v_coach_user
     AND NOT public.is_admin_role(p_user_id)
     AND NOT EXISTS (
       SELECT 1 FROM public.coach_booking_requests r
       WHERE r.coach_id = p_coach_id AND r.user_id = p_user_id
         AND r.status IN ('confirmed','completed')
     )
     AND NOT EXISTS (
       SELECT 1 FROM public.coach_enrollments e
       JOIN public.coach_offerings o ON o.id = e.offering_id
       WHERE o.coach_id = p_coach_id AND e.user_id = p_user_id
         AND e.status IN ('confirmed','completed')
     ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN QUERY
  SELECT * FROM public.coach_contacts WHERE coach_id = p_coach_id;
END;
$$;

-- Replace-all certification writer. Kept rows preserve review state;
-- new or edited rows go back to 'pending'. Verified status is
-- recomputed from approved credentials only.
CREATE OR REPLACE FUNCTION public.set_coach_certifications(
  p_user_id UUID,
  p_items JSONB  -- [{"id": uuid?, "name","issuer","issued_year","document_url"}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
  v_item JSONB;
  v_kept UUID[] := ARRAY[]::uuid[];
  v_existing RECORD;
  v_new_id UUID;
BEGIN
  SELECT id INTO v_coach_id FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
  LOOP
    IF length(btrim(COALESCE(v_item->>'name', ''))) = 0 THEN
      CONTINUE;
    END IF;
    IF (v_item->>'id') IS NOT NULL THEN
      SELECT * INTO v_existing FROM public.coach_certifications
      WHERE id = (v_item->>'id')::uuid AND coach_id = v_coach_id;
      IF v_existing.id IS NOT NULL THEN
        -- Content edits reset the credential to pending review.
        UPDATE public.coach_certifications
        SET name = v_item->>'name',
            issuer = v_item->>'issuer',
            issued_year = NULLIF(v_item->>'issued_year', '')::smallint,
            document_url = COALESCE(v_item->>'document_url', document_url),
            status = CASE
              WHEN name IS DISTINCT FROM v_item->>'name'
                OR issuer IS DISTINCT FROM v_item->>'issuer'
                OR issued_year IS DISTINCT FROM
                   NULLIF(v_item->>'issued_year', '')::smallint
                OR document_url IS DISTINCT FROM v_item->>'document_url'
              THEN 'pending' ELSE status END,
            reviewed_by = CASE
              WHEN name IS DISTINCT FROM v_item->>'name'
                OR issuer IS DISTINCT FROM v_item->>'issuer'
                OR issued_year IS DISTINCT FROM
                   NULLIF(v_item->>'issued_year', '')::smallint
                OR document_url IS DISTINCT FROM v_item->>'document_url'
              THEN NULL ELSE reviewed_by END,
            reviewed_at = CASE
              WHEN name IS DISTINCT FROM v_item->>'name'
                OR issuer IS DISTINCT FROM v_item->>'issuer'
                OR issued_year IS DISTINCT FROM
                   NULLIF(v_item->>'issued_year', '')::smallint
                OR document_url IS DISTINCT FROM v_item->>'document_url'
              THEN NULL ELSE reviewed_at END
        WHERE id = v_existing.id;
        v_kept := v_kept || v_existing.id;
        CONTINUE;
      END IF;
    END IF;
    INSERT INTO public.coach_certifications (
      coach_id, name, issuer, issued_year, document_url, status
    ) VALUES (
      v_coach_id, v_item->>'name', v_item->>'issuer',
      NULLIF(v_item->>'issued_year', '')::smallint,
      v_item->>'document_url', 'pending'
    )
    RETURNING id INTO v_new_id;
    v_kept := v_kept || v_new_id;
  END LOOP;

  -- Removed rows lose their credential status entirely.
  DELETE FROM public.coach_certifications
  WHERE coach_id = v_coach_id AND NOT (id = ANY(v_kept));

  UPDATE public.coach_profiles
  SET is_verified = EXISTS (
        SELECT 1 FROM public.coach_certifications c
        WHERE c.coach_id = v_coach_id AND c.status = 'approved'),
      updated_at = now()
  WHERE id = v_coach_id;
END;
$$;

-- review_coach_profile gains a 'rejected' decision. Rejection and
-- suspension both require a reason; approval of the profile is enough
-- to publish — verification stays derived from approved credentials.
CREATE OR REPLACE FUNCTION public.review_coach_profile(
  p_admin_id UUID,
  p_coach_id UUID,
  p_decision VARCHAR,  -- 'approved' | 'rejected' | 'suspended' | 'pending'
  p_verified BOOLEAN DEFAULT NULL,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_decision NOT IN ('approved','rejected','suspended','pending') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;
  IF p_decision IN ('rejected','suspended')
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  UPDATE public.coach_profiles
  SET status = p_decision,
      is_verified = COALESCE(p_verified, is_verified),
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      rejection_reason = p_reason,
      updated_at = now()
  WHERE id = p_coach_id
  RETURNING user_id, display_name INTO v_user_id, v_name;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;

  PERFORM public.sports_hub_notify(
    v_user_id, 'coach_supply', 'coach.profile_' || p_decision,
    CASE p_decision
      WHEN 'approved' THEN 'โปรไฟล์โค้ชได้รับการอนุมัติ'
      WHEN 'rejected' THEN 'โปรไฟล์โค้ชไม่ผ่านการตรวจสอบ'
      WHEN 'suspended' THEN 'โปรไฟล์โค้ชถูกระงับ'
      ELSE 'โปรไฟล์โค้ชอยู่ระหว่างตรวจสอบ'
    END,
    CASE
      WHEN p_decision = 'approved'
        THEN FORMAT('"%s" แสดงในรายการโค้ชแล้ว', v_name)
      ELSE FORMAT('%s — %s', v_name, COALESCE(p_reason, ''))
    END,
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'coachId', p_coach_id, 'status', p_decision));
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_coach_credentials(p_user_id UUID)
RETURNS SETOF public.coach_certifications
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN QUERY
  SELECT c.* FROM public.coach_certifications c
  JOIN public.coach_profiles p ON p.id = c.coach_id
  WHERE p.user_id = p_user_id
  ORDER BY c.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_coach_certification(
  p_admin_id UUID,
  p_cert_id UUID,
  p_decision VARCHAR,  -- 'approved' | 'rejected'
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cert RECORD;
  v_coach RECORD;
BEGIN
  IF NOT public.is_admin_role(p_admin_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  IF p_decision NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;
  IF p_decision = 'rejected'
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  UPDATE public.coach_certifications
  SET status = p_decision, reviewed_by = p_admin_id, reviewed_at = now(),
      rejection_reason = CASE
        WHEN p_decision = 'rejected' THEN p_reason ELSE NULL END
  WHERE id = p_cert_id
  RETURNING * INTO v_cert;

  IF v_cert.id IS NULL THEN
    RAISE EXCEPTION 'CERT_NOT_FOUND';
  END IF;

  UPDATE public.coach_profiles
  SET is_verified = EXISTS (
        SELECT 1 FROM public.coach_certifications c
        WHERE c.coach_id = v_cert.coach_id AND c.status = 'approved'),
      updated_at = now()
  WHERE id = v_cert.coach_id
  RETURNING user_id, display_name INTO v_coach;

  PERFORM public.sports_hub_notify(
    v_coach.user_id, 'coach_supply',
    'coach_certification.' || p_decision,
    CASE WHEN p_decision = 'approved'
         THEN 'ใบรับรองผ่านการตรวจสอบ' ELSE 'ใบรับรองไม่ผ่านการตรวจสอบ' END,
    FORMAT('%s — %s%s', v_coach.display_name, v_cert.name,
           CASE WHEN p_decision = 'rejected'
                THEN ' เหตุผล: ' || COALESCE(p_reason, 'ไม่ระบุ')
                ELSE '' END),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'coachId', v_cert.coach_id));
END;
$$;

-- Completeness checklist required before a profile can be submitted for
-- review. Returned as JSONB so the editor can flag missing fields.
CREATE OR REPLACE FUNCTION public.get_coach_profile_completeness(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  SELECT * INTO v_coach FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach.id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  RETURN jsonb_build_object(
    'coach_id', v_coach.id,
    'status', v_coach.status,
    'has_name', length(btrim(COALESCE(v_coach.display_name, ''))) > 0,
    'has_bio', length(btrim(COALESCE(v_coach.bio, ''))) > 0,
    'has_experience',
      length(btrim(COALESCE(v_coach.experience, ''))) > 0,
    'has_sport', EXISTS (
      SELECT 1 FROM public.coach_sports s
      WHERE s.coach_id = v_coach.id
        AND (cardinality(s.specialties) > 0
             OR cardinality(s.skill_levels) > 0)),
    'has_location', EXISTS (
      SELECT 1 FROM public.coach_teaching_locations l
      WHERE l.coach_id = v_coach.id),
    'has_pricing', v_coach.hourly_rate IS NOT NULL OR EXISTS (
      SELECT 1 FROM public.coach_offerings o
      WHERE o.coach_id = v_coach.id AND o.price IS NOT NULL),
    'has_credential', EXISTS (
      SELECT 1 FROM public.coach_certifications c
      WHERE c.coach_id = v_coach.id),
    'has_contact', EXISTS (
      SELECT 1 FROM public.coach_contacts ct
      WHERE ct.coach_id = v_coach.id
        AND (ct.phone IS NOT NULL OR ct.line_id IS NOT NULL
             OR ct.facebook_url IS NOT NULL))
  );
END;
$$;

-- Submit for admin review: requires the full checklist. Approved coaches
-- keep their status (post-approval edits publish immediately); rejected
-- profiles resubmit to pending; suspended cannot resubmit.
CREATE OR REPLACE FUNCTION public.submit_coach_profile_review(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_check JSONB;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  v_check := public.get_coach_profile_completeness(p_user_id);
  SELECT * INTO v_coach FROM public.coach_profiles
  WHERE user_id = p_user_id FOR UPDATE;

  IF v_coach.status = 'suspended' THEN
    RAISE EXCEPTION 'COACH_SUSPENDED';
  END IF;
  IF v_coach.status = 'pending' THEN
    RETURN; -- already queued
  END IF;
  IF NOT ((v_check->>'has_name')::boolean
      AND (v_check->>'has_bio')::boolean
      AND (v_check->>'has_experience')::boolean
      AND (v_check->>'has_sport')::boolean
      AND (v_check->>'has_location')::boolean
      AND (v_check->>'has_pricing')::boolean
      AND (v_check->>'has_credential')::boolean
      AND (v_check->>'has_contact')::boolean) THEN
    RAISE EXCEPTION 'PROFILE_INCOMPLETE';
  END IF;

  IF v_coach.status <> 'approved' THEN
    UPDATE public.coach_profiles
    SET status = 'pending', rejection_reason = NULL,
        reviewed_by = NULL, reviewed_at = NULL, updated_at = now()
    WHERE id = v_coach.id;

    INSERT INTO public.app_notifications (
      recipient_id, category, event_type, title, body, payload
    )
    SELECT u.id, 'coach_supply', 'coach.application_submitted',
           'มีคำขอสมัครโค้ชใหม่',
           FORMAT('%s ส่งโปรไฟล์โค้ชให้ตรวจสอบ', v_coach.display_name),
           JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                              'coachId', v_coach.id)
    FROM public.users u
    WHERE u.role = 'admin';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_coach_teaching_locations(
  p_user_id UUID,
  p_items JSONB
  -- [{"id": uuid?, "kind":"venue|custom","venue_id","name","address",
  --   "lat","lng","timezone"}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
  v_item JSONB;
  v_kept UUID[] := ARRAY[]::uuid[];
  v_id UUID;
  v_venue_tz VARCHAR(64);
BEGIN
  SELECT id INTO v_coach_id FROM public.coach_profiles
  WHERE user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
  LOOP
    IF length(btrim(COALESCE(v_item->>'name', ''))) = 0 THEN
      CONTINUE;
    END IF;
    IF COALESCE(v_item->>'kind', 'custom') NOT IN ('venue','custom') THEN
      RAISE EXCEPTION 'INVALID_LOCATION_KIND';
    END IF;
    IF v_item->>'kind' = 'venue' THEN
      -- Venue locations inherit the venue timezone snapshot.
      SELECT timezone INTO v_venue_tz FROM public.sports_venues
      WHERE id = NULLIF(v_item->>'venue_id', '')::uuid
        AND status = 'approved';
      IF v_venue_tz IS NULL THEN
        RAISE EXCEPTION 'VENUE_NOT_AVAILABLE';
      END IF;
    END IF;

    IF (v_item->>'id') IS NOT NULL THEN
      UPDATE public.coach_teaching_locations
      SET kind = COALESCE(v_item->>'kind', kind),
          venue_id = NULLIF(v_item->>'venue_id', '')::uuid,
          name = v_item->>'name',
          address = v_item->>'address',
          lat = NULLIF(v_item->>'lat', '')::double precision,
          lng = NULLIF(v_item->>'lng', '')::double precision,
          timezone = CASE WHEN v_item->>'kind' = 'venue'
                          THEN COALESCE(v_venue_tz, timezone)
                          ELSE COALESCE(
                            NULLIF(v_item->>'timezone', ''), timezone)
                     END
      WHERE id = (v_item->>'id')::uuid AND coach_id = v_coach_id
      RETURNING id INTO v_id;
      IF v_id IS NOT NULL THEN
        v_kept := v_kept || v_id;
        CONTINUE;
      END IF;
    END IF;

    INSERT INTO public.coach_teaching_locations (
      coach_id, kind, venue_id, name, address, lat, lng, timezone
    ) VALUES (
      v_coach_id, COALESCE(v_item->>'kind', 'custom'),
      NULLIF(v_item->>'venue_id', '')::uuid,
      v_item->>'name', v_item->>'address',
      NULLIF(v_item->>'lat', '')::double precision,
      NULLIF(v_item->>'lng', '')::double precision,
      CASE WHEN v_item->>'kind' = 'venue'
           THEN COALESCE(v_venue_tz, 'Asia/Bangkok')
           ELSE COALESCE(NULLIF(v_item->>'timezone', ''),
                         'Asia/Bangkok') END
    )
    RETURNING id INTO v_id;
    v_kept := v_kept || v_id;
  END LOOP;

  -- Locations referenced by offerings are detached, not deleted.
  DELETE FROM public.coach_teaching_locations l
  WHERE l.coach_id = v_coach_id
    AND NOT (l.id = ANY(v_kept))
    AND NOT EXISTS (
      SELECT 1 FROM public.coach_offerings o WHERE o.location_id = l.id);
END;
$$;

-- ===============
-- Favorites + relationship queries
-- ===============
CREATE OR REPLACE FUNCTION public.toggle_coach_favorite(
  p_user_id UUID,
  p_coach_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_status VARCHAR(10);
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  SELECT status INTO v_coach_status FROM public.coach_profiles
  WHERE id = p_coach_id;
  IF v_coach_status IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.coach_favorites
    WHERE user_id = p_user_id AND coach_id = p_coach_id
  ) THEN
    DELETE FROM public.coach_favorites
    WHERE user_id = p_user_id AND coach_id = p_coach_id;
    RETURN false;
  END IF;
  INSERT INTO public.coach_favorites (user_id, coach_id)
  VALUES (p_user_id, p_coach_id)
  ON CONFLICT DO NOTHING;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_coach_favorite_ids(p_user_id UUID)
RETURNS UUID[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN COALESCE((
    SELECT array_agg(coach_id) FROM public.coach_favorites
    WHERE user_id = p_user_id
  ), ARRAY[]::uuid[]);
END;
$$;

-- "ผู้ฝึกสอนของฉัน": coaches with a confirmed/completed relationship.
CREATE OR REPLACE FUNCTION public.list_my_coach_relationship_ids(
  p_user_id UUID
)
RETURNS UUID[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN COALESCE((
    SELECT array_agg(DISTINCT cid) FROM (
      SELECT r.coach_id AS cid FROM public.coach_booking_requests r
      WHERE r.user_id = p_user_id
        AND r.status IN ('confirmed','completed')
      UNION
      SELECT o.coach_id FROM public.coach_enrollments e
      JOIN public.coach_offerings o ON o.id = e.offering_id
      WHERE e.user_id = p_user_id
        AND e.status IN ('confirmed','completed')
    ) rel
  ), ARRAY[]::uuid[]);
END;
$$;

-- ===============
-- Offerings + sessions
-- ===============
CREATE OR REPLACE FUNCTION public.upsert_coach_offering(
  p_user_id UUID,
  p_offering_id UUID DEFAULT NULL,
  p_offering_type VARCHAR DEFAULT 'class',
  p_title VARCHAR DEFAULT NULL,
  p_description VARCHAR DEFAULT NULL,
  p_sport_id UUID DEFAULT NULL,
  p_learner_levels VARCHAR[] DEFAULT '{}',
  p_teaching_mode VARCHAR DEFAULT 'onsite',
  p_location_id UUID DEFAULT NULL,
  p_location_label VARCHAR DEFAULT NULL,
  p_timezone VARCHAR DEFAULT NULL,
  p_price NUMERIC DEFAULT NULL,
  p_pricing_unit VARCHAR DEFAULT 'per_hour',
  p_capacity INT DEFAULT NULL,
  p_min_enrollment INT DEFAULT 0,
  p_enrollment_cutoff_hours INT DEFAULT 24,
  p_cancellation_cutoff_hours INT DEFAULT 24,
  p_schedule_no_response VARCHAR DEFAULT 'cancel',
  p_auto_confirm BOOLEAN DEFAULT false,
  p_allow_partial_enrollment BOOLEAN DEFAULT true
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_offering RECORD;
  v_id UUID;
  v_tz VARCHAR(64);
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_offering_type NOT IN ('one_on_one','class','course') THEN
    RAISE EXCEPTION 'INVALID_OFFERING_TYPE';
  END IF;
  IF length(btrim(COALESCE(p_title, ''))) = 0 THEN
    RAISE EXCEPTION 'INVALID_TITLE';
  END IF;
  IF p_teaching_mode NOT IN ('onsite','online') THEN
    RAISE EXCEPTION 'INVALID_TEACHING_MODE';
  END IF;
  IF p_pricing_unit NOT IN
     ('per_hour','per_person','per_group','per_session','package') THEN
    RAISE EXCEPTION 'INVALID_PRICING_UNIT';
  END IF;
  IF p_schedule_no_response NOT IN ('cancel','keep') THEN
    RAISE EXCEPTION 'INVALID_NO_RESPONSE_POLICY';
  END IF;
  IF p_min_enrollment IS NOT NULL AND p_capacity IS NOT NULL
     AND p_min_enrollment > p_capacity THEN
    RAISE EXCEPTION 'MIN_EXCEEDS_CAPACITY';
  END IF;

  SELECT id, status, timezone INTO v_coach
  FROM public.coach_profiles WHERE user_id = p_user_id;
  IF v_coach.id IS NULL OR v_coach.status <> 'approved' THEN
    RAISE EXCEPTION 'COACH_NOT_APPROVED';
  END IF;

  -- Timezone policy: onsite uses the venue/custom location timezone,
  -- online uses the coach timezone.
  IF p_teaching_mode = 'online' THEN
    v_tz := COALESCE(v_coach.timezone, 'Asia/Bangkok');
  ELSE
    SELECT l.timezone INTO v_tz
    FROM public.coach_teaching_locations l
    WHERE l.id = p_location_id AND l.coach_id = v_coach.id;
    v_tz := COALESCE(
      v_tz,
      CASE WHEN p_offering_id IS NULL THEN v_coach.timezone
           ELSE (SELECT o.timezone FROM public.coach_offerings o
                 WHERE o.id = p_offering_id) END,
      'Asia/Bangkok');
  END IF;

  IF p_offering_id IS NULL THEN
    INSERT INTO public.coach_offerings (
      coach_id, offering_type, title, description, sport_id,
      learner_levels, teaching_mode, location_id, location_label,
      timezone, price, pricing_unit, capacity, min_enrollment,
      enrollment_cutoff_hours, cancellation_cutoff_hours,
      schedule_no_response, auto_confirm, allow_partial_enrollment,
      status
    ) VALUES (
      v_coach.id, p_offering_type, btrim(p_title), p_description,
      p_sport_id,
      COALESCE((
        SELECT array_agg(x) FROM unnest(p_learner_levels) x
        WHERE x IN ('beginner','intermediate','advanced','pro')
      ), '{}'),
      p_teaching_mode, p_location_id, p_location_label, v_tz,
      p_price, p_pricing_unit, p_capacity,
      COALESCE(p_min_enrollment, 0),
      COALESCE(p_enrollment_cutoff_hours, 24),
      COALESCE(p_cancellation_cutoff_hours, 24),
      COALESCE(p_schedule_no_response, 'cancel'),
      COALESCE(p_auto_confirm, false),
      COALESCE(p_allow_partial_enrollment, true), 'draft'
    )
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;

  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = p_offering_id FOR UPDATE;
  IF v_offering.id IS NULL OR v_offering.coach_id <> v_coach.id THEN
    RAISE EXCEPTION 'OFFERING_NOT_FOUND';
  END IF;
  IF v_offering.status IN ('cancelled','completed') THEN
    RAISE EXCEPTION 'OFFERING_NOT_EDITABLE';
  END IF;
  IF p_capacity IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.coach_enrollment_sessions es
    JOIN public.coach_enrollments e ON e.id = es.enrollment_id
    JOIN public.coach_offering_sessions s ON s.id = es.session_id
    WHERE e.offering_id = p_offering_id AND es.status = 'confirmed'
    GROUP BY s.id
    HAVING COUNT(*) > p_capacity
  ) THEN
    RAISE EXCEPTION 'CAPACITY_BELOW_CONFIRMED';
  END IF;

  UPDATE public.coach_offerings
  SET title = btrim(p_title), description = p_description,
      sport_id = COALESCE(p_sport_id, sport_id),
      learner_levels = COALESCE((
        SELECT array_agg(x) FROM unnest(p_learner_levels) x
        WHERE x IN ('beginner','intermediate','advanced','pro')
      ), learner_levels),
      teaching_mode = p_teaching_mode,
      location_id = p_location_id,
      location_label = p_location_label,
      timezone = v_tz,
      price = p_price, pricing_unit = p_pricing_unit,
      capacity = p_capacity,
      min_enrollment = COALESCE(p_min_enrollment, min_enrollment),
      enrollment_cutoff_hours = COALESCE(
        p_enrollment_cutoff_hours, enrollment_cutoff_hours),
      cancellation_cutoff_hours = COALESCE(
        p_cancellation_cutoff_hours, cancellation_cutoff_hours),
      schedule_no_response = COALESCE(
        p_schedule_no_response, schedule_no_response),
      auto_confirm = COALESCE(p_auto_confirm, auto_confirm),
      allow_partial_enrollment = COALESCE(
        p_allow_partial_enrollment, allow_partial_enrollment),
      updated_at = now()
  WHERE id = p_offering_id;
  RETURN p_offering_id;
END;
$$;

-- Replaces the session list. Sessions with enrollments cannot be
-- dropped silently — cancel them through cancel_coach_session instead.
CREATE OR REPLACE FUNCTION public.set_coach_offering_sessions(
  p_user_id UUID,
  p_offering_id UUID,
  p_sessions JSONB
  -- [{"id": uuid?,"starts_at","ends_at","seq","capacity","price",
  --   "location_label"}]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
  v_offering RECORD;
  v_item JSONB;
  v_kept UUID[] := ARRAY[]::uuid[];
  v_id UUID;
BEGIN
  SELECT p.id INTO v_coach_id FROM public.coach_profiles p
  WHERE p.user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = p_offering_id AND coach_id = v_coach_id
  FOR UPDATE;
  IF v_offering.id IS NULL THEN
    RAISE EXCEPTION 'OFFERING_NOT_FOUND';
  END IF;
  IF v_offering.status IN ('cancelled','completed') THEN
    RAISE EXCEPTION 'OFFERING_NOT_EDITABLE';
  END IF;

  FOR v_item IN
    SELECT * FROM jsonb_array_elements(COALESCE(p_sessions, '[]'::jsonb))
  LOOP
    IF (v_item->>'starts_at') IS NULL OR (v_item->>'ends_at') IS NULL
       OR (v_item->>'ends_at')::timestamptz
          <= (v_item->>'starts_at')::timestamptz THEN
      RAISE EXCEPTION 'INVALID_SESSION_TIME';
    END IF;

    IF (v_item->>'id') IS NOT NULL THEN
      -- Enrolled sessions keep their snapshot for learners who did not
      -- accept a change; reschedule goes through proposals instead.
      IF EXISTS (
        SELECT 1 FROM public.coach_enrollment_sessions es
        JOIN public.coach_enrollments e ON e.id = es.enrollment_id
        WHERE es.session_id = (v_item->>'id')::uuid
          AND e.status IN ('pending','confirmed')
      ) THEN
        UPDATE public.coach_offering_sessions
        SET seq = COALESCE((v_item->>'seq')::int, seq),
            capacity = COALESCE(
              NULLIF(v_item->>'capacity', '')::int, capacity),
            price = COALESCE(
              NULLIF(v_item->>'price', '')::numeric, price),
            updated_at = now()
        WHERE id = (v_item->>'id')::uuid AND offering_id = p_offering_id
        RETURNING id INTO v_id;
      ELSE
        UPDATE public.coach_offering_sessions
        SET seq = COALESCE((v_item->>'seq')::int, seq),
            starts_at = (v_item->>'starts_at')::timestamptz,
            ends_at = (v_item->>'ends_at')::timestamptz,
            timezone = COALESCE(NULLIF(v_item->>'timezone', ''),
                                v_offering.timezone),
            location_label = COALESCE(v_item->>'location_label',
                                      location_label),
            capacity = COALESCE(
              NULLIF(v_item->>'capacity', '')::int, capacity),
            price = COALESCE(
              NULLIF(v_item->>'price', '')::numeric, price),
            updated_at = now()
        WHERE id = (v_item->>'id')::uuid AND offering_id = p_offering_id
        RETURNING id INTO v_id;
      END IF;
      IF v_id IS NOT NULL THEN
        v_kept := v_kept || v_id;
        CONTINUE;
      END IF;
    END IF;

    INSERT INTO public.coach_offering_sessions (
      offering_id, seq, starts_at, ends_at, timezone, location_label,
      capacity, price
    ) VALUES (
      p_offering_id, COALESCE((v_item->>'seq')::int, 0),
      (v_item->>'starts_at')::timestamptz,
      (v_item->>'ends_at')::timestamptz,
      COALESCE(NULLIF(v_item->>'timezone', ''), v_offering.timezone),
      COALESCE(v_item->>'location_label', v_offering.location_label),
      NULLIF(v_item->>'capacity', '')::int,
      NULLIF(v_item->>'price', '')::numeric
    )
    RETURNING id INTO v_id;
    v_kept := v_kept || v_id;
  END LOOP;

  -- Unkept sessions without enrollments are deleted; enrolled ones stay.
  DELETE FROM public.coach_offering_sessions s
  WHERE s.offering_id = p_offering_id
    AND NOT (s.id = ANY(v_kept))
    AND NOT EXISTS (
      SELECT 1 FROM public.coach_enrollment_sessions es
      WHERE es.session_id = s.id)
    AND s.status = 'scheduled';
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_coach_offering(
  p_user_id UUID,
  p_offering_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
  v_offering RECORD;
BEGIN
  SELECT p.id INTO v_coach_id FROM public.coach_profiles p
  WHERE p.user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = p_offering_id AND coach_id = v_coach_id
  FOR UPDATE;
  IF v_offering.id IS NULL THEN
    RAISE EXCEPTION 'OFFERING_NOT_FOUND';
  END IF;
  IF v_offering.status NOT IN ('draft','closed') THEN
    RAISE EXCEPTION 'OFFERING_NOT_PUBLISHABLE';
  END IF;
  IF v_offering.offering_type <> 'one_on_one' AND NOT EXISTS (
    SELECT 1 FROM public.coach_offering_sessions s
    WHERE s.offering_id = p_offering_id AND s.status = 'scheduled'
      AND s.starts_at > now()
  ) THEN
    RAISE EXCEPTION 'NO_FUTURE_SESSIONS';
  END IF;
  IF v_offering.price IS NULL THEN
    RAISE EXCEPTION 'PRICE_REQUIRED';
  END IF;
  UPDATE public.coach_offerings
  SET status = 'published', min_decision = NULL, updated_at = now()
  WHERE id = p_offering_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.close_coach_offering(
  p_user_id UUID,
  p_offering_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT p.id INTO v_coach_id FROM public.coach_profiles p
  WHERE p.user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  UPDATE public.coach_offerings
  SET status = 'closed', updated_at = now()
  WHERE id = p_offering_id AND coach_id = v_coach_id
    AND status = 'published';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFERING_NOT_CLOSABLE';
  END IF;
END;
$$;

-- Cancels an offering/session set with a mandatory reason and notifies
-- every affected learner.
CREATE OR REPLACE FUNCTION public.cancel_coach_offering(
  p_user_id UUID,
  p_offering_id UUID,
  p_reason VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_offering RECORD;
  v_enrollment RECORD;
BEGIN
  IF length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;
  SELECT id, user_id, display_name INTO v_coach
  FROM public.coach_profiles WHERE user_id = p_user_id;
  IF v_coach.id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = p_offering_id AND coach_id = v_coach.id
  FOR UPDATE;
  IF v_offering.id IS NULL THEN
    RAISE EXCEPTION 'OFFERING_NOT_FOUND';
  END IF;
  IF v_offering.status IN ('cancelled','completed') THEN
    RAISE EXCEPTION 'OFFERING_NOT_CANCELLABLE';
  END IF;

  UPDATE public.coach_offerings
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_offering_id;
  UPDATE public.coach_offering_sessions
  SET status = 'cancelled', updated_at = now()
  WHERE offering_id = p_offering_id AND status = 'scheduled';

  FOR v_enrollment IN
    UPDATE public.coach_enrollments
    SET status = 'cancelled', cancelled_by = p_user_id,
        cancellation_reason = p_reason, cancelled_at = now(),
        updated_at = now()
    WHERE offering_id = p_offering_id
      AND status IN ('pending','confirmed')
    RETURNING id, user_id
  LOOP
    UPDATE public.coach_enrollment_sessions
    SET status = 'cancelled', updated_at = now()
    WHERE enrollment_id = v_enrollment.id
      AND status IN ('pending','confirmed');
    PERFORM public.sports_hub_notify(
      v_enrollment.user_id, 'coach_booking', 'coach_enrollment.cancelled',
      'คลาส/หลักสูตรถูกยกเลิก',
      FORMAT('%s · %s — เหตุผล: %s', v_coach.display_name,
             v_offering.title, p_reason),
      JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                         'offeringId', p_offering_id,
                         'enrollmentId', v_enrollment.id));
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_coach_session(
  p_user_id UUID,
  p_session_id UUID,
  p_reason VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_session RECORD;
  v_enrollment RECORD;
BEGIN
  IF length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;
  SELECT p.id, p.user_id, p.display_name INTO v_coach
  FROM public.coach_profiles p WHERE p.user_id = p_user_id;
  IF v_coach.id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  SELECT s.*, o.title AS offering_title, o.coach_id
  INTO v_session
  FROM public.coach_offering_sessions s
  JOIN public.coach_offerings o ON o.id = s.offering_id
  WHERE s.id = p_session_id
  FOR UPDATE OF s;
  IF v_session.id IS NULL OR v_session.coach_id <> v_coach.id THEN
    RAISE EXCEPTION 'SESSION_NOT_FOUND';
  END IF;
  IF v_session.status <> 'scheduled' THEN
    RAISE EXCEPTION 'SESSION_NOT_CANCELLABLE';
  END IF;

  UPDATE public.coach_offering_sessions
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_session_id;

  FOR v_enrollment IN
    UPDATE public.coach_enrollment_sessions es
    SET status = 'cancelled', updated_at = now()
    FROM public.coach_enrollments e
    WHERE es.enrollment_id = e.id AND es.session_id = p_session_id
      AND es.status IN ('pending','confirmed')
      AND e.status IN ('pending','confirmed')
    RETURNING es.enrollment_id AS id
  LOOP
    UPDATE public.coach_enrollments e
    SET status = 'cancelled', cancelled_by = p_user_id,
        cancellation_reason = p_reason, cancelled_at = now(),
        updated_at = now()
    WHERE e.id = v_enrollment.id
      AND NOT EXISTS (
        SELECT 1 FROM public.coach_enrollment_sessions x
        WHERE x.enrollment_id = e.id
          AND x.status IN ('pending','confirmed'))
    RETURNING e.user_id INTO v_enrollment;
  END LOOP;

  FOR v_enrollment IN
    SELECT DISTINCT e.id, e.user_id
    FROM public.coach_enrollments e
    JOIN public.coach_enrollment_sessions es ON es.enrollment_id = e.id
    WHERE es.session_id = p_session_id
      AND e.status IN ('pending','confirmed','cancelled')
      AND es.status = 'cancelled'
  LOOP
    PERFORM public.sports_hub_notify(
      v_enrollment.user_id, 'coach_booking',
      'coach_session.cancelled',
      'รอบเรียนถูกยกเลิก',
      FORMAT('%s · %s — เหตุผล: %s', v_coach.display_name,
             v_session.offering_title, p_reason),
      JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                         'sessionId', p_session_id,
                         'enrollmentId', v_enrollment.id));
  END LOOP;
END;
$$;

-- Public board for CoachDetailSheet: offerings with future sessions,
-- per-session confirmed counts and the viewer's enrollment state.
CREATE OR REPLACE FUNCTION public.get_coach_offering_board(
  p_coach_id UUID,
  p_viewer_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(offering_row ORDER BY offering_row->>'title')
    FROM (
      SELECT jsonb_build_object(
        'id', o.id,
        'offeringType', o.offering_type,
        'title', o.title,
        'description', o.description,
        'sportId', o.sport_id,
        'learnerLevels', o.learner_levels,
        'teachingMode', o.teaching_mode,
        'locationLabel', COALESCE(o.location_label, l.name),
        'timezone', o.timezone,
        'price', o.price,
        'pricingUnit', o.pricing_unit,
        'capacity', o.capacity,
        'minEnrollment', o.min_enrollment,
        'enrollmentCutoffHours', o.enrollment_cutoff_hours,
        'cancellationCutoffHours', o.cancellation_cutoff_hours,
        'cancellationPolicyVersion', o.cancellation_policy_version,
        'autoConfirm', o.auto_confirm,
        'allowPartialEnrollment', o.allow_partial_enrollment,
        'status', o.status,
        'sessions', COALESCE((
          SELECT jsonb_agg(sess ORDER BY sess->>'startsAt')
          FROM (
            SELECT jsonb_build_object(
              'id', s.id,
              'seq', s.seq,
              'startsAt', s.starts_at,
              'endsAt', s.ends_at,
              'timezone', s.timezone,
              'locationLabel', s.location_label,
              'capacity', COALESCE(s.capacity, o.capacity),
              'price', COALESCE(s.price, o.price),
              'status', s.status,
              'confirmedCount', (
                SELECT COUNT(*)::int
                FROM public.coach_enrollment_sessions es
                JOIN public.coach_enrollments e
                  ON e.id = es.enrollment_id
                WHERE es.session_id = s.id
                  AND es.status = 'confirmed'
                  AND e.status IN ('confirmed','completed')),
              'myEnrollmentStatus', (
                SELECT es.status FROM public.coach_enrollment_sessions es
                JOIN public.coach_enrollments e
                  ON e.id = es.enrollment_id
                WHERE es.session_id = s.id
                  AND e.user_id = p_viewer_id
                  AND e.status IN ('pending','confirmed','completed')
                LIMIT 1)
            ) AS sess
            FROM public.coach_offering_sessions s
            WHERE s.offering_id = o.id
            ORDER BY s.starts_at
          ) sessions
        ), '[]'::jsonb),
        'myEnrollmentId', (
          SELECT e.id FROM public.coach_enrollments e
          WHERE e.offering_id = o.id AND e.user_id = p_viewer_id
            AND e.status IN ('pending','confirmed','completed')
          LIMIT 1)
      ) AS offering_row
      FROM public.coach_offerings o
      LEFT JOIN public.coach_teaching_locations l ON l.id = o.location_id
      JOIN public.coach_profiles p ON p.id = o.coach_id
      WHERE o.coach_id = p_coach_id
        AND p.status = 'approved'
        AND o.status IN ('published','closed','completed')
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- Coach management board: all offerings with counts and sessions.
CREATE OR REPLACE FUNCTION public.list_my_coach_offerings(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT p.id INTO v_coach_id FROM public.coach_profiles p
  WHERE p.user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(offering_row ORDER BY offering_row->>'createdAt' DESC)
    FROM (
      SELECT jsonb_build_object(
        'id', o.id,
        'offeringType', o.offering_type,
        'title', o.title,
        'description', o.description,
        'sportId', o.sport_id,
        'learnerLevels', o.learner_levels,
        'teachingMode', o.teaching_mode,
        'locationId', o.location_id,
        'locationLabel', COALESCE(o.location_label, l.name),
        'timezone', o.timezone,
        'price', o.price,
        'pricingUnit', o.pricing_unit,
        'capacity', o.capacity,
        'minEnrollment', o.min_enrollment,
        'enrollmentCutoffHours', o.enrollment_cutoff_hours,
        'cancellationCutoffHours', o.cancellation_cutoff_hours,
        'cancellationPolicyVersion', o.cancellation_policy_version,
        'scheduleNoResponse', o.schedule_no_response,
        'autoConfirm', o.auto_confirm,
        'allowPartialEnrollment', o.allow_partial_enrollment,
        'status', o.status,
        'minDecision', o.min_decision,
        'reopenUntil', o.reopen_until,
        'createdAt', o.created_at,
        'firstSessionStart', (
          SELECT MIN(s.starts_at) FROM public.coach_offering_sessions s
          WHERE s.offering_id = o.id AND s.status = 'scheduled'),
        'confirmedCount', (
          SELECT COUNT(DISTINCT e.id)::int
          FROM public.coach_enrollments e
          WHERE e.offering_id = o.id AND e.status = 'confirmed'),
        'pendingCount', (
          SELECT COUNT(DISTINCT e.id)::int
          FROM public.coach_enrollments e
          WHERE e.offering_id = o.id AND e.status = 'pending'),
        'sessions', COALESCE((
          SELECT jsonb_agg(sess ORDER BY sess->>'startsAt')
          FROM (
            SELECT jsonb_build_object(
              'id', s.id, 'seq', s.seq,
              'startsAt', s.starts_at, 'endsAt', s.ends_at,
              'timezone', s.timezone,
              'locationLabel', s.location_label,
              'capacity', COALESCE(s.capacity, o.capacity),
              'price', COALESCE(s.price, o.price),
              'status', s.status,
              'confirmedCount', (
                SELECT COUNT(*)::int
                FROM public.coach_enrollment_sessions es
                JOIN public.coach_enrollments e
                  ON e.id = es.enrollment_id
                WHERE es.session_id = s.id AND es.status = 'confirmed'
                  AND e.status IN ('confirmed','completed')),
              'pendingCount', (
                SELECT COUNT(*)::int
                FROM public.coach_enrollment_sessions es
                JOIN public.coach_enrollments e
                  ON e.id = es.enrollment_id
                WHERE es.session_id = s.id AND es.status = 'pending'
                  AND e.status = 'pending')
            ) AS sess
            FROM public.coach_offering_sessions s
            WHERE s.offering_id = o.id
            ORDER BY s.starts_at
          ) sessions
        ), '[]'::jsonb)
      ) AS offering_row
      FROM public.coach_offerings o
      LEFT JOIN public.coach_teaching_locations l ON l.id = o.location_id
      WHERE o.coach_id = v_coach_id
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- ===============
-- 1:1 slots
-- ===============
CREATE OR REPLACE FUNCTION public.create_coach_slot(
  p_user_id UUID,
  p_offering_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ,
  p_publish BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_offering RECORD;
  v_slot_id UUID;
  v_hours NUMERIC;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL
     OR p_ends_at <= p_starts_at THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;
  IF p_starts_at <= now() THEN
    RAISE EXCEPTION 'SLOT_IN_PAST';
  END IF;
  SELECT id, status, timezone INTO v_coach
  FROM public.coach_profiles WHERE user_id = p_user_id;
  IF v_coach.id IS NULL OR v_coach.status <> 'approved' THEN
    RAISE EXCEPTION 'COACH_NOT_APPROVED';
  END IF;
  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = p_offering_id AND coach_id = v_coach.id
  FOR UPDATE;
  IF v_offering.id IS NULL
     OR v_offering.offering_type <> 'one_on_one' THEN
    RAISE EXCEPTION 'OFFERING_NOT_FOUND';
  END IF;

  -- No overlapping slot for the coach (draft/published/booked).
  IF EXISTS (
    SELECT 1 FROM public.coach_slots s
    WHERE s.coach_id = v_coach.id
      AND s.status IN ('draft','published','booked')
      AND s.starts_at < p_ends_at AND s.ends_at > p_starts_at
  ) THEN
    RAISE EXCEPTION 'SLOT_OVERLAP';
  END IF;

  v_hours := EXTRACT(EPOCH FROM (p_ends_at - p_starts_at)) / 3600.0;

  INSERT INTO public.coach_slots (
    coach_id, offering_id, starts_at, ends_at, timezone,
    price_snapshot, status
  ) VALUES (
    v_coach.id, p_offering_id, p_starts_at, p_ends_at,
    COALESCE(v_offering.timezone, v_coach.timezone),
    CASE WHEN v_offering.price IS NULL THEN NULL
         ELSE ROUND(v_offering.price * v_hours, 2) END,
    CASE WHEN p_publish THEN 'published' ELSE 'draft' END
  )
  RETURNING id INTO v_slot_id;
  RETURN v_slot_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_coach_slot(
  p_user_id UUID,
  p_slot_id UUID,
  p_starts_at TIMESTAMPTZ,
  p_ends_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
  v_slot RECORD;
  v_offering RECORD;
  v_hours NUMERIC;
BEGIN
  SELECT p.id INTO v_coach_id FROM public.coach_profiles p
  WHERE p.user_id = p_user_id;
  SELECT * INTO v_slot FROM public.coach_slots
  WHERE id = p_slot_id AND coach_id = v_coach_id
  FOR UPDATE;
  IF v_slot.id IS NULL THEN
    RAISE EXCEPTION 'SLOT_NOT_FOUND';
  END IF;
  -- Slots with requests/bookings cannot be edited silently.
  IF v_slot.status <> 'draft' OR EXISTS (
    SELECT 1 FROM public.coach_booking_requests r
    WHERE r.slot_id = p_slot_id
      AND r.status IN ('pending','confirmed')
  ) THEN
    RAISE EXCEPTION 'SLOT_NOT_EDITABLE';
  END IF;
  IF p_ends_at <= p_starts_at OR p_starts_at <= now() THEN
    RAISE EXCEPTION 'INVALID_SLOT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.coach_slots s
    WHERE s.coach_id = v_coach_id AND s.id <> p_slot_id
      AND s.status IN ('draft','published','booked')
      AND s.starts_at < p_ends_at AND s.ends_at > p_starts_at
  ) THEN
    RAISE EXCEPTION 'SLOT_OVERLAP';
  END IF;
  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = v_slot.offering_id;
  v_hours := EXTRACT(EPOCH FROM (p_ends_at - p_starts_at)) / 3600.0;
  UPDATE public.coach_slots
  SET starts_at = p_starts_at, ends_at = p_ends_at,
      price_snapshot = CASE WHEN v_offering.price IS NULL THEN NULL
                            ELSE ROUND(v_offering.price * v_hours, 2) END,
      updated_at = now()
  WHERE id = p_slot_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_coach_slot(
  p_user_id UUID,
  p_slot_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.coach_slots s
  SET status = 'published', updated_at = now()
  FROM public.coach_profiles p
  WHERE s.id = p_slot_id AND s.coach_id = p.id
    AND p.user_id = p_user_id AND s.status = 'draft'
    AND s.starts_at > now();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SLOT_NOT_PUBLISHABLE';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_coach_slot(
  p_user_id UUID,
  p_slot_id UUID,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slot RECORD;
  v_request RECORD;
BEGIN
  SELECT s.*, p.user_id AS coach_user_id
  INTO v_slot
  FROM public.coach_slots s
  JOIN public.coach_profiles p ON p.id = s.coach_id
  WHERE s.id = p_slot_id AND p.user_id = p_user_id
  FOR UPDATE OF s;
  IF v_slot.id IS NULL THEN
    RAISE EXCEPTION 'SLOT_NOT_FOUND';
  END IF;
  IF v_slot.status NOT IN ('draft','published') THEN
    RAISE EXCEPTION 'SLOT_NOT_CANCELLABLE';
  END IF;

  UPDATE public.coach_slots
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_slot_id;

  -- Pending requests on the cancelled slot are rejected with the reason.
  FOR v_request IN
    UPDATE public.coach_booking_requests
    SET status = 'rejected', decided_by = p_user_id, decided_at = now(),
        rejection_reason = COALESCE(NULLIF(btrim(p_reason), ''),
                                    'ช่วงเวลานี้ถูกยกเลิก'),
        updated_at = now()
    WHERE slot_id = p_slot_id AND status = 'pending'
    RETURNING id, user_id
  LOOP
    PERFORM public.sports_hub_notify(
      v_request.user_id, 'coach_booking', 'coach_booking.rejected',
      'คำขอจองถูกปฏิเสธ',
      'ช่วงเวลาที่ขอถูกโค้ชยกเลิก',
      JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                         'requestId', v_request.id,
                         'coachId', v_slot.coach_id));
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_coach_slots(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT p.id INTO v_coach_id FROM public.coach_profiles p
  WHERE p.user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'startsAt') FROM (
      SELECT jsonb_build_object(
        'id', s.id, 'offeringId', s.offering_id,
        'offeringTitle', o.title,
        'startsAt', s.starts_at, 'endsAt', s.ends_at,
        'timezone', s.timezone, 'price', s.price_snapshot,
        'status', s.status,
        'pendingRequests', (
          SELECT COUNT(*)::int FROM public.coach_booking_requests r
          WHERE r.slot_id = s.id AND r.status = 'pending')
      ) AS row
      FROM public.coach_slots s
      JOIN public.coach_offerings o ON o.id = s.offering_id
      WHERE s.coach_id = v_coach_id
      ORDER BY s.starts_at
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- Slot-based 1:1 request. Pending does not reserve the slot; approving
-- the first request claims it atomically.
CREATE OR REPLACE FUNCTION public.create_coach_booking_request_v2(
  p_user_id UUID,
  p_slot_id UUID,
  p_message VARCHAR DEFAULT NULL,
  p_idempotency_key VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slot RECORD;
  v_offering RECORD;
  v_coach RECORD;
  v_request_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT r.id INTO v_request_id
    FROM public.coach_booking_requests r
    WHERE r.user_id = p_user_id AND r.idempotency_key = p_idempotency_key;
    IF v_request_id IS NOT NULL THEN
      RETURN v_request_id;
    END IF;
  END IF;

  SELECT s.* INTO v_slot FROM public.coach_slots s
  WHERE s.id = p_slot_id
  FOR UPDATE;
  IF v_slot.id IS NULL OR v_slot.status <> 'published'
     OR v_slot.starts_at <= now() THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE';
  END IF;

  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = v_slot.offering_id;
  SELECT p.* INTO v_coach FROM public.coach_profiles p
  WHERE p.id = v_slot.coach_id;
  IF v_coach.status <> 'approved' OR NOT v_coach.accepting_students THEN
    RAISE EXCEPTION 'COACH_NOT_AVAILABLE';
  END IF;
  IF v_coach.user_id = p_user_id THEN
    RAISE EXCEPTION 'SELF_REQUEST_NOT_ALLOWED';
  END IF;

  -- One live request per learner per slot.
  IF EXISTS (
    SELECT 1 FROM public.coach_booking_requests r
    WHERE r.slot_id = p_slot_id AND r.user_id = p_user_id
      AND r.status IN ('pending','confirmed')
  ) THEN
    RAISE EXCEPTION 'ALREADY_REQUESTED';
  END IF;

  INSERT INTO public.coach_booking_requests (
    coach_id, user_id, sport_id, slot_id, teaching_mode_snapshot,
    hourly_rate_snapshot, timezone, starts_at, ends_at, message,
    status, idempotency_key
  ) VALUES (
    v_slot.coach_id, p_user_id, v_offering.sport_id, p_slot_id,
    v_offering.teaching_mode, v_slot.price_snapshot, v_slot.timezone,
    v_slot.starts_at, v_slot.ends_at, p_message, 'pending',
    p_idempotency_key
  )
  RETURNING id INTO v_request_id;

  PERFORM public.sports_hub_notify(
    v_coach.user_id, 'coach_booking', 'coach_booking.requested',
    'มีคำขอจองโค้ชใหม่',
    FORMAT('%s มีคำขอฝึกซ้อมใหม่', v_coach.display_name),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', v_request_id,
                       'coachId', v_slot.coach_id));
  PERFORM public.sports_hub_notify(
    p_user_id, 'coach_booking', 'coach_booking.requested',
    'ส่งคำขอจองโค้ชแล้ว',
    FORMAT('รอ %s ตอบรับ', v_coach.display_name),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', v_request_id,
                       'coachId', v_slot.coach_id));

  RETURN v_request_id;
END;
$$;

-- decide_coach_booking_request gains atomic slot claiming: approving a
-- slot-backed request books the slot and rejects the other pendings.
CREATE OR REPLACE FUNCTION public.decide_coach_booking_request(
  p_user_id UUID,
  p_request_id UUID,
  p_decision VARCHAR,  -- 'approve' | 'reject'
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_other RECORD;
BEGIN
  SELECT r.*, p.user_id AS coach_user_id, p.display_name AS coach_name
  INTO v_request
  FROM public.coach_booking_requests r
  JOIN public.coach_profiles p ON p.id = r.coach_id
  WHERE r.id = p_request_id
  FOR UPDATE OF r;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND';
  END IF;
  IF v_request.coach_user_id <> p_user_id
     AND NOT public.is_admin_role(p_user_id) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'REQUEST_NOT_PENDING';
  END IF;
  IF p_decision NOT IN ('approve','reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;
  IF p_decision = 'reject' AND
     length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  IF p_decision = 'approve' AND v_request.slot_id IS NOT NULL THEN
    -- First approval wins the slot; everyone else gets SLOT_TAKEN.
    UPDATE public.coach_slots
    SET status = 'booked', updated_at = now()
    WHERE id = v_request.slot_id AND status = 'published';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'SLOT_TAKEN';
    END IF;
  END IF;

  UPDATE public.coach_booking_requests
  SET status = CASE WHEN p_decision = 'approve' THEN 'confirmed'
                    ELSE 'rejected' END,
      decided_by = p_user_id, decided_at = now(),
      rejection_reason = CASE WHEN p_decision = 'reject' THEN p_reason END,
      updated_at = now()
  WHERE id = p_request_id;

  IF p_decision = 'approve' AND v_request.slot_id IS NOT NULL THEN
    FOR v_other IN
      UPDATE public.coach_booking_requests
      SET status = 'rejected', decided_by = p_user_id, decided_at = now(),
          rejection_reason = 'SLOT_TAKEN', updated_at = now()
      WHERE slot_id = v_request.slot_id AND status = 'pending'
        AND id <> p_request_id
      RETURNING id, user_id
    LOOP
      PERFORM public.sports_hub_notify(
        v_other.user_id, 'coach_booking', 'coach_booking.rejected',
        'ช่วงเวลานี้ถูกจองแล้ว',
        FORMAT('%s ตอบรับผู้เรียนคนอื่นสำหรับช่วงเวลานี้แล้ว',
               v_request.coach_name),
        JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                           'requestId', v_other.id,
                           'coachId', v_request.coach_id));
    END LOOP;
  END IF;

  PERFORM public.sports_hub_notify(
    v_request.user_id, 'coach_booking',
    'coach_booking.' || CASE WHEN p_decision = 'approve'
                             THEN 'confirmed' ELSE 'rejected' END,
    CASE WHEN p_decision = 'approve'
         THEN 'โค้ชตอบรับคำขอแล้ว' ELSE 'โค้ชปฏิเสธคำขอ' END,
    CASE WHEN p_decision = 'approve'
         THEN FORMAT('%s ยืนยันนัดฝึกซ้อม', v_request.coach_name)
         ELSE FORMAT('%s — เหตุผล: %s', v_request.coach_name,
                     COALESCE(p_reason, 'ไม่ระบุ')) END,
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', p_request_id,
                       'coachId', v_request.coach_id));
END;
$$;

-- Cancelling a confirmed slot-backed request frees the slot again.
CREATE OR REPLACE FUNCTION public.cancel_coach_booking_request(
  p_user_id UUID,
  p_request_id UUID,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_is_requester BOOLEAN;
  v_is_coach BOOLEAN;
BEGIN
  SELECT r.*, p.user_id AS coach_user_id, p.display_name AS coach_name
  INTO v_request
  FROM public.coach_booking_requests r
  JOIN public.coach_profiles p ON p.id = r.coach_id
  WHERE r.id = p_request_id
  FOR UPDATE OF r;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND';
  END IF;
  IF v_request.status NOT IN ('pending','confirmed') THEN
    RAISE EXCEPTION 'REQUEST_NOT_CANCELLABLE';
  END IF;

  v_is_requester := v_request.user_id = p_user_id;
  v_is_coach := v_request.coach_user_id = p_user_id
                OR public.is_admin_role(p_user_id);
  IF NOT v_is_requester AND NOT v_is_coach THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_is_coach AND NOT v_is_requester
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  UPDATE public.coach_booking_requests
  SET status = 'cancelled', cancelled_by = p_user_id,
      cancellation_reason = p_reason, cancelled_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  IF v_request.slot_id IS NOT NULL THEN
    UPDATE public.coach_slots
    SET status = CASE WHEN starts_at > now() THEN 'published'
                      ELSE 'expired' END,
        updated_at = now()
    WHERE id = v_request.slot_id AND status = 'booked';
  END IF;

  PERFORM public.sports_hub_notify(
    CASE WHEN v_is_requester THEN v_request.coach_user_id
         ELSE v_request.user_id END,
    'coach_booking', 'coach_booking.cancelled',
    'นัดฝึกซ้อมถูกยกเลิก',
    FORMAT('%s — %s', v_request.coach_name,
           COALESCE(p_reason, 'ผู้ใช้ยกเลิก')),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'requestId', p_request_id,
                       'coachId', v_request.coach_id));
END;
$$;

-- ===============
-- Enrollments
-- ===============
CREATE OR REPLACE FUNCTION public.create_coach_enrollment(
  p_user_id UUID,
  p_offering_id UUID,
  p_session_ids UUID[],
  p_policy_accepted BOOLEAN,
  p_idempotency_key VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offering RECORD;
  v_coach RECORD;
  v_enrollment_id UUID;
  v_first_start TIMESTAMPTZ;
  v_sessions UUID[];
  v_session_id UUID;
  v_status VARCHAR(10);
  v_scope VARCHAR(10);
  v_price NUMERIC;
  v_capacity INT;
  v_confirmed INT;
  v_policy_text TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF NOT COALESCE(p_policy_accepted, false) THEN
    RAISE EXCEPTION 'POLICY_CONSENT_REQUIRED';
  END IF;
  IF p_session_ids IS NULL OR cardinality(p_session_ids) = 0 THEN
    RAISE EXCEPTION 'NO_SESSIONS_SELECTED';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT e.id INTO v_enrollment_id FROM public.coach_enrollments e
    WHERE e.user_id = p_user_id
      AND e.idempotency_key = p_idempotency_key;
    IF v_enrollment_id IS NOT NULL THEN
      RETURN v_enrollment_id;
    END IF;
  END IF;

  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = p_offering_id
  FOR UPDATE;
  IF v_offering.id IS NULL
     OR v_offering.status NOT IN ('published','closed') THEN
    RAISE EXCEPTION 'OFFERING_NOT_OPEN';
  END IF;
  IF v_offering.offering_type = 'one_on_one' THEN
    RAISE EXCEPTION 'USE_SLOT_BOOKING';
  END IF;
  -- Reopened intake expires at reopen_until.
  IF v_offering.reopen_until IS NOT NULL
     AND now() > v_offering.reopen_until THEN
    RAISE EXCEPTION 'ENROLLMENT_CLOSED';
  END IF;

  SELECT p.* INTO v_coach FROM public.coach_profiles p
  WHERE p.id = v_offering.coach_id;
  IF v_coach.user_id = p_user_id THEN
    RAISE EXCEPTION 'SELF_ENROLLMENT_NOT_ALLOWED';
  END IF;

  -- Enrollment cutoff is measured from the offering's first session.
  SELECT MIN(s.starts_at) INTO v_first_start
  FROM public.coach_offering_sessions s
  WHERE s.offering_id = p_offering_id AND s.status = 'scheduled';
  IF v_first_start IS NULL THEN
    RAISE EXCEPTION 'OFFERING_NOT_OPEN';
  END IF;
  IF now() >= v_first_start
            - make_interval(hours => v_offering.enrollment_cutoff_hours)
     AND (v_offering.reopen_until IS NULL
          OR now() > v_offering.reopen_until) THEN
    RAISE EXCEPTION 'ENROLLMENT_CUTOFF_PASSED';
  END IF;

  -- Validate selected sessions belong to the offering and are open.
  SELECT array_agg(s.id ORDER BY s.starts_at) INTO v_sessions
  FROM public.coach_offering_sessions s
  WHERE s.offering_id = p_offering_id AND s.status = 'scheduled'
    AND s.starts_at > now()
    AND s.id = ANY(p_session_ids);
  IF v_sessions IS NULL
     OR cardinality(v_sessions) <> cardinality(p_session_ids) THEN
    RAISE EXCEPTION 'SESSION_UNAVAILABLE';
  END IF;

  IF v_offering.offering_type = 'course'
     AND NOT v_offering.allow_partial_enrollment THEN
    IF cardinality(v_sessions) <> (
      SELECT COUNT(*) FROM public.coach_offering_sessions s
      WHERE s.offering_id = p_offering_id AND s.status = 'scheduled'
        AND s.starts_at > now()
    ) THEN
      RAISE EXCEPTION 'COURSE_REQUIRES_ALL_SESSIONS';
    END IF;
    v_scope := 'course';
  ELSE
    v_scope := CASE WHEN v_offering.offering_type = 'course'
                    THEN 'sessions' ELSE 'sessions' END;
  END IF;

  -- Price snapshot.
  v_price := CASE v_offering.pricing_unit
    WHEN 'package' THEN v_offering.price
    ELSE (
      SELECT COALESCE(SUM(COALESCE(s.price, v_offering.price)), 0)
      FROM public.coach_offering_sessions s
      WHERE s.id = ANY(v_sessions)
    ) END;

  v_status := CASE
    WHEN v_offering.auto_confirm AND v_offering.status = 'published'
      THEN 'confirmed' ELSE 'pending' END;

  -- Confirmed enrollments consume seats atomically under the offering
  -- row lock; pending requests never hold capacity.
  IF v_status = 'confirmed' THEN
    FOREACH v_session_id IN ARRAY v_sessions LOOP
      SELECT COALESCE(s.capacity, v_offering.capacity) INTO v_capacity
      FROM public.coach_offering_sessions s WHERE s.id = v_session_id;
      SELECT COUNT(*) INTO v_confirmed
      FROM public.coach_enrollment_sessions es
      JOIN public.coach_enrollments e ON e.id = es.enrollment_id
      WHERE es.session_id = v_session_id AND es.status = 'confirmed'
        AND e.status IN ('confirmed','completed');
      IF v_capacity IS NOT NULL AND v_confirmed >= v_capacity THEN
        RAISE EXCEPTION 'SESSION_FULL';
      END IF;
    END LOOP;
  END IF;

  -- One live enrollment per learner per offering (the partial unique
  -- index also guards the race; this yields a clean error code).
  IF EXISTS (
    SELECT 1 FROM public.coach_enrollments e
    WHERE e.offering_id = p_offering_id AND e.user_id = p_user_id
      AND e.status IN ('pending','confirmed')
  ) THEN
    RAISE EXCEPTION 'ALREADY_ENROLLED';
  END IF;

  v_policy_text := FORMAT(
    'ยกเลิกได้ถึง %s ชั่วโมงก่อนเริ่ม session แรก (policy %s)',
    v_offering.cancellation_cutoff_hours,
    v_offering.cancellation_policy_version);

  INSERT INTO public.coach_enrollments (
    offering_id, user_id, scope, status, price_total, pricing_unit,
    cancellation_cutoff_hours, cancellation_policy_version,
    cancellation_policy_text, consent_at, idempotency_key
  ) VALUES (
    p_offering_id, p_user_id, v_scope, v_status, v_price,
    v_offering.pricing_unit, v_offering.cancellation_cutoff_hours,
    v_offering.cancellation_policy_version, v_policy_text, now(),
    p_idempotency_key
  )
  RETURNING id INTO v_enrollment_id;

  FOREACH v_session_id IN ARRAY v_sessions LOOP
    INSERT INTO public.coach_enrollment_sessions (
      enrollment_id, session_id, status
    ) VALUES (v_enrollment_id, v_session_id, v_status);
  END LOOP;

  PERFORM public.sports_hub_notify(
    v_coach.user_id, 'coach_booking', 'coach_enrollment.requested',
    'มีคำขอสมัครเรียนใหม่',
    FORMAT('%s · %s', v_coach.display_name, v_offering.title),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'offeringId', p_offering_id,
                       'enrollmentId', v_enrollment_id));
  PERFORM public.sports_hub_notify(
    p_user_id, 'coach_booking',
    'coach_enrollment.' || v_status,
    CASE WHEN v_status = 'confirmed'
         THEN 'สมัครเรียนสำเร็จ' ELSE 'ส่งคำขอสมัครแล้ว' END,
    FORMAT('%s · %s', v_coach.display_name, v_offering.title),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'offeringId', p_offering_id,
                       'enrollmentId', v_enrollment_id));

  RETURN v_enrollment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_coach_enrollment(
  p_user_id UUID,
  p_enrollment_id UUID,
  p_decision VARCHAR,  -- 'approve' | 'reject'
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enrollment RECORD;
  v_coach RECORD;
  v_es RECORD;
  v_capacity INT;
  v_confirmed INT;
BEGIN
  SELECT e.*, o.title AS offering_title, o.coach_id, o.capacity AS
         offering_capacity
  INTO v_enrollment
  FROM public.coach_enrollments e
  JOIN public.coach_offerings o ON o.id = e.offering_id
  WHERE e.id = p_enrollment_id
  FOR UPDATE OF e;
  IF v_enrollment.id IS NULL THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND';
  END IF;

  SELECT p.user_id, p.display_name INTO v_coach
  FROM public.coach_profiles p WHERE p.id = v_enrollment.coach_id;
  IF v_coach.user_id <> p_user_id
     AND NOT public.is_admin_role(p_user_id) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_enrollment.status <> 'pending' THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_PENDING';
  END IF;
  IF p_decision NOT IN ('approve','reject') THEN
    RAISE EXCEPTION 'INVALID_DECISION';
  END IF;
  IF p_decision = 'reject'
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  IF p_decision = 'approve' THEN
    -- Capacity recheck: approving can still fail when the session
    -- filled up after the request was filed.
    FOR v_es IN
      SELECT es.session_id FROM public.coach_enrollment_sessions es
      WHERE es.enrollment_id = p_enrollment_id AND es.status = 'pending'
      FOR UPDATE
    LOOP
      SELECT COALESCE(s.capacity, v_enrollment.offering_capacity)
      INTO v_capacity
      FROM public.coach_offering_sessions s
      WHERE s.id = v_es.session_id;
      SELECT COUNT(*) INTO v_confirmed
      FROM public.coach_enrollment_sessions x
      JOIN public.coach_enrollments e ON e.id = x.enrollment_id
      WHERE x.session_id = v_es.session_id AND x.status = 'confirmed'
        AND e.status IN ('confirmed','completed');
      IF v_capacity IS NOT NULL AND v_confirmed >= v_capacity THEN
        RAISE EXCEPTION 'SESSION_FULL';
      END IF;
    END LOOP;
    UPDATE public.coach_enrollment_sessions
    SET status = 'confirmed', updated_at = now()
    WHERE enrollment_id = p_enrollment_id AND status = 'pending';
  END IF;

  UPDATE public.coach_enrollments
  SET status = CASE WHEN p_decision = 'approve' THEN 'confirmed'
                    ELSE 'rejected' END,
      decided_by = p_user_id, decided_at = now(),
      rejection_reason = CASE WHEN p_decision = 'reject' THEN p_reason END,
      updated_at = now()
  WHERE id = p_enrollment_id;

  PERFORM public.sports_hub_notify(
    v_enrollment.user_id, 'coach_booking',
    'coach_enrollment.' || CASE WHEN p_decision = 'approve'
                                THEN 'confirmed' ELSE 'rejected' END,
    CASE WHEN p_decision = 'approve'
         THEN 'การสมัครได้รับการยืนยัน' ELSE 'คำขอสมัครถูกปฏิเสธ' END,
    FORMAT('%s%s', v_enrollment.offering_title,
           CASE WHEN p_decision = 'reject'
                THEN ' — เหตุผล: ' || COALESCE(p_reason, 'ไม่ระบุ')
                ELSE '' END),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'enrollmentId', p_enrollment_id,
                       'offeringId', v_enrollment.offering_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_coach_enrollment(
  p_user_id UUID,
  p_enrollment_id UUID,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enrollment RECORD;
  v_coach RECORD;
  v_is_learner BOOLEAN;
  v_is_coach BOOLEAN;
  v_first_start TIMESTAMPTZ;
BEGIN
  SELECT e.*, o.title AS offering_title, o.coach_id
  INTO v_enrollment
  FROM public.coach_enrollments e
  JOIN public.coach_offerings o ON o.id = e.offering_id
  WHERE e.id = p_enrollment_id
  FOR UPDATE OF e;
  IF v_enrollment.id IS NULL THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_FOUND';
  END IF;
  IF v_enrollment.status NOT IN ('pending','confirmed') THEN
    RAISE EXCEPTION 'ENROLLMENT_NOT_CANCELLABLE';
  END IF;

  SELECT p.user_id, p.display_name INTO v_coach
  FROM public.coach_profiles p WHERE p.id = v_enrollment.coach_id;
  v_is_learner := v_enrollment.user_id = p_user_id;
  v_is_coach := v_coach.user_id = p_user_id
                OR public.is_admin_role(p_user_id);
  IF NOT v_is_learner AND NOT v_is_coach THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_is_coach AND NOT v_is_learner
     AND length(btrim(COALESCE(p_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  -- Learner cancellation honors the accepted cutoff snapshot.
  IF v_is_learner AND NOT v_is_coach THEN
    SELECT MIN(COALESCE(es.override_starts_at, s.starts_at))
    INTO v_first_start
    FROM public.coach_enrollment_sessions es
    JOIN public.coach_offering_sessions s ON s.id = es.session_id
    WHERE es.enrollment_id = p_enrollment_id
      AND es.status IN ('pending','confirmed');
    IF v_first_start IS NOT NULL AND now() >= v_first_start
       - make_interval(hours =>
           COALESCE(v_enrollment.cancellation_cutoff_hours, 24)) THEN
      RAISE EXCEPTION 'CANCELLATION_CUTOFF_PASSED';
    END IF;
  END IF;

  UPDATE public.coach_enrollments
  SET status = 'cancelled', cancelled_by = p_user_id,
      cancellation_reason = p_reason, cancelled_at = now(),
      updated_at = now()
  WHERE id = p_enrollment_id;
  UPDATE public.coach_enrollment_sessions
  SET status = 'cancelled', updated_at = now()
  WHERE enrollment_id = p_enrollment_id
    AND status IN ('pending','confirmed');

  PERFORM public.sports_hub_notify(
    CASE WHEN v_is_learner THEN v_coach.user_id
         ELSE v_enrollment.user_id END,
    'coach_booking', 'coach_enrollment.cancelled',
    'การสมัครเรียนถูกยกเลิก',
    FORMAT('%s — %s', v_enrollment.offering_title,
           COALESCE(p_reason, 'ผู้เรียนยกเลิก')),
    JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                       'enrollmentId', p_enrollment_id,
                       'offeringId', v_enrollment.offering_id));
END;
$$;

-- Minimum-enrollment decision at/after the enrollment cutoff and before
-- the first session starts.
CREATE OR REPLACE FUNCTION public.resolve_coach_minimum(
  p_user_id UUID,
  p_offering_id UUID,
  p_action VARCHAR,  -- 'proceed' | 'cancel'
  p_reopen_until TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_offering RECORD;
  v_first_start TIMESTAMPTZ;
  v_confirmed INT;
  v_enrollment RECORD;
BEGIN
  SELECT p.id, p.user_id, p.display_name INTO v_coach
  FROM public.coach_profiles p WHERE p.user_id = p_user_id;
  IF v_coach.id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  SELECT * INTO v_offering FROM public.coach_offerings
  WHERE id = p_offering_id AND coach_id = v_coach.id
  FOR UPDATE;
  IF v_offering.id IS NULL THEN
    RAISE EXCEPTION 'OFFERING_NOT_FOUND';
  END IF;
  IF v_offering.min_enrollment <= 0
     OR v_offering.min_decision IS NOT NULL THEN
    RAISE EXCEPTION 'NO_MINIMUM_DECISION';
  END IF;

  SELECT MIN(s.starts_at) INTO v_first_start
  FROM public.coach_offering_sessions s
  WHERE s.offering_id = p_offering_id AND s.status = 'scheduled';
  IF v_first_start IS NULL OR now() >= v_first_start THEN
    RAISE EXCEPTION 'DECISION_WINDOW_CLOSED';
  END IF;
  -- The decision opens once enrollment intake is cut off.
  IF now() < v_first_start
             - make_interval(hours => v_offering.enrollment_cutoff_hours)
     AND (v_offering.reopen_until IS NULL
          OR now() < v_offering.reopen_until) THEN
    RAISE EXCEPTION 'DECISION_NOT_DUE';
  END IF;

  SELECT COUNT(DISTINCT e.id) INTO v_confirmed
  FROM public.coach_enrollments e
  WHERE e.offering_id = p_offering_id AND e.status = 'confirmed';
  IF v_confirmed >= v_offering.min_enrollment THEN
    RAISE EXCEPTION 'MINIMUM_ALREADY_MET';
  END IF;

  IF p_action = 'proceed' THEN
    IF p_reopen_until IS NOT NULL AND p_reopen_until > v_first_start THEN
      RAISE EXCEPTION 'REOPEN_PAST_FIRST_SESSION';
    END IF;
    UPDATE public.coach_offerings
    SET min_decision = 'proceed',
        reopen_until = p_reopen_until,
        status = CASE WHEN p_reopen_until IS NOT NULL
                      THEN 'published' ELSE 'closed' END,
        updated_at = now()
    WHERE id = p_offering_id;
    RETURN;
  END IF;

  IF p_action <> 'cancel' THEN
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  UPDATE public.coach_offerings
  SET min_decision = 'cancelled', status = 'cancelled', updated_at = now()
  WHERE id = p_offering_id;
  UPDATE public.coach_offering_sessions
  SET status = 'cancelled', updated_at = now()
  WHERE offering_id = p_offering_id AND status = 'scheduled';

  FOR v_enrollment IN
    UPDATE public.coach_enrollments
    SET status = 'cancelled', cancelled_by = p_user_id,
        cancellation_reason = 'ผู้สมัครไม่ถึงจำนวนขั้นต่ำ',
        cancelled_at = now(), updated_at = now()
    WHERE offering_id = p_offering_id
      AND status IN ('pending','confirmed')
    RETURNING id, user_id
  LOOP
    UPDATE public.coach_enrollment_sessions
    SET status = 'cancelled', updated_at = now()
    WHERE enrollment_id = v_enrollment.id
      AND status IN ('pending','confirmed');
    PERFORM public.sports_hub_notify(
      v_enrollment.user_id, 'coach_booking',
      'coach_enrollment.cancelled',
      'คลาส/หลักสูตรถูกยกเลิก',
      FORMAT('%s · %s — ผู้สมัครไม่ถึงจำนวนขั้นต่ำ',
             v_coach.display_name, v_offering.title),
      JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                         'offeringId', p_offering_id,
                         'enrollmentId', v_enrollment.id));
  END LOOP;
END;
$$;

-- Schedule-change proposal for one session; every confirmed learner
-- gets an accept/decline row. Original snapshots stay untouched.
CREATE OR REPLACE FUNCTION public.propose_coach_session_change(
  p_user_id UUID,
  p_session_id UUID,
  p_new_starts_at TIMESTAMPTZ,
  p_new_ends_at TIMESTAMPTZ,
  p_new_location VARCHAR DEFAULT NULL,
  p_reason VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach RECORD;
  v_session RECORD;
  v_proposal_id UUID;
  v_enrollment RECORD;
BEGIN
  IF p_new_ends_at <= p_new_starts_at THEN
    RAISE EXCEPTION 'INVALID_SESSION_TIME';
  END IF;
  SELECT p.id, p.user_id, p.display_name INTO v_coach
  FROM public.coach_profiles p WHERE p.user_id = p_user_id;
  IF v_coach.id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  SELECT s.*, o.coach_id, o.title AS offering_title
  INTO v_session
  FROM public.coach_offering_sessions s
  JOIN public.coach_offerings o ON o.id = s.offering_id
  WHERE s.id = p_session_id
  FOR UPDATE OF s;
  IF v_session.id IS NULL OR v_session.coach_id <> v_coach.id THEN
    RAISE EXCEPTION 'SESSION_NOT_FOUND';
  END IF;
  IF v_session.status <> 'scheduled' THEN
    RAISE EXCEPTION 'SESSION_NOT_CHANGEABLE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.coach_schedule_proposals p
    WHERE p.session_id = p_session_id AND p.status = 'open'
  ) THEN
    RAISE EXCEPTION 'PROPOSAL_ALREADY_OPEN';
  END IF;

  INSERT INTO public.coach_schedule_proposals (
    session_id, proposed_by, reason,
    old_starts_at, old_ends_at, old_location,
    new_starts_at, new_ends_at, new_location
  ) VALUES (
    p_session_id, p_user_id, p_reason,
    v_session.starts_at, v_session.ends_at, v_session.location_label,
    p_new_starts_at, p_new_ends_at, p_new_location
  )
  RETURNING id INTO v_proposal_id;

  FOR v_enrollment IN
    SELECT es.enrollment_id AS id, e.user_id
    FROM public.coach_enrollment_sessions es
    JOIN public.coach_enrollments e ON e.id = es.enrollment_id
    WHERE es.session_id = p_session_id AND es.status = 'confirmed'
      AND e.status = 'confirmed'
  LOOP
    INSERT INTO public.coach_schedule_change_responses (
      proposal_id, enrollment_id, user_id
    ) VALUES (v_proposal_id, v_enrollment.id, v_enrollment.user_id)
    ON CONFLICT DO NOTHING;
    PERFORM public.sports_hub_notify(
      v_enrollment.user_id, 'coach_booking',
      'coach_schedule.proposed',
      'โค้ชเสนอเปลี่ยนเวลาเรียน',
      FORMAT('%s · %s — โปรดตอบรับหรือปฏิเสธ',
             v_coach.display_name, v_session.offering_title),
      JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                         'proposalId', v_proposal_id,
                         'sessionId', p_session_id,
                         'enrollmentId', v_enrollment.id));
  END LOOP;

  RETURN v_proposal_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_coach_schedule_change(
  p_user_id UUID,
  p_proposal_id UUID,
  p_accept BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_response RECORD;
  v_proposal RECORD;
  v_no_response VARCHAR(8);
BEGIN
  SELECT r.*, e.user_id AS learner_id, e.status AS enrollment_status,
         e.offering_id
  INTO v_response
  FROM public.coach_schedule_change_responses r
  JOIN public.coach_enrollments e ON e.id = r.enrollment_id
  WHERE r.proposal_id = p_proposal_id AND r.user_id = p_user_id
  FOR UPDATE OF r;
  IF v_response.proposal_id IS NULL THEN
    RAISE EXCEPTION 'PROPOSAL_NOT_FOUND';
  END IF;
  IF v_response.response IS NOT NULL THEN
    RETURN; -- idempotent: the first answer wins
  END IF;

  SELECT * INTO v_proposal FROM public.coach_schedule_proposals
  WHERE id = p_proposal_id;
  IF v_proposal.status <> 'open' THEN
    RAISE EXCEPTION 'PROPOSAL_CLOSED';
  END IF;

  UPDATE public.coach_schedule_change_responses
  SET response = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
      responded_at = now()
  WHERE proposal_id = p_proposal_id AND enrollment_id = v_response.enrollment_id;

  IF p_accept THEN
    -- The accepted change becomes a schedule event on the learner's
    -- enrollment-session; the shared session row stays untouched.
    UPDATE public.coach_enrollment_sessions
    SET override_starts_at = v_proposal.new_starts_at,
        override_ends_at = v_proposal.new_ends_at,
        updated_at = now()
    WHERE enrollment_id = v_response.enrollment_id
      AND session_id = v_proposal.session_id;
  ELSE
    SELECT o.schedule_no_response INTO v_no_response
    FROM public.coach_offerings o WHERE o.id = v_response.offering_id;
    IF v_no_response = 'cancel' THEN
      UPDATE public.coach_enrollment_sessions
      SET status = 'cancelled', updated_at = now()
      WHERE enrollment_id = v_response.enrollment_id
        AND session_id = v_proposal.session_id;
      -- Whole enrollment lapses when no live sessions remain.
      UPDATE public.coach_enrollments e
      SET status = 'cancelled', cancelled_by = p_user_id,
          cancellation_reason = 'ปฏิเสธการเปลี่ยนตารางเรียน',
          cancelled_at = now(), updated_at = now()
      WHERE e.id = v_response.enrollment_id
        AND e.status IN ('pending','confirmed')
        AND NOT EXISTS (
          SELECT 1 FROM public.coach_enrollment_sessions es
          WHERE es.enrollment_id = e.id
            AND es.status IN ('pending','confirmed'));
    END IF;
  END IF;

  -- Proposal closes once every invited learner has answered.
  IF NOT EXISTS (
    SELECT 1 FROM public.coach_schedule_change_responses r
    WHERE r.proposal_id = p_proposal_id AND r.response IS NULL
  ) THEN
    UPDATE public.coach_schedule_proposals
    SET status = 'closed' WHERE id = p_proposal_id;
  END IF;
END;
$$;

-- ===============
-- Learner/coach enrollment reads
-- ===============
CREATE OR REPLACE FUNCTION public.list_my_coach_enrollments(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'createdAt' DESC) FROM (
      SELECT jsonb_build_object(
        'id', e.id,
        'offeringId', e.offering_id,
        'offeringTitle', o.title,
        'offeringType', o.offering_type,
        'coachId', o.coach_id,
        'coachName', cp.display_name,
        'scope', e.scope,
        'status', e.status,
        'priceTotal', e.price_total,
        'pricingUnit', e.pricing_unit,
        'cancellationCutoffHours', e.cancellation_cutoff_hours,
        'cancellationPolicyVersion', e.cancellation_policy_version,
        'cancellationPolicyText', e.cancellation_policy_text,
        'consentAt', e.consent_at,
        'rejectionReason', e.rejection_reason,
        'cancellationReason', e.cancellation_reason,
        'minEnrollment', o.min_enrollment,
        'confirmedCount', (
          SELECT COUNT(DISTINCT x.id)::int
          FROM public.coach_enrollments x
          WHERE x.offering_id = o.id AND x.status = 'confirmed'),
        'autoConfirm', o.auto_confirm,
        'offeringStatus', o.status,
        'createdAt', e.created_at,
        'sessions', COALESCE((
          SELECT jsonb_agg(sess ORDER BY sess->>'startsAt')
          FROM (
            SELECT jsonb_build_object(
              'sessionId', es.session_id,
              'seq', s.seq,
              'startsAt', COALESCE(es.override_starts_at, s.starts_at),
              'endsAt', COALESCE(es.override_ends_at, s.ends_at),
              'originalStartsAt', s.starts_at,
              'originalEndsAt', s.ends_at,
              'timezone', s.timezone,
              'locationLabel', COALESCE(s.location_label,
                                        o.location_label),
              'status', es.status,
              'price', COALESCE(s.price, o.price),
              'hasReview', EXISTS (
                SELECT 1 FROM public.coach_reviews rv
                WHERE rv.enrollment_id = e.id
                  AND rv.session_id = es.session_id),
              'proposal', (
                SELECT jsonb_build_object(
                  'id', pr.id,
                  'newStartsAt', pr.new_starts_at,
                  'newEndsAt', pr.new_ends_at,
                  'newLocation', pr.new_location,
                  'reason', pr.reason,
                  'myResponse', rr.response)
                FROM public.coach_schedule_proposals pr
                JOIN public.coach_schedule_change_responses rr
                  ON rr.proposal_id = pr.id
                 AND rr.enrollment_id = e.id
                WHERE pr.session_id = es.session_id
                  AND pr.status = 'open'
                LIMIT 1)
            ) AS sess
            FROM public.coach_enrollment_sessions es
            JOIN public.coach_offering_sessions s
              ON s.id = es.session_id
            WHERE es.enrollment_id = e.id
            ORDER BY COALESCE(es.override_starts_at, s.starts_at)
          ) sessions
        ), '[]'::jsonb)
      ) AS row
      FROM public.coach_enrollments e
      JOIN public.coach_offerings o ON o.id = e.offering_id
      JOIN public.coach_profiles cp ON cp.id = o.coach_id
      WHERE e.user_id = p_user_id
      ORDER BY e.created_at DESC
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- Coach-side queue + roster: enrollments grouped per offering/session.
CREATE OR REPLACE FUNCTION public.list_coach_enrollments_for_coach(
  p_user_id UUID,
  p_statuses VARCHAR[] DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT p.id INTO v_coach_id FROM public.coach_profiles p
  WHERE p.user_id = p_user_id;
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'COACH_NOT_FOUND';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY row->>'createdAt' DESC) FROM (
      SELECT jsonb_build_object(
        'id', e.id,
        'offeringId', e.offering_id,
        'offeringTitle', o.title,
        'offeringType', o.offering_type,
        'learnerName', NULLIF(btrim(
          CONCAT_WS(' ', u.first_name, u.last_name)), ''),
        'userId', e.user_id,
        'scope', e.scope,
        'status', e.status,
        'priceTotal', e.price_total,
        'pricingUnit', e.pricing_unit,
        'rejectionReason', e.rejection_reason,
        'cancellationReason', e.cancellation_reason,
        'createdAt', e.created_at,
        'sessions', COALESCE((
          SELECT jsonb_agg(sess ORDER BY sess->>'startsAt')
          FROM (
            SELECT jsonb_build_object(
              'sessionId', es.session_id,
              'startsAt', COALESCE(es.override_starts_at, s.starts_at),
              'endsAt', COALESCE(es.override_ends_at, s.ends_at),
              'timezone', s.timezone,
              'locationLabel', COALESCE(s.location_label,
                                        o.location_label),
              'status', es.status,
              'capacity', COALESCE(s.capacity, o.capacity),
              'confirmedCount', (
                SELECT COUNT(*)::int
                FROM public.coach_enrollment_sessions x
                JOIN public.coach_enrollments e2
                  ON e2.id = x.enrollment_id
                WHERE x.session_id = es.session_id
                  AND x.status = 'confirmed'
                  AND e2.status IN ('confirmed','completed'))
            ) AS sess
            FROM public.coach_enrollment_sessions es
            JOIN public.coach_offering_sessions s
              ON s.id = es.session_id
            WHERE es.enrollment_id = e.id
            ORDER BY COALESCE(es.override_starts_at, s.starts_at)
          ) sessions
        ), '[]'::jsonb)
      ) AS row
      FROM public.coach_enrollments e
      JOIN public.coach_offerings o ON o.id = e.offering_id
      LEFT JOIN public.users u ON u.id = e.user_id
      WHERE o.coach_id = v_coach_id
        AND (p_statuses IS NULL OR e.status = ANY(p_statuses))
      ORDER BY e.created_at DESC
    ) rows
  ), '[]'::jsonb);
END;
$$;

-- ===============
-- Housekeeping
-- ===============

-- Slot expiry + enrollment expiry at cutoff + under-minimum auto-cancel
-- + session completion + no-response policy application. Idempotent and
-- safe to run on a cron.
CREATE OR REPLACE FUNCTION public.housekeep_coach_scheduling()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired_slots INT := 0;
  v_expired_enrollments INT := 0;
  v_auto_cancelled INT := 0;
  v_completed_sessions INT := 0;
  v_no_response INT := 0;
  v_offering RECORD;
  v_enrollment RECORD;
  v_response RECORD;
BEGIN
  -- Published slots past their start are no longer bookable.
  UPDATE public.coach_slots
  SET status = 'expired', updated_at = now()
  WHERE status = 'published' AND starts_at <= now();
  GET DIAGNOSTICS v_expired_slots = ROW_COUNT;

  -- Pending enrollments lapse at the offering cutoff (or reopen_until).
  FOR v_enrollment IN
    UPDATE public.coach_enrollments e
    SET status = 'expired', updated_at = now()
    FROM public.coach_offerings o
    WHERE e.offering_id = o.id AND e.status = 'pending'
      AND o.status IN ('published','closed')
      AND now() >= (
        SELECT MIN(s.starts_at) FROM public.coach_offering_sessions s
        WHERE s.offering_id = o.id AND s.status = 'scheduled')
        - make_interval(hours => o.enrollment_cutoff_hours)
      AND (o.reopen_until IS NULL OR now() > o.reopen_until)
    RETURNING e.id, e.user_id, e.offering_id
  LOOP
    UPDATE public.coach_enrollment_sessions
    SET status = 'expired', updated_at = now()
    WHERE enrollment_id = v_enrollment.id AND status = 'pending';
    PERFORM public.sports_hub_notify(
      v_enrollment.user_id, 'coach_booking', 'coach_enrollment.expired',
      'คำขอสมัครหมดอายุ',
      'คำขอของคุณหมดอายุเมื่อถึงเวลาปิดรับสมัคร',
      JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                         'enrollmentId', v_enrollment.id,
                         'offeringId', v_enrollment.offering_id));
    v_expired_enrollments := v_expired_enrollments + 1;
  END LOOP;

  -- Offerings that reached their first session still below minimum
  -- without a coach decision are auto-cancelled.
  FOR v_offering IN
    SELECT o.* FROM public.coach_offerings o
    WHERE o.status IN ('published','closed')
      AND o.min_enrollment > 0
      AND o.min_decision IS NULL
      AND (SELECT MIN(s.starts_at) FROM public.coach_offering_sessions s
           WHERE s.offering_id = o.id AND s.status = 'scheduled')
          <= now()
      AND (SELECT COUNT(DISTINCT e.id) FROM public.coach_enrollments e
           WHERE e.offering_id = o.id AND e.status = 'confirmed')
          < o.min_enrollment
  LOOP
    UPDATE public.coach_offerings
    SET status = 'cancelled', min_decision = 'cancelled',
        updated_at = now()
    WHERE id = v_offering.id;
    UPDATE public.coach_offering_sessions
    SET status = 'cancelled', updated_at = now()
    WHERE offering_id = v_offering.id AND status = 'scheduled';
    FOR v_enrollment IN
      UPDATE public.coach_enrollments
      SET status = 'cancelled',
          cancellation_reason = 'ผู้สมัครไม่ถึงจำนวนขั้นต่ำ',
          cancelled_at = now(), updated_at = now()
      WHERE offering_id = v_offering.id
        AND status IN ('pending','confirmed')
      RETURNING id, user_id
    LOOP
      UPDATE public.coach_enrollment_sessions
      SET status = 'cancelled', updated_at = now()
      WHERE enrollment_id = v_enrollment.id
        AND status IN ('pending','confirmed');
      PERFORM public.sports_hub_notify(
        v_enrollment.user_id, 'coach_booking',
        'coach_enrollment.cancelled',
        'คลาส/หลักสูตรถูกยกเลิก',
        FORMAT('%s — ผู้สมัครไม่ถึงจำนวนขั้นต่ำ', v_offering.title),
        JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                           'enrollmentId', v_enrollment.id,
                           'offeringId', v_offering.id));
    END LOOP;
    v_auto_cancelled := v_auto_cancelled + 1;
  END LOOP;

  -- Unanswered proposals apply the offering no-response policy at the
  -- earlier of old/new start.
  FOR v_response IN
    SELECT r.*, p.session_id, p.new_starts_at, p.new_ends_at,
           p.id AS prop_id, o.schedule_no_response, o.id AS offering_id
    FROM public.coach_schedule_change_responses r
    JOIN public.coach_schedule_proposals p ON p.id = r.proposal_id
    JOIN public.coach_enrollment_sessions es
      ON es.enrollment_id = r.enrollment_id
     AND es.session_id = p.session_id
    JOIN public.coach_enrollments e ON e.id = r.enrollment_id
    JOIN public.coach_offerings o ON o.id = e.offering_id
    WHERE r.response IS NULL AND p.status = 'open'
      AND es.status = 'confirmed' AND e.status = 'confirmed'
      AND now() >= LEAST(p.old_starts_at, p.new_starts_at)
  LOOP
    UPDATE public.coach_schedule_change_responses
    SET responded_at = now()  -- policy-applied, response stays NULL
    WHERE proposal_id = v_response.prop_id
      AND enrollment_id = v_response.enrollment_id;
    IF v_response.schedule_no_response = 'cancel' THEN
      UPDATE public.coach_enrollment_sessions
      SET status = 'cancelled', updated_at = now()
      WHERE enrollment_id = v_response.enrollment_id
        AND session_id = v_response.session_id;
      UPDATE public.coach_enrollments e
      SET status = 'cancelled',
          cancellation_reason = 'ไม่ตอบรับการเปลี่ยนตารางเรียน',
          cancelled_at = now(), updated_at = now()
      WHERE e.id = v_response.enrollment_id
        AND e.status = 'confirmed'
        AND NOT EXISTS (
          SELECT 1 FROM public.coach_enrollment_sessions x
          WHERE x.enrollment_id = e.id
            AND x.status IN ('pending','confirmed'));
      PERFORM public.sports_hub_notify(
        v_response.user_id, 'coach_booking',
        'coach_enrollment.cancelled',
        'การสมัครถูกยกเลิกตามนโยบาย',
        'ไม่ได้ตอบรับการเปลี่ยนตารางเรียนภายในเวลาที่กำหนด',
        JSONB_BUILD_OBJECT('route', '/community/sports/coaches',
                           'enrollmentId', v_response.enrollment_id,
                           'offeringId', v_response.offering_id));
    END IF;
    v_no_response := v_no_response + 1;
  END LOOP;
  UPDATE public.coach_schedule_proposals p
  SET status = 'closed'
  WHERE p.status = 'open' AND NOT EXISTS (
    SELECT 1 FROM public.coach_schedule_change_responses r
    WHERE r.proposal_id = p.id AND r.response IS NULL
      AND r.responded_at IS NULL);

  -- Confirmed enrollment-sessions complete when their effective end
  -- time passes.
  FOR v_enrollment IN
    UPDATE public.coach_enrollment_sessions es
    SET status = 'completed', updated_at = now()
    FROM public.coach_offering_sessions s
    WHERE es.session_id = s.id AND es.status = 'confirmed'
      AND COALESCE(es.override_ends_at, s.ends_at) <= now()
    RETURNING es.enrollment_id AS id
  LOOP
    UPDATE public.coach_enrollments e
    SET status = 'completed', updated_at = now()
    WHERE e.id = v_enrollment.id AND e.status = 'confirmed'
      AND NOT EXISTS (
        SELECT 1 FROM public.coach_enrollment_sessions x
        WHERE x.enrollment_id = e.id
          AND x.status IN ('pending','confirmed'));
    v_completed_sessions := v_completed_sessions + 1;
  END LOOP;

  -- Session rows themselves also complete for the roster view.
  UPDATE public.coach_offering_sessions s
  SET status = 'completed', updated_at = now()
  WHERE s.status = 'scheduled' AND s.ends_at <= now();

  UPDATE public.coach_offerings o
  SET status = 'completed', updated_at = now()
  WHERE o.status IN ('published','closed') AND NOT EXISTS (
    SELECT 1 FROM public.coach_offering_sessions s
    WHERE s.offering_id = o.id AND s.status = 'scheduled');

  RETURN jsonb_build_object(
    'expiredSlots', v_expired_slots,
    'expiredEnrollments', v_expired_enrollments,
    'autoCancelledOfferings', v_auto_cancelled,
    'completedEnrollmentSessions', v_completed_sessions,
    'noResponseApplied', v_no_response);
END;
$$;

-- ===============
-- Coach reviews v2 (1–10, five mandatory categories)
-- ===============

CREATE OR REPLACE FUNCTION public.list_coach_review_categories()
RETURNS SETOF public.coach_review_category_catalog
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.coach_review_category_catalog
  WHERE is_active
  ORDER BY display_order, label_th;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_coach_review_tags()
RETURNS SETOF public.coach_review_tag_catalog
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.coach_review_tag_catalog
  WHERE is_active
  ORDER BY display_order, label_th;
END;
$$;

-- v1 adapter: the legacy 1–5 submit keeps working for old clients and
-- writes the scaled rating_10 as a legacy review (no category scores).
CREATE OR REPLACE FUNCTION public.submit_coach_review(
  p_user_id UUID,
  p_request_id UUID,
  p_rating INT,
  p_comment VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_review_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'INVALID_RATING';
  END IF;
  IF p_comment IS NOT NULL AND length(p_comment) > 500 THEN
    RAISE EXCEPTION 'COMMENT_TOO_LONG';
  END IF;

  SELECT r.*, p.user_id AS coach_user_id INTO v_request
  FROM public.coach_booking_requests r
  JOIN public.coach_profiles p ON p.id = r.coach_id
  WHERE r.id = p_request_id
  FOR UPDATE OF r;

  IF v_request.id IS NULL OR v_request.user_id <> p_user_id THEN
    RAISE EXCEPTION 'REQUEST_NOT_FOUND';
  END IF;
  IF v_request.status <> 'completed' THEN
    RAISE EXCEPTION 'REQUEST_NOT_COMPLETED';
  END IF;
  IF v_request.coach_user_id = p_user_id THEN
    RAISE EXCEPTION 'SELF_REVIEW_NOT_ALLOWED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.coach_reviews r WHERE r.booking_id = p_request_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_REVIEWED';
  END IF;

  INSERT INTO public.coach_reviews (
    coach_id, booking_id, user_id, rating, rating_10, is_legacy, comment
  ) VALUES (
    v_request.coach_id, p_request_id, p_user_id,
    p_rating, p_rating * 2, true,
    NULLIF(btrim(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;
  RETURN v_review_id;
END;
$$;

-- v2 submit: exactly one source (completed 1:1 booking OR a completed
-- enrollment session), all five category scores, derived overall.
CREATE OR REPLACE FUNCTION public.submit_coach_review_v2(
  p_user_id UUID,
  p_category_scores JSONB,
  p_comment VARCHAR DEFAULT NULL,
  p_tag_ids UUID[] DEFAULT NULL,
  p_custom_tags TEXT[] DEFAULT NULL,
  p_booking_id UUID DEFAULT NULL,
  p_enrollment_id UUID DEFAULT NULL,
  p_session_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_coach_id UUID;
  v_coach_user UUID;
  v_review_id UUID;
  v_tag_count INT;
  v_category RECORD;
  v_score NUMERIC;
  v_seen UUID[] := ARRAY[]::uuid[];
  v_overall NUMERIC;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  IF (p_booking_id IS NULL) = (p_enrollment_id IS NULL) THEN
    RAISE EXCEPTION 'INVALID_REVIEW_SOURCE';
  END IF;
  IF (p_enrollment_id IS NULL) <> (p_session_id IS NULL) THEN
    RAISE EXCEPTION 'INVALID_REVIEW_SOURCE';
  END IF;
  IF p_comment IS NOT NULL AND length(p_comment) > 500 THEN
    RAISE EXCEPTION 'COMMENT_TOO_LONG';
  END IF;
  IF p_category_scores IS NULL
     OR jsonb_typeof(p_category_scores) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_CATEGORY_SCORES';
  END IF;

  v_seen := ARRAY[]::uuid[];
  FOR v_category IN
    SELECT key, value FROM jsonb_each(p_category_scores)
  LOOP
    BEGIN
      v_score := (v_category.value)::numeric;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'INVALID_CATEGORY_SCORES';
    END;
    IF v_score <> trunc(v_score) OR v_score < 1 OR v_score > 10 THEN
      RAISE EXCEPTION 'INVALID_CATEGORY_SCORES';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.coach_review_category_catalog c
      WHERE c.id = v_category.key::uuid AND c.is_active
    ) THEN
      RAISE EXCEPTION 'INVALID_CATEGORY';
    END IF;
    v_seen := v_seen || v_category.key::uuid;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM public.coach_review_category_catalog c
    WHERE c.is_active AND NOT (c.id = ANY(v_seen))
  ) THEN
    RAISE EXCEPTION 'MISSING_CATEGORY_SCORES';
  END IF;

  v_tag_count := COALESCE(array_length(p_tag_ids, 1), 0)
               + COALESCE(array_length(p_custom_tags, 1), 0);
  IF v_tag_count > 5 THEN
    RAISE EXCEPTION 'TOO_MANY_TAGS';
  END IF;
  IF p_tag_ids IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_tag_ids) t
    WHERE NOT EXISTS (
      SELECT 1 FROM public.coach_review_tag_catalog c
      WHERE c.id = t AND c.is_active
    )
  ) THEN
    RAISE EXCEPTION 'INVALID_TAG';
  END IF;

  IF p_booking_id IS NOT NULL THEN
    SELECT r.coach_id, p.user_id AS coach_user_id
    INTO v_coach_id, v_coach_user
    FROM public.coach_booking_requests r
    JOIN public.coach_profiles p ON p.id = r.coach_id
    WHERE r.id = p_booking_id AND r.user_id = p_user_id
      AND r.status = 'completed';
    IF v_coach_id IS NULL THEN
      RAISE EXCEPTION 'BOOKING_NOT_COMPLETED';
    END IF;
  ELSE
    SELECT o.coach_id, p.user_id INTO v_coach_id, v_coach_user
    FROM public.coach_enrollments e
    JOIN public.coach_enrollment_sessions es
      ON es.enrollment_id = e.id AND es.session_id = p_session_id
    JOIN public.coach_offerings o ON o.id = e.offering_id
    JOIN public.coach_profiles p ON p.id = o.coach_id
    WHERE e.id = p_enrollment_id AND e.user_id = p_user_id
      AND e.status IN ('confirmed','completed')
      AND es.status = 'completed';
    IF v_coach_id IS NULL THEN
      RAISE EXCEPTION 'SESSION_NOT_COMPLETED';
    END IF;
  END IF;
  IF v_coach_user = p_user_id THEN
    RAISE EXCEPTION 'SELF_REVIEW_NOT_ALLOWED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.coach_reviews r
    WHERE (p_booking_id IS NOT NULL AND r.booking_id = p_booking_id)
       OR (p_enrollment_id IS NOT NULL
           AND r.enrollment_id = p_enrollment_id
           AND r.session_id = p_session_id)
  ) THEN
    RAISE EXCEPTION 'ALREADY_REVIEWED';
  END IF;

  -- Equal-weighted mean of the five categories, one decimal.
  SELECT ROUND(AVG((value)::numeric), 1) INTO v_overall
  FROM jsonb_each(p_category_scores);

  INSERT INTO public.coach_reviews (
    coach_id, booking_id, enrollment_id, session_id, user_id,
    rating, rating_10, is_legacy, rubric_version, comment
  ) VALUES (
    v_coach_id, p_booking_id, p_enrollment_id, p_session_id, p_user_id,
    NULL, v_overall, false, 'v2',
    NULLIF(btrim(COALESCE(p_comment, '')), '')
  )
  RETURNING id INTO v_review_id;

  INSERT INTO public.coach_review_category_scores (
    review_id, category_id, score
  )
  SELECT v_review_id, key::uuid, (value)::int
  FROM jsonb_each(p_category_scores);

  INSERT INTO public.coach_review_tags (review_id, tag_id)
  SELECT v_review_id, t FROM unnest(COALESCE(p_tag_ids, ARRAY[]::uuid[])) t
  ON CONFLICT DO NOTHING;

  INSERT INTO public.coach_review_custom_tags (review_id, label)
  SELECT v_review_id, btrim(label)
  FROM unnest(COALESCE(p_custom_tags, ARRAY[]::text[])) AS label
  WHERE length(btrim(label)) BETWEEN 1 AND 60;

  RETURN v_review_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_coach_review_helpful(
  p_user_id UUID,
  p_review_id UUID,
  p_helpful BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_review RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  SELECT id, user_id INTO v_review
  FROM public.coach_reviews
  WHERE id = p_review_id AND status = 'published';
  IF v_review.id IS NULL THEN
    RAISE EXCEPTION 'REVIEW_NOT_FOUND';
  END IF;
  IF v_review.user_id = p_user_id THEN
    RAISE EXCEPTION 'SELF_VOTE_NOT_ALLOWED';
  END IF;

  IF COALESCE(p_helpful, false) THEN
    INSERT INTO public.coach_review_helpful_votes (review_id, user_id)
    VALUES (p_review_id, p_user_id)
    ON CONFLICT (review_id, user_id) DO NOTHING;
  ELSE
    DELETE FROM public.coach_review_helpful_votes
    WHERE review_id = p_review_id AND user_id = p_user_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_coach_review_summary_v2(
  p_coach_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'average_rating', ROUND(AVG(r.rating_10)::numeric, 2),
    'review_count', COUNT(*),
    'band_counts', jsonb_build_object(
      'excellent', COUNT(*) FILTER (WHERE r.rating_10 >= 9),
      'good',      COUNT(*) FILTER (WHERE r.rating_10 BETWEEN 7 AND 8),
      'fair',      COUNT(*) FILTER (WHERE r.rating_10 BETWEEN 5 AND 6),
      'poor',      COUNT(*) FILTER (WHERE r.rating_10 BETWEEN 3 AND 4),
      'very_poor', COUNT(*) FILTER (WHERE r.rating_10 <= 2)
    ),
    'categories', COALESCE((
      SELECT jsonb_agg(cat ORDER BY (cat->>'display_order')::int)
      FROM (
        SELECT jsonb_build_object(
          'category_id', c.id,
          'key', c.key,
          'label_th', c.label_th,
          'label_en', c.label_en,
          'display_order', c.display_order,
          'average', ROUND(
            AVG(s.score) FILTER (WHERE r2.id IS NOT NULL)::numeric, 2),
          'sample_count', COUNT(r2.id)
        ) AS cat
        FROM public.coach_review_category_catalog c
        LEFT JOIN public.coach_review_category_scores s
          ON s.category_id = c.id
        LEFT JOIN public.coach_reviews r2
          ON r2.id = s.review_id
         AND r2.status = 'published'
         AND r2.coach_id = p_coach_id
        WHERE c.is_active
        GROUP BY c.id, c.key, c.label_th, c.label_en, c.display_order
      ) cats
    ), '[]'::jsonb),
    'topics', COALESCE((
      SELECT jsonb_agg(t ORDER BY (t->>'review_count')::int DESC,
                          t->>'label_th')
      FROM (
        SELECT jsonb_build_object(
          'tag_id', tc.id,
          'label_th', tc.label_th,
          'label_en', tc.label_en,
          'review_count', COUNT(*)
        ) AS t
        FROM public.coach_review_tags rt
        JOIN public.coach_review_tag_catalog tc
          ON tc.id = rt.tag_id AND tc.is_active
        JOIN public.coach_reviews r3 ON r3.id = rt.review_id
        WHERE r3.status = 'published' AND r3.coach_id = p_coach_id
        GROUP BY tc.id, tc.label_th, tc.label_en
      ) topics
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.coach_reviews r
  WHERE r.status = 'published' AND r.coach_id = p_coach_id;

  RETURN COALESCE(v_result, jsonb_build_object(
    'average_rating', NULL,
    'review_count', 0,
    'band_counts', '{}'::jsonb,
    'categories', '[]'::jsonb,
    'topics', '[]'::jsonb
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.list_coach_reviews_v2(
  p_coach_id UUID,
  p_tag_id UUID DEFAULT NULL,
  p_min_rating_10 NUMERIC DEFAULT NULL,
  p_max_rating_10 NUMERIC DEFAULT NULL,
  p_sort VARCHAR DEFAULT 'helpful',
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0,
  p_viewer_id UUID DEFAULT NULL
)
RETURNS TABLE(
  id UUID,
  coach_id UUID,
  user_id UUID,
  user_display_name TEXT,
  user_avatar_url TEXT,
  rating_10 NUMERIC,
  is_legacy BOOLEAN,
  comment VARCHAR,
  created_at TIMESTAMPTZ,
  helpful_count INT,
  viewer_voted BOOLEAN,
  tag_labels TEXT[],
  category_scores JSONB,
  total_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH filtered AS (
    SELECT
      r.id,
      r.coach_id,
      r.user_id,
      NULLIF(btrim(CONCAT_WS(' ', u.first_name, u.last_name)), '')
        AS user_display_name,
      u.profile_image_url AS user_avatar_url,
      r.rating_10,
      r.is_legacy,
      r.comment,
      r.created_at,
      (SELECT COUNT(*)::int
         FROM public.coach_review_helpful_votes hv
        WHERE hv.review_id = r.id) AS helpful_count,
      (p_viewer_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.coach_review_helpful_votes hv
        WHERE hv.review_id = r.id AND hv.user_id = p_viewer_id
      )) AS viewer_voted,
      (
        SELECT array_agg(label ORDER BY label)
        FROM (
          SELECT tc.label_th::text AS label
          FROM public.coach_review_tags rt
          JOIN public.coach_review_tag_catalog tc
            ON tc.id = rt.tag_id
          WHERE rt.review_id = r.id
          UNION ALL
          SELECT ct.label::text
          FROM public.coach_review_custom_tags ct
          WHERE ct.review_id = r.id
        ) labels
      ) AS tag_labels,
      (
        SELECT jsonb_object_agg(c.key, s.score)
        FROM public.coach_review_category_scores s
        JOIN public.coach_review_category_catalog c
          ON c.id = s.category_id
        WHERE s.review_id = r.id
      ) AS category_scores
    FROM public.coach_reviews r
    LEFT JOIN public.users u ON u.id = r.user_id
    WHERE r.status = 'published'
      AND r.coach_id = p_coach_id
      AND (p_min_rating_10 IS NULL OR r.rating_10 >= p_min_rating_10)
      AND (p_max_rating_10 IS NULL OR r.rating_10 <= p_max_rating_10)
      AND (p_tag_id IS NULL OR EXISTS (
        SELECT 1 FROM public.coach_review_tags rt
        WHERE rt.review_id = r.id AND rt.tag_id = p_tag_id
      ))
  )
  SELECT
    f.id, f.coach_id, f.user_id, f.user_display_name, f.user_avatar_url,
    f.rating_10, f.is_legacy, f.comment, f.created_at, f.helpful_count,
    f.viewer_voted,
    COALESCE(f.tag_labels, ARRAY[]::text[]) AS tag_labels,
    f.category_scores,
    COUNT(*) OVER () AS total_count
  FROM filtered f
  ORDER BY
    CASE WHEN p_sort = 'helpful' OR p_sort IS NULL
      THEN f.helpful_count END DESC NULLS LAST,
    CASE WHEN p_sort = 'highest'
      THEN f.rating_10 END DESC NULLS LAST,
    CASE WHEN p_sort = 'lowest'
      THEN f.rating_10 END ASC NULLS LAST,
    f.created_at DESC,
    f.id
  LIMIT COALESCE(p_limit, 20)
  OFFSET COALESCE(p_offset, 0);
END;
$$;

-- Eligible review targets for the learner's My Enrollments page:
-- completed 1:1 bookings and completed enrollment sessions that have
-- not been reviewed yet.
CREATE OR REPLACE FUNCTION public.list_my_coach_reviewable_ids(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  RETURN jsonb_build_object(
    'bookingIds', COALESCE((
      SELECT jsonb_agg(r.id) FROM public.coach_booking_requests r
      WHERE r.user_id = p_user_id AND r.status = 'completed'
        AND NOT EXISTS (
          SELECT 1 FROM public.coach_reviews rv
          WHERE rv.booking_id = r.id)
    ), '[]'::jsonb),
    'enrollmentSessions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'enrollmentId', es.enrollment_id, 'sessionId', es.session_id))
      FROM public.coach_enrollment_sessions es
      JOIN public.coach_enrollments e ON e.id = es.enrollment_id
      WHERE e.user_id = p_user_id AND es.status = 'completed'
        AND e.status IN ('confirmed','completed')
        AND NOT EXISTS (
          SELECT 1 FROM public.coach_reviews rv
          WHERE rv.enrollment_id = es.enrollment_id
            AND rv.session_id = es.session_id)
    ), '[]'::jsonb)
  );
END;
$$;

-- ===============
-- RLS
-- ===============
ALTER TABLE public.coach_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_teaching_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_offerings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_offering_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_enrollment_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_schedule_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_schedule_change_responses
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_review_category_catalog
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_review_category_scores
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_review_tag_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_review_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_review_custom_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coach_review_helpful_votes
  ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  -- coach_contacts/enrollments/proposals/favorites: no public select —
  -- reads go through the authorized RPCs above.

  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_teaching_locations'
      AND policyname='coach_teaching_locations_select_all') THEN
    CREATE POLICY coach_teaching_locations_select_all
      ON public.coach_teaching_locations FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_offerings'
      AND policyname='coach_offerings_select_published') THEN
    CREATE POLICY coach_offerings_select_published
      ON public.coach_offerings FOR SELECT
      USING (status IN ('published','closed','completed'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_offering_sessions'
      AND policyname='coach_offering_sessions_select_published') THEN
    CREATE POLICY coach_offering_sessions_select_published
      ON public.coach_offering_sessions FOR SELECT
      USING (EXISTS (
        SELECT 1 FROM public.coach_offerings o
        WHERE o.id = offering_id
          AND o.status IN ('published','closed','completed')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_slots'
      AND policyname='coach_slots_select_published') THEN
    CREATE POLICY coach_slots_select_published
      ON public.coach_slots FOR SELECT
      USING (status = 'published');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_review_category_catalog'
      AND policyname='coach_review_cat_select') THEN
    CREATE POLICY coach_review_cat_select
      ON public.coach_review_category_catalog
      FOR SELECT USING (is_active);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_review_category_scores'
      AND policyname='coach_review_scores_select') THEN
    CREATE POLICY coach_review_scores_select
      ON public.coach_review_category_scores FOR SELECT
      USING (EXISTS (
        SELECT 1 FROM public.coach_reviews r
        WHERE r.id = review_id AND r.status = 'published'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_review_tag_catalog'
      AND policyname='coach_review_tagcat_select') THEN
    CREATE POLICY coach_review_tagcat_select
      ON public.coach_review_tag_catalog FOR SELECT USING (is_active);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_review_tags'
      AND policyname='coach_review_tags_select') THEN
    CREATE POLICY coach_review_tags_select
      ON public.coach_review_tags FOR SELECT
      USING (EXISTS (
        SELECT 1 FROM public.coach_reviews r
        WHERE r.id = review_id AND r.status = 'published'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_review_custom_tags'
      AND policyname='coach_review_ctags_select') THEN
    CREATE POLICY coach_review_ctags_select
      ON public.coach_review_custom_tags FOR SELECT
      USING (EXISTS (
        SELECT 1 FROM public.coach_reviews r
        WHERE r.id = review_id AND r.status = 'published'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
    WHERE tablename='coach_review_helpful_votes'
      AND policyname='coach_review_votes_select') THEN
    CREATE POLICY coach_review_votes_select
      ON public.coach_review_helpful_votes FOR SELECT USING (true);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
