# Procurement / Purchasing (ระบบจัดซื้อจัดจ้าง)

## ภาพรวม (Overview)

ระบบจัดซื้อจัดจ้างสำหรับ Sheserved ERP รองรับ workflow แบบ **PR → PO → Goods Receipt → Back Order** ภายใต้การควบคุมสิทธิ์ระดับองค์กร (`profession_id`) และสาขา (`branch_id`) ตาม [ERP_CORE_ARCHITECTURE.md](ERP_CORE_ARCHITECTURE.md) พร้อมบันทึก **transaction saga observability** สำหรับ multi-step GR completion

ระบบนี้ถูกออกแบบให้:
- แยก **Purchase Requisition (PR)** กับ **Purchase Order (PO)** อย่างชัดเจน
- มี **ระบบอนุมัติตาม Role + วงเงิน**
- รองรับ **การรับของบางส่วน (Partial Receipt)** พร้อมติดตาม **Back Order**
- มี **ระบบแจ้งเตือน/รายงาน** ถึงผู้สั่ง ผู้อนุมัติ ผู้รับของ และ Supplier
- มี **Auto-Reorder** แต่ต้องมีผู้ยืนยัน (Confirmed) จึงมีผล
- รองรับ **2 โหมด Price History** (Snapshot ใน PO/PR = โหมด A เป็นค่าเริ่มต้น, ตาราง `supplier_price_history` = โหมด B เลือกใช้ได้)
- ไม่มี 3-Way Matching ใน Procurement Step 1 (Procurement Step 4 ค่อยเพิ่มใบวางบิล)

---

## ฟีเจอร์หลัก (Core Features)

1. **Supplier Management**
   - จัดการข้อมูลผู้จัดจำหน่าย (Vendors/Suppliers)
   - เก็บเงื่อนไขการชำระเงิน (Payment Terms), Tax ID, ที่อยู่
   - สถานะ Active/Inactive

2. **Purchase Requisition (PR)**
   - ใบขอซื้อจากแผนก/สาขา (เช่น ห้องยาขอซื้อยาเพิ่ม)
   - ระบุสินค้าจาก `products` (✅ unified product catalog)
   - ประมาณการราคา (`estimated_unit_price`) (✅ PR Items ใน Step 2)
   - สถานะ: `draft` → `pending_approval` → `approved` → `converted` / `rejected`

3. **Purchase Order (PO)**
   - ใบสั่งซื้ออย่างเป็นทางการส่งให้ Supplier
   - Step 1: 1 PR → 1 PO (ผ่าน `pr_id` FK ตรง) หรือสั่งตรงได้
   - สถานะ: `draft` → `sent` → `partially_received` → `fully_received` / `cancelled`

4. **Approval Workflow (Role + วงเงิน)**
   - Staff สร้าง PR/PO → Manager/Admin อนุมัติ
   - ถ้ายอด < `approval_amount_threshold` (ค่าเริ่มต้น 10,000 บาท) ผู้มี `access_level >= 2` สั่งได้เลย
   - ถ้ายอด >= threshold ต้องผ่าน `access_level = 3` (Full Access)
   - บันทึก `approved_by`, `approved_at`

5. **Goods Receipt (GR)**
   - รับของเข้าตาม PO ได้หลายครั้ง (Partial Receipt)
   - บันทึก Lot Number, Expiry Date, ต้นทุนจริงที่รับ (`unit_cost`)
   - ตรวจสอบจำนวน: `quantity_received` = `quantity_accepted` + `quantity_rejected`
   - อัปเดต `purchase_order_items.quantity_received`
   - เมื่อรับครบ → PO สถานะ `fully_received`
   - บันทึก `transaction_contexts` (Saga observability) ครบทุก step ใน GR completion

6. **Back Order Tracking**
   - เมื่อรับของบางส่วน ระบบสร้าง `back_orders` อัตโนมัติสำหรับจำนวนที่ยังไม่ได้รับ
   - แจ้งเตือนผู้สั่ง ผู้อนุมัติ ผู้รับของ และ Supplier
   - ระบุ **กำหนดการส่งของครั้งถัดไป** (`expected_delivery_date`) หากทราบ
   - รายงานสรุป: รับเข้าเท่าไร / ขาดเท่าไร / กำหนดส่งครั้งหน้าเมื่อไหร่

7. **Auto-Reorder (Alert → Confirmed → PR)**
   - ระบบตรวจสอบ `inventory_items.reorder_point` อัตโนมัติ
   - สร้าง `reorder_suggestions` เมื่อ stock ต่ำกว่า reorder point
   - **ต้องมีผู้ยืนยัน (Confirm)** จึงแปลงเป็น PR ได้ (`status = 'confirmed'` → `converted_to_pr`)
   - ไม่สร้าง PR โดยอัตโนมัติโดยไม่มีคนยืนยัน

8. **Price History (โหมด A + B)**
   - **โหมด A (ค่าเริ่มต้น):** เก็บ snapshot ราคาใน `purchase_order_items.unit_price` และ `purchase_requisition_items.estimated_unit_price` เท่านั้น
   - **โหมด B (เลือกใช้):** เปิด `procurement_settings.enable_price_history_tracking = true` ระบบจะ snapshot ลง `purchase_order_items` **และ** บันทึกประวัติลง `supplier_price_history` ด้วย เพื่อเปรียบเทียบราคาหลาย Supplier

---

## สถาปัตยกรรมและหลักการกำกับข้อมูล (Architecture & Data Governance)

### Multi-Tenant Isolation
- ทุกตารางมี `profession_id UUID NOT NULL REFERENCES professions(id)` แยกข้อมูลตามองค์กรอย่างเด็ดขาด
- Application Layer ใช้ `ServiceLocator.instance.currentUser?.professionId` กรองข้อมูล (ไม่ใช้ PostgreSQL RLS `auth.uid()`)

### Multi-Branch Support
- `branch_id` = สาขาที่สร้างเอกสาร
- `delivery_branch_id` = สาขาที่รับของ (default = `branch_id`)
- พนักงานระดับ HQ ดูรวมทุกสาขาได้ สาขาย่อยเห็นเฉพาะสาขาตนเอง

### ระดับสิทธิ์ Per-Module Permission (ผ่าน `role_module_permissions`)

ระบบสิทธิ์ใช้ตาราง `role_module_permissions` จาก Reliability Core (Phase 0) โดย `module_name = 'procurement'`:

| access_level | ชื่อ | ความสามารถใน Procurement |
|---|---|---|
| **3 (Full Access)** | ผู้จัดการ/Admin | อนุมัติ PR/PO, ตั้งค่า, ยกเลิกเอกสาร, ดูรายงานทุกสาขา |
| **2 (Edit Access)** | เจ้าหน้าที่จัดซื้อ | สร้าง/แก้ไข PR, PO, Goods Receipt, ยืนยัน Reorder Suggestion |
| **1 (View Only)** | ผู้ดูข้อมูล | ดูรายงาน ดูประวัติ ไม่สามารถแก้ไขได้ |
| **0 (None)** | ไม่มีสิทธิ์ | ไม่สามารถเข้าถึงโมดูล Procurement ได้ |

**ตรวจสอบสิทธิ์ที่ Application Layer:**
```dart
// ดึง access_level ของ user ใน module procurement
final roles = await supabase.rpc('get_user_roles_and_permissions', params: {
  'p_user_id': currentUser.id,
  'p_profession_id': currentUser.professionId,
});
final procurementLevel = roles
    .expand((r) => (r['permissions'] as List))
    .where((p) => p['module_name'] == 'procurement')
    .map((p) => p['access_level'] as int)
    .fold(0, max); // ใช้ค่าสูงสุดจากทุก role

if (procurementLevel < 2) throw UnauthorizedException('ไม่มีสิทธิ์แก้ไข');
```

**Branch Isolation:** ตรวจสอบ `employee_roles.branch_id` — ถ้า `NULL` = HQ ดูทุกสาขา, ถ้ามีค่า = เห็นเฉพาะสาขานั้น

### State Transition Hardening
- ใช้ `CHECK` constraints บนสถานะ (status) ป้องกันการเปลี่ยนสถานะผิดลำดับที่ฐานข้อมูล
- `updated_at` trigger อัปเดตอัตโนมัติทุกตาราง

---

## ฐานข้อมูล (Database Schema)

> **คำเตือน:** ไม่มีนโยบาย RLS ใดๆ ที่ใช้ `auth.uid()` ในฐานข้อมูล PostgreSQL การเข้าถึงข้อมูลควบคุมที่ Application Layer (Repository Pattern + ServiceLocator) ตาม [auth_data_guidelines.md](../../.agent/workflows/auth_data_guidelines.md)

> **สถานะ Migration:**
>
> ✅ **Step 1:** ตาราง `suppliers`, `purchase_requisitions`, `purchase_orders`, `purchase_order_items` ถูก migrate แล้วใน `20260611160000_erp_phase_1_data_and_inflow.sql`
>
> ✅ **Step 2:** ตาราง `purchase_requisition_items`, `goods_receipts`, `goods_receipt_items`, `back_orders`, `procurement_settings`, `document_sequences` ถูก migrate แล้วใน `20260701130000_procurement_step_2_tables.sql` พร้อม RPC functions ใน `20260701140000_procurement_step_2_rpc_functions.sql`, outbox constraint ใน `20260701150000_procurement_add_po_aggregate_type.sql`, และ notification integration ใน `20260701160000_procurement_notification_integration.sql`
>
> ✅ **Step 3:** ตาราง `reorder_suggestions`, `supplier_price_history` ถูก migrate แล้วใน `20260701170000_procurement_step_3_tables.sql` พร้อม RPC functions ใน `20260701180000_procurement_step_3_rpc_functions.sql`
>
> ✅ **Step 4:** ตาราง `supplier_invoices`, `supplier_invoice_items` ถูก migrate แล้วใน `20260702190000_procurement_step_4_matching.sql` พร้อม RPC functions ใน `20260702200000_procurement_step_4_rpc_functions.sql`, dashboard/report RPCs ใน `20260702210000_procurement_step_4_dashboard_report_rpc.sql`, และ PDF/email/search RPCs ใน `20260702220000_procurement_step_4_pdf_email_search.sql`

### 1. ตาราง Master & Config

```sql
-- ผู้จัดจำหน่าย (✅ Migrated: 20260611160000)
CREATE TABLE suppliers (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id    UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  supplier_name    TEXT NOT NULL,
  contact_name     TEXT,
  phone            TEXT,
  email            TEXT,
  address          TEXT,
  tax_id           TEXT,
  payment_terms    TEXT DEFAULT 'net_30',      -- net_30, net_60, cash, etc.
  lead_time_days   INTEGER DEFAULT 7,
  is_active        BOOLEAN DEFAULT true,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

-- ตั้งค่าระบบจัดซื้อต่อองค์กร (✅ Migrated: 20260701130000)
CREATE TABLE procurement_settings (
  id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id                   UUID NOT NULL UNIQUE REFERENCES professions(id) ON DELETE CASCADE,
  enable_price_history_tracking   BOOLEAN DEFAULT false,
  default_payment_terms           TEXT DEFAULT 'net_30',
  auto_reorder_threshold_multiplier DECIMAL(3,2) DEFAULT 1.0,
  approval_amount_threshold       DECIMAL(12,2) DEFAULT 10000,
  created_at                      TIMESTAMPTZ DEFAULT now(),
  updated_at                      TIMESTAMPTZ DEFAULT now()
);

-- ลำดับเลขที่เอกสาร (✅ Migrated: 20260701130000)
CREATE TABLE document_sequences (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id       UUID REFERENCES organization_branches(id) ON DELETE CASCADE,
  prefix          TEXT NOT NULL,                      -- 'PR', 'PO', 'GR'
  year            INTEGER NOT NULL,                   -- ปี ค.ศ. เช่น 2026
  last_number     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, prefix, year)
);

```

### 2. ตาราง Purchase Requisition (PR)

```sql
-- ✅ Migrated: 20260611160000
CREATE TABLE purchase_requisitions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID REFERENCES organization_branches(id) ON DELETE SET NULL,
  requester_id      UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,
  pr_number         TEXT NOT NULL,                      -- PR-20260611-001
  status            TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending_approval','approved','rejected','converted')),
  total_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  notes             TEXT,
  approved_by       UUID REFERENCES users(id) ON DELETE SET NULL,
  approved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, pr_number)
);

-- ✅ Migrated: 20260701130000
CREATE TABLE purchase_requisition_items (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id          UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  requisition_id         UUID NOT NULL REFERENCES purchase_requisitions(id) ON DELETE CASCADE,
  product_id             UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  item_name              TEXT NOT NULL,
  quantity_requested     INTEGER NOT NULL CHECK (quantity_requested > 0),
  estimated_unit_price   DECIMAL(12,2),
  estimated_total_price  DECIMAL(12,2),
  notes                  TEXT,
  created_at             TIMESTAMPTZ DEFAULT now(),
  updated_at             TIMESTAMPTZ DEFAULT now()
);
```

### 3. ตาราง Purchase Order (PO)

```sql
-- ✅ Migrated: 20260611160000
CREATE TABLE purchase_orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id             UUID REFERENCES organization_branches(id) ON DELETE SET NULL,
  supplier_id           UUID NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
  pr_id                 UUID REFERENCES purchase_requisitions(id) ON DELETE SET NULL,
  po_number             TEXT NOT NULL,                      -- PO-20260611-001
  status                TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','sent','partially_received','fully_received','cancelled')),
  total_amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_amount            DECIMAL(12,2) NOT NULL DEFAULT 0,
  grand_total           DECIMAL(12,2) NOT NULL DEFAULT 0,
  notes                 TEXT,
  expected_delivery_date DATE,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, po_number)
);

-- ✅ Migrated: 20260611160000
CREATE TABLE purchase_order_items (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id                  UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  product_id             UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  quantity_ordered       INTEGER NOT NULL DEFAULT 1 CHECK (quantity_ordered > 0),
  quantity_received      INTEGER NOT NULL DEFAULT 0,
  unit_price             DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_price            DECIMAL(12,2) NOT NULL DEFAULT 0,
  expected_delivery_date DATE,
  notes                  TEXT,
  created_at             TIMESTAMPTZ DEFAULT now()
);
```

