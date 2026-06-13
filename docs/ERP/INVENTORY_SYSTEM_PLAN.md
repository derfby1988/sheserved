# Inventory / Stock (ระบบจัดการคลังสินค้า)

## ภาพรวม (Overview)
ระบบคลังสินค้าสำหรับจัดการยาทั่วไป, ยาควบคุม, อุปกรณ์การแพทย์, และสินค้าขายปลีกภายในคลินิก/ศูนย์บริการ

## สิทธิ์การใช้งานและการเข้าถึงข้อมูล (Access Control & Tenant Isolation)
- **Tenant-based Inventory:** ข้อมูลคลังสินค้าและสต๊อกทั้งหมดจะถูกแยกตามองค์กร (`profession_id`) อย่างเด็ดขาด
- **Role-based Access:** ผู้ที่มีสิทธิ์บริหารจัดการคลังสินค้าขององค์กรนั้นๆ ได้แก่:
  1. แอดมินส่วนกลางของแพลตฟอร์ม Sheserved
  2. พนักงานขององค์กรนั้นๆ ที่ได้รับการแต่งตั้งและมอบสิทธิ์ผ่านระบบ [HR System](HR_SYSTEM_PLAN.md) (เช่น เภสัชกร, ผู้จัดการคลินิก)

## การเชื่อมโยงสินค้ากับฐานข้อมูลยากลาง (Product → Master Medication Linking)

> **หลักการสำคัญ:** องค์กรจะไม่สร้างข้อมูลยาซ้ำด้วยตัวเอง แต่จะ **เลือกเชื่อมโยง** รายการสินค้าคลังของตนเองเข้ากับรายการยาที่มีอยู่แล้วในตาราง `medications` ซึ่งจัดการโดย Sheserved Admin ผ่านหน้า [PharmacyProductsPage](../../lib/features/pharmacy/presentation/pages/pharmacy_products_page.dart)

### ตาราง `medications` (Master Data — จัดการโดย Sheserved Admin)
ตารางนี้เป็น **ฐานข้อมูลยากลางของระบบ** ซึ่ง Sheserved Admin เป็นผู้ดูแล ประกอบด้วย:
- ข้อมูลยาจาก อย. (`source_type = 'FDA'`) — นำเข้าผ่านหน้า FDA Search
- ข้อมูลยาที่ไม่ได้ขึ้นทะเบียน (`source_type = 'UNREGISTERED'`)
- รหัส TMT มาตรฐาน (`vtm_code`, `gp_code`, `tp_code`)
- ข้อมูลทางคลินิก (`clinical_knowledge` — indications, dosage, contraindications ฯลฯ)
- หมวดหมู่สินค้า (`product_categories` ผ่าน `medication_category_mappings`)

### ตาราง `custom_medications` (Tenant Data — จัดการโดยแต่ละองค์กร)
ตารางนี้สำหรับ **สินค้าหรือยาเฉพาะของคลินิก** ที่ไม่อยู่ในฐานข้อมูลกลาง:
- ข้อมูลสินค้าถูกแยกตามองค์กรอย่างเด็ดขาด (`profession_id`)
- องค์กรสามารถกำหนดชื่อยา, หมวดหมู่, ราคาขาย, และต้นทุนได้เอง
- **Tenant Isolation:** พนักงานของคลินิก A จะไม่มีทางมองเห็นยา custom ของคลินิก B

### โครงสร้างการเชื่อมโยง (Linking Schema)

```
medications (Master)     custom_medications (Tenant)
         ↑                        ↑
         └───────┐        ┌───────┘
inventory_items (Tenant — ของแต่ละองค์กร)
  - profession_id          → แยกข้อมูลตาม Tenant
  - medication_id          → FK (ยาจาก Master DB - เป็น NULL ได้ถ้าเป็น custom)
  - custom_medication_id   → FK (ยาจาก Tenant DB - เป็น NULL ได้ถ้าเป็น master)
  - quantity               → จำนวนคงเหลือในคลังขององค์กรนี้
  - cost_price             → ราคาทุนที่องค์กรซื้อมา (ต่างกันได้ต่าง Tenant)
  - selling_price          → ราคาขายที่องค์กรกำหนดเอง
  - is_vatable             → สินค้านี้คิด VAT ไหม (สำหรับออกรายงานภาษี)
  - lot_number             → หมายเลขล็อต
  - expiry_date            → วันหมดอายุ
  - reorder_point          → จุดสั่งซื้อเพิ่ม (แจ้งเตือนเมื่อสต๊อกต่ำ)
```

