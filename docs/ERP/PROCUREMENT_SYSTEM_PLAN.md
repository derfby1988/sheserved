# Procurement / Purchasing (ระบบจัดซื้อจัดจ้าง)

## ภาพรวม (Overview)

ระบบจัดซื้อจัดจ้างสำหรับ Sheserved ERP รองรับ workflow แบบ **PR → PO → Goods Receipt → Back Order** ภายใต้การควบคุมสิทธิ์ระดับองค์กร (`profession_id`) และสาขา (`branch_id`) ตาม [ERP_CORE_ARCHITECTURE.md](ERP_CORE_ARCHITECTURE.md)

ระบบนี้ถูกออกแบบให้:
- แยก **Purchase Requisition (PR)** กับ **Purchase Order (PO)** อย่างชัดเจน
- มี **ระบบอนุมัติตาม Role + วงเงิน**
- รองรับ **การรับของบางส่วน (Partial Receipt)** พร้อมติดตาม **Back Order**
- มี **ระบบแจ้งเตือน/รายงาน** ถึงผู้สั่ง ผู้อนุมัติ ผู้รับของ และ Supplier
- มี **Auto-Reorder** แต่ต้องมีผู้ยืนยัน (Confirmed) จึงมีผล
- รองรับ **2 โหมด Price History** (Snapshot ใน PO/PR = โหมด A เป็นค่าเริ่มต้น, ตาราง `supplier_price_history` = โหมด B เลือกใช้ได้)
- ไม่มี 3-Way Matching ใน Phase 1 (Phase 2 ค่อยเพิ่มใบวางบิล)

---

## ฟีเจอร์หลัก (Core Features)

1. **Supplier Management**
   - จัดการข้อมูลผู้จัดจำหน่าย (Vendors/Suppliers)
   - เก็บเงื่อนไขการชำระเงิน (Payment Terms), Tax ID, ที่อยู่
   - สถานะ Active/Inactive

2. **Purchase Requisition (PR)**
   - ใบขอซื้อจากแผนก/สาขา (เช่น ห้องยาขอซื้อยาเพิ่ม)
   - ระบุสินค้าจาก `inventory_items` หรือ `medications` หรือ `custom_medications`
   - ประมาณการราคา (`estimated_unit_price`)
   - สถานะ: `draft` → `pending_approval` → `approved` → `converted_to_po` / `rejected` / `cancelled`

3. **Purchase Order (PO)**
   - ใบสั่งซื้ออย่างเป็นทางการส่งให้ Supplier
   - สามารถสร้างจาก PR (รวมหลาย PR ได้) หรือสั่งตรงได้
   - สถานะ: `draft` → `pending_approval` → `approved` → `sent_to_supplier` → `partially_received` → `fully_received` / `cancelled` / `closed`

4. **Approval Workflow (Role + วงเงิน)**
   - Staff สร้าง PR/PO → Manager/Admin อนุมัติ
   - ถ้ายอด < `approval_amount_threshold` (ค่าเริ่มต้น 10,000 บาท) Staff สั่งได้เลย (ขึ้นกับสิทธิ์)
   - ถ้ายอด >= threshold ต้องผ่าน Manager/Admin
   - บันทึก `approved_by`, `approved_at`, `approval_notes`

5. **Goods Receipt (GR)**
   - รับของเข้าตาม PO ได้หลายครั้ง (Partial Receipt)
   - บันทึก Lot Number, Expiry Date, ต้นทุนจริงที่รับ (`unit_cost`)
   - ตรวจสอบจำนวน: `quantity_received` = `quantity_accepted` + `quantity_rejected`
   - อัปเดต `purchase_order_items.quantity_received`
   - เมื่อรับครบ → PO สถานะ `fully_received`

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

### ระดับสิทธิ์ 3 ขั้น (Per-Module Permission)
- **Admin/Manager:** อนุมัติ PR/PO, ตั้งค่า, ยกเลิกเอกสาร
- **Editor:** สร้าง/แก้ไข PR, PO, Goods Receipt, ยืนยัน Reorder Suggestion
- **Viewer:** ดูรายงาน ดูประวัติ ไม่สามารถแก้ไขได้

### State Transition Hardening
- ใช้ `CHECK` constraints บนสถานะ (status) ป้องกันการเปลี่ยนสถานะผิดลำดับที่ฐานข้อมูล
- `updated_at` trigger อัปเดตอัตโนมัติทุกตาราง