> **หมายเหตุ Step 1-2:**
> - PO:PR ใช้ FK ตรง (`pr_id`) รองรับ 1:1 ก่อน
> - Junction table `purchase_order_pr_links` (รองรับ N:1) จะเพิ่มใน Procurement Step 4 ถ้าจำเป็น
> - `delivery_branch_id`, `vat_rate`, `discount_amount`, `approved_by/at`, `sent_to_supplier_at` ยังไม่ได้เพิ่ม — อยู่ใน backlog Step 4

### 4. ตาราง Goods Receipt & Back Order

> **สถานะ:** ✅ Migrated: 20260701130000 — พร้อม RPC `create_goods_receipt`, `update_po_status_from_receipt` ใน 20260701140000

```sql
-- ✅ Migrated: 20260701130000
CREATE TABLE goods_receipts (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id               UUID REFERENCES organization_branches(id),
  purchase_order_id       UUID NOT NULL REFERENCES purchase_orders(id),
  gr_number               TEXT NOT NULL,
  receipt_date            TIMESTAMPTZ DEFAULT now(),
  supplier_delivery_note  TEXT,
  received_by             UUID NOT NULL REFERENCES users(id),
  status                  TEXT NOT NULL DEFAULT 'completed'
    CHECK (status IN ('pending','completed','rejected')),
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, gr_number)
);

-- ✅ Migrated: 20260701130000
CREATE TABLE goods_receipt_items (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  goods_receipt_id        UUID NOT NULL REFERENCES goods_receipts(id) ON DELETE CASCADE,
  purchase_order_item_id  UUID NOT NULL REFERENCES purchase_order_items(id),
  quantity_received       INTEGER NOT NULL CHECK (quantity_received > 0),
  quantity_accepted       INTEGER NOT NULL CHECK (quantity_accepted >= 0),
  quantity_rejected       INTEGER NOT NULL DEFAULT 0 CHECK (quantity_rejected >= 0),
  lot_number              TEXT,
  expiry_date             DATE,
  unit_cost               DECIMAL(12,2),
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT check_accepted_plus_rejected CHECK (quantity_accepted + quantity_rejected = quantity_received)
);

-- ✅ Migrated: 20260701130000
CREATE TABLE back_orders (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  purchase_order_id       UUID NOT NULL REFERENCES purchase_orders(id),
  purchase_order_item_id  UUID NOT NULL REFERENCES purchase_order_items(id),
  supplier_id             UUID NOT NULL REFERENCES suppliers(id),
  quantity_back_ordered   INTEGER NOT NULL CHECK (quantity_back_ordered > 0),
  quantity_fulfilled      INTEGER NOT NULL DEFAULT 0 CHECK (quantity_fulfilled >= 0),
  expected_delivery_date  DATE,
  status                  TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','partially_fulfilled','fulfilled','cancelled')),
  notes                   TEXT,
  notified_requester      BOOLEAN DEFAULT false,
  notified_approver       BOOLEAN DEFAULT false,
  notified_receiver       BOOLEAN DEFAULT false,
  notified_supplier       BOOLEAN DEFAULT false,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);
```

### 5. ตาราง Reorder Suggestions & Price History

> **สถานะ:** ✅ Migrated แล้วใน `20260701170000_procurement_step_3_tables.sql`

```sql
-- ✅ Migrated in 20260701170000_procurement_step_3_tables.sql
CREATE TABLE reorder_suggestions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id               UUID REFERENCES organization_branches(id),
  product_id              UUID NOT NULL REFERENCES products(id),
  current_quantity        INTEGER NOT NULL,
  reorder_point           INTEGER NOT NULL,
  suggested_quantity      INTEGER NOT NULL CHECK (suggested_quantity > 0),
  preferred_supplier_id   UUID REFERENCES suppliers(id),
  reason                  TEXT NOT NULL DEFAULT 'below_reorder_point',
  status                  TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','confirmed','rejected','converted_to_pr')),
  confirmed_by            UUID,
  confirmed_at            TIMESTAMPTZ,
  converted_pr_id         UUID REFERENCES purchase_requisitions(id),
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);

-- ✅ Migrated in 20260701170000_procurement_step_3_tables.sql (ใช้เมื่อโหมด Price History เปิด)
CREATE TABLE supplier_price_history (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  supplier_id             UUID NOT NULL REFERENCES suppliers(id),
  product_id              UUID NOT NULL REFERENCES products(id),
  unit_price              DECIMAL(12,2) NOT NULL,
  effective_date          DATE NOT NULL DEFAULT CURRENT_DATE,
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT now()
);
```

### 6. Outbox Events (ตารางกลาง — Reliability Core)

> **สถานะ:** ✅ Migrated แล้วใน `20260609180000_create_accounting_core_schema.sql`
>
> Procurement **ไม่นิยาม `outbox_events` เอง** แต่ใช้ตารางกลางจาก Reliability Core:

```sql
-- ✅ ตารางกลาง (อยู่ใน 20260609180000 แล้ว — ไม่ต้อง migrate ซ้ำ)
-- Procurement ใช้ aggregate_type = 'procurement_gr' สำหรับ event ทุกประเภท
CREATE TABLE outbox_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  aggregate_type  TEXT NOT NULL CHECK (aggregate_type IN (
    'pos_sale','procurement_gr','hr_payroll','telemedicine','logistics','manual'
  )),
  aggregate_id    UUID NOT NULL,
  event_type      TEXT NOT NULL,      -- เช่น 'procurement.po_sent', 'procurement.goods_receipted'
  payload         JSONB NOT NULL DEFAULT '{}',
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','published','failed','processing')),
  retry_count     INT NOT NULL DEFAULT 0,
  error_message   TEXT,
  created_at      TIMESTAMPTZ DEFAULT now(),
  published_at    TIMESTAMPTZ
);
```

### 7. Indexes & Performance

> **สถานะ:** ✅ Index สำหรับตารางที่ migrate แล้วถูกสร้างพร้อม migration ทั้ง Step 1 และ Step 2
> ✅ Index สำหรับตาราง Reorder/Price History ถูกสร้างใน `20260701170000_procurement_step_3_tables.sql`

```sql
-- ✅ Indexes ที่ migrate แล้ว (อยู่ใน 20260611160000)
CREATE INDEX idx_suppliers_profession ON suppliers(profession_id, is_active, supplier_name);
CREATE INDEX idx_pr_profession ON purchase_requisitions(profession_id, status, created_at DESC);
CREATE INDEX idx_po_profession ON purchase_orders(profession_id, status, created_at DESC);
CREATE INDEX idx_po_supplier ON purchase_orders(supplier_id, status);
CREATE INDEX idx_po_items_po ON purchase_order_items(po_id);
CREATE INDEX idx_po_items_product ON purchase_order_items(product_id);

-- ⏳ Indexes สำหรับตาราง Step 2+
CREATE INDEX idx_gr_recent ON goods_receipts(profession_id, branch_id, receipt_date)
  WHERE receipt_date > now() - interval '90 days';
CREATE INDEX idx_back_order_open ON back_orders(profession_id, status)
  WHERE status IN ('open','partially_fulfilled');
CREATE INDEX idx_reorder_pending ON reorder_suggestions(profession_id, branch_id, status)
  WHERE status = 'pending';
CREATE INDEX idx_gr_items_receipt ON goods_receipt_items(goods_receipt_id);
CREATE INDEX idx_gr_items_po_item ON goods_receipt_items(purchase_order_item_id);
CREATE INDEX idx_back_order_po ON back_orders(purchase_order_id);
CREATE INDEX idx_back_order_supplier ON back_orders(supplier_id);
CREATE INDEX idx_price_history_lookup ON supplier_price_history(profession_id, supplier_id, product_id, effective_date);
CREATE INDEX idx_document_sequences_lookup ON document_sequences(profession_id, branch_id, prefix, year);
```

### 8. Trigger อัปเดต updated_at

> **สถานะ:** ✅ Triggers สำหรับ `suppliers`, `purchase_requisitions`, `purchase_orders` ถูกสร้างแล้วใน migration

```sql
-- ฟังก์ชันกลาง (✅ มีอยู่แล้วจาก migration ก่อนหน้า)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers ที่ migrate แล้ว:
-- ✅ Step 1: trg_suppliers_updated_at, trg_pr_updated_at, trg_po_updated_at
-- ✅ Step 2: trg_procurement_settings_updated_at, trg_pr_items_updated_at, trg_goods_receipts_updated_at, trg_gr_items_updated_at, trg_back_orders_updated_at, trg_document_sequences_updated_at
-- ✅ Step 3: trg_reorder_suggestions_updated_at (migrated in 20260701170000)
```

---

## กระบวนการทำงานหลัก (Business Logic)

### 1. Approval Workflow

```
PR Status Flow:
draft → pending_approval → approved → converted
  ↓         ↓                ↓
(ลบ draft)  rejected       rejected

PO Status Flow:
draft → sent → partially_received → fully_received
  ↓                                     ↓
cancelled                            (เสร็จสิ้น)
```

**Logic ที่ Application Layer (Flutter / API):**
- เมื่อ Staff กด "Submit for Approval":
  1. ตรวจสอบ `procurement_settings.approval_amount_threshold` (✅ DB/RPC + Flutter `ProcurementSettingsPage` อ่านค่าแล้ว)
  2. ถ้า `total_amount` < threshold และผู้ใช้มี `access_level >= 2` → อนุมัติอัตโนมัติ (`status = 'approved'`, `approved_by = currentUser.id`)
  3. ถ้า `total_amount` >= threshold → `status = 'pending_approval'` รอ `access_level = 3` กดอนุมัติ
- เมื่อ Manager กด "Reject": revert เป็น `status = 'rejected'`
- **ไม่มี RLS ใน PostgreSQL** ตรวจสอบ `role_module_permissions.access_level` ที่ Repository Layer ก่อน execute

### 2. Auto-Reorder Logic

```
Inventory Check (Cron/Background Job)
  ↓
quantity <= reorder_point * multiplier
  ↓
สร้าง reorder_suggestions (status = 'pending')
  ↓
ผู้ใช้ (Editor/Manager) กด "Confirm" → status = 'confirmed'
  ↓
ผู้ใช้กด "Convert to PR" → สร้าง purchase_requisitions (status = 'draft')
  ↓
PR ดำเนินการตามปกติ
```

**ข้อจำกัด:** ไม่สามารถสร้าง PR โดยอัตโนมัติจาก `reorder_suggestions` ได้ หากไม่มีการ "Confirm" โดยบุคคล

### 3. Partial Receipt → Back Order → Notification

```
PO: สั่ง 100 ชิ้น
  ↓
GR #1: รับ 70 ชิ้น (quantity_accepted=70, quantity_rejected=0)
  ↓
System: update PO.items.quantity_received = 70
        PO.status = 'partially_received'
        สร้าง back_orders: quantity_back_ordered = 30, status='open'
  ↓
รายงาน/แจ้งเตือน (Dashboard + Outbox):
  - ผู้สั่ง (requester): PR #001 รับเข้า 70/100, ค้าง 30
  - ผู้อนุมัติ (approver): PO #002 รับเข้า 70/100, ค้าง 30
  - ผู้รับของ (received_by): GR #001 รับเข้า 70, ค้าง 30
  - Supplier: ค้างส่ง 30 ชิ้น (ถ้ามีกำหนดส่งครั้งหน้า แจ้งด้วย)
```

**รายงานที่ต้องมี:**
- รายงานการรับของตาม PO: รับแล้วเท่าไร / ค้างเท่าไร / กำหนดส่งครั้งถัดไป
- Back Order Summary ราย Supplier
- Notification ผ่าน `outbox_events` → ส่งไปยัง Notification Service / Dashboard Alert

### 4. Price History Modes

**โหมด A (Default):**
- ไม่ต้องสร้าง `supplier_price_history`
- ราคา snapshot อยู่ใน `purchase_order_items.unit_price`
- Query ราคาเก่า: `SELECT unit_price FROM purchase_order_items poi JOIN purchase_orders po ON poi.po_id = po.id WHERE poi.product_id = ? ORDER BY po.created_at DESC`

**โหมด B (เลือกใช้):**
- ตั้งค่า `procurement_settings.enable_price_history_tracking = true`
- เมื่อสร้าง/อนุมัติ PO ให้ INSERT เข้า `supplier_price_history` พร้อมกัน
- รองรับการเปรียบเทียบราคา Supplier หลายรายต่อสินค้าเดียวกัน
- สามารถสลับกลับไปใช้โหมด A ได้ตลอด (ข้อมูลในตารางยังอยู่ แต่ระบบไม่เขียนใหม่)

---

## ER Diagram (Entity Relationship)

