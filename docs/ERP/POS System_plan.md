# POS System — แผนฉบับสมบูรณ์ (ปรับปรุงแล้ว)
### Sheserved Platform — Unified Checkout with Medical Service Centers

> แผนนี้ปรับปรุงจาก `pos-system-plan-b88a9d.md` โดยรวมคำตอบจากผู้ออกแบบระบบและการตรวจสอบโค้ดจริง

---

## 1. Goals & Scope (ไม่เปลี่ยนแปลง)

**Three POS Modes:**

| Mode | Actor | Context | Key Feature |
|---|---|---|---|
| **Mode A: Patient Self-Checkout** | `UserType.consumer` | Online, in-app | Patient เพิ่มสินค้าใส่ตะกร้า, จ่ายออนไลน์, รับใบเสร็จดิจิทัล |
| **Mode B: Counter POS** | Platform Admin/Staff (`role_level` 1 หรือ 2) | Physical counter, walk-in | Staff เลือก patient ด้วย phone/ชื่อ (บังคับลงทะเบียน), เพิ่มสินค้า, รับเงิน/QR |
| **Mode C: ERP Dashboard POS** | สมาชิกของ Profession Group ที่ `uses_pos_system = true` | ERP Dashboard | คลินิกคู่ค้าจัดการ catalog, ดู orders, รับชำระเงิน |

**Walk-in Patient Policy (ตัดสินใจแล้ว: Option A)**
- บังคับให้ staff กรอก **phone number** ของ walk-in patient ก่อน checkout
- ระบบ query ใน `users` table → ถ้าไม่พบ → สร้าง user record ใหม่ด้วย phone number ทันที
- ห้าม guest checkout โดยไม่มี user record เพื่อความถูกต้องในการออกใบเสร็จ

---

## 2. Database Schema (ฉบับสมบูรณ์)

### 2.1 Modified Tables

```sql
-- ============================================
-- PROFESSIONS (Add POS toggle)
-- ============================================
ALTER TABLE professions ADD COLUMN IF NOT EXISTS uses_pos_system BOOLEAN DEFAULT false;
ALTER TABLE professions ADD COLUMN IF NOT EXISTS has_external_hrm BOOLEAN DEFAULT false; -- สำหรับระบบ HR แยกตามองค์กร
ALTER TABLE professions ADD COLUMN IF NOT EXISTS tax_id TEXT; -- สำหรับ นิติบุคคล (NULL สำหรับ บุคคลธรรมดา)
```

### 2.2 New Tables

