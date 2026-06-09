-- Migration: POS Core Schema
-- Tables: orders, order_items, unified_payments, shopping_carts, clinic_services, clinic_appointments
-- Functions: generate_order_number, confirm_unified_payment, confirm_cash_payment
-- Prerequisites: users, professions, organization_branches
-- RLS: Enable but allow all — controlled at Application Layer

-- 0. Ensure updated_at trigger function exists
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 1. ORDER NUMBER SEQUENCE
-- ============================================
CREATE SEQUENCE IF NOT EXISTS public.order_number_seq START 1;

-- ============================================
-- 2. ORDERS (Unified Order Header)
-- ============================================
CREATE TABLE IF NOT EXISTS public.orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number      TEXT NOT NULL UNIQUE DEFAULT 'ORD-' || TO_CHAR(now(), 'YYYYMMDD') || '-' || LPAD(nextval('public.order_number_seq')::TEXT, 4, '0'),
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  profession_id     UUID REFERENCES public.professions(id) ON DELETE SET NULL,
  branch_id         UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
  pos_mode          TEXT NOT NULL DEFAULT 'patient_self_checkout'
                      CHECK (pos_mode IN ('patient_self_checkout', 'counter_pos', 'erp_dashboard')),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'paid', 'processing', 'completed', 'cancelled', 'refunded')),
  total_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
  vat_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
  wht_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
  final_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  currency          TEXT NOT NULL DEFAULT 'THB',
  payment_method    TEXT CHECK (payment_method IN ('cash', 'promptpay', 'omise_card', 'mock')),
  payment_status    TEXT DEFAULT 'unpaid'
                      CHECK (payment_status IN ('unpaid', 'pending', 'paid', 'failed', 'refunded')),
  paid_at           TIMESTAMPTZ,
  served_by         UUID REFERENCES public.users(id) ON DELETE SET NULL,
  staff_notes       TEXT,
  coupon_id         UUID,
  discount_code     TEXT,
  loyalty_points_used INTEGER DEFAULT 0,
  -- Refund fields
  refund_reason     TEXT,
  refunded_at       TIMESTAMPTZ,
  refunded_by       UUID REFERENCES public.users(id) ON DELETE SET NULL,
  refund_status     TEXT DEFAULT 'none'
                      CHECK (refund_status IN ('none', 'requested', 'approved', 'rejected', 'completed')),
  refund_requested_at TIMESTAMPTZ,
  refund_approved_by  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  -- Metadata
  metadata          JSONB DEFAULT '{}',
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orders_user ON public.orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_profession ON public.orders(profession_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_pos_mode ON public.orders(pos_mode, status);
CREATE INDEX IF NOT EXISTS idx_orders_branch ON public.orders(branch_id);
CREATE INDEX IF NOT EXISTS idx_orders_served_by ON public.orders(served_by);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status, created_at DESC)
  WHERE status IN ('paid', 'completed');

CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 3. ORDER ITEMS (Line Items)
-- ============================================
CREATE TABLE IF NOT EXISTS public.order_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  item_type         TEXT NOT NULL
                      CHECK (item_type IN ('consultation_package', 'pharmacy_product', 'membership_plan', 'clinic_service', 'prepaid_package')),
  item_id           UUID NOT NULL,
  item_name         TEXT NOT NULL,
  item_snapshot     JSONB NOT NULL DEFAULT '{}',
  quantity          INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price        DECIMAL(12,2) NOT NULL,
  total_price       DECIMAL(12,2) NOT NULL,
  is_vatable        BOOLEAN DEFAULT false,
  vat_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_type ON public.order_items(item_type, item_id);