```
professions (ERP Core)
  │ profession_id
  ▼
┌─────────────────┐    ┌────────────────────────┐    ┌─────────────────────┐
│    suppliers    │    │ procurement_settings   │    │organization_branches│
│  (✅ Migrated)  │    │   (✅ Migrated)        │    │     (✅ Migrated)   │
└────────┬────────┘    └────────────────────────┘    └─────────────────────┘
         │ supplier_id                                          │
         │                                                      │ branch_id
         ▼                                                      ▼
┌─────────────────────┐    ┌─────────────────────────────┐
│   purchase_orders   │◄───┤   purchase_order_items      │
│  (✅ Migrated)      │    │  (✅ Migrated)              │
│   - supplier_id(FK)│    │   - po_id (FK)              │
│   - pr_id (FK)     │    │   - product_id (FK→products)│
│   - branch_id       │    └──────────┬──────────────────┘
└──────────┬──────────┘               │ po_id (via lot)
           │                          ▼
           │              ┌─────────────────────────────┐
           │              │   inventory_lots             │
           │              │  (✅ Migrated)               │
           │              │   - product_id               │
           │              │   - po_id (FK→purchase_orders)│
           │              │   - quantity_remaining        │
           │              └──────────┬──────────────────┘
           │                         │
           │                         ▼
           │              ┌─────────────────────────────┐
           │              │   stock_movements            │
           │              │  (✅ Migrated)               │
           │              │   - lot_id (FK)              │
           │              │   - movement_type='receipt'   │
           │              │   - reference_type='po'       │
           │              └─────────────────────────────┘
           │
┌──────────▼──────────┐    ┌─────────────────────────────┐
│   goods_receipts    │◄───┤   goods_receipt_items       │
│  (✅ Migrated)       │    │  (✅ Migrated)              │
│   - purchase_order_id│   │   - purchase_order_item_id  │
│   - received_by      │    │   - quantity_accepted       │
│   - branch_id        │    │   - lot_number              │
└──────────────────────┘    │   - expiry_date             │
                            └─────────────────────────────┘

┌─────────────────────────┐    ┌─────────────────────────────┐
│ purchase_requisitions   │◄───┤ purchase_requisition_items  │
│  (✅ Migrated)          │    │  (✅ Migrated)              │
│   - requester_id        │    │   - product_id (FK→products)│
│   - approved_by         │    └─────────────────────────────┘
│   - branch_id           │
└─────────────────────────┘

┌─────────────────────────┐    ┌─────────────────────────────┐
│     back_orders         │    │  reorder_suggestions        │
│  (✅ Migrated)           │    │  (✅ Migrated — Step 3)    │
│   - purchase_order_id   │    │  - product_id               │
│   - purchase_order_item_id│  │  - preferred_supplier_id    │
│   - supplier_id         │    │  - confirmed_by             │
│   - expected_delivery_date│  │  - converted_pr_id          │
└─────────────────────────┘    └─────────────────────────────┘

┌─────────────────────────┐    ┌─────────────────────────────┐
│ supplier_price_history  │    │  outbox_events (Reliability)│
│  (✅ Migrated — Step 3)│    │  (✅ Migrated — ตารางกลาง)  │
│   - supplier_id         │    │   - aggregate_type =        │
│   - product_id          │    │     'procurement_gr'        │
│   - unit_price          │    │   - payload (JSONB)         │
│   - effective_date      │    │   - status                  │
└─────────────────────────┘    └─────────────────────────────┘
```

**Key Relationships:**
- `purchase_orders.supplier_id` → `suppliers` (N:1)
- `purchase_orders.pr_id` → `purchase_requisitions` (N:1, Step 1 = 1:1)
- `purchase_order_items.po_id` → `purchase_orders` (N:1)
- `purchase_order_items.product_id` → `products` (N:1)
- `inventory_lots.po_id` → `purchase_orders` (N:1 — GR สร้าง lot ที่อ้างอิง PO)
- `goods_receipts.purchase_order_id` → `purchase_orders` (N:1)
- `goods_receipt_items.purchase_order_item_id` → `purchase_order_items` (N:1)
- `back_orders.purchase_order_id` → `purchase_orders` (N:1)
- `reorder_suggestions.converted_pr_id` → `purchase_requisitions` (0..1:1)
- `outbox_events` → ตารางกลาง Reliability Core (ใช้ `aggregate_type = 'procurement_gr'`)

---

## การเชื่อมโยงกับระบบอื่น (Integrations)

### Inventory System
- เมื่อ GR สถานะ `completed` → สร้าง/อัปเดต **`inventory_lots`** (ไม่ใช่ `inventory_items.quantity` โดยตรง):
  - `INSERT INTO inventory_lots (product_id, po_id, lot_number, expiry_date, quantity_received, quantity_remaining, unit_cost, ...)`
  - หรือ `UPDATE inventory_lots SET quantity_remaining = quantity_remaining + accepted WHERE lot_number = ? AND product_id = ?`
- สร้าง `stock_movements` (movement_type = `'receipt'`, reference_type = `'po'`, reference_id = PO ID)
- ใช้ RPC `get_product_total_stock(product_id, branch_id)` ตรวจสอบ stock รวม
- บันทึก `lot_number`, `expiry_date`, `unit_cost` ลง `inventory_lots` ตรง (✅ มี `po_id` FK อยู่แล้ว)

### Accounting System
- เมื่อ GR `completed` → สร้างรายการ Accounts Payable (AP) อัตโนมัติ
- ส่ง event ผ่าน `outbox_events` (ตารางกลาง Reliability Core):
  - `aggregate_type = 'procurement_gr'`
  - `event_type = 'procurement.goods_receipted'`
  - payload ประกอบด้วย `profession_id`, `purchase_order_id`, `goods_receipt_id`, `total_cost`, `supplier_id`
- Accounting Module อ่านจาก `inbox_events` แล้วบันทึกลง GL/AP ตามผังบัญชี
- **ไม่มี 3-Way Matching ใน Step 1** (ไม่ต้อง matching กับใบวางบิล — อยู่ใน Step 3)

### Tax & Fiscal Document Core (การเชื่อมโยงภาษี)
- ใน Step 1 การคำนวณภาษีจะทำแบบง่ายใน PO (`purchase_orders.tax_amount` คำนวณตาม `vat_rate` ของคู่ค้า)
- เมื่อระบบพัฒนาถึง Step 3 (3-Way Matching) และระบบ Accounting Core รองรับแบบเต็มรูปแบบ:
  - จะเปลี่ยนมาใช้โครงสร้างภาษีของ **Tax & Fiscal Document Core** เพื่อรองรับการคำนวณภาษีแบบละเอียดรายบรรทัดผ่านตาราง `order_item_tax_lines`
  - รองรับตัวเลือกราคารวมภาษี/แยกภาษี (`is_inclusive` flag)
  - บันทึกการรับใบกำกับภาษีซื้อผ่านตาราง `tax_invoices` โดยอ้างอิงตรงจาก Goods Receipt และ Supplier Invoice

### Notification / Dashboard Alert
- ทุกการเปลี่ยนสถานะ PR/PO/GR/Back Order ที่สำคัญ ส่ง event เข้า `outbox_events`
- Notification Service อ่าน event และส่ง:
  - In-app notification (Flutter)
  - Email ถ้ามี config
  - Dashboard Alert ใน `ProcurementDashboardPage`

### Read Model / Analytics
- ส่ง events ไปยัง Read Model เพื่อสร้าง snapshot:
  - ยอดสั่งซื้อรวมรายเดือน
  - Back Order ค้างราย Supplier
  - ต้นทุนเฉลี่ยต่อสินค้า

---

## รายละเอียด Business Logic เฉพาะ (Detailed Business Logic)

### 5.1 การคำนวณยอดรวม PO (PO Total Calculation)

```
FOR EACH item IN purchase_order_items:
  item.total_price = item.quantity_ordered * item.unit_price

po.subtotal = SUM(item.total_price)
po.tax_amount = po.subtotal * po.vat_rate (default 7.00%, ผู้ใช้สามารถกำหนดเองได้ต่อ PO)
po.discount_amount = user_input (default 0)
po.total_amount = po.subtotal + po.tax_amount - po.discount_amount
```

**Constraint:** `po.total_amount` ต้องถูก recalculate ทุกครั้งที่มีการเพิ่ม/ลบ/แก้ไขรายการสินค้าใน PO

### 5.2 การแปลง PR → PO (PR to PO Conversion)

```
WHEN PR.status = 'approved' AND user clicks "Convert to PO":
  1. CREATE purchase_orders:
     - pr_id = pr.id
     - supplier_id = user_selected (หรือ preferred_supplier จาก reorder)
     - branch_id = pr.branch_id
     - status = 'draft'
     - total_amount/tax_amount/grand_total = calculated from items

  2. FOR EACH pr_item IN purchase_requisition_items (✅ Step 2):
     CREATE purchase_order_item:
       - po_id = new_po.id
       - product_id = pr_item.product_id
       - quantity_ordered = pr_item.quantity_requested
       - unit_price = pr_item.estimated_unit_price (หรือ last_price จาก history)
       - total_price = quantity_ordered * unit_price

  3. UPDATE purchase_requisitions:
     - status = 'converted'
     - updated_at = now()

  4. INSERT outbox_events:
     - aggregate_type = 'procurement_po'
     - event_type = 'procurement.pr_converted_to_po'
     - payload = { pr_id, po_id, profession_id, total_amount }
```

**ข้อจำกัด:**
- PR ที่มี status ไม่ใช่ `approved` ไม่สามารถ convert เป็น PO ได้
- Step 1: 1 PR → 1 PO (ผ่าน `pr_id` FK ตรง) — รองรับ N:1 ใน Step 2

### 5.3 การรับของ (GR) → อัปเดต PO & สร้าง Back Order

```
WHEN Goods Receipt ถูกบันทึก (status = 'completed'):

  FOR EACH gr_item IN goods_receipt_items:
    1. UPDATE purchase_order_items:
       - quantity_received += gr_item.quantity_accepted
       - updated_at = now()

    2. back_order_qty = po_item.quantity_ordered - po_item.quantity_received

    3. IF back_order_qty > 0:
         CREATE back_orders:
           - purchase_order_id = po.id
           - purchase_order_item_id = po_item.id
           - supplier_id = po.supplier_id
           - quantity_back_ordered = back_order_qty
           - quantity_fulfilled = 0
           - status = 'open'
           - expected_delivery_date = user_input (หรือ po.expected_delivery_date)

  4. UPDATE purchase_orders:
     IF ALL po_items.quantity_received >= po_items.quantity_ordered:
       - status = 'fully_received'
     ELSE IF ANY po_items.quantity_received > 0:
       - status = 'partially_received'

  5. UPSERT inventory_lots:
     - product_id = po_item.product_id
     - po_id = po.id
     - lot_number = gr_item.lot_number
     - expiry_date = gr_item.expiry_date
     - quantity_received += gr_item.quantity_accepted
     - quantity_remaining += gr_item.quantity_accepted
     - unit_cost = gr_item.unit_cost

  6. INSERT stock_movements:
     - lot_id = inventory_lot.id
     - movement_type = 'receipt'
     - reference_type = 'po'
     - reference_id = po.id
     - quantity = gr_item.quantity_accepted

  7. INSERT outbox_events (aggregate_type = 'procurement_gr'):
     - event_type = 'procurement.goods_receipted'
     - event_type = 'procurement.po_fully_received' (if fully)
```

### 5.4 State Transition Guard Matrix

**PO Status Transitions (ตรงกับ DB จริง — 5 สถานะ):**
| จากสถานะ | ไปยัง | เงื่อนไข | ผู้ทำได้ |
|---|---|---|---|
| `draft` | `sent` | มีรายการสินค้าอย่างน้อย 1 รายการ | access_level ≥ 2 |
| `draft` | `cancelled` | — | access_level ≥ 2 |
| `sent` | `partially_received` | GR บางส่วน | System/Receiver |
| `sent` | `fully_received` | GR ครบทุกรายการ | System/Receiver |
| `sent` | `cancelled` | ยังไม่มี GR | access_level = 3 |
| `partially_received` | `fully_received` | GR ครบทุกรายการที่ยังค้าง | System/Receiver |
| `partially_received` | `cancelled` | ผู้ใช้ตัดสินใจไม่รับของที่เหลือ | access_level = 3 |

**PR Status Transitions:**
| จากสถานะ | ไปยัง | เงื่อนไข | ผู้ทำได้ |
|---|---|---|---|
| `draft` | `pending_approval` | — | Editor |
| `approved` | `converted` | มี PO ถูกสร้างจาก PR นี้ | access_level ≥ 2 |
| `approved` | `rejected` | — | Manager/Admin |

### 5.5 Idempotency Keys

ทุก operation ที่มีผลต่อเงินหรือ stock ต้องมี idempotency key:

```dart
String generateIdempotencyKey({
  required String operation,
  required String entityId,
  required String userId,
}) {
  return '${operation}_${entityId}_${userId}_${DateTime.now().millisecondsSinceEpoch}';
}
```

**Operations ที่ต้องมี idempotency:**
- Create PR, Update PR status
- Create PO, Update PO status, Convert PR → PO
- Create Goods Receipt (สำคัญที่สุด — ป้องกัน stock เพิ่มซ้ำ)
- Confirm Reorder Suggestion
- Update Back Order (fulfill partial)

### 5.6 Auto-Numbering Logic (Running Number by Branch)

**รูปแบบ:** `{prefix}-{YYYY}-{branch_code}-{running_number}`
- **PR:** `PR-2026-BKK-0001`
- **PO:** `PO-2026-BKK-0001`
- **GR:** `GR-2026-BKK-0001`

**Logic ที่ Application Layer:**
```dart
String generateDocumentNumber({
  required String prefix,      // 'PR', 'PO', 'GR'
  required String branchCode,  // จาก organization_branches.code
  required int currentSequence,
}) {
  final year = DateTime.now().year;
  final seq = currentSequence.toString().padLeft(4, '0');
  return '$prefix-$year-$branchCode-$seq';
}
```