```sql
-- ============================================
-- ORDER NUMBER SEQUENCE
-- ============================================
CREATE SEQUENCE IF NOT EXISTS order_number_seq START 1;

-- ============================================
-- ORDERS (Unified Order Header)
-- ============================================
CREATE TABLE IF NOT EXISTS orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number      TEXT NOT NULL UNIQUE DEFAULT generate_order_number(), -- e.g., B01-ORD-20260629-0001
  user_id           UUID NOT NULL REFERENCES users(id),    -- Patient/customer
  profession_id     UUID REFERENCES professions(id),        -- NULL สำหรับ platform orders
  branch_id         UUID REFERENCES organization_branches(id), -- สาขาที่ทำการขาย (Multi-branch)
  pos_mode          TEXT NOT NULL DEFAULT 'patient_self_checkout'
                      CHECK (pos_mode IN ('patient_self_checkout', 'counter_pos', 'erp_dashboard')),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'paid', 'processing', 'completed', 'cancelled', 'refunded')),
  total_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
  vat_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,       -- ภาษีมูลค่าเพิ่ม (VAT) สำหรับออกรายงานภาษีขาย
  wht_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,       -- ภาษีหัก ณ ที่จ่าย (Withholding Tax)
  final_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  currency          TEXT NOT NULL DEFAULT 'THB',
  payment_method    TEXT CHECK (payment_method IN ('cash', 'promptpay', 'omise_card', 'mock')),
  payment_status    TEXT DEFAULT 'unpaid'
                      CHECK (payment_status IN ('unpaid', 'pending', 'paid', 'failed', 'refunded')),
  paid_at           TIMESTAMPTZ,
  served_by         UUID REFERENCES users(id),              -- Staff ที่ประมวลผล order (NULL สำหรับ self-checkout)
  staff_notes       TEXT,                                   -- หมายเหตุจาก staff (Mode B/C)
  coupon_id         UUID,                                   -- อ้างอิง ID ของคูปอง (Integration กับ CRM)
  discount_code     TEXT,                                   -- รหัสส่วนลด (Text backup)
  loyalty_points_used INTEGER DEFAULT 0,                    -- จำนวนแต้มที่ใช้แลกส่วนลด (Integration กับ CRM)
  -- Refund fields
  refund_reason     TEXT,
  refunded_at       TIMESTAMPTZ,
  refunded_by       UUID REFERENCES users(id),
  refund_status     TEXT DEFAULT 'none'
                      CHECK (refund_status IN ('none', 'requested', 'approved', 'rejected', 'completed')),
  refund_requested_at TIMESTAMPTZ,
  refund_approved_by  UUID REFERENCES users(id),
  -- Metadata
  metadata          JSONB DEFAULT '{}',
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- Order queries scoped by: user_id (patient), served_by (staff), profession_id + branch_id (clinic)
-- Enforced in Flutter Repository via ServiceLocator.currentUser?.id + role lookups in user_group_roles / employee_roles

-- ============================================
-- ORDER ITEMS (Line Items)
-- ============================================
CREATE TABLE IF NOT EXISTS order_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  item_type         TEXT NOT NULL
                      CHECK (item_type IN ('consultation_package', 'pharmacy_product', 'membership_plan', 'clinic_service', 'prepaid_package')),
  item_id           UUID NOT NULL,
  item_name         TEXT NOT NULL,                          -- denormalized สำหรับ receipt
  item_snapshot     JSONB NOT NULL,                         -- snapshot ข้อมูล ณ เวลาที่ซื้อ
  quantity          INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price        DECIMAL(12,2) NOT NULL,
  total_price       DECIMAL(12,2) NOT NULL,
  is_vatable        BOOLEAN DEFAULT false,                  -- ใช้คำนวณว่ารายการนี้คิด VAT หรือไม่ (ยา/แพทย์ มักจะยกเว้น)
  vat_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,       -- จำนวนภาษีที่คำนวณได้สำหรับสินค้านี้
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- Order item visibility governed by parent order scope in Repository

-- ============================================
-- UNIFIED PAYMENTS
-- ============================================
CREATE TABLE IF NOT EXISTS unified_payments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID NOT NULL REFERENCES orders(id),
  user_id           UUID NOT NULL REFERENCES users(id),
  amount            DECIMAL(12,2) NOT NULL,
  payment_method    TEXT NOT NULL CHECK (payment_method IN ('cash', 'promptpay', 'omise_card', 'mock')),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'confirmed', 'failed', 'refunded')),
  provider_reference  TEXT,                                 -- reference จาก payment provider
  qr_payload        TEXT,                                   -- สำหรับ PromptPay QR
  confirmed_at      TIMESTAMPTZ,
  confirmed_by      UUID REFERENCES users(id),              -- สำหรับ manual confirmation (Mode B/C)
  failed_reason     TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- Payment queries scoped by user_id or role_level in Repository, not PostgreSQL RLS

-- ============================================
-- SHOPPING CARTS (Mode A only — Per-User Session)
-- ============================================
CREATE TABLE IF NOT EXISTS shopping_carts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL UNIQUE REFERENCES users(id),
  items             JSONB NOT NULL DEFAULT '[]',
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- Cart queries filtered by user_id injected from ServiceLocator in Repository

-- ============================================
-- CLINIC SERVICES (Per-Profession Catalog — Mode C)
-- ============================================
CREATE TABLE IF NOT EXISTS clinic_services (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  name              TEXT NOT NULL,
  description       TEXT,
  price             DECIMAL(12,2) NOT NULL,
  is_vatable        BOOLEAN DEFAULT false,                  -- บริการทางการแพทย์ส่วนใหญ่ยกเว้น VAT แต่ถ้าขายของอาจจะมี
  duration_minutes  INTEGER,
  category          TEXT,                                   -- 'checkup', 'vaccine', 'lab_test', etc.
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- clinic_services queries scoped by profession_id + role_level in Repository
-- Public read (is_active = true) filtered in query, write restricted to staff role checks in Flutter

-- ============================================
-- CLINIC APPOINTMENTS (สร้างใหม่)
-- ผู้ใช้งานสมัครสมาชิกเข้า Profession ที่แพลตฟอร์มสร้างไว้
-- เมื่อ clinic service ถูกซื้อ → สร้าง appointment อัตโนมัติ
-- ============================================
CREATE TABLE IF NOT EXISTS clinic_appointments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID NOT NULL REFERENCES orders(id),
  order_item_id     UUID NOT NULL REFERENCES order_items(id),
  profession_id     UUID NOT NULL REFERENCES professions(id),  -- ศูนย์/คลินิก
  patient_id        UUID NOT NULL REFERENCES users(id),         -- ผู้รับบริการ
  clinic_service_id UUID REFERENCES clinic_services(id),        -- บริการที่จอง
  staff_id          UUID REFERENCES users(id),                  -- เจ้าหน้าที่ที่รับผิดชอบ (optional)
  scheduled_at      TIMESTAMPTZ,                               -- วัน-เวลานัด (NULL = รอการนัดหมาย)
  duration_minutes  INTEGER,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
  notes             TEXT,                                       -- หมายเหตุนัดหมาย
  cancelled_reason  TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- Appointment queries scoped by profession_id + branch_id in Repository, verified against user_group_roles / employee_roles

-- ============================================
-- PROFESSION INVITATIONS (Staff Invitation Flow)
-- ============================================
CREATE TABLE IF NOT EXISTS profession_invitations (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  invited_by        UUID NOT NULL REFERENCES users(id),
  invitee_user_id   UUID REFERENCES users(id),
  invitee_phone     TEXT,
  invitee_email     TEXT,
  proposed_role_level INTEGER NOT NULL DEFAULT 3 CHECK (proposed_role_level IN (2, 3)),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'accepted', 'rejected', 'expired')),
  message           TEXT,
  expires_at        TIMESTAMPTZ DEFAULT (now() + INTERVAL '7 days'),
  accepted_at       TIMESTAMPTZ,
  rejected_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- Invitation queries filtered by current user role in Repository, not by PostgreSQL RLS

-- Unique constraint: ป้องกัน duplicate pending invitations
CREATE UNIQUE INDEX IF NOT EXISTS idx_invitations_unique_pending
  ON profession_invitations(profession_id, invitee_user_id)
  WHERE status = 'pending';

-- ============================================
-- REFUND REQUESTS (Approval Flow)
-- ============================================
CREATE TABLE IF NOT EXISTS refund_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID NOT NULL REFERENCES orders(id),
  requested_by      UUID NOT NULL REFERENCES users(id),     -- Patient หรือ Staff ที่ขอ refund
  reason            TEXT NOT NULL,
  amount            DECIMAL(12,2) NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
  reviewed_by       UUID REFERENCES users(id),              -- Admin ที่ approve/reject
  reviewed_at       TIMESTAMPTZ,
  review_note       TEXT,
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- Query filters applied in POS Repository: patient sees own, staff sees clinic-scoped, admin sees all

-- ============================================
-- IN-APP NOTIFICATIONS (Platform notifications — ไม่ใช้ external push)
-- ============================================
CREATE TABLE IF NOT EXISTS platform_notifications (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id),
  type              TEXT NOT NULL
                      CHECK (type IN ('pos_invitation', 'order_status', 'refund_status', 'appointment_update', 'general')),
  title             TEXT NOT NULL,
  body              TEXT NOT NULL,
  data              JSONB DEFAULT '{}',                      -- context data (order_id, invitation_id, etc.)
  is_read           BOOLEAN DEFAULT false,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- Access Control: Application Layer (Repository Pattern)
-- RLS enforced in Flutter via ServiceLocator + role checks — see Auth Guidelines Compliance section
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON platform_notifications(user_id, is_read, created_at DESC)
  WHERE is_read = false;
```

### 2.3 DB Functions

