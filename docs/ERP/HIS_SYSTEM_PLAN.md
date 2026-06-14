# Hospital Information System (HIS) & Clinic Management

## ภาพรวม (Overview)
ระบบ HIS (Hospital Information System) หรือระบบบริหารจัดการคลินิกเต็มรูปแบบ ถูกจัดวางไว้ใน **Phase สุดท้าย** ของการพัฒนา Sheserved ERP เพื่อเป็นส่วนเติมเต็มที่ทำให้คลินิกสามารถบริหารจัดการผู้ป่วยได้อย่างครบวงจร ตั้งแต่เดินเข้าคลินิก (OPD) จนถึงการบันทึกประวัติการรักษา (EMR)

ระบบนี้จะเชื่อมโยงกับฐานข้อมูลของ POS, Inventory, HR, และ CRM ที่ถูกพัฒนาไว้ก่อนหน้านี้ เพื่อลดการทำงานซ้ำซ้อน

## ฟีเจอร์หลัก (Core Features)

### 1. ระบบผู้ป่วยนอก (OPD - Outpatient Department)
- **Registration & Triage:** การลงทะเบียนผู้ป่วยใหม่/เก่า, ซักประวัติเบื้องต้น, วัดสัญญาณชีพ (Vitals: ความดัน, น้ำหนัก, ส่วนสูง)
- **Queue Management:** ระบบจัดการคิวรอพบแพทย์ เรียงลำดับตามเวลาจอง (ดึงจากระบบ CRM) หรือ Walk-in
- **Patient Dashboard:** หน้าจอสำหรับพยาบาล/เจ้าหน้าที่ เพื่อดูสถานะคนไข้ในคลินิกแบบ Real-time (รอตรวจ, กำลังตรวจ, รอรับยา, รอชำระเงิน)

### 2. ระบบเวชระเบียนอิเล็กทรอนิกส์ (EMR - Electronic Medical Record)
- **Dynamic Medical Records (Custom EMR Forms):** ระบบฟอร์มบันทึกประวัติการรักษาอัจฉริยะ ที่อนุญาตให้คลินิกหรือแพทย์สามารถ **ออกแบบและปรับแต่งฟิลด์ข้อมูลได้เอง (Form Builder)** ผู้ใช้งานสามารถเพิ่มฟิลด์ (เช่น Text, Checkbox, Dropdown, รูปภาพประกอบ), จัดเรียงตำแหน่ง (Drag & Drop Layout), และตั้งค่าฟอร์มเฉพาะทาง (เช่น ฟอร์มสำหรับทันตกรรม, ฟอร์มสำหรับคลินิกผิวหนัง) เพื่อให้สอดคล้องกับสไตล์การทำงานของแพทย์แต่ละท่าน
  - *Data Persistence:* การจัดเรียงตำแหน่งและโครงสร้างฟอร์ม (Schema) จะต้องถูกเก็บบันทึกลงในตารางฐานข้อมูลจริง (เช่น ตาราง `emr_form_templates`) ผูกกับแพทย์แต่ละท่านหรือแต่ละแผนก
  - *Auto-Load:* เมื่อแพทย์เข้ามาเปิดฟอร์มตรวจรักษาในครั้งถัดไป ระบบจะต้องดึงโครงสร้างฟอร์มล่าสุดที่แพทย์เคยปรับแต่งไว้ (Last used template) ขึ้นมาแสดงเป็นค่าเริ่มต้น (Default) ทันที เพื่อความรวดเร็วในการทำงาน
