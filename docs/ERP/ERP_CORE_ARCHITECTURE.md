# Sheserved ERP - Core Architecture

## ภาพรวม (Overview)

> **หมายเหตุสำหรับองค์กรที่ได้รับสิทธิ์ขาย:** ทุกองค์กรที่มีค่า `uses_pos_system = true` จะได้รับ **ระบบ ERP ทั้งหมด** (POS, Inventory, Procurement, Accounting, HR, CRM) อย่างเต็มรูปแบบในฐานข้อมูลเดียวกัน โดยข้อมูลจะถูกแยกตาม `profession_id` เพื่อให้แต่ละองค์กรมีข้อมูลของตนเองแยกจากองค์กรอื่น.

## ภาพรวมระบบ (System Overview)
เอกสารนี้เป็นจุดศูนย์กลาง (Master File) ที่ใช้อธิบายโครงสร้างและสถาปัตยกรรมของ Sheserved ERP (Enterprise Resource Planning) สำหรับคลินิกและศูนย์บริการด้านสุขภาพ 
ระบบ ERP นี้เกิดจากการเชื่อมโยงระบบย่อย (Modules) ต่างๆ เข้าด้วยกันเพื่อให้ข้อมูลทำงานสอดคล้องกันแบบ Single Source of Truth

## สถาปัตยกรรมหลัก (Core Architecture Principle)
- **Multi-Tenant ERP Isolation:** ทุกองค์กร (Profession/Clinic) ที่ได้รับสิทธิ์ในการค้าขาย (เช่น มีสถานะ `uses_pos_system = true`) จะได้รับสิทธิ์ในการใช้งานระบบ ERP ที่จำเป็นทั้งหมดเป็น **"ของตนเอง"** โดยปริยาย ข้อมูลทุกตารางในระบบ ERP จะถูกออกแบบให้แยกขาดจากองค์กรอื่นอย่างเด็ดขาดด้วยการอ้างอิง `profession_id` (Tenant-based Data Isolation)
- **Multi-Branch Support:** ภายใต้ 1 องค์กร (`profession_id`) ระบบรองรับการขยายสาขา (Branches) โดยใช้แนวทาง "Branch as Location/Sub-tenant" ผ่านคอลัมน์ `branch_id` สาขาสามารถเลือกได้ว่าจะใช้ Tax ID รวมกับองค์กรแม่ หรือแยกนิติบุคคล/Tax ID ย่อยของตนเอง (กำหนดล่วงหน้าก่อนเริ่มขาย) พนักงานสามารถถูกกำหนดสิทธิ์แยกรายสาขาได้ หรือสามารถรับสิทธิ์ระดับส่วนกลาง (HQ) เพื่อดูรวมทุกสาขาก็ได้
- **Storage Mode & Failover Strategy (Local-First Hybrid):** ศูนย์บริการสามารถเลือกโครงสร้างฐานข้อมูลได้
  - **Supabase Cloud (บังคับใช้งานกับบางระบบ):** ใช้สำหรับ Auth (ดึงข้อมูลผู้ใช้ผ่าน `ServiceLocator` ตาม `auth_data_guidelines.md` เสมอ), ระบบ Chat/Telemedicine, และระบบคิวสำรองข้อมูล (Sync Queue)
  - **Self-host PostgreSQL (ค่าเริ่มต้นสำหรับ HIS/EMR):** ให้บริการฐานข้อมูล ERP และเวชระเบียนที่ฝั่งคลินิก (Local Server) เพื่อปกป้องข้อมูลผู้ป่วย (PDPA) อย่างไรก็ตาม คลินิกสามารถปรับเปลี่ยนให้เป็น Cloud-only หรือ Hybrid ได้ตามต้องการ
  - **Auto Failover & Sync:** หากเซิร์ฟเวอร์ Self-host ล่ม `DataBroker` ใน Flutter จะสลับไปเก็บข้อมูลชั่วคราวลง `erp_sync_queue` บน Supabase อัตโนมัติ และเมื่อระบบกลับมาออนไลน์ จะเริ่มซิงค์ข้อมูลลง Self-host เป็นอันดับแรก โดยใช้กฎ **Last-Write-Wins (หรือ Timestamp-Based Merge)** ในการแก้ไขความขัดแย้ง (Conflict Resolution)