```sql
-- ============================================
-- ORDER NUMBER GENERATOR
-- ============================================
CREATE OR REPLACE FUNCTION generate_order_number(p_branch_code TEXT DEFAULT '')
RETURNS TEXT AS $$
DECLARE
  v_date TEXT;
  v_seq  TEXT;
  v_prefix TEXT;
BEGIN
  v_date := TO_CHAR(now(), 'YYYYMMDD');
  v_seq  := LPAD(nextval('order_number_seq')::TEXT, 4, '0');
  v_prefix := CASE WHEN p_branch_code != '' THEN p_branch_code || '-' ELSE '' END;
  RETURN v_prefix || 'ORD-' || v_date || '-' || v_seq;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- CONFIRM PAYMENT + UPDATE ORDER (Atomic)
-- ============================================
CREATE OR REPLACE FUNCTION confirm_unified_payment(
  p_payment_id UUID,
  p_reference TEXT,
  p_confirmed_by UUID DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE unified_payments
  SET status = 'confirmed',
      confirmed_at = now(),
      provider_reference = p_reference,
      confirmed_by = p_confirmed_by
  WHERE id = p_payment_id AND status = 'pending';

  UPDATE orders
  SET status = 'paid',
      payment_status = 'paid',
      paid_at = now(),
      updated_at = now()
  WHERE id = (SELECT order_id FROM unified_payments WHERE id = p_payment_id)
    AND status = 'pending';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- CONFIRM CASH PAYMENT (Mode B/C)
-- ============================================
CREATE OR REPLACE FUNCTION confirm_cash_payment(
  p_order_id UUID,
  p_served_by UUID
) RETURNS VOID AS $$
BEGIN
  UPDATE orders
  SET status = 'paid',
      payment_status = 'paid',
      paid_at = now(),
      payment_method = 'cash',
      served_by = p_served_by,
      updated_at = now()
  WHERE id = p_order_id AND status = 'pending';

  INSERT INTO unified_payments (order_id, user_id, amount, payment_method, status, confirmed_at, confirmed_by)
  SELECT id, user_id, final_amount, 'cash', 'confirmed', now(), p_served_by
  FROM orders WHERE id = p_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- POST-PURCHASE ACTIONS (Atomic — runs in single transaction)
-- ============================================
CREATE OR REPLACE FUNCTION process_post_purchase_actions(
  p_order_id UUID
) RETURNS VOID AS $$
DECLARE
  v_item RECORD;
  v_order RECORD;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id AND status = 'paid';
  IF NOT FOUND THEN RETURN; END IF;

  FOR v_item IN SELECT * FROM order_items WHERE order_id = p_order_id
  LOOP
    CASE v_item.item_type
      WHEN 'consultation_package' THEN
        -- สร้าง consultation_request record
        INSERT INTO consultation_requests (user_id, package_id, package_name, price, status, created_at, updated_at)
        VALUES (
          v_order.user_id,
          v_item.item_id,
          v_item.item_name,
          v_item.unit_price,
          'pending',
          now(), now()
        ) ON CONFLICT DO NOTHING;

      WHEN 'membership_plan' THEN
        -- activate ใน user_memberships
        INSERT INTO user_memberships (user_id, plan_id, status, activated_at, created_at, updated_at)
        VALUES (v_order.user_id, v_item.item_id, 'active', now(), now(), now())
        ON CONFLICT (user_id, plan_id) DO UPDATE SET status = 'active', activated_at = now();

      WHEN 'prepaid_package' THEN
        -- สร้าง customer_packages record (จากระบบ CRM)
        INSERT INTO customer_packages (customer_user_id, profession_id, package_id, total_sessions, remaining_sessions, status, created_at, updated_at)
        VALUES (
          v_order.user_id,
          v_order.profession_id,
          v_item.item_id,
          (v_item.item_snapshot->>'total_sessions')::INTEGER,
          (v_item.item_snapshot->>'total_sessions')::INTEGER,
          'active',
          now(), now()
        );

      WHEN 'clinic_service' THEN
        -- สร้าง clinic_appointment
        INSERT INTO clinic_appointments (
          order_id, order_item_id, profession_id, patient_id,
          clinic_service_id, status, duration_minutes, created_at, updated_at
        )
        SELECT
          p_order_id, v_item.id, v_order.profession_id, v_order.user_id,
          v_item.item_id, 'pending',
          (v_item.item_snapshot->>'duration_minutes')::INTEGER,
          now(), now()
        ON CONFLICT DO NOTHING;

      ELSE NULL; -- pharmacy_product: managed separately
    END CASE;
  END LOOP;

  -- การใช้งาน Coupon (Integration กับ CRM)
  IF v_order.coupon_id IS NOT NULL THEN
     INSERT INTO coupon_usages (coupon_id, user_id, order_id, used_at)
     VALUES (v_order.coupon_id, v_order.user_id, p_order_id, now());
  END IF;

  -- การใช้งาน แต้ม (Integration กับ CRM)
  IF COALESCE(v_order.loyalty_points_used, 0) > 0 THEN
    INSERT INTO loyalty_point_transactions (
      user_id, profession_id, points, transaction_type, reference_type, reference_id, created_at
    ) VALUES (
      v_order.user_id, v_order.profession_id, -v_order.loyalty_points_used, 'redeemed', 'order', p_order_id, now()
    );
  END IF;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- SEND IN-APP NOTIFICATION (ใช้แทน Push)
-- ============================================
CREATE OR REPLACE FUNCTION send_platform_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO platform_notifications (user_id, type, title, body, data)
  VALUES (p_user_id, p_type, p_title, p_body, p_data)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- INVITE POS STAFF (Admin only)
-- ============================================
CREATE OR REPLACE FUNCTION invite_pos_staff(
  p_profession_id UUID,
  p_invited_by UUID,
  p_invitee_user_id UUID DEFAULT NULL,
  p_invitee_phone TEXT DEFAULT NULL,
  p_proposed_role_level INTEGER DEFAULT 3,
  p_message TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  v_invitation_id UUID;
  v_invitee_name TEXT;
BEGIN
  -- Validate: only admin (role_level 1) can invite
  IF NOT EXISTS (
    SELECT 1 FROM user_group_roles
    WHERE profession_id = p_profession_id AND user_id = p_invited_by AND role_level = 1
  ) THEN
    RAISE EXCEPTION 'Only admin can invite staff';
  END IF;

  -- Check already member
  IF p_invitee_user_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM user_group_roles
    WHERE profession_id = p_profession_id AND user_id = p_invitee_user_id
  ) THEN
    RAISE EXCEPTION 'User is already a member of this group';
  END IF;

  INSERT INTO profession_invitations (
    profession_id, invited_by, invitee_user_id, invitee_phone,
    proposed_role_level, status, message, expires_at
  ) VALUES (
    p_profession_id, p_invited_by, p_invitee_user_id, p_invitee_phone,
    p_proposed_role_level, 'pending', p_message, now() + INTERVAL '7 days'
  ) RETURNING id INTO v_invitation_id;

  -- Send in-app notification to invitee
  IF p_invitee_user_id IS NOT NULL THEN
    PERFORM send_platform_notification(
      p_invitee_user_id,
      'pos_invitation',
      'คำเชิญเข้าร่วมกลุ่มอาชีพ',
      'คุณได้รับคำเชิญเข้าร่วมเป็นสมาชิกกลุ่มอาชีพ',
      jsonb_build_object('invitation_id', v_invitation_id, 'profession_id', p_profession_id)
    );
  END IF;

  RETURN v_invitation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- ACCEPT INVITATION
-- ============================================
CREATE OR REPLACE FUNCTION accept_profession_invitation(
  p_invitation_id UUID,
  p_user_id UUID
) RETURNS VOID AS $$
DECLARE
  v_inv RECORD;
BEGIN
  SELECT * INTO v_inv FROM profession_invitations WHERE id = p_invitation_id;

  IF v_inv IS NULL THEN RAISE EXCEPTION 'Invitation not found'; END IF;
  IF v_inv.status != 'pending' THEN RAISE EXCEPTION 'Invitation is no longer pending'; END IF;
  IF v_inv.expires_at < now() THEN
    UPDATE profession_invitations SET status = 'expired' WHERE id = p_invitation_id;
    RAISE EXCEPTION 'Invitation has expired';
  END IF;
  IF v_inv.invitee_user_id IS NOT NULL AND v_inv.invitee_user_id != p_user_id THEN
    RAISE EXCEPTION 'This invitation is for another user';
  END IF;

  INSERT INTO user_group_roles (profession_id, user_id, role_level, created_at, updated_at)
  VALUES (v_inv.profession_id, p_user_id, v_inv.proposed_role_level, now(), now())
  ON CONFLICT (profession_id, user_id) DO NOTHING;

  UPDATE profession_invitations
  SET status = 'accepted', accepted_at = now(), invitee_user_id = p_user_id
  WHERE id = p_invitation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- REQUEST REFUND (Patient/Staff → สร้าง refund request รอ Admin approve)
-- ============================================
CREATE OR REPLACE FUNCTION request_refund(
  p_order_id UUID,
  p_requested_by UUID,
  p_reason TEXT,
  p_amount DECIMAL DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  v_refund_id UUID;
  v_order RECORD;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id AND status = 'paid';
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found or not eligible for refund'; END IF;

  IF EXISTS (SELECT 1 FROM refund_requests WHERE order_id = p_order_id AND status IN ('pending', 'approved')) THEN
    RAISE EXCEPTION 'A refund request already exists for this order';
  END IF;

  INSERT INTO refund_requests (order_id, requested_by, reason, amount, status, created_at, updated_at)
  VALUES (
    p_order_id, p_requested_by, p_reason,
    COALESCE(p_amount, v_order.final_amount),
    'pending', now(), now()
  ) RETURNING id INTO v_refund_id;

  UPDATE orders SET refund_status = 'requested', refund_requested_at = now(), updated_at = now()
  WHERE id = p_order_id;

  RETURN v_refund_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- APPROVE/REJECT REFUND (Admin only)
-- ============================================
CREATE OR REPLACE FUNCTION review_refund(
  p_refund_id UUID,
  p_reviewer_id UUID,
  p_approved BOOLEAN,
  p_note TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_refund RECORD;
BEGIN
  SELECT * INTO v_refund FROM refund_requests WHERE id = p_refund_id AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Refund request not found or already reviewed'; END IF;

  -- Only admin (role_level = 1) can approve
  IF NOT EXISTS (
    SELECT 1 FROM user_group_roles WHERE user_id = p_reviewer_id AND role_level = 1
  ) THEN
    RAISE EXCEPTION 'Only admin can review refund requests';
  END IF;

  IF p_approved THEN
    UPDATE refund_requests
    SET status = 'approved', reviewed_by = p_reviewer_id, reviewed_at = now(), review_note = p_note, updated_at = now()
    WHERE id = p_refund_id;

    UPDATE orders
    SET status = 'refunded', payment_status = 'refunded',
        refund_status = 'approved', refund_reason = v_refund.reason,
        refunded_at = now(), refunded_by = p_reviewer_id, updated_at = now()
    WHERE id = v_refund.order_id;
  ELSE
    UPDATE refund_requests
    SET status = 'rejected', reviewed_by = p_reviewer_id, reviewed_at = now(), review_note = p_note, updated_at = now()
    WHERE id = p_refund_id;

    UPDATE orders
    SET refund_status = 'rejected', updated_at = now()
    WHERE id = v_refund.order_id;
  END IF;

  -- Notify patient
  PERFORM send_platform_notification(
    v_refund.requested_by,
    'refund_status',
    CASE WHEN p_approved THEN 'คำขอคืนเงินได้รับการอนุมัติ' ELSE 'คำขอคืนเงินถูกปฏิเสธ' END,
    COALESCE(p_note, CASE WHEN p_approved THEN 'คำขอคืนเงินของคุณได้รับการอนุมัติแล้ว' ELSE 'คำขอคืนเงินของคุณถูกปฏิเสธ' END),
    jsonb_build_object('refund_id', p_refund_id, 'order_id', v_refund.order_id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.4 Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_profession ON orders(profession_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_pos_mode ON orders(pos_mode, status);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_order ON unified_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_clinic_services_profession ON clinic_services(profession_id, is_active);
CREATE INDEX IF NOT EXISTS idx_appointments_profession ON clinic_appointments(profession_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON clinic_appointments(patient_id, status);
CREATE INDEX IF NOT EXISTS idx_refunds_order ON refund_requests(order_id, status);
CREATE INDEX IF NOT EXISTS idx_invitations_profession ON profession_invitations(profession_id, status);
CREATE INDEX IF NOT EXISTS idx_invitations_invitee ON profession_invitations(invitee_user_id, status);
```