**Sequence Tracking:**
- เก็บ sequence ต่อ `profession_id` + `branch_id` + `prefix` + `year`
- หากไม่มี `branch_id` (HQ) ใช้ `branch_code = 'HQ'`
- Query ล่าสุด: `SELECT MAX(CAST(SUBSTRING(po_number FROM '...') AS INT)) ...`
- หรือใช้ตาราง `document_sequences` แยก เพื่อป้องกัน race condition (ดูรายละเอียดโครงสร้างตารางได้ในส่วนฐานข้อมูล [ตาราง Master & Config](#1-ตาราง-master--config))

---

## หน้าจอ Flutter UI (Flutter Pages)

> [!NOTE]
> ใน **Procurement Step 1** หน้าจอหลักได้รับการรวมศูนย์ไว้ในหน้าจอเดียวที่สวยงามและรองรับ Responsive Layout คือ [ProcurementPage](file:///Users/apisekpanyakong/ProjectFlutter/sheserved/lib/features/erp/presentation/pages/procurement_page.dart) โดยใช้การสลับ Tab (ผู้จัดจำหน่าย, ใบขอซื้อ, ใบสั่งซื้อ) และ Dialog Forms ฝังในหน้าเพื่อความสะดวกและรวดเร็วในการทำงาน

### Procurement Dashboard
- `ProcurementDashboardPage` — ภาพรวม: PR รออนุมัติ, PO รอส่ง, GR วันนี้, Back Order ค้าง, Reorder Alert

### Supplier Management
- `SupplierDirectoryPage` — รายการ Supplier, ค้นหา, เปิด/ปิดสถานะ
- `SupplierDetailPage` — ดูประวัติ PO, Back Order, ราคา (ถ้าเปิดโหมด B)
- `SupplierFormPage` — สร้าง/แก้ไข Supplier

### PR Management
- `PrListPage` — รายการ PR, filter ตามสถานะ/สาขา
- `PrDetailPage` — ดูรายละเอียด PR และรายการสินค้า
- `PrFormPage` — สร้าง/แก้ไข PR, เพิ่มรายการสินค้า (เลือกจาก inventory)
- `PrApprovalPage` — หน้าอนุมัติ/ปฏิเสธ PR (สำหรับ Manager)

### PO Management
- `PoListPage` — รายการ PO, filter ตามสถานะ/Supplier/สาขา
- `PoDetailPage` — ดูรายละเอียด PO และรายการสินค้า
- `PoFormPage` — สร้าง PO จาก PR หรือสั่งตรง, เลือก Supplier
- `PoApprovalPage` — หน้าอนุมัติ/ปฏิเสธ PO
- `PoSendToSupplierPage` — ส่ง PO ให้ Supplier (mark as sent, บันทึกเวลา)

### Goods Receipt
- `GoodsReceiptListPage` — รายการ GR
- `GoodsReceiptFormPage` — รับของตาม PO (scan/search PO), ระบุจำนวนรับ/ตีกลับ, Lot, Expiry
- `GoodsReceiptDetailPage` — ดูรายละเอียด GR และรายการที่รับ

### Back Order & Reports
- `BackOrderListPage` — รายการ Back Order ค้าง, filter ราย Supplier
- `BackOrderDetailPage` — ดูรายละเอียด, อัปเดตกำหนดส่งครั้งถัดไป
- `ProcurementReportPage` — รายงานสรุป:
  - การรับของตาม PO (รับแล้ว/ค้าง/กำหนดส่ง)
  - สรุปยอดสั่งซื้อราย Supplier
  - สรุปต้นทุนการซื้อรายเดือน

### Reorder & Settings
- `ReorderSuggestionPage` — รายการแจ้งเตือนสต๊อกต่ำ, กด Confirm / Reject / Convert to PR
- `ProcurementSettingsPage` — ตั้งค่าวงเงินอนุมัติ, payment terms default, multiplier, เปิด/ปิดโหมด B

---

## ตัวอย่าง Outbox Payload (Outbox Event Examples)

### Event: `procurement.goods_receipted`

```json
{
  "event_id": "evt-gr-001",
  "event_type": "procurement.goods_receipted",
  "aggregate_type": "goods_receipt",
  "aggregate_id": "gr-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T14:30:00Z",
  "payload": {
    "goods_receipt_id": "gr-uuid-001",
    "goods_receipt_number": "GR-2026-0001",
    "purchase_order_id": "po-uuid-001",
    "purchase_order_number": "PO-2026-0001",
    "supplier_id": "sup-uuid-001",
    "supplier_name": "บริษัท ยาดี จำกัด",
    "received_by": "user-uuid-456",
    "receipt_date": "2026-06-09T14:30:00Z",
    "total_items": 3,
    "total_quantity_accepted": 170,
    "total_quantity_rejected": 5,
    "total_cost": 42500.00,
    "items": [
      {
        "product_id": "prod-uuid-001",
        "item_name": "Paracetamol 500mg",
        "quantity_accepted": 100,
        "quantity_rejected": 0,
        "unit_cost": 150.00,
        "lot_number": "LOT-2026-A001",
        "expiry_date": "2027-06-01"
      },
      {
        "product_id": "prod-uuid-002",
        "item_name": "Amoxicillin 250mg",
        "quantity_accepted": 50,
        "quantity_rejected": 5,
        "unit_cost": 200.00,
        "lot_number": "LOT-2026-B002",
        "expiry_date": "2027-12-01"
      },
      {
        "product_id": "prod-uuid-003",
        "item_name": "Syringe 3cc",
        "quantity_accepted": 20,
        "quantity_rejected": 0,
        "unit_cost": 50.00,
        "lot_number": "LOT-2026-C003",
        "expiry_date": null
      }
    ],
    "back_orders_created": [
      {
        "purchase_order_item_id": "poi-uuid-002",
        "item_name": "Amoxicillin 250mg",
        "quantity_back_ordered": 45,
        "expected_delivery_date": "2026-06-20"
      }
    ]
  }
}
```

### Event: `procurement.pr_converted_to_po`

```json
{
  "event_id": "evt-pr-po-001",
  "event_type": "procurement.pr_converted_to_po",
  "aggregate_type": "purchase_order",
  "aggregate_id": "po-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T10:00:00Z",
  "payload": {
    "purchase_requisition_id": "pr-uuid-001",
    "purchase_requisition_number": "PR-2026-0001",
    "purchase_order_id": "po-uuid-001",
    "purchase_order_number": "PO-2026-0001",
    "supplier_id": "sup-uuid-001",
    "supplier_name": "บริษัท ยาดี จำกัด",
    "converted_by": "user-uuid-456",
    "total_amount": 52500.00,
    "item_count": 3
  }
}
```

### Event: `procurement.po_approved`

```json
{
  "event_id": "evt-po-appr-001",
  "event_type": "procurement.po_approved",
  "aggregate_type": "purchase_order",
  "aggregate_id": "po-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T09:30:00Z",
  "payload": {
    "purchase_order_id": "po-uuid-001",
    "purchase_order_number": "PO-2026-0001",
    "approved_by": "user-uuid-789",
    "approved_by_name": "สมชาย ผู้จัดการ",
    "approved_at": "2026-06-09T09:30:00Z",
    "total_amount": 52500.00,
    "auto_approved": false,
    "approval_notes": "อนุมัติตามแผนการจัดซื้อประจำเดือน"
  }
}
```

### Event: `procurement.back_order_created`

```json
{
  "event_id": "evt-bo-001",
  "event_type": "procurement.back_order_created",
  "aggregate_type": "back_order",
  "aggregate_id": "bo-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T14:30:00Z",
  "payload": {
    "back_order_id": "bo-uuid-001",
    "purchase_order_id": "po-uuid-001",
    "purchase_order_number": "PO-2026-0001",
    "purchase_order_item_id": "poi-uuid-002",
    "supplier_id": "sup-uuid-001",
    "supplier_name": "บริษัท ยาดี จำกัด",
    "item_name": "Amoxicillin 250mg",
    "product_id": "prod-uuid-002",
    "quantity_back_ordered": 45,
    "quantity_fulfilled": 0,
    "expected_delivery_date": "2026-06-20",
    "requester_id": "user-uuid-456",
    "approver_id": "user-uuid-789",
    "receiver_id": "user-uuid-101"
  }
}
```

### Event: `inventory.stock_increased` (จาก Procurement)

```json
{
  "event_id": "evt-stock-001",
  "event_type": "inventory.stock_increased",
  "aggregate_type": "procurement_gr",
  "aggregate_id": "prod-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T14:30:00Z",
  "payload": {
    "product_id": "prod-uuid-001",
    "item_name": "Paracetamol 500mg",
    "lot_id": "lot-uuid-001",
    "lot_number": "LOT-2026-A001",
    "quantity_received": 100,
    "quantity_remaining": 100,
    "source_type": "goods_receipt",
    "source_po_id": "po-uuid-001",
    "unit_cost": 150.00,
    "expiry_date": "2027-06-01"
  }
}
```

---

## ตัวอย่าง Notification Payload

### แจ้งเตือนผู้สั่ง (Requester) เมื่อมี Back Order

```json
{
  "notification_id": "notif-001",
  "recipient_id": "user-uuid-456",
  "recipient_role": "requester",
  "type": "back_order_alert",
  "title": "มีรายการสินค้าค้างส่งจาก PO #PO-2026-0001",
  "body": "Paracetamol 500mg รับเข้า 100/200 ชิ้น (ค้าง 100 ชิ้น)",
  "data": {
    "purchase_order_id": "po-uuid-001",
    "purchase_order_number": "PO-2026-0001",
    "goods_receipt_id": "gr-uuid-001",
    "back_order_id": "bo-uuid-001",
    "item_name": "Paracetamol 500mg",
    "quantity_ordered": 200,
    "quantity_received": 100,
    "quantity_back_ordered": 100,
    "expected_delivery_date": "2026-06-20",
    "deep_link": "/procurement/back-orders/bo-uuid-001"
  },
  "channels": ["in_app", "email"],
  "created_at": "2026-06-09T14:30:00Z"
}
```

### แจ้งเตือนผู้อนุมัติ (Approver) เมื่อ PO รออนุมัติ

```json
{
  "notification_id": "notif-002",
  "recipient_id": "user-uuid-789",
  "recipient_role": "approver",
  "type": "po_pending_approval",
  "title": "มี PO รออนุมัติจาก สมชาย กำลัง",
  "body": "PO-2026-0001 ยอดรวม 52,500 บาท รออนุมัติ",
  "data": {
    "purchase_order_id": "po-uuid-001",
    "purchase_order_number": "PO-2026-0001",
    "requester_name": "สมชาย กำลัง",
    "total_amount": 52500.00,
    "item_count": 3,
    "deep_link": "/procurement/po/po-uuid-001/approve"
  },
  "channels": ["in_app", "push"],
  "created_at": "2026-06-09T09:15:00Z"
}
```

### แจ้งเตือน Supplier

```json
{
  "notification_id": "notif-003",
  "recipient_type": "supplier",
  "supplier_id": "sup-uuid-001",
  "type": "back_order_reminder",
  "title": "แจ้งเตือนรายการค้างส่ง — PO-2026-0001",
  "body": "Amoxicillin 250mg ค้างส่ง 45 ชิ้น กำหนดส่ง 20/06/2026",
  "data": {
    "purchase_order_number": "PO-2026-0001",
    "supplier_delivery_note": "GR-2026-0001",
    "item_name": "Amoxicillin 250mg",
    "quantity_back_ordered": 45,
    "expected_delivery_date": "2026-06-20"
  },
  "channels": ["email"],
  "created_at": "2026-06-09T14:30:00Z"
}
```

---

## End-to-End Sample Flow (ตัวอย่างการทำงานแบบเต็ม)

### สถานการณ์: ห้องยาขอซื้อยา Paracetamol และ Amoxicillin

**Step 1 — Reorder Alert (Auto)**
```
inventory_items: Paracetamol 500mg
  current_quantity = 15
  reorder_point = 50
  multiplier = 1.0
  → ระบบสร้าง reorder_suggestions (status = 'pending')
```

**Step 2 — User ยืนยัน Reorder**
```
เภสัชกร (Editor) กด "Confirm"
  → reorder_suggestions.status = 'confirmed'
  → กด "Convert to PR"
  → สร้าง purchase_requisitions:
       pr_number = 'PR-2026-0001'
       status = 'draft'
       requester_id = 'pharmacist-user-001'
       branch_id = 'branch-001'
```

**Step 3 — สร้าง PR และส่งอนุมัติ**
```
เภสัชกรเพิ่มรายการ:
  - Paracetamol 500mg x 200 ชิ้น @ 150 บาท = 30,000
  - Amoxicillin 250mg x 100 ชิ้น @ 200 บาท = 20,000
  PR.total_amount = 50,000

เภสัชกรกด "Submit for Approval"
  → ตรวจสอบ threshold = 10,000
  → 50,000 >= 10,000 → status = 'pending_approval'

ผู้จัดการ (Manager) กด "อนุมัติ"
  → status = 'approved'
  → approved_by = 'manager-user-001'
  → approved_at = 2026-06-09 09:30:00
```

**Step 4 — แปลง PR → PO**
```
เภสัชกรกด "Convert to PO"
  → เลือก Supplier: "บริษัท ยาดี จำกัด"
  → สร้าง purchase_orders:
       po_number = 'PO-2026-0001'
       pr_id = 'PR-2026-0001'
       supplier_id = 'sup-001'
       status = 'draft'
       total_amount = 50,000

  → สร้าง purchase_order_items จาก PR items
  → PR.status = 'converted'
  → Outbox: procurement.pr_converted_to_po

เภสัชกรกด "Send to Supplier"
  → PO.status = 'sent'
  → Outbox: procurement.po_sent
```

**Step 5 — Supplier ส่งของ (GR #1)**
```
วันที่ 2026-06-15 Supplier ส่งมา:
  - Paracetamol 500mg: 200 ชิ้น (ครบ)
  - Amoxicillin 250mg: 50 ชิ้น (ขาด 50 ชิ้น)

เภสัชกรบันทึก GR:
  goods_receipts.gr_number = 'GR-2026-0001'
  goods_receipts.purchase_order_id = 'PO-2026-0001'
  status = 'completed'
  received_by = 'pharmacist-user-001'

  goods_receipt_items:
    - Paracetamol: quantity_received=200, accepted=200, rejected=0
    - Amoxicillin: quantity_received=50, accepted=50, rejected=0

  → อัปเดต PO:
    Paracetamol: quantity_received = 200 (ครบ)
    Amoxicillin: quantity_received = 50 (ค้าง 50)
    PO.status = 'partially_received'

  → สร้าง back_orders:
    item: Amoxicillin 250mg
    quantity_back_ordered = 50
    status = 'open'
    expected_delivery_date = '2026-06-25' (เภสัชกรกรอก)

  → อัปเดต Inventory (inventory_lots):
    Paracetamol: สร้าง lot LOT-2026-A001, qty_remaining = 200
    Amoxicillin: สร้าง lot LOT-2026-B001, qty_remaining = 50

  → Outbox (aggregate_type = 'procurement_gr'):
    - procurement.goods_receipted
    - procurement.back_order_created
```

**Step 6 — Supplier ส่งของครั้งที่ 2 (GR #2)**
```
วันที่ 2026-06-25 Supplier ส่ง Amoxicillin ที่ค้างมา:
  - Amoxicillin 250mg: 50 ชิ้น (ครบ)

เภสัชกรบันทึก GR #2:
  goods_receipts.gr_number = 'GR-2026-0002'
  goods_receipt_items:
    - Amoxicillin: quantity_received=50, accepted=50, rejected=0

  → อัปเดต PO:
    Amoxicillin: quantity_received = 50 + 50 = 100 (ครบ)
    PO.status = 'fully_received'

  → อัปเดต back_orders:
    quantity_fulfilled = 50
    status = 'fulfilled'

  → อัปเดต Inventory (inventory_lots):
    Amoxicillin: lot LOT-2026-B002, qty_remaining = 50

  → Outbox (aggregate_type = 'procurement_gr'):
    - procurement.goods_receipted
    - procurement.po_fully_received
    - procurement.back_order_fulfilled
```

**สรุปรายงานที่ผู้ใช้เห็น:**
| เอกสาร | รายการ | สั่ง/ขอ | รับแล้ว | ค้าง | สถานะ |
|---|---|---|---|---|---|
| PR-2026-0001 | Paracetamol 500mg | 200 | — | — | converted |
| PR-2026-0001 | Amoxicillin 250mg | 100 | — | — | converted |
| PO-2026-0001 | Paracetamol 500mg | 200 | 200 | 0 | fully_received |
| PO-2026-0001 | Amoxicillin 250mg | 100 | 100 | 0 | fully_received |
| GR-2026-0001 | (รวม) | — | 250 | 50 (back order) | completed |
| GR-2026-0002 | Amoxicillin 250mg | — | 50 | 0 | completed |
| BO-2026-0001 | Amoxicillin 250mg | — | 50 | 0 | fulfilled |

---

## Application Service Functions (Backend / RPC)

> หมายเหตุ: ระบบนี้ใช้ **Application Layer** (Flutter Repository → Supabase Client) ไม่ใช่ PostgreSQL Stored Procedures สำหรับ business logic หลัก แต่เพื่อประสิทธิภาพบาง operation อาจใช้ Supabase RPC (PostgREST function) หรือ Serverless Edge Function

### Functions ที่ควรมีใน Application Layer

```dart
// lib/features/procurement/domain/repositories/procurement_repository.dart

abstract class ProcurementRepository {
  // === PR Operations ===
  Future<PurchaseRequisition> createPR({
    required String professionId,
    required String branchId,
    required String requesterId,
    required List<PRItemInput> items,
    String? notes,
  });

  Future<PurchaseRequisition> submitPRForApproval({
    required String prId,
    required String userId,
  });

  Future<PurchaseRequisition> approvePR({
    required String prId,
    required String approverId,
    String? approvalNotes,
  });

  Future<PurchaseRequisition> rejectPR({
    required String prId,
    required String approverId,
    required String reason,
  });

  // === PO Operations ===
  Future<PurchaseOrder> convertPrToPo({
    required String prId,
    required String supplierId,
    required String convertedBy,
  });

  Future<PurchaseOrder> submitPOForApproval({
    required String poId,
    required String userId,
  });

  Future<PurchaseOrder> approvePO({
    required String poId,
    required String approverId,
    String? approvalNotes,
  });

  Future<PurchaseOrder> sendPOToSupplier({
    required String poId,
    required String sentBy,
  });

  Future<PurchaseOrder> cancelPO({
    required String poId,
    required String cancelledBy,
    required String reason,
  });

  // === Goods Receipt Operations ===
  Future<GoodsReceipt> createGoodsReceipt({
    required String poId,
    required String professionId,
    required String branchId,
    required String receivedBy,
    required List<GRItemInput> items,
    String? supplierDeliveryNote,
  });

  // === Back Order Operations ===
  Future<BackOrder> updateBackOrderExpectedDeliveryDate({
    required String backOrderId,
    required DateTime expectedDate,
    required String updatedBy,
  });

  Future<List<BackOrder>> getOpenBackOrdersBySupplier({
    required String supplierId,
    required String professionId,
  });

  // === Reorder Operations ===
  Future<ReorderSuggestion> confirmReorderSuggestion({
    required String suggestionId,
    required String confirmedBy,
  });

  Future<PurchaseRequisition> convertReorderToPR({
    required String suggestionId,
    required String convertedBy,
  });

  // === Dashboard / Report ===
  Future<ProcurementDashboardSummary> getDashboardSummary({
    required String professionId,
    String? branchId,
  });

  Future<List<ProcurementReportRow>> getProcurementReport({
    required String professionId,
    required DateTime startDate,
    required DateTime endDate,
    String? branchId,
    String? supplierId,
  });
}
```

### Supabase RPC (ถ้าต้องการ optimize บาง query)

```sql
-- RPC: คำนวณยอดรวม PO แบบ atomic (ป้องกัน race condition)
CREATE OR REPLACE FUNCTION calculate_po_totals(p_po_id UUID)
RETURNS TABLE(subtotal DECIMAL, tax DECIMAL, total DECIMAL) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(total_price), 0)::DECIMAL AS subtotal,
    COALESCE(SUM(total_price) * 0.07, 0)::DECIMAL AS tax,
    COALESCE(SUM(total_price) * 1.07, 0)::DECIMAL AS total
  FROM purchase_order_items
  WHERE purchase_order_id = p_po_id;
END;
$$ LANGUAGE plpgsql;

-- RPC: ตรวจสอบว่า PO รับของครบหรือยัง
CREATE OR REPLACE FUNCTION check_po_fully_received(p_po_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN NOT EXISTS (
    SELECT 1 FROM purchase_order_items
    WHERE purchase_order_id = p_po_id
      AND quantity_received < quantity_ordered
  );
END;
$$ LANGUAGE plpgsql;

-- RPC: สร้าง back_orders จาก GR ที่รับไม่ครบ
CREATE OR REPLACE FUNCTION create_back_orders_from_gr(p_gr_id UUID)
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER := 0;
  v_po_item RECORD;
BEGIN
  FOR v_po_item IN
    SELECT poi.id, poi.purchase_order_id, poi.quantity_ordered, poi.quantity_received
    FROM purchase_order_items poi
    JOIN goods_receipt_items gri ON gri.purchase_order_item_id = poi.id
    WHERE gri.goods_receipt_id = p_gr_id
      AND poi.quantity_received < poi.quantity_ordered
  LOOP
    INSERT INTO back_orders (
      profession_id, purchase_order_id, purchase_order_item_id,
      supplier_id, quantity_back_ordered, quantity_fulfilled, status
    )
    SELECT
      po.profession_id,
      v_po_item.purchase_order_id,
      v_po_item.id,
      po.supplier_id,
      v_po_item.quantity_ordered - v_po_item.quantity_received,
      0,
      'open'
    FROM purchase_orders po
    WHERE po.id = v_po_item.purchase_order_id
    ON CONFLICT DO NOTHING;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql;
```

---

## Unit Test Scenarios (Test Cases)

### Group 1: PR Lifecycle

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 1.1 | สร้าง PR ที่ valid | items = [Paracetamol x 200] | PR.status = 'draft', PR.total_amount = 30,000 |
| 1.2 | Submit PR ที่มี items ว่าง | items = [] | ข้อผิดพลาด: "ต้องมีอย่างน้อย 1 รายการ" |
| 1.3 | Submit PR ที่ยอด < threshold | total = 5,000 | PR.status = 'approved' (auto), approved_by = userId |
| 1.4 | Submit PR ที่ยอด >= threshold | total = 50,000 | PR.status = 'pending_approval' |
| 1.5 | Manager อนุมัติ PR | PR.status = 'pending_approval' | PR.status = 'approved', approved_at != null |
| 1.6 | Staff ธรรมดาพยายามอนุมัติ PR | user = Staff (Viewer) | ข้อผิดพลาด: "ไม่มีสิทธิ์อนุมัติ" |
| 1.7 | Convert PR ที่ยังไม่ approved | PR.status = 'draft' | ข้อผิดพลาด: "PR ต้องได้รับการอนุมัติก่อน" |
| 1.8 | Convert PR ที่ approved แล้ว | PR.status = 'approved' | PO ถูกสร้าง, PR.status = 'converted' |

### Group 2: PO Lifecycle & Approval

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 2.1 | PO total calculation | total_amount=50,000, tax=3,500 | grand_total = 53,500 |
| 2.2 | Cancel PO ที่ยังไม่ sent | PO.status = 'draft' | PO.status = 'cancelled' |
| 2.3 | Cancel PO ที่ sent แล้ว (ยังไม่มี GR) | PO.status = 'sent' | PO.status = 'cancelled' (access_level = 3 เท่านั้น) |
| 2.4 | Send PO ให้ Supplier | PO.status = 'draft' | PO.status = 'sent' |

### Group 3: Goods Receipt & Back Order

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 3.1 | GR ครบทุกรายการ | PO: Paracetamol x 200, GR: accepted=200 | PO.status = 'fully_received', ไม่มี back_order |
| 3.2 | GR บางส่วน | PO: Amoxicillin x 100, GR: accepted=50 | PO.status = 'partially_received', back_order created qty=50 |
| 3.3 | GR มีของตีกลับ | accepted=45, rejected=5 | quantity_received = 50, quantity_accepted = 45 |
| 3.4 | GR ซ้ำ (idempotency) | same idempotency key กด 2 ครั้ง | ครั้งที่ 2: ข้อผิดพลาด "operation นี้ถูกประมวลผลแล้ว", stock ไม่เพิ่มซ้ำ |
| 3.5 | GR ครั้งที่ 2 ทำให้ครบ | back_order qty=50, GR#2 accepted=50 | PO.status = 'fully_received', back_order.status = 'fulfilled' |
| 3.6 | GR ที่ accepted + rejected != received | accepted=40, rejected=5, received=50 | CHECK constraint failed |
| 3.7 | Inventory updated after GR | Paracetamol, GR accepted=200 | inventory_lots สร้าง lot ใหม่, qty_remaining = 200, มี stock_movement type='receipt' |

### Group 4: Auto-Reorder

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 4.1 | Stock ต่ำกว่า reorder_point | qty=15, reorder_point=50 | reorder_suggestions created, status='pending' |
| 4.2 | Confirm reorder suggestion | suggestion.status='pending' | status='confirmed', confirmed_by = userId |
| 4.3 | Convert confirmed suggestion to PR | status='confirmed' | PR created, suggestion.status='converted_to_pr' |
| 4.4 | Reject reorder suggestion | status='pending' | status='rejected', ไม่มี PR สร้าง |
| 4.5 | Convert suggestion ที่ยังไม่ confirmed | status='pending' | ข้อผิดพลาด: "ต้องยืนยันก่อน" |
| 4.6 | Stock ยังสูงกว่า reorder_point | qty=60, reorder_point=50 | ไม่มี suggestion สร้าง |

### Group 5: Price History & Settings

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 5.1 | โหมด A (default) สร้าง PO | enable_price_history=false | snapshot ใน purchase_order_items อย่างเดียว |
| 5.2 | โหมด B สร้าง PO | enable_price_history=true | snapshot ใน PO items + INSERT supplier_price_history |
| 5.3 | เปลี่ยน threshold เป็น 5,000 | approval_amount_threshold=5000 | PO ที่ total >= 5,000 ต้องรออนุมัติ |
| 5.4 | Multiplier = 1.5 | reorder_point=50, multiplier=1.5 | สร้าง suggestion เมื่อ qty <= 75 (50 * 1.5) |

### Group 6: Permission & Security

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 6.1 | Viewer พยายามสร้าง PR | user.role = Viewer | ข้อผิดพลาด: "ไม่มีสิทธิ์สร้าง" |
| 6.2 | Editor ดู PR ของสาขาอื่น | user.branch_id='A', PR.branch_id='B' | ข้อผิดพลาด: "ไม่มีสิทธิ์ดูข้อมูลสาขานี้" |
| 6.3 | HQ Staff ดูทุกสาขา | user.permission='HQ' | ดู PR ทุกสาขาได้ |
| 6.4 | ข้อมูล tenant isolation | profession_id='A' query profession_id='B' | ไม่พบข้อมูล (ไม่ error แต่ empty result) |

---

## Flutter Data Layer (Repository Interface)

### Abstract Repository Contracts

```dart
// lib/features/procurement/domain/repositories/

abstract class PurchaseRequisitionRepository {
  Future<List<PurchaseRequisition>> getAll({
    required String professionId,
    String? branchId,
    String? status,
    int limit = 20,
    int offset = 0,
  });

  Future<PurchaseRequisition?> getById(String id);
  Future<PurchaseRequisition> create(CreatePRParams params);
  Future<PurchaseRequisition> update(String id, UpdatePRParams params);
  Future<void> delete(String id);
  Future<PurchaseRequisition> submitForApproval(String id);
  Future<PurchaseRequisition> approve(String id, {String? notes});
  Future<PurchaseRequisition> reject(String id, {required String reason});
  Future<PurchaseRequisition> convertToPO(String id, {required String supplierId});
}

abstract class PurchaseOrderRepository {
  Future<List<PurchaseOrder>> getAll({
    required String professionId,
    String? branchId,
    String? status,
    String? supplierId,
  });

  Future<PurchaseOrder?> getById(String id);
  Future<PurchaseOrder> createFromPR({required String prId, required String supplierId});
  Future<PurchaseOrder> createDirect(CreatePOParams params);
  Future<PurchaseOrder> update(String id, UpdatePOParams params);
  Future<PurchaseOrder> submitForApproval(String id);
  Future<PurchaseOrder> approve(String id, {String? notes});
  Future<PurchaseOrder> sendToSupplier(String id);
  Future<PurchaseOrder> cancel(String id, {required String reason});
}

abstract class GoodsReceiptRepository {
  Future<List<GoodsReceipt>> getAll({
    required String professionId,
    String? branchId,
    String? purchaseOrderId,
  });

  Future<GoodsReceipt?> getById(String id);
  Future<GoodsReceipt> create(CreateGRParams params);
  Future<GoodsReceipt> complete(String id);
}

abstract class SupplierRepository {
  Future<List<Supplier>> getAll({
    required String professionId,
    bool? isActive,
  });

  Future<Supplier?> getById(String id);
  Future<Supplier> create(CreateSupplierParams params);
  Future<Supplier> update(String id, UpdateSupplierParams params);
  Future<void> toggleActive(String id);
}

abstract class BackOrderRepository {
  Future<List<BackOrder>> getOpen({
    required String professionId,
    String? supplierId,
  });

  Future<BackOrder?> getById(String id);
  Future<BackOrder> updateExpectedDeliveryDate(String id, DateTime date);
  Future<BackOrder> markFulfilled(String id);
}

abstract class ReorderSuggestionRepository {
  Future<List<ReorderSuggestion>> getPending({
    required String professionId,
    String? branchId,
  });

  Future<ReorderSuggestion> confirm(String id);
  Future<ReorderSuggestion> reject(String id);
  Future<PurchaseRequisition> convertToPR(String id);
}

// === Data Models (DTOs / Entities) ===

class PurchaseRequisition {
  final String id;
  final String professionId;
  final String? branchId;
  final String prNumber;
  final String requesterId;
  final String status;
  final Decimal totalAmount;
  final String? approvedBy;
  final DateTime? approvedAt;
  final List<PurchaseRequisitionItem> items;
  // ...
}

class PurchaseOrder {
  final String id;
  final String professionId;
  final String? branchId;
  final String? deliveryBranchId;
  final String poNumber;
  final String supplierId;
  final String? prId;
  final String status;
  final Decimal totalAmount;
  final List<PurchaseOrderItem> items;
  // ...
}

class GoodsReceipt {
  final String id;
  final String professionId;
  final String purchaseOrderId;
  final String grNumber;
  final String receivedBy;
  final String status;
  final List<GoodsReceiptItem> items;
  // ...
}
```

---

## Auth Guidelines Compliance

- **ไม่มีนโยบาย RLS ใดๆ ที่ใช้ `auth.uid()` ใน PostgreSQL** ทุกตารางใช้ `profession_id` และ `branch_id` เป็น tenant isolation
- การตรวจสอบสิทธิ์ผู้ใช้ทำที่ **Application Layer** ผ่าน Repository Pattern:
  - ดึง `userId` จาก `ServiceLocator.instance.currentUser?.id` (ไม่ใช่ `Supabase.instance.client.auth.currentUser`)
  - ตรวจสอบ `role_module_permissions` ว่าผู้ใช้มี `access_level` ระดับใดใน module `'procurement'` (0=None, 1=View, 2=Edit, 3=Full)
  - กรองข้อมูลตาม `profession_id` และ `employee_roles.branch_id` ก่อน execute query
- `approved_by`, `received_by`, `confirmed_by`, `requester_id` เก็บ `UUID` ของผู้ใช้จาก Application Layer ไม่ใช่จาก `auth.uid()` ของ Supabase
- ทุก write operation ที่มีผลต่อ stock หรือเงิน ต้องผ่าน Reliability Core (idempotency check + outbox publish) ก่อน commit

---

## Integration with Reliability Core (✅ Implement แล้ว)

> Procurement ใช้โครงสร้างพื้นฐาน Reliability Core ที่ implement แล้วใน Phase 0 migrations:
> - `outbox_events` → `20260609180000_create_accounting_core_schema.sql`
> - `idempotency_keys` → `20260609180000_create_accounting_core_schema.sql`
> - `inbox_events` → `20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql`
> - `transaction_contexts` → `20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql`
> - `transaction_audit_log` → `20260612140000_add_reliability_transaction_tables.sql`

### Outbox Events

Procurement ใช้ `aggregate_type` ตาม aggregate ที่เกี่ยวข้อง:

| event_type | aggregate_type | เมื่อไร | Consumer(s) | สถานะ |
|---|---|---|---|---|
| `procurement.pr_approved` | `procurement_pr` | PR ได้รับการอนุมัติ | Notification | ✅ ส่งแล้วใน `approve_purchase_requisition` |
| `procurement.pr_converted_to_po` | `procurement_po` | PR ถูกแปลงเป็น PO | Notification, Inventory | ✅ ส่งแล้วใน `convert_pr_to_po` |
| `procurement.po_sent` | `procurement_po` | PO ส่งให้ Supplier | Notification | ✅ ส่งแล้วใน `send_purchase_order` RPC |
| `procurement.goods_receipted` | `procurement_gr` | GR completed | Inventory, Accounting | ✅ ส่งแล้วใน `create_goods_receipt` |
| `procurement.back_order_created` | `back_order` | มีของค้างส่ง | Notification | ✅ ส่งแล้วใน `create_goods_receipt` |
| `procurement.po_fully_received` | `procurement_po` | PO รับของครบ | Notification, Accounting | ✅ ส่งแล้วใน `create_goods_receipt` |
| `procurement.back_order_fulfilled` | `back_order` | Back order ถูก fulfill ครบ | Notification | ✅ ส่งแล้วใน `create_goods_receipt` |

### Idempotency Keys

Operations ที่ต้องผ่าน idempotency check (`scope = 'procurement_gr'`):
- ✅ การสร้าง GR (ป้องกันการรับของซ้ำ) — `create_goods_receipt` รับ `p_idempotency_key` และเช็ค `idempotency_keys`
- ⏳ การอนุมัติ PR/PO (ป้องกันกดอนุมัติซ้ำ) — ยังไม่มี idempotency

### Transaction Context (Saga) สำหรับ GR Completed ✅ Implemented

> **สถานะ:**  implement แล้วใน `create_goods_receipt` RPC — observability-only (ไม่มี compensation)

```
Saga: create_goods_receipt (source_module = 'procurement')
────────────────────────────────────────────────
1. create_transaction_context(
     source_module='procurement',
     operation_type='create_goods_receipt',
     metadata = {po_id, received_by, branch_id}
   )
2. Step: gr_created — insert goods_receipts
3. Step: gr_items_created — insert goods_receipt_items
4. Step: po_items_updated — update purchase_order_items.quantity_received
5. Step: inventory_lots_created — insert inventory_lots
6. Step: stock_movements_created — insert stock_movements
7. Step: back_orders_processed — create/fulfill back_orders
8. Step: po_status_updated — update_po_status_from_receipt
9. Step: outbox_events_emitted — publish procurement.goods_receipted / po_fully_received / back_order_created / back_order_fulfilled
10. Step: idempotency_stored — store idempotency key
11. Step: audit_logs_recorded — record_audit_log calls
12. update_transaction_context(status='committed', metadata + {gr_id, gr_number})

Error handling:
  → update_transaction_context(status='failed')
  → RAISE (transaction rolled back by PostgreSQL)
```

### Inbox Events (สำหรับ Procurement เป็น Consumer)

| source aggregate_type | event_type | สิ่งที่ Procurement ทำ |
|---|---|---|
| `pos_sale` | `inventory.stock_low` | ตรวจสอบ reorder_point และสร้าง reorder_suggestion |

### Audit Trail & Transaction Saga Observability

> **สถานะ:** ✅ บันทึก `transaction_audit_log` แล้วใน RPC หลัก (`approve_purchase_requisition`, `reject_purchase_requisition`, `convert_pr_to_po`, `send_purchase_order`, `create_goods_receipt`)
> **สถานะ:** ✅ บันทึก `transaction_contexts` สำหรับ GR completion ใน `create_goods_receipt` (10 steps, status `started` → `committed` / `failed`)

ทุกการเปลี่ยนแปลงสถานะ PR/PO/GR ต้องบันทึกลง `transaction_audit_log` ผ่าน RPC `record_audit_log()` และ GR completion บันทึกลง `transaction_contexts` เพื่อ traceability ของ multi-step transaction

---

## Feature Toggle & Subscription

> Procurement ใช้ `organization_feature_flags` (✅ ตาราง + RPC implement แล้วใน Phase 0)

| feature_name | status | ผล |
|---|---|---|
| `procurement_module` | `enabled` | เข้าถึงได้ปกติ |
| `procurement_module` | `disabled` | UI Locked: ข้อมูลเดิมยังอยู่, ไม่สามารถสร้าง/แก้ไขเอกสาร |
| `procurement_module` | `beta` | เปิดทดลอง มี badge "ทดลองใช้งาน" |

**ตรวจสอบที่ App Layer:**
```dart
final flags = await supabase.rpc('get_profession_feature_flags', params: {
  'p_profession_id': currentUser.professionId,
});
final procurementFlag = flags.firstWhere(
  (f) => f['feature_name'] == 'procurement_module',
  orElse: () => {'status': 'disabled'},
);
if (procurementFlag['status'] == 'disabled') {
  // แสดง Locked UI
}
```

---

## DataBroker & Storage Mode

> Procurement repository ต้อง routing ผ่าน **DataBroker** ตาม ERP Core Architecture:
> - **Cloud Mode:** API calls ไป Supabase โดยตรง
> - **Self-host Mode:** API calls ไป IP ของ External Drive (PostgreSQL ที่คลินิก host เอง)
>
> Repository ไม่ควร hardcode endpoint แต่ใช้ `DataBroker.resolve()` เพื่อกำหนด base URL

---

## Notification System

> รายละเอียด notification delivery ดำเนินการตาม [ERP_NOTIFICATION_SYSTEM_PLAN.md](ERP_NOTIFICATION_SYSTEM_PLAN.md)
> - In-App Notification ผ่าน Supabase Realtime (ฟรี)
> - Email/LINE ตาม config ของแต่ละองค์กร
>
> Procurement event payloads (ดู section "Outbox Event Payloads" ด้านบน) ถูกส่งผ่าน `outbox_events` → Notification Service อ่านและแสดงตามช่องทางที่เหมาะสม

---

## แผนการพัฒนา (Phased Implementation)

> **Phase Naming Convention:** ใช้รูปแบบ "ERP Phase X / Procurement Step Y" เพื่อสอดคล้องกับ ERP Master Phase

### ERP Phase 1 / Procurement Step 1: Core (PR + PO + Supplier) ✅ Completed
- **Schema (✅):** `suppliers`, `purchase_requisitions`, `purchase_orders`, `purchase_order_items` → `20260611160000`
- **Inventory (✅):** `inventory_lots` (with `po_id` FK), `stock_movements`, `warehouse_locations` → `20260611160000`
- **Reliability (✅):** `outbox_events`, `idempotency_keys`, `inbox_events`, `transaction_contexts`, `transaction_audit_log`
- **RBAC (✅):** `role_module_permissions` (module = `'procurement'`), `organization_feature_flags`
- **UI (✅):** `ProcurementPage` รวบรวม Suppliers, PR, PO, GR, Back Orders ไว้ในหน้าเดียวแบบ Tabbed UI (route `/erp/suppliers`)

### ERP Phase 1 / Procurement Step 2: GR + Back Order + PR Items + Settings ✅ Completed

#### ✅ Completed (Migrated & Tested)
- **Schema (✅):** `20260701130000_procurement_step_2_tables.sql` สร้างตาราง `goods_receipts`, `goods_receipt_items`, `back_orders`, `purchase_requisition_items`, `procurement_settings`, `document_sequences`
- **RPC (✅):** `20260701140000_procurement_step_2_rpc_functions.sql` — `generate_document_number`, `create_goods_receipt` (พร้อม idempotency check + transaction saga observability), `update_po_status_from_receipt`, `approve_purchase_requisition`, `reject_purchase_requisition`, `convert_pr_to_po` (พร้อม VAT 7% + outbox event), `send_purchase_order`
- **Outbox (✅):** `20260701150000_procurement_add_po_aggregate_type.sql` — เพิ่ม `procurement_po` และ `accounting` เข้า CHECK constraint ของ `outbox_events.aggregate_type`
- **Notification (✅):** `20260701160000_procurement_notification_integration.sql` — `app_notifications` table + trigger แปลง procurement outbox events → in-app notifications
- **Flutter (✅):** Models, Repository (ส่ง `idempotencyKey`), Provider, `ProcurementPage` มี Tab GR + Back Order + ปุ่มสร้าง GR, `ProcurementSettingsPage`, `NotificationListPage`, `TlzNotificationButton`
- **Test Script (✅ ผ่าน):** `supabase/migrations/test_procurement_step_2.sql` — ทดสอบ E2E ครบทุก flow (PR approve → convert PR→PO → send PO → GR partial receipt → back order → inventory lot → stock movement → outbox events → PO status update → back order fulfillment → transaction saga observability)
- **Integration:** GR completed → `inventory_lots` + `stock_movements` + `outbox_events` (aggregate_type = `procurement_gr`); PR→PO → `outbox_events` (aggregate_type = `procurement_po`); outbox events → `app_notifications`
- **สถานะ DB:** ✅ รัน migration แล้วทั้ง 4 files ทดสอบผ่าน

#### Step 2 Deliverables

**Priority 1A — Core Data Flow ✅ Completed**
1. ✅ `convert_pr_to_po` อ่าน PR items จาก `purchase_requisition_items` แทนการรับ `p_items` JSONB
2. ✅ Back order fulfillment logic: อัปเดต `quantity_fulfilled` และ `status = 'fulfilled'` เมื่อ GR รับของค้างครบ

**Priority 1B — Outbox Events ✅ Completed**
3. ✅ ส่ง outbox events ครบทั้ง 4 ที่ขาด: `procurement.pr_approved`, `procurement.back_order_created`, `procurement.po_fully_received`, `procurement.back_order_fulfilled`
4. ✅ เพิ่ม `procurement_pr` และ `back_order` เข้า `outbox_events.aggregate_type` CHECK constraint

**Priority 2 — Application Layer ✅ Completed**
5. ✅ สร้าง `ProcurementSettingsPage` ใน Flutter (วงเงินอนุมัติ, multiplier, price history mode) — route `/erp/procurement-settings`
6. ✅ เชื่อม `procurement_settings.approval_amount_threshold` เข้ากับ PR submit workflow — auto-approve ถ้ายอด < threshold

**Priority 3 — PR Items UI & PO Sent Outbox ✅ Completed**
7. ✅ พัฒนา PR items management UI (เพิ่ม/ลบรายการสินค้าใน PR) — `_showPrItemsDialog` ใน `ProcurementPage`
8. ✅ ส่ง PO status เป็น `procurement.po_sent` ผ่าน `send_purchase_order` RPC + outbox event

**Priority 4 — Audit Trail & Notification ✅ Completed**
9. ✅ บันทึก `transaction_audit_log` สำหรับทุกการเปลี่ยนสถานะ PR/PO/GR — เพิ่ม `record_audit_log()` ใน `approve_purchase_requisition`, `reject_purchase_requisition`, `convert_pr_to_po`, `send_purchase_order`, `create_goods_receipt`
10. ✅ เชื่อม outbox events กับ Notification Service — สร้าง `app_notifications` table + trigger `trg_procurement_outbox_notify` แปลง procurement outbox events เป็น in-app notifications สำหรับ Admin/Editor ใน profession; Flutter `NotificationRepository` + `NotificationProvider` + `NotificationListPage` + `TlzNotificationButton` แสดง badge และรายการแจ้งเตือน
    - **Migration:** `20260701160000_procurement_notification_integration.sql` — `app_notifications` table, RLS, trigger, RPCs (`mark_notification_read`, `mark_all_notifications_read`, `get_unread_notification_count`)
    - **Flutter:** `notification_repository.dart`, `notification_provider.dart`, `notification_list_page.dart`, updated `tlz_notification_button.dart` (ConsumerWidget + badge from provider)
    - **Route:** `/erp/notifications` ใน `main.dart`

**Priority 5 — Transaction Saga Observability ✅ Completed**
11. ✅ Implement `transaction_context` (Saga) สำหรับ GR completion — **แนวทาง: Observability-Only (ไม่ใช้ Compensation)**
    - **Migration:** `20260701140000_procurement_step_2_rpc_functions.sql` — เพิ่ม transaction context tracking ใน `create_goods_receipt` (10 steps: gr_created, gr_items_created, po_items_updated, inventory_lots_created, stock_movements_created, back_orders_processed, po_status_updated, outbox_events_emitted, idempotency_stored, audit_logs_recorded)
    - **Status flow:** `started` → `committed` (สำเร็จ) หรือ `failed` (error)
    - **Metadata:** เก็บ `po_id`, `received_by`, `branch_id`, `gr_id`, `gr_number`
    - **Test:** `test_procurement_step_2.sql` — ตรวจสอบ transaction context สำหรับ GR #1 และ GR #2 (status=committed, steps ≥ 8, total contexts ≥ 2)

#### สรุปการทำ Priority 5 — Transaction Saga Observability (Completed)

| ไฟล์ | การแก้ไข | สถานะ |
|---|---|---|
| `20260701140000_procurement_step_2_rpc_functions.sql` | แก้ `create_goods_receipt` เพิ่ม transaction context tracking 10 steps + `committed`/`failed` status | ✅ Applied |
| `test_procurement_step_2.sql` | เพิ่ม assertion ตรวจสอบ `transaction_contexts` สำหรับ GR #1, GR #2 และ total contexts | ✅ Passed |
| `PROCUREMENT_SYSTEM_PLAN.md` | อัปเดต Priority 5 เป็น completed | ✅ |

**Step ที่บันทึกใน `transaction_contexts.steps`:**
1. `gr_created`
2. `gr_items_created`
3. `po_items_updated`
4. `inventory_lots_created`
5. `stock_movements_created`
6. `back_orders_processed`
7. `po_status_updated`
8. `outbox_events_emitted`
9. `idempotency_stored`
10. `audit_logs_recorded`

**Metadata:** เก็บ `po_id`, `received_by`, `branch_id`, `gr_id`, `gr_number`

**Status flow:** `started` → `committed` (สำเร็จ) หรือ `failed` (error)

**ข้อจำกัด:**
- ❌ ไม่มี compensation functions
- ❌ ไม่เปลี่ยน idempotency logic
- ❌ ไม่แก้ Flutter หรือ RPC อื่น
- ❌ ไม่เปลี่ยน FK หรือ constraints

**ประโยชน์:**
- Debug GR multi-step transaction ย้อนหลังได้
- Foundation สำหรับ distributed transaction / compensation ในอนาคต

### ERP Phase 1 / Procurement Step 3: Auto-Reorder & Price History ✅ Implemented
- **Schema (✅):** `reorder_suggestions`, `supplier_price_history` ใน `20260701170000_procurement_step_3_tables.sql`
- **UI (✅):** `ReorderSuggestionPage` (confirm/convert to PR), `SupplierDetailPage` (price history tab), `ProcurementSettingsPage` (price history toggle)
- **Logic (✅):** Manual trigger `check_reorder_points` RPC ตรวจสอบ stock ต่ำ, ผู้ใช้ยืนยันก่อน convert เป็น PR
- **Feature (✅):** เปิด/ปิดโหมด Price History ได้ตามการตั้งค่า `procurement_settings.enable_price_history_tracking`
- **RPCs (✅):** `check_reorder_points`, `confirm_reorder_suggestion`, `reject_reorder_suggestion`, `convert_reorder_to_pr`, `record_supplier_price_history`, `get_supplier_price_history`, `get_latest_supplier_price`
- **Integration (✅):** `convert_pr_to_po` บันทึก price history เมื่อ mode B เปิด, outbox event `procurement.reorder_suggestion_created` → notification
- **Test (✅):** `test_procurement_step_3.sql` — E2E test reorder flow + price history mode B

### ERP Phase 3 / Procurement Step 4: Reporting & Advanced Integration ✅ Implemented

- **Schema (✅):** `supplier_invoices`, `supplier_invoice_items` ใน `20260702190000_procurement_step_4_matching.sql`
- **UI (✅):** `ProcurementDashboardPage` (KPI cards + monthly chart + top products), `ProcurementReportPage` (5 report types + date range filter + DataTable)
- **3-Way Matching (✅):** `create_supplier_invoice`, `match_supplier_invoice` (PO vs GR vs Invoice, tolerance ±1 qty / ±0.5% price), `update_invoice_matching_status`, `get_invoice_matching_summary`
- **Dashboard/Report (✅):** `get_procurement_dashboard_metrics` RPC (9 KPIs + monthly chart + top 10 products), `get_procurement_report` RPC (5 report types: po_summary, gr_summary, back_order_summary, price_variance, supplier_performance)
- **PO PDF/Email (✅):** `generate_po_pdf_url` (mock signed URL), `send_po_email` (outbox event for email consumer)
- **Full-Text Search (✅):** `search_procurement_documents` RPC (search PO, PR, GR, suppliers with ILIKE)
- **Notification (✅):** `supplier_invoice` aggregate type + events: `procurement.supplier_invoice_created`, `procurement.invoice_matched`, `procurement.invoice_mismatch`, `procurement.invoice_status_changed`
- **Test (✅):** `test_procurement_step_4.sql` — E2E test 3-way matching (match + mismatch) + dashboard + report + PDF + email + search + notifications

#### 4.1 3-Way Matching (PO vs GR vs Supplier Invoice)

**Schema ใหม่:** `20260702190000_procurement_step_4_matching.sql`

```sql
CREATE TABLE supplier_invoices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    supplier_id         UUID NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    po_id               UUID REFERENCES purchase_orders(id) ON DELETE SET NULL,
    invoice_number      TEXT NOT NULL,              -- เลขใบกำกับภาษีจาก supplier
    invoice_date        DATE NOT NULL,
    due_date            DATE,
    total_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    grand_total         DECIMAL(12,2) NOT NULL DEFAULT 0,
    status              TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','matched','partially_matched','disputed','paid')),
    matching_status     TEXT NOT NULL DEFAULT 'pending'
        CHECK (matching_status IN ('pending','matched','mismatch_quantity','mismatch_price','mismatch_tax','disputed')),
    notes               TEXT,
    created_by          UUID,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, invoice_number)
);

CREATE TABLE supplier_invoice_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_invoice_id UUID NOT NULL REFERENCES supplier_invoices(id) ON DELETE CASCADE,
    po_item_id          UUID REFERENCES purchase_order_items(id) ON DELETE SET NULL,
    product_id          UUID REFERENCES products(id) ON DELETE SET NULL,
    quantity_invoiced   INTEGER NOT NULL DEFAULT 0,
    unit_price          DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_price         DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
    matched_quantity    INTEGER NOT NULL DEFAULT 0,  -- จำนวนที่ match กับ GR แล้ว
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);
```

**RPCs:**
- `create_supplier_invoice(...)` — สร้างใบกำกับภาษีซื้อ + บันทึก `transaction_audit_log`
- `match_supplier_invoice(p_invoice_id)` — เปรียบเทียบ 3-way: PO คาดหวัง vs GR รับจริง vs Invoice จาก supplier
- `update_invoice_matching_status(p_invoice_id, p_status, p_reason)` — ยกเลิก/ dispute
- `get_invoice_matching_summary(p_po_id)` — ดูสถานะ matching ของ PO

**กฎ Matching:**
- ตรวจสอบ `quantity_invoiced` vs `quantity_received` (จาก GR) อนุโลม `±quantity_tolerance` (เช่น 1% หรือ 1 unit)
- ตรวจสอบ `unit_price` อนุโลม `±price_tolerance` (เช่น 0.5%)
- ตรวจสอบ `tax_amount` ตาม vat_rate (default 7%)
- ถ้าทุกอย่างตรง → `matching_status = 'matched'` + `status = 'matched'`
- ถ้าไม่ตรง → บันทึก `mismatch_*` พร้อมสร้าง notification ให้ admin/provider

**Integration กับ Accounting:**
- เมื่อ matched แล้ว สร้าง `journal_entry` ผ่าน RPC ที่มีอยู่ (หรือ RPC ใหม่) เพื่อบันทึก:
  - Dr สินค้าคงคลัง / Dr ค่าใช้จ่าย
  - Cr ภาษีซื้อ (input VAT)
  - Cr เจ้าหนี้การค้า (accounts payable)
- ใช้ `chart_of_accounts` account_type=2 (Liability) สำหรับ AP และ account_type=5 (Expense) สำหรับ COGS

#### 4.2 Procurement Dashboard & Reporting

**UI ใหม่:**
- `ProcurementDashboardPage` — แสดง metrics สรุป (KPI cards + charts)
- `ProcurementReportPage` — รายงานแบบตาราง + filter + export

**Metrics สำคัญ:**
- ยอดสั่งซื้อรายเดือน (PO total by month)
- จำนวน PR รออนุมัติ / รับของบางส่วน / ค้างส่ง (Back Order)
- ต้นทุนเฉลี่ยต่อสินค้า (จาก `supplier_price_history` หรือ `inventory_lots.unit_cost`)
- Supplier performance (lead time, on-time delivery %, price variance)
- 3-Way matching status summary
- Top 10 สินค้าที่สั่งซื้อบ่อย

**Technical Stack:**
- ใช้ `dashboard_snapshots` (Read Model) ที่มีอยู่แล้ว + `upsert_dashboard_snapshot` RPC
- ใช้ `fl_chart` สำหรับ charts (มีอยู่ใน `pubspec.yaml`)
- สร้าง RPC สรุปข้อมูล: `get_procurement_dashboard_metrics(p_profession_id, p_branch_id, p_start_date, p_end_date)`
- สร้าง RPC สำหรับรายงาน: `get_procurement_report(p_profession_id, p_report_type, p_filters)`

**Reports ที่ต้องมี:**
- `po_summary` — สรุป PO ตาม status, supplier, ช่วงวันที่
- `gr_summary` — สรุป Goods Receipt
- `back_order_summary` — รายการค้างส่ง
- `price_variance` — เปรียบเทียบราคาซื้อต่อสินค้า
- `supplier_performance` — สถิติ supplier

#### 4.3 PO PDF Generation & Email Sending

**Current state:** `send_purchase_order` RPC มีอยู่แล้ว แต่ปัจจุบันทำเพียงอัปเดต status + emit outbox event ยังไม่สร้าง PDF หรือส่ง email จริง

**Option A (แนะนำ):** Server-side PDF + external email service (resilient)
- สร้าง RPC `generate_po_pdf_url(p_po_id)` — ใช้ Supabase Storage + Edge Function สร้าง PDF แล้วคืน signed URL
- สร้าง RPC `send_po_email(p_po_id, p_email, p_message)` — บันทึก request ลง `outbox_events` หรือ `email_queue` แล้วส่งผ่าน external service (เช่น Supabase Edge Function / Resend / SendGrid)
- ข้อดี: ไม่ต้องเพิ่ม package ใน Flutter, ทำงาน offline-safe
- ข้อเสีย: ต้องมี Edge Function หรือ external service

**Option B:** Client-side PDF + share/mailto
- ใช้ `pdf` + `printing` package (หรือ `share_plus`) สร้าง PDF ใน Flutter แล้ว share หรือเปิด mailto ผ่าน `url_launcher` (มีอยู่แล้ว)
- ข้อดี: ไม่ต้องพึ่ง server, เร็วต้นทาง
- ข้อเสีย: ต้องเพิ่ม dependency, ไม่เหมาะกับ batch sending, ไม่มี audit trail บน server

**แนะนำเลือก Option A** สำหรับ production แต่ทำ Phase 1 เป็น mock/signed URL ก่อน (ไม่ต้องมี Edge Function จริง)

#### 4.4 Full-Text Search

**Option A (แนะนำ):** PostgreSQL native `tsvector`/`tsquery`
- เพิ่ม column `search_vector` ในตาราง `purchase_orders`, `purchase_requisitions`, `goods_receipts`, `suppliers`
- สร้าง GIN index `idx_po_search_vector`
- สร้าง RPC `search_procurement_documents(p_profession_id, p_query, p_entity_types)`
- รองรับภาษาไทยโดยใช้ `pg_trgm` (fuzzy) + `to_tsvector('thai', ...)` ถ้า extension พร้อม
- ข้อดี: ไม่ต้องเพิ่ม external service, รวดเร็ว, ทำงานใน SQL

**Option B:** Supabase full-text search ผ่าน PostgREST
- ใช้ `ilike` หรือ `textSearch` จาก Supabase client
- ข้อดี: ง่าย, ไม่ต้องสร้าง RPC
- ข้อเสีย: ไม่ flexible, ช้าเมื่อข้อมูลเยอะ

**แนะนำ Option A** สำหรับความยืดหยุ่นและประสิทธิภาพ

#### 4.5 งานย่อยและลำดับความสำคัญ (Step 4 Implementation Plan) — ✅ All Completed

> **หลักการจัดลำดับ:** Dependency-first → Core matching → Notification (ทำให้ testing สมบูรณ์) → Visible value (Dashboard/Report) → Nice-to-have (PDF/Search) → Test → Docs

1. ✅ **Migration 3-Way Matching (high)** — `20260702190000_procurement_step_4_matching.sql` สร้าง `supplier_invoices`, `supplier_invoice_items`, indexes, RLS, updated_at triggers, outbox constraint ใหม่ (`supplier_invoice`)
2. ✅ **3-Way Matching RPCs (high)** — `create_supplier_invoice`, `match_supplier_invoice`, `update_invoice_matching_status`, `get_invoice_matching_summary` ใน `20260702200000_procurement_step_4_rpc_functions.sql`
3. ✅ **Notification / Outbox (high)** — เพิ่ม `supplier_invoice` aggregate type ใน trigger + events: `procurement.supplier_invoice_created`, `procurement.invoice_matched`, `procurement.invoice_mismatch`, `procurement.invoice_status_changed`
4. ✅ **Procurement Dashboard (high)** — `ProcurementDashboardPage` + metrics RPC `get_procurement_dashboard_metrics` ใน `20260702210000_procurement_step_4_dashboard_report_rpc.sql`
5. ✅ **Procurement Report (high)** — `ProcurementReportPage` + `get_procurement_report` RPC + 5 report types (po_summary, gr_summary, back_order_summary, price_variance, supplier_performance)
6. ✅ **PO PDF / Email (medium)** — `generate_po_pdf_url` (mock signed URL), `send_po_email` (outbox event) ใน `20260702220000_procurement_step_4_pdf_email_search.sql`
7. ✅ **Full-Text Search (medium)** — `search_procurement_documents` RPC (ILIKE-based, search PO/PR/GR/suppliers)
8. ✅ **Test Script (high)** — `test_procurement_step_4.sql` ทดสอบ 3-way matching (match + mismatch) + notification + dashboard + report + PDF + email + search
9. ✅ **Documentation (medium)** — อัปเดต `PROCUREMENT_SYSTEM_PLAN.md` เป็น Implemented


### ERP Phase 4 / Procurement Step 5: HIS & Pharmacy Integration ⏳ Design Complete

> **Status:** ออกแบบรายละเอียดพร้อมแล้ว รอตัดสินใจ scope ก่อน implement

> **ข้อจำกัดที่พบ:** ระบบมี `medical_prescriptions`, `medications`, `inventory_lots`, `custom_medications`, `DrugRiskScreeningService` แล้ว แต่ยังไม่มี bridge ระหว่างห้องยา/คลินิกกับ Procurement (ขอซื้อยา → PR) และยังไม่มี FEFO allocation logic สำหรับ dispensing ยาควบคุมพิเศษ

#### 5.1 HIS/Pharmacy → Procurement Bridge (ห้องยาขอซื้อยา → PR อัตโนมัติ)

**Schema ใหม่:** `20260703100000_procurement_step_5_pharmacy_bridge.sql`

```sql
CREATE TABLE pharmacy_procurement_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    branch_id           UUID REFERENCES organization_branches(id) ON DELETE SET NULL,
    requester_id        UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,  -- พยาบาล/เภสัชกร
    request_number      TEXT NOT NULL,              -- PHARM-REQ-20260703-001
    request_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    status              TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected','converted_to_pr','partially_converted')),
    priority            TEXT NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low','normal','high','critical')),
    generated_pr_id     UUID REFERENCES purchase_requisitions(id) ON DELETE SET NULL,
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (profession_id, request_number)
);

CREATE TABLE pharmacy_procurement_request_items (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    pharmacy_procurement_request_id UUID NOT NULL REFERENCES pharmacy_procurement_requests(id) ON DELETE CASCADE,
    product_id              UUID REFERENCES products(id) ON DELETE SET NULL,          -- สินค้า ERP
    custom_medication_id    UUID REFERENCES custom_medications(id) ON DELETE SET NULL,  -- ยาที่ไม่มีใน master
    medication_id           UUID REFERENCES medications(id) ON DELETE SET NULL,      -- ยาจาก master catalog (optional)
    item_name               TEXT NOT NULL,
    quantity_requested      INTEGER NOT NULL CHECK (quantity_requested > 0),
    quantity_approved       INTEGER NOT NULL DEFAULT 0,
    quantity_converted_to_pr INTEGER NOT NULL DEFAULT 0,
    estimated_unit_price    DECIMAL(12,2),
    urgency_reason          TEXT,                   -- เช่น ยาควบคุมพิเศษใกล้หมด, ผู้ป่วยรอใช้
    suggested_supplier_id   UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status                  TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected','converted_to_pr')),
    created_at              TIMESTAMPTZ DEFAULT NOW()
);
```

**RPCs ใหม่:**
- `create_pharmacy_procurement_request(p_profession_id, p_branch_id, p_requester_id, p_items JSONB, p_priority, p_notes)` — ห้องยาสร้าง request
- `approve_pharmacy_procurement_request(p_request_id, p_approver_id, p_item_approvals JSONB)` — หัวหน้าเภสัช/ผู้จัดการอนุมัติจำนวน
- `convert_pharmacy_request_to_pr(p_request_id, p_created_by)` — แปลง request ที่ approved เป็น PR ในระบบ procurement
- `get_pharmacy_procurement_requests(p_profession_id, p_status, p_limit)` — ดูรายการขอซื้อยา

**Flow:**
1. พยาบาล/เภสัชกรเห็นยาใกล้หมด หรือผู้ป่วยต้องใช้ยาพิเศษ → สร้าง `pharmacy_procurement_request` (status: `pending`)
2. หัวหน้าเภสัชอนุมัติจำนวน (status: `approved`)
3. ระบบ auto-generate PR ผ่าน `convert_pharmacy_request_to_pr` (status: `converted_to_pr`, บันทึก `generated_pr_id`)
4. PR เดินตาม flow ปกติ: PR → PO → GR → 3-Way Matching

#### 5.2 FEFO / Lot / Expiry Integration (เบิกจ่ายยา)

**สิ่งที่มีอยู่:** `inventory_lots` (quantity_received, quantity_remaining, expiry_date, status), `stock_movements`

**สิ่งที่ต้องเพิ่ม:**

**RPC ใหม่:** `allocate_inventory_for_dispensing(p_profession_id, p_product_id, p_branch_id, p_quantity_needed, p_strategy)`

```sql
-- Strategy: 'fefo' (default), 'fifo', 'lot_specific'
-- Returns JSONB: { allocations: [{ lot_id, lot_number, expiry_date, quantity_allocated, unit_cost }], total_allocated, shortfall }
```

**Logic:**
1. หา lots ที่ `status = 'active'` และ `quantity_remaining > 0` ของ product นั้น
2. เรียงตาม `expiry_date ASC` (FEFO) หรือ `created_at ASC` (FIFO)
3. Allocate จาก lot แรกจนกว่าจะครบ quantity_needed
4. ถ้าไม่พอ → return `shortfall` ให้ห้องยาทราบว่าต้องขอซื้อเพิ่ม
5. บันทึก `inventory_reservations` (status: active) ก่อนจ่ายจริง
6. เมื่อจ่ายจริง อัปเดต `quantity_remaining`, สร้าง `stock_movements` (movement_type: 'sale'), อัปเดต `reservations` → fulfilled

**RPC ใหม่:** `dispense_medication_from_lots(p_prescription_item_id, p_allocations JSONB, p_dispensed_by)`
- ใช้ร่วมกับ `medical_prescription_items`
- บันทึกว่าจ่ายจาก lot ไหน จำนวนเท่าไร
- อัปเดต `is_dispensed`, `dispensed_at`, `dispensed_lot_id` ใน `medical_prescription_items`

#### 5.3 ยาควบคุมพิเศษ (Controlled Drug Procurement)

**Schema ใหม่:** `20260703110000_procurement_step_5_controlled_drugs.sql`

```sql
CREATE TABLE controlled_drug_procurement_tracking (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id       UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    supplier_id         UUID NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
    po_id               UUID REFERENCES purchase_orders(id) ON DELETE SET NULL,
    invoice_id          UUID REFERENCES supplier_invoices(id) ON DELETE SET NULL,
    drug_fda_status     TEXT NOT NULL CHECK (drug_fda_status IN ('S','N','P')),
    drug_name           TEXT NOT NULL,
    quantity_ordered    INTEGER NOT NULL,
    quantity_received   INTEGER NOT NULL DEFAULT 0,
    quantity_dispensed  INTEGER NOT NULL DEFAULT 0,
    supplier_license_no TEXT,                     -- ใบอนุญาตขายยาควบคุมของผู้จำหน่าย
    license_expiry_date DATE,
    license_verified    BOOLEAN DEFAULT false,
    po_approved_by      UUID REFERENCES users(id) ON DELETE SET NULL,
    po_approved_at      TIMESTAMPTZ,
    notes               TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE controlled_drug_movements (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
    tracking_id             UUID NOT NULL REFERENCES controlled_drug_procurement_tracking(id) ON DELETE CASCADE,
    lot_id                  UUID REFERENCES inventory_lots(id) ON DELETE SET NULL,
    movement_type           TEXT NOT NULL
        CHECK (movement_type IN ('received','dispensed','returned','expired','adjusted')),
    quantity                INTEGER NOT NULL,
    reference_type          TEXT,                   -- prescription, po, gr, adjustment
    reference_id            UUID,
    performed_by            UUID REFERENCES users(id) ON DELETE SET NULL,
    performed_at            TIMESTAMPTZ DEFAULT NOW(),
    notes                   TEXT
);
```

**กฎหมายไทยที่ต้องรองรับ:**
- `S` (ยาควบคุมพิเศษ): ต้องบันทึกการสั่งจ่ายและการจ่าย
- `N` (ยาเสพติดให้โทษ): บัญชีสม. จำกัดจำนวน ใบสั่งยาพิเศษ
- `P` (วัตถุออกฤทธิ์ต่อจิตและประสาท): ต้องบันทึกรับ-จ่ายเข้มงวด

**Validation ตอนจัดซื้อ:**
- ตรวจสอบ `supplier_license_no` ของผู้จำหน่ายว่ายังไม่หมดอายุ
- บันทึก `license_verified` ก่อนสร้าง PO
- สร้าง `controlled_drug_procurement_tracking` ทุกครั้งที่ PO มียาควบคุม
- ไม่ต้อง integrate กับ `DrugRiskScreeningService` โดยตรง (ตัวนั้นใช้ตอนสั่งจ่าย) แต่ใช้ข้อมูล `fda_risk_status` จาก `medications` ตอนสร้าง request

#### 5.4 UI ที่ต้องสร้าง

- **`PharmacyProcurementRequestPage`** — ห้องยาสร้าง request, เลือกยา, ระบุจำนวน, ความเร่งด่วน
- **`PharmacyProcurementApprovalPage`** — หัวหน้าเภสัชอนุมัติจำนวน
- **`LotAllocationDialog`** — แสดง lots ที่ allocate ได้ตาม FEFO ตอนจ่ายยา
- **`ControlledDrugTrackingPage`** — รายงานการรับ-จ่ายยาควบคุม (auditable)
- **แจ้งเตือน:** `procurement.pharmacy_request_created`, `procurement.pharmacy_request_approved`, `procurement.pharmacy_request_converted_to_pr`, `inventory.lot_shortfall`

#### 5.5 งานย่อยและลำดับความสำคัญ (Step 5 Implementation Plan)

> **หลักการจัดลำดับ:** Bridge schema → FEFO allocation → Controlled drug tracking → UI → Test → Docs

1. **Migration Pharmacy Bridge (high)** — `20260703100000_procurement_step_5_pharmacy_bridge.sql`: `pharmacy_procurement_requests`, `pharmacy_procurement_request_items`, indexes, RLS, triggers
2. **Pharmacy Bridge RPCs (high)** — `create_pharmacy_procurement_request`, `approve_pharmacy_procurement_request`, `convert_pharmacy_request_to_pr`, `get_pharmacy_procurement_requests`
3. **FEFO Allocation RPC (high)** — `allocate_inventory_for_dispensing` + `dispense_medication_from_lots` ใน `20260703120000_procurement_step_5_fefo_allocation.sql`
4. **Controlled Drug Migration (high)** — `20260703110000_procurement_step_5_controlled_drugs.sql`: `controlled_drug_procurement_tracking`, `controlled_drug_movements`
5. **Controlled Drug Validation (high)** — RPC ตรวจสอบ `supplier_license_no`, สร้าง tracking record ตอน PO มียาควบคุม
6. **Notification / Outbox (medium)** — เพิ่ม aggregate types: `pharmacy_procurement_request`, `controlled_drug` + events
7. **Flutter UI (medium)** — `PharmacyProcurementRequestPage`, `PharmacyProcurementApprovalPage`, `LotAllocationDialog`, `ControlledDrugTrackingPage`
8. **Test Script (high)** — `test_procurement_step_5.sql`: test pharmacy request → PR → FEFO allocate → controlled drug tracking
9. **Documentation (medium)** — อัปเดต `PROCUREMENT_SYSTEM_PLAN.md` เป็น Implemented

#### 5.6 Dependencies จาก Step ก่อนหน้า

- ต้องมี Step 1-4 เสร็จสมบูรณ์ก่อน (มี PR, PO, GR, supplier_invoices, notification trigger)
- `medical_prescriptions`, `medications`, `custom_medications`, `inventory_lots` มีอยู่แล้วจาก ERP Phase 1/4
- `DrugRiskScreeningService` ใช้เป็น reference สำหรับ FDA status แต่ไม่ต้องแก้ไข