- **Data Governance & Consent Management (ระบบขออนุญาตและตรวจสอบการเข้าถึงข้อมูล):** แม้ศูนย์บริการจะตั้งค่าเก็บข้อมูลไว้ที่ Self-host ทั้งหมด แต่ระบบต้องรองรับกลไกการดึงข้อมูล (Data Retrieval) อย่างโปร่งใสและถูกต้องตามกฎหมาย:
  - **การร้องขอและอนุมัติ (Request & Approval):** หากมีการร้องขอข้อมูลจากภายนอก (เช่น ส่วนกลาง, หรือการส่งต่อเคส) จะต้องผ่านกระบวนการยืนยันความยินยอม (Consent) จากเจ้าของข้อมูลหรือผู้มีอำนาจก่อนเสมอ
  - **ประวัติการเข้าถึง (Audit & Access Log):** ระบบจะต้องบันทึกประวัติทุกขั้นตอนอย่างละเอียด ได้แก่ ประวัติการร้องขอ, ประวัติการอนุมัติ, เวลาดำเนินการ, และ **ต้องบันทึกสำเนาข้อมูลที่ถูกส่งออกไป (Data Payload)** ไว้ทุกรายการ เพื่อให้สามารถตรวจสอบย้อนหลัง (Audit Trail) ได้ 100% (สอดคล้องกับ PDPA)

## การติดตั้ง Self-host ฝั่งคลินิก (การจำลองใน Phase พัฒนา)
เพื่อไม่ให้กระทบกับระบบและฐานข้อมูลหลักของ Sheserved การพัฒนาฟีเจอร์ Self-host จะถูกจำลองในสภาพแวดล้อมดังนี้:
1. **แยก Environment เด็ดขาด:** ติดตั้ง PostgreSQL Database และ Data API สำหรับฝั่งคลินิกลงบน **External Drive อีกลูกหนึ่ง** (ไม่ได้รันบน Drive หรือ Server ตัวเดียวกับระบบเดิม)
2. **การตั้งค่า (Cloud Configuration):** ในระบบส่วนกลาง (Supabase) จะเพิ่มฟิลด์ `storage_mode = 'hybrid'` และ `self_host_api_url` เข้าไปในตาราง `professions`
3. **Data Routing (Flutter App):** เมื่อผู้ใช้ Login ผ่าน Sheserved Auth สำเร็จ `DataBroker` จะเช็ค Config ว่าคลินิกนี้เป็น Hybrid หรือไม่ หากใช่ การเรียก API ของหมวด ERP จะถูกส่งพุ่งตรงไปยัง IP ของ External Drive แทน (โดยแนบ Auth Token ไปด้วยเพื่อความปลอดภัย)

## โมดูลต่างๆ และความสัมพันธ์ (Modules & Relationships)

1. **[POS System](POS System_plan.md)**
   - **หน้าที่:** จัดการการขายหน้าร้าน (Point of Sale), รับชำระเงิน, ออกใบเสร็จ
   - **การเชื่อมโยง:** ส่งข้อมูลการขายไปตัดสต๊อกใน *Inventory*, ส่งข้อมูลรายได้ไปที่ *Accounting*, ให้แต้มสะสมใน *CRM*, และมีช่องทาง **API (POS Injection)** เพื่อรับคำสั่งซื้อ (Sales Order) จากตะกร้าสินค้าส่วนกลาง (Global Platform Shopping Cart)

2. **[Inventory / Stock System](INVENTORY_SYSTEM_PLAN.md)**
   - **หน้าที่:** จัดการคลังสินค้า, นับสต๊อก, ล็อตสินค้า, วันหมดอายุ
   - **การเชื่อมโยง:** รับสินค้าเข้าจาก *Procurement*, ตัดสินค้าออกจากการขายใน *POS*