---

## ฐานข้อมูล (Database Schema)

> **คำเตือน:** ไม่มีนโยบาย RLS ใดๆ ที่ใช้ `auth.uid()` ในฐานข้อมูล PostgreSQL การเข้าถึงข้อมูลควบคุมที่ Application Layer (Repository Pattern + ServiceLocator) ตาม [auth_data_guidelines.md](../../.agent/workflows/auth_data_guidelines.md)

### 1. ตาราง Master & Config

```sql
-- ผู้จัดจำหน่าย
CREATE TABLE suppliers (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id    UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  contact_name     TEXT,
  phone            TEXT,
  email            TEXT,
  address          TEXT,
  tax_id           TEXT,
  payment_terms    INTEGER DEFAULT 30,
  is_active        BOOLEAN DEFAULT true,
  created_by       UUID,
  updated_by       UUID,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

-- ตั้งค่าระบบจัดซื้อต่อองค์กร
CREATE TABLE procurement_settings (
  id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id                   UUID NOT NULL UNIQUE REFERENCES professions(id) ON DELETE CASCADE,
  enable_price_history_tracking   BOOLEAN DEFAULT false,
  default_payment_terms           INTEGER DEFAULT 30,
  auto_reorder_threshold_multiplier DECIMAL(3,2) DEFAULT 1.0,
  approval_amount_threshold       DECIMAL(12,2) DEFAULT 10000,
  created_at                      TIMESTAMPTZ DEFAULT now(),
  updated_at                      TIMESTAMPTZ DEFAULT now()
);
```

### 2. ตาราง Purchase Requisition (PR)

```sql
CREATE TABLE purchase_requisitions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID REFERENCES organization_branches(id),
  pr_number         TEXT NOT NULL,
  requester_id      UUID NOT NULL,
  requester_notes   TEXT,
  status            TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending_approval','approved','rejected','converted_to_po','cancelled')),
  total_amount      DECIMAL(12,2) DEFAULT 0,
  approved_by       UUID,
  approved_at       TIMESTAMPTZ,
  approval_notes    TEXT,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, pr_number)
);

CREATE TABLE purchase_requisition_items (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id          UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  requisition_id         UUID NOT NULL REFERENCES purchase_requisitions(id) ON DELETE CASCADE,
  inventory_item_id      UUID REFERENCES inventory_items(id),
  medication_id          UUID REFERENCES medications(id),
  custom_medication_id   UUID REFERENCES custom_medications(id),
  item_name              TEXT NOT NULL,
  quantity_requested     INTEGER NOT NULL CHECK (quantity_requested > 0),
  estimated_unit_price   DECIMAL(12,2),
  estimated_total_price  DECIMAL(12,2),
  uom                    TEXT,
  notes                  TEXT,
  created_at             TIMESTAMPTZ DEFAULT now(),
  updated_at             TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT check_item_source CHECK (
    (inventory_item_id IS NOT NULL) OR
    (medication_id IS NOT NULL) OR
    (custom_medication_id IS NOT NULL)
  )
);
```

### 3. ตาราง Purchase Order (PO)

```sql
CREATE TABLE purchase_orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id             UUID REFERENCES organization_branches(id),
  delivery_branch_id    UUID REFERENCES organization_branches(id),
  po_number             TEXT NOT NULL,
  supplier_id           UUID NOT NULL REFERENCES suppliers(id),
  pr_id                 UUID REFERENCES purchase_requisitions(id),
  status                TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending_approval','approved','sent_to_supplier','partially_received','fully_received','cancelled','closed')),
  order_date            DATE NOT NULL DEFAULT CURRENT_DATE,
  expected_delivery_date DATE,
  subtotal              DECIMAL(12,2) DEFAULT 0,
  tax_amount            DECIMAL(12,2) DEFAULT 0,
  discount_amount       DECIMAL(12,2) DEFAULT 0,
  total_amount          DECIMAL(12,2) DEFAULT 0,
  approved_by           UUID,
  approved_at           TIMESTAMPTZ,
  approval_notes        TEXT,
  sent_to_supplier_at   TIMESTAMPTZ,
  notes                 TEXT,
  created_by            UUID,
  updated_by            UUID,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, po_number)
);

CREATE TABLE purchase_order_items (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id          UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  purchase_order_id      UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  inventory_item_id      UUID REFERENCES inventory_items(id),
  medication_id          UUID REFERENCES medications(id),
  custom_medication_id   UUID REFERENCES custom_medications(id),
  item_name              TEXT NOT NULL,
  quantity_ordered       INTEGER NOT NULL CHECK (quantity_ordered > 0),
  quantity_received      INTEGER NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
  unit_price             DECIMAL(12,2) NOT NULL,
  total_price            DECIMAL(12,2) NOT NULL,
  uom                    TEXT,
  notes                  TEXT,
  created_at             TIMESTAMPTZ DEFAULT now(),
  updated_at             TIMESTAMPTZ DEFAULT now()
);
```

