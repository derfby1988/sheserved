# Delivery & Logistics Management Plan

## ภาพรวม (Overview)
โมดูล **Delivery / Logistics** เป็นระบบที่ออกแบบมาเพื่อทำงานเป็น **"สะพานเชื่อม"** ระหว่าง 3 ระบบหลักของ Sheserved ERP ได้แก่:
**POS (รับออเดอร์/คิดเงิน/เก็บค่าส่ง) ➡️ Inventory (ตัดสต๊อก/แพ็คของ) ➡️ Accounting (รับรู้รายได้ค่าขนส่ง)**

ระบบถูกออกแบบมาเพื่อรองรับการจัดส่งสินค้า (เช่น การขายผ่านหน้าร้านออนไลน์ หรือการจัดส่งยาจากใบสั่งยา Telemedicine) ทั้งในรูปแบบทีมขนส่งของคลินิกเอง (In-house Fleet) และการเชื่อมต่อกับผู้ให้บริการภายนอก (3PL)

---

## ฟีเจอร์หลัก (Core Features)

### 1. การคำนวณระยะทางและค่าส่ง (Distance & Shipping Fee Calculation)
- **พิกัดที่แม่นยำ:** ระบบรับพิกัดจุดหมายปลายทางจากแอปพลิเคชันฝั่งผู้ป่วย/ลูกค้า (ผ่าน Google Maps SDK)
- **อัตราค่าขนส่ง (Dynamic Pricing):** คลินิกสามารถตั้งค่าเรทราคาตามระยะทาง (เช่น 0-5 กม. เหมา 40 บาท, หลังจากนั้น กม. ละ 10 บาท)
- **POS Integration:** ทันทีที่คำนวณระยะทางเสร็จ ระบบ POS จะดึงค่าบริการจัดส่งนี้ไปรวมในบิลเพื่อเรียกเก็บเงินลูกค้าทันที

### 2. การจัดการรอบรถ หรือไรเดอร์ (Fleet & Rider Management)
- **การจัดการบุคลากร (HR Integration):** ระบุตัวพนักงาน/ไรเดอร์ที่มีคิวว่าง และคำนวณรอบวิ่ง
- **การจัดสรรออเดอร์ (Job Dispatch):** เมื่อ Inventory ยืนยันการแพ็คสินค้า (Packed) ระบบจะสร้าง Job และจับคู่ (Assign) กับไรเดอร์ในองค์กรที่พร้อมทำงาน
- **ผลตอบแทน (Commissions):** บันทึกเที่ยววิ่งเพื่อนำไปประมวลผลเป็นค่ารอบให้พนักงานในระบบ HR

### 3. การติดตามสถานะพัสดุ (Real-time Tracking)
- **สถานะการจัดส่ง (Status Pipeline):** รอแพ็ค -> กำลังจัดส่ง (In-Transit) -> จัดส่งสำเร็จ (Delivered)
- **Inventory Sync:** ทันทีที่สถานะกลายเป็น "จัดส่งสำเร็จ" ระบบ Inventory จะทำเครื่องหมายว่าสินค้านั้นถูกนำออกจากคลังและถึงมือผู้รับเรียบร้อย
- **Accounting Sync:** การเก็บเงินปลายทาง (ถ้ามี) หรือค่าบริการจัดส่ง จะถูกส่งไปบันทึกบัญชี (General Ledger) เป็นรายได้ในระบบ Accounting ทันที

---

## 🔒 มาตรการควบคุมต้นทุนแผนที่ (Google Maps Cost Prevention)

เพื่อให้การคำนวณระยะทางและการติดตามพิกัดไรเดอร์มีประสิทธิภาพโดย**ไม่เกิดค่าใช้จ่าย API ล่าช้า (Zero Billing Cost)** ระบบจะบังคับใช้นโยบายดังนี้:
1. **Mobile-Only Maps:** การแสดงผลแผนที่, การค้นหาสถานที่, และระบบ Tracking ทั้งหมด จะถูกเขียนและเรียกใช้ผ่าน **Google Maps SDK for iOS** และ **Google Maps SDK for Android** เท่านั้น (ซึ่งเป็นโควต้าแบบใช้ฟรีไม่จำกัด)
2. **Web Fallback:** หากเข้าใช้งานระบบจัดการ (ERP Dashboard) ผ่าน Web Browser หรือคอมพิวเตอร์ จะแสดงผลเพียง "ข้อความสถานะ" หรือตัวเลขระยะทางที่บันทึกในฐานข้อมูลเท่านั้น **ห้าม** โหลด/แสดงแผนที่ของ Google ผ่าน Maps JavaScript API โดยเด็ดขาด

---

## Database Schema (ร่าง)

```sql
CREATE TABLE delivery_orders (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id   UUID NOT NULL REFERENCES professions(id),
  pos_receipt_id  UUID REFERENCES pos_receipts(id), -- เชื่อมโยงกับบิลขาย
  rider_id        UUID REFERENCES users(id),        -- พนักงานจัดส่ง
  recipient_name  TEXT NOT NULL,
  recipient_phone TEXT NOT NULL,
  dest_latitude   DECIMAL(10, 8),
  dest_longitude  DECIMAL(11, 8),
  distance_km     DECIMAL(10, 2),
  shipping_fee    DECIMAL(10, 2) DEFAULT 0,
  status          TEXT DEFAULT 'pending', -- pending, packed, shipping, delivered, cancelled
  shipped_at      TIMESTAMPTZ,
  delivered_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- การติดตามพิกัดไรเดอร์ (ส่งข้อมูลจาก Mobile App)
CREATE TABLE delivery_tracking (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_order_id UUID NOT NULL REFERENCES delivery_orders(id) ON DELETE CASCADE,
  rider_id          UUID NOT NULL REFERENCES users(id),
  current_latitude  DECIMAL(10, 8),
  current_longitude DECIMAL(11, 8),
  recorded_at       TIMESTAMPTZ DEFAULT now()
);
```
