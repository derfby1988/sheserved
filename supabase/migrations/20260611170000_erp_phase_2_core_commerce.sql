-- Migration: ERP Phase 2 — Core Commerce & Platform
-- Date: 2026-06-11
-- Prerequisites: Phase 1 tables (products, customers, inventory) + POS Core (orders, unified_payments)
-- Modules: Commerce (checkout_sessions, payment_transactions) + Logistics (delivery_orders)

-- ============================================================
-- 1. CHECKOUT SESSIONS (State Machine for Checkout Flow)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.checkout_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    customer_id     UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    cart_snapshot   JSONB NOT NULL DEFAULT '{}',           -- snapshot ของตะกร้า
    order_id        UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    status          TEXT NOT NULL DEFAULT 'created'
                        CHECK (status IN (
                            'created',          -- สร้าง session
                            'payment_pending',  -- รอชำระเงิน
                            'payment_failed',   -- ชำระเงินล้มเหลว
                            'paid',             -- ชำระเงินสำเร็จ
                            'confirmed',        -- ยืนยัน order
                            'cancelled',        -- ยกเลิก
                            'expired'           -- หมดอายุ
                        )),
    payment_method  TEXT,                                  -- promptpay, cash, credit_card, etc.
    total_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    vat_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    net_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
    coupon_id       UUID REFERENCES public.coupons(id) ON DELETE SET NULL,
    loyalty_points_used INTEGER DEFAULT 0,
    idempotency_key TEXT UNIQUE,                           -- ป้องกัน duplicate checkout
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 minutes'),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checkout_sessions_profession
    ON public.checkout_sessions(profession_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_user
    ON public.checkout_sessions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_order
    ON public.checkout_sessions(order_id)
    WHERE order_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_checkout_sessions_updated_at ON public.checkout_sessions;
CREATE TRIGGER trg_checkout_sessions_updated_at
    BEFORE UPDATE ON public.checkout_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. PAYMENT TRANSACTIONS (Detailed Transaction Log)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.payment_transactions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    checkout_session_id UUID REFERENCES public.checkout_sessions(id) ON DELETE SET NULL,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    currency        TEXT NOT NULL DEFAULT 'THB',
    payment_method  TEXT NOT NULL,                         -- promptpay, cash, credit_card, etc.
    provider        TEXT,                                  -- omise, stripe, etc.
    provider_txn_id TEXT,                                  -- transaction ID จาก provider
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN (
                            'pending',
                            'processing',
                            'completed',
                            'failed',
                            'refunded',
                            'partially_refunded'
                        )),
    error_code      TEXT,
    error_message   TEXT,
    metadata        JSONB DEFAULT '{}',                    -- provider response, raw data
    processed_at    TIMESTAMPTZ,
    refunded_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_txn_profession
    ON public.payment_transactions(profession_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_txn_order
    ON public.payment_transactions(order_id, status);
CREATE INDEX IF NOT EXISTS idx_payment_txn_provider
    ON public.payment_transactions(provider, provider_txn_id)
    WHERE provider_txn_id IS NOT NULL;

-- ============================================================
-- 3. DELIVERY ORDERS (Logistics Core)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.delivery_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    customer_id     UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    delivery_status TEXT NOT NULL DEFAULT 'pending'
                        CHECK (delivery_status IN (
                            'pending',          -- รอจัดส่ง
                            'preparing',        -- เตรียมสินค้า
                            'ready_for_pickup', -- พร้อมให้ไรเดอร์มารับ
                            'picked_up',        -- ไรเดอร์รับแล้ว
                            'in_transit',       -- กำลังส่ง
                            'arrived',          -- ถึงจุดหมาย
                            'delivered',        -- ส่งสำเร็จ
                            'failed',           -- ส่งไม่สำเร็จ
                            'cancelled',        -- ยกเลิก
                            'returned'          -- คืนสินค้า
                        )),
    recipient_name  TEXT NOT NULL,
    recipient_phone TEXT NOT NULL,
    delivery_address TEXT NOT NULL,
    delivery_notes  TEXT,
    delivery_type   TEXT NOT NULL DEFAULT 'standard'       -- standard, express, same_day
                        CHECK (delivery_type IN ('standard', 'express', 'same_day', 'pickup')),
    scheduled_delivery_at TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,
    proof_of_delivery JSONB DEFAULT '{}',                    -- signature, photo, gps
    tracking_number TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_orders_profession
    ON public.delivery_orders(profession_id, delivery_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_order
    ON public.delivery_orders(order_id);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_status
    ON public.delivery_orders(delivery_status, scheduled_delivery_at)
    WHERE delivery_status IN ('pending', 'preparing', 'ready_for_pickup', 'in_transit');

DROP TRIGGER IF EXISTS trg_delivery_orders_updated_at ON public.delivery_orders;
CREATE TRIGGER trg_delivery_orders_updated_at
    BEFORE UPDATE ON public.delivery_orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. RLS POLICIES (Idempotent)
-- ============================================================
ALTER TABLE public.checkout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "checkout_sessions_select" ON public.checkout_sessions;
CREATE POLICY "checkout_sessions_select" ON public.checkout_sessions FOR SELECT USING (true);
DROP POLICY IF EXISTS "checkout_sessions_modify" ON public.checkout_sessions;
CREATE POLICY "checkout_sessions_modify" ON public.checkout_sessions FOR ALL USING (true);

DROP POLICY IF EXISTS "payment_txn_select" ON public.payment_transactions;
CREATE POLICY "payment_txn_select" ON public.payment_transactions FOR SELECT USING (true);
DROP POLICY IF EXISTS "payment_txn_modify" ON public.payment_transactions;
CREATE POLICY "payment_txn_modify" ON public.payment_transactions FOR ALL USING (true);

DROP POLICY IF EXISTS "delivery_orders_select" ON public.delivery_orders;
CREATE POLICY "delivery_orders_select" ON public.delivery_orders FOR SELECT USING (true);
DROP POLICY IF EXISTS "delivery_orders_modify" ON public.delivery_orders;
CREATE POLICY "delivery_orders_modify" ON public.delivery_orders FOR ALL USING (true);

-- ============================================================
-- 5. RPC FUNCTIONS
-- ============================================================

-- Create checkout session with idempotency
CREATE OR REPLACE FUNCTION create_checkout_session(
    p_profession_id UUID,
    p_user_id UUID,
    p_cart_snapshot JSONB,
    p_total_amount DECIMAL(12,2),
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_session_id UUID;
BEGIN
    -- Check idempotency
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_session_id
        FROM public.checkout_sessions
        WHERE idempotency_key = p_idempotency_key
          AND profession_id = p_profession_id;
        
        IF v_session_id IS NOT NULL THEN
            RETURN v_session_id;
        END IF;
    END IF;

    INSERT INTO public.checkout_sessions (
        profession_id, user_id, cart_snapshot, total_amount,
        net_amount, idempotency_key
    )
    VALUES (
        p_profession_id, p_user_id, p_cart_snapshot, p_total_amount,
        p_total_amount, p_idempotency_key
    )
    RETURNING id INTO v_session_id;

    RETURN v_session_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Confirm checkout (transition to confirmed + create order)
CREATE OR REPLACE FUNCTION confirm_checkout(
    p_session_id UUID,
    p_order_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.checkout_sessions
    SET status = 'confirmed',
        order_id = p_order_id,
        updated_at = NOW()
    WHERE id = p_session_id
      AND status = 'paid';

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update delivery status
CREATE OR REPLACE FUNCTION update_delivery_status(
    p_delivery_order_id UUID,
    p_new_status TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_delivered_at TIMESTAMPTZ;
BEGIN
    IF p_new_status = 'delivered' THEN
        v_delivered_at := NOW();
    END IF;

    UPDATE public.delivery_orders
    SET delivery_status = p_new_status,
        delivery_notes = COALESCE(p_notes, delivery_notes),
        delivered_at = COALESCE(v_delivered_at, delivered_at),
        updated_at = NOW()
    WHERE id = p_delivery_order_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