3. **[Procurement / Purchasing System](PROCUREMENT_SYSTEM_PLAN.md)**
   - **หน้าที่:** จัดซื้อจัดจ้าง, ขอซื้อ (PR), สั่งซื้อ (PO), จัดการข้อมูล Supplier
   - **การเชื่อมโยง:** เพิ่มสต๊อกเข้า *Inventory* เมื่อรับของ, ส่งบันทึกรายจ่ายไปที่ *Accounting* (Accounts Payable)

4. **[Accounting / Finance System](ACCOUNTING_SYSTEM_PLAN.md)**
   - **หน้าที่:** ระบบบัญชี, สมุดรายวัน, รับจ่าย (AR/AP), สรุปผลกำไรขาดทุน
   - **การเชื่อมโยง:** รับข้อมูลรายได้จาก *POS* และค่าใช้จ่ายจาก *Procurement* / *HR*

5. **[HR System](HR_SYSTEM_PLAN.md)**
   - **หน้าที่:** จัดการทรัพยากรบุคคล, กะการทำงาน, เงินเดือน, ค่าคอมมิชชั่น
   - **การเชื่อมโยง:** ดึงยอดขายจาก *POS* มาคำนวณค่าคอมมิชชั่นให้พนักงาน

6. **[CRM System](CRM_SYSTEM_PLAN.md)**
   - **หน้าที่:** บริหารความสัมพันธ์ลูกค้า, แต้มสะสม (Point), แพ็กเกจสมาชิก, และระบบจัดการเนื้อหา/เคสรีวิว (Phase ท้าย)
   - **การเชื่อมโยง:** นำแต้มมาใช้เป็นส่วนลดใน *POS*, เก็บประวัติการซื้อจาก *POS*, และเผยแพร่เคสรีวิวของคลินิกออกไปยังหน้าแอปฝั่งผู้ใช้ (`health_article_page.dart`) เพื่อให้ผู้ป่วยรีวิวและรับแต้มสะสม

7. **[HIS / Clinic Management System (Phase สุดท้าย)](HIS_SYSTEM_PLAN.md)**
   - **หน้าที่:** ระบบบริหารจัดการคลินิกและโรงพยาบาลแบบเต็มรูปแบบ รวมถึงแผนกผู้ป่วยนอก (OPD) และระบบเวชระเบียนอิเล็กทรอนิกส์ (Electronic Medical Record: EMR)
   - **การเชื่อมโยง:** ดึงประวัติคนไข้/การนัดหมายจาก *CRM*, ส่งคำสั่งจ่ายยาไปตัดสต๊อกที่ *Inventory* และคิดเงินที่ *POS*, เชื่อมต่อตารางแพทย์จาก *HR*
   - **ความสำคัญ:** เป็นมาตรฐานที่โรงพยาบาลและคลินิกในประเทศไทยนิยมใช้ เพื่อรองรับการเก็บประวัติการรักษา, การวินิจฉัยโรค (ICD-10), การสั่งหัตถการ, และการจัดการคิวรับบริการอย่างเป็นระบบ โดยจัดไว้ใน Phase สุดท้ายของการพัฒนา ERP

