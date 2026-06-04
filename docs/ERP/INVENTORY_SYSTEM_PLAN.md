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

### Phase 9: Inventory Core & Lot Management (Pre-HIS Phase)
- **วัตถุประสงค์:** สร้างระบบคลังสินค้าที่รองรับ Multi-branch และระบบ Lot/Expiry อย่างสมบูรณ์ เพื่อเตรียมพร้อมให้ระบบ HIS (Pharmacy) เรียกใช้งาน
- **Database Schema Updates:**
  - สร้าง `inventory_items` ที่ทำหน้าที่เป็นระดับ Lot ย่อย (Row-level FEFO)
  - สร้าง `stock_movements` (Transaction logs) เพื่อบันทึกประวัติ In/Out/Transfer/Adjust
- **Backend Logic (Supabase RPC):**
  - ฟังก์ชัน `deduct_inventory_fefo()` สำหรับรับรหัสยา แล้วไปไล่ตัดสต๊อกจาก `inventory_items` ล็อตที่ `expiry_date` ใกล้ที่สุดก่อน หากยอดไม่พอให้ข้ามไปตัดล็อตถัดไปจนครบจำนวน
  - Job แจ้งเตือนยาใกล้หมดอายุ (Expiry Alert) และยาถึงจุดสั่งซื้อ (`reorder_point`)
- **Flutter UI:**
  - `InventoryDashboardPage` แสดงภาพรวมสต็อก แจ้งเตือนยาหมดอายุ, Low Stock, และแจ้งเตือนรอบการตรวจนับ (Stocktake Alert)
  - `GoodsReceiptPage` ฟอร์มรับของเข้า บังคับกรอก Lot Number, Expiry Date และต้นทุน (Cost)
  - `StockAdjustmentPage` (ปรับปรุงยอดสต็อกหลังการตรวจนับ)
  - `StockTransferPage` (สร้างคำสั่งโอนย้ายสินค้าระหว่างสาขาหรือคลังย่อย)
  - `StockMovementTrackingPage` (หน้าประวัติและติดตามสถานะการโยกย้ายสินค้า เช่น ระหว่างทาง(In-Transit), รับเข้าแล้ว, ยกเลิก)
  - `StocktakeConfigPage` หน้าจอสำหรับผู้ให้บริการตั้งค่าความถี่ในการตรวจนับสต็อก
  - `LabelPrintingPage` (หน้าจัดการและสั่งพิมพ์ฉลากสินค้า/บาร์โค้ด ตั้งค่าเครื่องพิมพ์และรูปแบบฉลาก)

### Phase 10: HIS & Pharmacy Integration (Final Phase)
- **วัตถุประสงค์:** เชื่อมระบบคลังเข้ากับห้องยาของ HIS เต็มรูปแบบ
- **การทำงาน:** เมื่อห้องยาใน HIS สั่งจ่ายยา (Prescription Fulfilled) ระบบจะเรียก `deduct_inventory_fefo()` อัตโนมัติ เพื่อตัดสต๊อกยา และส่งข้อมูลต้นทุนไปยัง Accounting System ทันที
