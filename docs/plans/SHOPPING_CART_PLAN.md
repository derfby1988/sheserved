# Global Platform Feature: Shopping Cart (Universal Cart)

## ภาพรวม (Overview)
ระบบตะกร้าสินค้า (Shopping Cart) ของ Sheserved จะถูกออกแบบให้เป็น **Global Platform Feature** ที่ทำงานอยู่บนแอปพลิเคชันฝั่งผู้ใช้งาน (Consumer App) โดยไม่ผูกมัดหรือฝังตัวอยู่ใต้ ERP ของคลินิกใดคลินิกหนึ่ง

เหตุผลสำคัญที่ต้องแยกตะกร้าสินค้าออกจากการเป็นโมดูลย่อยของ ERP คือ **"พฤติกรรมผู้บริโภค"** ลูกค้า 1 คนอาจจะ:
1. ซื้อยา/เวชสำอาง จาก **คลินิก A** (ใช้งาน Sheserved ERP)
2. จองบริการหัตถการ จาก **คลินิก B** (ใช้งาน Sheserved ERP แบบ Cloud)
3. บริจาคเงินเข้าโครงการการกุศล หรือ ซื้อของที่ระลึกของ **แพลตฟอร์ม Sheserved เอง** (ไม่ผ่าน ERP)
4. ซื้อสินค้าจาก **พาร์ทเนอร์ร้านค้าขนาดเล็ก** (ไม่ได้ใช้ Sheserved ERP)

ระบบ Universal Cart จะช่วยให้ลูกค้าสามารถรวมทุกรายการไว้ในตะกร้าเดียว กดชำระเงินเพียงครั้งเดียว (Single Checkout) แล้วระบบตะกร้าจะทำหน้าที่ **"กระจายออเดอร์ (Order Splitting & Routing)"** ไปยังผู้ให้บริการแต่ละแห่งเอง

---

## กลไกการทำงานหลัก (Core Mechanisms)

### 1. ระบบตะกร้ารวมศูนย์ (Universal Cart Management)
- เก็บข้อมูลรายการสินค้า (Cart Items) โดยแต่ละรายการจะผูกกับ `profession_id` (เจ้าของสินค้า/บริการ) หรือกำหนดให้เป็นส่วนกลาง
- คำนวณยอดรวม (Subtotal), ส่วนลดจากคูปอง (Discount), และค่าจัดส่ง (Shipping Fee) แยกตามเจ้าของร้าน ก่อนนำมารวมเป็นยอดสุทธิ (Grand Total) ประจำตะกร้า

### 2. การชำระเงิน (Single Checkout & Payment Split)
- เมื่อลูกค้าชำระเงิน (Payment Gateway) ระบบ Platform จะรับเงินรวมก้อนใหญ่
- ระบบบัญชีหลังบ้านของ Platform จะทำการหักค่าธรรมเนียม (Platform Fee) และคำนวณยอดที่จะโอนจ่าย (Payout) ให้กับคลินิก/ร้านค้าแต่ละรายโดยอัตโนมัติ

### 3. การกระจายออเดอร์ (Order Routing & Injection)
ตะกร้าสินค้าจะเป็นคนส่งข้อมูลการสั่งซื้อแยกย้ายไปยังระบบของร้านค้านั้นๆ:
- **กรณีเป็นคลินิกที่ใช้ Sheserved ERP:**
  ระบบตะกร้าจะยิง API (POS Injection) ข้ามไปสร้างใบสั่งซื้อ (Sales Order / Receipt) ในระบบ **POS System** ของคลินิกนั้นโดยตรง เมื่อ POS รับออเดอร์แล้ว ระบบจะไหลเข้าสู่กระบวนการปกติของ ERP เช่น ตัดสต๊อก (Inventory), รับรู้รายได้ (Accounting), และคำนวณรอบจัดส่ง (Logistics)
- **กรณีเป็นร้านค้าทั่วไป (ไม่ได้ใช้ ERP):**
  ระบบสร้าง Order ในระดับ Platform Database แจ้งเตือนพ่อค้าแม่ค้าผ่านระบบแชทหรือ Notification ให้แพ็คของส่ง
- **กรณีเป็นสินค้า/บริการกลางของแพลตฟอร์ม (Platform Native):**
  บันทึกลงฐานข้อมูลส่วนกลาง (Platform Admin Dashboard)

---

## การเชื่อมโยงกับ ERP Core (API Integration)

เพื่อรองรับระบบตะกร้าสินค้าส่วนกลาง ระบบ ERP จะต้องเปิดช่องทางรับข้อมูล (Endpoints) ดังต่อไปนี้:
1. **API เช็คสต๊อก:** ให้ตะกร้าสินค้าสามารถเช็คจำนวนสต๊อกสินค้าล่าสุดก่อนอนุญาตให้ลูกค้ากดชำระเงิน
2. **API สั่งซื้อ (POS Injection):** รับ Data Payload จากตะกร้าสินค้าเพื่อสร้างบิลในระบบ POS อัตโนมัติ (โดยระบุที่มาของบิลว่ามาจาก "Global Cart - Online")

---

## บันทึกการพัฒนา UI (UI Development Notes)
- **จุดเข้าสู่หน้าตะกร้า (Cart Entry Point):** กำหนดให้เข้าถึงผ่านไอคอน `TlzCartButton` ซึ่งอยู่ภายใน `TlzAppTopBar` (`lib/shared/widgets/tlz_app_top_bar.dart`) 
- **การนำทาง (Routing):** มีการกำหนดค่าเริ่มต้นของปุ่มไว้ให้ Route ไปที่ `'/cart'` อัตโนมัติ (`Navigator.pushNamed(context, '/cart')`) ในกรณีที่ไม่มีการกำหนด callback มาทับ
- **สิ่งที่ต้องทำต่อ (TODO):** ในอนาคตเมื่อมีการสร้างหน้า UI ตะกร้าสินค้าจริงเสร็จสิ้น จะต้องนำ Route `'/cart'` ไปลงทะเบียนไว้ในไฟล์ `main.dart` หรือไฟล์ router ที่เกี่ยวข้อง เพื่อให้แอปพลิเคชันนำทางได้อย่างสมบูรณ์และไม่เกิด Error

---

## Database Schema (ร่างคร่าวๆ สำหรับ Platform Level)

```sql
CREATE TABLE platform_shopping_cart (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE platform_cart_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_id         UUID NOT NULL REFERENCES platform_shopping_cart(id) ON DELETE CASCADE,
  profession_id   UUID, -- อ้างอิงเจ้าของสินค้า (หากเป็นของส่วนกลางให้เป็น NULL)
  product_id      UUID NOT NULL, -- รหัสสินค้า/บริการ
  quantity        INTEGER NOT NULL DEFAULT 1,
  unit_price      DECIMAL(12,2) NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE platform_orders (
  -- เก็บคำสั่งซื้อรวมหลังจากชำระเงินสำเร็จ 
  -- ก่อนที่จะแยกใบเสร็จ (Receipts) ย่อยส่งไปให้ ERP แต่ละคลินิก
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id),
  grand_total     DECIMAL(12,2) NOT NULL,
  payment_status  TEXT DEFAULT 'completed',
  created_at      TIMESTAMPTZ DEFAULT now()
);
```