- **Diagnosis (ICD-10):** รองรับการบันทึกรหัสโรคมาตรฐานสากล ICD-10 (International Classification of Diseases) ตามมาตรฐานกระทรวงสาธารณสุข
- **Procedures, Annotations & Photos:** บันทึกหัตถการที่ทำ (เช่น ฉีดโบท็อกซ์, ทำเลเซอร์) โดยเน้นการออกแบบระบบให้รองรับการทำงานผ่าน Tablet (iPad/Android) อย่างสมบูรณ์:
  - **Camera Integration:** สามารถกดถ่ายภาพคนไข้ (ภาพ Before/After หรือภาพบาดแผล) จากกล้องของอุปกรณ์ (Device Camera) และอัปโหลดเข้าสู่ประวัติเวชระเบียนของคนไข้รายนั้นได้ทันที
  - **Stylus / Pen Drawing:** รองรับการใช้ปากกาสไตลัส (เช่น Apple Pencil, S-Pen) เพื่อวาด เขียน หรือวงกลมระบุตำแหน่ง (Marking) ทับลงบนรูปภาพของคนไข้ หรือบนรูปภาพกราฟิกสรีระร่างกาย (Anatomy Diagrams) ที่เตรียมไว้ให้ โดยระบบจะจัดเก็บภาพที่ถูกวาดเขียนแล้วบันทึกเป็นหลักฐานการรักษาต่อไป
- **Prescription & Lab Orders:** การสั่งจ่ายยา (ส่งข้อมูลไปตัดสต๊อกใน Inventory) และการสั่งตรวจทางห้องปฏิบัติการ (Lab)
- **Consent Forms:** ระบบจัดเก็บลายเซ็นอิเล็กทรอนิกส์ (E-Signature) สำหรับเอกสารยินยอมการรักษา

### 3. ระบบจัดการห้องยา (Pharmacy)
- รับคำสั่งยา (Prescription) จากแพทย์
- ตรวจสอบประวัติการแพ้ยา (Allergy Check)
- พิมพ์ฉลากยา (Label Printing) พร้อมวิธีใช้
- ส่งข้อมูลการจ่ายยาไปยัง POS เพื่อรวมในบิลค่ารักษา

### 3.1 การรับใบสั่งยาจาก Telemedicine (Chat Consultation)

ระบบห้องยารองรับการรับคำสั่งยาจากการปรึกษาทางไกล (Telemedicine) ผ่านแชท โดยมี flow ดังนี้:

**Schema หลัก:** อ้างอิง `CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` สำหรับตาราง `prescriptions`, `prescription_templates`, `prescription_template_items`, `prescription_selection_history`

```
[แพทย์ใน PrescriptionEditorPage]
  → [สร้าง/แก้ไขรายการยา]
  → [กด "บันทึกชุดยาเป็น Template"]
      ├─ บันทึกลง prescription_templates + prescription_template_items
      └─ ผูกกับ profession_id ของแพทย์
  → [เลือก Template + กด "ส่งใบสั่งยา"]
      ├─ ระบบคัดกรอง Telemedicine Prescription (DrugRiskScreening)
      ├─ ดึง fda_risk_status จาก medications (Thai FDA อย.)
      ├─ ห้ามทันที: S (ยาควบคุมพิเศษ), N (ยาเสพติด), P (วัตถุออกฤทธิ์จิต)
      ├─ ตรวจสอบย่อยสำหรับ D (ยาอันตราย): hormone_injection, chemotherapy ห้าม
      ├─ custom_medications ต้องมี custom_risk_level กำหนดไว้
      ├─ unregistered ใช้ riskLevel จาก unregistered_details
      ├─ ตรวจสอบใบอนุญาต Telemedicine ของแพทย์
      └─ ถ้าไม่ผ่าน → บล็อค + แจ้งแพทย์ + บันทึก rejection reason
  → [ผู้ป่วยยินยอม Consent + Disclaimer]
      ├─ แสดงข้อความยินยอม + ข้อจำกัด Telemedicine
      ├─ แจ้งหมวดยาที่ได้รับ (เช่น "ยาสามัญประจำบ้าน")
      └─ บันทึก consent_given_at + consent_version + disclaimer_accepted
  → [สร้าง prescriptions (source_type = 'telemedicine')]
      ├─ บันทึก fda_risk_status แต่ละรายการยา (สำหรับ audit)
      ├─ ผูก template_id, template_name (ถ้ามี)
      ├─ ถ้ามี profession_id → ส่งเข้า HIS Pharmacy Queue ของคลินิกนั้น
      └─ ถ้าไม่มี profession_id → ส่งเข้า Sheserved Central Pharmacy
  → [ผู้ป่วยเลือกชุดยา — PrescriptionChoicePage]
      ├─ แสดงใบสั่งยา + ชุดยาที่แพทย์เสนอ
      ├─ ผู้ป่วยเลือกชุดยา → บันทึกลง prescription_selection_history
      └─ แสดงประวัติการเลือกย้อนหลัง
  → [ห้องยา รับคำสั่งยา]
      ├─ ตรวจสอบ Allergy + Inventory
      ├─ ตรวจสอบ fda_risk_status ซ้ำอีกครั้ง (defense in depth)
      ├─ อัปเดต pharmacy_status = 'verified' หรือ 'rejected'
      └─ ถ้า verified → พิมพ์สลากยา + แพ็คยา
  → [ส่งข้อมูลไป POS รวมในบิล]
      ├─ สร้าง order_items type = 'pharmacy_product'
      └─ รอผู้ป่วยชำระเงิน
  → [ตัดสต๊อก Inventory (FEFO)]
      └─ อัปเดต pharmacy_status = 'dispensed'
  → [ถ้า delivery_needed]
      └─ ส่งต่อ Delivery Core → pharmacy_status = 'delivered'
```

