# Laboratory Information System (LIS) / ระบบจัดการห้องปฏิบัติการ

## ภาพรวม (Overview)
ระบบเชื่อมต่อและจัดการห้องปฏิบัติการ (External Lab Integration System) เป็นโมดูลหนึ่งภายใต้ Sheserved ERP ที่ออกแบบมาเพื่อเป็นตัวกลางระหว่าง คลินิก/ศูนย์บริการสุขภาพ กับ ห้องปฏิบัติการภายนอก (External Labs) โดยเน้นความยืดหยุ่นสูง เพื่อให้องค์กรสามารถกำหนดรูปแบบการเชื่อมต่อ การจัดเก็บสิ่งส่งตรวจ และระบบการเงินได้อย่างอิสระเป็นรายเคสหรือรายคู่ค้า

## สิทธิ์การใช้งานและการเข้าถึงข้อมูล (Access Control & Tenant Isolation)
- **Tenant-based Data:** ข้อมูลคู่ค้า (Lab Partners) คำสั่งตรวจ (Lab Orders) และผลตรวจ (Lab Results) จะถูกแยกระดับคลินิกอย่างเด็ดขาดด้วย `profession_id`
- **Patient Data Governance:** การส่งข้อมูลคนไข้ไปยังแล็บภายนอกจะทำภายใต้การปกปิดข้อมูลที่ไม่จำเป็น และต้องมีการบันทึกประวัติการส่งข้อมูลเสมอตามหลัก PDPA

## ความยืดหยุ่นของระบบ (System Flexibility)
ระบบถูกออกแบบมาเพื่อรองรับเงื่อนไข 3 ด้านหลัก ซึ่งคลินิกสามารถตกลงกับแล็บภายนอกได้อย่างอิสระ:

1. **รูปแบบการเชื่อมต่อ (Integration Mode)**
   - `API` / `HL7` / `FHIR`: เชื่อมต่อผ่าน API ของแล็บ ระบบจะส่งข้อมูลออเดอร์และรับผลตรวจกลับมาที่ EMR อัตโนมัติ
   - `MANUAL_PORTAL`: แล็บบันทึกผลผ่าน Portal ของระบบ หรือพนักงานคลินิกแนบไฟล์ผลตรวจ (PDF) เข้าระบบด้วยตนเอง

2. **การจัดเก็บสิ่งส่งตรวจ (Specimen Collection Mode)**
   - `CLINIC_COLLECTED`: คลินิกเป็นผู้เก็บตัวอย่าง (เลือด/ปัสสาวะ) และส่งมอบผ่าน Messenger/Logistics ให้กับแล็บ
   - `PATIENT_TRAVEL`: ผู้ป่วยถือใบส่งตรวจ (Lab Request Form) เดินทางไปรับบริการเจาะเลือด/ตรวจที่แล็บด้วยตนเอง

3. **รูปแบบการชำระเงิน (Billing Mode - ตั้งค่าเป็นรายเคสได้)**
   - `CLINIC_COLLECTS`: คลินิกเรียกเก็บเงินจากคนไข้ผ่าน POS ของ Sheserved และคลินิกไปชำระค่าบริการกับแล็บในภายหลัง
   - `LAB_COLLECTS`: คนไข้เดินทางไปตรวจและชำระเงินกับทางห้องปฏิบัติการโดยตรง (คลินิกไม่บันทึกรายได้ผ่าน POS)

## โครงสร้างฐานข้อมูล (Database Schema)