```sql
-- 1. ตารางเก็บสินค้านอกฐานข้อมูลกลางของแต่ละองค์กร
CREATE TABLE custom_medications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id UUID NOT NULL REFERENCES professions(id),
  name          TEXT NOT NULL,
  description   TEXT,
  category_id   UUID REFERENCES product_categories(id),
  price         DECIMAL(12,2) DEFAULT 0,
  cost_price    DECIMAL(12,2) DEFAULT 0,
  image_url     TEXT,
  is_active     BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, name)
);

-- 2. ตารางสต๊อกสินค้าที่รองรับทั้งยา Master และยา Custom
CREATE TABLE inventory_items (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id        UUID NOT NULL REFERENCES professions(id),
  medication_id        UUID REFERENCES medications(id),
  custom_medication_id UUID REFERENCES custom_medications(id),
  quantity             INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  cost_price           DECIMAL(12,2),
  selling_price        DECIMAL(12,2),
  is_vatable           BOOLEAN DEFAULT false,
  lot_number           TEXT,
  expiry_date          DATE,
  reorder_point        INTEGER DEFAULT 0,
  created_at           TIMESTAMPTZ DEFAULT now(),
  updated_at           TIMESTAMPTZ DEFAULT now(),
  
  -- บังคับว่าต้องมี medication_id หรือ custom_medication_id อย่างใดอย่างหนึ่งเท่านั้น
  CONSTRAINT check_item_source CHECK (
    (medication_id IS NOT NULL AND custom_medication_id IS NULL) OR
    (medication_id IS NULL AND custom_medication_id IS NOT NULL)
  )
);

-- 3. ตารางการตั้งค่ารอบตรวจนับสต็อก (Stocktake Configurations)
CREATE TABLE stocktake_configurations (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id        UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  -- branch_id            UUID REFERENCES organization_branches(id), -- ถ้าแยกตรวจนับตามสาขา
  frequency_type       TEXT NOT NULL, -- 'WEEKLY', 'MONTHLY', 'YEARLY', 'CUSTOM'
  custom_interval_days INTEGER,       -- จำนวนวันกรณีความถี่แบบกำหนดเอง (CUSTOM)
  next_stocktake_date  DATE NOT NULL, -- วันที่ต้องตรวจนับรอบถัดไป
  is_active            BOOLEAN DEFAULT true,
  created_at           TIMESTAMPTZ DEFAULT now(),
  updated_at           TIMESTAMPTZ DEFAULT now()
);
```

### ขั้นตอนสำหรับองค์กร (User Flow)
1. องค์กรเข้าสู่หน้า **Inventory Management** ใน ERP Dashboard
2. กด **"เพิ่มสินค้าเข้าคลัง"** → ค้นหายาจากตาราง `medications` (ใช้ชื่อ, TMT code, รหัส อย.)
3. เลือกรายการยาที่ต้องการ → ระบบดึงชื่อ, ประเภท, ข้อมูลคลินิกมาให้อัตโนมัติ
4. องค์กรกรอกข้อมูลที่เป็นของตัวเอง: ราคาทุน, ราคาขาย, จำนวน, ล็อต, วันหมดอายุ
5. ระบบ **Smart Recommendation** แนะนำผังบัญชีที่เหมาะสม (จาก Accounting module)