-- ============================================
-- 4. UNIFIED PAYMENTS
-- ============================================
CREATE TABLE IF NOT EXISTS public.unified_payments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount            DECIMAL(12,2) NOT NULL,
  payment_method    TEXT NOT NULL CHECK (payment_method IN ('cash', 'promptpay', 'omise_card', 'mock')),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'confirmed', 'failed', 'refunded')),
  provider_reference  TEXT,
  qr_payload        TEXT,
  confirmed_at      TIMESTAMPTZ,
  confirmed_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  failed_reason     TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_order ON public.unified_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_user ON public.unified_payments(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.unified_payments(status, created_at DESC)
  WHERE status IN ('pending', 'failed');

-- ============================================
-- 5. SHOPPING CARTS (Mode A — Per-User Session)
-- ============================================
CREATE TABLE IF NOT EXISTS public.shopping_carts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  items             JSONB NOT NULL DEFAULT '[]',
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE TRIGGER trg_shopping_carts_updated_at BEFORE UPDATE ON public.shopping_carts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 6. CLINIC SERVICES (Per-Profession Catalog — Mode C)
-- ============================================
CREATE TABLE IF NOT EXISTS public.clinic_services (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  price             DECIMAL(12,2) NOT NULL,
  is_vatable        BOOLEAN DEFAULT false,
  duration_minutes  INTEGER,
  category          TEXT,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_clinic_services_profession ON public.clinic_services(profession_id, is_active)
  WHERE is_active = true;

CREATE TRIGGER trg_clinic_services_updated_at BEFORE UPDATE ON public.clinic_services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 7. CLINIC APPOINTMENTS (สร้างเมื่อซื้อ clinic_service)
-- ============================================
-- NOTE: สร้างตารางนี้เพื่อใช้เป็น data source สำหรับ KPI Phase 3 (appointments metric)
CREATE TABLE IF NOT EXISTS public.clinic_appointments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  order_item_id     UUID NOT NULL REFERENCES public.order_items(id) ON DELETE CASCADE,
  profession_id     UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
  patient_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  clinic_service_id UUID REFERENCES public.clinic_services(id) ON DELETE SET NULL,
  staff_id          UUID REFERENCES public.users(id) ON DELETE SET NULL,
  scheduled_at      TIMESTAMPTZ,
  duration_minutes  INTEGER,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
  notes             TEXT,
  cancelled_reason  TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_appointments_profession ON public.clinic_appointments(profession_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON public.clinic_appointments(patient_id, status);
CREATE INDEX IF NOT EXISTS idx_appointments_order ON public.clinic_appointments(order_id);
CREATE INDEX IF NOT EXISTS idx_appointments_completed ON public.clinic_appointments(status, scheduled_at)
  WHERE status = 'completed';

CREATE TRIGGER trg_clinic_appointments_updated_at BEFORE UPDATE ON public.clinic_appointments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 8. DB FUNCTIONS
-- ============================================

-- Order Number Generator
CREATE OR REPLACE FUNCTION public.generate_order_number(p_branch_code TEXT DEFAULT '')
RETURNS TEXT AS $$
DECLARE
  v_date TEXT;
  v_seq  TEXT;
  v_prefix TEXT;
BEGIN
  v_date := TO_CHAR(now(), 'YYYYMMDD');
  v_seq  := LPAD(nextval('public.order_number_seq')::TEXT, 4, '0');
  v_prefix := CASE WHEN p_branch_code != '' THEN p_branch_code || '-' ELSE '' END;
  RETURN v_prefix || 'ORD-' || v_date || '-' || v_seq;
END;
$$ LANGUAGE plpgsql;

-- Confirm Payment + Update Order (Atomic)
CREATE OR REPLACE FUNCTION public.confirm_unified_payment(
  p_payment_id UUID,
  p_reference TEXT,
  p_confirmed_by UUID DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE public.unified_payments
  SET status = 'confirmed',
      confirmed_at = now(),
      provider_reference = p_reference,
      confirmed_by = p_confirmed_by
  WHERE id = p_payment_id AND status = 'pending';

  UPDATE public.orders
  SET status = 'paid',
      payment_status = 'paid',
      paid_at = now(),
      updated_at = now()
  WHERE id = (SELECT order_id FROM public.unified_payments WHERE id = p_payment_id)
    AND status = 'pending';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Confirm Cash Payment (Mode B/C)
CREATE OR REPLACE FUNCTION public.confirm_cash_payment(
  p_order_id UUID,
  p_served_by UUID
) RETURNS VOID AS $$
BEGIN
  UPDATE public.orders
  SET status = 'paid',
      payment_status = 'paid',
      paid_at = now(),
      payment_method = 'cash',
      served_by = p_served_by,
      updated_at = now()
  WHERE id = p_order_id AND status = 'pending';

  INSERT INTO public.unified_payments (order_id, user_id, amount, payment_method, status, confirmed_at, confirmed_by)
  SELECT id, user_id, final_amount, 'cash', 'confirmed', now(), p_served_by
  FROM public.orders WHERE id = p_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 9. RLS (Enable but allow all — controlled at Application Layer)
-- ============================================
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unified_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shopping_carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinic_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clinic_appointments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_select" ON public.orders FOR SELECT USING (true);
CREATE POLICY "orders_modify" ON public.orders FOR ALL USING (true);
CREATE POLICY "order_items_select" ON public.order_items FOR SELECT USING (true);
CREATE POLICY "order_items_modify" ON public.order_items FOR ALL USING (true);
CREATE POLICY "payments_select" ON public.unified_payments FOR SELECT USING (true);
CREATE POLICY "payments_modify" ON public.unified_payments FOR ALL USING (true);
CREATE POLICY "carts_select" ON public.shopping_carts FOR SELECT USING (true);
CREATE POLICY "carts_modify" ON public.shopping_carts FOR ALL USING (true);
CREATE POLICY "clinic_services_select" ON public.clinic_services FOR SELECT USING (true);
CREATE POLICY "clinic_services_modify" ON public.clinic_services FOR ALL USING (true);
CREATE POLICY "appointments_select" ON public.clinic_appointments FOR SELECT USING (true);
CREATE POLICY "appointments_modify" ON public.clinic_appointments FOR ALL USING (true);