```sql
-- 1. ข้อมูลคู่ค้าห้องปฏิบัติการ (Lab Partners)
CREATE TABLE lab_partners (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  integration_mode  TEXT NOT NULL,  -- 'API', 'HL7', 'MANUAL_PORTAL'
  api_endpoint      TEXT,
  contact_info      TEXT,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE lab_partners ENABLE ROW LEVEL SECURITY;

-- 2. แคตตาล็อกรายการตรวจของแล็บ (Lab Test Catalogs)
CREATE TABLE lab_test_catalogs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_partner_id    UUID NOT NULL REFERENCES lab_partners(id) ON DELETE CASCADE,
  test_code         TEXT NOT NULL,
  test_name         TEXT NOT NULL,
  cost_price        DECIMAL(12,2) DEFAULT 0,
  selling_price     DECIMAL(12,2) DEFAULT 0,
  is_active         BOOLEAN DEFAULT true,
  UNIQUE (lab_partner_id, test_code)
);
ALTER TABLE lab_test_catalogs ENABLE ROW LEVEL SECURITY;

-- 3. ใบสั่งตรวจแล็บ (Lab Orders)
CREATE TABLE lab_orders (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id            UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  patient_user_id          UUID NOT NULL REFERENCES users(id),
  lab_partner_id           UUID NOT NULL REFERENCES lab_partners(id),
  emr_record_id            UUID, -- FK ไปยังตารางเวชระเบียน (ถ้ามี)
  
  specimen_collection_mode TEXT NOT NULL, -- 'CLINIC_COLLECTED', 'PATIENT_TRAVEL'
  billing_mode             TEXT NOT NULL, -- 'CLINIC_COLLECTS', 'LAB_COLLECTS'
  
  status                   TEXT NOT NULL DEFAULT 'PENDING', 
                           -- 'DRAFT', 'PENDING', 'ACCEPTED', 'REJECTED', 'IN_PROGRESS', 'RESULT_READY', 'COMPLETED'
  rejection_reason         TEXT, -- บังคับกรอกถ้า status = 'REJECTED'
  
  created_by               UUID NOT NULL REFERENCES users(id), -- แพทย์/พนักงานผู้สั่ง
  created_at               TIMESTAMPTZ DEFAULT now(),
  updated_at               TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE lab_orders ENABLE ROW LEVEL SECURITY;

-- 4. รายการตรวจย่อยในออเดอร์ (Lab Order Items)
CREATE TABLE lab_order_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id      UUID NOT NULL REFERENCES lab_orders(id) ON DELETE CASCADE,
  catalog_id        UUID NOT NULL REFERENCES lab_test_catalogs(id),
  price             DECIMAL(12,2) NOT NULL,
  UNIQUE (lab_order_id, catalog_id)
);
ALTER TABLE lab_order_items ENABLE ROW LEVEL SECURITY;

-- 5. ผลการตรวจแล็บ (Lab Results)
CREATE TABLE lab_results (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id      UUID NOT NULL REFERENCES lab_orders(id) ON DELETE CASCADE,
  result_data       JSONB,           -- โครงสร้างข้อมูลผลตรวจแบบโครงสร้าง (กรณีเชื่อมต่อ API)
  result_file_url   TEXT,            -- ลิงก์ไฟล์ PDF สแกน (กรณีเชื่อมต่อ Manual)
  approved_by       TEXT,            -- ชื่อนักเทคนิคการแพทย์ผู้รับรองผล
  reported_at       TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE lab_results ENABLE ROW LEVEL SECURITY;
```

## กระบวนการทำงาน (End-to-End Workflow)

1. **การตั้งค่าคู่ค้า (Partner Onboarding):** แอดมิน/ผู้จัดการของคลินิก เพิ่มรายการแล็บพันธมิตรลงใน `lab_partners` พร้อมกำหนดรูปแบบการเชื่อมต่อ
2. **แพทย์สั่งตรวจ (Ordering):** 
   - แพทย์เลือกรายการ Lab จากหน้า HIS/EMR ของผู้ป่วย 
   - ระบบบังคับให้เลือกว่าใครเป็นคนเก็บเงิน (`CLINIC_COLLECTS` / `LAB_COLLECTS`) และใครเป็นคนเก็บสิ่งส่งตรวจ (`CLINIC_COLLECTED` / `PATIENT_TRAVEL`)
3. **การชำระเงิน (Billing Check):**
   - หากตั้งค่าเป็น `CLINIC_COLLECTS` ระบบจะส่งข้อมูลยอดชำระไปพักไว้ที่ **POS System** เมื่อคนไข้ชำระเงินสำเร็จ สถานะออเดอร์ถึงจะพร้อมดำเนินการ
   - หากเป็น `LAB_COLLECTS` ระบบจะข้ามไปขั้นตอนการส่งออเดอร์ทันที
4. **การตอบรับของแล็บ (Lab Acknowledgment):** 
   - แล็บผ่าน API หรือระบบ Portal ภายนอกจะสามารถกด "ยอมรับ (Accept)" หรือ **"ปฏิเสธ (Reject)"** ได้
   - หากกดปฏิเสธ **ระบบบังคับ**ให้แล็บหรือพนักงานต้องกรอกเหตุผล (`rejection_reason`) กลับเข้ามาในระบบทุกครั้ง
5. **การรับผลและรายงานผล (Result Integration):**
   - เมื่อตรวจเสร็จสิ้น ผลตรวจจะวิ่งกลับมาในตาราง `lab_results` โดยอัตโนมัติ (กรณี API) หรือพนักงานนำ PDF มาอัปโหลด
   - แจ้งเตือนไปยังหน้า Dashboard ของแพทย์ว่ามีผลตรวจพร้อมให้อ่าน (`RESULT_READY`) และเชื่อมโยงผลไปบันทึกไว้ในเวชระเบียน (EMR) โดยตรง

## การเชื่อมโยงกับระบบอื่นใน ERP
- **POS System:** รับคำสั่งตรวจมาเรียกเก็บเงินคนไข้
- **Accounting System:** รับรู้ต้นทุนค่าตรวจแล็บกรณีคลินิกเก็บเงินคนไข้ เพื่อใช้เป็นยอดค้างจ่าย (Accounts Payable) ให้กับห้องปฏิบัติการ
- **HIS / EMR:** ผูกคำสั่งตรวจและผลตรวจเข้ากับเวชระเบียนผู้ป่วยแบบไร้รอยต่อ
- **Logistics System:** สร้างรอบจัดส่งให้ Messenger หากใช้ระบบ `CLINIC_COLLECTED`