### 4. ตาราง Goods Receipt & Back Order

```sql
CREATE TABLE goods_receipts (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id               UUID REFERENCES organization_branches(id),
  purchase_order_id       UUID NOT NULL REFERENCES purchase_orders(id),
  gr_number               TEXT NOT NULL,
  receipt_date            TIMESTAMPTZ DEFAULT now(),
  supplier_delivery_note  TEXT,
  received_by             UUID NOT NULL,
  status                  TEXT NOT NULL DEFAULT 'completed'
    CHECK (status IN ('pending','completed','rejected')),
  notes                   TEXT,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, gr_number)
);

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

-- ติดตั้ง Back Order (จำนวนที่ยังไม่ได้รับจาก PO)
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

```sql
-- แนะนำการสั่งซื้ออัตโนมัติ (ต้องมีผู้ยืนยัน จึงมีผล)
CREATE TABLE reorder_suggestions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id               UUID REFERENCES organization_branches(id),
  inventory_item_id       UUID NOT NULL REFERENCES inventory_items(id),
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

-- ประวัติราคาจาก Supplier (ใช้เมื่อโหมด B เปิด)
CREATE TABLE supplier_price_history (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id           UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  supplier_id             UUID NOT NULL REFERENCES suppliers(id),
  medication_id           UUID REFERENCES medications(id),
  custom_medication_id    UUID REFERENCES custom_medications(id),
  inventory_item_id       UUID REFERENCES inventory_items(id),
  unit_price              DECIMAL(12,2) NOT NULL,
  uom                     TEXT,
  effective_date          DATE NOT NULL DEFAULT CURRENT_DATE,
  notes                   TEXT,
  created_by              UUID,
  created_at              TIMESTAMPTZ DEFAULT now()
);
```

### 6. Indexes & Performance

```sql
-- Partial indexes: ลดต้นทุน query เอกสารที่ Active
CREATE INDEX idx_pr_active ON purchase_requisitions(profession_id, branch_id, status)
  WHERE status IN ('draft','pending_approval','approved');
CREATE INDEX idx_po_active ON purchase_orders(profession_id, branch_id, status)
  WHERE status IN ('draft','pending_approval','approved','sent_to_supplier','partially_received');
CREATE INDEX idx_gr_recent ON goods_receipts(profession_id, branch_id, receipt_date)
  WHERE receipt_date > now() - interval '90 days';
CREATE INDEX idx_back_order_open ON back_orders(profession_id, status)
  WHERE status IN ('open','partially_fulfilled');
CREATE INDEX idx_reorder_pending ON reorder_suggestions(profession_id, branch_id, status)
  WHERE status = 'pending';
CREATE INDEX idx_supplier_active ON suppliers(profession_id, is_active)
  WHERE is_active = true;

-- Indexes สำหรับ FK lookup
CREATE INDEX idx_pr_items_requisition ON purchase_requisition_items(requisition_id);
CREATE INDEX idx_po_items_order ON purchase_order_items(purchase_order_id);
CREATE INDEX idx_gr_items_receipt ON goods_receipt_items(goods_receipt_id);
CREATE INDEX idx_gr_items_po_item ON goods_receipt_items(purchase_order_item_id);
CREATE INDEX idx_back_order_po ON back_orders(purchase_order_id);
CREATE INDEX idx_back_order_supplier ON back_orders(supplier_id);
CREATE INDEX idx_price_history_lookup ON supplier_price_history(profession_id, supplier_id, inventory_item_id, effective_date);
```

### 7. Trigger อัปเดต updated_at

```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'suppliers','procurement_settings',
    'purchase_requisitions','purchase_requisition_items',
    'purchase_orders','purchase_order_items',
    'goods_receipts','goods_receipt_items',
    'back_orders','reorder_suggestions','supplier_price_history'
  ]
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();',
      tbl, tbl
    );
  END LOOP;