8. **[Telemedicine System (ระบบโทรเวชกรรม - Phase สุดท้าย)](../plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md)** (เชื่อมโยงร่วมกับ **[Video System](../plans/VIDEO_SYSTEM_PLAN.md)**)
   - **หน้าที่:** รองรับการปรึกษาแพทย์ทางไกลผ่านระบบแชท การโทรวิดีโอ (Tele-Consultation) และการส่งต่อการช่วยเหลือเหตุฉุกเฉิน (Emergency Alert Response)
   - **การเชื่อมโยง:**
     - **HIS/EMR:** ส่งต่อบันทึกผลการวินิจฉัยโรคและแผนการรักษาจาก `consultation_notes` (Medical Summary) เข้าเป็นส่วนหนึ่งของเวชระเบียนผู้ป่วย (EMR)
     - **POS System:** รับส่งข้อมูลใบสั่งยาอิเล็กทรอนิกส์ (`prescriptions`) จากการแชท/วิดีโอคอล เพื่อเข้ากระบวนการชำระเงินค่าปรึกษาและค่ายาอัตโนมัติ
     - **Inventory / Stock:** เมื่อ POS บันทึกการชำระเงินค่ายาเสร็จสิ้น จะตัดยอดสต๊อกยาตามล็อตวันหมดอายุ (FEFO/Lot/Expiry)
     - **HR System:** บันทึกเวลาปฏิบัติงานของแพทย์ (`consultation_sessions`) และบันทึกประวัติการช่วยเหลือเหตุฉุกเฉินของอาสาสมัคร (Volunteer Response) เพื่อใช้ประเมินค่าตอบแทนหรือผลงาน
     - **Accounting / Finance:** รับรู้รายได้จากการให้บริการปรึกษาทางไกลและการจำหน่ายยา

9. **CDP (Customer Data Platform) / การเชื่อมโยงข้อมูลลูกค้าแบบองค์รวม**
   - **หน้าที่:** ควบรวมข้อมูลลูกค้า (Identity Resolution) จากทุกแหล่งเข้าด้วยกันด้วย **Global ID** เพียงหนึ่งเดียว (Single Customer View / 360-degree View)
   - **การเชื่อมโยง:** ทำงานข้ามระบบทั้งหมดโดยเฉพาะร่วมกับ **CRM** (ใช้วิเคราะห์พฤติกรรม แบ่งกลุ่มเป้าหมาย และทำ Marketing Automation), **HIS** (ดึงประวัติการรักษา), และ **POS** (ดึงยอดสั่งซื้อ) เพื่อเป็นรากฐานในการส่งมอบการบริการลูกค้า (Customer Service) ที่แม่นยำและตรงจุดที่สุด

10. **[Logistics / Delivery Management](../plans/Delivery_PLAN.md)**
    - **หน้าที่:** ระบบจัดการการจัดส่งสินค้าและยา จัดการรอบรถ ไรเดอร์ และติดตามสถานะพัสดุ
    - **การเชื่อมโยง:** เป็นสะพานเชื่อมระหว่าง **POS** (รับออเดอร์/คิดค่าส่ง), **Inventory** (เบิกของ/แพ็ค/ตัดสต๊อก), และ **Accounting** (รับรู้รายได้ค่าขนส่ง)

## มาตรฐานบัญชีและการเงิน (Accounting & Financial Standards)
ระบบย่อยทั้งหมดใน Sheserved ERP จะถูกออกแบบและทำงานสอดคล้องกันภายใต้ **ผังบัญชีมาตรฐาน (Standard Chart of Accounts)** และ **บัญชีแยกประเภท (General Ledger)** ที่ใช้ในประเทศไทย โดยอ้างอิงจากตัวบทกฎหมายและข้อกำหนดของ **กรมสรรพากร (Revenue Department)** เป็นหลัก เพื่อให้เอกสารทางการเงิน (เช่น ใบกำกับภาษี, ใบเสร็จรับเงิน, หัก ณ ที่จ่าย) และรายงานทางบัญชีสามารถนำไปใช้ยื่นภาษีและตรวจสอบทางกฎหมายได้อย่างถูกต้อง

## ERP Dashboard (แดชบอร์ดจัดการองค์กร)

ทุกองค์กรที่ผ่านการยืนยันจาก Admin Sheserved (ตามขั้นตอนการลงทะเบียนในหมวดหมู่ที่ Sheserved กำหนด) จะได้รับหน้าจอ **ERP Dashboard** เป็นของตนเอง ซึ่งประกอบด้วย:

### 1. หน้าตั้งค่าเบื้องต้น (Organization Settings)
- ข้อมูลองค์กร (ชื่อ, ที่อยู่, เลขที่ผู้เสียภาษี, โลโก้)
- ข้อมูลการติดต่อและช่องทางการชำระเงิน
- การตั้งค่าภาษา, สกุลเงิน, และเขตเวลา

### 2. หน้าจัดการแยกรายโมดูล (Module Management Pages)
แต่ละโมดูลใน ERP จะมีหน้าจัดการของตัวเองภายใน Dashboard ขององค์กร ได้แก่:
- 🛒 **POS Management** — จัดการสินค้า, ราคา, โปรโมชั่น
- 📦 **Inventory Management** — จัดการคลังสินค้า, สต๊อก
- 🛍️ **Procurement Management** — จัดการการสั่งซื้อ, Supplier
- 📊 **Accounting Management** — ดูรายงานบัญชี, ผังบัญชี
- 👥 **HR Management** — จัดการพนักงาน, กะงาน, เงินเดือน
- 🎁 **CRM Management** — จัดการลูกค้า, แต้มสะสม, แพ็กเกจ
- 🏥 **HIS / EMR Management** — จัดการเวชระเบียน, ตรวจรักษา, สั่งยา (Phase สุดท้าย)
- 📞 **Telemedicine Management** — ติดตามการปรึกษาทางแชท/วิดีโอคอล, ใบสั่งยาออนไลน์, และสถิติการแจ้งเหตุฉุกเฉิน (Phase สุดท้าย)
- 🚚 **Logistics Management** — จัดการรอบรถ, ไรเดอร์, และติดตามพิกัดการจัดส่ง

### 3. จุดเข้าสู่ระบบจากหน้าหลัก (Home Page Entry Point)
เพื่อรักษาโครงสร้าง UI (Layout) ของแอปพลิเคชันไม่ให้ผิดเพี้ยนไปจากเดิม และแยกประสบการณ์ใช้งานระหว่างผู้ใช้งานทั่วไปกับพนักงานองค์กรอย่างชัดเจน:
- **กลไกการแสดงผล (Dynamic Card Replacement):** ระบบจะตรวจสอบสถานะผู้ใช้งานที่ล็อกอินว่ามีสิทธิ์อยู่ในตาราง `employee_roles` หรือไม่
- **ผู้ใช้ทั่วไป (Consumer):** หน้าจอ Home จะแสดง `HomePharmacyCard` (สำหรับค้นหาและสั่งซื้อยา) ตามปกติ
- **พนักงาน/เจ้าขององค์กร (Staff/Owner):** ระบบจะ **ซ่อน** `HomePharmacyCard` และนำการ์ด **`HomeErpCard` (การจัดการองค์กร / ERP Dashboard)** มาวางแทนที่ในตำแหน่งเดียวกัน เพื่อเป็นจุดศูนย์กลางในการเข้าถึงระบบจัดการ ERP ของสาขาที่ตนเองได้รับสิทธิ์ โดยที่ความสูงและการจัดวางในหน้าจอ Home จะยังคงเหมือนเดิมทุกประการ

### 4. ระบบสิทธิ์การใช้งาน (Permission System)

#### หลักการ
- **ชื่อตำแหน่งกำหนดเอง:** แต่ละองค์กรสามารถสร้างและตั้งชื่อตำแหน่ง (Role) ได้เองอย่างอิสระ เช่น "หัวหน้าแผนก", "แคชเชียร์", "เภสัชกร" เป็นต้น
- **สิทธิ์แบบรายโมดูล (Per-Module Permissions):** แต่ละตำแหน่งสามารถกำหนดสิทธิ์แยกกันในแต่ละโมดูล ERP ได้อิสระ เช่น ตำแหน่ง "แคชเชียร์" มีสิทธิ์เต็มที่ใน POS แต่เป็นแค่ Viewer ใน Accounting
- **3 ระดับสิทธิ์ต่อโมดูล (3 Permission Levels per Module):**
  | ระดับ | ความสามารถ |
  |-------|------------|
  | **ระดับ 1 (Full Access)** | เข้าถึงได้ทุกฟังก์ชัน, แก้ไข, ลบ, ออกรายงาน |
  | **ระดับ 2 (Edit Access)** | ใช้งานและแก้ไขข้อมูลได้ แต่ไม่สามารถลบหรือเข้าถึงการตั้งค่าขั้นสูง |
  | **ระดับ 3 (View Only)** | ดูข้อมูลและรายงานได้เท่านั้น ไม่สามารถแก้ไขข้อมูลใดๆ |