## ฟีเจอร์หลักเบื้องต้น (Core Features)
- **Stock Management:** ดูยอดคงเหลือของสินค้าแต่ละรายการแบบ Real-time
- **Lot & Expiry Tracking (FEFO):** จัดการสินค้ายาและเวชภัณฑ์ด้วยระบบเข้าก่อน-ออกก่อนตามวันหมดอายุ (First Expire, First Out) โดยบังคับให้ระบุ Lot Number และ Expiry Date เสมอ และเวลาตัดสต๊อกจะตัดจาก Lot ที่ใกล้หมดอายุก่อนอัตโนมัติ
- **Stock Movements & Transfer Tracking:** บันทึกประวัติการเข้า-ออกของสินค้า (Goods In / Goods Out / Adjustments) และระบบติดตามสถานะการโยกย้ายสินค้าระหว่างสาขา/คลังย่อย/Shelf (เช่น Pending, In-Transit, Completed, Rejected)
- **Stocktake / Cycle Counting (ระบบตรวจนับสต็อก):** องค์กร/ผู้ให้บริการสามารถตั้งค่าความถี่ในการตรวจนับสต็อกได้เอง เช่น รายสัปดาห์, รายเดือน, รายปี หรือแบบกำหนดรอบเอง (Custom) โดยระบบจะช่วยแจ้งเตือนเมื่อถึงรอบการนับสต็อก เพื่อให้ยอดตรงกับความจริงเสมอ
- **Product Label Printing (ระบบพิมพ์ฉลากสินค้าและบาร์โค้ด):** รองรับการพิมพ์ฉลากสินค้า, บาร์โค้ด, และฉลากยา โดยเชื่อมต่อกับเครื่องพิมพ์สติ๊กเกอร์/ความร้อน (Thermal Printers) ที่นิยมใช้ในประเทศไทยได้อย่างครอบคลุม (เช่น เครื่องพิมพ์ที่รองรับคำสั่ง ESC/POS, TSPL, ZPL, CPCL) ผ่านการเชื่อมต่อ USB, Bluetooth, LAN หรือ Wi-Fi 
- **Multiple Locations (คลังย่อย):** รองรับการแยกคลังย่อยประจำสาขา (`branch_id`) เช่น คลังหน้าร้าน, คลังห้องยา, คลังเก็บหลัก

## การเชื่อมโยงกับระบบอื่น (Integrations)
- **[POS System](../plans/implementation_plan.md):** เมื่อมีการทำรายการขาย (Order = Paid) ระบบ POS จะส่งสัญญาณมาให้ตัดสต๊อกสินค้าที่เกี่ยวข้องโดยอัตโนมัติ
- **[Procurement System](PROCUREMENT_SYSTEM_PLAN.md):** เมื่อมีการรับของจากใบสั่งซื้อ (PO Receipt) สต๊อกในระบบจะเพิ่มขึ้นอัตโนมัติพร้อมอ้างอิงต้นทุน
- **[Pharmacy Master DB](../../lib/features/pharmacy/presentation/pages/pharmacy_products_page.dart):** ใช้ตาราง `medications` เป็น Master Data อ้างอิงชื่อยา, รหัส อย., และข้อมูลทางคลินิก

## แผนการพัฒนา (Phased Implementation)
*ระบบ Inventory ถูกจัดวางไว้ใน Phase ท้ายๆ เนื่องจากมีความซับซ้อนสูง และต้องรอให้ระบบพื้นฐาน (POS, Accounting, HR) นิ่งก่อน โดยเฉพาะฟีเจอร์ยาและ Lot/Expiry*

> **สถานะอัปเดตล่าสุด:** ส่วนใหญ่ของ Phase 9 ได้ถูกนำไป implement ล่วงหน้าเพื่อรองรับ POS/Checkout ที่ต้องตัดสต๊อกจริง ทำให้หลายฟีเจอร์ข้ามมาอยู่ใน Phase 2–3 แทน
>
> **อัปเดตครั้งใหญ่ (2026-06-13):** แก้ไข blocker `stock_movements.product_id NOT NULL` + `inventory_lots.product_id NOT NULL` ที่ทำให้ custom medications ใช้งานไม่ได้ เพิ่มหน้า Phase 9 ที่เหลือทั้งหมดที่ไม่มี dependency กับงานอื่น

### Phase 9: Inventory Core & Lot Management (Pre-HIS Phase)
- **วัตถุประสงค์:** สร้างระบบคลังสินค้าที่รองรับ Multi-branch และระบบ Lot/Expiry อย่างสมบูรณ์ เพื่อเตรียมพร้อมให้ระบบ HIS (Pharmacy) เรียกใช้งาน

