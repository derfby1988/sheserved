# Sheserved ERP - Core Architecture

## ภาพรวม (Overview)

> **หมายเหตุสำหรับองค์กรที่ได้รับสิทธิ์ขาย:** ทุกองค์กรที่มีค่า `uses_pos_system = true` จะได้รับ **ระบบ ERP ทั้งหมด** ให้ทดลองใช้งานเต็มระบบในระยะเวลาที่ Sheserved กำหนด เมื่อหมดช่วงทดลอง องค์กรจะต้องเลือกสมัคร **Subscription Plan** เพื่อใช้งานต่อ โดยโมดูลที่ไม่ได้อยู่ในแพลนจะถูกล็อก (Locked) แต่ข้อมูลเดิมทั้งหมดยังคงถูกเก็บรักษาไว้อย่างปลอดภัย (ดูรายละเอียดใน [ระบบ Subscription & Licensing](#ระบบ-subscription--licensing-erp-service-management))

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
4. **หน้าจอตั้งค่าและเลือก Drive (Setup UI):** ต้องมีหน้าจอสำหรับผู้ดูแลระบบของคลินิก โดย**ระบบจะทำการแสกนและค้นหา IP ของเซิร์ฟเวอร์ฐานข้อมูลในเครือข่ายให้อัตโนมัติ (Auto-Discovery)** เพื่ออำนวยความสะดวก พร้อมทั้งอนุญาตให้ผู้ดูแลระบบสามารถแก้ไข (Edit) หรือกรอก IP/URL แบบแมนนวลเองได้ในกรณีที่ค้นหาไม่พบ เมื่อตั้งค่าสำเร็จ ระบบจะเปลี่ยน `storage_mode` และบันทึก `self_host_api_url` ให้โดยอัตโนมัติ

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

8. **[LIS / Laboratory Information System (External Lab Integration)](LAB_SYSTEM_PLAN.md)**
   - **หน้าที่:** ระบบจัดการและเชื่อมต่อกับห้องปฏิบัติการภายนอก (External Labs) เพื่อรองรับการสั่งตรวจและรับผลตรวจ
   - **การเชื่อมโยง:** รับคำสั่งตรวจจาก *HIS*, โยนยอดชำระไปที่ *POS*, บันทึกต้นทุน/หนี้ค้างจ่ายที่ *Accounting*, และเชื่อมต่อ *Logistics* กรณีจัดส่งตัวอย่าง

9. **[Telemedicine System (ระบบโทรเวชกรรม - Phase สุดท้าย)](../plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md)** (เชื่อมโยงร่วมกับ **[Video System](../plans/VIDEO_SYSTEM_PLAN.md)**)
   - **หน้าที่:** รองรับการปรึกษาแพทย์ทางไกลผ่านระบบแชท การโทรวิดีโอ (Tele-Consultation) และการส่งต่อการช่วยเหลือเหตุฉุกเฉิน (Emergency Alert Response)
   - **การเชื่อมโยง:**
     - **HIS/EMR:** ส่งต่อบันทึกผลการวินิจฉัยโรคและแผนการรักษาจาก `consultation_notes` (Medical Summary) เข้าเป็นส่วนหนึ่งของเวชระเบียนผู้ป่วย (EMR)
     - **POS System:** รับส่งข้อมูลใบสั่งยาอิเล็กทรอนิกส์ (`prescriptions`) จากการแชท/วิดีโอคอล เพื่อเข้ากระบวนการชำระเงินค่าปรึกษาและค่ายาอัตโนมัติ
     - **Inventory / Stock:** เมื่อ POS บันทึกการชำระเงินค่ายาเสร็จสิ้น จะตัดยอดสต๊อกยาตามล็อตวันหมดอายุ (FEFO/Lot/Expiry)
     - **HR System:** บันทึกเวลาปฏิบัติงานของแพทย์ (`consultation_sessions`) และบันทึกประวัติการช่วยเหลือเหตุฉุกเฉินของอาสาสมัคร (Volunteer Response) เพื่อใช้ประเมินค่าตอบแทนหรือผลงาน
     - **Accounting / Finance:** รับรู้รายได้จากการให้บริการปรึกษาทางไกลและการจำหน่ายยา

10. **CDP (Customer Data Platform) / การเชื่อมโยงข้อมูลลูกค้าแบบองค์รวม**
   - **หน้าที่:** ควบรวมข้อมูลลูกค้า (Identity Resolution) จากทุกแหล่งเข้าด้วยกันด้วย **Global ID** เพียงหนึ่งเดียว (Single Customer View / 360-degree View)
   - **การเชื่อมโยง:** ทำงานข้ามระบบทั้งหมดโดยเฉพาะร่วมกับ **CRM** (ใช้วิเคราะห์พฤติกรรม แบ่งกลุ่มเป้าหมาย และทำ Marketing Automation), **HIS** (ดึงประวัติการรักษา), **POS** (ดึงยอดสั่งซื้อ) และ **Read Model / Analytics** (ดึง aggregated snapshot เพื่อสร้าง 360-degree view แบบ real-time) เพื่อเป็นรากฐานในการส่งมอบการบริการลูกค้า (Customer Service) ที่แม่นยำและตรงจุดที่สุด

11. **[Logistics / Delivery Management](../plans/Delivery_PLAN.md)**
    - **หน้าที่:** ระบบจัดการการจัดส่งสินค้าและยา จัดการรอบรถ ไรเดอร์ และติดตามสถานะพัสดุ
    - **การเชื่อมโยง:** เป็นสะพานเชื่อมระหว่าง **POS** (รับออเดอร์/คิดค่าส่ง), **Inventory** (เบิกของ/แพ็ค/ตัดสต๊อก), และ **Accounting** (รับรู้รายได้ค่าขนส่ง)

12. **Commerce Core (Order & Checkout)**
    - **หน้าที่:** ระบบคำสั่งซื้อ (Order) และเซสชันชำระเงิน (CheckoutSession) เป็นแกนกลางของการทำธุรกรรมการค้าทุกช่องทาง (POS, ตะกร้าออนไลน์, สั่งยาจาก Telemedicine)
    - **การเชื่อมโยง:** รับ intent จาก **Cart** (checkout), ส่งคำสั่งซื้อไป **POS** (ผ่าน POS Injection), ส่งข้อมูลรายได้ไป **Accounting** (ผ่าน Outbox), ส่งข้อมูลจัดส่งไป **Logistics**

13. **Cart Core (Shopping Cart & Merchant Grouping)**
    - **หน้าที่:** ตะกร้าสินค้าสากล (Universal Cart) รองรับ multi-supplier, multi-tenant, การแบ่ง checkout ตาม merchant, และ snapshot ราคา/สต๊อกตอนหยิบใส่ตะกร้า
    - **การเชื่อมโยง:** ส่งข้อมูล checkout ไป **Commerce** (สร้าง Order), ดึงข้อมูลสินค้าจาก **Inventory** (เช็คสต๊อกแบบ real-time), ดึงโปรไฟล์ลูกค้าจาก **CRM**

14. **Settlement Core (Payout & Vendor Contract)**
    - **หน้าที่:** จัดการสัญญา vendor (platform fee, settlement cycle), บันทึก settlement ledger, สร้าง payout batch และติดตามการโอนเงินให้แต่ละ merchant
    - **การเชื่อมโยง:** รับข้อมูลคำสั่งซื้อจาก **Commerce** (เพื่อคำนวณ fee), ส่งข้อมูล payout ไป **Accounting** (เพื่อบันทึก AP/GL), อ่านสถานะชำระเงินจาก **POS**

15. **Read Model / Analytics Core (CQRS & Projections)**
    - **หน้าที่:** ระบบ projection แบบ event-driven (CQRS) สร้าง dashboard snapshot, materialized view สำหรับรายงาน, และ caching layer แยกจาก transactional database
    - **การเชื่อมโยง:** อ่าน events จาก **Reliability** (`outbox_events`), สร้าง snapshot สำหรับ **POS** (ยอดขายรวม), **Inventory** (สต๊อกคงเหลือ), **CRM** (แต้มสะสม), **Accounting** (รายงานกำไรขาดทุน)

16. **Reliability Core (Idempotency, Outbox & Audit)**
    - **หน้าที่:** infrastructure cross-cutting สำหรับความน่าเชื่อถือของระบบ — idempotency keys, outbox/inbox events, transaction audit log, circuit breakers, retry mechanisms, dead letter records
    - **การเชื่อมโยง:** ทำงานข้ามทุก core และโมดูลธุรกิจ — ทุกการเขียนข้อมูล (write operation) ที่มีผลต่อเงินหรือสต๊อกต้องผ่าน **Reliability** (idempotency check + outbox publish) ก่อน commit
    - **หมายเหตุ:** เป็น **always-on infrastructure** — ไม่สามารถปิดได้ผ่าน subscription module toggle และไม่มี UI หน้าจัดการแยกใน Dashboard (แต่มี monitoring console สำหรับ ERP Service Manager)

## ระบบจัดการเอกสารและแบบฟอร์มทางการแพทย์ (Medical Document & Form Management)
ระบบ ERP รองรับการออกเอกสารทางการแพทย์และเอกสารคลินิกอย่างครบวงจร ภายใต้แนวคิด **Customizable Templates (แบบฟอร์มที่ปรับแต่งได้)** สำหรับแต่ละองค์กร (`profession_id`):
- **ประเภทเอกสารที่รองรับ:** ใบรับรองแพทย์ (Medical Certificates), ใบส่งต่อผู้ป่วย (Referral Forms), ใบเวชระเบียน (Medical Records), สรุปผลการรักษา (Medical Summaries), แบบฟอร์มยินยอม (Consent Forms) และอื่นๆ
- **การปรับแต่งแบบฟอร์ม (Form Customization):** แต่ละคลินิก/องค์กรสามารถออกแบบ ปรับแต่งโลโก้, ข้อความหัวกระดาษ-ท้ายกระดาษ, และปรับโครงสร้างฟิลด์ข้อมูลในแบบฟอร์มให้เหมาะสมกับรูปแบบของตนเองได้
- **Smart Template Memory:** ระบบจะจดจำแบบฟอร์มและการตั้งค่าล่าสุดที่องค์กรปรับแต่ง (Auto-save latest template) และเรียกใช้แบบฟอร์มนั้นเป็นค่าเริ่มต้น (Default) ในครั้งถัดไปโดยอัตโนมัติ เพื่อความรวดเร็วในการทำงาน
- **การจัดเก็บและตรวจสอบย้อนหลัง:** เอกสารที่ถูกสร้างและพิมพ์จะถูกจัดเก็บประวัติ (Document History) เชื่อมโยงกับเวชระเบียน (EMR) ของผู้ป่วยรายนั้น เพื่อให้สามารถตรวจสอบย้อนหลังหรือพิมพ์ซ้ำได้เสมอ

## มาตรฐานบัญชีและการเงิน (Accounting & Financial Standards)
ระบบย่อยทั้งหมดใน Sheserved ERP จะถูกออกแบบและทำงานสอดคล้องกันภายใต้ **ผังบัญชีมาตรฐาน (Standard Chart of Accounts)** และ **บัญชีแยกประเภท (General Ledger)** ที่ใช้ในประเทศไทย โดยอ้างอิงจากตัวบทกฎหมายและข้อกำหนดของ **กรมสรรพากร (Revenue Department)** เป็นหลัก เพื่อให้เอกสารทางการเงิน (เช่น ใบกำกับภาษี, ใบเสร็จรับเงิน, หัก ณ ที่จ่าย) และรายงานทางบัญชีสามารถนำไปใช้ยื่นภาษีและตรวจสอบทางกฎหมายได้อย่างถูกต้อง

## ERP Dashboard (แดชบอร์ดจัดการองค์กร)

ทุกองค์กรที่ผ่านการยืนยันจาก Admin Sheserved (ตามขั้นตอนการลงทะเบียนในหมวดหมู่ที่ Sheserved กำหนด) จะได้รับหน้าจอ **ERP Dashboard** เป็นของตนเอง ซึ่งประกอบด้วย:

### 1. หน้าตั้งค่าเบื้องต้น (Organization Settings)
- [x] ข้อมูลองค์กร (ชื่อ, ที่อยู่, เลขที่ผู้เสียภาษี, โลโก้, โทรศัพท์, อีเมล)
- [x] การตั้งค่าภาษา, สกุลเงิน, เขตเวลา, โหมดจัดเก็บข้อมูล (cloud/self-host/hybrid)
- [x] Multi-Branch Support: จัดการสาขา (เพิ่ม/แก้ไข/ลบ) พร้อมรหัสสาขาภาษี (`branch_tax_code`)
- [x] UI Glassmorphism: ใช้ `GlassCard`, `GlassButton`, พื้นหลัง pastel gradient
- [x] ช่องทางการชำระเงิน (Payment Channels) — `payment_channels` table + `PaymentChannelsPage` + dynamic checkout methods
- [x] Validation logic สำหรับ `branch_tax_code` — DB-level `validate_branch_tax_code()` + Flutter `_isValidBranchTaxCode()` (5 digits, e.g., 00000)

### สถานะปัจจุบัน
- ✔️ ฟีเจอร์ Organization Settings (Glassmorphism, editable branches, branch_tax_code+email) เสร็จแล้วตาม checklist ด้านบน
- ⏳ Phase 0 (RBAC, Reliability Core, Feature Flags, Organization Settings schema) และ Phase 1 (CRM + Procurement + Inventory data) ถูก mark ว่า ✅ COMPLETE โดยมีทั้ง migration + Flutter layer cover
- ✅ Phase 2 (Commerce/Cart/Settlement/Delivery) **COMPLETE** — มีทั้ง migration + Flutter layer ครบถ้วน สามารถเพิ่ม/ลบตะกร้า → checkout → สร้าง order → ชำระเงิน → delivery → ดู vendor contracts ได้
- ✅ Payment Channels (`payment_channels` + `seed_default_payment_channels` + `PaymentChannelsPage`) + branch_tax_code validation (DB + Flutter) **COMPLETE** — migration รันสำเร็จบน Supabase

### 2. หน้าจัดการแยกรายโมดูล (Module Management Pages)
แต่ละโมดูลใน ERP จะมีหน้าจัดการของตัวเองภายใน Dashboard ขององค์กร ได้แก่:
- 🛒 **POS Management** — จัดการสินค้า, ราคา, โปรโมชั่น
- 📦 **Inventory Management** — จัดการคลังสินค้า, สต๊อก
- 🛍️ **Procurement Management** — จัดการการสั่งซื้อ, Supplier
- 📊 **Accounting Management** — ดูรายงานบัญชี, ผังบัญชี
- 👥 **HR Management** — จัดการพนักงาน, กะงาน, เงินเดือน
- 🎁 **CRM Management** — จัดการลูกค้า, แต้มสะสม, แพ็กเกจ
- 🏥 **HIS / EMR Management** — จัดการเวชระเบียน, ตรวจรักษา, สั่งยา (Phase สุดท้าย)
- 🔬 **LIS / Lab Management** — จัดการคู่ค้าแล็บ, สั่งตรวจ, รับผลตรวจ
- 📞 **Telemedicine Management** — ติดตามการปรึกษาทางแชท/วิดีโอคอล, ใบสั่งยาออนไลน์, และสถิติการแจ้งเหตุฉุกเฉิน (Phase สุดท้าย)
- 🚚 **Logistics Management** — จัดการรอบรถ, ไรเดอร์, และติดตามพิกัดการจัดส่ง
- 🛍️ **Commerce Management** — ดูคำสั่งซื้อ (Order), เซสชันชำระเงิน (Checkout), และสถานะธุรกรรม
- 🛒 **Cart Management** — ดูตะกร้าสินค้าที่ยังไม่ checkout, จัดการ merchant grouping, และ snapshot ราคา
- 💰 **Settlement Management** — ดูสัญญา vendor, ตาราง payout batch, และสถานะการโอนเงิน
- 📈 **Analytics Management** — ดู dashboard snapshot, รายงานสรุปจาก Read Model projections (ยอดขาย, สต๊อก, แต้ม)
- ⚙️ **System Operations** — ดูสถานะ outbox events, idempotency keys, circuit breaker states และ dead letter records (เฉพาะ ERP Service Manager หรือผู้ดูแลระบบระดับสูง)

### 3. หน้า Overview ของ ERP Dashboard (`/erp/dashboard`)

หน้าแรกที่แสดงเมื่อเข้า ERP Dashboard เป็น **ภาพรวมของโมดูล** ที่เปิดใช้งาน ไม่ใช่หน้ารายละเอียดของโมดูลใดโมดูลหนึ่ง

**ประกอบด้วย:**
1. **Organization Header** — ชื่อองค์กร + โลโก้ + สาขาที่เลือก + Subscription Tier โดยใช้ glass card แบบ soft pastel ใน Light mode
2. **Module Cards Board** — การ์ดเข้าถึงโมดูลที่เปิดใช้งาน (ตาม `organization_feature_flags` + `tier_features`) แบบ mixed-size responsive board
   - โมดูลที่ปิด → ซ่อน
   - โมดูลที่ไม่อยู่ใน Tier → disabled หรือ badge "ต้องสมัคร"
3. **Recent Notifications** — แจ้งเตือนล่าสุดจากทุกโมดูล (In-App, ฟรี)
4. **Quick Stats (Optional)** — จำนวน notification ที่ยังไม่อ่าน ต่อโมดูล (ไม่ใช่ KPI ธุรกิจ)

**รูปแบบการจัดวางภาพรวม:**
- **Mobile:** 2-column responsive board, มีบาง tile span 2 columns
- **Tablet:** 3-column board, สลับ tile แบบ square / capsule / hero card
- **Desktop:** 4-column board, ยังยืดหยุ่นตามความกว้างหน้าจอ
- **Light mode:** ใช้โทน iOS natural pastel + glass shine ตาม `ERP_GLASSMORPHISM_PLAN.md`

**ไม่ประกอบด้วย:**
- ❌ **KPI Summary** (ยอดขาย, สต๊อก, แต้ม) → อยู่ใน **Analytics Management** (`/erp/analytics`) หรือแต่ละโมดูลย่อย
- ❌ **รายงานละเอียด** → อยู่ในแต่ละโมดูล เช่น `/erp/crm/reports`, `/erp/pos/reports`
- ❌ **กราฟ/Chart** → อยู่ใน Analytics Management หรือโมดูลย่อย

> **หลักการ:** Overview เป็น **Entry Point/Navigation Hub** — ให้ user เห็นว่ามีโมดูลอะไรบ้าง และเข้าไปยังโมดูลนั้นๆ ได้ในคลิกเดียว

### 4. การปรับแต่งการจัดเรียง Module Cards (User Customizable Grid)

ผู้ใช้งานแต่ละคนสามารถ **ลาก-วาง (Drag & Drop)** การ์ดโมดูลเพื่อจัดเรียงตามความชอบได้ โดยระบบจะ **บันทึกตำแหน่งลงฐานข้อมูล** และ **เรียกใช้ตำแหน่งล่าสุด** ที่บันทึกไว้ในครั้งถัดไป

#### ฐานข้อมูล (Database Schema)
> **สถานะ:** ✅ Phase 0 COMPLETE — `user_module_layouts` มี migration + Flutter layer (`ModuleManagementPage`, drag-drop reordering)

```sql
CREATE TABLE user_module_layouts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profession_id   UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  
  -- รายการโมดูลเรียงตามลำดับที่ user กำหนด
  module_order    TEXT[] NOT NULL DEFAULT '{}',
                  -- เช่น {'crm','pos','inventory','hr','accounting'}
  
  -- โมดูลที่ user ซ่อน (ไม่แสดงบน Dashboard)
  hidden_modules  TEXT[] NOT NULL DEFAULT '{}',
                  -- เช่น {'his','lis'} — โมดูลที่ปิดอยู่จะถูกซ่อนโดยอัตโนมัติ ไม่ต้องเก็บในนี้
  
  -- สถานะการแก้ไข
  is_customized   BOOLEAN DEFAULT false,  -- true = user ปรับแต่งแล้ว, false = ใช้ default
  
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, profession_id)
);

-- Index สำหรับดึง layout เร็ว
CREATE INDEX idx_user_module_layouts_user ON user_module_layouts(user_id, profession_id);

-- RLS: user เห็นเฉพาะ layout ของตนเอง
ALTER TABLE user_module_layouts ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_module_layout_isolation ON user_module_layouts
  USING (user_id = auth.uid());
```

#### ลำดับเริ่มต้น (Default Order)

ถ้า user ยังไม่เคยปรับแต่ง (`is_customized = false`) ใช้ลำดับ default:

```dart
const defaultModuleOrder = [
  'crm',        // 1. CRM (สำคัญที่สุดสำหรับคลินิก)
  'pos',        // 2. POS
  'inventory',  // 3. Inventory
  'hr',         // 4. HR
  'accounting', // 5. Accounting
  'pharmacy',   // 6. Pharmacy
  'procurement',// 7. Procurement
  'his',        // 8. HIS
  'telemedicine',// 9. Telemedicine
  'logistics',  // 10. Logistics
  'commerce',   // 11. Commerce
  'analytics',  // 12. Analytics
  'settings',   // 13. Settings (ล่างสุด)
];
```

#### การทำงานของ UI

```dart
// ReorderableGridView หรือ DragTarget + Draggable
class ModuleCardsGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(userModuleLayoutProvider);
    final modules = ref.watch(enabledModulesProvider); // กรองตาม feature toggle + tier
    
    // รวมลำดับจาก layout กับโมดูลที่เปิดใช้งาน
    final orderedModules = _applyLayoutOrder(modules, layout.moduleOrder);
    
    return ReorderableGridView.count(
      crossAxisCount: isDesktop ? 4 : isTablet ? 3 : 2,
      children: orderedModules.map((module) => ModuleCard(module)).toList(),
      onReorder: (oldIndex, newIndex) {
        // อัปเดต UI ทันที (optimistic)
        ref.read(userModuleLayoutProvider.notifier).reorder(oldIndex, newIndex);
        // บันทึกลง DB (debounce 500ms)
        ref.read(userModuleLayoutProvider.notifier).saveLayout();
      },
    );
  }
}
```

#### กฎการปรับแต่ง

- **ซ่อนโมดูล:** กดค้าง → เลือก "ซ่อน" → เพิ่มลง `hidden_modules` → ไม่แสดงบน grid
- **เรียงคืน:** ปุ่ม "เรียงคืนเริ่มต้น" → ล้าง `module_order` + `hidden_modules` → ใช้ default
- **ลำดับซ้ำกันได้:** user A เรียง CRM ก่อน, user B เรียง POS ก่อน — แยกกันตาม `user_id`
- **เปลี่ยน profession:** แต่ละ profession มี layout แยก (`profession_id` ใน unique key)
- **ไม่กระทบผู้ใช้อื่น:** layout เป็นของ user คนนั้นเท่านั้น (RLS)

#### API / RPC
> **สถานะ:** ✅ Phase 0 COMPLETE — RPC พร้อมใช้งาน

```sql
-- ดึง layout ของ user
CREATE OR REPLACE FUNCTION get_user_module_layout(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS JSONB AS $$
  SELECT jsonb_build_object(
    'module_order', module_order,
    'hidden_modules', hidden_modules,
    'is_customized', is_customized
  )
  FROM user_module_layouts
  WHERE user_id = p_user_id AND profession_id = p_profession_id;
$$ LANGUAGE plpgsql;

-- บันทึก layout
CREATE OR REPLACE FUNCTION save_user_module_layout(
  p_user_id UUID,
  p_profession_id UUID,
  p_module_order TEXT[],
  p_hidden_modules TEXT[]
) RETURNS VOID AS $$
  INSERT INTO user_module_layouts (user_id, profession_id, module_order, hidden_modules, is_customized)
  VALUES (p_user_id, p_profession_id, p_module_order, p_hidden_modules, true)
  ON CONFLICT (user_id, profession_id)
  DO UPDATE SET
    module_order = EXCLUDED.module_order,
    hidden_modules = EXCLUDED.hidden_modules,
    is_customized = true,
    updated_at = now();
$$ LANGUAGE plpgsql;
```

---

### 4.5 การปรับแต่งธีมสี Dashboard (User Theme Customization)

> **ดูแผน UI/UX ฉบับรวม:** [ERP_DASHBOARD_UI_PLAN.md](ERP_DASHBOARD_UI_PLAN.md) — รวม Glassmorphism + Light/Dark Theme + Sidebar Navigation

ผู้ใช้งานแต่ละคนสามารถเลือก **ธีมสี (Color Theme)** ของ ERP Dashboard ได้ที่หน้า **"ตั้งค่า Dashboard"** (`/erp/settings/theme`) โดยใช้งานครั้งแรกจะได้ **ธีมเริ่มต้นของ Sheserved**

#### ฐานข้อมูล (Database Schema)
> **สถานะ:** ✅ Phase 0 COMPLETE — schema + migration + Flutter layer พร้อม

```sql
-- ============================================================
-- ตารางธีมสีของผู้ใช้ (User Dashboard Theme)
-- ============================================================
CREATE TABLE user_dashboard_themes (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  
  -- ธีมที่เลือก
  theme_preset          TEXT DEFAULT 'sheserved_default',
                          -- 'sheserved_default', 'ocean_blue', 'sunset_orange',
                          -- 'forest_green', 'royal_purple', 'midnight_black',
                          -- 'coral_pink', 'custom'
  
  -- สีที่กำหนดเอง (ถ้า theme_preset = 'custom')
  custom_primary        TEXT,  -- เช่น '#00695C' (sidebar bg)
  custom_accent         TEXT,  -- เช่น '#FFC107' (toggle button, badge)
  custom_surface        TEXT,  -- เช่น '#FFFFFF' (active item bg)
  custom_text_primary   TEXT,  -- เช่น '#FFFFFF' (label text)
  custom_text_secondary TEXT,  -- เช่น 'rgba(255,255,255,0.7)' (dim icon)
  custom_error          TEXT,  -- เช่น '#EF4444' (badge bg)
  
  -- สถานะ
  is_using_custom       BOOLEAN DEFAULT false,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, profession_id)
);

-- RLS
ALTER TABLE user_dashboard_themes ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_theme_isolation ON user_dashboard_themes
  USING (user_id = auth.uid());

-- ============================================================
-- ตารางธีมสีเริ่มต้นของ Sheserved (Master Presets)
-- ============================================================
CREATE TABLE theme_presets (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  preset_key    TEXT NOT NULL UNIQUE,  -- 'sheserved_default', 'ocean_blue', ...
  preset_name_th TEXT NOT NULL,         -- 'Sheserved Default', 'สีฟ้ามหาสมุทร'
  preset_name_en TEXT NOT NULL,
  
  -- สีหลัก
  primary_color      TEXT NOT NULL,  -- sidebar background
  accent_color       TEXT NOT NULL,  -- toggle button, highlights
  surface_color      TEXT NOT NULL,  -- active item bg
  text_primary       TEXT NOT NULL,  -- label text
  text_secondary     TEXT NOT NULL,  -- dim icon
  error_color        TEXT NOT NULL,  -- badge bg
  
  -- สีเสริม
  card_bg            TEXT,           -- bottom promo card bg
  card_text          TEXT,           -- bottom promo card text
  gradient_start     TEXT,           -- sidebar gradient start (optional)
  gradient_end       TEXT,           -- sidebar gradient end (optional)
  
  is_active          BOOLEAN DEFAULT true,
  created_at         TIMESTAMPTZ DEFAULT now()
);

-- Seed: Sheserved Default Theme (Teal Dark)
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('sheserved_default', 'Sheserved Default', 'Sheserved Default', '#00695C', '#FFC107', '#FFFFFF', '#FFFFFF', 'rgba(255,255,255,0.7)', '#EF4444', '#FFFFFF', '#1F2937');

-- Seed: Ocean Blue
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('ocean_blue', 'สีฟ้ามหาสมุทร', 'Ocean Blue', '#1565C0', '#FF6F00', '#FFFFFF', '#FFFFFF', 'rgba(255,255,255,0.7)', '#EF4444', '#FFFFFF', '#1F2937');

-- Seed: Sunset Orange
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('sunset_orange', 'สีส้มพระอาทิตย์ตก', 'Sunset Orange', '#E65100', '#FFD600', '#FFFFFF', '#FFFFFF', 'rgba(255,255,255,0.7)', '#EF4444', '#FFFFFF', '#1F2937');

-- Seed: Forest Green
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('forest_green', 'สีเขียวป่าไม้', 'Forest Green', '#2E7D32', '#FFEB3B', '#FFFFFF', '#FFFFFF', 'rgba(255,255,255,0.7)', '#EF4444', '#FFFFFF', '#1F2937');

-- Seed: Royal Purple
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('royal_purple', 'สีม่วงราชา', 'Royal Purple', '#6A1B9A', '#FFEA00', '#FFFFFF', '#FFFFFF', 'rgba(255,255,255,0.7)', '#EF4444', '#FFFFFF', '#1F2937');

-- Seed: Midnight Black
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('midnight_black', 'สีดำเที่ยงคืน', 'Midnight Black', '#212121', '#00E676', '#424242', '#FFFFFF', 'rgba(255,255,255,0.6)', '#EF4444', '#424242', '#FFFFFF');

-- Seed: Coral Pink
INSERT INTO theme_presets (preset_key, preset_name_th, preset_name_en, primary_color, accent_color, surface_color, text_primary, text_secondary, error_color, card_bg, card_text) VALUES
('coral_pink', 'สีชมพูปะการัง', 'Coral Pink', '#C2185B', '#76FF03', '#FFFFFF', '#FFFFFF', 'rgba(255,255,255,0.7)', '#EF4444', '#FFFFFF', '#1F2937');
```

#### ธีมที่มีให้เลือก (Presets)

| Preset Key | ชื่อ (ไทย) | Primary (Sidebar BG) | Accent (Toggle/Badge) | ลักษณะ |
|-----------|-----------|----------------------|----------------------|--------|
| `sheserved_default` | Sheserved Default | `#00695C` (Teal) | `#FFC107` (Amber) | คลาสสิก, สบายตา |
| `ocean_blue` | สีฟ้ามหาสมุทร | `#1565C0` (Blue) | `#FF6F00` (Deep Orange) | สดชื่น, มืออาชีพ |
| `sunset_orange` | สีส้มพระอาทิตย์ตก | `#E65100` (Orange) | `#FFD600` (Yellow) | อบอุ่น, กระตือรือร้น |
| `forest_green` | สีเขียวป่าไม้ | `#2E7D32` (Green) | `#FFEB3B` (Yellow) | ธรรมชาติ, สุขภาพ |
| `royal_purple` | สีม่วงราชา | `#6A1B9A` (Purple) | `#FFEA00` (Yellow) | หรูหรา, โดดเด่น |
| `midnight_black` | สีดำเที่ยงคืน | `#212121` (Black) | `#00E676` (Green) | มืด, ประหยัดแบต |
| `coral_pink` | สีชมพูปะการัง | `#C2185B` (Pink) | `#76FF03` (Lime) | สดใส, สร้างสรรค์ |
| `custom` | กำหนดเอง | ตาม user | ตาม user | ปรับทุกสีได้ |

> **หมายเหตุ:** ธีม `sheserved_default` ใช้เป็นค่าเริ่มต้นสำหรับผู้ใช้งานทุกคนที่เข้าใช้ ERP Dashboard เป็นครั้งแรก (`theme_preset = 'sheserved_default'`)

#### หน้าเลือกธีม (`/erp/settings/theme`)

```
┌─────────────────────────────────────────────┐
│  <- กลับ  |  ธีมสี Dashboard                  |
├─────────────────────────────────────────────┤
│  ธีมที่ใช้งานอยู่                           │
│  ┌───────────────────────────────────────┐  │
│  │ 🎨 [Preview Box]                      │  │
│  │    Sheserved Default                   │  │
│  │    #00695C + #FFC107                   │  │
│  └───────────────────────────────────────┘  │
│                                              │
│  เลือกธีม                                   │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐          │
│  │ 🟢  │ │ 🔵  │ │ 🟠  │ │ 🟩  │          │
│  │Default│ │Ocean│ │Sun- │ │Forest│          │
│  │     │ │Blue │ │ set │ │Green │          │
│  └─────┘ └─────┘ └─────┘ └─────┘          │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐          │
│  │ 🟣  │ │ ⬛  │ │ 🩷  │ │ 🎨  │          │
│  │Royal│ │Mid- │ │Coral│ │Custom│          │
│  │     │ │night│ │Pink │ │     │          │
│  └─────┘ └─────┘ └─────┘ └─────┘          │
│                                              │
│  [กำหนดสีเอง]  <- แสดงเฉพาะเมื่อเลือก Custom  │
│  ┌───────────────────────────────────────┐  │
│  │ Primary:     [🎨 #00695C]            │  │
│  │ Accent:      [🎨 #FFC107]            │  │
│  │ Surface:     [🎨 #FFFFFF]            │  │
│  │ Text Primary: [🎨 #FFFFFF]            │  │
│  │ Error:        [🎨 #EF4444]            │  │
│  └───────────────────────────────────────┘  │
│                                              │
│        [💾 บันทึก]    [❌ คืนค่าเริ่มต้น]     │
└─────────────────────────────────────────────┘
```

#### การใช้งานธีมใน CollapsibleSidebar

```dart
class ThemedCollapsibleSidebar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(userDashboardThemeProvider);
    
    // ใช้สีจากธีมที่ user เลือก
    final primaryColor = Color(int.parse(theme.primaryColor.replaceFirst('#', '0xFF')));
    final accentColor = Color(int.parse(theme.accentColor.replaceFirst('#', '0xFF')));
    final surfaceColor = Color(int.parse(theme.surfaceColor.replaceFirst('#', '0xFF')));
    final textPrimary = Color(int.parse(theme.textPrimary.replaceFirst('#', '0xFF')));
    final textSecondary = Color(int.parse(theme.textSecondary.replaceFirst('#', '0xFF')));
    final errorColor = Color(int.parse(theme.errorColor.replaceFirst('#', '0xFF')));
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: primaryColor, // <- ใช้สีจากธีม
      child: Column(
        children: [
          // Toggle button ใช้ accent color
          _buildToggleButton(accentColor),
          // Nav items ใช้ textPrimary / textSecondary
          _buildNavItems(primaryColor, surfaceColor, textPrimary, textSecondary),
          // Badge ใช้ errorColor
          _buildBadge(errorColor),
        ],
      ),
    );
  }
}
```

#### API / RPC
> **สถานะ:** ✅ Phase 0 COMPLETE — RPC พร้อมใช้งาน

```sql
-- ดึงธีมของ user
CREATE OR REPLACE FUNCTION get_user_dashboard_theme(
  p_user_id UUID,
  p_profession_id UUID
) RETURNS JSONB AS $$
  SELECT jsonb_build_object(
    'preset', theme_preset,
    'custom', jsonb_build_object(
      'primary', custom_primary,
      'accent', custom_accent,
      'surface', custom_surface,
      'text_primary', custom_text_primary,
      'text_secondary', custom_text_secondary,
      'error', custom_error
    ),
    'is_custom', is_using_custom
  )
  FROM user_dashboard_themes
  WHERE user_id = p_user_id AND profession_id = p_profession_id;
$$ LANGUAGE plpgsql;

-- บันทึกธีม
CREATE OR REPLACE FUNCTION save_user_dashboard_theme(
  p_user_id UUID,
  p_profession_id UUID,
  p_preset TEXT,
  p_custom JSONB DEFAULT NULL
) RETURNS VOID AS $$
  INSERT INTO user_dashboard_themes (
    user_id, profession_id, theme_preset,
    custom_primary, custom_accent, custom_surface,
    custom_text_primary, custom_text_secondary, custom_error,
    is_using_custom
  )
  SELECT 
    p_user_id, p_profession_id, p_preset,
    p_custom->>'primary', p_custom->>'accent', p_custom->>'surface',
    p_custom->>'text_primary', p_custom->>'text_secondary', p_custom->>'error',
    (p_preset = 'custom')
  ON CONFLICT (user_id, profession_id)
  DO UPDATE SET
    theme_preset = EXCLUDED.theme_preset,
    custom_primary = EXCLUDED.custom_primary,
    custom_accent = EXCLUDED.custom_accent,
    custom_surface = EXCLUDED.custom_surface,
    custom_text_primary = EXCLUDED.custom_text_primary,
    custom_text_secondary = EXCLUDED.custom_text_secondary,
    custom_error = EXCLUDED.custom_error,
    is_using_custom = EXCLUDED.is_using_custom,
    updated_at = now();
$$ LANGUAGE plpgsql;

-- ดึงรายการธีม preset ทั้งหมด
CREATE OR REPLACE FUNCTION get_theme_presets()
RETURNS JSONB AS $$
  SELECT jsonb_agg(
    jsonb_build_object(
      'key', preset_key,
      'name_th', preset_name_th,
      'name_en', preset_name_en,
      'colors', jsonb_build_object(
        'primary', primary_color,
        'accent', accent_color,
        'surface', surface_color,
        'text_primary', text_primary,
        'text_secondary', text_secondary,
        'error', error_color
      )
    )
    ORDER BY preset_key
  )
  FROM theme_presets
  WHERE is_active = true;
$$ LANGUAGE plpgsql;
```

#### กฎการใช้งานธีม

- **ครั้งแรก:** `INSERT` อัตโนมัติด้วย `theme_preset = 'sheserved_default'` เมื่อ user เข้า ERP Dashboard ครั้งแรก
- **เปลี่ยนธีม:** เลือก preset จากหน้า settings → `save_user_dashboard_theme()` → `Consumer` re-build sidebar ทันที
- **Custom:** เปิด color picker → กำหนดสีเอง 6 ค่า → `theme_preset = 'custom'`
- **คืนค่าเริ่มต้น:** กด "คืนค่าเริ่มต้น" → `theme_preset = 'sheserved_default'` + ล้าง `custom_*`
- **แยกตาม profession:** แต่ละ profession มี theme แยก (`profession_id` ใน unique key)
- **Sheserved Admin:** สามารถเพิ่ม/ลบ/แก้ไข `theme_presets` ได้ผ่าน `/admin/theme-presets`

### 5. จุดเข้าสู่ระบบจากหน้าหลัก (Home Page Entry Point)

เพื่อรักษาโครงสร้าง UI (Layout) ของแอปพลิเคชันไม่ให้ผิดเพี้ยนไปจากเดิม และแยกประสบการณ์ใช้งานระหว่างผู้ใช้งานทั่วไปกับพนักงานองค์กรอย่างชัดเจน:

#### หลักการ: Dynamic Card Replacement (ไม่เปลี่ยน Layout)

- **กลไกการแสดงผล:** ระบบตรวจสอบ `employee_roles` + `role` field ของผู้ใช้ แล้วเลือกการ์ดที่เหมาะสม
- **ขนาดและตำแหน่ง:** `HomeErpCard` ใช้ `key` เดียวกัน (`_pharmacyKey`) มี padding, borderRadius, shadow, icon size เหมือน `HomePharmacyCard` ทุกประการ — ไม่กระทบการคำนวณ map offset หรือ layout ใดๆ ของหน้า Home
- **Responsive:** รองรับ Portrait และ Landscape (constraint width 50% เหมือนเดิม)

#### การ์ดตาม Role (บนหน้า Home)

| Role | การ์ดที่แสดง | เนื้อหา | ปุ่ม Action |
|------|-------------|---------|------------|
| **Consumer** | `HomePharmacyCard` | 💊 ร้านยาใกล้คุณ / จัดส่ง 10 นาที | `[ค้นหา]` |
| **Employee** | `HomeErpCard` | 📊 ERP Dashboard / จัดการคลินิก / 🔔 2 ใหม่ | `[เข้า]` |
| **Owner** | `HomeErpCard` | 📊 ERP Dashboard / จัดการคลินิก / 🔔 2 ใหม่ | `[จัด管理] [เข้า]` |
| **Sheserved Admin** | `HomeErpCard` | 🏢 Sheserved Admin / จัดการระบบ ERP / 🔔 5 ระบบ | `[เข้า]` |

> **หมายเหตุ:** Badge แจ้งเตือน (`🔔`) บน `HomeErpCard` ใช้ **In-App Notification (Headsector)** ซึ่งเป็นช่องทาง **ฟรี 100%** ผ่าน Supabase Realtime ไม่มีค่าใช้จ่ายเพิ่ม

#### เงื่อนไขการแสดง HomeErpCard

```dart
bool shouldShowErpCard(User user) {
  if (user == null) return false;
  if (user.role == 'sheserved_admin') return true;
  // ตรวจสอบ employee_roles
  return user.professionId != null 
      && user.professionId != '00000000-0000-0000-0000-000000000001' // Consumer profession
      && hasEmployeeRole(user.id, user.professionId);
}
```

#### Routing จาก HomeErpCard

```
Home Page
    │
    ├── HomeErpCard (onTap)
    │       │
    │       ▼
    │   /erp ──► ErpDashboardShell (Drawer + AppBar + Branch Selector)
    │       │
    │       ├── 📊 /erp/dashboard (Overview รวมทุก module + Quick Actions)
    │       ├── 🛒 /erp/pos
    │       ├── 📦 /erp/inventory
    │       ├── 👥 /erp/hr
    │       ├── 📊 /erp/crm ──► CrmDashboardPage
    │       ├── 💰 /erp/accounting
    │       └── ⚙️ /erp/settings
    │
    └── (ถ้าไม่มี ERP access) ──► HomePharmacyCard (ปกติ)
```

- `/erp` เป็น **Shell Route** — มี Drawer + AppBar คงที่ ทุก sub-page render ภายใน shell
- การ์ด `HomeErpCard` ไม่ใช่ standalone page — กดแล้วเข้า `/erp` (shell) ไม่ใช่ `/erpDashboard`
- **Sheserved Admin** กดเข้า `/admin/subscription/tiers` (แยกจาก ERP shell — เป็นหน้า Admin ภายใน)

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
> **สถานะ:** ✅ Phase 0 COMPLETE — `organization_branches`, `organization_roles`, `employee_roles` มี migration + UI
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
  email           TEXT,
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
  module_name     TEXT NOT NULL CHECK (module_name IN ('pos', 'inventory', 'procurement', 'accounting', 'hr', 'crm', 'his', 'lis', 'telemedicine', 'logistics', 'commerce', 'cart', 'settlement', 'read_model', 'reliability')),
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
> **สถานะ:** ✅ Phase 0 COMPLETE — `organization_feature_flags` มี migration + UI toggle
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

## ระบบ Subscription & Licensing (ERP Service Management)

ระบบควบคุมการให้บริการ ERP ของ Sheserved ภายใต้โมเดล **Subscription-based Licensing** โดย Sheserved เป็นผู้กำหนดโปรแกรมการสมัครและเงื่อนไขทั้งหมด

### หลักการสำคัญ
- **Free Trial → Subscription:** ทุกองค์กรที่ได้รับอนุมัติจาก Sheserved Admin จะได้ทดลองใช้ **ทุกโมดูล ERP เต็มระบบ** ในช่วงระยะเวลาทดลองที่ Sheserved กำหนด เมื่อหมดช่วงทดลอง โมดูลจะถูกล็อก (Locked UI) แต่ **ข้อมูลเดิมทั้งหมดยังถูกเก็บรักษาไว้** อย่างปลอดภัย
- **ยกเว้นค่าธรรมเนียมสำหรับสาขา Sheserved (Free Internal Waiver):** หากเป็นสาขาหรือองค์กรภายใต้ Sheserved เอง จะได้รับก## แผนงานการพัฒนาและลำดับความสำคัญ (Development Roadmap & Phase Ordering)

เพื่อให้การทดสอบในสภาวะการใช้งานจริงมีความลื่นไหลและสามารถทำ **Integration Test แบบ Zero-Mock (ไม่ใช้ Mock Data)** จากต้นน้ำไปปลายน้ำได้ ลำดับการพัฒนาระบบ ERP ทั้ง 10 โมดูล รวมถึงระบบจัดส่ง [Logistics / Delivery Management](../plans/Delivery_PLAN.md) จะถูกจัดเรียงตามความเกี่ยวพันของข้อมูล (Data Dependencies) ดังนี้:

```mermaid
graph TD
    subgraph Phase 1: Data & Inflow Foundations (ข้อมูลหลักและรับสินค้าเข้าคลัง)
        CRM[1. CRM System - ข้อมูลลูกค้า/ผู้ป่วย]
        PRO[2. Procurement - ใบสั่งซื้อสินค้า] --> INV[3. Inventory - รับของเข้าคลัง]
    end
    subgraph Phase 2: Core Commerce & Logistics (การขายและการขนส่ง)
        INV --> POS[4. POS System - ขายและหักสต็อก]
        CRM --> POS
        POS --> LOG[5. Logistics/Delivery - การจัดส่งยาและเวชภัณฑ์]
        INV --> LOG
    end
    subgraph Phase 3: Finance & HR Operations (การเงินและพนักงาน)
        POS --> ACC[6. Accounting - บันทึกรายได้และรายจ่าย]
        PRO --> ACC
        POS --> HR[7. HR System - คำนวณคอมมิชชันและกะงาน]
    end
    subgraph Phase 4: Clinical & Advanced Integrations (การแพทย์และการเชื่อมต่อภายนอก)
        CRM --> HIS[8. HIS / EMR - สิทธิ์รักษา/เวชระเบียน]
        INV --> HIS
        HIS --> LIS[9. LIS / External Lab - สั่งตรวจแล็บ]
        HIS --> TELE[10. Telemedicine & Video]
    end
```

### เฟส 1: ข้อมูลหลักและการนำเข้าสินค้า (Data & Inflow Foundations)
เฟสเตรียมข้อมูลและป้อนสินค้าเข้าระบบเพื่อให้มีข้อมูลจริงสำหรับการทำธุรกรรมในเฟสถัดไป
1. **[CRM System](CRM_SYSTEM_PLAN.md) (ระบบลูกค้าสัมพันธ์):** จัดการโปรไฟล์ลูกค้า, คะแนนสะสม, แพ็กเกจการรักษา (เป็นพื้นฐานให้กับ POS และ HIS)
2. **[Procurement / Purchasing System](PROCUREMENT_SYSTEM_PLAN.md) (ระบบจัดซื้อ):** ออกเอกสารขอซื้อ/สั่งซื้อ (PR/PO) เพื่อซื้อสินค้าเข้าคลัง
3. **[Inventory / Stock System](INVENTORY_SYSTEM_PLAN.md) (ระบบคลังสินค้า):** จัดการเก็บสินค้าคงคลัง, ล็อตสินค้า, วันหมดอายุ โดยรับข้อมูลจริงจากใบสั่งซื้อของระบบ Procurement

### เฟส 2: การขายหน้าร้านและการจัดส่ง (Core Commerce & Logistics)
เฟสการออกเอกสารทางการค้าและการเคลื่อนย้ายสินค้าออกนอกองค์กร
4. **[POS System](POS System_plan.md) (ระบบขายหน้าร้าน):** ดึงประวัติลูกค้าจริงจาก CRM และสินค้าในสต็อกจริงจาก Inventory มาทำรายการขายพร้อมตัดสต็อกทันที
5. **[Logistics / Delivery Management](../plans/Delivery_PLAN.md) (ระบบจัดส่ง):** ดึงออเดอร์ยาหรือสินค้าที่ชำระเงินเรียบร้อยแล้วจาก POS/Inventory มาจัดคิวรอบรถและมอบหมายงานให้ไรเดอร์จัดส่งจริง

### เฟส 3: บัญชีการเงินและการจัดการพนักงาน (Finance & HR Operations)
เฟสประเมินผลการดำเนินการและการให้ผลตอบแทนพนักงาน
6. **[Accounting / Finance System](ACCOUNTING_SYSTEM_PLAN.md) (ระบบบัญชี):** รับข้อมูลการชำระเงินจริงจาก POS และยอดค่าใช้จ่ายจัดซื้อจาก Procurement เพื่อบันทึกบัญชีแยกประเภทอัตโนมัติ
7. **[HR System](HR_SYSTEM_PLAN.md) (ระบบทรัพยากรบุคคล):** บันทึกชั่วโมงทำงาน และดึงข้อมูลการขายจริงจาก POS ไปคำนวณค่าคอมมิชชันพนักงานโดยตรง

### เฟส 4: ระบบการแพทย์และการเชื่อมต่อภายนอก (Clinical & Advanced Integrations)
เฟสสุดท้ายที่มีความซับซ้อนสูงและต้องอาศัยฐานข้อมูลคนไข้ (CRM) และคลังยา (Inventory) ในการทดสอบ
8. **[HIS / Clinic Management System](HIS_SYSTEM_PLAN.md) (ระบบบริหารคลินิก/เวชระเบียน EMR):** จัดการคิวคนไข้ (จาก CRM), บันทึกการวินิจฉัย (EMR), และการสั่งยา (โดยตัดคลังยาจาก Inventory)
9. **[LIS / Laboratory Information System (External Lab Integration)](LAB_SYSTEM_PLAN.md) (ระบบแล็บ):** เชื่อมต่อส่งใบสั่งตรวจจาก HIS ไปยังแล็บภายนอก และส่งกลับผลตรวจเข้า EMR
10. **[Telemedicine System](../plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md) & [Video System](../plans/VIDEO_SYSTEM_PLAN.md) (ระบบโทรเวชกรรม):** ให้บริการพบแพทย์ทางไกลผ่าน Video Call บันทึกประวัติเข้า EMR และสั่งยาไปยังห้องยาของ HIS หรือระบบ Logistics ต่อไป

---

## สรุปผลการวิเคราะห์เชิงสถาปัตยกรรมจาก ERP / Delivery / Shopping Cart

จากการประเมินร่วมกันของ `ERP_CORE_ARCHITECTURE.md`, `Delivery_PLAN.md`, และ `SHOPPING_CART_PLAN.md` พบว่าแผนทั้งสามมีทิศทางที่สอดคล้องกัน แต่ยังขาดแกนกลางร่วมที่จำเป็นต่อการขยายระบบให้รองรับ concurrent users จำนวนมากอย่างปลอดภัย โดยเฉพาะในจุดที่เชื่อมระหว่างตะกร้า, คำสั่งซื้อ, สต๊อก, การจัดส่ง, และบัญชี

### ช่องว่างและความเสี่ยงหลัก

- **หลักการตัดสินใจร่วมสำหรับทุกข้อด้านล่าง:** ใช้แนวทาง **PostgreSQL-first + worker ภายในระบบเดิม** เป็นค่าเริ่มต้นก่อนเสมอ และจะเพิ่ม service ภายนอก (เช่น Redis, broker, routing engine, warehouse อื่น) ก็ต่อเมื่อมีตัวเลขโหลดจริงยืนยันว่าจำเป็น เพราะวิธีนี้ปลอดภัย เร็วพอสำหรับระยะเริ่มต้น และต้นทุนต่ำที่สุด

- **Ownership ของออเดอร์ยังไม่ชัด:** ยังแยกไม่เด็ดขาดว่า `cart intent`, `POS order`, `delivery fulfillment`, และ `accounting posting` ใครเป็นเจ้าของสถานะสุดท้ายของธุรกรรม
  - **แนวทางที่แนะนำ (ความปลอดภัย + ความเร็ว):**
    - **Cart Intent** — `Platform` เป็นเจ้าของ canonical ชัดเจน เก็บ snapshot ราคาและสต๊อกตอน checkout ไม่ให้ merchant เปลี่ยนระหว่าง browse → pay
    - **POS Order (Post-Injection)** — `ERP/POS` เป็นเจ้าของ canonical สำหรับ fulfillment (ตัดสต๊อก, จัดส่ง, ออกใบเสร็จ) แต่ `Platform` เก็บ mirror สำหรับลูกค้าดูประวัติ ไม่ต้อง query ข้ามระบบทุกครั้ง
    - **Delivery Fulfillment** — `Logistics Module` เป็น canonical owner ของ tracking state (assigned → picked → delivered) แต่ `POS` เก็บ mirror สำหรับ state สำคัญ (delivered/failed) เพื่อให้ staff ดูใน ERP ได้โดยไม่ต้อง call platform
    - **Accounting Posting** — `Accounting Module` เป็น canonical owner ของ GL entries แต่ `POS` สร้าง outbox event เพื่อ trigger posting แบบ async ลด blocking ตอน checkout
    - **เหตุผล:** แยก canonical vs mirror ช่วยลด cross-system query ตอน peak load, กัน race condition ตอน concurrent checkout, และให้แต่ละโมดูลมี single source of truth ของตัวเอง
- **Phase ordering ยังไม่เป็น canonical เดียว:** เอกสาร ERP ยังมีลำดับการพัฒนาที่อธิบายต่างกันในหลายส่วน ทำให้ dependency ระหว่างโมดูลไม่เป็นมาตรฐานเดียว
  - **ปัญหาที่พบ:**
    - `ERP_CORE_ARCHITECTURE.md` แบ่งเป็น 4 เฟสหยาบ (CRM+Procurement+Inventory → POS+Logistics → Accounting+HR → HIS+LIS+Telemedicine)
    - `POS System_plan.md` แบ่งเป็น 5 เฟสละเอียดของ POS เอง (Mode A → Mode B → Mode C → Invitation → Refund) โดยไม่ระบุว่าอยู่ใน ERP Phase ไหน
    - `CRM_SYSTEM_PLAN.md` แบ่งเป็น 13 เฟสย่อย (Schema → Loyalty → Coupon → Promotion → UI → Member → Follow-up → Appointment Schema → Slot Calculator → Staff UI → Consumer UI → Notification → Reports) โดยไม่ map กับ ERP Phase
    - ผลคือ **มีหลาย "Phase 1" ในหลายเอกสาร** — ทีมพัฒนาไม่รู้ว่าควรเริ่ม POS Phase 1 หรือ CRM Phase 1 ก่อน
  - **แนวทางที่แนะนำ (ความปลอดภัย + ความเร็ว):**
    - ใช้ **ERP Phase เป็น canonical เดียว** ทุกเอกสารย่อยต้องระบุว่าอยู่ใน ERP Phase ไหน และ Step ไหนภายใน Phase นั้น
    - แยกชื่อเฟสย่อยในเอกสารลูกให้ชัดเจน เช่น `ERP Phase 2 / POS Step 1: Mode A Self-Checkout` แทน `POS Phase 1`
    - จัดลำดับตาม **data dependency** ไม่ใช่ตามความสะดวกของทีม — ระบบที่เป็น upstream (Auth, User, Branch, Product/Service master) ต้องเสร็จก่อนระบบที่เป็น downstream (POS, Accounting, Delivery)
    - **ความปลอดภัย:** ถ้า POS ทำก่อนมี CRM/Inventory ที่นิ่ง จะเกิด orphan order (order ที่ไม่มี customer record หรือไม่มี stock data ให้ตัดจริง)
    - **ความเร็ว:** ถ้าแยก phase ชัด ทีมต่างกันสามารถทำงานขนานกันได้ในแต่ละ step โดยไม่ต้องรอทั้งหมดเสร็จ (เช่น POS Step 1 กับ CRM Step 1 ทำพร้อมกันได้ถ้า upstream schema พร้อม)
- **Transaction boundary ยังไม่ครบ:** ยังไม่มีมาตรฐานกลางสำหรับ `idempotency`, `outbox`, `inbox`, `audit log`, และการกัน duplicate write
  - **ปัญหาที่พบ:**
    - `POS System_plan.md` มี flow checkout (สร้าง order → ชำระเงิน → ตัดสต๊อก → คำนวณแต้ม) แต่ไม่ระบุว่าถ้า step 3 ล้มเหลว จะ rollback อย่างไร
    - `SHOPPING_CART_PLAN.md` มีการยิง API "POS Injection" แต่ไม่มี retry policy, timeout handling, หรือ idempotency key
    - `ERP_CORE_ARCHITECTURE.md` มีแนวคิด "Sync Queue" สำหรับ hybrid storage แต่ไม่ระบบว่าเป็น outbox pattern ที่ guarantee delivery หรือไม่
    - ทุกเอกสารไม่มี schema สำหรับ `idempotency_keys`, `outbox_events`, `inbox_events`, `transaction_audit_log`
    - ไม่มี compensation strategy (Saga pattern) สำหรับ long-running transaction เช่น checkout → payment → inventory → delivery → accounting
  - **แนวทางที่แนะนำ (ความปลอดภัย + ความเร็ว):**
    - **ต้นทุนต่ำสุด:** เริ่มจากตารางใน PostgreSQL ชุดเดียว + background worker / cron job ที่มีอยู่ในระบบเดิมก่อน ไม่ต้องเพิ่ม message broker หรือ distributed transaction platform ในรอบแรก
    - **Idempotency Key:** ทุก mutation API (POST/PUT/DELETE) ที่มีผลต่อเงินหรือสต๊อก ต้องรับ `Idempotency-Key` header หรือ `idempotency_key` body param
      - เก็บใน `idempotency_keys` table: `(key_hash, request_payload, response_payload, created_at, expires_at)`
      - ถ้า client ส่ง key ซ้ำ → คืน response เดิมทันที (ไม่ทำงานซ้ำ)
      - **ความปลอดภัย:** กัน double-charge, double-order, double-refund ตอน network retry
      - **ความเร็ว:** ลดโหลดบน downstream เพราะ duplicate request ถูก reject ที่ edge
    - **Outbox Pattern:** แทนการ call API ข้าม module โดยตรง ให้แต่ละ module เขียน event ลง `outbox_events` table ใน **transaction เดียวกับ** business operation
      - Schema: `(id, aggregate_type, aggregate_id, event_type, payload, status, retry_count, created_at, processed_at)`
      - ตัวอย่าง: POS สร้าง order พร้อม insert `outbox_events` (type='order.created') ใน transaction เดียวกัน → commit สำเร็จคือ "order สร้าง + event เก็บ" atomic
      - Background worker อ่าน `outbox_events` ที่ `status='pending'` ส่งไปยัง module ปลายทาง (Accounting, Logistics, Platform) แล้ว update `status='processed'`
      - **ความปลอดภัย:** ถ้า module ปลายทางล่ม event ไม่หาย เพราะยังอยู่ใน outbox รอ retry
      - **ความเร็ว:** POS checkout ไม่ block รอ Accounting/Logistics ทำงาน ทำได้เร็วขึ้นมาก
    - **Inbox Pattern (สำหรับ module รับ event):** module ปลายทางมี `inbox_events` table รับ event แล้ว process แบบ idempotent
      - Schema: `(id, source, event_type, payload, status, processed_at, error_message)`
      - ตัวอย่าง: Accounting รับ 'order.created' → บันทึก inbox → คำนวณ GL → update status='completed'
      - ถ้า process ล้มเหลว → retry ด้วย exponential backoff ไม่เกิน 3 ครั้ง แล้วย้ายไป `dead_letter_events`
      - **ความปลอดภัย:** กัน lost event และกัน process ซ้ำ (idempotent consumer)
      - **ความเร็ว:** module ปลายทาง control จังหวะเอง ไม่ต้อง realtime ตลอด
    - **Audit Log (Append-only):** ทุกการเปลี่ยนแปลงสถานะที่มีผลต่อเงินหรือสต๊อกต้องบันทึก `transaction_audit_log`
      - Schema: `(id, table_name, record_id, action, old_values, new_values, actor_id, actor_type, profession_id, branch_id, session_id, ip_address, user_agent, created_at)`
      - บันทึกทั้ง `old_values` และ `new_values` เป็น JSONB เพื่อให้ diff ย้อนหลังได้
      - ใช้ PostgreSQL trigger หรือ Supabase Realtime ไม่ต้องแก้ business logic ทุกจุด
      - **ความปลอดภัย:** PDPA + ตรวจสอบย้อนหลัง 100% + กัน insider threat
      - **ความเร็ว:** trigger ทำงาน async จาก main transaction ไม่ block business flow
    - **Duplicate Write Prevention (Client + Server):**
      - Client: debounce submit button + local state tracking (e.g. `isSubmitting`)
      - Server: `idempotency_keys` table + unique constraint บน `(idempotency_key, user_id)`
      - Database: `UNIQUE` constraint บน `order_number`, `transaction_ref` และใช้ `ON CONFLICT DO NOTHING/UPDATE` สำหรับ upsert
      - **ความปลอดภัย:** กัน race condition ตอน user กด submit 2 ครั้ง หรือ network retry
      - **ความเร็ว:** `ON CONFLICT` ใน PostgreSQL ทำงานที่ C-level เร็วกว่า check-then-insert ใน application code
    - **Compensation / Saga (สำหรับ Long-running Transaction):**
      - แทนการใช้ distributed transaction (2PC) ที่ slow และ brittle ให้ใช้ Saga pattern
      - ตัวอย่าง checkout flow:
        1. Create order (local transaction) → publish 'order.created'
        2. Reserve inventory (local transaction) → publish 'inventory.reserved'
        3. Process payment (local transaction) → publish 'payment.confirmed'
        4. ถ้า payment failed → trigger compensation: release inventory + cancel order
        5. Post to accounting (async via outbox)
        6. Create delivery order (async via outbox)
      - แต่ละ step เป็น local transaction ที่มี compensation action ชัดเจน
      - **ความปลอดภัย:** ถ้า step กลางล้มเหลว ระบบ rollback แบบ orchestrated ไม่ทิ้ง dirty state
      - **ความเร็ว:** ไม่ต้อง lock resource ข้าม module นาน ๆ แต่ละ step ทำงานเร็วและคืน resource ทันที
- **Inventory safety ยังไม่พอ:** ยังขาด `reservation` และ `stock ledger` ที่ทำให้การขายและ checkout ปลอดภัยต่อ oversell ในช่วงโหลดสูง
  - **ปัญหาที่พบ:**
    - `INVENTORY_SYSTEM_PLAN.md` มีตาราง `inventory_items` ที่เก็บ `quantity` เป็น integer ธรรมดา โดยมี `CHECK (quantity >= 0)` แต่ไม่มีกลไกป้องกัน race condition ตอน concurrent checkout
    - ถ้า checkout 2 รายการพร้อมกัน อ่าน `quantity = 5` ทั้งคู่ แต่ละรายการตัด 3 ชิ้น → ผลลัพธ์ `quantity = 2` (ควรเป็น 2 แต่ถ้าอ่านคนละ snapshot อาจกลายเป็น -1)
    - ไม่มี **reservation** — user ใส่สินค้าในตะกร้าแล้ว stock ยังไม่ถูกจอง ทำให้คนอื่นซื้อไปก่อนแล้ว checkout ไม่สำเร็จ (oversell หรือ out-of-stock ระหว่าง browse → pay)
    - ไม่มี **stock ledger** (append-only movement log) — ถ้ามีการปรับยอด หรือตัดสต๊อกผิดพลาด ตรวจสอบย้อนหลังไม่ได้ว่าเกิดอะไรขึ้น
    - `inventory_items` มี `lot_number` และ `expiry_date` แต่เก็บ quantity รวมเป็นแถวเดียว ทำให้ **FEFO (First Expire First Out)** ทำงานจริงไม่ได้ — ต้องแยกแถวตาม lot ถึงจะตัดล็อตที่ใกล้หมดอายุก่อนได้
    - ไม่มี **warehouse / branch / location** ระดับ stock — `branch_id` อยู่แค่ใน `stocktake_configurations` แต่ไม่มีใน `inventory_items`
    - ไม่มี **available vs reserved vs on-hand** แยกกัน — มีแค่จำนวนรวมเดียว
  - **แนวทางที่แนะนำ (ความปลอดภัย + ความเร็ว):**
    - **แยกแถวตาม Lot (Lot-level stock):** แทนที่จะเก็บ `quantity` รวมในแถวเดียว ให้แยกเป็นแถวตาม lot
      - Schema: `inventory_lots` `(id, profession_id, branch_id, warehouse_location_id, medication_id, lot_number, expiry_date, quantity_on_hand, quantity_reserved, cost_price, selling_price, ...)`
      - `quantity_on_hand` = จำนวนที่มีจริง, `quantity_reserved` = จำนวนที่ถูกจอง (ยังไม่ตัดจริง), `quantity_available = quantity_on_hand - quantity_reserved`
      - **ความปลอดภัย:** FEFO ทำงานได้จริง เพราะแยก lot ชัดเจน ตัดจาก lot ที่ expiry_date ใกล้ที่สุดก่อน
      - **ความเร็ว:** ไม่ต้อง scan หา lot ในข้อมูล JSONB หรือ string เพราะแยก row แล้ว index ได้
    - **Reservation Flow (ก่อนตัดสต๊อกจริง):**
      1. User เพิ่มสินค้าในตะกร้า / กด checkout → ระบบสร้าง `inventory_reservations` record พร้อม `expires_at` (เช่น +15 นาที)
      2. อัปเดต `quantity_reserved` ใน `inventory_lots` ด้วย `SELECT ... FOR UPDATE` หรือ atomic UPDATE
      3. ถ้าชำระเงินสำเร็จ → แปลง reservation เป็น `stock_movement` (type='sale') และลด `quantity_on_hand` + ล้าง `quantity_reserved`
      4. ถ้าชำระเงินล้มเหลว หรือหมดเวลา → release reservation (ลด `quantity_reserved` คืน)
      5. **ความปลอดภัย:** กัน oversell ได้ 100% เพราะ `quantity_available = on_hand - reserved` คำนวณก่อนยอมให้ reserve
      6. **ความเร็ว:** reservation เป็น lightweight operation เร็วกว่าการตัดสต๊อกจริง + สร้าง GL ในขั้นตอนเดียวกัน
    - **Optimistic Locking / Version:** เพิ่ม `version INTEGER DEFAULT 1` ใน `inventory_lots`
      - ทุกการอัปเดตต้อง `UPDATE ... WHERE version = current_version`
      - ถ้า affected rows = 0 → แปลว่ามีคนอัปเดตก่อน → retry หรือ reject
      - **ความปลอดภัย:** กัน lost update ตอน concurrent แต่ไม่ต้อง lock database นาน
      - **ความเร็ว:** ไม่ต้อง `FOR UPDATE` ล็อค row ทิ้งไว้ ลด contention
    - **Stock Ledger (Append-only):** ทุกการเคลื่อนไหวของสต๊อกต้องบันทึก `stock_movements`
      - Schema: `(id, profession_id, branch_id, lot_id, movement_type, quantity, reference_type, reference_id, before_quantity, after_quantity, actor_id, created_at)`
      - `movement_type`: 'receipt', 'sale', 'reservation', 'reservation_release', 'adjustment', 'transfer_in', 'transfer_out', 'return'
      - `before_quantity` และ `after_quantity` บันทึก snapshot ตอนนั้น → ตรวจสอบย้อนหลังได้
      - **ความปลอดภัย:** ถ้ามีการปรับยอดผิด หรือตัดสต๊อกเกิน ดูจาก ledger รู้ทันทีว่าเกิดอะไรขึ้นเมื่อไหร่
      - **ความเร็ว:** append-only ไม่ต้อง UPDATE แถวเดิม ไม่เกิด lock conflict
    - **PostgreSQL Advisory Lock สำหรับ Hot Items (ใช้เฉพาะเมื่อวัด contention สูงจริง):**
      - ถ้ามีสินค้าขายดีที่ contention สูงจริงค่อยใช้ `pg_advisory_lock(profession_id::bigint % 2^31, lot_id_hash)`
      - ล็อคเฉพาะสินค้านั้น ไม่ล็อคตารางทั้งหมด และไม่ต้องเพิ่มระบบภายนอก
      - **ความปลอดภัย:** กัน race condition บน hot item โดยไม่ทำให้สินค้าอื่นช้าลง
      - **ความเร็ว:** advisory lock ทำงานที่ memory ไม่ต้อง scan table
- **Delivery model ยังบาง:** ยังไม่มี state machine, rider assignment, route stop, proof-of-delivery, และ exception handling สำหรับงานขนส่งจริง
  - **ปัญหาที่พบ:**
    - `Delivery_PLAN.md` มีแค่ 2 ตาราง: `delivery_orders` (5 สถานะ: pending → packed → shipping → delivered → cancelled) และ `delivery_tracking` (บันทึกพิกัด)
    - **State machine ไม่ครบ:** ขาด `assigned`, `picked_up`, `at_dropoff`, `failed`, `returned`, `partial_delivery`, `reattempt_scheduled`, `cancelled_by_rider`, `cancelled_by_customer` ทำให้ track ปัญหาจริงไม่ได้
    - **ไม่มี rider model:** มีแค่ `rider_id` ใน `delivery_orders` แต่ไม่มี shift, availability, vehicle type, max capacity, zone coverage, หรือ rating
    - **ไม่มี dispatch / route planning:** ไม่มี `delivery_run`, `route_stop`, `batch_assignment` ถ้ามีออเดอร์หลายใบต้องส่งพร้อมกัน ไรเดอร์ต้องวิ่งไปมาไม่เป็นระบบ
    - **ไม่มี proof-of-delivery (POD):** ไม่มี signature, รูปถ่าย, ชื่อผู้รับ, หมายเหตุ, หรือ verification code ทำให้ dispute ไม่มีหลักฐาน
    - **ไม่มี exception handling:** ถ้าลูกค้าไม่รับ ไรเดอร์รถเสีย หรือที่อยู่ผิด ไม่มี state หรือ workflow รองรับ
    - **ไม่มี 3PL abstraction:** เอกสารบอกรองรับ 3PL แต่ไม่มี adapter model / carrier contract / tracking mapping / carrier API credentials
    - **ค่าส่งยึดระยะทางอย่างเดียว:** ไม่มี fee rule engine สำหรับ zone pricing, weight-based, time-based (rush hour), หรือ surge pricing
    - **ผูกมัดกับ POS มากเกินไป:** `pos_receipt_id` อ้างอิง `pos_receipts` ทำให้ delivery ไม่สามารถสร้างได้ถ้าไม่มี POS receipt (เช่น สั่งผ่าน telemedicine ที่ไม่ผ่าน POS โดยตรง)
    - **ไม่มี delivery scheduling:** ไม่รองรับ ASAP vs time window (เช่น "ส่ง 14:00-16:00") ทำให้ไม่เหมาะกับยาที่ต้องส่งตามเวลานัด
  - **แนวทางที่แนะนำ (ความปลอดภัย + ความเร็ว):**
    - **State Machine แบบเต็มรูปแบบ:** แยก state เป็น 3 ระดับ
      - **Pre-dispatch:** `pending` → `packed` → `ready_for_pickup`
      - **In-transit:** `assigned` → `picked_up` → `in_transit` → `at_dropoff` → `delivered` / `failed_attempt`
      - **Exception:** `failed_attempt` → `reattempt_scheduled` / `returned_to_warehouse` / `cancelled`
      - **ความปลอดภัย:** ทุก state transition ต้องมี validation (เช่น ห้าม `delivered` ถ้ายังไม่ `in_transit`) + audit log บันทึกทุกการเปลี่ยน state
      - **ความเร็ว:** state ชัดเจนทำให้ index บน status มีประสิทธิภาพ ค้นหา "ออเดอร์ที่ต้องจัดส่งวันนี้" ได้เร็ว
    - **Rider / Fleet Model:**
      - `riders` table: `(id, user_id, profession_id, vehicle_type, max_capacity_weight, max_capacity_volume, zone_coverage, is_active, current_status, current_latitude, current_longitude, last_location_at)`
      - `rider_shifts` table: `(id, rider_id, shift_date, start_time, end_time, is_available, max_orders_per_shift)`
      - **ความปลอดภัย:** รู้ว่าไรเดอร์คนไหนพร้อม คนไหนเกิน capacity ไม่ assign ซ้ำ
      - **ความเร็ว:** ค้นหา rider ที่พร้อมใกล้ที่สุดได้ด้วย geospatial index บน `current_latitude, current_longitude`
    - **Dispatch & Route Planning:**
      - `delivery_runs` table: รวมหลายออเดอร์เป็นรอบวิ่งเดียว (batch) พร้อม `estimated_start_time`, `estimated_end_time`, `total_distance_km`
      - `route_stops` table: ลำดับการจัดส่ง `(run_id, stop_sequence, delivery_order_id, estimated_arrival, actual_arrival, status)`
      - ใช้ algorithm ง่าย ๆ สำหรับเริ่มต้น: nearest-neighbor + time window constraint
      - **ความปลอดภัย:** ไรเดอร์ไม่พลาดออเดอร์ เพราะมีลำดับ stop ชัดเจน
      - **ความเร็ว:** batch หลายออเดอร์ลดจำนวนรอบวิ่ง ประหยัดเวลาและน้ำมัน
    - **Proof-of-Delivery (POD):**
      - `proof_of_deliveries` table: `(id, delivery_order_id, delivered_by, recipient_name, recipient_signature_image_url, delivery_photo_url, verification_code_used, notes, latitude, longitude, delivered_at)`
      - ลูกค้าได้รับ SMS/Notification พร้อม verification code ตอนไรเดอร์ถึง
      - ไรเดอร์กรอก code หรือถ่ายรูป + ลายเซ็นเป็นหลักฐาน
      - **ความปลอดภัย:** กัน dispute "ไม่ได้รับของ" มีหลักฐานชัดเจน
      - **ความเร็ว:** ไรเดอร์กรอก code หรือ snap รูป ใช้เวลาไม่ถึง 10 วินาที
    - **Exception Handling Workflow:**
      - `delivery_exceptions` table: `(id, delivery_order_id, exception_type, reason, reported_by, resolved_by, resolution_type, created_at, resolved_at)`
      - `exception_type`: 'recipient_not_home', 'wrong_address', 'vehicle_breakdown', 'damaged_goods', 'refused_delivery', 'rider_emergency'
      - `resolution_type`: 'reattempt_same_day', 'reattempt_next_day', 'return_to_warehouse', 'cancel_and_refund'
      - **ความปลอดภัย:** ทุก exception ต้องมี resolution + บันทึก audit trail
      - **ความเร็ว:** ไรเดอร์ report exception ผ่าน mobile app 1 ครั้ง ระบบ auto-assign resolution workflow
    - **3PL Adapter Layer (เปิดใช้เมื่อมี carrier จริงเท่านั้น):**
      - `carrier_configs` table: `(id, profession_id, carrier_name, carrier_code, api_base_url, api_key_encrypted, is_active, tracking_url_template)`
      - `delivery_orders` เพิ่ม `carrier_id` (NULL = in-house fleet)
      - `carrier_tracking_mappings` table: แปลง tracking status ของ 3PL เป็น canonical Sheserved status
      - **ความปลอดภัย:** API key เก็บ encrypted ไม่เก็บ plain text
      - **ความเร็ว:** ใช้ adapter pattern เปลี่ยน 3PL ได้โดยไม่แก้ business logic และถ้ายังไม่ใช้ 3PL ให้ปิดโมดูลนี้ไว้เพื่อลดต้นทุน
    - **Fee Rule Engine:**
      - `delivery_fee_rules` table: `(id, profession_id, rule_type, zone_polygon, min_distance_km, max_distance_km, min_weight_kg, max_weight_kg, base_fee, per_km_fee, time_multiplier, is_active, priority)`
      - `rule_type`: 'distance', 'zone', 'weight', 'time_window', 'urgency'
      - คำนวณค่าส่งโดยหา rule ที่ match มากที่สุด (highest priority) แล้วรวม base_fee + (distance × per_km_fee) × time_multiplier
      - **ความปลอดภัย:** กันการคิดค่าส่งผิด มี audit trail ทุกการคำนวณ
      - **ความเร็ว:** fee คำนวณครั้งเดียวตอน create delivery order แล้ว snapshot ไว้ ไม่ต้องคำนวณซ้ำทุกครั้งที่ดู
    - **Delivery Scheduling:**
      - `delivery_orders` เพิ่ม `delivery_type` ('asap', 'scheduled') และ `delivery_window_start`, `delivery_window_end`
      - ถ้าเป็น scheduled → ไม่ assign ก่อนถึงเวลา แต่ reserve ไว้ใน rider_shift
      - **ความปลอดภัย:** ยาที่ต้องส่งตามนัด ไม่ถูกส่งก่อนเวลา
      - **ความเร็ว:** ระบบ batch assign ออเดอร์ scheduled ตามเวลา ไม่ต้อง check realtime ตลอด
- **Shopping cart ยังไม่รองรับ split checkout เต็มรูปแบบ:** ยังไม่มี model สำหรับแยก merchant, แยก payment allocation, และ settlement เมื่อ cart เดียวต้องแตกเป็นหลายคำสั่งซื้อ
  - **ปัญหาที่พบ:**
    - `SHOPPING_CART_PLAN.md` มีแค่ 3 ตาราง: `platform_shopping_cart`, `platform_cart_items`, `platform_orders` — ไม่มี `cart_groups`, `cart_merchant_groups`, `checkout_sessions`, `payment_allocations`, `merchant_settlements`
    - `POS System_plan.md` มี `shopping_carts` แยกอีกชุดหนึ่ง (`items` เป็น JSONB) — ส่งผลให้ **มี cart 2 ชุดซ้อนกัน**: platform cart กับ POS Mode A cart
    - `platform_cart_items` เก็บ `unit_price` แบบ current price ไม่ใช่ snapshot price — ถ้า merchant เปลี่ยนราคาระหว่าง user browse กับ checkout จะเกิด price mismatch
    - ไม่มี **cart item snapshot** — ถ้า product ถูกลบหรือเปลี่ยนชื่อหลังจากใส่ตะกร้า จะไม่มีข้อมูล reference ว่าซื้ออะไร
    - ไม่มี **checkout session** — ไม่สามารถ recover ตะกร้าที่กำลังชำระเงินแล้ว browser crash หรือ app ปิด
    - ไม่มี **merchant group / cart split** — ถ้า cart มีสินค้าจาก clinic A + clinic B + platform native ระบบไม่รู้ว่าต้องแตกเป็นกี่ order ย่อย
    - ไม่มี **payment allocation** — รับเงินก้อนเดียว แต่ไม่มี ledger ว่าเงินนี้จะแบ่งให้ใครเท่าไหร่
    - ไม่มี **tax/discount/shipping allocation policy** — ถ้ามีส่วนลดหรือค่าส่งรวม จะกระจายต่อ merchant อย่างไรให้ถูกต้องตามบัญชี
    - ไม่มี **stock reservation จาก cart** — user ใส่ตะกร้าแล้ว stock ยังไม่ถูกจอง ทำให้ oversell ง่ายตอน concurrent สูง
    - `platform_orders` มี `grand_total` กับ `payment_status = 'completed'` แต่ไม่มี `checkout_status` — ไม่รู้ว่าอยู่ขั้นตอนไหน (browsing → checking out → awaiting_payment → paid → split → injected → completed)
  - **แนวทางที่แนะนำ (ความปลอดภัย + ความเร็ว):**
    - **Unified Cart Model (รวม platform + POS):**
      - ยุบ `platform_shopping_cart` และ `shopping_carts` (POS) เป็น `cart_sessions` ชุดเดียว
      - `cart_sessions` เป็นของ Platform (canonical) แต่ POS ดึงมาแสดงผลได้ผ่าน API
      - **ความปลอดภัย:** ไม่มี cart ซ้ำซ้อน ไม่ต้อง sync ข้าม 2 ระบบ
      - **ความเร็ว:** user มี cart เดียว ไม่ว่าจะเข้าผ่านช่องทางไหน
    - **Cart Item Snapshot:**
      - `cart_items` เก็บ `product_snapshot` (JSONB) บันทึกชื่อ, ราคา, ภาพ, หน่วย ตอนที่ใส่ตะกร้า
      - แยก `unit_price_current` (ราคาตอน browse) กับ `unit_price_snapshot` (ราคาตอน snapshot ตอน checkout)
      - **ความปลอดภัย:** กัน price mismatch ตอน checkout ไม่ว่า merchant เปลี่ยนราคาเมื่อไหร่
      - **ความเร็ว:** ไม่ต้อง join product table ตอนแสดงตะกร้า ดึง snapshot ได้เลย
    - **Merchant Group / Cart Split:**
      - `cart_merchant_groups` table: `(id, cart_session_id, merchant_type, merchant_id, subtotal, discount, shipping_fee, tax, grand_total)`
      - `merchant_type`: 'profession' (clinic), 'platform', 'partner'
      - ตอน checkout ระบบ group items ตาม merchant → สร้าง `checkout_merchant_orders` ย่อย
      - **ความปลอดภัย:** แต่ละ merchant order มี total ชัดเจน ตรวจสอบย้อนหลังได้
      - **ความเร็ว:** group ตอน checkout ครั้งเดียว ไม่ต้องคำนวณซ้ำ
    - **Checkout Session:**
      - `checkout_sessions` table: `(id, cart_session_id, user_id, status, initiated_at, expires_at, payment_method, idempotency_key, payment_gateway_session_id)`
      - `status`: 'initiated', 'awaiting_payment', 'payment_confirmed', 'splitting', 'injected', 'completed', 'failed', 'expired'
      - **ความปลอดภัย:** recover ได้ถ้า app crash ระหว่างชำระเงิน ตรวจสอบ duplicate checkout ได้
      - **ความเร็ว:** checkout session เป็น lightweight state machine ตรวจสอบสถานะเร็ว
    - **Payment Allocation & Settlement:**
      - `payment_allocations` table: `(id, checkout_session_id, merchant_type, merchant_id, gross_amount, platform_fee_amount, net_payout_amount, status)`
      - `platform_fee_amount = gross_amount × platform_fee_rate` (snapshot ตอน checkout)
      - `net_payout_amount = gross_amount - platform_fee_amount - shipping_fee_subsidy`
      - `status`: 'pending', 'on_hold', 'released', 'payout_initiated', 'payout_completed'
      - **ความปลอดภัย:** ทุกบาททุกสตางค์มี audit trail ชัดเจนว่าไปไหน
      - **ความเร็ว:** คำนวณ allocation ตอน checkout แล้ว freeze snapshot ไม่ต้องคำนวณซ้ำ
    - **Discount/Shipping/Tax Allocation Policy:**
      - กำหนด policy เป็น setting ใน `cart_merchant_groups`: `discount_allocation_method`
      - `proportional`: แบ่งส่วนลดตามสัดส่วน subtotal ของแต่ละ merchant
      - `merchant_first`: ส่วนลดเป็นของ merchant (ลดจากยอด merchant ก่อนคิด platform fee)
      - `platform_first`: ส่วนลดเป็นของ platform (ลดจากยอดรวมก่อนแล้วแบ่ง)
      - **ความปลอดภัย:** ทุก merchant ได้รับเงินถูกต้องตามที่ตกลง
      - **ความเร็ว:** policy ถูก snapshot ตอน checkout ไม่ต้องคำนวณใหม่ทุกครั้ง
    - **Stock Reservation from Cart:**
      - ตอน user กด " checkout" (ไม่ใช่ตอนใส่ตะกร้า) → ระบบ reserve stock ผ่าน `inventory_reservations` (ดู schema ด้านบน)
      - `cart_session_id` ใน `inventory_reservations` เชื่อมกลับมาที่ cart
      - ถ้า checkout ล้มเหลวหรือหมดเวลา → release reservation
      - **ความปลอดภัย:** กัน oversell 100% ตอน peak concurrent
      - **ความเร็ว:** reserve ตอน checkout (ไม่ตอน add to cart) เพราะ add to cart ไม่ใช่ commitment
- **Read model / analytics layer ยังไม่ชัด:** dashboard, monitoring, และ reporting มีแนวโน้มจะไปดึงจากตาราง transactional โดยตรง ซึ่งเสี่ยงต่อ performance bottleneck
  - **ปัญหาที่พบ:**
    - `KPI_DASHBOARD_PLAN.md` ระบุว่า "ยอด Actual ดึง Query จากระบบอื่น (POS, Accounting)" — แปลว่าทุกครั้งที่ดู dashboard ต้อง query ข้าม `orders` + `pos_receipts` + `accounting_entries` + `inventory_movements` + `delivery_orders` พร้อมกัน
    - ไม่มี **read model / materialized view / projection table** ที่ optimize สำหรับการอ่าน dashboard
    - ไม่มี **caching strategy** สำหรับ KPI data — ทุก request ไปดึงจาก database โดยตรง
    - ไม่มี **async data pipeline** สำหรับ aggregation — ถ้ามีคนดู dashboard พร้อมกัน 10 คน ระบบต้องคำนวณ aggregate ซ้ำ 10 ครั้ง
    - ไม่มี **projection checkpoint** — ถ้ามีการ rebuild dashboard data ระบบไม่รู้ว่าคำนวณถึงไหนแล้ว ต้อง full scan ทุกครั้ง
    - Dashboard query มักต้องใช้ `COUNT(*)`, `SUM()`, `GROUP BY date/branch/employee` บนตารางขนาดใหญ่ — ถ้าไม่มี index หรือ pre-aggregation จะ scan ทั้ง table ทำให้ slow
    - ไม่มี **data retention policy** สำหรับ tracking/audit data — `delivery_tracking` บันทึกพิกัดทุก 5-10 วินาที ถ้าสะสมไม่ลบ ตารางจะโตเร็วมาก
    - ไม่มี **read replica / read-only endpoint** — dashboard query ไปดึงจาก primary database เดียวกับ transaction ทำให้ contention
  - **แนวทางที่แนะนำ (ความปลอดภัย + ความเร็ว):**
    - **CQRS (Command Query Responsibility Segregation):**
      - แยก write model (transactional tables) กับ read model (projection/aggregation tables) อย่างชัดเจน
      - Write model: `orders`, `stock_movements`, `payment_transactions` — optimize สำหรับ ACID + concurrency
      - Read model: `dashboard_snapshots`, `kpi_aggregations`, `reporting_views` — optimize สำหรับ query เร็ว ไม่ต้อง normalize
      - **ความปลอดภัย:** read model ไม่ block write model → ลด lock contention ที่เกิดจาก dashboard query ในช่วง peak
      - **ความเร็ว:** dashboard query ดึงจาก table ที่มีคอลัมน์พร้อมใช้ ไม่ต้อง join/aggregate ทุกครั้ง
    - **Event-driven Projections (ด้วย Outbox):**
      - ใช้ `outbox_events` (จาก Transaction Boundary schema ด้านบน) เป็น trigger
      - ตัวอย่าง: เมื่อมี `order.created` event → projection worker อัปเดต `kpi_aggregations_daily` (revenue, order_count)
      - ตัวอย่าง: เมื่อมี `stock_movement` event → projection worker อัปเดต `inventory_snapshot` (quantity_on_hand รวม)
      - **ความปลอดภัย:** projection update เป็น async ไม่ block checkout flow → ลด latency ตอนขาย
      - **ความเร็ว:** worker คำนวณ aggregation ครั้งเดียว แล้วหลายคนอ่านจากผลลัพธ์ที่เตรียมไว้
    - **Pre-computed Dashboard Snapshots:**
      - `dashboard_snapshots` table: เก็บ KPI ที่คำนวณล่วงหน้า `(id, profession_id, branch_id, snapshot_type, snapshot_date, metrics_json, computed_at, expires_at)`
      - `snapshot_type`: 'daily_revenue', 'daily_orders', 'monthly_profit', 'staff_performance', 'inventory_status', 'delivery_performance'
      - `metrics_json`: `{ "revenue": 150000.00, "order_count": 45, "avg_order_value": 3333.33, "top_product": "..." }`
      - Cron job คำนวณทุก 5-15 นาที แล้ว update snapshot
      - **ความปลอดภัย:** snapshot ถูกคำนวณจาก read model ที่ผ่าน RLS แล้ว ไม่มี data leak
      - **ความเร็ว:** dashboard ดึง snapshot 1 row ใช้เวลา < 10ms แทนที่จะ query + aggregate หลาย table
    - **Projection Checkpoint:**
      - `projection_checkpoints` table: `(id, projection_name, last_event_id, last_processed_at, lag_seconds)`
      - บันทึกว่า projection "daily_revenue" ประมวลผล event ล่าสุดถึง id ไหนแล้ว
      - ถ้า worker restart → อ่าน checkpoint แล้ว resume จากจุดนั้น ไม่ต้อง full scan
      - **ความปลอดภัย:** กัน data loss ถ้า projection worker crash แล้ว restart
      - **ความเร็ว:** resume จากจุดล่าสุด ไม่ต้อง re-process event เก่าทั้งหมด
    - **Caching Layer สำหรับ Dashboard (ทำเมื่อ snapshot ยังไม่พอ):**
      - ค่าเริ่มต้นให้ใช้ `dashboard_snapshots` + materialized view ของ PostgreSQL ก่อน
      - ถ้ายังมี hot path จริงค่อยเพิ่ม Redis / Memcached หรือ PostgreSQL UNLOGGED table สำหรับ snapshot ที่ compute บ่อย
      - Cache key: `dashboard:{profession_id}:{branch_id}:{snapshot_type}:{date}`
      - TTL: 5-15 นาที (ตามความถี่การอัปเดตข้อมูล)
      - **ความปลอดภัย:** cache ไม่เก็บ PII/sensitive data ถ้าไม่จำเป็น หรือ encrypt ถ้าจำเป็น
      - **ความเร็ว:** อ่านจาก cache (memory) เร็วกว่า query database 10-100 เท่า
    - **Materialized Views (สำหรับ Reporting):**
      - สร้าง `MATERIALIZED VIEW` สำหรับรายงานที่ query ช้า เช่น `mv_monthly_sales_by_branch`, `mv_staff_commission_summary`
      - `REFRESH MATERIALIZED VIEW CONCURRENTLY` รันทุก 1-6 ชั่วโมง (ไม่ block read)
      - **ความปลอดภัย:** materialized view ใช้ RLS policy เดียวกับ base table
      - **ความเร็ว:** reporting ดึงจาก view ที่มี index แล้ว ไม่ต้องคำนวณใหม่ทุกครั้ง
    - **Data Retention & Archival:**
      - `delivery_tracking` (location updates) → เก็บแค่ 30 วัน แล้ว archive ไป cold storage หรือ aggregate เป็น `delivery_performance_summary`
      - `transaction_audit_log` → partition รายเดือน ลบ partition เก่า (> 2 ปี) หรือ archive ไป S3/MinIO
      - `stock_movements` → เก็บ raw data 1 ปี แล้วสร้าง `inventory_yearly_summary`
      - **ความปลอดภัย:** archived data ยังเข้าถึงได้ถ้าต้องการ audit แต่ไม่โหลด database
      - **ความเร็ว:** ตารางหลักไม่โตเร็วเกินไป index ยังมีประสิทธิภาพ

### โมเดลร่วมที่ยังควรเพิ่ม

- **Commerce Core:** `Order`, `OrderItem`, `OrderItemSnapshot`, `CheckoutSession`, `PaymentTransaction`, `PaymentAllocation`, `RefundTransaction`, `PriceSnapshot`, `OrderStatusHistory`, `SalesChannel`, `OrderNote`, `OrderHold`, `OrderDiscountLine`, `OrderItemTaxLine`, `PaymentSchedule`, `BillingAttempt`, `ReturnRequestItem`, `Fulfillment`, `FulfillmentItem`, `CustomerWallet`, `WalletTransaction`
- **Reliability Core:** `IdempotencyKey`, `OutboxEvent`, `InboxEvent`, `AuditLog`, `TransactionContext`, `CircuitBreakerState`, `RetryAttempt`, `RateLimitPolicy`, `QueueJobAudit`, `DeadLetterRecord`
- **Inventory Core:** `InventoryLot`, `WarehouseLocation`, `InventoryReservation`, `StockMovement`, `StockLedger`, `StockAdjustment`, `InventoryTransfer`, `StocktakeSession`, `StocktakeLine`, `ReorderSuggestion`, `InventoryAlert`
- **Cart Core:** `CartSession`, `CartItem`, `CartGroup`, `CartMerchantGroup`, `CartPricingRule`, `CartPromotionSnapshot`
- **Delivery Core:** `DeliveryOrder`, `Rider`, `RiderShift`, `DeliveryRun`, `RouteStop`, `ProofOfDelivery`, `DeliveryException`, `CarrierConfig`, `CarrierTrackingMapping`, `DeliveryFeeRule`, `DeliveryTracking`
- **Settlement Core:** `MerchantAccount`, `VendorContract`, `SettlementLedger`, `PayoutBatch`
- **Scale / Read Models:** `ReadModelProjection`, `ProjectionCheckpoint`, `DashboardSnapshot`

### Schema สำหรับ Transaction Boundary
> **สถานะ:** ✅ **Implement แล้ว** (2026-06-12)
> - `idempotency_keys` — อยู่ใน `20260609180000_create_accounting_core_schema.sql`
> - `outbox_events` — อยู่ใน `20260609180000_create_accounting_core_schema.sql`
> - `inbox_events` — อยู่ใน `20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql`
> - `transaction_contexts` — อยู่ใน `20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql`
> - `transaction_audit_log` — อยู่ใน `20260612140000_add_reliability_transaction_tables.sql`
> - `dead_letter_events` — อยู่ใน `20260612140000_add_reliability_transaction_tables.sql`
> - RPC: `record_audit_log`, `create_transaction_context`, `update_transaction_context`
> - Dart models: `TransactionAuditLog`, `InboxEvent` (existing), `TransactionContext` (existing)
> - PhaseZeroRepository methods: `getAuditLogs`, `recordAuditLog`, `createTransactionContext`, `updateTransactionContext`

```sql
-- ============================================
-- 1. IDEMPOTENCY KEYS
-- ============================================
CREATE TABLE idempotency_keys (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_hash      TEXT NOT NULL UNIQUE,                  -- SHA-256 ของ idempotency_key + user_id + endpoint
  user_id       UUID NOT NULL REFERENCES users(id),
  endpoint      TEXT NOT NULL,                         -- เช่น 'POST /api/v1/orders'
  request_payload JSONB,                                 -- เก็บ request ที่ส่งมาครั้งแรก
  response_payload JSONB,                              -- เก็บ response ที่คืนกลับไปครั้งแรก
  status        TEXT NOT NULL DEFAULT 'pending'        -- 'pending', 'completed', 'failed'
                  CHECK (status IN ('pending', 'completed', 'failed')),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + interval '24 hours',
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_idempotency_keys_hash ON idempotency_keys(key_hash);
CREATE INDEX idx_idempotency_keys_expires ON idempotency_keys(expires_at);

-- ============================================
-- 2. OUTBOX EVENTS
-- ============================================
CREATE TABLE outbox_events (
  id              BIGSERIAL PRIMARY KEY,               -- BIGSERIAL เพื่อให้ worker อ่านตามลำดับได้ง่าย
  aggregate_type  TEXT NOT NULL,                       -- 'order', 'payment', 'inventory', 'delivery'
  aggregate_id    UUID NOT NULL,                      -- ID ของ record หลัก (เช่น order.id)
  event_type      TEXT NOT NULL,                      -- 'order.created', 'payment.confirmed', 'inventory.reserved'
  payload         JSONB NOT NULL,                      -- ข้อมูล event ที่ต้องส่ง
  status          TEXT NOT NULL DEFAULT 'pending'     -- 'pending', 'processing', 'processed', 'failed', 'dead_letter'
                    CHECK (status IN ('pending', 'processing', 'processed', 'failed', 'dead_letter')),
  retry_count     INTEGER NOT NULL DEFAULT 0,
  error_message   TEXT,
  target_modules  TEXT[] NOT NULL DEFAULT '{}',       -- ['accounting', 'logistics', 'platform']
  created_at      TIMESTAMPTZ DEFAULT now(),
  processed_at    TIMESTAMPTZ,
  next_retry_at   TIMESTAMPTZ
);
CREATE INDEX idx_outbox_pending ON outbox_events(status, next_retry_at) WHERE status IN ('pending', 'failed');
CREATE INDEX idx_outbox_aggregate ON outbox_events(aggregate_type, aggregate_id);

-- ============================================
-- 3. INBOX EVENTS
-- ============================================
CREATE TABLE inbox_events (
  id              BIGSERIAL PRIMARY KEY,
  source          TEXT NOT NULL,                       -- 'pos', 'platform', 'logistics', 'payment_gateway'
  source_event_id TEXT NOT NULL,                     -- ID ของ event ต้นทาง (กัน process ซ้ำ)
  event_type      TEXT NOT NULL,
  payload         JSONB NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending'   -- 'pending', 'processing', 'completed', 'failed'
                    CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  retry_count     INTEGER NOT NULL DEFAULT 0,
  error_message   TEXT,
  processed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX idx_inbox_source_event ON inbox_events(source, source_event_id);
CREATE INDEX idx_inbox_pending ON inbox_events(status, created_at) WHERE status = 'pending';

-- ============================================
-- 4. DEAD LETTER EVENTS
-- ============================================
CREATE TABLE dead_letter_events (
  id              BIGSERIAL PRIMARY KEY,
  source_table    TEXT NOT NULL,                       -- 'outbox_events' หรือ 'inbox_events'
  source_event_id BIGINT NOT NULL,
  event_type      TEXT NOT NULL,
  payload         JSONB NOT NULL,
  error_message   TEXT NOT NULL,
  retry_count     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 5. TRANSACTION AUDIT LOG (Append-only)
-- ============================================
CREATE TABLE transaction_audit_log (
  id              BIGSERIAL PRIMARY KEY,
  table_name      TEXT NOT NULL,                       -- 'orders', 'inventory_reservations', 'payments'
  record_id       UUID NOT NULL,                      -- ID ของ record ที่ถูกเปลี่ยนแปลง
  action          TEXT NOT NULL                        -- 'INSERT', 'UPDATE', 'DELETE'
                    CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  old_values      JSONB,                               -- ค่าก่อนเปลี่ยนแปลง (NULL สำหรับ INSERT)
  new_values      JSONB,                               -- ค่าหลังเปลี่ยนแปลง (NULL สำหรับ DELETE)
  actor_id        UUID REFERENCES users(id),           -- ใครเป็นคนกระทำ
  actor_type      TEXT NOT NULL DEFAULT 'user'        -- 'user', 'system', 'worker', 'webhook'
                    CHECK (actor_type IN ('user', 'system', 'worker', 'webhook')),
  profession_id   UUID,                                -- tenant isolation
  branch_id       UUID,
  session_id      TEXT,                                -- สำหรับ trace request ข้าม service
  ip_address      INET,
  user_agent      TEXT,
  reason          TEXT,                                -- หมายเหตุการเปลี่ยนแปลง (ถ้ามี)
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_audit_table_record ON transaction_audit_log(table_name, record_id, created_at DESC);
CREATE INDEX idx_audit_profession ON transaction_audit_log(profession_id, created_at DESC);
CREATE INDEX idx_audit_session ON transaction_audit_log(session_id);
CREATE INDEX idx_audit_created_at ON transaction_audit_log(created_at DESC);

-- Partition ตามเวลา (แนะนำสำหรับ production)
-- CREATE TABLE transaction_audit_log_2026_01 PARTITION OF transaction_audit_log
--   FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
```

### Schema สำหรับ Reliability Core
> **สถานะ:** ✅ **Implement แล้ว** (2026-06-12)
> - `circuit_breaker_states` — อยู่ใน `20260612140000_add_reliability_transaction_tables.sql`
> - `retry_attempts` — อยู่ใน `20260612140000_add_reliability_transaction_tables.sql`
> - `rate_limit_policies` — อยู่ใน `20260612140000_add_reliability_transaction_tables.sql`
> - `queue_job_audit` — อยู่ใน `20260612140000_add_reliability_transaction_tables.sql`
> - `dead_letter_records` — อยู่ใน `20260612140000_add_reliability_transaction_tables.sql`
> - RPC: `update_circuit_breaker`, `create_retry_attempt`, `resolve_dead_letter`
> - Dart models: `CircuitBreakerState`, `RetryAttempt`, `DeadLetterRecord`
> - PhaseZeroRepository methods: `getCircuitBreakers`, `updateCircuitBreaker`, `getDeadLetterRecords`, `resolveDeadLetter`, `getRetryAttempts`, `createRetryAttempt`

> **ผลการวิเคราะห์:** เอกสารระบุ `Reliability Core` ประกอบด้วย `IdempotencyKey`, `OutboxEvent`, `InboxEvent`, `AuditLog`, `TransactionContext` แต่ขาดโมเดลที่สำคัญ 3 ประการ:
> 1. **`CircuitBreakerState`** — `payment-queue-service.js` มี implementation จริง (failure count, MAX_FAILURES, auto half-open หลัง 30 นาที) แต่เอกสารไม่มี schema หรือ model รองรับ ทำให้ระบบอื่นไม่สามารถ reuse pattern นี้ได้
> 2. **`RetryAttempt` / `RetryPolicy`** — `queue-config.js` และ BullMQ worker มี retry/backoff (fixed, exponential, linear) แต่ไม่มีตารางเก็บประวัติ retry ข้าม queue หรือ cross-service retry policy ที่เป็น canonical
> 3. **`RateLimitPolicy`** — `rate-limiter.js` มี sliding window counter บน Redis (60 req/min, strict 10 req/min, auth 5 req/min) แต่เอกสารไม่มี model เก็บ rule หรือตาราง audit การถูก block
> 4. **`TransactionContext`** — อยู่ในรายชื่อแต่ไม่มี schema ใดๆ ทั้งที่ระบบมี long-running transaction (checkout → payment → inventory → delivery → accounting) ที่ต้องใช้ Saga pattern
> 5. **`IdempotencyKey`** — เอกสารวาง schema ไว้บน PostgreSQL แต่ implementation จริง (`idempotency.js`) ใช้ Redis (TTL 24 ชม.) ซึ่งเร็วกว่าแต่ไม่ durable ควรมี dual-write หรือ fallback strategy

```sql
-- ============================================
-- 1. TRANSACTION CONTEXTS (Saga / Distributed Transaction)
-- ============================================
CREATE TABLE transaction_contexts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  saga_type         TEXT NOT NULL,                         -- 'checkout', 'refund', 'procurement_approval'
  status            TEXT NOT NULL DEFAULT 'started'
                      CHECK (status IN ('started', 'compensating', 'completed', 'failed', 'cancelled')),
  root_aggregate_type TEXT NOT NULL,                     -- 'order', 'procurement_request'
  root_aggregate_id   UUID NOT NULL,
  steps             JSONB NOT NULL DEFAULT '[]',         -- [{step:'reserve_inventory', status:'completed', started_at, completed_at}, ...]
  compensation_log  JSONB DEFAULT '[]',                  -- บันทึก compensation action ที่ทำไปแล้ว
  started_at        TIMESTAMPTZ DEFAULT now(),
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_transaction_contexts_root ON transaction_contexts(root_aggregate_type, root_aggregate_id);
CREATE INDEX idx_transaction_contexts_status ON transaction_contexts(status, created_at DESC);

-- ============================================
-- 2. CIRCUIT BREAKER STATES
-- ============================================
CREATE TABLE circuit_breaker_states (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  service_name      TEXT NOT NULL,                         -- 'payment_gateway', 'omise', 'promptpay_batch', 'supabase'
  circuit_state     TEXT NOT NULL DEFAULT 'closed'
                      CHECK (circuit_state IN ('closed', 'open', 'half_open')),
  failure_count     INTEGER NOT NULL DEFAULT 0,
  success_count     INTEGER NOT NULL DEFAULT 0,
  last_failure_at   TIMESTAMPTZ,
  last_success_at   TIMESTAMPTZ,
  opened_at         TIMESTAMPTZ,
  half_open_at      TIMESTAMPTZ,
  max_failures      INTEGER NOT NULL DEFAULT 5,
  reset_timeout_sec INTEGER NOT NULL DEFAULT 1800,         -- 30 นาที (ตรงกับ payment-queue-service.js)
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, service_name)
);
CREATE INDEX idx_circuit_breaker_profession ON circuit_breaker_states(profession_id, service_name);

-- ============================================
-- 3. RETRY ATTEMPTS (Cross-Queue / Cross-Service)
-- ============================================
CREATE TABLE retry_attempts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  operation_type    TEXT NOT NULL,                         -- 'payment_transfer', 'inventory_sync', 'email_send'
  target_id         UUID NOT NULL,                         -- ID ของ record ที่ถูก retry (เช่น order_id, transaction_id)
  attempt_number    INTEGER NOT NULL DEFAULT 1,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'success', 'permanent_failure')),
  error_message     TEXT,
  backoff_ms        INTEGER NOT NULL DEFAULT 2000,         -- ตรงกับ queue-config.js DEFAULT_BACKOFF_DELAY_MS
  next_attempt_at   TIMESTAMPTZ,
  succeeded_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_retry_attempts_target ON retry_attempts(operation_type, target_id, attempt_number DESC);
CREATE INDEX idx_retry_attempts_next ON retry_attempts(status, next_attempt_at) WHERE status = 'pending';

-- ============================================
-- 4. RATE LIMIT POLICIES (Configuration + Audit)
-- ============================================
CREATE TABLE rate_limit_policies (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  endpoint_pattern  TEXT NOT NULL,                         -- '/api/orders', '/api/login'
  window_sec        INTEGER NOT NULL DEFAULT 60,
  max_requests      INTEGER NOT NULL DEFAULT 60,
  key_type          TEXT NOT NULL DEFAULT 'ip'
                      CHECK (key_type IN ('ip', 'user_id', 'api_key')),
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_rate_limit_policies_profession ON rate_limit_policies(profession_id, endpoint_pattern);

-- ============================================
-- 5. QUEUE JOB AUDIT (BullMQ / Background Worker Traceability)
-- ============================================
CREATE TABLE queue_job_audit (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  queue_name        TEXT NOT NULL,                         -- 'payment-transfers', 'donation-escrow', 'sync-queue'
  job_id            TEXT NOT NULL,                         -- BullMQ job ID
  job_name          TEXT NOT NULL,
  job_data          JSONB,
  status            TEXT NOT NULL
                      CHECK (status IN ('queued', 'processing', 'completed', 'failed', 'dead_letter')),
  attempts_made     INTEGER NOT NULL DEFAULT 0,
  error_message     TEXT,
  worker_host       TEXT,                                  -- hostname ของ worker ที่ process
  started_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_queue_job_audit_queue ON queue_job_audit(queue_name, status);
CREATE INDEX idx_queue_job_audit_profession ON queue_job_audit(profession_id, created_at DESC);

-- ============================================
-- 6. DEAD LETTER RECORDS (Formalized)
-- ============================================
CREATE TABLE dead_letter_records (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  source_queue      TEXT NOT NULL,                         -- ชื่อ queue ต้นทาง
  original_job_id   TEXT,
  aggregate_type    TEXT NOT NULL,                         -- 'order', 'payment', 'inventory'
  aggregate_id      UUID NOT NULL,
  event_type        TEXT NOT NULL,
  payload           JSONB NOT NULL,
  error_message     TEXT NOT NULL,
  retry_count       INTEGER NOT NULL DEFAULT 0,
  resolution        TEXT DEFAULT 'unresolved'
                      CHECK (resolution IN ('unresolved', 'manual_retry', 'compensated', 'ignored')),
  resolved_by       UUID REFERENCES users(id),
  resolved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_dead_letter_unresolved ON dead_letter_records(resolution, created_at) WHERE resolution = 'unresolved';
CREATE INDEX idx_dead_letter_aggregate ON dead_letter_records(aggregate_type, aggregate_id);
```

### Schema สำหรับ Tax & Fiscal Document Core (แนะนำ)
> **สถานะ:** 🔴 ยังไม่ implement — เป็น schema แนะนำสำหรับอนาคต (ใบกำกับภาษี, ใบลดหนี้, ใบเพิ่มหนี้)

> **ผลการวิเคราะห์:** POS System ปัจจุบันเก็บ `vat_amount` และ `wht_amount` เป็น column รวมใน `orders` ซึ่งไม่เพียงพอต่อการออกเอกสารภาษีตามกฎหมายไทย (ใบกำกับภาษี, ใบลดหนี้, ใบเพิ่มหนี้) และไม่รองรับการแยกเอกสารภาษีหลายฉบับต่อหนึ่ง order (เช่น แยกเบิกบริษัท/ส่วนตัว) หรือการตรวจสอบย้อนหลัง (Audit Trail) รายบรรทัด VAT ดังนั้นต้องมี Tax & Fiscal Document Core แยกเป็นเอกสารอิสระจาก order

```sql
-- ============================================
-- 1. ORDER ITEM TAX LINES (VAT breakdown รายบรรทัด)
-- ============================================
CREATE TABLE order_item_tax_lines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id),
  branch_id       UUID REFERENCES organization_branches(id),
  order_item_id   UUID NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  tax_type        TEXT NOT NULL DEFAULT 'vat'
                    CHECK (tax_type IN ('vat', 'wht', 'specific_tax', 'excise_tax')),
  tax_rate        DECIMAL(5,4) NOT NULL DEFAULT 0.0700,     -- เช่น 0.0700 = 7%
  tax_base_amount DECIMAL(12,2) NOT NULL DEFAULT 0,          -- ฐานภาษี
  tax_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,          -- มูลค่าภาษี
  is_inclusive    BOOLEAN NOT NULL DEFAULT true,             -- true = VAT inclusive (ราคารวมภาษี)
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_order_item_tax_lines_item ON order_item_tax_lines(order_item_id);
CREATE INDEX idx_order_item_tax_lines_profession ON order_item_tax_lines(profession_id);

-- ============================================
-- 2. TAX INVOICES (ใบกำกับภาษี)
-- ============================================
CREATE TABLE tax_invoices (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  order_id          UUID REFERENCES orders(id),              -- NULL ถ้าออกแยกจาก order (manual)
  invoice_number    TEXT NOT NULL,                            -- เช่น TIV-20260609-0001
  invoice_type      TEXT NOT NULL DEFAULT 'tax_invoice'       -- 'tax_invoice', 'abbreviated_tax_invoice'
                    CHECK (invoice_type IN ('tax_invoice', 'abbreviated_tax_invoice')),
  status            TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'cancelled', 'voided')),
  buyer_name        TEXT NOT NULL,
  buyer_tax_id      TEXT,                                     -- เลขประจำตัวผู้เสียภาษีผู้ซื้อ
  buyer_branch_code TEXT DEFAULT '00000',                      -- รหัสสาขาผู้ซื้อ
  buyer_address     TEXT,
  total_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  vat_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_with_vat    DECIMAL(12,2) NOT NULL DEFAULT 0,        -- รวมภาษี
  issue_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  issue_datetime    TIMESTAMPTZ DEFAULT now(),
  cancelled_at      TIMESTAMPTZ,
  cancelled_reason  TEXT,
  e_invoice_uuid    UUID,                                     -- สำหรับเชื่อม e-Tax Invoice ของกรมสรรพากร
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, invoice_number)
);
CREATE INDEX idx_tax_invoices_order ON tax_invoices(order_id);
CREATE INDEX idx_tax_invoices_profession ON tax_invoices(profession_id, issue_date DESC);
CREATE INDEX idx_tax_invoices_einvoice ON tax_invoices(e_invoice_uuid) WHERE e_invoice_uuid IS NOT NULL;

-- ============================================
-- 3. TAX INVOICE ITEMS
-- ============================================
CREATE TABLE tax_invoice_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tax_invoice_id    UUID NOT NULL REFERENCES tax_invoices(id) ON DELETE CASCADE,
  order_item_id     UUID REFERENCES order_items(id),          -- NULL ถ้าเป็นรายการเพิ่มเติมด้วยตนเอง
  item_name         TEXT NOT NULL,
  item_description  TEXT,
  quantity          DECIMAL(12,4) NOT NULL DEFAULT 1,
  unit_price        DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_price       DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
  vat_rate          DECIMAL(5,4) NOT NULL DEFAULT 0.0700,
  vat_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
  net_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,        -- ราคาสุทธิหลังหักส่วนลด + VAT
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_tax_invoice_items_invoice ON tax_invoice_items(tax_invoice_id);

-- ============================================
-- 4. RECEIPTS (ใบเสร็จรับเงิน / Simplified Receipt)
-- ============================================
CREATE TABLE receipts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  order_id          UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  receipt_number    TEXT NOT NULL,
  receipt_type      TEXT NOT NULL DEFAULT 'cash_receipt'
                    CHECK (receipt_type IN ('cash_receipt', 'official_receipt')),
  status            TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'cancelled')),
  total_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  payment_method    TEXT,
  issued_by         UUID REFERENCES users(id),
  issue_datetime    TIMESTAMPTZ DEFAULT now(),
  cancelled_at      TIMESTAMPTZ,
  cancelled_reason  TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, receipt_number)
);
CREATE INDEX idx_receipts_order ON receipts(order_id);
CREATE INDEX idx_receipts_profession ON receipts(profession_id, issue_datetime DESC);

-- ============================================
-- 5. CREDIT NOTES (ใบลดหนี้)
-- ============================================
CREATE TABLE credit_notes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  tax_invoice_id    UUID NOT NULL REFERENCES tax_invoices(id), -- อ้างอิงใบกำกับภาษีต้นทาง
  order_id          UUID REFERENCES orders(id),
  credit_note_number TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('draft', 'active', 'cancelled')),
  reason            TEXT NOT NULL,                             -- เหตุผลการลดหนี้
  original_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,        -- มูลค่าเดิม
  credit_amount     DECIMAL(12,2) NOT NULL DEFAULT 0,        -- มูลค่าลดหนี้
  vat_adjustment    DECIMAL(12,2) NOT NULL DEFAULT 0,        -- ปรับปรุง VAT
  issue_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  issue_datetime    TIMESTAMPTZ DEFAULT now(),
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, credit_note_number)
);
CREATE INDEX idx_credit_notes_invoice ON credit_notes(tax_invoice_id);
CREATE INDEX idx_credit_notes_profession ON credit_notes(profession_id, issue_date DESC);

-- ============================================
-- 6. DEBIT NOTES (ใบเพิ่มหนี้)
-- ============================================
CREATE TABLE debit_notes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  tax_invoice_id    UUID NOT NULL REFERENCES tax_invoices(id),
  order_id          UUID REFERENCES orders(id),
  debit_note_number TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('draft', 'active', 'cancelled')),
  reason            TEXT NOT NULL,
  original_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
  debit_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  vat_adjustment    DECIMAL(12,2) NOT NULL DEFAULT 0,
  issue_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  issue_datetime    TIMESTAMPTZ DEFAULT now(),
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, debit_note_number)
);
CREATE INDEX idx_debit_notes_invoice ON debit_notes(tax_invoice_id);
CREATE INDEX idx_debit_notes_profession ON debit_notes(profession_id, issue_date DESC);
```

### Schema สำหรับ Inventory Safety (แนะนำ)
> **สถานะ:** ⏳ บางส่วน implement — `warehouse_locations`, `inventory_lots`, `stock_movements` อยู่ใน migration Phase 1; ฟังก์ชัน `reserve_stock`, `deduct_stock` ยังไม่ migrate

```sql
-- ============================================
-- 1. WAREHOUSE / STOCK LOCATIONS
-- ============================================
CREATE TABLE warehouse_locations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id),
  branch_id       UUID REFERENCES organization_branches(id),
  location_code   TEXT NOT NULL,                       -- 'WH-MAIN', 'WH-FRONT', 'PHARMACY-ROOM'
  location_name   TEXT NOT NULL,
  location_type   TEXT NOT NULL DEFAULT 'warehouse'   -- 'warehouse', 'shelf', 'fridge', 'counter'
                    CHECK (location_type IN ('warehouse', 'shelf', 'fridge', 'counter', 'dispensary')),
  is_active       BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, location_code)
);

-- ============================================
-- 2. INVENTORY LOTS (Lot-level stock)
-- ============================================
CREATE TABLE inventory_lots (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id),
  branch_id             UUID REFERENCES organization_branches(id),
  warehouse_location_id UUID REFERENCES warehouse_locations(id),
  medication_id         UUID REFERENCES medications(id),
  custom_medication_id  UUID REFERENCES custom_medications(id),
  lot_number            TEXT NOT NULL,
  expiry_date           DATE NOT NULL,
  quantity_on_hand      INTEGER NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
  quantity_reserved     INTEGER NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  cost_price            DECIMAL(12,2) DEFAULT 0,
  selling_price         DECIMAL(12,2) DEFAULT 0,
  is_vatable            BOOLEAN DEFAULT false,
  version               INTEGER NOT NULL DEFAULT 1,    -- Optimistic locking
  is_active             BOOLEAN DEFAULT true,          -- false = ถ้า lot หมดแล้วปิด
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),

  -- ต้องมี medication_id หรือ custom_medication_id อย่างใดอย่างหนึ่ง
  CONSTRAINT check_lot_medication_source CHECK (
    (medication_id IS NOT NULL AND custom_medication_id IS NULL) OR
    (medication_id IS NULL AND custom_medication_id IS NOT NULL)
  )
);
CREATE INDEX idx_inventory_lots_profession ON inventory_lots(profession_id);
CREATE INDEX idx_inventory_lots_medication ON inventory_lots(medication_id);
CREATE INDEX idx_inventory_lots_custom ON inventory_lots(custom_medication_id);
CREATE INDEX idx_inventory_lots_expiry ON inventory_lots(expiry_date);
CREATE INDEX idx_inventory_lots_available ON inventory_lots(profession_id, medication_id)
  WHERE is_active = true AND (quantity_on_hand - quantity_reserved) > 0;

-- ============================================
-- 3. INVENTORY RESERVATIONS
-- ============================================
CREATE TABLE inventory_reservations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id),
  branch_id       UUID REFERENCES organization_branches(id),
  lot_id          UUID NOT NULL REFERENCES inventory_lots(id),
  order_id        UUID REFERENCES orders(id),          -- ถ้ามี order แล้ว
  cart_session_id UUID,                                -- ถ้ายังไม่มี order (ระหว่าง checkout)
  quantity        INTEGER NOT NULL CHECK (quantity > 0),
  status          TEXT NOT NULL DEFAULT 'active'     -- 'active', 'converted', 'expired', 'cancelled'
                    CHECK (status IN ('active', 'converted', 'expired', 'cancelled')),
  expires_at      TIMESTAMPTZ NOT NULL,                -- เช่น now() + interval '15 minutes'
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_reservations_active ON inventory_reservations(status, expires_at)
  WHERE status = 'active';
CREATE INDEX idx_reservations_lot ON inventory_reservations(lot_id, status);
CREATE INDEX idx_reservations_order ON inventory_reservations(order_id);

-- ============================================
-- 4. STOCK MOVEMENTS (Append-only ledger)
-- ============================================
CREATE TABLE stock_movements (
  id              BIGSERIAL PRIMARY KEY,
  profession_id   UUID NOT NULL REFERENCES professions(id),
  branch_id       UUID REFERENCES organization_branches(id),
  lot_id          UUID NOT NULL REFERENCES inventory_lots(id),
  movement_type   TEXT NOT NULL                         -- 'receipt', 'sale', 'reservation', 'reservation_release', 'adjustment', 'transfer_in', 'transfer_out', 'return', 'expired', 'damaged'
                    CHECK (movement_type IN ('receipt', 'sale', 'reservation', 'reservation_release', 'adjustment', 'transfer_in', 'transfer_out', 'return', 'expired', 'damaged')),
  quantity        INTEGER NOT NULL,                    -- บวก = เข้า, ลบ = ออก
  before_quantity INTEGER NOT NULL,
  after_quantity  INTEGER NOT NULL,
  reference_type  TEXT,                                -- 'order', 'purchase_order', 'transfer', 'adjustment', 'prescription'
  reference_id    UUID,                                -- ID ของ record ต้นทาง
  actor_id        UUID REFERENCES users(id),           -- ใครเป็นคนกระทำ
  actor_type      TEXT NOT NULL DEFAULT 'user'
                    CHECK (actor_type IN ('user', 'system', 'worker')),
  reason          TEXT,                                -- หมายเหตุ (สำหรับ adjustment)
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_stock_movements_lot ON stock_movements(lot_id, created_at DESC);
CREATE INDEX idx_stock_movements_profession ON stock_movements(profession_id, created_at DESC);
CREATE INDEX idx_stock_movements_reference ON stock_movements(reference_type, reference_id);

-- ============================================
-- 5. FUNCTIONS สำหรับ Inventory Operations
-- ============================================

-- คำนวณ available quantity ของ lot
CREATE OR REPLACE FUNCTION calculate_available_quantity(p_lot_id UUID)
RETURNS INTEGER AS $$
DECLARE
  v_on_hand INTEGER;
  v_reserved INTEGER;
BEGIN
  SELECT quantity_on_hand, quantity_reserved
  INTO v_on_hand, v_reserved
  FROM inventory_lots
  WHERE id = p_lot_id;

  RETURN COALESCE(v_on_hand, 0) - COALESCE(v_reserved, 0);
END;
$$ LANGUAGE plpgsql;

-- Reserve stock ด้วย optimistic locking
CREATE OR REPLACE FUNCTION reserve_stock(
  p_lot_id UUID,
  p_quantity INTEGER,
  p_cart_session_id UUID DEFAULT NULL,
  p_order_id UUID DEFAULT NULL,
  p_expires_minutes INTEGER DEFAULT 15
)
RETURNS UUID AS $$
DECLARE
  v_available INTEGER;
  v_reservation_id UUID;
BEGIN
  -- ตรวจสอบ available quantity
  SELECT calculate_available_quantity(p_lot_id) INTO v_available;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock: available %, requested %', v_available, p_quantity;
  END IF;

  -- สร้าง reservation record
  INSERT INTO inventory_reservations (
    profession_id, branch_id, lot_id, cart_session_id, order_id,
    quantity, status, expires_at
  )
  SELECT
    profession_id, branch_id, id, p_cart_session_id, p_order_id,
    p_quantity, 'active', now() + (p_expires_minutes || ' minutes')::interval
  FROM inventory_lots
  WHERE id = p_lot_id
  RETURNING id INTO v_reservation_id;

  -- อัปเดต quantity_reserved
  UPDATE inventory_lots
  SET quantity_reserved = quantity_reserved + p_quantity,
      version = version + 1
  WHERE id = p_lot_id;

  -- บันทึก ledger
  INSERT INTO stock_movements (
    profession_id, branch_id, lot_id, movement_type, quantity,
    before_quantity, after_quantity, reference_type, reference_id, actor_type, reason
  )
  SELECT
    profession_id, branch_id, id, 'reservation', p_quantity,
    quantity_on_hand + quantity_reserved - p_quantity, quantity_on_hand + quantity_reserved,
    CASE WHEN p_order_id IS NOT NULL THEN 'order' ELSE 'cart' END,
    COALESCE(p_order_id, p_cart_session_id),
    'system',
    'Stock reserved for checkout'
  FROM inventory_lots
  WHERE id = p_lot_id;

  RETURN v_reservation_id;
END;
$$ LANGUAGE plpgsql;

-- Release reservation (เมื่อ checkout ล้มเหลว หรือหมดเวลา)
CREATE OR REPLACE FUNCTION release_stock_reservation(p_reservation_id UUID)
RETURNS VOID AS $$
DECLARE
  v_lot_id UUID;
  v_quantity INTEGER;
  v_before_qoh INTEGER;
  v_before_res INTEGER;
BEGIN
  SELECT lot_id, quantity
  INTO v_lot_id, v_quantity
  FROM inventory_reservations
  WHERE id = p_reservation_id AND status = 'active';

  IF NOT FOUND THEN
    RETURN; -- ไม่มี reservation ที่ active อยู่
  END IF;

  SELECT quantity_on_hand, quantity_reserved
  INTO v_before_qoh, v_before_res
  FROM inventory_lots WHERE id = v_lot_id;

  -- ลด quantity_reserved
  UPDATE inventory_lots
  SET quantity_reserved = GREATEST(quantity_reserved - v_quantity, 0),
      version = version + 1
  WHERE id = v_lot_id;

  -- อัปเดต reservation status
  UPDATE inventory_reservations
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_reservation_id;

  -- บันทึก ledger
  INSERT INTO stock_movements (
    profession_id, branch_id, lot_id, movement_type, quantity,
    before_quantity, after_quantity, reference_type, reference_id, actor_type, reason
  )
  SELECT
    profession_id, branch_id, id, 'reservation_release', v_quantity,
    v_before_qoh + v_before_res, v_before_qoh + (v_before_res - v_quantity),
    'reservation', p_reservation_id,
    'system',
    'Reservation released (payment failed or expired)'
  FROM inventory_lots
  WHERE id = v_lot_id;
END;
$$ LANGUAGE plpgsql;

-- Deduct stock (เมื่อชำระเงินสำเร็จ แปลง reservation เป็น sale)
CREATE OR REPLACE FUNCTION deduct_stock(
  p_reservation_id UUID,
  p_order_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_lot_id UUID;
  v_quantity INTEGER;
  v_before_qoh INTEGER;
BEGIN
  SELECT lot_id, quantity
  INTO v_lot_id, v_quantity
  FROM inventory_reservations
  WHERE id = p_reservation_id AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active reservation % not found', p_reservation_id;
  END IF;

  SELECT quantity_on_hand INTO v_before_qoh
  FROM inventory_lots WHERE id = v_lot_id;

  -- ลด quantity_on_hand และ quantity_reserved พร้อมกัน
  UPDATE inventory_lots
  SET quantity_on_hand = quantity_on_hand - v_quantity,
      quantity_reserved = GREATEST(quantity_reserved - v_quantity, 0),
      version = version + 1
  WHERE id = v_lot_id;

  -- อัปเดต reservation → converted
  UPDATE inventory_reservations
  SET status = 'converted', order_id = p_order_id, updated_at = now()
  WHERE id = p_reservation_id;

  -- บันทึก ledger
  INSERT INTO stock_movements (
    profession_id, branch_id, lot_id, movement_type, quantity,
    before_quantity, after_quantity, reference_type, reference_id, actor_type, reason
  )
  SELECT
    profession_id, branch_id, id, 'sale', -v_quantity,
    v_before_qoh, v_before_qoh - v_quantity,
    'order', p_order_id,
    'system',
    'Stock deducted after successful payment'
  FROM inventory_lots
  WHERE id = v_lot_id;
END;
$$ LANGUAGE plpgsql;

-- Job ล้าง reservation ที่หมดอายุ (รันทุก 5 นาที)
CREATE OR REPLACE FUNCTION cleanup_expired_reservations()
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT id FROM inventory_reservations
    WHERE status = 'active' AND expires_at < now()
  LOOP
    PERFORM release_stock_reservation(r.id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql;
```

### Schema สำหรับ Inventory Core — โมเดลที่ขาดหาย
> **สถานะ:** ✅ **Implement แล้ว** (2026-06-12)
> - `stock_adjustments` — อยู่ใน `20260612150000_add_inventory_system.sql`
> - `inventory_transfers` + `inventory_transfer_lines` — อยู่ใน `20260612150000_add_inventory_system.sql`
> - `stocktake_sessions` + `stocktake_lines` — อยู่ใน `20260612150000_add_inventory_system.sql`
> - `inventory_alerts` (low_stock, expiry, reorder) — อยู่ใน `20260612150000_add_inventory_system.sql`
> - `custom_medications` (tenant-specific products) — อยู่ใน `20260612150000_add_inventory_system.sql`
> - `inventory_items` (stock summary + cost/selling/reorder_point) — อยู่ใน `20260612150000_add_inventory_system.sql`
> - RPC: `deduct_inventory_fefo`, `create_stock_adjustment`, `create_inventory_transfer`, `complete_inventory_transfer`, `check_inventory_alerts`, `complete_stocktake_session`
> - Dart models: `InventoryItem`, `CustomMedication`, `StocktakeConfiguration`, `StocktakeSession`, `StocktakeLine`, `StockAdjustment`, `InventoryTransfer`, `InventoryTransferLine`, `InventoryAlert`
> - PhaseOneRepository + PhaseOneNotifier methods ครบ CRUD + FEFO deduction

> **ผลการวิเคราะห์เดิม:** ขาดโมเดลสำคัญ 6 ประการที่ทำให้ระบบ Inventory ไม่สามารถทำงาน end-to-end ได้
> ✅ **แก้ไขแล้ว:**
> 1. **`StockAdjustment`** — `stock_adjustments` table + `create_stock_adjustment()` RPC + `StockAdjustment` model + `PhaseOneRepository.createStockAdjustment()`
> 2. **`InventoryTransfer`** — `inventory_transfers` + `inventory_transfer_lines` + `create_inventory_transfer()` + `complete_inventory_transfer()` + `InventoryTransfer` model
> 3. **`StocktakeSession` / `StocktakeLine`** — `stocktake_sessions` + `stocktake_lines` + `complete_stocktake_session()` RPC + `StocktakeSession`, `StocktakeLine` models
> 4. **`InventoryAlert`** — `inventory_alerts` + `check_inventory_alerts()` RPC + `InventoryAlert` model
> 5. **`inventory_items` vs `inventory_lots`** — สร้าง `inventory_items` ใหม่เป็น stock summary (quantity, cost_price, selling_price, reorder_point) โดย `inventory_lots` ยังคงเป็น lot-level detail สำหรับ FEFO deduction
> 6. **Flutter Implementation** — `PhaseOneRepository` + `PhaseOneNotifier` ครบ CRUD สำหรับทุก table ใหม่ + FEFO deduction helper

```sql
-- ============================================
-- 1. STOCK ADJUSTMENTS (Parent record สำหรับการปรับยอด)
-- ============================================
CREATE TABLE stock_adjustments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id),
  branch_id       UUID REFERENCES organization_branches(id),
  adjustment_type TEXT NOT NULL DEFAULT 'cycle_count'
                      CHECK (adjustment_type IN ('cycle_count', 'damaged', 'expired', 'lost', 'found', 'system_correction')),
  status          TEXT NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'approved', 'rejected', 'posted')),
  total_quantity_change INTEGER NOT NULL DEFAULT 0,   -- ผลรวม quantity change (บวก/ลบ)
  reason          TEXT NOT NULL,                         -- เหตุผลการปรับยอด
  requested_by    UUID NOT NULL REFERENCES users(id),
  approved_by     UUID REFERENCES users(id),
  posted_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_stock_adjustments_profession ON stock_adjustments(profession_id, status);
CREATE INDEX idx_stock_adjustments_created ON stock_adjustments(created_at DESC);

-- ============================================
-- 2. STOCK ADJUSTMENT LINES (รายการ lot ที่ถูกปรับในแต่ละครั้ง)
-- ============================================
CREATE TABLE stock_adjustment_lines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  adjustment_id   UUID NOT NULL REFERENCES stock_adjustments(id) ON DELETE CASCADE,
  lot_id          UUID NOT NULL REFERENCES inventory_lots(id),
  expected_quantity INTEGER NOT NULL DEFAULT 0,          -- จำนวนตามระบบก่อนปรับ
  actual_quantity   INTEGER NOT NULL DEFAULT 0,          -- จำนวนที่นับได้จริง
  quantity_change   INTEGER NOT NULL,                    -- actual - expected (บวก = เพิ่ม, ลบ = ลด)
  reason          TEXT,                                  -- เหตุผลรายบรรทัด (ถ้าแตกต่างจาก parent)
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_adjustment_lines_adjustment ON stock_adjustment_lines(adjustment_id);
CREATE INDEX idx_adjustment_lines_lot ON stock_adjustment_lines(lot_id);

-- ============================================
-- 3. INVENTORY TRANSFERS (คำสั่งโยกย้ายสินค้าระหว่าง location/branch)
-- ============================================
CREATE TABLE inventory_transfers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  from_branch_id    UUID REFERENCES organization_branches(id),
  to_branch_id      UUID REFERENCES organization_branches(id),
  from_location_id  UUID REFERENCES warehouse_locations(id),
  to_location_id    UUID REFERENCES warehouse_locations(id),
  transfer_number   TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'in_transit', 'received', 'rejected', 'cancelled')),
  requested_by      UUID NOT NULL REFERENCES users(id),
  approved_by       UUID REFERENCES users(id),
  received_by       UUID REFERENCES users(id),
  shipped_at        TIMESTAMPTZ,
  received_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, transfer_number)
);
CREATE INDEX idx_inventory_transfers_profession ON inventory_transfers(profession_id, status);
CREATE INDEX idx_inventory_transfers_status ON inventory_transfers(status, created_at DESC);

-- ============================================
-- 4. INVENTORY TRANSFER LINES
-- ============================================
CREATE TABLE inventory_transfer_lines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id     UUID NOT NULL REFERENCES inventory_transfers(id) ON DELETE CASCADE,
  lot_id          UUID NOT NULL REFERENCES inventory_lots(id),
  quantity        INTEGER NOT NULL CHECK (quantity > 0),
  received_quantity INTEGER DEFAULT 0,                   -- จำนวนที่รับจริง (อาจไม่ตรงกับที่ส่ง)
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_transfer_lines_transfer ON inventory_transfer_lines(transfer_id);

-- ============================================
-- 5. STOCKTAKE SESSIONS (รอบการตรวจนับสต๊อก)
-- ============================================
CREATE TABLE stocktake_sessions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  session_name      TEXT NOT NULL,                         -- เช่น 'Monthly Count June 2026'
  frequency_type    TEXT NOT NULL DEFAULT 'custom'         -- 'weekly', 'monthly', 'yearly', 'custom', 'adhoc'
                      CHECK (frequency_type IN ('weekly', 'monthly', 'yearly', 'custom', 'adhoc')),
  status            TEXT NOT NULL DEFAULT 'draft'
                      CHECK (status IN ('draft', 'counting', 'reviewing', 'adjusted', 'cancelled')),
  planned_date      DATE NOT NULL,
  started_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ,
  conducted_by      UUID REFERENCES users(id),
  reviewed_by       UUID REFERENCES users(id),
  adjustment_id     UUID REFERENCES stock_adjustments(id), -- ถ้าสร้าง adjustment แล้ว
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_stocktake_sessions_profession ON stocktake_sessions(profession_id, status);
CREATE INDEX idx_stocktake_sessions_planned ON stocktake_sessions(planned_date);

-- ============================================
-- 6. STOCKTAKE LINES (ผลการนับแต่ละ lot)
-- ============================================
CREATE TABLE stocktake_lines (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id        UUID NOT NULL REFERENCES stocktake_sessions(id) ON DELETE CASCADE,
  lot_id            UUID NOT NULL REFERENCES inventory_lots(id),
  expected_quantity INTEGER NOT NULL DEFAULT 0,          -- จำนวนตามระบบ
  counted_quantity  INTEGER,                             -- จำนวนที่นับได้ (NULL = ยังไม่นับ)
  variance          INTEGER GENERATED ALWAYS AS (COALESCE(counted_quantity, 0) - expected_quantity) STORED,
  is_recounted      BOOLEAN DEFAULT false,               -- true ถ้านับซ้ำแล้ว
  counted_by        UUID REFERENCES users(id),
  counted_at        TIMESTAMPTZ,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_stocktake_lines_session ON stocktake_lines(session_id);
CREATE INDEX idx_stocktake_lines_variance ON stocktake_lines(session_id) WHERE variance != 0;

-- ============================================
-- 7. REORDER SUGGESTIONS (Automated procurement trigger)
-- ============================================
CREATE TABLE reorder_suggestions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  medication_id     UUID REFERENCES medications(id),
  custom_medication_id UUID REFERENCES custom_medications(id),
  lot_id            UUID REFERENCES inventory_lots(id),
  current_stock     INTEGER NOT NULL DEFAULT 0,
  reorder_point     INTEGER NOT NULL DEFAULT 0,
  suggested_qty     INTEGER NOT NULL DEFAULT 0,          -- จำนวนที่แนะนำให้สั่งซื้อ
  supplier_id       UUID REFERENCES suppliers(id),       -- ถ้ารู้ supplier ประจำ
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'approved', 'rejected', 'converted_to_po')),
  approved_by       UUID REFERENCES users(id),
  purchase_order_id UUID,                                  -- ถ้าสร้าง PO แล้ว
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_reorder_suggestions_pending ON reorder_suggestions(status, created_at) WHERE status = 'pending';
CREATE INDEX idx_reorder_suggestions_profession ON reorder_suggestions(profession_id, medication_id);

-- ============================================
-- 8. INVENTORY ALERTS (Low stock / Expiry / Reorder notifications)
-- ============================================
CREATE TABLE inventory_alerts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  alert_type        TEXT NOT NULL                         -- 'low_stock', 'expiry_warning', 'expired', 'reorder', 'transfer_overdue'
                      CHECK (alert_type IN ('low_stock', 'expiry_warning', 'expired', 'reorder', 'transfer_overdue', 'damaged')),
  severity          TEXT NOT NULL DEFAULT 'medium'        -- 'low', 'medium', 'high', 'critical'
                      CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  medication_id     UUID REFERENCES medications(id),
  custom_medication_id UUID REFERENCES custom_medications(id),
  lot_id            UUID REFERENCES inventory_lots(id),
  title             TEXT NOT NULL,
  message           TEXT NOT NULL,
  is_read           BOOLEAN DEFAULT false,
  is_dismissed      BOOLEAN DEFAULT false,
  resolved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_inventory_alerts_unread ON inventory_alerts(profession_id, is_read, is_dismissed) WHERE is_read = false AND is_dismissed = false;
CREATE INDEX idx_inventory_alerts_type ON inventory_alerts(alert_type, severity);
CREATE INDEX idx_inventory_alerts_created ON inventory_alerts(created_at DESC);
```

### Schema สำหรับ Cart Core (แนะนำ)
> **สถานะ:** ⏳ บางส่วน implement — `cart_sessions`, `cart_items`, `checkout_sessions` อยู่ใน migration Phase 2; `cart_merchant_groups`, `payment_allocations` ยังไม่ migrate

> **ผลการวิเคราะห์:** `SHOPPING_CART_PLAN.md` มีแค่ 3 ตารางพื้นฐาน (`platform_shopping_cart`, `platform_cart_items`, `platform_orders`) ขาดโมเดลสำคัญ 8 ประการ:
> 1. **Cart 2 ชุดซ้อนกัน —** `POS System_plan.md` มี `shopping_carts` อีกชุด (`items` เป็น JSONB) ทำให้ platform cart กับ POS cart ไม่ sync กัน
> 2. **ไม่มี Cart Item Snapshot —** `platform_cart_items` เก็บ `unit_price` แบบ current price ไม่ใช่ snapshot → ถ้า merchant เปลี่ยนราคาระหว่าง browse กับ checkout เกิด price mismatch
> 3. **ไม่มี Checkout Session —** ไม่สามารถ recover ตะกร้าที่กำลังชำระเงินแล้ว app crash หรือตรวจสอบ duplicate checkout ได้
> 4. **ไม่มี Merchant Group / Cart Split —** ถ้า cart มีสินค้าจาก clinic A + clinic B + platform native ระบบไม่รู้ว่าต้องแตกเป็นกี่ order ย่อย
> 5. **ไม่มี Payment Allocation —** รับเงินก้อนเดียวแต่ไม่มี ledger ว่าเงินจะแบ่งให้ใครเท่าไหร่
> 6. **ไม่มี Tax/Discount/Shipping Allocation Policy —** ถ้ามีส่วนลดหรือค่าส่งรวม จะกระจายต่อ merchant อย่างไรให้ถูกต้องตามบัญชี
> 7. **ไม่มี Stock Reservation จาก Cart —** user ใส่ตะกร้าแล้ว stock ยังไม่ถูกจอง ทำให้ oversell ตอน concurrent สูง
> 8. **`platform_orders` ไม่มี checkout status —** มีแค่ `payment_status = 'completed'` ไม่รู้ว่าอยู่ขั้นตอนไหน (browsing → checking out → awaiting_payment → paid → split → injected → completed)

```sql
-- ============================================
-- 1. CART SESSIONS (Unified Cart — ยุบ platform + POS เป็นชุดเดียว)
-- ============================================
CREATE TABLE cart_sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id),
  profession_id   UUID REFERENCES professions(id),       -- NULL = platform-native cart (multi-merchant)
  branch_id       UUID REFERENCES organization_branches(id),
  cart_type       TEXT NOT NULL DEFAULT 'platform'        -- 'platform', 'pos', 'telemedicine'
                      CHECK (cart_type IN ('platform', 'pos', 'telemedicine')),
  status          TEXT NOT NULL DEFAULT 'active'         -- 'active', 'checkout_in_progress', 'converted', 'abandoned', 'expired'
                      CHECK (status IN ('active', 'checkout_in_progress', 'converted', 'abandoned', 'expired')),
  total_items     INTEGER NOT NULL DEFAULT 0,
  total_quantity  INTEGER NOT NULL DEFAULT 0,
  subtotal        DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_total  DECIMAL(12,2) NOT NULL DEFAULT 0,
  shipping_total  DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_total       DECIMAL(12,2) NOT NULL DEFAULT 0,
  grand_total     DECIMAL(12,2) NOT NULL DEFAULT 0,
  currency        TEXT NOT NULL DEFAULT 'THB',
  expires_at      TIMESTAMPTZ,                             -- หมดอายุถ้าไม่มี activity
  converted_to_order_id UUID,                            -- ถ้าแปลงเป็น order แล้ว
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_sessions_user ON cart_sessions(user_id, status);
CREATE INDEX idx_cart_sessions_expires ON cart_sessions(expires_at) WHERE status IN ('active', 'checkout_in_progress');

-- ============================================
-- 2. CART ITEMS (พร้อม Snapshot)
-- ============================================
CREATE TABLE cart_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_session_id UUID NOT NULL REFERENCES cart_sessions(id) ON DELETE CASCADE,
  profession_id   UUID REFERENCES professions(id),       -- เจ้าของสินค้า (NULL = platform)
  product_type    TEXT NOT NULL DEFAULT 'medication'      -- 'medication', 'custom_medication', 'service', 'package'
                      CHECK (product_type IN ('medication', 'custom_medication', 'service', 'package', 'donation')),
  product_id      UUID NOT NULL,                         -- ID ของสินค้า (ไม่ว่าจะ type อะไร)
  quantity        INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  -- Current price (ตอน browse)
  unit_price_current  DECIMAL(12,2) NOT NULL DEFAULT 0,
  -- Snapshot price (freeze ตอน checkout)
  unit_price_snapshot DECIMAL(12,2),
  -- Product snapshot (JSONB บันทึกชื่อ, รูป, หน่วย ตอนใส่ตะกร้า)
  product_snapshot    JSONB DEFAULT '{}',
  line_subtotal       DECIMAL(12,2) NOT NULL DEFAULT 0,  -- quantity × unit_price_snapshot (หรือ current ถ้ายังไม่ snapshot)
  line_discount       DECIMAL(12,2) NOT NULL DEFAULT 0,
  line_tax            DECIMAL(12,2) NOT NULL DEFAULT 0,
  line_total          DECIMAL(12,2) NOT NULL DEFAULT 0,  -- subtotal - discount + tax
  is_selected         BOOLEAN DEFAULT true,               -- ถ้า false = ยังไม่เลือกให้ checkout
  added_at            TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_items_cart ON cart_items(cart_session_id, is_selected);
CREATE INDEX idx_cart_items_product ON cart_items(product_type, product_id);

-- ============================================
-- 3. CART MERCHANT GROUPS (Cart Split / Multi-merchant)
-- ============================================
CREATE TABLE cart_merchant_groups (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_session_id   UUID NOT NULL REFERENCES cart_sessions(id) ON DELETE CASCADE,
  merchant_type     TEXT NOT NULL DEFAULT 'profession'    -- 'profession', 'platform', 'partner'
                      CHECK (merchant_type IN ('profession', 'platform', 'partner')),
  merchant_id       UUID,                                  -- profession_id หรือ partner_id
  subtotal          DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
  shipping_fee      DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
  grand_total       DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_allocation_method TEXT DEFAULT 'proportional' -- 'proportional', 'merchant_first', 'platform_first'
                      CHECK (discount_allocation_method IN ('proportional', 'merchant_first', 'platform_first')),
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_merchant_groups_cart ON cart_merchant_groups(cart_session_id);

-- ============================================
-- 4. CART PRICING RULES (Dynamic pricing / Promotion engine)
-- ============================================
CREATE TABLE cart_pricing_rules (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID REFERENCES professions(id),       -- NULL = platform-wide rule
  rule_name         TEXT NOT NULL,
  rule_type         TEXT NOT NULL                           -- 'discount_percentage', 'discount_amount', 'buy_x_get_y', 'free_shipping', 'bundle_price'
                      CHECK (rule_type IN ('discount_percentage', 'discount_amount', 'buy_x_get_y', 'free_shipping', 'bundle_price', 'member_price')),
  applies_to        TEXT NOT NULL DEFAULT 'all'             -- 'all', 'category', 'product', 'merchant'
                      CHECK (applies_to IN ('all', 'category', 'product', 'merchant')),
  target_id         UUID,                                    -- product_id หรือ category_id (ถ้า applies_to ไม่ใช่ 'all')
  min_quantity      INTEGER DEFAULT 1,
  min_subtotal      DECIMAL(12,2) DEFAULT 0,
  discount_value    DECIMAL(12,2) DEFAULT 0,               -- % หรือ amount ขึ้นกับ rule_type
  max_discount      DECIMAL(12,2),                           -- cap ส่วนลดสูงสุด
  start_at          TIMESTAMPTZ,
  end_at            TIMESTAMPTZ,
  usage_limit       INTEGER,                                 -- จำนวนครั้งที่ใช้ได้ (NULL = unlimited)
  usage_count       INTEGER DEFAULT 0,
  is_active         BOOLEAN DEFAULT true,
  priority          INTEGER DEFAULT 100,                     -- ตัวเลขน้อย = ใช้ก่อน
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_pricing_rules_active ON cart_pricing_rules(is_active, start_at, end_at);

-- ============================================
-- 5. CART PROMOTION SNAPSHOTS (Freeze promotion ตอน checkout)
-- ============================================
CREATE TABLE cart_promotion_snapshots (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_session_id   UUID NOT NULL REFERENCES cart_sessions(id) ON DELETE CASCADE,
  rule_id           UUID REFERENCES cart_pricing_rules(id),
  rule_name         TEXT NOT NULL,
  rule_type         TEXT NOT NULL,
  discount_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,
  applied_to_merchant_group_id UUID REFERENCES cart_merchant_groups(id),
  applied_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_promotion_snapshots_cart ON cart_promotion_snapshots(cart_session_id);

-- ============================================
-- 6. CHECKOUT SESSIONS (Recoverable checkout state machine)
-- ============================================
CREATE TABLE checkout_sessions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_session_id         UUID NOT NULL REFERENCES cart_sessions(id),
  user_id                 UUID NOT NULL REFERENCES users(id),
  status                  TEXT NOT NULL DEFAULT 'initiated'
                              CHECK (status IN ('initiated', 'awaiting_payment', 'payment_confirmed', 'splitting', 'injected', 'completed', 'failed', 'expired')),
  payment_method          TEXT,                              -- 'credit_card', 'promptpay', 'cash', 'wallet'
  idempotency_key         TEXT UNIQUE,                       -- กัน duplicate checkout
  payment_gateway_session_id TEXT,                           -- Stripe/Omise session ID
  payment_transaction_id  UUID,                              -- อ้างอิง payment_transactions
  initiated_at            TIMESTAMPTZ DEFAULT now(),
  expires_at              TIMESTAMPTZ,                         -- เช่น now() + interval '30 minutes'
  completed_at            TIMESTAMPTZ,
  failed_at               TIMESTAMPTZ,
  failure_reason          TEXT,
  created_at              TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_checkout_sessions_cart ON checkout_sessions(cart_session_id);
CREATE INDEX idx_checkout_sessions_status ON checkout_sessions(status, expires_at);
CREATE INDEX idx_checkout_sessions_idempotency ON checkout_sessions(idempotency_key);
```

### Schema สำหรับ Delivery Core — โมเดลที่ขาดหาย (แนะนำ)
> **สถานะ:** ⏳ บางส่วน implement — `riders`, `delivery_orders`, `delivery_runs`, `route_stops` อยู่ใน migration Phase 2; `delivery_exceptions`, `carrier_configs`, `delivery_tracking` ยังไม่ migrate

> **ผลการวิเคราะห์:** `ERP_CORE_ARCHITECTURE.md` มี schema Delivery ที่ครบถ้วนกว่า `Delivery_PLAN.md` มาก (9 ตาราง vs 2 ตาราง) แต่ยังมีช่องโหว่ 5 ประการ:
> 1. **`Shipment` / `ShipmentItem` ขาด schema —** model list เดิมระบุ `Shipment`, `ShipmentItem` แต่ไม่มีตารางใดๆ ในเอกสารหรือ codebase ทั้งหมด ควรมี `shipments` สำหรับ 3PL tracking number และ physical package tracking (`tracking_number`, `carrier_reference`, `shipment_status`) โดยเฉพาะเมื่อใช้ carrier ภายนอก
> 2. **`RiderAssignment` ไม่มีตาราง —** model list เดิมมี `RiderAssignment` แต่ schema ใช้ `delivery_orders.rider_id` แบบ direct FK ซึ่งเหมาะสมกับ in-house fleet แต่ไม่รองรับการ assign แบบ batch หรือ bidding (เช่น Grab-style ที่ rider กดรับงานเอง) → ควรมี `rider_assignments` ถ้ารองรับ self-assignment หรือ dispatch queue
> 3. **`Delivery_PLAN.md` ล้าสมัย —** ยังใช้ `pos_receipt_id` ผูกมัดกับ POS (`delivery_orders` → `pos_receipts`) และมีแค่ 5 สถานะ (`pending`, `packed`, `shipping`, `delivered`, `cancelled`) ซึ่งไม่เพียงพอต่องานขนส่งจริง (ขาด `assigned`, `picked_up`, `at_dropoff`, `failed_attempt`, `reattempt_scheduled`, `returned_to_warehouse`) แต่ `ERP_CORE_ARCHITECTURE.md` ได้แก้ไขแล้วด้วย `source_type`/`source_order_id` และ state machine 13 สถานะ
> 4. **ไม่มี implementation code จริง —** ค้นหาใน `lib/` และ `websocket-server/` ไม่พบ models, repositories, services, หรือ UI pages สำหรับ Delivery Core ใดๆ (`Delivery_PLAN.md` และ `ERP_CORE_ARCHITECTURE.md` เป็น documentation-only ทั้งหมด)
> 5. **`delivery_tracking` ไม่มี retention policy ใน schema —** แม้เอกสารระบุให้เก็บแค่ 30 วันแล้ว archive แต่ schema ไม่มี partition หรือ `retention_until` column → ตารางนี้จะโตเร็วมากถ้าไรเดอร์เยอะและส่ง location ทุก 10-30 วินาที

```sql
-- ============================================
-- A. SHIPMENTS (3PL Physical Package Tracking)
-- ============================================
CREATE TABLE shipments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  delivery_order_id UUID NOT NULL REFERENCES delivery_orders(id),
  carrier_id        UUID REFERENCES carrier_configs(id),
  tracking_number   TEXT NOT NULL,                     -- เลข tracking ของ 3PL
  carrier_reference TEXT,                              -- เลขอ้างอิงของ carrier
  shipment_status   TEXT NOT NULL DEFAULT 'created'
                      CHECK (shipment_status IN ('created', 'picked_up', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'returned')),
  weight_kg         DECIMAL(8,2) DEFAULT 0,
  dimensions_cm     JSONB,                             -- {length, width, height}
  label_url         TEXT,                              -- URL ของ shipping label
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_shipments_tracking ON shipments(tracking_number);
CREATE INDEX idx_shipments_order ON shipments(delivery_order_id);

-- ============================================
-- B. SHIPMENT ITEMS (รายการสินค้าในแต่ละ shipment)
-- ============================================
CREATE TABLE shipment_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id       UUID NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
  order_item_id     UUID REFERENCES order_items(id),   -- ถ้าสร้างจาก order
  inventory_lot_id  UUID REFERENCES inventory_lots(id), -- ถ้าต้องระบุ lot
  item_name         TEXT NOT NULL,
  quantity          INTEGER NOT NULL CHECK (quantity > 0),
  weight_kg         DECIMAL(8,2) DEFAULT 0,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_shipment_items_shipment ON shipment_items(shipment_id);

-- ============================================
-- C. RIDER ASSIGNMENTS (สำหรับ self-assignment / dispatch queue)
-- ============================================
CREATE TABLE rider_assignments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_order_id UUID NOT NULL REFERENCES delivery_orders(id),
  rider_id          UUID REFERENCES riders(id),
  assignment_type   TEXT NOT NULL DEFAULT 'auto_dispatch'
                      CHECK (assignment_type IN ('auto_dispatch', 'manual_assign', 'self_pickup', 'bid_accepted')),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'accepted', 'rejected', 'expired', 'cancelled')),
  offered_at        TIMESTAMPTZ DEFAULT now(),
  accepted_at       TIMESTAMPTZ,
  rejected_at       TIMESTAMPTZ,
  rejection_reason  TEXT,
  expires_at        TIMESTAMPTZ,                         -- หมดอายุถ้า rider ไม่ตอบรับ
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_rider_assignments_order ON rider_assignments(delivery_order_id);
CREATE INDEX idx_rider_assignments_rider ON rider_assignments(rider_id, status);
CREATE INDEX idx_rider_assignments_pending ON rider_assignments(status, expires_at)
  WHERE status = 'pending';
```

### Schema สำหรับ Delivery Model (แนะนำ)
> **สถานะ:** ⏳ บางส่วน implement — ดูรายละเอียดใน section Delivery Core ด้านบน

```sql
-- ============================================
-- 1. RIDERS / FLEET
-- ============================================
CREATE TABLE riders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  vehicle_type      TEXT NOT NULL DEFAULT 'motorcycle'
                    CHECK (vehicle_type IN ('motorcycle', 'car', 'van', 'bicycle', 'walking')),
  vehicle_plate     TEXT,
  max_capacity_weight_kg DECIMAL(8,2) DEFAULT 10,
  max_capacity_volume_l  DECIMAL(8,2) DEFAULT 50,
  zone_coverage     TEXT[] DEFAULT '{}',             -- เช่น ['zone_a', 'zone_b']
  is_active         BOOLEAN DEFAULT true,
  current_status    TEXT DEFAULT 'offline'          -- 'offline', 'online', 'on_delivery', 'on_break'
                    CHECK (current_status IN ('offline', 'online', 'on_delivery', 'on_break', 'unavailable')),
  current_latitude  DECIMAL(10, 8),
  current_longitude DECIMAL(11, 8),
  last_location_at  TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_riders_profession_status ON riders(profession_id, current_status)
  WHERE current_status IN ('online', 'on_delivery');
CREATE INDEX idx_riders_location ON riders(current_latitude, current_longitude)
  WHERE current_status IN ('online', 'on_delivery');

-- ============================================
-- 2. RIDER SHIFTS
-- ============================================
CREATE TABLE rider_shifts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id        UUID NOT NULL REFERENCES riders(id),
  shift_date      DATE NOT NULL,
  start_time      TIME NOT NULL,
  end_time        TIME NOT NULL,
  is_available    BOOLEAN DEFAULT true,
  max_orders      INTEGER DEFAULT 20,
  assigned_orders INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_rider_shifts_available ON rider_shifts(rider_id, shift_date, is_available)
  WHERE is_available = true AND assigned_orders < max_orders;

-- ============================================
-- 3. DELIVERY ORDERS (เต็มรูปแบบ)
-- ============================================
CREATE TABLE delivery_orders (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id),
  branch_id           UUID REFERENCES organization_branches(id),
  -- แยก reference ออกจาก POS ให้ยืดหยุ่น
  source_type         TEXT NOT NULL DEFAULT 'pos'    -- 'pos', 'telemedicine', 'platform', 'manual'
                        CHECK (source_type IN ('pos', 'telemedicine', 'platform', 'manual')),
  source_order_id     UUID,                          -- ID ของ order ต้นทาง (pos receipt, platform order, etc.)
  rider_id            UUID REFERENCES riders(id),
  carrier_id          UUID,                          -- NULL = in-house fleet
  recipient_name      TEXT NOT NULL,
  recipient_phone     TEXT NOT NULL,
  dest_address        TEXT,
  dest_latitude       DECIMAL(10, 8),
  dest_longitude      DECIMAL(11, 8),
  distance_km         DECIMAL(10, 2),
  shipping_fee        DECIMAL(12, 2) DEFAULT 0,
  fee_snapshot        JSONB DEFAULT '{}',            -- snapshot ของ fee rule ที่ใช้คำนวณ
  delivery_type       TEXT NOT NULL DEFAULT 'asap'   -- 'asap', 'scheduled'
                        CHECK (delivery_type IN ('asap', 'scheduled')),
  delivery_window_start TIMESTAMPTZ,
  delivery_window_end   TIMESTAMPTZ,
  -- State machine แบบเต็มรูปแบบ
  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN (
                          'pending', 'packed', 'ready_for_pickup',
                          'assigned', 'picked_up', 'in_transit', 'at_dropoff',
                          'delivered', 'failed_attempt', 'reattempt_scheduled',
                          'returned_to_warehouse', 'cancelled'
                        )),
  status_changed_at   TIMESTAMPTZ DEFAULT now(),
  packed_at           TIMESTAMPTZ,
  assigned_at         TIMESTAMPTZ,
  picked_up_at        TIMESTAMPTZ,
  in_transit_at       TIMESTAMPTZ,
  at_dropoff_at       TIMESTAMPTZ,
  delivered_at        TIMESTAMPTZ,
  failed_attempt_at   TIMESTAMPTZ,
  cancelled_at        TIMESTAMPTZ,
  cancellation_reason TEXT,
  -- Metadata
  package_count       INTEGER DEFAULT 1,
  package_weight_kg   DECIMAL(8,2) DEFAULT 0,
  special_instructions TEXT,                        -- หมายเหตุพิเศษ (เช่น "โทรก่อนส่ง", "อย่าโทรก่อน 11:00")
  metadata            JSONB DEFAULT '{}',
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_delivery_orders_profession ON delivery_orders(profession_id, status, created_at DESC);
CREATE INDEX idx_delivery_orders_rider ON delivery_orders(rider_id, status)
  WHERE rider_id IS NOT NULL AND status IN ('assigned', 'picked_up', 'in_transit', 'at_dropoff');
CREATE INDEX idx_delivery_orders_source ON delivery_orders(source_type, source_order_id);
CREATE INDEX idx_delivery_orders_scheduled ON delivery_orders(delivery_window_start, status)
  WHERE delivery_type = 'scheduled' AND status = 'pending';

-- ============================================
-- 4. DELIVERY RUNS & ROUTE STOPS
-- ============================================
CREATE TABLE delivery_runs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  rider_id          UUID NOT NULL REFERENCES riders(id),
  shift_id          UUID REFERENCES rider_shifts(id),
  run_date          DATE NOT NULL,
  status            TEXT NOT NULL DEFAULT 'planned'
                    CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled')),
  total_distance_km DECIMAL(10, 2) DEFAULT 0,
  estimated_start_time TIMESTAMPTZ,
  estimated_end_time   TIMESTAMPTZ,
  actual_start_time    TIMESTAMPTZ,
  actual_end_time      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE route_stops (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id            UUID NOT NULL REFERENCES delivery_runs(id) ON DELETE CASCADE,
  stop_sequence     INTEGER NOT NULL,
  delivery_order_id UUID REFERENCES delivery_orders(id),
  stop_type         TEXT NOT NULL DEFAULT 'delivery'  -- 'delivery', 'pickup', 'depot'
                    CHECK (stop_type IN ('delivery', 'pickup', 'depot')),
  estimated_arrival TIMESTAMPTZ,
  actual_arrival    TIMESTAMPTZ,
  estimated_departure TIMESTAMPTZ,
  actual_departure   TIMESTAMPTZ,
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'arrived', 'completed', 'skipped')),
  latitude          DECIMAL(10, 8),
  longitude         DECIMAL(11, 8),
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (run_id, stop_sequence)
);
CREATE INDEX idx_route_stops_run ON route_stops(run_id, stop_sequence);

-- ============================================
-- 5. PROOF OF DELIVERY (POD)
-- ============================================
CREATE TABLE proof_of_deliveries (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_order_id       UUID NOT NULL REFERENCES delivery_orders(id),
  delivered_by            UUID NOT NULL REFERENCES riders(id),
  recipient_name          TEXT,
  recipient_signature_url TEXT,                        -- URL ของรูปลายเซ็น
  delivery_photo_url      TEXT,                        -- URL ของรูปถ่ายตอนส่ง
  verification_code       TEXT,                        -- รหัสยืนยันที่ลูกค้ากรอก
  notes                   TEXT,
  latitude                DECIMAL(10, 8),
  longitude               DECIMAL(11, 8),
  delivered_at            TIMESTAMPTZ DEFAULT now(),
  created_at              TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_pod_order ON proof_of_deliveries(delivery_order_id);

-- ============================================
-- 6. DELIVERY EXCEPTIONS
-- ============================================
CREATE TABLE delivery_exceptions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_order_id UUID NOT NULL REFERENCES delivery_orders(id),
  exception_type    TEXT NOT NULL
                    CHECK (exception_type IN (
                      'recipient_not_home', 'wrong_address', 'vehicle_breakdown',
                      'damaged_goods', 'refused_delivery', 'rider_emergency',
                      'traffic_delay', 'weather_delay', 'customer_cancelled'
                    )),
  reason            TEXT NOT NULL,                     -- รายละเอียดจากไรเดอร์
  reported_by       UUID NOT NULL REFERENCES users(id),
  photo_url         TEXT,                            -- รูปถ่ายหลักฐาน (ถ้ามี)
  resolved_by       UUID REFERENCES users(id),
  resolution_type   TEXT                              -- 'reattempt_same_day', 'reattempt_next_day', 'return_to_warehouse', 'cancel_and_refund'
                    CHECK (resolution_type IN ('reattempt_same_day', 'reattempt_next_day', 'return_to_warehouse', 'cancel_and_refund')),
  resolution_notes  TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  resolved_at       TIMESTAMPTZ
);
CREATE INDEX idx_exceptions_order ON delivery_exceptions(delivery_order_id);
CREATE INDEX idx_exceptions_unresolved ON delivery_exceptions(resolved_at)
  WHERE resolved_at IS NULL;

-- ============================================
-- 7. 3PL CARRIER CONFIGS
-- ============================================
CREATE TABLE carrier_configs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id),
  carrier_name        TEXT NOT NULL,                   -- 'Kerry Express', 'Flash Express'
  carrier_code        TEXT NOT NULL,                   -- 'kerry', 'flash'
  api_base_url        TEXT,
  api_key_encrypted   TEXT,                            -- เก็บ encrypted ไม่เก็บ plain text
  api_secret_encrypted TEXT,
  tracking_url_template TEXT,                          -- เช่น 'https://track.example.com/?id={{tracking_number}}'
  is_active           BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, carrier_code)
);

CREATE TABLE carrier_tracking_mappings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carrier_id      UUID NOT NULL REFERENCES carrier_configs(id),
  carrier_status  TEXT NOT NULL,                     -- status ที่ 3PL ส่งมา
  canonical_status TEXT NOT NULL,                    -- แปลงเป็น Sheserved status
  description     TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 8. DELIVERY FEE RULES
-- ============================================
CREATE TABLE delivery_fee_rules (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  rule_name         TEXT NOT NULL,
  rule_type         TEXT NOT NULL
                    CHECK (rule_type IN ('distance', 'zone', 'weight', 'time_window', 'urgency', 'flat_rate')),
  priority          INTEGER NOT NULL DEFAULT 100,    -- ตัวเลขน้อย = สำคัญกว่า
  -- Zone (ใช้ polygon ถ้าเป็น zone-based)
  zone_polygon      JSONB,                           -- GeoJSON Polygon
  -- Distance range
  min_distance_km   DECIMAL(8, 2) DEFAULT 0,
  max_distance_km   DECIMAL(8, 2) DEFAULT 9999,
  -- Weight range
  min_weight_kg     DECIMAL(8, 2) DEFAULT 0,
  max_weight_kg     DECIMAL(8, 2) DEFAULT 9999,
  -- Time window
  time_window_start TIME,
  time_window_end   TIME,
  -- Fee calculation
  base_fee          DECIMAL(12, 2) NOT NULL DEFAULT 0,
  per_km_fee        DECIMAL(12, 2) DEFAULT 0,
  per_kg_fee        DECIMAL(12, 2) DEFAULT 0,
  time_multiplier   DECIMAL(4, 2) DEFAULT 1.00,    -- เช่น 1.5 = rush hour
  urgency_multiplier DECIMAL(4, 2) DEFAULT 1.00,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_fee_rules_profession ON delivery_fee_rules(profession_id, is_active, priority DESC);

-- ============================================
-- 9. DELIVERY TRACKING (location updates)
-- ============================================
CREATE TABLE delivery_tracking (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_order_id UUID NOT NULL REFERENCES delivery_orders(id) ON DELETE CASCADE,
  rider_id          UUID NOT NULL REFERENCES riders(id),
  latitude          DECIMAL(10, 8) NOT NULL,
  longitude         DECIMAL(11, 8) NOT NULL,
  accuracy_meters   DECIMAL(6, 2),
  speed_kmh         DECIMAL(6, 2),
  recorded_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_tracking_order ON delivery_tracking(delivery_order_id, recorded_at DESC);
CREATE INDEX idx_tracking_rider ON delivery_tracking(rider_id, recorded_at DESC);
```

### Schema สำหรับ Settlement Core (แนะนำ)
> **สถานะ:** ⏳ บางส่วน implement — `vendor_contracts` อยู่ใน migration Phase 2; `merchant_accounts`, `settlement_ledgers`, `payout_batch_lines` ยังไม่ migrate

> **ผลการวิเคราะห์:** Settlement Core มี model list (`MerchantAccount`, `VendorContract`, `SettlementLedger`, `PayoutBatch`) แต่ไม่มี schema หรือ analysis ใดๆ ในเอกสาร แม้ `SHOPPING_CART_PLAN.md` จะมี `payment_allocations` และ `payout_batches` แต่ขาดโมเดลสำคัญ 4 ประการ:
> 1. **`MerchantAccount` ไม่มีตาราง —** ไม่มีข้อมูลบัญชีธนาคาร/ e-Wallet ของ merchant (clinic/partner) ที่จะรับเงิน payout → ไม่สามารถโอนเงินอัตโนมัติได้
> 2. **`VendorContract` ไม่มีตาราง —** ไม่มีข้อมูลสัญญา platform fee rate, settlement cycle (T+1, T+7, monthly), หรือ minimum payout threshold ต่อ merchant → คำนวณ fee ไม่ถูกต้อง
> 3. **`SettlementLedger` ไม่มีตาราง —** ไม่มี ledger รวมที่แสดงยอดรอจ่าย (payable), ยอดจ่ายแล้ว (paid), และ balance ต่อ merchant ในแต่ละรอบ → ตรวจสอบย้อนหลังไม่ได้
> 4. **`PayoutBatch` มีอยู่แต่ไม่สมบูรณ์ —** `payout_batches` ใน Shopping Cart schema มีแค่ `batch_type`, `total_amount`, `status` แต่ไม่มี `payout_method`, `bank_account_id`, `failure_reason`, หรือ retry mechanism

```sql
-- ============================================
-- 1. MERCHANT ACCOUNTS (บัญชีรับเงินของ merchant)
-- ============================================
CREATE TABLE merchant_accounts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID REFERENCES professions(id),       -- NULL = platform partner
  partner_id        UUID,                                  -- ถ้าเป็น partner นอก ERP
  merchant_type     TEXT NOT NULL DEFAULT 'profession'      -- 'profession', 'partner', 'platform'
                      CHECK (merchant_type IN ('profession', 'partner', 'platform')),
  account_type      TEXT NOT NULL DEFAULT 'bank'            -- 'bank', 'promptpay', 'wallet'
                      CHECK (account_type IN ('bank', 'promptpay', 'wallet')),
  bank_code         TEXT,                                  -- '002' = BBL, '004' = KBANK, ฯลฯ
  bank_name         TEXT,
  account_number    TEXT NOT NULL,                         -- เก็บ encrypted ถ้า sensitive
  account_name      TEXT NOT NULL,
  promptpay_id      TEXT,                                  -- เบอร์โทรหรือเลขบัตรประชาชน
  is_primary        BOOLEAN DEFAULT false,                 -- บัญชีหลักสำหรับ payout
  is_verified       BOOLEAN DEFAULT false,                 -- ยืนยันแล้วหรือยัง
  verified_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, partner_id, account_type, is_primary)
);
CREATE INDEX idx_merchant_accounts_profession ON merchant_accounts(profession_id, merchant_type);

-- ============================================
-- 2. VENDOR CONTRACTS (สัญญา platform fee / settlement)
-- ============================================
CREATE TABLE vendor_contracts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID REFERENCES professions(id),       -- NULL = platform-wide default
  partner_id        UUID,
  contract_type     TEXT NOT NULL DEFAULT 'platform_fee'    -- 'platform_fee', 'delivery_fee_share', 'advertising', 'subscription'
                      CHECK (contract_type IN ('platform_fee', 'delivery_fee_share', 'advertising', 'subscription')),
  platform_fee_rate DECIMAL(5,4) NOT NULL DEFAULT 0.0300, -- เช่น 0.0300 = 3%
  minimum_payout    DECIMAL(12,2) NOT NULL DEFAULT 0,      -- ถอนขั้นต่ำ
  settlement_cycle  TEXT NOT NULL DEFAULT 't_plus_7'         -- 't_plus_1', 't_plus_7', 't_plus_15', 'monthly'
                      CHECK (settlement_cycle IN ('t_plus_1', 't_plus_7', 't_plus_15', 'monthly')),
  effective_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  expiry_date       DATE,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_vendor_contracts_profession ON vendor_contracts(profession_id, contract_type, is_active);

-- ============================================
-- 3. SETTLEMENT LEDGERS (ยอดรอจ่าย/จ่ายแล้ว ต่อ merchant ต่อรอบ)
-- ============================================
CREATE TABLE settlement_ledgers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID REFERENCES professions(id),
  partner_id        UUID,
  merchant_type     TEXT NOT NULL DEFAULT 'profession'
                      CHECK (merchant_type IN ('profession', 'partner', 'platform')),
  settlement_period TEXT NOT NULL,                         -- '2026-06' หรือ '2026-W24'
  period_start      DATE NOT NULL,
  period_end        DATE NOT NULL,
  opening_balance   DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_revenue     DECIMAL(12,2) NOT NULL DEFAULT 0,    -- ยอดขายรวมในรอบ
  total_fee         DECIMAL(12,2) NOT NULL DEFAULT 0,    -- platform fee รวม
  total_refund      DECIMAL(12,2) NOT NULL DEFAULT 0,    -- ยอดคืนเงิน
  net_payable       DECIMAL(12,2) NOT NULL DEFAULT 0,    -- ยอดที่ต้องจ่าย
  total_paid        DECIMAL(12,2) NOT NULL DEFAULT 0,    -- ยอดที่จ่ายไปแล้ว
  closing_balance   DECIMAL(12,2) NOT NULL DEFAULT 0,    -- net_payable - total_paid
  status            TEXT NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open', 'pending_payout', 'partially_paid', 'paid', 'on_hold', 'disputed')),
  currency          TEXT NOT NULL DEFAULT 'THB',
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, partner_id, settlement_period, merchant_type)
);
CREATE INDEX idx_settlement_ledgers_profession ON settlement_ledgers(profession_id, status);
CREATE INDEX idx_settlement_ledgers_period ON settlement_ledgers(period_start, period_end);

-- ============================================
-- 4. PAYOUT BATCHES (รวมการโอนจ่ายหลาย merchant — สมบูรณ์)
-- ============================================
CREATE TABLE payout_batches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID REFERENCES professions(id),   -- NULL = platform payout (หลาย merchant)
  batch_type        TEXT NOT NULL DEFAULT 'merchant'   -- 'merchant', 'rider', 'refund'
                      CHECK (batch_type IN ('merchant', 'rider', 'refund')),
  total_amount      DECIMAL(12, 2) NOT NULL DEFAULT 0,
  total_records     INTEGER NOT NULL DEFAULT 0,          -- จำนวนรายการใน batch
  currency          TEXT NOT NULL DEFAULT 'THB',
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  payout_method     TEXT NOT NULL DEFAULT 'bank_transfer' -- 'bank_transfer', 'promptpay', 'wallet'
                      CHECK (payout_method IN ('bank_transfer', 'promptpay', 'wallet')),
  bank_reference    TEXT,                                -- เลขอ้างอิงธนาคาร
  failure_reason    TEXT,
  retry_count       INTEGER NOT NULL DEFAULT 0,
  processed_by      UUID REFERENCES users(id),
  processed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_payout_batches_status ON payout_batches(status, created_at DESC);
CREATE INDEX idx_payout_batches_profession ON payout_batches(profession_id, batch_type);

-- ============================================
-- 5. PAYOUT BATCH LINES (รายละเอียดแต่ละรายการใน batch)
-- ============================================
CREATE TABLE payout_batch_lines (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_batch_id   UUID NOT NULL REFERENCES payout_batches(id) ON DELETE CASCADE,
  settlement_ledger_id UUID REFERENCES settlement_ledgers(id),
  merchant_account_id UUID REFERENCES merchant_accounts(id),
  merchant_type     TEXT NOT NULL DEFAULT 'profession',
  merchant_id       UUID,                                  -- profession_id หรือ partner_id
  payout_amount     DECIMAL(12,2) NOT NULL DEFAULT 0,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  failure_reason    TEXT,
  bank_reference    TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  completed_at      TIMESTAMPTZ
);
CREATE INDEX idx_payout_batch_lines_batch ON payout_batch_lines(payout_batch_id);
CREATE INDEX idx_payout_batch_lines_merchant ON payout_batch_lines(merchant_type, merchant_id);
```

### Schema สำหรับ Shopping Cart (แนะนำ)
> **สถานะ:** ⏳ บางส่วน implement — `cart_sessions`, `cart_items`, `checkout_sessions` อยู่ใน migration Phase 2; ตารางอื่นๆ ยังเป็นแนวทาง

```sql
-- ============================================
-- 1. CART SESSIONS (รวม platform + POS เป็นชุดเดียว)
-- ============================================
CREATE TABLE cart_sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id),
  status          TEXT NOT NULL DEFAULT 'active'     -- 'active', 'checking_out', 'converted', 'abandoned', 'expired'
                    CHECK (status IN ('active', 'checking_out', 'converted', 'abandoned', 'expired')),
  expires_at      TIMESTAMPTZ,                        -- หมดอายุถ้าไม่มี activity (เช่น +7 วัน)
  converted_to_checkout_id UUID,                    -- เชื่อมกลับไป checkout_session ถ้า convert แล้ว
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_sessions_user ON cart_sessions(user_id, status)
  WHERE status IN ('active', 'checking_out');
CREATE INDEX idx_cart_sessions_expired ON cart_sessions(expires_at)
  WHERE status IN ('active', 'checking_out');

-- ============================================
-- 2. CART ITEMS (พร้อม snapshot)
-- ============================================
CREATE TABLE cart_items (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_session_id   UUID NOT NULL REFERENCES cart_sessions(id) ON DELETE CASCADE,
  product_source    TEXT NOT NULL                     -- 'medications', 'custom_medications', 'clinic_services', 'platform_products'
                    CHECK (product_source IN ('medications', 'custom_medications', 'clinic_services', 'platform_products')),
  product_id        UUID NOT NULL,                   -- ID ของ product ตาม product_source
  profession_id     UUID REFERENCES professions(id), -- NULL = platform native product
  quantity          INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  -- ราคา current (อัปเดตได้ถ้า user refresh)
  unit_price_current DECIMAL(12, 2) NOT NULL,
  -- snapshot ตอน checkout (freeze ไม่ให้แก้)
  unit_price_snapshot DECIMAL(12, 2),
  snapshot_at       TIMESTAMPTZ,
  -- ข้อมูล snapshot ของ product ตอนใส่ตะกร้า
  product_snapshot  JSONB DEFAULT '{}',              -- {name, image_url, unit, sku, category, ...}
  -- Pricing rules ที่ใช้
  applied_rules     JSONB DEFAULT '[]',              -- [{rule_type, rule_name, discount_amount}]
  is_selected       BOOLEAN DEFAULT true,           -- ถ้า user uncheck บางรายการ
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_items_cart ON cart_items(cart_session_id, is_selected)
  WHERE is_selected = true;
CREATE INDEX idx_cart_items_product ON cart_items(product_source, product_id);

-- ============================================
-- 3. CART MERCHANT GROUPS (กลุ่มตาม merchant สำหรับ split checkout)
-- ============================================
CREATE TABLE cart_merchant_groups (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_session_id       UUID NOT NULL REFERENCES cart_sessions(id) ON DELETE CASCADE,
  merchant_type         TEXT NOT NULL                 -- 'profession', 'platform', 'partner'
                    CHECK (merchant_type IN ('profession', 'platform', 'partner')),
  merchant_id           UUID,                          -- profession_id หรือ partner_id (NULL = platform)
  subtotal              DECIMAL(12, 2) NOT NULL DEFAULT 0,
  discount_amount       DECIMAL(12, 2) NOT NULL DEFAULT 0,
  shipping_fee          DECIMAL(12, 2) NOT NULL DEFAULT 0,
  tax_amount            DECIMAL(12, 2) NOT NULL DEFAULT 0,
  grand_total           DECIMAL(12, 2) NOT NULL DEFAULT 0,
  -- Allocation policy snapshot
  discount_allocation_method TEXT NOT NULL DEFAULT 'proportional'
                    CHECK (discount_allocation_method IN ('proportional', 'merchant_first', 'platform_first')),
  shipping_allocation_method TEXT NOT NULL DEFAULT 'proportional'
                    CHECK (shipping_allocation_method IN ('proportional', 'equal_split', 'merchant_pays_own')),
  created_at            TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cart_merchant_groups_cart ON cart_merchant_groups(cart_session_id);

-- ============================================
-- 4. CHECKOUT SESSIONS
-- ============================================
CREATE TABLE checkout_sessions (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_session_id           UUID NOT NULL REFERENCES cart_sessions(id),
  user_id                   UUID NOT NULL REFERENCES users(id),
  status                    TEXT NOT NULL DEFAULT 'initiated'
                    CHECK (status IN ('initiated', 'awaiting_payment', 'payment_confirmed', 'splitting', 'injecting', 'completed', 'failed', 'expired')),
  initiated_at              TIMESTAMPTZ DEFAULT now(),
  expires_at                TIMESTAMPTZ NOT NULL,     -- เช่น now() + interval '30 minutes'
  payment_method            TEXT,                     -- 'credit_card', 'promptpay', 'omise_card', 'cash'
  idempotency_key           TEXT NOT NULL UNIQUE,     -- กัน duplicate checkout
  payment_gateway_session_id TEXT,                     -- session ID จาก payment gateway
  payment_gateway_reference  TEXT,                     -- transaction ref จาก payment gateway
  grand_total               DECIMAL(12, 2) NOT NULL DEFAULT 0,
  platform_fee_total        DECIMAL(12, 2) NOT NULL DEFAULT 0,
  merchant_payout_total       DECIMAL(12, 2) NOT NULL DEFAULT 0,
  metadata                  JSONB DEFAULT '{}',
  created_at                TIMESTAMPTZ DEFAULT now(),
  updated_at                TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_checkout_sessions_user ON checkout_sessions(user_id, status, created_at DESC);
CREATE INDEX idx_checkout_sessions_cart ON checkout_sessions(cart_session_id);
CREATE INDEX idx_checkout_sessions_idempotency ON checkout_sessions(idempotency_key);
CREATE INDEX idx_checkout_sessions_expired ON checkout_sessions(expires_at, status)
  WHERE status IN ('initiated', 'awaiting_payment');

-- ============================================
-- 5. CHECKOUT MERCHANT ORDERS (ผลจากการ split cart)
-- ============================================
CREATE TABLE checkout_merchant_orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  checkout_session_id   UUID NOT NULL REFERENCES checkout_sessions(id),
  cart_merchant_group_id UUID NOT NULL REFERENCES cart_merchant_groups(id),
  merchant_type         TEXT NOT NULL
                    CHECK (merchant_type IN ('profession', 'platform', 'partner')),
  merchant_id             UUID,                      -- profession_id หรือ partner_id
  -- Order reference ที่สร้างหลังจาก injection
  injected_order_id       UUID,                      -- อ้างอิง POS order หรือ platform order ที่สร้าง
  injected_order_type     TEXT,                      -- 'pos_order', 'platform_order', 'partner_order'
  -- Financial breakdown
  subtotal                DECIMAL(12, 2) NOT NULL DEFAULT 0,
  discount_amount         DECIMAL(12, 2) NOT NULL DEFAULT 0,
  shipping_fee            DECIMAL(12, 2) NOT NULL DEFAULT 0,
  tax_amount              DECIMAL(12, 2) NOT NULL DEFAULT 0,
  grand_total             DECIMAL(12, 2) NOT NULL DEFAULT 0,
  platform_fee_rate       DECIMAL(5, 4) NOT NULL DEFAULT 0.00,  -- snapshot ตอน checkout (เช่น 0.0300 = 3%)
  platform_fee_amount     DECIMAL(12, 2) NOT NULL DEFAULT 0,
  net_payout_amount       DECIMAL(12, 2) NOT NULL DEFAULT 0,
  -- Status
  status                  TEXT NOT NULL DEFAULT 'pending_injection'
                    CHECK (status IN ('pending_injection', 'injecting', 'injected', 'injection_failed', 'cancelled')),
  injection_attempts      INTEGER NOT NULL DEFAULT 0,
  last_injection_error    TEXT,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_checkout_merchant_orders_session ON checkout_merchant_orders(checkout_session_id);
CREATE INDEX idx_checkout_merchant_orders_merchant ON checkout_merchant_orders(merchant_type, merchant_id);
CREATE INDEX idx_checkout_merchant_orders_status ON checkout_merchant_orders(status)
  WHERE status IN ('pending_injection', 'injection_failed');

-- ============================================
-- 6. PAYMENT ALLOCATIONS (ledger ของการแบ่งเงิน)
-- ============================================
CREATE TABLE payment_allocations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  checkout_session_id   UUID NOT NULL REFERENCES checkout_sessions(id),
  merchant_type         TEXT NOT NULL
                    CHECK (merchant_type IN ('profession', 'platform', 'partner')),
  merchant_id           UUID,
  -- Financial breakdown
  gross_amount          DECIMAL(12, 2) NOT NULL DEFAULT 0,     -- ยอดขายรวมของ merchant
  discount_amount       DECIMAL(12, 2) NOT NULL DEFAULT 0,     -- ส่วนลดที่ merchant รับผิดชอบ
  shipping_fee          DECIMAL(12, 2) NOT NULL DEFAULT 0,     -- ค่าส่งที่ merchant ได้
  tax_amount            DECIMAL(12, 2) NOT NULL DEFAULT 0,
  platform_fee_rate     DECIMAL(5, 4) NOT NULL DEFAULT 0.00,
  platform_fee_amount   DECIMAL(12, 2) NOT NULL DEFAULT 0,     -- ค่าธรรมเนียม platform
  shipping_subsidy      DECIMAL(12, 2) NOT NULL DEFAULT 0,     -- ถ้า platform อุดหนุนค่าส่ง
  net_payout_amount     DECIMAL(12, 2) NOT NULL DEFAULT 0,     -- ยอดที่ต้องโอนให้ merchant
  currency              TEXT NOT NULL DEFAULT 'THB',
  -- Settlement tracking
  status                TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'on_hold', 'released', 'payout_initiated', 'payout_completed', 'payout_failed')),
  payout_batch_id       UUID,                                     -- เชื่อมกับ payout batch
  payout_reference      TEXT,                                     -- เลขอ้างอิงการโอน
  released_at           TIMESTAMPTZ,
  payout_initiated_at   TIMESTAMPTZ,
  payout_completed_at   TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_payment_allocations_session ON payment_allocations(checkout_session_id);
CREATE INDEX idx_payment_allocations_merchant ON payment_allocations(merchant_type, merchant_id, status)
  WHERE status IN ('pending', 'on_hold', 'payout_failed');
CREATE INDEX idx_payment_allocations_payout ON payment_allocations(status, payout_batch_id)
  WHERE status IN ('payout_initiated', 'payout_completed');

-- ============================================
-- 7. PAYOUT BATCHES (รวมการโอนจ่ายหลาย merchant)
-- ============================================
CREATE TABLE payout_batches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID REFERENCES professions(id),   -- NULL = platform payout (หลาย merchant)
  batch_type        TEXT NOT NULL DEFAULT 'merchant'   -- 'merchant', 'rider', 'refund'
                    CHECK (batch_type IN ('merchant', 'rider', 'refund')),
  total_amount      DECIMAL(12, 2) NOT NULL DEFAULT 0,
  currency          TEXT NOT NULL DEFAULT 'THB',
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  bank_reference    TEXT,                                -- เลขอ้างอิงธนาคาร
  processed_by      UUID REFERENCES users(id),
  processed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 8. PLATFORM ORDERS (canonical customer view)
-- ============================================
CREATE TABLE platform_orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id),
  checkout_session_id UUID REFERENCES checkout_sessions(id),
  grand_total       DECIMAL(12, 2) NOT NULL,
  payment_status    TEXT NOT NULL DEFAULT 'pending'
                    CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded', 'partially_refunded')),
  -- Customer-facing status
  fulfillment_status TEXT NOT NULL DEFAULT 'pending'
                    CHECK (fulfillment_status IN ('pending', 'processing', 'packed', 'shipped', 'delivered', 'cancelled')),
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_platform_orders_user ON platform_orders(user_id, created_at DESC);
CREATE INDEX idx_platform_orders_checkout ON platform_orders(checkout_session_id);
```

### Schema สำหรับ Read Model / Analytics Core (แนะนำ)
> **สถานะ:** 🔴 ยังไม่ implement — เป็น schema แนะนำสำหรับอนาคต (projection checkpoints, dashboard snapshots, KPI aggregations, materialized views)

> **ผลการวิเคราะห์:** `KPI_DASHBOARD_PLAN.md` ระบุว่า "ยอด Actual ดึง Query จากระบบอื่น (POS, Accounting)" ซึ่งหมายความว่าทุกครั้งที่ดู dashboard ต้อง query ข้ามหลายตาราง transactional โดยตรง ขาดโมเดลสำคัญ 6 ประการ:
> 1. **ไม่มี Read Model / Materialized View —** ไม่มี `dashboard_snapshots` หรือ `kpi_aggregations` ที่ optimize สำหรับการอ่าน ทำให้ dashboard query ไปดึงจาก `orders` + `pos_receipts` + `accounting_entries` + `inventory_movements` + `delivery_orders` พร้อมกัน
> 2. **ไม่มี Caching Strategy —** ไม่มี Redis / Memcached หรือ PostgreSQL UNLOGGED table สำหรับ snapshot ที่ compute บ่อย → ถ้ามีคนดู dashboard พร้อมกัน 10 คน ระบบต้องคำนวณ aggregate ซ้ำ 10 ครั้ง
> 3. **ไม่มี Async Data Pipeline —** ไม่มี projection worker ที่ process event จาก `outbox_events` แล้ว update read model แบบ async → dashboard data stale หรือ block write model
> 4. **ไม่มี Projection Checkpoint —** ถ้า projection worker restart ไม่รู้ว่าคำนวณถึงไหนแล้ว ต้อง full scan ทุกครั้ง
> 5. **ไม่มี Read Replica / Read-only Endpoint —** dashboard query ไปดึงจาก primary database เดียวกับ transaction → lock contention
> 6. **ไม่มี Data Retention Policy —** `delivery_tracking` บันทึกพิกัดทุก 5-10 วินาที ถ้าสะสมไม่ลบ ตารางจะโตเร็วมาก
> 7. **ไม่มี Implementation Code —** ค้นหาใน `lib/` และ `websocket-server/` ไม่พบ projection worker, dashboard repository, หรือ caching layer ใดๆ

```sql
-- ============================================
-- 1. PROJECTION CHECKPOINTS (ติดตามว่า projection ทำงานถึงไหนแล้ว)
-- ============================================
CREATE TABLE projection_checkpoints (
  id                BIGSERIAL PRIMARY KEY,
  projection_name   TEXT NOT NULL UNIQUE,            -- 'daily_revenue', 'inventory_snapshot', 'staff_performance'
  projection_type     TEXT NOT NULL DEFAULT 'event'    -- 'event', 'cron', 'manual'
                    CHECK (projection_type IN ('event', 'cron', 'manual')),
  last_event_id     BIGINT,                          -- อ้างอิง outbox_events.id ล่าสุดที่ประมวลผลแล้ว
  last_processed_at TIMESTAMPTZ,
  lag_seconds       INTEGER DEFAULT 0,               -- ความห่างจาก realtime (seconds)
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 2. DASHBOARD SNAPSHOTS (pre-computed KPI)
-- ============================================
CREATE TABLE dashboard_snapshots (
  id                BIGSERIAL PRIMARY KEY,
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id), -- NULL = รวมทุกสาขา
  snapshot_type     TEXT NOT NULL                       -- 'daily_revenue', 'daily_orders', 'monthly_profit',
                                                      -- 'staff_performance', 'inventory_status',
                                                      -- 'delivery_performance', 'customer_cohort'
                    CHECK (snapshot_type IN (
                      'daily_revenue', 'daily_orders', 'weekly_revenue', 'weekly_orders',
                      'monthly_profit', 'quarterly_profit', 'yearly_profit',
                      'staff_performance', 'inventory_status', 'delivery_performance',
                      'customer_cohort', 'platform_health'
                    )),
  snapshot_date     DATE NOT NULL,                     -- วันที่ของ snapshot (สำหรับ daily/weekly)
  snapshot_period   TEXT NOT NULL DEFAULT 'daily'    -- 'daily', 'weekly', 'monthly', 'quarterly', 'yearly'
                    CHECK (snapshot_period IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly')),
  -- Metrics ที่คำนวณล่วงหน้า
  metrics_json      JSONB NOT NULL DEFAULT '{}',      -- { "revenue": 150000, "order_count": 45, ... }
  -- Metadata
  computed_at       TIMESTAMPTZ DEFAULT now(),
  expires_at        TIMESTAMPTZ,                      -- TTL สำหรับ cache invalidation
  computed_by       TEXT DEFAULT 'cron_worker',     -- 'cron_worker', 'event_worker', 'manual'
  version           INTEGER NOT NULL DEFAULT 1,       -- Optimistic locking สำหรับ concurrent update
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, snapshot_type, snapshot_date, snapshot_period)
);
CREATE INDEX idx_dashboard_snapshots_lookup ON dashboard_snapshots(profession_id, snapshot_type, snapshot_date DESC);
CREATE INDEX idx_dashboard_snapshots_branch ON dashboard_snapshots(profession_id, branch_id, snapshot_type, snapshot_date DESC);
CREATE INDEX idx_dashboard_snapshots_expires ON dashboard_snapshots(expires_at)
  WHERE expires_at IS NOT NULL;

-- ============================================
-- 3. KPI AGGREGATIONS (รายละเอียดระดับ daily/employee/branch)
-- ============================================
CREATE TABLE kpi_aggregations_daily (
  id                BIGSERIAL PRIMARY KEY,
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  employee_id       UUID REFERENCES users(id),       -- NULL = รวมทุกคน
  aggregation_date  DATE NOT NULL,
  -- Revenue metrics
  revenue_gross     DECIMAL(15, 2) NOT NULL DEFAULT 0,
  revenue_net       DECIMAL(15, 2) NOT NULL DEFAULT 0,
  discount_total    DECIMAL(15, 2) NOT NULL DEFAULT 0,
  tax_total         DECIMAL(15, 2) NOT NULL DEFAULT 0,
  -- Order metrics
  order_count       INTEGER NOT NULL DEFAULT 0,
  order_cancelled   INTEGER NOT NULL DEFAULT 0,
  avg_order_value   DECIMAL(12, 2) NOT NULL DEFAULT 0,
  -- Inventory metrics
  items_sold        INTEGER NOT NULL DEFAULT 0,
  items_returned    INTEGER NOT NULL DEFAULT 0,
  -- Delivery metrics
  deliveries_count  INTEGER NOT NULL DEFAULT 0,
  deliveries_failed INTEGER NOT NULL DEFAULT 0,
  avg_delivery_time_minutes INTEGER DEFAULT 0,
  -- Customer metrics
  unique_customers  INTEGER NOT NULL DEFAULT 0,
  new_customers     INTEGER NOT NULL DEFAULT 0,
  -- Computed metadata
  computed_at       TIMESTAMPTZ DEFAULT now(),
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, employee_id, aggregation_date)
);
CREATE INDEX idx_kpi_daily_lookup ON kpi_aggregations_daily(profession_id, aggregation_date DESC);
CREATE INDEX idx_kpi_daily_branch ON kpi_aggregations_daily(profession_id, branch_id, aggregation_date DESC);
CREATE INDEX idx_kpi_daily_employee ON kpi_aggregations_daily(profession_id, employee_id, aggregation_date DESC);

-- ============================================
-- 4. INVENTORY SNAPSHOTS (read model สำหรับ stock level)
-- ============================================
CREATE TABLE inventory_snapshots (
  id                BIGSERIAL PRIMARY KEY,
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  warehouse_location_id UUID,
  medication_id     UUID REFERENCES medications(id),
  custom_medication_id UUID REFERENCES custom_medications(id),
  snapshot_date     DATE NOT NULL,
  quantity_on_hand  INTEGER NOT NULL DEFAULT 0,
  quantity_reserved INTEGER NOT NULL DEFAULT 0,
  quantity_available INTEGER NOT NULL DEFAULT 0,
  total_value       DECIMAL(15, 2) NOT NULL DEFAULT 0,  -- quantity_on_hand × cost_price
  low_stock_count   INTEGER NOT NULL DEFAULT 0,        -- จำนวนรายการที่ต่ำกว่า reorder_point
  expiry_alert_count INTEGER NOT NULL DEFAULT 0,        -- จำนวนรายการที่ใกล้หมดอายุ (< 30 วัน)
  computed_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, warehouse_location_id, medication_id, custom_medication_id, snapshot_date)
);
CREATE INDEX idx_inventory_snapshots_lookup ON inventory_snapshots(profession_id, snapshot_date DESC);

-- ============================================
-- 5. CUSTOMER COHORT ANALYSIS (read model สำหรับ CRM)
-- ============================================
CREATE TABLE customer_cohort_snapshots (
  id                BIGSERIAL PRIMARY KEY,
  profession_id     UUID NOT NULL REFERENCES professions(id),
  cohort_month      DATE NOT NULL,                     -- วันที่ลูกค้าเข้ามาครั้งแรก (truncate to month)
  snapshot_month    DATE NOT NULL,                     -- วันที่ snapshot
  cohort_size       INTEGER NOT NULL DEFAULT 0,        -- จำนวนลูกค้าใน cohort
  active_count      INTEGER NOT NULL DEFAULT 0,        -- จำนวนที่ยัง active (มี order ใน snapshot_month)
  retention_rate    DECIMAL(5, 2) DEFAULT 0,         -- active_count / cohort_size × 100
  avg_lifetime_value DECIMAL(15, 2) DEFAULT 0,       -- LTV ของ cohort
  computed_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, cohort_month, snapshot_month)
);
CREATE INDEX idx_cohort_lookup ON customer_cohort_snapshots(profession_id, cohort_month DESC);

-- ============================================
-- 6. DELIVERY PERFORMANCE SUMMARY (aggregate จาก delivery_tracking)
-- ============================================
CREATE TABLE delivery_performance_summaries (
  id                BIGSERIAL PRIMARY KEY,
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  rider_id          UUID REFERENCES riders(id),      -- NULL = รวมทุกคน
  summary_date      DATE NOT NULL,
  total_runs        INTEGER NOT NULL DEFAULT 0,
  total_deliveries  INTEGER NOT NULL DEFAULT 0,
  successful_deliveries INTEGER NOT NULL DEFAULT 0,
  failed_attempts   INTEGER NOT NULL DEFAULT 0,
  avg_delivery_time_minutes INTEGER DEFAULT 0,
  total_distance_km DECIMAL(10, 2) DEFAULT 0,
  fuel_cost_estimate DECIMAL(12, 2) DEFAULT 0,
  customer_rating_avg DECIMAL(3, 2) DEFAULT 0,
  computed_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, rider_id, summary_date)
);
CREATE INDEX idx_delivery_perf_lookup ON delivery_performance_summaries(profession_id, summary_date DESC);

-- ============================================
-- 7. MATERIALIZED VIEW สำหรับ Reporting (ตัวอย่าง)
-- ============================================

-- Monthly Sales by Branch
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_monthly_sales_by_branch AS
SELECT
  profession_id,
  branch_id,
  DATE_TRUNC('month', created_at)::DATE AS month,
  COUNT(*) AS order_count,
  SUM(final_amount) AS revenue,
  SUM(discount_amount) AS discount_total,
  AVG(final_amount) AS avg_order_value
FROM orders
WHERE status IN ('paid', 'completed')
GROUP BY profession_id, branch_id, DATE_TRUNC('month', created_at)::DATE
WITH DATA;

CREATE UNIQUE INDEX idx_mv_monthly_sales
  ON mv_monthly_sales_by_branch(profession_id, branch_id, month);

-- Staff Performance Summary
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_staff_performance AS
SELECT
  profession_id,
  branch_id,
  served_by AS employee_id,
  DATE_TRUNC('month', created_at)::DATE AS month,
  COUNT(*) AS order_count,
  SUM(final_amount) AS revenue,
  AVG(final_amount) AS avg_order_value
FROM orders
WHERE status IN ('paid', 'completed') AND served_by IS NOT NULL
GROUP BY profession_id, branch_id, served_by, DATE_TRUNC('month', created_at)::DATE
WITH DATA;

CREATE UNIQUE INDEX idx_mv_staff_performance
  ON mv_staff_performance(profession_id, branch_id, employee_id, month);

-- Function สำหรับ refresh materialized view แบบ concurrent (ไม่ block read)
CREATE OR REPLACE FUNCTION refresh_reporting_views()
RETURNS VOID AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_sales_by_branch;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_staff_performance;
END;
$$ LANGUAGE plpgsql;
```

### ตาราง priority สำหรับการพัฒนา (ปรับปรุงหลังวิเคราะห์ 7 Core)

| Priority | Core / สิ่งที่ต้องทำ | เหตุผลหลัก | ผลต่อ scalability |
|---|---|---|---|
| **P0** | **Reliability Core** — `IdempotencyKey`, `OutboxEvent`, `InboxEvent`, `TransactionContext`, `CircuitBreakerState` | ทุก core อื่นต้องใช้ — ถ้าไม่มี checkout ไม่ปลอดภัย | **สูงมาก** |
| **P0** | **Commerce Core** — `Order`, `OrderItem`, `PaymentTransaction`, `CheckoutSession` + state flow `Cart→Order→Delivery→Accounting` | แกนธุรกรรมกลาง ทุกโมดูลอื่นต่อยอด | **สูงมาก** |
| **P0** | **Inventory Core (พื้นฐาน)** — `InventoryLot`, `InventoryReservation`, `StockMovement`, `WarehouseLocation` | กัน oversell ต้องทำก่อนเปิดขาย — reservation เป็น prerequisite ของ checkout | **สูงมาก** |
| **P1** | **Cart Core** — `CartSession`, `CartItem` (snapshot), `CheckoutSession` (state machine), `CartMerchantGroup` | ต้องใช้ Commerce + Inventory ที่ P0 เป็นพื้นฐาน | **สูง** |
| **P1** | **Settlement Core** — `VendorContract`, `MerchantAccount`, `PaymentAllocation`, `SettlementLedger` | dependency ของ Cart split — ต้องคำนวณ fee/payout ตอน checkout | **สูง** |
| **P1** | **Delivery Core (พื้นฐาน)** — `DeliveryOrder`, `Rider`, `RiderShift`, `DeliveryRun`, `RouteStop`, `POD` | ใช้ได้จริงต้องมีทั้งหมด ไม่ใช่แค่ 2 ตาราง | **สูง** |
| **P2** | **Read Model / Analytics Core** — `ProjectionCheckpoint`, `DashboardSnapshot`, `KPIAggregations` | ลดโหลดบน transactional tables | **สูง** |
| **P2** | **Inventory Core (ส่วนขยาย)** — `StockAdjustment`, `InventoryTransfer`, `StocktakeSession`, `ReorderSuggestion`, `InventoryAlert` | ใช้งานจริงได้ แต่ไม่ block checkout | **กลาง-สูง** |
| **P2** | **Delivery Core (ส่วนขยาย)** — `Shipment`, `ShipmentItem`, `RiderAssignment`, `DeliveryException`, `CarrierConfig` | 3PL, batch assign, exception handling | **กลาง-สูง** |
| **P3** | ขยาย HIS / LIS / Telemedicine บน backbone ที่นิ่งแล้ว | โมดูล clinical มีความซับซ้อนสูง ควรต่อยอดหลัง core commerce พร้อม | **กลาง** |

### สรุปสถานะงานปัจจุบัน (Complete / Partial / Missing)

| Core / งาน | สถานะ | หลักฐานในเอกสาร | ข้อสรุปเชิงปฏิบัติ |
|---|---|---|---|
| **Phase 0 Foundations** | **Complete** | `20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql` + Flutter layer | ใช้เป็นฐานได้แล้ว |
| **Phase 1 Inflow / Inventory base** | **Complete** | `warehouse_locations`, `inventory_lots`, `stock_movements`, `inventory_reservations` + `custom_medications`, `inventory_items`, `stocktake_configurations`, `stocktake_sessions`, `stocktake_lines`, `stock_adjustments`, `inventory_transfers`, `inventory_transfer_lines`, `inventory_alerts` + RPC (`deduct_inventory_fefo`, `create_stock_adjustment`, `create_inventory_transfer`, `complete_inventory_transfer`, `check_inventory_alerts`, `complete_stocktake_session`) + Dart models (`InventoryItem`, `CustomMedication`, `StocktakeConfiguration`, `StocktakeSession`, `StockAdjustment`, `InventoryTransfer`, `InventoryAlert`) + PhaseOneRepository/Notifier | ใช้เป็นฐาน checkout / stock reservation + FEFO + stocktake + transfer + alert ได้ |
| **Phase 2 Commerce / Cart / Delivery base** | **Complete** | `checkout_sessions`, `payment_transactions`, `cart_sessions`, `riders`, `delivery_runs`, `route_stops` + `confirm_checkout` fix + `update_checkout_session_status` | checkout flow ครบ end-to-end |
| **Payment Channels** | **Complete** | migration `20260612080000_add_payment_channels_and_tax_validation.sql` + `PaymentChannelsPage` | ใช้ได้จริง และ checkout เปลี่ยนเป็น dynamic ได้แล้ว |
| **branch_tax_code validation** | **Complete** | `validate_branch_tax_code()` + client-side `_isValidBranchTaxCode()` | ปิดช่องโหว่ข้อมูลสาขาภาษีได้แล้ว |
| **Inventory runtime functions** | **Implemented** | migration `20260612092000_add_inventory_runtime_functions.sql` (`release_stock_reservation`, `deduct_stock`, `cleanup_expired_reservations`) + `PhaseOneRepository` + `CheckoutPage` / `CounterPosPage` wire | production-ready สำหรับ checkout/pos flow |
| **Settlement full model** | **Complete** | `vendor_contracts` + `merchant_accounts` + `payment_allocations` + `settlement_ledgers` + `payout_batches` + `payout_batch_lines` + RPC `calculate_payment_allocation` / `create_payout_batch` + Dart models + PhaseTwoRepository methods + auto-wire checkout/pos | คำนวณ fee + payout end-to-end ได้แล้ว |
| **Delivery extensions** | **Complete** | base delivery + `shipments`, `shipment_items`, `carrier_configs`, `delivery_exceptions`, `proof_of_deliveries` + RPC (`record_delivery_exception`, `create_shipment`, `complete_delivery_with_proof`) + Dart models + PhaseTwoRepository/Notifier | logistics pipeline พร้อมใช้ |
| **Read Model / Analytics** | **Complete** | `projection_checkpoints` + `dashboard_snapshots` + `kpi_aggregations` + RPC (`upsert_dashboard_snapshot`, `generate_daily_snapshot`, `get_snapshot_comparison`, `upsert_kpi_aggregation`, `advance_projection_checkpoint`) + Dart models (`DashboardSnapshot`, `ProjectionCheckpoint`, `KpiAggregation`) + PhaseTwoRepository/Notifier | dashboard + KPI pipeline พร้อมใช้ |
| **Transaction Boundary / Reliability extras** | **Complete** | `idempotency_keys` + `outbox_events` + `inbox_events` + `transaction_contexts` (existing) + `transaction_audit_log` + `dead_letter_events` + `circuit_breaker_states` + `retry_attempts` + `rate_limit_policies` + `queue_job_audit` + `dead_letter_records` (migration `20260612140000_add_reliability_transaction_tables.sql`) + RPC (`record_audit_log`, `update_circuit_breaker`, `create_retry_attempt`, `resolve_dead_letter`) + Dart models (`TransactionAuditLog`, `CircuitBreakerState`, `RetryAttempt`, `DeadLetterRecord`) + PhaseZeroRepository methods | reliability infrastructure ครบ end-to-end พร้อมใช้ |

### Roadmap ถัดไปที่แนะนำ (เรียงลำดับทำจริง)

1. **~~ปิด Inventory runtime gap~~** ✅ **2026-06-12**
   - migration `20260612092000_add_inventory_runtime_functions.sql` (`release_stock_reservation`, `deduct_stock`, `cleanup_expired_reservations`)
   - `PhaseOneRepository` + `CheckoutPage` / `CounterPosPage` wire เรียบร้อย — กัน oversell + stock ค้างได้แล้ว

2. **~~เช็ก payment / checkout pipeline~~** ✅ **2026-06-12**
   - `confirm_checkout` bug (ตรวจ `status = 'paid'` แต่ session เป็น `'created'`) → แก้เป็น `IN ('created', 'payment_pending', 'paid')`
   - เพิ่ม `update_checkout_session_status()` RPC
   - `CheckoutPage` / `CounterPosPage` บันทึก `payment_transaction` + `checkout_session_id` link + อัปเดต `order.status = 'paid'` เรียบร้อย

3. **~~เติม Settlement ให้ครบ~~** ✅ **2026-06-12**
   - migration `20260612123000_add_settlement_rpc_functions.sql` (`calculate_payment_allocation`, `create_payout_batch`, `get_settlement_summary`)
   - Dart models: `MerchantAccount`, `PaymentAllocation`, `SettlementLedger`, `PayoutBatch`, `PayoutBatchLine`
   - `PhaseTwoRepository` + `PhaseTwoNotifier` methods ครบ CRUD
   - `CheckoutPage` / `CounterPosPage` auto-calculate allocation หลัง payment success
   - fee split + payout batch end-to-end พร้อมใช้

4. **~~เติม Delivery extensions~~** ✅ **2026-06-12**
   - migration `20260612130000_add_delivery_extensions.sql` (`shipments`, `shipment_items`, `carrier_configs`, `delivery_exceptions`, `proof_of_deliveries`)
   - RPC: `record_delivery_exception`, `create_shipment`, `complete_delivery_with_proof`, `update_route_stop_status`
   - Dart models: `DeliveryRun`, `RouteStop`, `Shipment`, `CarrierConfig`, `DeliveryException`, `ProofOfDelivery`
   - `PhaseTwoRepository` + `PhaseTwoNotifier` methods ครบ CRUD

5. **~~ค่อยทำ Read Model / Analytics pipeline~~** ✅ **2026-06-12**
   - migration `20260612130000_add_analytics_rpc_functions.sql` (`upsert_dashboard_snapshot`, `generate_daily_snapshot`, `get_snapshot_comparison`, `upsert_kpi_aggregation`, `advance_projection_checkpoint`)
   - Dart models: `DashboardSnapshot`, `ProjectionCheckpoint`, `KpiAggregation`
   - `PhaseTwoRepository` + `PhaseTwoNotifier` methods ครบ CRUD
   - dashboard + KPI pipeline พร้อมใช้

6. **~~ปิดความไม่สอดคล้องของ Reliability / Transaction sections~~** ✅ **2026-06-12**
   - migration `20260612140000_add_reliability_transaction_tables.sql` (`transaction_audit_log`, `dead_letter_events`, `circuit_breaker_states`, `retry_attempts`, `rate_limit_policies`, `queue_job_audit`, `dead_letter_records`)
   - RPC: `record_audit_log`, `update_circuit_breaker`, `create_retry_attempt`, `resolve_dead_letter`
   - Dart models: `TransactionAuditLog`, `CircuitBreakerState`, `RetryAttempt`, `DeadLetterRecord`
   - `PhaseZeroRepository` methods ครบ CRUD
   - reliability infrastructure ครบ end-to-end พร้อมใช้

### ตาราง Canonical Phase Ordering (ปรับปรุงหลังวิเคราะห์ 7 Core)

| ERP Phase | ชื่อ Phase | ระบบที่ต้องทำ | Steps ย่อย (จากเอกสารลูก) | เงื่อนไขขึ้นต่อ Phase ก่อน | ความปลอดภัย / ความเร็ว |
|---|---|---|---|---|---|
| **Phase 0** | Foundation & Identity + Reliability Core | Auth, User, Branch, Role/Permission, Organization Settings, **Reliability Core** | - Auth Service<br>- `organization_branches`, `organization_roles`, `employee_roles`, `role_module_permissions`<br>- **Reliability Step 1:** `idempotency_keys`, `outbox_events`, `inbox_events`, `transaction_contexts` | — | ถ้าไม่มี tenant isolation + reliability foundation ก่อน ระบบอื่นจะ checkout ไม่ปลอดภัย |

> **สถานะ Phase 0 (2026-06-12):** ✅ COMPLETE
> - **Migration Schema:** `20260611140000_erp_phase_0_reliability_rbac_feature_flags.sql`
>   - `inbox_events`, `transaction_contexts` (Reliability Core)
>   - `organization_roles`, `role_module_permissions`, `employee_roles` (RBAC)
>   - `organization_feature_flags` (Feature Toggles)
>   - RPC functions: `get_user_roles_and_permissions`, `get_profession_feature_flags`, `upsert_feature_flag`, `create_transaction_context`, `update_transaction_context`
> - **Migration Schema:** `20260609180000_create_accounting_core_schema.sql` (existing)
>   - `outbox_events`, `idempotency_keys` (Reliability Core)
> - **Migration Schema:** `20260612140000_add_reliability_transaction_tables.sql` (new)
>   - `transaction_audit_log`, `dead_letter_events` (Transaction Boundary)
>   - `circuit_breaker_states`, `retry_attempts`, `rate_limit_policies`, `queue_job_audit`, `dead_letter_records` (Reliability Core)
>   - RPC functions: `record_audit_log`, `update_circuit_breaker`, `create_retry_attempt`, `resolve_dead_letter`
> - **Migration Seed:** `20260611150000_seed_phase_0_defaults.sql`
>   - System roles: `owner`, `admin`, `manager`, `staff`, `cashier`, `accountant`
>   - Default permissions ตามบทบาท (Owner=Full, Cashier=POS+Cart, etc.)
>   - Default feature flags (ทั้งหมด disabled — secure by default)
> - **Flutter Layer:**
>   - Models: `OrganizationRole`, `RoleModulePermission`, `EmployeeRole`, `OrganizationFeatureFlag`, `TransactionAuditLog`, `CircuitBreakerState`, `RetryAttempt`, `DeadLetterRecord`
>   - Repository: `PhaseZeroRepository` (RBAC + Feature Flags + Transaction Context + Reliability / Audit / Circuit Breaker / Dead Letter / Retry)
>   - Provider: `PhaseZeroNotifier` + `phaseZeroProvider` (พร้อม `hasModulePermission()`, `isFeatureEnabled()`, `toggleFeatureFlag()`)
>   - UI Pages: `RoleManagementPage`, `PermissionManagementPage`, `FeatureFlagsPage` (ใช้ GlassCard + responsive)
>   - Routes: `/erp/roles`, `/erp/feature-flags`
> - **Existing (ไม่ต้องสร้างใหม่):** `users`, `professions`, `organization_branches`, `outbox_events`, `idempotency_keys`
| **Phase 1** | Data & Inflow | CRM + Procurement + **Inventory Core (พื้นฐาน)** + Product/Service Master | - CRM Step 1-3: Schema, Loyalty, Coupon<br>- Procurement Step 1: PR/PO Schema<br>- **Inventory Step 1:** `inventory_lots`, `warehouse_locations`, `stock_movements`, `inventory_reservations`<br>- Product/Service Catalog (shared master) | Phase 0 | รองรับ zero-mock integration test ได้เพราะมี customer + stock + reservation จริง |

> **สถานะ Phase 1 (2026-06-12):** ✅ COMPLETE
> - **Migration Schema:** `20260611160000_erp_phase_1_data_and_inflow.sql`
>   - **Product Master:** `product_categories`, `products` (shared master สำหรับ POS + Cart)
>   - **CRM:** `loyalty_tiers`, `customers`, `loyalty_points`, `coupons`, `coupon_redemptions`
>   - **Procurement:** `suppliers`, `purchase_requisitions`, `purchase_orders`, `purchase_order_items`
>   - **Inventory Core:** `warehouse_locations`, `inventory_lots` (FEFO), `stock_movements` (ledger), `inventory_reservations` (oversell prevention)
>   - **RPC functions:** `get_product_stock_summary`, `get_product_total_stock`, `get_product_reserved_quantity`, `get_product_available_stock`, `create_inventory_reservation`, `update_customer_stats`
> - **Migration Schema ใหม่:** `20260612150000_add_inventory_system.sql`
>   - **Custom Medications:** `custom_medications` (tenant-specific products)
>   - **Inventory Items:** `inventory_items` (stock summary + cost/selling/reorder)
>   - **Stocktake:** `stocktake_configurations`, `stocktake_sessions`, `stocktake_lines`
>   - **Adjustments & Transfers:** `stock_adjustments`, `inventory_transfers`, `inventory_transfer_lines`
>   - **Alerts:** `inventory_alerts` (low_stock, expiry, reorder)
>   - **RPC functions:** `deduct_inventory_fefo`, `create_stock_adjustment`, `create_inventory_transfer`, `complete_inventory_transfer`, `check_inventory_alerts`, `complete_stocktake_session`
> - **Migration Seed:** `20260611161000_seed_phase_1_sample_data.sql`
>   - Product categories, sample products, loyalty tiers, warehouse locations, sample suppliers
> - **Flutter Layer:**
>   - Models: `Product`, `Customer`, `Supplier`, `InventoryLot`, `InventoryItem`, `CustomMedication`, `StocktakeConfiguration`, `StocktakeSession`, `StockAdjustment`, `InventoryTransfer`, `InventoryAlert`
>   - Repository: `PhaseOneRepository` (Products, Customers, Suppliers, Inventory, Coupons, POs + Inventory System CRUD + FEFO)
>   - Provider: `PhaseOneNotifier` + `phaseOneProvider` (พร้อม helper `lowStockProducts`, `expiringLots`, `expiredLots`, `inventoryItems`, `inventoryAlerts`)
>   - UI Pages: `ProductListPage`, `CustomerListPage`, `SupplierListPage`, `InventoryPage` (ใช้ GlassCard + TabBar)
>   - Routes: `/erp/products`, `/erp/customers`, `/erp/suppliers`, `/erp/inventory`
> - **Integration:** รองรับ zero-mock — product → inventory lot → stock movement → customer → สร้าง order ใน Phase 2 ได้ทันที + FEFO deduction ตัดสต๊อกอัตโนมัติ
| **Phase 2** | Core Commerce & Platform | **Commerce Core** + **Cart Core** + Payment + **Settlement Core (พื้นฐาน)** + **Delivery Core (พื้นฐาน)** | - **Commerce Step 1:** `orders`, `order_items`, `payment_transactions`, `checkout_sessions`<br>- **Cart Step 1-2:** `cart_sessions`, `cart_items`, `cart_merchant_groups` (split logic)<br>- **Settlement Step 1:** `vendor_contracts`, `merchant_accounts`, `payment_allocations` (fee/payout ตอน checkout)<br>- Payment Gateway Integration<br>- **Logistics Step 1:** `delivery_orders`, `riders`, `delivery_runs`, `route_stops`, `POD` | Phase 1 | POS ต้องมี Inventory Reservation + Settlement Contract ก่อนจึงไม่เกิด orphan order หรือ split ที่คำนวณไม่ได้ |

> **สถานะ Phase 2 (2026-06-11):** ✅ COMPLETE
> - **Migration Schema:** `20260611170000_erp_phase_2_core_commerce.sql`
>   - `checkout_sessions` (state machine: created → payment_pending → paid → confirmed → cancelled → expired)
>   - `payment_transactions` (PromptPay, cash, credit_card + provider_txn_id)
>   - `delivery_orders` (pending → preparing → in_transit → delivered)
> - **Migration Schema:** `20260611171000_erp_phase_2_settlement_logistics_cart.sql`
>   - **Settlement Core:** `vendor_contracts`, `merchant_accounts`, `payment_allocations`
>   - **Logistics Core:** `riders`, `delivery_runs`, `route_stops`
>   - **Cart Core:** `cart_sessions`, `cart_items`, `cart_merchant_groups`
>   - RPC: `calculate_payment_allocation`, `assign_delivery_to_rider`, `add_item_to_cart`
> - **Migration Seed:** `20260611172000_seed_phase_2_sample_data.sql`
>   - 3 riders, 3 vendor contracts, 2 merchant accounts
> - **Existing Tables (from POS Core):** `orders`, `order_items`, `unified_payments`, `shopping_carts`, `clinic_services`, `clinic_appointments`
> - **Flutter Layer:**
>   - Models: `CheckoutSession`, `PaymentTransaction`, `DeliveryOrder`, `VendorContract`, `CartSession`, `CartItem`, `Rider`
>   - Repository: `PhaseTwoRepository` (Checkout, Payment, Delivery, Settlement, Cart, Logistics)
>   - Provider: `PhaseTwoNotifier` + `phaseTwoProvider` (รองรับ cart, checkout, payment, delivery, vendor contracts)
>   - UI Pages: `CartPage`, `CheckoutPage`, `OrderSuccessPage`, `CounterPosPage` (Mode B), `ClinicPosPage` (Mode C), `DeliveryOrdersPage`, `VendorContractsPage`
>   - Routes: `/erp/cart`, `/erp/checkout`, `/erp/pos/counter`, `/erp/pos/clinic`, `/erp/delivery`, `/erp/vendor-contracts`, `/order/success`
>   - RPC เพิ่มเติม: `remove_item_from_cart`
> - **Integration:** `CounterPosPage` → `orders`/`order_items` (existing POS Core); `CartPage` → `cart_sessions`/`cart_items` (normalized) + `shopping_carts` (JSONB fallback)
| **Phase 3** | Finance & Operations + Read Model / Analytics Core | Accounting + HR + **Settlement Core (ส่วนขยาย)** + **Read Model / Analytics Core** | - Accounting Step 1: GL, AP/AR<br>- HR Step 1: Employee, Shift<br>- **Settlement Step 2:** `settlement_ledgers`, `payout_batches`, `payout_batch_lines`<br>- **Read Model Step 1:** `projection_checkpoints`, `dashboard_snapshots`, `kpi_aggregations` | Phase 2 | บันทึกรายได้/รายจ่าย + สร้าง read model ต้องมี order จริงก่อน แต่ไม่ต้องรอ clinical |

> **สถานะ Phase 3 (2026-06-12):** ✅ COMPLETE
> - **Migration Schema:** `20260611180000_erp_phase_3_finance_operations.sql`
>   - **Accounting Core:** `chart_of_accounts`, `gl_entries`, `accounts_receivable`, `accounts_payable`
>   - **HR Core:** `employees`, `shifts`
>   - **Settlement Step 2:** `settlement_ledgers`, `payout_batches`, `payout_batch_lines`
>   - **Read Model Core:** `projection_checkpoints`, `dashboard_snapshots`, `kpi_aggregations`
>   - RPC: `create_gl_from_order`, `upsert_dashboard_snapshot`
> - **Migration Schema ใหม่:** `20260612080000_add_payment_channels_and_tax_validation.sql`
>   - **Payment Channels Core:** `payment_channels` (channel_code, channel_name, channel_type, is_enabled, is_default, config JSONB, fee_percent, display_order, icon_name)
>   - **RLS:** `payment_channels_select` (public) + `payment_channels_modify` (owner/admin via `employee_roles`)
>   - **RPC:** `seed_default_payment_channels(p_profession_id)` — seed cash/PromptPay/credit_card
>   - **Validation:** `validate_branch_tax_code(p_branch_tax_code TEXT)` — ตัวเลข 5 หลัก (00000 = สำนักงานใหญ่)
> - **Flutter Layer:**
>   - Models: `Employee`, `GlEntry`, `DashboardSnapshot`
>   - Repository: `PhaseThreeRepository` (HR, GL, Dashboard Snapshots)
>   - Provider: `PhaseThreeNotifier` + `phaseThreeProvider`
>   - UI Pages: `EmployeeListPage`, `GlEntriesPage`, `DashboardAnalyticsPage`, `PaymentChannelsPage`
>   - Routes: `/erp/employees`, `/erp/gl-entries`, `/erp/analytics`, `/erp/payment-channels`
> - **Integration:** `create_gl_from_order()` auto-debits cash + credits revenue จาก `orders.grand_total`; `CounterPosPage` → `OrderRepository.createOrderFromCart()` → `orders` + `order_items` → สร้าง GL อัตโนมัติ
> - **Compile Status:** `flutter run` ✅ (exit code 0) — SM X135G, ERP Dashboard "แพทย์ทั่วไป" โหลดสำเร็จ
| **Phase 4** | Clinical & Advanced | HIS + LIS + Telemedicine + CDP | - HIS Step 1: EMR, OPD<br>- LIS Step 1: External Lab API<br>- Telemedicine Step 1: Video/Chat Integration<br>- CDP Step 1: Customer cohort, analytics enrichment | Phase 1-3 | ระบบ clinical ซับซ้อน ควรต่อยอดหลัง core commerce + read model พร้อม |

> **สถานะ Phase 4 (2026-06-11):** ✅ COMPLETE
> - **Migration Schema:** `20260611190000_erp_phase_4_clinical_advanced.sql` ✅ **สำเร็จ**
>   - **HIS Step 1:** `emr_records`, `opd_visits`, `medical_prescriptions`, `medical_prescription_items`, `vitals`
>   - **LIS Step 1:** `lab_tests`, `lab_results`, `lab_external_requests`
>   - **Telemedicine Step 1:** `tele_consultations` (ใช้ existing `consultation_requests` + `chat_rooms`)
>   - **CDP Step 1:** `customer_cohorts`, `cohort_members`, `analytics_events`
>   - RPC: `create_opd_visit()` (auto queue number), `add_patient_to_cohort()`
> - **Flutter Layer สร้างแล้ว:**
>   - Models: `EmrRecord`, `OpdVisit`
>   - Repository: `PhaseFourRepository` (EMR, OPD, Prescriptions, Lab, Cohorts)
>   - Provider: `PhaseFourNotifier` + `phaseFourProvider`
>   - UI Pages: `EmrListPage`, `OpdVisitPage`, `PrescriptionPage`, `LabResultsPage`, `PatientCohortPage`
>   - Routes: `/clinical/emr`, `/clinical/opd`, `/clinical/prescriptions`, `/clinical/lab`, `/clinical/cohorts`
> - **Compile Status:** `flutter run` ✅ (exit code 0) — SM X135G, ERP Dashboard "แพทย์ทั่วไป" โหลดสำเร็จ
| **Phase 5** | Commerce Polish + Loyalty + Reports | POS Refund + CRM Loyalty Auto + KPI Export | - POS Step 5: Refund requests + review workflow<br>- CRM Step 5: Loyalty auto-calculation at checkout<br>- KPI Step 5: PDF/Excel export + scheduled reports | Phase 1-4 | ต่อยอด commerce ที่มีอยู่ ไม่ต้องใช้ external service |

> **สถานะ Phase 5 (2026-06-11):** ✅ COMPLETE
> - **Migration Schema:** `20260611200000_erp_phase_5_polish_loyalty_reports.sql` ✅
>   - **POS Step 5:** `refund_requests` (order_id, amount, reason, status, requested_by, reviewed_by)
>   - **CRM Step 5:** `loyalty_point_rules` (profession_id, points_per_baht, bonus_multiplier) — ใช้ existing `loyalty_points`
>   - **KPI Step 5:** `scheduled_reports` (profession_id, report_type, frequency, last_run_at, next_run_at)
>   - RPC: `request_refund()`, `review_refund()`, `calculate_loyalty_points()`, `generate_report_payload()`
> - **Flutter Layer สร้างแล้ว:**
>   - Models: `RefundRequest`, `LoyaltyRule`, `ScheduledReport`
>   - Repository: `PhaseFiveRepository` (Refund, Loyalty, Reports)
>   - Provider: `PhaseFiveNotifier` + `phaseFiveProvider`
>   - UI Pages: `RefundListPage`, `LoyaltyRulesPage`, `ReportExportPage`
>   - Routes: `/erp/refunds`, `/erp/loyalty`, `/erp/reports`
> - **Compile Status:** `flutter run` ✅ (exit code 0)

> **Implementation rule:** เมื่อเริ่มลงมือทำ ให้ยึดตารางนี้เป็นแหล่งอ้างอิงเดียวสำหรับลำดับงานทั้งหมด และอ้างอิงชื่อขั้นงานย่อยตาม `ERP Phase X / [System] Step Y` เสมอ เพื่อไม่ให้ phase numbering ของเอกสารลูกคลาดเคลื่อนจาก canonical order ข้างต้น

**กฎสำหรับเอกสารลูก:**
- ทุกเอกสารย่อย (POS, CRM, etc.) ต้องระบุ `ERP Phase X / [System] Step Y` แทนการใช้ `Phase 1` ของตัวเอง
- ถ้าเอกสารลูกมี steps มากกว่า 1 ใน phase เดียวกัน ให้ขนานกันได้ (เช่น CRM Step 1-3 ทำพร้อมกันใน Phase 1)
- ถ้าเอกสารลูกต้องการเริ่มก่อน upstream เสร็จ ให้ใช้ **mock contract + interface** แต่ห้าม merge ลง production จนกว่า upstream phase จะผ่าน integration test
- **เอกสารลูกห้าม duplicate DDL — อ้างอิง schema จาก `ERP_CORE_ARCHITECTURE.md` เท่านั้น:** เอกสารลูกกล่าวถึง business logic / UI flow / API contract เท่านั้น ไม่เขียน `CREATE TABLE` ซ้ำ — ถ้า master เปลี่ยน schema เอกสารลูกไม่ต้องแก้ (เพราะไม่มี schema ซ้ำ)
- **Change Propagation:** เมื่อ `ERP_CORE_ARCHITECTURE.md` อัปเดต schema ของ core ใดๆ เอกสารลูกที่เกี่ยวข้องต้องได้รับการทำเครื่องหมาย `[STALE — รอ sync]` และต้องอัปเดตภายใน 1 sprint

### ตาราง Canonical Ownership Model

| Domain | Canonical Owner | Mirror / Replica | ข้อมูลสำคัญ |
|---|---|---|---|
| **Cart Intent** | Platform | — | snapshot ราคา, สต๊อกตอน checkout |
| **Order (Customer View)** | Platform Orders | — | ประวัติการซื้อของลูกค้า |
| **Order (Merchant Fulfillment)** | ERP/POS | Platform (mirror) | ตัดสต๊อก, จัดส่ง, ใบเสร็จ |
| **Delivery Tracking** | Logistics Module | POS (terminal state) | assigned → delivered |
| **Payment** | Platform | — | รับเงิน, split, payout |
| **Accounting (Merchant GL)** | Accounting Module | — | รายได้, ภาษี, ค่าใช้จ่าย |
| **Accounting (Platform GL)** | Platform Accounting | — | platform fee, payout liability |
| **Reliability Core** | Platform (infrastructure team) | — | `outbox_events`, `idempotency_keys`, `circuit_breaker_states` — cross-cutting infrastructure |
| **Inventory Core** | Inventory Module / ERP | Platform (read-only mirror via outbox) | `inventory_lots`, `inventory_reservations` — write ผ่าน `InventoryRepository` เท่านั้น |
| **Settlement Core** | Platform Accounting | Merchant Module (event consumer) | `vendor_contracts`, `payment_allocations`, `payout_batches` — คำนวณที่ Platform ส่ง event ให้ Merchant Accounting |
| **Read Model / Analytics Core** | Platform (infrastructure worker) | แต่ละ Module (data source via outbox) | `dashboard_snapshots`, `projection_checkpoints` — module ต่างๆ ส่ง event ให้ worker ประมวลผล ไม่เขียนตรง |

> **กลยุทธ์ Mirror / Replica:** `outbox_events` เป็น canonical channel เดียวสำหรับ cross-module sync — ไม่ให้ module อื่น update ตารางของ module ตรงๆ หรือ query foreign DB โดยตรง

### ข้อสรุปเชิงปฏิบัติ

- **ควรใช้ ERP Core นี้เป็น master reference สำหรับ data ownership และ transaction flow**
- **Delivery และ Shopping Cart ควรถูกมองเป็น execution layer ที่ต่อกับ commerce core ไม่ใช่ระบบแยกอิสระ**
- **ก่อนขยายฟีเจอร์ใหม่ ควรล็อก model กลางและ consistency strategy ให้เสร็จ**
- **หากต้องรองรับ concurrent สูงจริง ต้องออกแบบไปทาง event-driven + read model + idempotent write ตั้งแต่ต้น**
- **Data Migration — Strangler Fig + Dual-Write:** ยุบตารางซ้อนทับ (`platform_shopping_cart` + POS `shopping_carts` → `cart_sessions`) ต้องทำผ่าน dual-write (write ทั้งตารางเก่าและใหม่พร้อมกัน 1-2 sprint) แล้วค่อย redirect foreign key และ drop ตารางเก่า — ไม่มี downtime รองรับ rollback
- **Mirror / Replica ผ่าน Outbox Pattern:** Module ที่เป็น canonical owner เท่านั้นเขียนตารางตัวเอง แล้ว publish event ผ่าน `outbox_events` — module อื่นอ่านผ่าน event ไม่ query DB ตรง
- **RLS อยู่ที่ Application Layer (Repository Pattern):** เนื่องจากใช้ custom `AuthService` ผ่าน `ServiceLocator` แทน Supabase Auth native → RLS policy ไม่ใช้ที่ PostgreSQL layer แต่ audit ทุก repository ให้ inject `userId` จาก `ServiceLocator` ถูกต้อง

---

### สิ่งที่ยังไม่ได้เชื่อมต่อตามแผน

รายการนี้ถูกแบ่งเป็น 3 กลุ่มตามความเร่งด่วนและ Phase Ordering:

#### กลุ่ม A: Current Blockers (ต้องแก้ก่อนเริ่ม Phase ใดๆ)

| ลำดับ | รายการ | เหตุผลที่เป็น Blocker |
|---|---|---|
| 1 | **Feature Toggles** — `organization_feature_flags` ยังไม่ถูกนำมาใช้ในการเปิด/ปิดโมดูล UI | ถ้าไม่มี ทุก module ที่ merge ใน Phase 2-3 จะมองเห็นทั้งหมทั้งหมดตั้งแต่ Phase 0 → security risk |
| 2 | **Permission Page UI** — ยังไม่มีหน้าจอสำหรับจัดการสิทธิ์ (`Permission Management Page`) | Phase 0 ระบุว่ามี Role/Permission แต่จริงๆ ไม่มีที่ให้ admin จัดการ RBAC → ใช้ default role ทุกคน |
| 3 | **Routing + Dashboard onTap** — `/erpHome`, `/erpDashboard`, `/posManagement` ยังไม่ได้กำหนด route ใน `MaterialApp` และ `ErpDashboardPage` onTap ยังเป็น placeholder | Navigation ขาด → user ไปไม่ถึง module ที่ implement แล้ว |
| 4 | **HomeErpCard → ErpHomePage** — navigation จาก `HomeErpCard` ยังไม่อัปเดต | Minor blocker — user คลิกจาก Home แล้วไม่เข้า ERP |

#### กลุ่ม B: Future Work (ตาม Phase Ordering)

| Phase | รายการ | หมายเหตุ |
|---|---|---|
| **Phase 1** | **Procurement Management UI**, **CRM Management UI**, **Inventory Management UI** | Schema มีแล้ว (`inventory_lots`, `stock_movements`, `warehouse_locations`) แต่ไม่มีหน้าจอให้ admin จัดการ |
| **Phase 2** | **Cart / Checkout UI**, **Delivery / Logistics UI**, **POS Mode B/C UI** | `SHOPPING_CART_PLAN.md` มี schema เก่า 3 ตาราง — ต้องสร้าง UI สำหรับ `cart_sessions` ใหม่; `Delivery_PLAN.md` เป็น documentation-only |
| **Phase 3** | **Accounting Management UI**, **HR Management UI**, **Settlement / Payout UI**, **KPI Dashboard UI** | `KPI_DASHBOARD_PLAN.md` มีแผนแต่ไม่มีหน้าจอ; Settlement ต้องรอ Phase 3 (`payout_batches`, `settlement_ledgers`) |
| **Phase 4** | **HIS / LIS / Telemedicine UI** | รอ core commerce + read model พร้อม |

#### กลุ่ม C: Infrastructure (ไม่มี Phase แต่ต้องมี)

| รายการ | เหตุผล | ความสำคัญ |
|---|---|---|
| **Outbox / Idempotency Monitor UI** | ต้องดู `outbox_events`, `dead_letter_records`, `circuit_breaker_states` ได้เพื่อ debug event-driven system | **P2** — ถ้า event หายจะไม่รู้ว่าเกิดอะไร |
| **Subscription Schema → Phase Mapping** | `subscription_plans` (line 2555) อยู่นอก Phase Ordering — ควร map ว่าอยู่ Phase ไหน (Phase 0 หรือ add-on?) | **P2** — ไม่ชัดว่าเป็น foundation หรือ business feature |
| **Migration Tool / Backfill Runner** | Strangler Fig + Dual-Write ต้องการเครื่องมือ run backfill script (`cart_sessions` จากตารางเก่า 2 ชุด) | **P2** — ถ้าไม่มีเครื่องมือ backfill จะต้องทำมือ |

*หมายเหตุ: สามารถคลิกที่ชื่อแต่ละระบบเพื่อเข้าไปดู/แก้ไขรายละเอียดแผนงานเชิงลึกได้*สร้างฐานข้อมูล (Subscription Schema)

```sql
-- 1. แพลนการสมัคร (สร้างโดย Sheserved Admin / ERP Service Manager)
> **สถานะ:** 🔴 ยังไม่ implement — เป็น schema แนะนำสำหรับอนาคต (subscription plans, quotas, billing)
CREATE TABLE subscription_plans (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_name         TEXT NOT NULL,                          -- เช่น 'Starter', 'Pro', 'Enterprise'
  plan_description  TEXT,
  billing_cycle     TEXT NOT NULL DEFAULT 'MONTHLY',        -- 'MONTHLY', 'YEARLY'
  price             DECIMAL(12,2) NOT NULL DEFAULT 0,       -- ราคา (บาท)
  trial_days        INTEGER NOT NULL DEFAULT 30,            -- จำนวนวันทดลองใช้
  is_custom         BOOLEAN DEFAULT false,                  -- true = แพลนพิเศษเฉพาะองค์กร
  target_profession_id UUID REFERENCES professions(id),     -- ถ้าเป็น Custom Plan → ระบุองค์กรเป้าหมาย (NULL = แพลนกลาง)
  required_erp_phase TEXT NOT NULL DEFAULT 'Phase 0',       -- Phase ขั้นต่ำที่ต้องเสร็จก่อนขายแพลนนี้ ('Phase 0'-'Phase 4')
  minimum_core_version TEXT NOT NULL DEFAULT '1.0.0',       -- Semantic version ของ core schema ที่ compatible
  is_active         BOOLEAN DEFAULT true,
  created_by        UUID NOT NULL REFERENCES users(id),     -- ERP Service Manager ที่สร้าง
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- 2. โมดูลที่เปิดใช้ได้ในแต่ละแพลน + โควต้า
CREATE TABLE subscription_plan_modules (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id           UUID NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  module_name       TEXT NOT NULL,  -- 'pos', 'inventory', 'procurement', 'accounting', 'hr', 'crm', 'his', 'lis', 'telemedicine', 'logistics', 'reliability', 'commerce', 'cart', 'settlement', 'read_model'
                                    -- หมายเหตุ: 'reliability' เป็น always-on infrastructure — ไม่ให้ปิด (is_enabled ต้องเป็น true เสมอ)
  is_enabled        BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (plan_id, module_name)
);

-- 3. โควต้าจำกัดการใช้งานของแต่ละแพลน
CREATE TABLE subscription_plan_quotas (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id           UUID NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  quota_key         TEXT NOT NULL,  -- เช่น 'max_patients', 'max_pos_transactions_per_day', 'max_reports_per_month'
  quota_value       INTEGER NOT NULL DEFAULT -1,            -- -1 = ไม่จำกัด (Unlimited)
  UNIQUE (plan_id, quota_key)
);

-- 4. การสมัครของแต่ละองค์กร (1 องค์กร : 1 Active Subscription)
CREATE TABLE organization_subscriptions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  plan_id           UUID NOT NULL REFERENCES subscription_plans(id),
  status            TEXT NOT NULL DEFAULT 'TRIAL',
                    -- 'TRIAL', 'ACTIVE', 'EXPIRED', 'SUSPENDED'
  is_internal_free  BOOLEAN DEFAULT false,                  -- true = ยกเว้นค่าธรรมเนียมสำหรับสาขา/องค์กรภายในของ Sheserved เอง
  trial_start_date  DATE NOT NULL DEFAULT CURRENT_DATE,
  trial_end_date    DATE NOT NULL,                          -- วันหมดทดลอง
  subscription_start_date DATE,                             -- วันเริ่มสมัครจริง (หลังชำระเงิน)
  subscription_end_date   DATE,                             -- วันหมดอายุสมาชิก
  payment_method    TEXT,           -- 'CREDIT_CARD', 'BANK_TRANSFER', 'FREE_INTERNAL'
  auto_renew        BOOLEAN DEFAULT false,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- 5. ประวัติการเปลี่ยนแปลง Subscription (Audit Trail)
CREATE TABLE subscription_change_log (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id   UUID NOT NULL REFERENCES organization_subscriptions(id) ON DELETE CASCADE,
  changed_field     TEXT NOT NULL,  -- 'plan_id', 'status', 'is_internal_free', 'trial_end_date', 'subscription_end_date'
  old_value         TEXT,
  new_value         TEXT NOT NULL,
  reason            TEXT,           -- เหตุผลการเปลี่ยนแปลง (เช่น 'upgrade_plan', 'free_waiver_approved', 'trial_expired')
  actor_id          UUID NOT NULL REFERENCES users(id),  -- ใครเป็นคนเปลี่ยน
  actor_role        TEXT NOT NULL DEFAULT 'system',     -- 'system', 'erp_service_manager', 'organization_owner', 'payment_gateway'
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_subscription_change_log_subscription ON subscription_change_log(subscription_id, created_at DESC);

-- 6. ประวัติการชำระเงินค่า Subscription
CREATE TABLE subscription_payments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id   UUID NOT NULL REFERENCES organization_subscriptions(id) ON DELETE CASCADE,
  amount            DECIMAL(12,2) NOT NULL,
  payment_method    TEXT NOT NULL,  -- 'CREDIT_CARD', 'BANK_TRANSFER'
  payment_status    TEXT NOT NULL DEFAULT 'PENDING',
                    -- 'PENDING', 'COMPLETED', 'FAILED', 'REFUNDED'
  transaction_ref   TEXT,           -- เลขอ้างอิงธุรกรรม
  approved_by       UUID REFERENCES users(id),               -- ERP Service Manager ที่อนุมัติ (กรณี BANK_TRANSFER)
  paid_at           TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- 6. ตัวนับการใช้งานจริง (Usage Counters) — Reset ตามรอบบิลลิ่ง
CREATE TABLE organization_usage_counters (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  quota_key         TEXT NOT NULL,  -- ต้องตรงกับ subscription_plan_quotas.quota_key
  current_value     INTEGER NOT NULL DEFAULT 0,
  period_start      DATE NOT NULL,
  period_end        DATE NOT NULL,
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, quota_key, period_start)
);

-- RLS
ALTER TABLE subscription_plans             ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_plan_modules      ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_plan_quotas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_subscriptions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_change_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_payments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_usage_counters    ENABLE ROW LEVEL SECURITY;
```

### ตัวแปรโควต้ามาตรฐาน (Standard Quota Keys)

โมดูลใหม่ทุกตัวใน ERP จะถูกเพิ่ม `quota_key` เข้าตาราง `subscription_plan_quotas` โดยอัตโนมัติ:

| Module | quota_key | คำอธิบาย |
|--------|-----------|----------|
| **POS** | `max_pos_transactions_per_day` | จำนวนรายการขายต่อวัน |
| **POS** | `max_pos_branches` | จำนวนสาขาที่เปิดใช้ POS |
| **Inventory** | `max_inventory_skus` | จำนวน SKU สินค้าในคลัง |
| **Procurement** | `max_purchase_orders_per_month` | จำนวน PO ต่อเดือน |
| **Accounting** | `max_reports_per_month` | จำนวนรายงานบัญชีที่ออกได้ต่อเดือน |
| **HR** | `max_employees` | จำนวนพนักงานในระบบ |
| **CRM** | `max_patients` | จำนวนลูกค้า/ผู้ป่วยในระบบ |
| **CRM** | `max_coupons` | จำนวนคูปองที่สร้างได้ |
| **HIS/EMR** | `max_visits_per_month` | จำนวน Visit ที่เปิดได้ต่อเดือน |
| **HIS/EMR** | `max_medical_documents_per_month` | จำนวนเอกสารทางการแพทย์ที่พิมพ์ได้ |
| **LIS** | `max_lab_orders_per_month` | จำนวนใบสั่งตรวจแล็บต่อเดือน |
| **Telemedicine** | `max_teleconsult_minutes_per_month` | จำนวนนาทีวิดีโอคอลต่อเดือน |
| **Logistics** | `max_delivery_rounds_per_month` | จำนวนรอบจัดส่งต่อเดือน |
| **Global** | `max_branches` | จำนวนสาขาสูงสุดที่เปิดได้ |
| **Infrastructure** | `max_outbox_events_per_minute` | จำนวน outbox events ที่สร้างได้ต่อนาที |
| **Infrastructure** | `max_concurrent_checkouts` | จำนวน checkout พร้อมกันสูงสุด |
| **Infrastructure** | `max_dashboard_queries_per_hour` | จำนวน dashboard queries ต่อชั่วโมง |
| **Infrastructure** | `max_inventory_reservation_ttl_minutes` | เวลาสูงสุดที่ stock ถูก reserve ก่อน auto-release |
| **Infrastructure** | `max_circuit_breaker_recovery_per_hour` | จำนวน recovery จาก circuit breaker ต่อชั่วโมง |

### กระบวนการทำงาน (Subscription Workflow)

1. **องค์กรลงทะเบียน:** Sheserved Admin อนุมัติ → ระบบสร้าง `organization_subscriptions` สถานะ `TRIAL` พร้อมกำหนด `trial_end_date`
2. **ช่วงทดลอง:** องค์กรใช้ทุกโมดูลได้เต็มระบบ ไม่จำกัดโควต้า
3. **หมดช่วงทดลอง:** ระบบเปลี่ยนสถานะเป็น `EXPIRED` → ทุกโมดูลแสดงเป็น **Locked** (กดแล้วขึ้นหน้า Upgrade)
4. **สมัครแพลน:** องค์กรเลือกแพลนและชำระเงิน (Credit Card ตัดอัตโนมัติ หรือ โอนเงินแล้ว ERP Service Manager กดอนุมัติ)
5. **ใช้งานตามโควต้า:** ระบบตรวจสอบ `organization_usage_counters` เทียบกับ `subscription_plan_quotas` ก่อนทุกการกระทำสำคัญ → หากเกินโควต้าจะแสดงข้อความแจ้งเตือนให้อัปเกรดแพลน
6. **ต่ออายุ:** หากตั้งค่า `auto_renew = true` ระบบจะพยายามตัดบัตรเครดิตอัตโนมัติเมื่อใกล้หมดอายุ หากตัดไม่ได้ → แจ้งเตือน → หากไม่ดำเนินการภายใน Grace Period → สถานะเปลี่ยนเป็น `SUSPENDED`

### การตรวจสอบโควต้าในระบบ (Quota Enforcement Logic)

ระบบจะตรวจสอบโควต้า **ที่ PostgreSQL Layer (RPC Function)** เพื่อให้ทำงานได้ทั้งจาก Flutter App และ Background Worker:

```
Entry Point (Flutter App หรือ Worker)
  → เรียก Supabase RPC: check_quota(profession_id, quota_key, increment_amount)
    → PostgreSQL Function ตรวจสอบ is_internal_free + plan_quota + usage_counter
      → อนุญาต / ปฏิเสธ พร้อม return remaining_quota
```

ขั้นตอน:
1. **ทุก write operation** (ทั้งจาก Flutter Repository และ background worker) ต้องผ่าน `check_quota()` RPC **ก่อน** commit transaction
2. `check_quota()` ดึง subscription ปัจจุบัน + ตรวจสอบ `is_internal_free`
3. หาก `is_internal_free = true` → ยกเว้น → อนุญาตทันที (ไม่นับ counter)
4. หาก `quota_value = -1` (Unlimited) → อนุญาตทันที (ไม่ตรวจสอบ ceiling)
5. หาก `current_value + increment_amount <= quota_value` → อนุญาต → `current_value += increment_amount` (ใช้ `SELECT ... FOR UPDATE` กัน race condition)
6. หาก `current_value + increment_amount > quota_value` → ปฏิเสธ → return error code `QUOTA_EXCEEDED` → Flutter แสดง UpgradeDialog / Worker เก็บ dead_letter

> **เหตุผล:** QuotaGuard อยู่ที่ PostgreSQL layer แทน Flutter Middleware → worker ที่ consume outbox events ก็ถูกนับ quota เท่ากัน → ไม่มี under-count หรือ over-count

---

## รายละเอียดหน้าจอและการทำงาน (UI/UX Screen Specifications)

### 1. หน้าจอแจ้งเตือนและอัปเกรดแพลน (Upgrade Dialog / Locked State Screen)

เมื่อองค์กรพยายามเข้าใช้งานโมดูลที่ไม่ได้อยู่ในแพลน หรือมีสิทธิ์การใช้งาน (Quota) เต็มขีดจำกัดแล้ว ระบบจะแสดง Dialog หรือ Bottom Sheet สำหรับอัปเกรดแพลนทันที

#### A. กรณีเข้าใช้งานโมดูลที่ถูกล็อก (Locked Module Clicked)
- **พฤติกรรม (Behavior):** แสดงเป็นหน้าจอ Overlay หรือ Bottom Sheet ด้านล่าง โดยมีลักษณะกึ่งหน้าต่างป๊อปอัป มีดีไซน์แบบ Glassmorphism สวยงาม โดดเด่น
- **รายละเอียดที่แสดงในหน้าจอ:**
  - **ไอคอนโมดูลและชื่อโมดูล** ที่ต้องการเข้าใช้งาน (เช่น "โมดูลเวชระเบียน HIS" หรือ "ระบบแล็บ LIS")
  - **สถานะปัจจุบัน:** แสดงป้ายกำกับโดดเด่น เช่น `ทดลองใช้สิ้นสุดแล้ว` หรือ `ไม่อยู่ในแพลนปัจจุบันของคุณ`
  - **ข้อเสนอการอัปเกรด (Upgrade Offers):** แสดงการ์ดแพลนแนะนำที่รองรับโมดูลนี้ (เปรียบเทียบความคุ้มค่า เช่น Starter vs Pro)
  - **ปุ่มดำเนินการ (Call to Action):**
    - ปุ่ม **"อัปเกรดแพลนทันที"** (ปุ่มหลัก: สีม่วงไล่เฉด - Primary Purple Gradient) สำหรับเปิดหน้าชำระเงิน/เลือกแพลน
    - ปุ่ม **"ติดต่อฝ่ายบริการลูกค้า"** (ปุ่มรอง: Outline) เพื่อสอบถามข้อมูลเพิ่มเติม
    - ปุ่ม **"ปิดหน้าต่าง"** (ปิด Dialog กลับไปหน้าแดชบอร์ดหลัก)

#### B. กรณีโควต้าใช้งานเต็ม (Quota Reached Dialog)
- **พฤติกรรม (Behavior):** แสดงหน้าต่างป๊อปอัปเตือนทันทีเมื่อพยายามทำรายการใหม่ที่เกินโควต้า (เช่น กำลังจะออกใบเสร็จ POS ใบที่ 101 ในแพลนที่จำกัด 100 ใบต่อวัน)
- **รายละเอียดที่แสดงในหน้าจอ:**
  - **หัวข้อชัดเจน:** `ขออภัย โควต้าการใช้งานของคุณเต็มแล้ว`
  - **แถบแสดงเปอร์เซ็นต์ (Progress Bar):** แสดงปริมาณการใช้งานจริงเทียบกับโควต้าของแพลนปัจจุบัน เช่น `การทำรายการ POS: 100 / 100 รายการ (100%)`
  - **คำแนะนำ:** "กรุณาอัปเกรดเป็นแพลนที่สูงขึ้นเพื่อทำการออกบิลต่อ หรือรอรีเซ็ตโควต้าในรอบถัดไป"
  - **ปุ่มอัปเกรดด่วน (Quick Upgrade):** พุ่งตรงไปยังขั้นตอนการชำระเงินของแพลนถัดไปเพื่อใช้งานต่อได้ทันทีโดยไม่ให้กระบวนการขาย/บริการหยุดชะงัก

---

### 2. หน้าจอจัดการแพลนสำหรับ ERP Service Manager (ERP Subscription Management Console)

พนักงาน Sheserved ในกลุ่ม **ผู้จัดการบริการ ERP (ERP Service Manager)** จะเข้าใช้งานผ่านหน้า Dashboard ส่วนกลาง โดยมีฟังก์ชันจัดการหลักดังนี้:

#### A. หน้าหลักการจัดการบริการ (Subscription Dashboard Overview)
- **Metrics Dashboard:** 
  - จำนวน Active Subscriptions ทั้งหมด แยกตามประเภทแพลน (Starter, Pro, Enterprise, Custom)
  - ยอดรายได้รวมรายเดือน (MRR) และรายปี (ARR)
  - จำนวนรายการชำระเงินที่รอการอนุมัติ (Pending Bank Transfers)
- **ระบบค้นหาและกรอง (Search & Filter):** ค้นหาตามชื่อองค์กร (`profession_id`), สถานะการสมัคร (`TRIAL`, `ACTIVE`, `EXPIRED`), หรือประเภทแพลน
- **รายการแจ้งเตือนสิทธิ์ (Alerts List):** แสดงองค์กรที่ใกล้หมดอายุทดลองใช้ (Trial) หรือยอดค้างชำระ

#### B. หน้าสร้างและแก้ไขแพลนการใช้งาน (Plan Creator / Editor Screen)
- **ข้อมูลทั่วไป (General Info):** ช่องกรอก ชื่อแพลน, คำอธิบายแพลน, ราคาต่อเดือน/ต่อปี, จำนวนวันทดลองใช้ฟรี
- **การเลือกเปิด/ปิดโมดูล (Module Selection - Toggle Checklist):**
  - รายการ Checklist โมดูล ERP ทั้งหมด 10 โมดูล (POS, Inventory, Procurement, Accounting, HR, CRM, HIS, LIS, Telemedicine, Logistics)
  - สวิตช์สลับ (Toggle Switch) เพื่อกำหนดว่าแพลนนี้สามารถใช้โมดูลนี้ได้หรือไม่ (`is_enabled`)
- **การตั้งค่าขีดจำกัดโควต้า (Quota Limits Configuration):**
  - ช่องกรอกข้อมูลตัวเลขจำกัดการใช้งานตามตัวแปรโควต้ามาตรฐาน (เช่น จำนวนสาขาสูงสุด, จำนวนพนักงานสูงสุด, จำนวนรายการขายต่อวัน)
  - มีช่องเช็คบ็อกซ์ "ไม่จำกัด" (Unlimited) เพื่อส่งค่า `-1` ไปยังฐานข้อมูล

#### C. หน้าสร้างแพลนพิเศษเฉพาะองค์กรและการยกเว้นค่าบริการ (Custom Plan & Free Waiver Manager)
- **การกำหนดสถานะยกเว้นค่าบริการ (Free Waiver Toggle):**
  - **ข้อจำกัดการมองเห็นและการเข้าถึง (Strict Visibility & Access Control):** 
    - **ปุ่มสวิตช์นี้จะต้องถูกซ่อนโดยเด็ดขาดและเข้าถึงไม่ได้โดยบุคคลภายนอก** (เช่น พนักงาน, ผู้จัดการคลินิก หรือเจ้าขององค์กรทั่วไปที่ใช้งานระบบ ERP)
    - ระบบจะยินยอมให้เฉพาะผู้ใช้ที่อยู่ในกลุ่ม **`ERP Service Manager` (พนักงานภายในของ Sheserved ที่ผ่านการยืนยันสถานะ `sheserved_internal`)** เท่านั้นที่จะมีสิทธิ์มองเห็นและปรับแก้สวิตช์นี้ได้ ผ่านการตรวจสอบ Role และการใช้ RLS Policies ฝั่ง Backend
  - **สถานที่ตั้ง:** อยู่ในการจัดการรายละเอียดข้อมูลองค์กร (Organization Detail View) หรือในหน้าจอจัดทำแพลนพิเศษ (Custom Plan Config Screen) ภายใน Subscription Console ของ **ERP Service Manager**
  - **การออกแบบ UI:** 
    - มีสวิตช์เปิด/ปิด (Switch Widget) ที่มีป้ายกำกับชัดเจน: `[ ] ยกเว้นค่าบริการสำหรับหน่วยงานภายใน Sheserved (Free Internal Waiver)`
    - เมื่อผู้ใช้ทำการเปิดใช้งาน (Toggle On) ระบบจะแสดง Dialog Warning เพื่อยืนยัน: *"คุณแน่ใจหรือไม่ที่จะเปิดใช้งานฟรีถาวรให้กับองค์กรนี้? การดำเนินการนี้จะกำหนดให้สิทธิ์การใช้งานขององค์กรนี้เป็น Unlimited และยกเว้นการชำระเงินทั้งหมด"*
    - เมื่อกดยืนยัน ค่า `is_internal_free` ในตาราง `organization_subscriptions` จะถูกตั้งค่าเป็น `true` และระบบจะบังคับตั้งค่า `payment_method = 'FREE_INTERNAL'` และสถานะ subscription เป็น `ACTIVE` โดยไม่มีวันหมดอายุโดยอัตโนมัติ
- **การจับคู่แพลนเฉพาะราย (One-to-One Association):**
  - ค้นหาและระบุองค์กรปลายทาง (`target_profession_id`) ที่จะได้รับสิทธิ์แพลนนี้
  - ตั้งราคาพิเศษเฉพาะดีลองค์กรนั้นๆ และกำหนดวันหมดอายุตามสัญญาข้อตกลง
  - สามารถเปิด/ปิดโมดูล และปรับแต่งตัวเลขโควต้าได้อิสระนอกเหนือจากแพลนมาตรฐาน (Standard Plans) (หาก `is_internal_free` เป็นจริง ระบบจะข้ามการบังคับใช้ตัวเลขโควต้าเหล่านี้)

#### D. หน้ายืนยันการชำระเงินด้วยเงินโอน (Bank Transfer Verification Screen)
- **รายการรอตรวจสอบ (Pending Approval Queue):** แสดงรายการที่ลูกค้าโอนเงินและแนบหลักฐานสลิป (Slip Uploaded)
- **รายละเอียดการตรวจสอบ:**
  - ภาพสลิปการโอนเงิน (คลิกเพื่อขยายภาพขนาดใหญ่และซูมตรวจความถูกต้องได้)
  - ยอดเงินโอน, วันเวลาที่โอน, ธนาคารต้นทาง
  - รายละเอียดแพลนและองค์กรที่ขอเปิดใช้
- **ปุ่มจัดการ (Action Buttons):**
  - ปุ่ม **"อนุมัติ (Approve)"** -> เปลี่ยนสถานะเป็น `ACTIVE`, กำหนดวันเริ่ม-หมดอายุ, อัปเดต `approved_by` ในตาราง `subscription_payments` และส่ง Notification แจ้งเตือนผู้ใช้องค์กร
  - ปุ่ม **"ปฏิเสธ (Reject)"** -> แสดงช่องให้กรอกเหตุผลที่ปฏิเสธ (เช่น ยอดเงินโอนไม่ตรง, แนบรูปภาพไม่ชัดเจน) เพื่อส่งแจ้งเตือนให้ลูกค้าแนบหลักฐานชำระเงินเข้ามาใหม่อีกครั้ง

---

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

## แผนงานการพัฒนาและลำดับความสำคัญ (Development Roadmap & Phase Ordering)

> **หมายเหตุ:** ส่วนนี้ถูกรวมเข้ากับเนื้อหาหลักข้างต้นแล้ว โปรดดู:
> - **ตาราง Priority:** `### ตาราง priority สำหรับการพัฒนา (ปรับปรุงหลังวิเคราะห์ 7 Core)`
> - **ตาราง Phase Ordering:** `### ตาราง Canonical Phase Ordering (ปรับปรุงหลังวิเคราะห์ 7 Core)`
> - **สิ่งที่ยังไม่ได้เชื่อมต่อ:** `### สิ่งที่ยังไม่ได้เชื่อมต่อตามแผน` (แยก 3 กลุ่ม: Current Blockers / Future Work / Infrastructure)
>
> ส่วน Mermaid diagram และรายการ bullet แบบเดิมถูกลบออกเพื่อป้องกัน drift ระหว่างเอกสารหลักกับสำเนา