#### การจัดการสิทธิ์
- **หน้าจัดการสิทธิ์** (`Permission Management Page`): แต่ละองค์กรมีหน้าจัดการสิทธิ์เป็นของตนเองภายใน Dashboard
- **ผู้มีสิทธิ์จัดการ:** ผู้ถือสิทธิ์สูงสุดขององค์กร (Owner/ผ่านการยืนยัน Sheserved) สามารถมอบสิทธิ์ให้พนักงานในทุกระดับ รวมถึงระดับเดียวกับตนเองได้
- **การ Scope ข้อมูล:** สิทธิ์ทั้งหมดถูก Scope ภายใน `profession_id` ขององค์กรนั้นๆ เท่านั้น และลงลึกระดับสาขาด้วย `branch_id` (หากระบุ `branch_id = NULL` หมายถึงสิทธิ์ระดับ HQ ที่ดูแลทุกสาขา)

```sql
-- ตารางเก็บข้อมูลสาขาของแต่ละองค์กร (Multi-Branch Support)
CREATE TABLE organization_branches (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id),
  branch_code     TEXT NOT NULL,                            -- เช่น 'HQ', 'B01', 'B02'
  branch_name     TEXT NOT NULL,
  is_headquarter  BOOLEAN DEFAULT false,
  tax_id          TEXT,                                     -- ถ้าเว้นว่าง จะใช้ tax_id ของ professions แทน
  branch_tax_code TEXT,                                     -- รหัสสาขาสำหรับออกใบกำกับภาษี เช่น '00000', '00001'
  address         TEXT,
  phone           TEXT,
  is_active       BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(profession_id, branch_code)
);

-- ตาราง DB สำหรับระบบสิทธิ์
CREATE TABLE organization_roles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id), -- Tenant isolation
  role_name       TEXT NOT NULL,                            -- ชื่อตำแหน่งที่กำหนดเอง เช่น "แคชเชียร์"
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE role_module_permissions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id         UUID NOT NULL REFERENCES organization_roles(id),
  module_name     TEXT NOT NULL CHECK (module_name IN ('pos', 'inventory', 'procurement', 'accounting', 'hr', 'crm', 'his', 'telemedicine', 'logistics')),
  access_level    INTEGER NOT NULL CHECK (access_level IN (1, 2, 3)), -- 1=Full, 2=Edit, 3=View
  UNIQUE (role_id, module_name)
);

CREATE TABLE employee_roles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id),
  branch_id       UUID REFERENCES organization_branches(id), -- ถ้า NULL = ผู้ดูแลระดับ HQ ดูแลทุกสาขา
  user_id         UUID NOT NULL REFERENCES users(id),      -- ต้องเป็นสมาชิก Sheserved
  role_id         UUID NOT NULL REFERENCES organization_roles(id),
  assigned_at     TIMESTAMPTZ DEFAULT now()
);
```