END $$;
```

---

## กระบวนการทำงานหลัก (Business Logic)

### 1. Approval Workflow

```
PR/PO Status Flow:
draft → pending_approval → approved → converted_to_po / sent_to_supplier
  ↓         ↓                ↓
cancelled  rejected       rejected
```

**Logic ที่ Application Layer (Flutter / API):**
- เมื่อ Staff กด "Submit for Approval":
  1. ตรวจสอบ `procurement_settings.approval_amount_threshold`
  2. ถ้า `total_amount` < threshold และผู้ใช้มีสิทธิ์ Editor ขึ้นไป → อนุมัติอัตโนมัติ (`status = 'approved'`, `approved_by = currentUser.id`)
  3. ถ้า `total_amount` >= threshold → `status = 'pending_approval'` รอ Manager/Admin กดอนุมัติ
- เมื่อ Manager กด "Reject": บันทึก `approval_notes` และ revert สถานะ
- **ไม่มี RLS ใน PostgreSQL** ตรวจสอบสิทธิ์ที่ Repository Layer โดยดู `employee_roles` ก่อน execute

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
- ราคา snapshot อยู่ใน `purchase_order_items.unit_price` และ `purchase_requisition_items.estimated_unit_price`
- Query ราคาเก่า: `SELECT unit_price FROM purchase_order_items WHERE inventory_item_id = ? ORDER BY created_at DESC`

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
│   (Master)      │    │     (Config)           │    │     (ERP Core)      │
└────────┬────────┘    └────────────────────────┘    └─────────────────────┘
         │ supplier_id                                          │
         │                                                      │ branch_id
         ▼                                                      ▼
┌─────────────────────┐    ┌─────────────────────────────┐
│   purchase_orders   │◄───┤   purchase_order_items      │
│   - pr_id (FK)      │    │   - inventory_item_id (FK)  │
│   - supplier_id(FK) │    │   - medication_id (FK)      │
│   - branch_id       │    │   - custom_medication_id(FK)│
│   - delivery_branch │    └─────────────────────────────┘
└──────────┬──────────┘
           │ po_id
           │
┌──────────▼──────────┐    ┌─────────────────────────────┐
│   goods_receipts    │◄───┤   goods_receipt_items       │
│   - purchase_order_id│    │   - purchase_order_item_id  │
│   - received_by      │    │   - quantity_accepted       │
│   - branch_id        │    │   - lot_number              │
└──────────────────────┘    │   - expiry_date             │
                            └─────────────────────────────┘

┌─────────────────────────┐    ┌─────────────────────────────┐
│ purchase_requisitions   │◄───┤ purchase_requisition_items  │
│   - requester_id        │    │   - inventory_item_id       │
│   - approved_by         │    │   - medication_id           │
│   - branch_id           │    │   - custom_medication_id    │
└─────────────────────────┘    └─────────────────────────────┘

┌─────────────────────────┐    ┌─────────────────────────────┐
│     back_orders         │    │  reorder_suggestions        │
│   - purchase_order_id   │    │  - inventory_item_id        │
│   - purchase_order_item_id│  │  - preferred_supplier_id    │
│   - supplier_id         │    │  - confirmed_by             │
│   - expected_delivery_date│  │  - converted_pr_id          │
└─────────────────────────┘    └─────────────────────────────┘

┌─────────────────────────┐
│ supplier_price_history  │
│   - supplier_id         │
│   - inventory_item_id   │
│   - unit_price          │
│   - effective_date      │
└─────────────────────────┘
```

**Key Relationships:**
- `purchase_orders.pr_id` → `purchase_requisitions` (0..1:1)
- `purchase_orders.supplier_id` → `suppliers` (N:1)
- `purchase_order_items.purchase_order_id` → `purchase_orders` (N:1)
- `goods_receipts.purchase_order_id` → `purchase_orders` (1:1)
- `goods_receipt_items.purchase_order_item_id` → `purchase_order_items` (N:1)
- `back_orders.purchase_order_id` → `purchase_orders` (N:1)
- `back_orders.purchase_order_item_id` → `purchase_order_items` (1:1)
- `reorder_suggestions.converted_pr_id` → `purchase_requisitions` (0..1:1)