#### ✅ Database Schema & RLS (Complete — 2026-06-12)
- ✅ `custom_medications` — สินค้าเฉพาะองค์กร
- ✅ `inventory_items` — สต็อกระดับ Lot ย่อย (Row-level FEFO)
- ✅ `inventory_lots` — ประวัติ Lot รับเข้า
- ✅ `stocktake_configurations` / `stocktake_sessions` / `stocktake_lines` — ตรวจนับสต็อก
- ✅ `stock_adjustments` — ปรับสต็อก
- ✅ `inventory_transfers` / `inventory_transfer_lines` — โอนย้ายสินค้า
- ✅ `inventory_alerts` — แจ้งเตือนสต็อก
- ✅ `stock_movements` — Transaction logs (In/Out/Transfer/Adjust)
- ✅ RLS Policies เปิดใช้งานแล้ว (`USING (true)` — ต้องแก้ก่อน Production)

#### ✅ Backend Logic — Supabase RPC (Complete — 2026-06-13)
- ✅ `deduct_inventory_fefo()` — ตัดสต๊อกตาม FEFO (ใช้แล้วใน Checkout/Counter POS)
- ✅ `create_inventory_transfer()` — สร้างรายการโอนย้าย + reserve stock
- ✅ `complete_inventory_transfer()` — ยืนยันโอนย้ายปลายทาง + บันทึก stock_movement (transfer_in/transfer_out)
- ✅ `create_stock_adjustment()` — สร้างปรับสต็อก + อัปเดต quantity + บันทึก stock_movement
- ✅ `complete_stocktake_session()` — ปิดรอบตรวจนับ + สร้าง adjustment อัตโนมัติ
- ✅ `check_inventory_alerts()` — ตรวจสอบและสร้างแจ้งเตือน (low_stock, expiry_warning, expired)
- ✅ `create_inventory_reservation()` / `release_inventory_reservation()` — จอง/คืนสต๊อก (POS pre-deduct)
- ✅ `get_stock_movements_by_profession()` — query ประวัติสต็อกตาม profession (พร้อม pagination)
- ✅ `create_stocktake_configuration()` — สร้างตั้งค่ารอบตรวจนับ
- ✅ `update_stocktake_configuration()` — แก้ไขตั้งค่ารอบตรวจนับ
- ✅ `delete_stocktake_configuration()` — ลบ/ปิดการใช้งานตั้งค่า

#### ✅ Flutter UI — PhaseOneNotifier + Pages (Complete — 2026-06-13)
- ✅ `InventoryPage` — 6 tabs: สต็อก, แจ้งเตือน, ตรวจนับ, โอนย้าย, ปรับสต็อก, รับเข้า (พร้อม Pull-to-refresh)
- ✅ `InventoryDashboardPage` — ภาพรวมสต็อก (summary cards + แจ้งเตือนล่าสุด + quick actions)
- ✅ `StockTransferPage` — ฟอร์มสร้างรายการโอนย้าย (เลือกหลายสินค้า, จำนวน, หมายเหตุ, **เลือกสาขาต้นทาง/ปลายทาง**)
- ✅ `StockAdjustmentPage` — ฟอร์มปรับสต็อก (เลือกสินค้า, แสดงจำนวนปัจจุบัน, ประเภท, จำนวนหลังปรับ, เหตุผล)
- ✅ `StockMovementTrackingPage` — ประวัติการเคลื่อนไหวสต็อก (In/Out/Transfer/Adjust/Expiry แบบเต็มจอ)
- ✅ `StocktakeConfigPage` — ตั้งค่าความถี่ตรวจนับสต็อก (CRUD + เลือกสาขา + วันที่ตรวจนับถัดไป)
- ✅ `GoodsReceiptPage` — รับของเข้าคลังแบบเต็มจอ (เลือกสินค้า/ยาคัสตอม + Lot + จำนวน + ต้นทุน + วันหมดอายุ + **เลือกสาขา**)
- ✅ FAB ใน `InventoryPage` (tab โอนย้าย/ปรับสต็อก) + Dialog สร้าง Adjustment/Transfer inline
- ✅ ปุ่ม Action: ปิดรอบตรวจนับ + ยืนยันโอนย้าย ในแต่ละรายการ
- ✅ `PhaseOneNotifier` — เพิ่ม `loadStockMovements()`, `create/update/deleteStocktakeConfiguration()`, `recordStockReceipt()` รองรับ `customMedicationId`
- ✅ Routes: `/erp/inventory`, `/erp/inventory/dashboard`, `/erp/inventory/transfer`, `/erp/inventory/adjustment`, `/erp/inventory/movements`, `/erp/inventory/stocktake-config`, `/erp/inventory/receipt`
- ✅ Dashboard tiles: คลังสินค้า, ภาพรวมคลัง, โอนย้ายสินค้า, ปรับสต็อก, ประวัติสต็อก, ตั้งค่าตรวจนับ, รับของเข้า