#### Schema — เพิ่มฟิลด์สำหรับ Telemedicine Prescription

```sql
-- ตาราง prescriptions อยู่ใน CHAT_CONSULTATION_IMPROVEMENT_PLAN.md
-- เพิ่มฟิลด์ดังนี้:
--   profession_id, branch_id, source_type, is_telemedicine_eligible,
--   consent_given_at, consent_version, disclaimer_accepted,
--   delivery_needed, his_prescription_id, pharmacy_status,
--   template_id, template_name  (เชื่อม prescription_templates)
-- ตาราง prescription_templates, prescription_template_items,
-- prescription_selection_history อยู่ใน CHAT_CONSULTATION_IMPROVEMENT_PLAN.md

-- เพิ่ม custom_risk_level ให้ custom_medications (สำหรับองค์กรกำหนดเอง)
ALTER TABLE custom_medications ADD COLUMN IF NOT EXISTS custom_risk_level TEXT
  CHECK (custom_risk_level IN ('low', 'medium', 'high', 'very_high', 'prohibited'));

-- เพิ่ม dangerous_sub_category ให้ medications (สำหรับยาอันตราย D)
ALTER TABLE medications ADD COLUMN IF NOT EXISTS dangerous_sub_category TEXT;
  -- 'hormone_injection', 'chemotherapy', 'abortifacient', 'antibiotic_injection', etc.

-- เพิ่ม fda_risk_status ใน prescription line items (สำหรับ audit trail)
ALTER TABLE prescriptions ADD COLUMN IF NOT EXISTS medication_risk_snapshot JSONB DEFAULT '[]';
  -- [{"medication_id":"...","fda_risk_status":"ND","name":"Paracetamol"}]

-- Bridge table: คำสั่งยาเข้าห้องยา
CREATE TABLE IF NOT EXISTS prescription_orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prescription_id       UUID NOT NULL REFERENCES prescriptions(id),
  profession_id       UUID REFERENCES professions(id),
  branch_id           UUID REFERENCES organization_branches(id),
  source_type         TEXT NOT NULL DEFAULT 'telemedicine'
                        CHECK (source_type IN ('telemedicine', 'opd', 'walk_in')),
  queue_number        TEXT,                             -- เลขคิวห้องยา
  pharmacy_status     TEXT DEFAULT 'pending'
                        CHECK (pharmacy_status IN ('pending', 'verified', 'dispensed', 'delivered', 'rejected')),
  assigned_pharmacist UUID REFERENCES users(id),        -- เภสัชกรที่รับงาน
  verified_at         TIMESTAMPTZ,
  dispensed_at        TIMESTAMPTZ,
  rejected_reason     TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Index สำหรับห้องยา query คิว
CREATE INDEX idx_prescription_orders_queue
  ON prescription_orders(profession_id, branch_id, pharmacy_status, created_at DESC);
```