---

## การเชื่อมโยงกับระบบอื่น (Integrations)

### Inventory System
- เมื่อ GR สถานะ `completed` → เพิ่ม stock ใน `inventory_items.quantity` ตาม `quantity_accepted`
- สร้าง `stock_movements` (type = 'goods_receipt') พร้อมอ้างอิง `goods_receipt_id`
- บันทึก `lot_number`, `expiry_date`, `unit_cost` ลง `inventory_items` หรือตาราง lot ย่อย (ตาม [INVENTORY_SYSTEM_PLAN.md](INVENTORY_SYSTEM_PLAN.md))

### Accounting System (Phase 1)
- เมื่อ GR `completed` → สร้างรายการ Accounts Payable (AP) อัตโนมัติ
- ส่ง event ผ่าน `outbox_events`:
  - `event_type = 'procurement.goods_receipted'`
  - payload ประกอบด้วย `profession_id`, `purchase_order_id`, `goods_receipt_id`, `total_cost`, `supplier_id`
- Accounting Module อ่าน event แล้วบันทึกลง GL/AP ตามผังบัญชี
- **ไม่มี 3-Way Matching ใน Phase 1** (ไม่ต้อง matching กับใบวางบิล)

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
po.tax_amount = po.subtotal * vat_rate (ค่าเริ่มต้น 0.07 หรือตาม settings)
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
     - delivery_branch_id = pr.branch_id (default)
     - status = 'draft'
     - subtotal/tax/total = calculated from items

  2. FOR EACH pr_item IN purchase_requisition_items:
     CREATE purchase_order_item:
       - purchase_order_id = new_po.id
       - inventory_item_id = pr_item.inventory_item_id
       - medication_id = pr_item.medication_id
       - custom_medication_id = pr_item.custom_medication_id
       - item_name = pr_item.item_name
       - quantity_ordered = pr_item.quantity_requested
       - unit_price = pr_item.estimated_unit_price (หรือ last_price จาก history)
       - total_price = quantity_ordered * unit_price

  3. UPDATE purchase_requisitions:
     - status = 'converted_to_po'
     - updated_at = now()

  4. INSERT outbox_event:
     - event_type = 'procurement.pr_converted_to_po'
     - payload = { pr_id, po_id, profession_id, total_amount }
```

**ข้อจำกัด:**
- PR ที่มี status ไม่ใช่ `approved` ไม่สามารถ convert เป็น PO ได้
- 1 PR → 1 PO (1:1) ใน Phase 1

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

  5. UPDATE inventory_items:
     - quantity += SUM(gr_item.quantity_accepted) per inventory_item
     - บันทึก lot_number, expiry_date, unit_cost

  6. INSERT stock_movements:
     - type = 'goods_receipt'
     - quantity = gr_item.quantity_accepted
     - reference_id = goods_receipt_id

  7. INSERT outbox_events:
     - event_type = 'procurement.goods_receipted'
     - event_type = 'inventory.stock_increased'
     - event_type = 'accounting.ap_created' (Phase 1)
```

### 5.4 State Transition Guard Matrix

**PO Status Transitions:**
| จากสถานะ | ไปยัง | เงื่อนไข | ผู้ทำได้ |
|---|---|---|---|
| `draft` | `pending_approval` | มีรายการสินค้าอย่างน้อย 1 รายการ | Editor/Manager |
| `draft` | `cancelled` | — | Editor/Manager |
| `pending_approval` | `approved` | total < threshold หรือ Manager อนุมัติ | Auto / Manager |
| `pending_approval` | `rejected` | — | Manager/Admin |
| `approved` | `sent_to_supplier` | — | Editor/Manager |
| `sent_to_supplier` | `partially_received` | GR บางส่วน | System/Receiver |
| `sent_to_supplier` | `fully_received` | GR ครบทุกรายการ | System/Receiver |
| `partially_received` | `fully_received` | GR ครบทุกรายการที่ยังค้าง | System/Receiver |
| `partially_received` | `closed` | ผู้ใช้ตัดสินใจไม่รับของที่เหลือ | Manager/Admin |
| `any` (ก่อน sent) | `cancelled` | ยังไม่ sent_to_supplier | Manager/Admin |