---

## 3. Flutter Architecture

### 3.1 New Feature Module: `lib/features/pos/`

```
lib/features/pos/
├── data/
│   ├── models/
│   │   ├── order_model.dart
│   │   ├── order_item_model.dart
│   │   ├── cart_item_model.dart
│   │   ├── clinic_service_model.dart
│   │   ├── clinic_appointment_model.dart
│   │   ├── payment_result_model.dart
│   │   ├── refund_request_model.dart
│   │   └── invitation_model.dart
│   └── repositories/
│       ├── order_repository.dart
│       ├── cart_repository.dart
│       ├── clinic_service_repository.dart
│       ├── clinic_appointment_repository.dart
│       ├── invitation_repository.dart
│       ├── refund_repository.dart
│       └── platform_notification_repository.dart
├── domain/
│   └── services/
│       ├── cart_service.dart           (Mode A logic)
│       ├── counter_pos_service.dart    (Mode B: counter cart + patient lookup)
│       ├── clinic_pos_service.dart     (Mode C: catalog + orders scoped to profession)
│       ├── checkout_service.dart       (orchestrates order + payment — all modes)
│       └── unified_payment_service.dart (shared QR builder, mock, cash — ไม่ผูกกับ donation)
├── presentation/
│   ├── pages/
│   │   ├── mode_a/
│   │   │   ├── cart_page.dart
│   │   │   ├── checkout_page.dart
│   │   │   └── order_success_page.dart
│   │   ├── mode_b/
│   │   │   ├── counter_pos_page.dart
│   │   │   ├── patient_lookup_page.dart
│   │   │   ├── counter_cart_page.dart
│   │   │   └── counter_receipt_page.dart
│   │   ├── mode_c/
│   │   │   ├── erp_dashboard_page.dart
│   │   │   ├── clinic_catalog_page.dart
│   │   │   ├── clinic_orders_page.dart
│   │   │   ├── clinic_pos_page.dart
│   │   │   ├── clinic_appointments_page.dart
│   │   │   └── clinic_staff_page.dart
│   │   └── shared/
│   │       ├── order_history_page.dart
│   │       ├── receipt_detail_page.dart
│   │       ├── pending_invitations_page.dart
│   │       ├── refund_request_page.dart
│   │       └── notifications_page.dart
│   ├── widgets/
│   │   ├── cart_item_tile.dart
│   │   ├── order_summary_card.dart
│   │   ├── payment_method_selector.dart
│   │   ├── receipt_widget.dart
│   │   ├── patient_search_bar.dart
│   │   ├── walk_in_registration_dialog.dart   ← NEW: Mode B walk-in phone registration
│   │   ├── clinic_service_card.dart
│   │   ├── appointment_card.dart
│   │   ├── refund_request_card.dart
│   │   ├── pos_mode_guard.dart
│   │   └── profession_invitation_banner.dart
│   └── bloc/
│       ├── cart/
│       │   ├── cart_bloc.dart
│       │   ├── cart_event.dart
│       │   └── cart_state.dart
│       ├── counter_pos/
│       │   ├── counter_pos_bloc.dart
│       │   ├── counter_pos_event.dart
│       │   └── counter_pos_state.dart
│       ├── clinic_pos/
│       │   ├── clinic_pos_bloc.dart
│       │   ├── clinic_pos_event.dart
│       │   └── clinic_pos_state.dart
│       └── checkout/
│           ├── checkout_bloc.dart
│           ├── checkout_event.dart
│           └── checkout_state.dart
└── pos_feature.dart   (DI registration + named routes)
```