#### การแจ้งเตือน (Notifications)

| เหตุการณ์ | ผู้รับ | ช่องทาง | ข้อความ |
|---|---|---|---|
| Prescription ส่งเข้าคิวห้องยา | เภสัชกร/พนักงานห้องยา | In-app + Push | "มีใบสั่งยาใหม่จาก Telemedicine — คิวที่ X" |
| **Screening ไม่ผ่าน** | แพทย์ (แชท) | In-app | "ใบสั่งยาถูกบล็อก: [ยา] อยู่ในหมวดห้ามสั่งผ่าน Telemedicine" |
| **Custom med ไม่มี risk level** | Admin องค์กร | In-app + Email | "ยา [ชื่อ] ยังไม่ได้กำหนดระดับความเสี่ยง — กรุณาอัปเดต" |
| Allergy Alert | เภสัชกร | In-app | "ผู้ป่วยมีประวัติแพ้ยา XXX — ตรวจสอบ" |
| ยาไม่พอสต๊อก | ผู้ป่วย (แชท) + แพทย์ | In-app + Push | "ยา XXX ไม่พอสต๊อก กรุณาเปลี่ยนยาหรือรอเติม" |
| พร้อมรับยา | ผู้ป่วย | SMS / Push | "ยาของคุณพร้อมแล้ว กรุณามารับที่คลินิก / รอจัดส่ง" |
| จัดส่งยาสำเร็จ | ผู้ป่วย | SMS / Push | "ยาจัดส่งถึงบ้านแล้ว" |

## การเชื่อมโยงกับระบบอื่น (Integrations)
- **CRM:** ดึงข้อมูลส่วนตัวของคนไข้และตารางนัดหมายล่วงหน้า
- **HR:** ผูกประวัติการตรวจรักษากับแพทย์ผู้ทำการรักษา (เพื่อนำไปคำนวณ Doctor Fee / ค่ามือ)
- **Inventory:** ตัดสต็อกยาทันทีเมื่อแพทย์สั่งจ่ายยา หรือเมื่อห้องยาทำการจ่ายยาเสร็จสิ้น
- **POS:** รวมค่าแพทย์ (DF), ค่าหัตถการ, และค่ายา เพื่อสร้างใบแจ้งหนี้ (Invoice) ออกบิล และรับชำระเงิน
- **Chat Consultation:** อ้างอิง `CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` สำหรับ flow Telemedicine Prescription, Templates, Patient Selection History
  - `prescriptions` — ใบสั่งยาที่เชื่อมกับ consultation
  - `prescription_templates` — ชุดยาที่แพทย์บันทึกไว้
  - `prescription_template_items` — รายการยาในชุดยา
  - `prescription_selection_history` — ประวัติการเลือกชุดยาของผู้ป่วย

## แผนการพัฒนา (Phased Implementation Placeholder)
*รายละเอียดการออกแบบ Database Schema และ UI ของระบบ HIS จะถูกเพิ่มเติมเมื่อเข้าใกล้ Phase สุดท้ายของการพัฒนา ERP โดยจะนำมาตรฐาน FHIR (Fast Healthcare Interoperability Resources) หรือ HL7 มาพิจารณาเพื่อการส่งต่อข้อมูลหากจำเป็นในอนาคต*

> **หมายเหตุ:** Prescription Templates + Patient Selection History ถูก implement แล้วใน Chat Consultation flow ตาม `CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` — HIS Pharmacy Queue รองรับรับคำสั่งยาที่ผู้ป่วยเลือกแล้วผ่าน `prescription_selection_history`*
