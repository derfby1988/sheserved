-- Migration: ERP Phase 2 — Delivery Extensions
-- Date: 2026-06-12
-- Prerequisites: Phase 2 delivery tables (delivery_orders, riders, delivery_runs, route_stops)

-- ============================================================
-- 1. SHIPMENTS (3PL / outbound package tracking)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.shipments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    delivery_order_id UUID NOT NULL REFERENCES public.delivery_orders(id) ON DELETE CASCADE,
    carrier_config_id UUID,
    tracking_number TEXT,                                  -- เลขพัสดุจาก 3PL
    shipment_status TEXT NOT NULL DEFAULT 'pending'
                        CHECK (shipment_status IN (
                            'pending', 'label_created', 'picked_up',
                            'in_transit', 'out_for_delivery', 'delivered',
                            'failed', 'returned'
                        )),
    weight_kg       DECIMAL(8,3) DEFAULT 0,                -- น้ำหนักรวม
    dimensions_cm   JSONB DEFAULT '{}',                    -- {length, width, height}
    shipping_cost   DECIMAL(12,2) NOT NULL DEFAULT 0,       -- ค่าขนส่งที่จ่าย
    label_url       TEXT,                                  -- URL ใบปะหน้า
    picked_up_at    TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,
    carrier_raw_response JSONB DEFAULT '{}',               -- raw tracking response
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shipments_profession
    ON public.shipments(profession_id, shipment_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shipments_delivery
    ON public.shipments(delivery_order_id);
CREATE INDEX IF NOT EXISTS idx_shipments_tracking
    ON public.shipments(tracking_number)
    WHERE tracking_number IS NOT NULL;

DROP TRIGGER IF EXISTS trg_shipments_updated_at ON public.shipments;
CREATE TRIGGER trg_shipments_updated_at
    BEFORE UPDATE ON public.shipments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.1 Shipment Items (รายการสินค้าในแต่ละ shipment)
CREATE TABLE IF NOT EXISTS public.shipment_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_id     UUID NOT NULL REFERENCES public.shipments(id) ON DELETE CASCADE,
    order_item_id     UUID REFERENCES public.order_items(id) ON DELETE SET NULL,
    product_id        UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_name      TEXT NOT NULL,                       -- snapshot ชื่อ
    quantity          INTEGER NOT NULL DEFAULT 1,
    weight_kg         DECIMAL(8,3) DEFAULT 0,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shipment_items_shipment
    ON public.shipment_items(shipment_id);

-- ============================================================
-- 2. CARRIER CONFIGS (3PL provider settings)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.carrier_configs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    carrier_code    TEXT NOT NULL,                         -- e.g. 'kerry', 'flash', 'j&t'
    carrier_name    TEXT NOT NULL,
    carrier_type    TEXT NOT NULL DEFAULT '3pl'
                        CHECK (carrier_type IN ('3pl', 'own_fleet', 'platform', 'drop_off')),
    api_endpoint    TEXT,                                  -- tracking API URL
    api_key         TEXT,                                  -- encrypted in practice
    is_active       BOOLEAN DEFAULT true,
    base_rate       DECIMAL(12,2) NOT NULL DEFAULT 0,      -- ค่าขนส่งพื้นฐาน
    per_kg_rate     DECIMAL(12,2) NOT NULL DEFAULT 0,     -- ต่อ kg
    cod_fee_rate    DECIMAL(5,2) NOT NULL DEFAULT 0,     -- % COD fee
    contact_phone   TEXT,
    contact_email   TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_carrier_configs_profession
    ON public.carrier_configs(profession_id, is_active, carrier_type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_carrier_configs_code
    ON public.carrier_configs(profession_id, carrier_code);

DROP TRIGGER IF EXISTS trg_carrier_configs_updated_at ON public.carrier_configs;
CREATE TRIGGER trg_carrier_configs_updated_at
    BEFORE UPDATE ON public.carrier_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Add FK constraint to shipments (carrier_configs now exists)
ALTER TABLE public.shipments
    ADD CONSTRAINT fk_shipments_carrier_config
    FOREIGN KEY (carrier_config_id) REFERENCES public.carrier_configs(id) ON DELETE SET NULL;

-- ============================================================
-- 3. DELIVERY EXCEPTIONS (incidents during delivery)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.delivery_exceptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    delivery_order_id UUID NOT NULL REFERENCES public.delivery_orders(id) ON DELETE CASCADE,
    route_stop_id   UUID REFERENCES public.route_stops(id) ON DELETE SET NULL,
    exception_type  TEXT NOT NULL
                        CHECK (exception_type IN (
                            'recipient_not_available', 'address_incorrect',
                            'package_damaged', ' refused_by_recipient',
                            'vehicle_breakdown', 'weather_delay',
                            'traffic_delay', 'other'
                        )),
    severity        TEXT NOT NULL DEFAULT 'medium'
                        CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    description     TEXT,
    photo_url       TEXT,
    gps_lat         DECIMAL(10,8),
    gps_lng         DECIMAL(11,8),
    resolved_at     TIMESTAMPTZ,
    resolution      TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_exceptions_profession
    ON public.delivery_exceptions(profession_id, exception_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_exceptions_order
    ON public.delivery_exceptions(delivery_order_id);

-- ============================================================
-- 4. PROOF OF DELIVERIES (structured delivery confirmation)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.proof_of_deliveries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id   UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    delivery_order_id UUID NOT NULL REFERENCES public.delivery_orders(id) ON DELETE CASCADE,
    route_stop_id   UUID REFERENCES public.route_stops(id) ON DELETE SET NULL,
    proof_type      TEXT NOT NULL
                        CHECK (proof_type IN ('photo', 'signature', 'qr_scan', 'otp', 'id_card', 'note')),
    proof_url       TEXT,                                  -- รูป / URL ลายเซ็น
    metadata        JSONB DEFAULT '{}',                    -- {device_info, gps, timestamp}
    verified_by     UUID REFERENCES public.users(id) ON DELETE SET NULL,
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_proof_of_deliveries_order
    ON public.proof_of_deliveries(delivery_order_id, proof_type);

-- ============================================================
-- 5. RLS POLICIES
-- ============================================================
ALTER TABLE public.shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carrier_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proof_of_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "shipments_select" ON public.shipments;
CREATE POLICY "shipments_select" ON public.shipments FOR SELECT USING (true);
DROP POLICY IF EXISTS "shipments_modify" ON public.shipments;
CREATE POLICY "shipments_modify" ON public.shipments FOR ALL USING (true);

DROP POLICY IF EXISTS "shipment_items_select" ON public.shipment_items;
CREATE POLICY "shipment_items_select" ON public.shipment_items FOR SELECT USING (true);
DROP POLICY IF EXISTS "shipment_items_modify" ON public.shipment_items;
CREATE POLICY "shipment_items_modify" ON public.shipment_items FOR ALL USING (true);

DROP POLICY IF EXISTS "carrier_configs_select" ON public.carrier_configs;
CREATE POLICY "carrier_configs_select" ON public.carrier_configs FOR SELECT USING (true);
DROP POLICY IF EXISTS "carrier_configs_modify" ON public.carrier_configs;
CREATE POLICY "carrier_configs_modify" ON public.carrier_configs FOR ALL USING (true);

DROP POLICY IF EXISTS "delivery_exceptions_select" ON public.delivery_exceptions;
CREATE POLICY "delivery_exceptions_select" ON public.delivery_exceptions FOR SELECT USING (true);
DROP POLICY IF EXISTS "delivery_exceptions_modify" ON public.delivery_exceptions;
CREATE POLICY "delivery_exceptions_modify" ON public.delivery_exceptions FOR ALL USING (true);

DROP POLICY IF EXISTS "proof_of_deliveries_select" ON public.proof_of_deliveries;
CREATE POLICY "proof_of_deliveries_select" ON public.proof_of_deliveries FOR SELECT USING (true);
DROP POLICY IF EXISTS "proof_of_deliveries_modify" ON public.proof_of_deliveries;
CREATE POLICY "proof_of_deliveries_modify" ON public.proof_of_deliveries FOR ALL USING (true);

-- ============================================================
-- 6. RPC FUNCTIONS
-- ============================================================

-- 6.1 Record delivery exception
CREATE OR REPLACE FUNCTION record_delivery_exception(
    p_profession_id UUID,
    p_delivery_order_id UUID,
    p_exception_type TEXT,
    p_severity TEXT DEFAULT 'medium',
    p_description TEXT DEFAULT NULL,
    p_photo_url TEXT DEFAULT NULL,
    p_gps_lat DECIMAL(10,8) DEFAULT NULL,
    p_gps_lng DECIMAL(11,8) DEFAULT NULL,
    p_route_stop_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_exception_id UUID;
BEGIN
    INSERT INTO public.delivery_exceptions (
        profession_id, delivery_order_id, route_stop_id,
        exception_type, severity, description, photo_url,
        gps_lat, gps_lng
    )
    VALUES (
        p_profession_id, p_delivery_order_id, p_route_stop_id,
        p_exception_type, p_severity, p_description, p_photo_url,
        p_gps_lat, p_gps_lng
    )
    RETURNING id INTO v_exception_id;

    -- Update delivery order status to failed if critical
    IF p_severity = 'critical' THEN
        UPDATE public.delivery_orders
        SET delivery_status = 'failed', updated_at = NOW()
        WHERE id = p_delivery_order_id;
    END IF;

    RETURN v_exception_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.2 Create shipment + items
CREATE OR REPLACE FUNCTION create_shipment(
    p_profession_id UUID,
    p_delivery_order_id UUID,
    p_carrier_config_id UUID DEFAULT NULL,
    p_tracking_number TEXT DEFAULT NULL,
    p_weight_kg DECIMAL(8,3) DEFAULT 0,
    p_dimensions_cm JSONB DEFAULT '{}',
    p_shipping_cost DECIMAL(12,2) DEFAULT 0
)
RETURNS UUID AS $$
DECLARE
    v_shipment_id UUID;
BEGIN
    INSERT INTO public.shipments (
        profession_id, delivery_order_id, carrier_config_id,
        tracking_number, weight_kg, dimensions_cm, shipping_cost
    )
    VALUES (
        p_profession_id, p_delivery_order_id, p_carrier_config_id,
        p_tracking_number, p_weight_kg, p_dimensions_cm, p_shipping_cost
    )
    RETURNING id INTO v_shipment_id;

    -- Update delivery order to preparing if still pending
    UPDATE public.delivery_orders
    SET delivery_status = 'preparing', updated_at = NOW()
    WHERE id = p_delivery_order_id AND delivery_status = 'pending';

    RETURN v_shipment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.3 Complete delivery with proof
CREATE OR REPLACE FUNCTION complete_delivery_with_proof(
    p_delivery_order_id UUID,
    p_proof_type TEXT,
    p_proof_url TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}',
    p_verified_by UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_route_stop_id UUID;
    v_proof_id UUID;
    v_run_id UUID;
BEGIN
    -- Find route_stop
    SELECT rs.id, rs.delivery_run_id INTO v_route_stop_id, v_run_id
    FROM public.route_stops rs
    WHERE rs.delivery_order_id = p_delivery_order_id
    ORDER BY rs.created_at DESC
    LIMIT 1;

    -- Insert proof
    INSERT INTO public.proof_of_deliveries (
        profession_id, delivery_order_id, route_stop_id,
        proof_type, proof_url, metadata, verified_by, verified_at
    )
    SELECT
        del.profession_id, p_delivery_order_id, v_route_stop_id,
        p_proof_type, p_proof_url, p_metadata, p_verified_by, CASE WHEN p_verified_by IS NOT NULL THEN NOW() END
    FROM public.delivery_orders del
    WHERE del.id = p_delivery_order_id
    RETURNING id INTO v_proof_id;

    -- Update delivery order
    UPDATE public.delivery_orders
    SET delivery_status = 'delivered',
        delivered_at = NOW(),
        proof_of_delivery = proof_of_delivery || jsonb_build_object(
            p_proof_type, COALESCE(p_proof_url, p_metadata::text)
        ),
        updated_at = NOW()
    WHERE id = p_delivery_order_id;

    -- Update route stop
    IF v_route_stop_id IS NOT NULL THEN
        UPDATE public.route_stops
        SET status = 'delivered', actual_arrival = NOW(), updated_at = NOW()
        WHERE id = v_route_stop_id;
    END IF;

    -- Update run completed count
    IF v_run_id IS NOT NULL THEN
        UPDATE public.delivery_runs
        SET completed_orders = completed_orders + 1,
            status = CASE WHEN completed_orders + 1 >= total_orders THEN 'completed' ELSE status END,
            completed_at = CASE WHEN completed_orders + 1 >= total_orders THEN NOW() END,
            updated_at = NOW()
        WHERE id = v_run_id;
    END IF;

    RETURN v_proof_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.4 Update route stop status
CREATE OR REPLACE FUNCTION update_route_stop_status(
    p_route_stop_id UUID,
    p_status TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.route_stops
    SET status = p_status,
        actual_arrival = CASE WHEN p_status = 'arrived' THEN NOW() ELSE actual_arrival END,
        updated_at = NOW()
    WHERE id = p_route_stop_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