### 3.2 Named Routes (POS Feature)

```dart
// ใน pos_feature.dart
class PosRoutes {
  static const cartPage         = '/pos/cart';
  static const checkoutPage     = '/pos/checkout';
  static const orderSuccess     = '/pos/order-success';
  static const counterPos       = '/pos/counter';
  static const patientLookup    = '/pos/counter/patient-lookup';
  static const counterCart      = '/pos/counter/cart';
  static const counterReceipt   = '/pos/counter/receipt';
  static const erpDashboard  = '/pos/erp';
  static const clinicCatalog    = '/pos/clinic/catalog';
  static const clinicOrders     = '/pos/clinic/orders';
  static const clinicPosPage    = '/pos/clinic/pos';
  static const clinicAppointments = '/pos/clinic/appointments';
  static const clinicStaff      = '/pos/clinic/staff';
  static const orderHistory     = '/pos/orders';
  static const receiptDetail    = '/pos/receipt';
  static const pendingInvitations = '/pos/invitations';
  static const refundRequest    = '/pos/refund';
  static const notifications    = '/pos/notifications';
}
```

### 3.3 GroupRoleRepository — Methods ที่ต้องเพิ่ม

ต้องเพิ่มใน [group_role_repository.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/admin/data/repositories/group_role_repository.dart):

```dart
/// ดึง role_level ของ user ใน profession ที่ระบุ
/// คืน null ถ้าไม่ได้เป็นสมาชิก
Future<int?> getUserRoleLevel(String professionId, String userId) async {
  try {
    final response = await _client
        .from('user_group_roles')
        .select('role_level')
        .eq('profession_id', professionId)
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    return response?['role_level'] as int?;
  } catch (e) {
    debugPrint('getUserRoleLevel error: $e');
    return null;
  }
}

/// ดึง role_level ต่ำสุด (= permission สูงสุด) ที่ user มีในทุก profession
/// ใช้สำหรับตรวจสอบ Mode B access (platform-level staff)
Future<int?> getHighestRoleLevel(String userId) async {
  try {
    final response = await _client
        .from('user_group_roles')
        .select('role_level')
        .eq('user_id', userId)
        .order('role_level', ascending: true) // ต่ำสุด = สูงสุด
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    return response?['role_level'] as int?;
  } catch (e) {
    debugPrint('getHighestRoleLevel error: $e');
    return null;
  }
}
```

### 3.4 Profession Model — Fields ที่ต้องเพิ่ม

ต้องเพิ่มใน [profession.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/admin/models/profession.dart):

```dart
// ใน class Profession
final bool usesPosSystem;  // true = นิติบุคคลที่ใช้ระบบ POS
final bool hasExternalHrm; // true = องค์กรภายนอกที่มีระบบ HRM ของตนเอง
final String? taxId;       // เลข tax ID สำหรับ นิติบุคคล
```

### 3.5 UnifiedPaymentService (แยกจาก Donation)

**หมายเหตุ:** [payment_service.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/donation/services/payment_service.dart) ผูกแน่นกับ donation escrow logic — **ห้าม reuse โดยตรง**

`UnifiedPaymentService` จะ:
- ✅ Reuse: `_buildPromptPayPayload()`, `_crc16()` (copy ไป shared utility)
- ❌ ไม่ Reuse: escrow transition, `DonationRepository` calls
- ✅ เพิ่มใหม่: `confirmCash()` method สำหรับ Mode B/C

### 3.6 Walk-in Patient Flow (Mode B — บังคับลงทะเบียน)

```dart
// ใน WalkInRegistrationDialog
// 1. Staff กรอก phone number ของ walk-in patient
// 2. query users table → ถ้าพบ: ใช้ user นั้น
// 3. ถ้าไม่พบ → สร้าง user ใหม่ด้วย phone number
//    (ไม่มี email/password — สร้าง placeholder user record)
// 4. ต่อไป PatientLookupPage จะแสดง walk-in user ที่สร้างไว้

Future<UserModel> findOrCreateWalkInPatient(String phone) async {
  final existing = await userRepository.findByPhone(phone);
  if (existing != null) return existing;

  // สร้าง walk-in user record
  return await userRepository.createWalkInUser(
    phone: phone,
    userType: UserType.consumer,
    isWalkIn: true, // flag สำหรับ tracking
  );
}
```

### 3.7 In-App Notification Flow (ไม่ใช้ External Push)

```dart
// InvitationRepository
Stream<List<InvitationModel>> getPendingInvitationsForUser(String userId) {
  return _client
      .from('profession_invitations')
      .stream(primaryKey: ['id'])
      .eq('invitee_user_id', userId)
      .asyncMap((_) => _fetchPendingInvitations(userId));
}

// PlatformNotificationRepository
Stream<int> getUnreadCount(String userId) {
  return _client
      .from('platform_notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .eq('is_read', false)
      .map((rows) => rows.length);
}

// ใน TlzNotificationButton — ปัจจุบัน icon เป็น chat_bubble_outline
// จะต้องเปลี่ยนเป็น notifications_outlined เมื่อรวม notification stream เข้า
```

### 3.8 ProfessionInvitationBanner (แก้ไข Error Handling)

```dart
StreamBuilder<List<InvitationModel>>(
  stream: invitationRepository.getPendingInvitationsForUser(userId),
  builder: (context, snapshot) {
    if (snapshot.hasError) return const SizedBox.shrink(); // ← เงียบถ้า error
    if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
    final invitations = snapshot.data!;
    return ProfessionInvitationBanner(
      count: invitations.length,
      professions: invitations.map((i) => i.professionName).toList(),
      onTap: () => Navigator.pushNamed(context, PosRoutes.pendingInvitations),
      onDismiss: () => setState(() => _bannerDismissed = true),
    );
  },
)
```

---

## 4. Payment Flow (ปรับ PromptPay เป็น Manual Confirm)