### 5. ระบบการแจ้งเตือนภายในองค์กร (Intra-Organization Notifications)
สำหรับการแจ้งเตือนระหว่างพนักงานกันเองในองค์กรเดียวกัน (ภายใต้ `profession_id` เดียวกัน) ครอบคลุมทุกระบบย่อยของ ERP ให้ปฏิบัติตามแนวทาง UI และการทำงานดังนี้:
- **ตำแหน่งแสดงผล:** แสดงบริเวณพื้นที่ **Headsector (มุมขวาบน)** ในหน้า Home ของแอปพลิเคชัน
- **การเรียงลำดับ (Sorting):** เรียงลำดับให้การแจ้งเตือนล่าสุดอยู่ด้านบนเสมอ (Newest first)
- **รูปแบบการแสดงผล (UI Design):** 
  - ใช้การ์ดที่มี **พื้นหลังสีม่วงอ่อน (Light Purple)** เพื่อให้มีความโดดเด่นและเป็นเอกลักษณ์สำหรับการแจ้งเตือนภายในองค์กร
  - **ต้องมีโลโก้ขององค์กรนำหน้าข้อความแจ้งเตือนเสมอ** โดยให้ดึงภาพโลโก้จริงจากฐานข้อมูล (เช่น ตาราง `professions`) มาแสดง

### ฟีเจอร์เปิด/ปิด (Feature Toggles)

*เพื่อให้แต่ละองค์กรสามารถกำหนดการเปิดหรือปิดโมดูลได้ตามความต้องการ*

```sql
CREATE TABLE organization_feature_flags (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id UUID NOT NULL REFERENCES professions(id),
  feature_name  TEXT NOT NULL,                -- เช่น 'crm_loyalty', 'crm_coupons', 'crm_promotions', 'pos_module', 'inventory_module'
  is_enabled    BOOLEAN NOT NULL DEFAULT true, -- true = เปิดใช้งาน, false = ปิด
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, feature_name)
);
```

---

### การเชื่อมโยงระบบโทรเวชกรรมและการแจ้งเหตุฉุกเฉิน (Telemedicine & Emergency System Integration - Phase สุดท้าย)

เพื่อเตรียมรองรับเคสผู้ป่วยและการสื่อสารทางไกลที่ถูกส่งต่อมาจากระบบแชท [CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](../plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md) และระบบวิดีโอช่วยเหลือฉุกเฉิน [VIDEO_SYSTEM_PLAN.md](../plans/VIDEO_SYSTEM_PLAN.md) ระบบ ERP จะทำหน้าที่เชื่อมโยงข้อมูลในลักษณะ Single Source of Truth ดังนี้:

#### 1. การบูรณาการร่วมกับระบบเวชระเบียน (HIS / EMR Sync)
* **การบันทึกประวัติรักษาระยะไกล:** เมื่อแพทย์และคนไข้สิ้นสุดการปรึกษาทางไกล (Tele-consultation session) ข้อมูลผลการวินิจฉัยโรค (ICD-10) อาการสำคัญ และแผนการรักษาจากตาราง `consultation_notes` (Medical Summary) จะถูกส่งเข้าสู่ฐานข้อมูลหลักของ HIS ภายใต้ตาราง EMR ของคนไข้รายนั้นทันที โดยจำแนกตาม `profession_id` ของแพทย์/คลินิกที่ให้บริการ
* **ภาพและคลิปวิดีโอทางแพทย์:** สื่อมัลติมีเดีย (รูปภาพแสดงอาการ, วิดีโอแจ้งเหตุ) ที่ส่งผ่านห้องแชทและคอล ซึ่งผ่านขั้นตอนการทำ **Face Blur และประทับลายน้ำ (PDPA Compliance)** แล้ว จะถูกเก็บบันทึกและเชื่อมโยงกับแถบประวัติรักษาในระบบ EMR เพื่อให้แพทย์ใช้พิจารณาประกอบการติดตามผลรักษา

#### 2. การสั่งยาและการตัดคลังสินค้า (E-Prescription & Inventory Integration)
* **ใบสั่งยาออนไลน์:** ใบสั่งยาอิเล็กทรอนิกส์ (`prescriptions`) ที่เกิดขึ้นในห้องแชทจะส่งข้อมูลยารายการย่อย (Medications JSON) ไปยังห้องยาของระบบ HIS โดยอัตโนมัติ
* **การคัดกรองตามหลัก FEFO:** ระบบห้องยาของ HIS จะดึงข้อมูลสต๊อกยารายการดังกล่าวจากระบบ **Inventory** เพื่อตรวจสอบวันหมดอายุและล็อตสินค้า และทำการจองยาโดยเลือกใช้ล็อตที่ใกล้หมดอายุก่อนตามหลัก FEFO (First Expired, First Out)

