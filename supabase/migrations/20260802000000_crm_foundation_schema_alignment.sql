-- Migration: CRM Foundation & Alignment Migration (Step 1 & Step 2)
-- Date: 2026-08-02
-- Description: Implement non-breaking schema alterations, alias views, and new master tables for CRM & Appointment system.

-- ============================================================
-- 1. NEW MASTER TABLES (Step 2)
-- ============================================================

-- 1.1 Service Rooms
CREATE TABLE IF NOT EXISTS public.service_rooms (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id       UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    room_name       TEXT NOT NULL,
    room_code       TEXT,
    capacity        INTEGER DEFAULT 1,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_rooms_profession ON public.service_rooms(profession_id, is_active);

-- 1.2 Appointment Service Types
CREATE TABLE IF NOT EXISTS public.appointment_service_types (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    type_name               TEXT NOT NULL,
    default_duration_minutes INTEGER NOT NULL DEFAULT 30,
    default_price           DECIMAL(12,2) DEFAULT 0,
    requires_doctor         BOOLEAN DEFAULT true,
    is_active               BOOLEAN DEFAULT true,
    created_at              TIMESTAMPTZ DEFAULT now(),
    updated_at              TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_appointment_service_types_profession ON public.appointment_service_types(profession_id, is_active);

-- 1.3 Practitioners
CREATE TABLE IF NOT EXISTS public.practitioners (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES public.users(id) ON DELETE CASCADE,
    display_name    TEXT NOT NULL,
    license_number  TEXT,
    specialty       TEXT,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_practitioners_profession ON public.practitioners(profession_id, is_active);
CREATE INDEX IF NOT EXISTS idx_practitioners_user ON public.practitioners(user_id);

-- 1.4 Service Schedules
CREATE TABLE IF NOT EXISTS public.service_schedules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    practitioner_id UUID REFERENCES public.practitioners(id) ON DELETE CASCADE,
    day_of_week     INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    max_patients    INTEGER DEFAULT 10,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_schedules_practitioner ON public.service_schedules(practitioner_id, day_of_week);

-- 1.5 Schedule Blockouts
CREATE TABLE IF NOT EXISTS public.schedule_blockouts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    practitioner_id UUID REFERENCES public.practitioners(id) ON DELETE CASCADE,
    start_time      TIMESTAMPTZ NOT NULL,
    end_time        TIMESTAMPTZ NOT NULL,
    reason          TEXT,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_schedule_blockouts_practitioner ON public.schedule_blockouts(practitioner_id, start_time, end_time);

-- 1.6 Appointment Policies
CREATE TABLE IF NOT EXISTS public.appointment_policies (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    policy_name             TEXT NOT NULL,
    cancel_buffer_hours     INTEGER DEFAULT 24,
    reschedule_buffer_hours INTEGER DEFAULT 12,
    deposit_required        BOOLEAN DEFAULT false,
    deposit_amount          DECIMAL(12,2) DEFAULT 0,
    created_at              TIMESTAMPTZ DEFAULT now(),
    updated_at              TIMESTAMPTZ DEFAULT now()
);

-- 1.7 Customer Prepaid Course Packages
CREATE TABLE IF NOT EXISTS public.customer_packages (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    customer_id         UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    package_name        TEXT NOT NULL,
    total_sessions      INTEGER NOT NULL,
    used_sessions       INTEGER NOT NULL DEFAULT 0,
    remaining_sessions  INTEGER NOT NULL,
    total_price         DECIMAL(12,2) NOT NULL DEFAULT 0,
    expires_at          TIMESTAMPTZ,
    status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'expired', 'cancelled')),
    created_at          TIMESTAMPTZ DEFAULT now(),
    updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_packages_customer ON public.customer_packages(customer_id, status);

-- 1.8 Package Session Logs
CREATE TABLE IF NOT EXISTS public.package_session_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    package_id          UUID NOT NULL REFERENCES public.customer_packages(id) ON DELETE CASCADE,
    profession_id       UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    appointment_id      UUID REFERENCES public.clinic_appointments(id) ON DELETE SET NULL,
    order_id            UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    sessions_deducted   INTEGER NOT NULL DEFAULT 1,
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_package_session_logs_package ON public.package_session_logs(package_id);

-- 1.9 Promotions
CREATE TABLE IF NOT EXISTS public.promotions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    description     TEXT,
    discount_pct    DECIMAL(5,2),
    discount_amount DECIMAL(12,2),
    start_date      TIMESTAMPTZ NOT NULL,
    end_date        TIMESTAMPTZ NOT NULL,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_promotions_profession ON public.promotions(profession_id, is_active, start_date, end_date);

-- 1.10 Customer Feedbacks / CSAT
CREATE TABLE IF NOT EXISTS public.customer_feedbacks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    customer_id     UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    appointment_id UUID REFERENCES public.clinic_appointments(id) ON DELETE SET NULL,
    rating          INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment         TEXT,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customer_feedbacks_profession ON public.customer_feedbacks(profession_id, rating);


-- ============================================================
-- 2. NON-BREAKING ALTER TABLE EXTENSIONS (Step 1)
-- ============================================================

-- 2.1 clinic_appointments
ALTER TABLE public.clinic_appointments
    ADD COLUMN IF NOT EXISTS appointment_no TEXT,
    ADD COLUMN IF NOT EXISTS room_id UUID REFERENCES public.service_rooms(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS service_type_id UUID REFERENCES public.appointment_service_types(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS deposit_paid DECIMAL(12,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS booking_channel TEXT DEFAULT 'walk_in',
    ADD COLUMN IF NOT EXISTS reminder_sent_24h BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS reminder_sent_2h BOOLEAN DEFAULT false;

-- 2.2 coupons
ALTER TABLE public.coupons
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL;

-- 2.3 loyalty_tiers
ALTER TABLE public.loyalty_tiers
    ADD COLUMN IF NOT EXISTS tier_key TEXT,
    ADD COLUMN IF NOT EXISTS point_multiplier DECIMAL(5,2) DEFAULT 1.0;

-- 2.4 customers
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS tier TEXT DEFAULT 'bronze';

-- 2.5 loyalty_points
ALTER TABLE public.loyalty_points
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL;


-- ============================================================
-- 3. ALIAS VIEWS FOR CRM SYSTEM PLAN ALIGNMENT (Step 1)
-- ============================================================

-- 3.1 VIEW: appointments
CREATE OR REPLACE VIEW public.appointments AS
SELECT
    ca.id,
    COALESCE(ca.appointment_no, ca.id::text) AS appointment_no,
    ca.profession_id,
    ca.patient_id AS patient_user_id,
    ca.staff_id AS practitioner_id,
    ca.clinic_service_id AS service_type_id,
    ca.room_id,
    ca.scheduled_at,
    ca.duration_minutes,
    ca.status,
    ca.notes,
    ca.cancelled_reason AS cancellation_reason,
    ca.deposit_paid,
    ca.booking_channel,
    ca.reminder_sent_24h,
    ca.reminder_sent_2h,
    ca.created_at,
    ca.updated_at
FROM public.clinic_appointments ca;

-- 3.2 VIEW: coupon_usages
CREATE OR REPLACE VIEW public.coupon_usages AS
SELECT
    cr.id,
    cr.coupon_id,
    cr.profession_id,
    cr.customer_id AS user_id,
    cr.order_id,
    cr.discount_amount AS discount_applied,
    c.coupon_type AS discount_type,
    c.max_discount AS max_discount_baht,
    cr.created_at AS used_at
FROM public.coupon_redemptions cr
LEFT JOIN public.coupons c ON c.id = cr.coupon_id;

-- 3.3 VIEW: member_tiers
CREATE OR REPLACE VIEW public.member_tiers AS
SELECT
    id,
    profession_id,
    tier_name,
    tier_key,
    min_points,
    discount_pct,
    point_multiplier,
    description,
    sort_order,
    is_active,
    created_at
FROM public.loyalty_tiers;

-- 3.4 VIEW: customer_loyalty_wallets
CREATE OR REPLACE VIEW public.customer_loyalty_wallets AS
SELECT
    c.id AS customer_id,
    c.profession_id,
    c.user_id,
    c.display_name,
    c.phone,
    c.email,
    c.tier,
    c.total_points AS current_points,
    c.lifetime_value,
    c.visit_count,
    c.last_visit_at
FROM public.customers c;

-- 3.5 VIEW: loyalty_point_transactions
CREATE OR REPLACE VIEW public.loyalty_point_transactions AS
SELECT
    lp.id,
    lp.profession_id,
    lp.customer_id,
    lp.points_change,
    lp.points_balance,
    lp.transaction_type,
    lp.reference_type,
    lp.reference_id,
    lp.description,
    lp.expires_at,
    lp.created_at
FROM public.loyalty_points lp;


-- ============================================================
-- 4. RLS POLICIES FOR NEW TABLES
-- ============================================================

ALTER TABLE public.service_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointment_service_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.practitioners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_blockouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointment_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_session_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_feedbacks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_rooms_all" ON public.service_rooms FOR ALL USING (true);
CREATE POLICY "appointment_service_types_all" ON public.appointment_service_types FOR ALL USING (true);
CREATE POLICY "practitioners_all" ON public.practitioners FOR ALL USING (true);
CREATE POLICY "service_schedules_all" ON public.service_schedules FOR ALL USING (true);
CREATE POLICY "schedule_blockouts_all" ON public.schedule_blockouts FOR ALL USING (true);
CREATE POLICY "appointment_policies_all" ON public.appointment_policies FOR ALL USING (true);
CREATE POLICY "customer_packages_all" ON public.customer_packages FOR ALL USING (true);
CREATE POLICY "package_session_logs_all" ON public.package_session_logs FOR ALL USING (true);
CREATE POLICY "promotions_all" ON public.promotions FOR ALL USING (true);
CREATE POLICY "customer_feedbacks_all" ON public.customer_feedbacks FOR ALL USING (true);