### PromptPay — Manual Confirmation Flow (Phase 1-5)

```
[Patient/Staff สร้าง Order]
  → [Generate PromptPay QR (EMVCo format)]
  → [แสดง QR บนหน้าจอ]
  → [Patient/Customer สแกน QR และโอนเงิน]
  → [Staff/Patient อัปโหลด slip หรือ Staff กด "ยืนยันรับเงินแล้ว"]
  → [เรียก confirm_unified_payment() พร้อม confirmed_by = staff_id]
  → [Order status → 'paid']
  → [เรียก process_post_purchase_actions(order_id)]
```

> [!NOTE]
> Webhook จาก payment provider จะพิจารณาเพิ่มใน Phase ถัดไป ปัจจุบันใช้ manual confirmation โดย staff

### Omise Card Payment Flow (Mode A) - จะดำเนินการใน Phase ท้าย

```
[Patient สร้าง Order]
  → [แสดง Omise Credit Card Form (omise_flutter)]
  → [Tokenize card ได้ omise_token]
  → [เรียก backend เพื่อสร้าง Charge ผ่าน Omise Secret Key]
  → [ถ้า Charge success → สร้าง unified_payments status='confirmed']
  → [เรียก process_post_purchase_actions(order_id)]
```

> [!NOTE]
> Omise มีค่าธรรมเนียมบริการ (Service fee) และต้องการการตั้งค่า Merchant account จึงจะถูกเลื่อนไปทำใน Phase 8 (Integration ท้ายสุด)

### Cash Payment Flow (Mode B/C)

```
[Staff เลือก Cash]
  → [กรอก received amount → คำนวณ change]
  → [กด "รับเงินแล้ว"]
  → [เรียก confirm_cash_payment(order_id, staff_id)]
  → [เรียก process_post_purchase_actions(order_id)]
  → [แสดง CounterReceiptPage พร้อม change amount]
```

---

## 5. Refund Flow (Approval)

```
[Patient/Staff ขอ refund]
  → [request_refund(order_id, reason, amount)]
  → [order.refund_status → 'requested']
  → [Admin เห็น pending refund list]
  → [Admin กด Approve/Reject + note]
  → [review_refund(refund_id, approved, note)]
  → [ถ้า Approve: order.status → 'refunded']
  → [In-app notification ส่งถึง patient]
  → [Staff ดำเนินการคืนเงิน manual (เงินสด/โอน)]
```

> [!NOTE]
> Refund ในระยะแรกเป็น manual (Admin approve → staff คืนเงินเอง) ไม่ผ่าน payment gateway อัตโนมัติ

---

## 6. Phased Implementation (ปรับปรุงแล้ว)

### Phase 0: Shared Prerequisites — Week 0 [ใหม่]
- [ ] เพิ่ม `usesPosSystem`, `hasExternalHrm` + `taxId` ใน `Profession` model + `professions` table
- [ ] เพิ่ม `getUserRoleLevel()` + `getHighestRoleLevel()` ใน `GroupRoleRepository`
- [ ] สร้าง `UnifiedPaymentService` (shared QR builder ไม่ผูก donation)
- [ ] สร้าง `generate_order_number()` function + sequence
- [ ] สร้าง `platform_notifications` table + `send_platform_notification()` function
- [ ] สร้าง `PlatformNotificationRepository`
- [ ] เพิ่ม `findByPhone()` + `createWalkInUser()` ใน `UserRepository`

### Phase 1: Core Schema + Mode A — Week 1-2
- [ ] Create tables: `orders`, `order_items`, `unified_payments`, `shopping_carts`
- [ ] Create RLS policies สำหรับทุก table ด้านบน
- [ ] สร้าง `confirm_unified_payment()` + `process_post_purchase_actions()` functions
- [ ] Build `OrderRepository`, `CartRepository`
- [ ] Build `CartService` (Mode A logic)
- [ ] Build `CartPage`, `CheckoutPage`, `OrderSuccessPage`
- [ ] Build `UnifiedPaymentService` (PromptPay QR + Mock)
- [ ] Build `CartBloc`

### Phase 2: Mode B (Counter POS) — Week 3-4
- [ ] Build `CounterPosService` + `WalkInRegistrationDialog`
- [ ] Build `CounterPosPage`, `PatientLookupPage`, `CounterCartPage`, `CounterReceiptPage`
- [ ] Build `PosModeGuard` widget สำหรับ role-based routing
- [ ] เพิ่ม "POS Counter" menu ใน `tlz_drawer.dart` (Admin/Staff role_level 1-2)
- [ ] Build `CounterPosBloc`
- [ ] Cash payment flow พร้อม change calculation

### Phase 3: Mode C (ERP Dashboard POS) — Week 5-6
- [ ] Create tables: `clinic_services`, `clinic_appointments`
- [ ] Create RLS policies สำหรับ clinic tables
- [ ] Build `ClinicServiceRepository`, `ClinicAppointmentRepository`
- [ ] Build `ClinicPosService`
- [ ] Build `ErpDashboardPage`, `ClinicCatalogPage`, `ClinicOrdersPage`, `ClinicPosPage`, `ClinicAppointmentsPage`
- [ ] Build `ClinicPosBloc`

### Phase 4: Invitation System + ProfessionAdminPage — Week 7
- [ ] Create table: `profession_invitations` + unique constraint
- [ ] สร้าง `invite_pos_staff()`, `accept_profession_invitation()` functions
- [ ] Build `InvitationRepository`
- [ ] Build `ClinicStaffPage` (view invitations + send new invitations)
- [ ] Build `PendingInvitationsPage` (user กด accept/reject)
- [ ] Build `ProfessionInvitationBanner` (home page header)
- [ ] อัปเดต `TlzNotificationButton` ให้แสดง pending invitation count
- [ ] เพิ่ม "เป็นองค์กรที่ใช้ POS" toggle + `tax_id` field ใน `ProfessionEditorDialog`
- [ ] เพิ่ม POS badge ใน `ProfessionAdminPage` list

### Phase 5: Refund System + System Integrations — Week 8-9
- [ ] Create table: `refund_requests` + RLS policies
- [ ] สร้าง `request_refund()` + `review_refund()` functions
- [ ] Build `RefundRepository`
- [ ] Build `RefundRequestPage`, `RefundRequestCard`
- [ ] ตรวจสอบ `process_post_purchase_actions()` ทำงานครบทุก item_type
- [ ] อัปเดต `ServiceLocator` เพิ่ม POS repositories + services ทั้งหมด

### Phase 6: Polish & Reports — Week 10
- [ ] Pull-to-refresh, empty states, loading skeletons ทุก page
- [ ] Daily sales report สำหรับ Counter POS (by staff)
- [ ] Daily sales report สำหรับ ERP Dashboard (by profession)
- [ ] Printable receipt template (PDF/share)
- [ ] `NotificationsPage` แสดง platform_notifications ทั้งหมด
- [ ] Final testing & bug fixes