#### 🆕 Schema Fixes (2026-06-13)
- ✅ Migration: `20260613110000_fix_stock_movements_for_custom_medications.sql`
  - `inventory_lots.product_id` → nullable + เพิ่ม `custom_medication_id` + `inventory_item_id` + `check_lot_source`
  - `stock_movements.product_id` → nullable + เพิ่ม `custom_medication_id` + `inventory_item_id` + `check_movement_source`
  - อัปเดต `deduct_inventory_fefo()`, `create_stock_adjustment()`, `complete_inventory_transfer()` ให้ insert ทุก FK
  - เพิ่ม RPC `get_stock_movements_by_profession()`, `create/update/delete_stocktake_configuration()`
  - เพิ่ม indexes สำหรับ custom_medication_id, inventory_item_id, profession_id

#### ⏳ ยังไม่เสร็จ / คงเหลือสำหรับ Phase 9
- ⏳ `LabelPrintingPage` — พิมพ์ฉลาก/บาร์โค้ด (รอ hardware integration / thermal printer libraries)
- ⏳ RLS Policies แบบ Production-ready (เปลี่ยนจาก `USING (true)` เป็น `profession_id = current_setting('app.profession_id')::UUID`)
- ⏳ `StockAdjustmentPage` — เพิ่ม `branch_id` dropdown (schema `stock_adjustments` ยังไม่มี `branch_id` — ต้องเพิ่ม migration)
- ⏳ `warehouse_locations` Flutter layer — ยังไม่มี model/repository/provider (schema มีแล้ว)
- ⏳ POS/Checkout integration กับ `deduct_inventory_fefo()` แบบเต็มรูปแบบ (รอ POS เสร็จ)

### Phase 10: HIS & Pharmacy Integration (Final Phase)
- **วัตถุประสงค์:** เชื่อมระบบคลังเข้ากับห้องยาของ HIS เต็มรูปแบบ
- **การทำงาน:** เมื่อห้องยาใน HIS สั่งจ่ายยา (Prescription Fulfilled) ระบบจะเรียก `deduct_inventory_fefo()` อัตโนมัติ เพื่อตัดสต๊อกยา และส่งข้อมูลต้นทุนไปยัง Accounting System ทันที
- **สถานะ:** ⏳ รอ Phase 4 Clinical/HIS เสร็จก่อน

---

## สรุปความพร้อมใช้งาน (Zero-Mock Testing)

ทุกฟีเจอร์ที่ขึ้นเครื่องหมาย ✅ ด้านบน สามารถทดสอบโดยไม่ต้องใช้ mock data ได้ทันที เพราะ:
1. Migration รันบน Supabase แล้ว:
   - `20260612150000_add_inventory_system.sql` (Schema + RPC หลัก)
   - `20260613110000_fix_stock_movements_for_custom_medications.sql` (Fix custom medication support + เพิ่ม RPC ใหม่)
2. RPC functions ทำงานจริง (`SECURITY DEFINER` + ตรวจสอบ stock จริง)
3. RLS เปิดอยู่ (แม้จะไม่ปลอดภัยสำหรับ production แต่ทดสอบผ่าน)
4. `CheckoutPage` / `CounterPosPage` ก็เรียก `deductStock` / `createInventoryReservation` จริงแล้ว
5. `PhaseOneNotifier` มี methods ครบทั้ง load + create + complete + CRUD stocktake config + stock movements
6. `websocket-server` มี `inventory-alert-checker.js` (scheduled job ทุก 24 ชม.) เรียก `check_inventory_alerts()` อัตโนมัติ