#### 3. การชำระเงินและการเงิน (POS, CRM & Accounting Integration)
* **การสร้างบิลอัตโนมัติ:** เมื่อแพทย์ยืนยันส่งใบสั่งยา ระบบ **POS System** จะได้รับใบแจ้งหนี้จำหน่ายยาและค่าปรึกษาเพื่อให้คนไข้กดยืนยันชำระเงินผ่านช่องทาง Payment Gateway บนแอปพลิเคชัน
* **การรับรู้รายได้และแต้มสะสม:** เมื่อยอดเงินชำระเสร็จสมบูรณ์:
  - POS จะสั่งการให้ Inventory ตัดสต๊อกยาออกจากระบบถาวร
  - ระบบ **Accounting** จะบันทึกการรับรู้รายได้ (General Ledger) ทันที
  - ระบบ **CRM** จะคำนวณคะแนนสะสม (Loyalty Points) และประมวลผลการใช้สิทธิ์คูปอง/แพ็กเกจของผู้ซื้อ

#### 4. การจัดการบุคลากรทางการแพทย์และอาสาสมัคร (HR Integration)
* **ค่าตอบแทนและชั่วโมงการปรึกษา:** ระบบจะดึงประวัติระยะเวลาการโทร/แชทจากตาราง `consultation_sessions` ในช่วงกะเวลาปฏิบัติงานมาคำนวณเป็นค่าคอมมิชชันหรือค่าธรรมเนียมวิชาชีพแพทย์ในระบบ **HR System**
* **สถิติการออกเหตุอาสาสมัคร:** ในระบบช่วยเหลือฉุกเฉิน (Video System) ประวัติของเจ้าหน้าที่ในการกดยืนยันให้ความช่วยเหลือผู้ป่วย (`Volunteer Response`) จะถูกนำไปแปลงเป็นผลงานช่วยเหลือสังคม ชั่วโมงจิตอาสา หรือคำนวณเบี้ยเลี้ยงพิเศษในระบบ HR ต่อไป

---

### สิ่งที่ยังไม่ได้เชื่อมต่อตามแผน
- **Routing**: ยังไม่ได้กำหนด route สำหรับ `/erpHome`, `/erpDashboard`, `/posManagement`, ฯลฯ ใน `MaterialApp` หรือระบบ router
- **โมดูลที่ขาด**: ยังไม่มีไฟล์ UI จริงสำหรับ **Procurement Management**, **Accounting Management**, **HR Management**, **CRM Management**, **Permission Management**
- **เชื่อมโยง Dashboard**: `ErpDashboardPage` ยังไม่เชื่อมต่อกับหน้าโมดูลย่อย (ยังคงเป็น `onTap` ที่ placeholder)
- **Feature Toggles**: ตาราง `organization_feature_flags` ยังไม่ได้ถูกนำมาใช้ในการเปิด/ปิดโมดูล UI
- **HomeErpCard Route**: ยังไม่ได้อัปเดต navigation จาก `HomeErpCard` ไปยัง `ErpHomePage`
- **Permission Page**: ยังไม่มี UI สำหรับจัดการสิทธิ์ (`Permission Management Page`)
- **KPI Dashboard**: มีการออกแบบแผนงานแล้วที่ `KPI_DASHBOARD_PLAN.md` (ใช้ระบบสิทธิ์ร่วมกับ HR) แต่ยังไม่มีการสร้างหน้าจอ UI จริง

*หมายเหตุ: สามารถคลิกที่ชื่อแต่ละระบบเพื่อเข้าไปดู/แก้ไขรายละเอียดแผนงานเชิงลึกได้*