### Phase 7: CRM Integration (Loyalty & Packages) — Week 11
- [ ] เพิ่ม `loyalty_points_used` และ `coupon_id` ใน UI การ checkout (โหมด A/B/C)
- [ ] เชื่อมต่อ `CheckoutService` กับ `CrmRepository` เพื่อลด/เพิ่มแต้มสะสม
- [ ] รองรับการเพิ่ม 'prepaid_package' ลงในตะกร้าสินค้า
- [ ] ทดสอบ Trigger หรือ `process_post_purchase_actions` เพื่อสร้าง `customer_packages`

### Phase 8: Omise Card Integration (Final Phase) — Week 12
- [ ] (รับทราบเรื่องค่าบริการ) สมัครและตั้งค่า Omise Merchant Account สำหรับแพลตฟอร์ม
- [ ] เพิ่ม `omise_flutter` SDK
- [ ] สร้าง `OmisePaymentService` เพื่อทำ Tokenization
- [ ] สร้าง Backend API endpoint (Supabase Edge Function) สำหรับตัดบัตรเครดิต (Charge API)
- [ ] เพิ่ม Credit Card option ใน `PaymentMethodSelector` (Mode A)

---

## 7. Files to Create / Modify (Complete List)

### Phase 0 — Prerequisites (Modified Files)
| File | Change |
|---|---|
| [profession.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/admin/models/profession.dart) | เพิ่ม `usesPosSystem`, `hasExternalHrm` + `taxId` fields |
| [profession_repository.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/admin/data/repositories/profession_repository.dart) | Handle `uses_pos_system`, `has_external_hrm` + `tax_id` ใน create/update |
| [group_role_repository.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/admin/data/repositories/group_role_repository.dart) | เพิ่ม `getUserRoleLevel()` + `getHighestRoleLevel()` |
| `lib/features/auth/data/repositories/user_repository.dart` | เพิ่ม `findByPhone()` + `createWalkInUser()` |
| [service_locator.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/services/service_locator.dart) | Register POS repos + services |

### Phase 0 — Prerequisites (New Files)
| File | Purpose |
|---|---|
| `lib/features/pos/domain/services/unified_payment_service.dart` | Shared payment: QR builder, mock, cash (ไม่ผูก donation) |
| `lib/features/pos/data/repositories/platform_notification_repository.dart` | CRUD + stream in-app notifications |

### Phase 1 — Mode A (New Files)
| File | Purpose |
|---|---|
| `lib/features/pos/data/models/order_model.dart` | Order data model |
| `lib/features/pos/data/models/order_item_model.dart` | Order item model |
| `lib/features/pos/data/models/cart_item_model.dart` | Cart item model |
| `lib/features/pos/data/models/payment_result_model.dart` | Payment result model |
| `lib/features/pos/data/repositories/order_repository.dart` | Order CRUD + queries |
| `lib/features/pos/data/repositories/cart_repository.dart` | Cart CRUD |
| `lib/features/pos/domain/services/cart_service.dart` | Mode A cart business logic |
| `lib/features/pos/domain/services/checkout_service.dart` | Checkout orchestration (all modes) |
| `lib/features/pos/presentation/pages/mode_a/cart_page.dart` | Mode A cart UI |
| `lib/features/pos/presentation/pages/mode_a/checkout_page.dart` | Mode A checkout |
| `lib/features/pos/presentation/pages/mode_a/order_success_page.dart` | Mode A success |
| `lib/features/pos/presentation/widgets/cart_item_tile.dart` | Cart item tile |
| `lib/features/pos/presentation/widgets/payment_method_selector.dart` | Payment method chooser |
| `lib/features/pos/presentation/widgets/receipt_widget.dart` | Receipt display |
| `lib/features/pos/presentation/widgets/order_summary_card.dart` | Order summary |
| `lib/features/pos/presentation/bloc/cart/cart_bloc.dart` | Cart BLoC |
| `lib/features/pos/presentation/bloc/cart/cart_event.dart` | Cart events |
| `lib/features/pos/presentation/bloc/cart/cart_state.dart` | Cart states |
| `lib/features/pos/presentation/pages/shared/order_history_page.dart` | Order history (all modes) |
| `lib/features/pos/presentation/pages/shared/receipt_detail_page.dart` | Receipt detail |
| `lib/features/pos/pos_feature.dart` | DI registration + named routes |

### Phase 1 — Mode A (Modified Files)
| File | Change |
|---|---|
| [tlz_drawer.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/shared/widgets/tlz_drawer.dart) | เพิ่ม "ตะกร้าสินค้า" menu สำหรับ consumer |
| `pubspec.yaml` | เพิ่ม dependency ถ้าจำเป็น (qr_flutter สำหรับ QR display) |

### Phase 2 — Mode B (New Files)
| File | Purpose |
|---|---|
| `lib/features/pos/domain/services/counter_pos_service.dart` | Counter cart + patient lookup logic |
| `lib/features/pos/presentation/pages/mode_b/counter_pos_page.dart` | Counter POS entry |
| `lib/features/pos/presentation/pages/mode_b/patient_lookup_page.dart` | Search patient by phone/name |
| `lib/features/pos/presentation/pages/mode_b/counter_cart_page.dart` | Staff builds cart for patient |
| `lib/features/pos/presentation/pages/mode_b/counter_receipt_page.dart` | Printable receipt + change |
| `lib/features/pos/presentation/widgets/patient_search_bar.dart` | Patient search widget |
| `lib/features/pos/presentation/widgets/walk_in_registration_dialog.dart` | Walk-in phone registration |
| `lib/features/pos/presentation/widgets/pos_mode_guard.dart` | Role-based route guard |
| `lib/features/pos/presentation/bloc/counter_pos/counter_pos_bloc.dart` | Counter POS BLoC |
| `lib/features/pos/presentation/bloc/counter_pos/counter_pos_event.dart` | Counter POS events |
| `lib/features/pos/presentation/bloc/counter_pos/counter_pos_state.dart` | Counter POS states |
| `lib/features/pos/presentation/bloc/checkout/checkout_bloc.dart` | Checkout BLoC |
| `lib/features/pos/presentation/bloc/checkout/checkout_event.dart` | Checkout events |
| `lib/features/pos/presentation/bloc/checkout/checkout_state.dart` | Checkout states |

### Phase 2 — Mode B (Modified Files)
| File | Change |
|---|---|
| [tlz_drawer.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/shared/widgets/tlz_drawer.dart) | เพิ่ม "POS Counter" menu สำหรับ Admin/Staff (role_level 1-2) |