**PR Status Transitions:**
| จากสถานะ | ไปยัง | เงื่อนไข | ผู้ทำได้ |
|---|---|---|---|
| `draft` | `pending_approval` | — | Editor |
| `approved` | `converted_to_po` | มี PO ถูกสร้างจาก PR นี้ | Editor/Manager |
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

---

## หน้าจอ Flutter UI (Flutter Pages)

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
        "inventory_item_id": "inv-uuid-001",
        "medication_id": "med-uuid-001",
        "item_name": "Paracetamol 500mg",
        "quantity_accepted": 100,
        "quantity_rejected": 0,
        "unit_cost": 150.00,
        "lot_number": "LOT-2026-A001",
        "expiry_date": "2027-06-01"
      },
      {
        "inventory_item_id": "inv-uuid-002",
        "medication_id": "med-uuid-002",
        "item_name": "Amoxicillin 250mg",
        "quantity_accepted": 50,
        "quantity_rejected": 5,
        "unit_cost": 200.00,
        "lot_number": "LOT-2026-B002",
        "expiry_date": "2027-12-01"
      },
      {
        "inventory_item_id": "inv-uuid-003",
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
    "inventory_item_id": "inv-uuid-002",
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
  "aggregate_type": "inventory_item",
  "aggregate_id": "inv-uuid-001",
  "profession_id": "prof-uuid-123",
  "branch_id": "branch-uuid-001",
  "occurred_at": "2026-06-09T14:30:00Z",
  "payload": {
    "inventory_item_id": "inv-uuid-001",
    "item_name": "Paracetamol 500mg",
    "quantity_change": 100,
    "previous_quantity": 15,
    "new_quantity": 115,
    "source_type": "goods_receipt",
    "source_id": "gr-uuid-001",
    "unit_cost": 150.00,
    "lot_number": "LOT-2026-A001",
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
  → PR.status = 'converted_to_po'
  → Outbox: procurement.pr_converted_to_po

ผู้จัดการกด "อนุมัติ PO"
  → PO.status = 'approved'
  → Outbox: procurement.po_approved

เภสัชกรกด "Send to Supplier"
  → PO.status = 'sent_to_supplier'
  → sent_to_supplier_at = 2026-06-09 10:00:00
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

  → อัปเดต Inventory:
    Paracetamol: 15 → 215 (+200)
    Amoxicillin: 20 → 70 (+50)

  → Outbox:
    - procurement.goods_receipted
    - inventory.stock_increased (2 events)
    - procurement.back_order_created
    - accounting.ap_created (total_cost = 200*150 + 50*200 = 40,000)
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

  → อัปเดต Inventory:
    Amoxicillin: 70 → 120 (+50)

  → Outbox:
    - procurement.goods_receipted
    - inventory.stock_increased
    - procurement.back_order_fulfilled
    - accounting.ap_created (10,000)
```

**สรุปรายงานที่ผู้ใช้เห็น:**
| เอกสาร | รายการ | สั่ง/ขอ | รับแล้ว | ค้าง | สถานะ |
|---|---|---|---|---|---|
| PR-2026-0001 | Paracetamol 500mg | 200 | — | — | converted_to_po |
| PR-2026-0001 | Amoxicillin 250mg | 100 | — | — | converted_to_po |
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
| 1.8 | Convert PR ที่ approved แล้ว | PR.status = 'approved' | PO ถูกสร้าง, PR.status = 'converted_to_po' |

### Group 2: PO Lifecycle & Approval

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 2.1 | PO total calculation | subtotal=50,000, vat=7%, discount=0 | total = 53,500 |
| 2.2 | PO with discount | subtotal=50,000, discount=5,000 | subtotal=50,000, total=48,150 (vat หลังหักส่วนลด) |
| 2.3 | Submit PO ที่ total < threshold | total = 5,000 | PO.status = 'approved' (auto) |
| 2.4 | Cancel PO ที่ยังไม่ sent | PO.status = 'approved' | PO.status = 'cancelled' |
| 2.5 | Cancel PO ที่ sent แล้ว | PO.status = 'sent_to_supplier' | ข้อผิดพลาด: "ไม่สามารถยกเลิก PO ที่ส่งให้ Supplier แล้ว" |
| 2.6 | Send PO ให้ Supplier | PO.status = 'approved' | PO.status = 'sent_to_supplier', sent_to_supplier_at != null |

### Group 3: Goods Receipt & Back Order

| # | Test Case | Input | Expected Result |
|---|---|---|---|
| 3.1 | GR ครบทุกรายการ | PO: Paracetamol x 200, GR: accepted=200 | PO.status = 'fully_received', ไม่มี back_order |
| 3.2 | GR บางส่วน | PO: Amoxicillin x 100, GR: accepted=50 | PO.status = 'partially_received', back_order created qty=50 |
| 3.3 | GR มีของตีกลับ | accepted=45, rejected=5 | quantity_received = 50, quantity_accepted = 45 |
| 3.4 | GR ซ้ำ (idempotency) | same idempotency key กด 2 ครั้ง | ครั้งที่ 2: ข้อผิดพลาด "operation นี้ถูกประมวลผลแล้ว", stock ไม่เพิ่มซ้ำ |
| 3.5 | GR ครั้งที่ 2 ทำให้ครบ | back_order qty=50, GR#2 accepted=50 | PO.status = 'fully_received', back_order.status = 'fulfilled' |
| 3.6 | GR ที่ accepted + rejected != received | accepted=40, rejected=5, received=50 | CHECK constraint failed |
| 3.7 | Inventory updated after GR | Paracetamol qty=15, GR accepted=200 | Inventory qty = 215 |

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
  - ตรวจสอบ `employee_roles` ว่าผู้ใช้มีสิทธิ์ในโมดูล Procurement ระดับใด (Viewer/Editor/Manager)
  - กรองข้อมูลตาม `profession_id` และ `branch_id` ก่อน execute query
- `created_by`, `updated_by`, `approved_by`, `received_by`, `confirmed_by` เก็บ `UUID` ของผู้ใช้จาก Application Layer ไม่ใช่จาก `auth.uid()` ของ Supabase
- ทุก write operation ที่มีผลต่อ stock หรือเงิน ต้องผ่าน Reliability Core (idempotency check + outbox publish) ก่อน commit

---

## แผนการพัฒนา (Phased Implementation)

### Phase 1: Procurement Core (PR + PO + GR + Supplier)
- **Schema:** สร้างทุกตารางตามเอกสารฉบับนี้ (ยกเว้น `supplier_price_history` ถ้าไม่เปิดโหมด B)
- **UI:** `SupplierDirectoryPage`, `PrListPage`, `PrFormPage`, `PoListPage`, `PoFormPage`, `GoodsReceiptFormPage`
- **Logic:** Approval Workflow, Partial Receipt, Auto-Back Order, ส่ง outbox ไป Inventory
- **Integration:** รับของเสร็จ → อัปเดต stock ใน Inventory + ส่ง outbox ไป Accounting (AP auto-create)
- **ไม่ทำ:** 3-Way Matching, Supplier Invoice matching

### Phase 2: Auto-Reorder & Price History
- **Schema:** เพิ่ม `reorder_suggestions`, `supplier_price_history`, `procurement_settings`
- **UI:** `ReorderSuggestionPage`, `ProcurementSettingsPage`, `SupplierDetailPage` (แสดงกราฟราคา)
- **Logic:** Background job ตรวจสอบ stock ต่ำ, ผู้ใช้ยืนยันก่อน convert เป็น PR
- **Feature:** เปิด/ปิดโหมด B ได้ตามการตั้งค่า

### Phase 3: Reporting & Advanced Integration
- **UI:** `ProcurementDashboardPage`, `ProcurementReportPage`, `BackOrderListPage` พร้อมกราฟ
- **Integration:** เพิ่ม 3-Way Matching (PO vs GR vs Supplier Invoice) เมื่อ Accounting Module รองรับ `supplier_invoices`
- **Feature:** ส่ง PO PDF ให้ Supplier ผ่าน email, รองรับการค้นหาย้อนหลังแบบ full-text

### Phase 4: HIS & Pharmacy Integration
- เชื่อม PR กับการสั่งยาใน HIS (ห้องยาขอซื้อยา → สร้าง PR อัตโนมัติ)
- เชื่อม Goods Receipt กับ FEFO/Lot/Expiry ของ Inventory System อย่างสมบูรณ์
- รองรับการสั่งซื้อยาควบคุมพิเศษ (ตามกฎหมายไทย) พร้อม audit trail