### Phase 3 — Mode C (New Files)
| File | Purpose |
|---|---|
| `lib/features/pos/data/models/clinic_service_model.dart` | Clinic service model |
| `lib/features/pos/data/models/clinic_appointment_model.dart` | Clinic appointment model |
| `lib/features/pos/data/repositories/clinic_service_repository.dart` | Clinic service CRUD |
| `lib/features/pos/data/repositories/clinic_appointment_repository.dart` | Clinic appointment CRUD |
| `lib/features/pos/domain/services/clinic_pos_service.dart` | Clinic catalog + order mgmt |
| `lib/features/pos/presentation/pages/mode_c/erp_dashboard_page.dart` | ERP overview |
| `lib/features/pos/presentation/pages/mode_c/clinic_catalog_page.dart` | Manage services |
| `lib/features/pos/presentation/pages/mode_c/clinic_orders_page.dart` | View/filter orders |
| `lib/features/pos/presentation/pages/mode_c/clinic_pos_page.dart` | Clinic checkout |
| `lib/features/pos/presentation/pages/mode_c/clinic_appointments_page.dart` | Manage appointments |
| `lib/features/pos/presentation/widgets/clinic_service_card.dart` | Clinic service card |
| `lib/features/pos/presentation/widgets/appointment_card.dart` | Appointment card |
| `lib/features/pos/presentation/bloc/clinic_pos/clinic_pos_bloc.dart` | Clinic POS BLoC |
| `lib/features/pos/presentation/bloc/clinic_pos/clinic_pos_event.dart` | Clinic POS events |
| `lib/features/pos/presentation/bloc/clinic_pos/clinic_pos_state.dart` | Clinic POS states |

### Phase 3 — Mode C (Modified Files)
| File | Change |
|---|---|
| [tlz_drawer.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/shared/widgets/tlz_drawer.dart) | เพิ่ม "คลินิกของฉัน" menu สำหรับ Expert ที่มี POS profession |

### Phase 4 — Invitation System (New Files)
| File | Purpose |
|---|---|
| `lib/features/pos/data/models/invitation_model.dart` | Invitation model |
| `lib/features/pos/data/repositories/invitation_repository.dart` | Invitation CRUD + stream |
| `lib/features/pos/presentation/pages/mode_c/clinic_staff_page.dart` | Manage staff + invitations |
| `lib/features/pos/presentation/pages/shared/pending_invitations_page.dart` | User accepts/rejects invites |
| `lib/features/pos/presentation/pages/shared/notifications_page.dart` | All in-app notifications |
| `lib/features/pos/presentation/widgets/profession_invitation_banner.dart` | Home header banner |

### Phase 4 — Invitation System (Modified Files)
| File | Change |
|---|---|
| [profession_admin_page.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/admin/presentation/pages) | เพิ่ม POS toggle + `tax_id` field ใน dialog; POS badge ใน list |
| [tlz_notification_button.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/shared/widgets/tlz_notification_button.dart) | เชื่อม stream pending invitations → แสดง badge count |
| [home_page.dart](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/home/presentation/pages/home_page.dart) | เพิ่ม `ProfessionInvitationBanner` ที่ top |

### Phase 5 — Refund + Integrations (New Files)
| File | Purpose |
|---|---|
| `lib/features/pos/data/models/refund_request_model.dart` | Refund request model |
| `lib/features/pos/data/repositories/refund_repository.dart` | Refund CRUD |
| `lib/features/pos/presentation/pages/shared/refund_request_page.dart` | Create refund request |
| `lib/features/pos/presentation/widgets/refund_request_card.dart` | Refund status card |
| `lib/features/pos/presentation/widgets/daily_sales_report.dart` | Daily sales widget |

---

## 8. Auth Guidelines Compliance

> สอดคล้องกับ [auth_data_guidelines.md](../../.agent/workflows/auth_data_guidelines.md) และ [ERP_CORE_ARCHITECTURE.md](ERP_CORE_ARCHITECTURE.md)

- **User ID:** เสมอจาก `ServiceLocator.instance.currentUser?.id`
- **ห้ามใช้:** `Supabase.instance.client.auth.currentUser?.id` (ค่าจะเป็น `null` เสมอ)
- **Walk-in patient:** ต้องสร้าง real UUID user record ใน `users` table — ห้าม mock IDs
- **Role checks (Application Layer — Repository Pattern):**
  - Mode B: ตรวจ `role_level` จาก `user_group_roles` (1=Admin, 2=Staff) ในฝั่ง Flutter Repository ก่อน query
  - Mode C: ตรวจ `profession.usesPosSystem == true` AND `role_level` จาก `user_group_roles` ในฝั่ง Flutter Repository
- **Profession isolation:** Clinic users query orders ที่ `profession_id = their_profession_id` เท่านั้น — กรองที่ Repository ไม่ใช่ PostgreSQL RLS
- **Access Control:** ไม่ใช้ `ENABLE ROW LEVEL SECURITY` หรือ `auth.uid()` ใน PostgreSQL เนื่องจากระบบใช้ custom `AuthService` ผ่าน `ServiceLocator` แทน Supabase Auth native → ควบคุมสิทธิ์ที่ Application Layer (Repository Pattern) ตามหลักการใน ERP_CORE_ARCHITECTURE.md
- **DB functions:** ใช้ `SECURITY DEFINER` เฉพาะ functions ที่ต้องการ elevated privileges (confirm_payment, post_purchase_actions, refund_review) — ไม่ใช้เพื่อ bypass RLS

---

## 9. Success Criteria (อัปเดต)

### Walk-in Patient (Mode B)
- [ ] Staff กด "Walk-in" → กรอก phone number
- [ ] ถ้า phone ไม่อยู่ในระบบ → สร้าง user ใหม่อัตโนมัติ + ใส่ใน cart
- [ ] ใบเสร็จแสดง phone number ของ walk-in patient

### PromptPay (All Modes)
- [ ] แสดง QR code บนหน้าจอ (สร้างจาก EMVCo format)
- [ ] Staff กด "ยืนยันรับเงินแล้ว" → order status → 'paid'
- [ ] ไม่ต้อง webhook ในระยะแรก

### Refund (Mode B/C)
- [ ] Patient/Staff ขอ refund พร้อมระบุเหตุผล
- [ ] Admin เห็น pending refund list
- [ ] Admin กด Approve/Reject + note
- [ ] In-app notification ส่งถึง patient ทันที
- [ ] Staff ดำเนินการคืนเงิน manual หลัง approve

### In-App Notification
- [ ] เมื่อได้รับ invitation → notification badge เพิ่มใน `TlzNotificationButton`
- [ ] Banner ปรากฏที่ top ของ `HomePage`
- [ ] `NotificationsPage` แสดง notifications ทั้งหมด พร้อม mark as read
- [ ] **ยังไม่มี** FCM/APNs push notification (พิจารณาภายหลัง)

### clinic_appointments
- [ ] เมื่อ clinic_service ถูกซื้อ → appointment สร้างอัตโนมัติ (status='pending')
- [ ] Clinic staff เห็น pending appointments ใน `ClinicAppointmentsPage`
- [ ] Staff สามารถ confirm appointment + ระบุวันเวลานัด
- [ ] Patient เห็น appointment status ใน order history
