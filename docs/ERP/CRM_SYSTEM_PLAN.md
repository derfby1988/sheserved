# CRM System Plan — Sheserved ERP

## ภาพรวม (Overview)

ระบบ CRM ของ Sheserved ERP ทำหน้าที่ดูแลลูกค้าและผู้รับบริการ เพื่อสร้างความภักดีต่อแบรนด์ (Customer Loyalty) กระตุ้นยอดขาย ติดตามผลการรักษา/การบริการ และ**จัดการการนัดหมายระหว่างศูนย์บริการสุขภาพกับผู้ป่วย** ครบวงจร

> **Multi-Tenant Design:** ทุกข้อมูลใน CRM จะถูกแยกตาม `profession_id` (Tenant Isolation) ทำให้แต่ละองค์กรมีระบบแต้ม คูปอง และโปรโมชันที่เป็นอิสระจากกันอย่างสมบูรณ์ ลูกค้าของคลินิก A จะไม่เห็นแต้มหรือโปรโมชันของคลินิก B เด็ดขาด

### การยกระดับด้วย CDP (Customer Data Platform)
ระบบ CRM ทำงานร่วมกับโครงสร้าง **CDP** เพื่อสร้างมุมมองลูกค้าแบบ 360 องศา (Single Customer View):
- **Identity Resolution:** เชื่อมโยงตัวตนของลูกค้าที่อาจติดต่อเข้ามาจากหลายบทบาท (เช่น เป็นทั้งลูกค้าทั่วไป, คนไข้, ผู้ใช้อื่นๆ) ให้เป็นบุคคลเดียวกันด้วย **Global ID** 
- **Customer Insight & 360 View:** ดึงข้อมูลข้ามระบบ (ประวัติยอดซื้อจาก POS, ประวัติการรักษาจาก HIS/EMR, ประวัติโทร/แชทจาก Telemedicine) มารวมไว้ในหน้า Dashboard เดียว เพื่อให้เจ้าหน้าที่ (Customer Service) ให้บริการได้ตรงจุด
- **Audience Segmentation & Marketing Automation:** วิเคราะห์พฤติกรรมลูกค้าทั้งหมดเพื่อแบ่งกลุ่มเป้าหมาย (Segmentation) และใช้ต่อยอดในโมดูล CRM สำหรับทำแคมเปญอัตโนมัติ (เช่น ส่งโปรโมชันหรือแจ้งเตือนอัตโนมัติ)

---

## หลักการออกแบบ (Design Principles)

1. **Tenant Isolation:** ทุกตารางมี `profession_id` เป็น Foreign Key และถูก Scope ด้วย Row Level Security (RLS) ของ Supabase
2. **Multi-Branch Aware:** สามารถกำหนดได้ว่าโปรโมชันหรือคูปองนั้นใช้ได้กับ **ทุกสาขา** หรือ **เฉพาะบางสาขา** (`branch_id`)
3. **เจ้าขององค์กรเป็นผู้กำหนดเอง:** ผู้มีสิทธิ์ระดับ Full Access ในโมดูล `crm` เท่านั้นที่สร้างและแก้ไขกฎแต้ม คูปอง และโปรโมชันได้
4. **เชื่อมกับ POS อัตโนมัติ:** แต้มถูกคำนวณและหักอัตโนมัติเมื่อ POS ยืนยันการขาย
5. **Data Unification (CDP Ready):** โครงสร้างประวัติลูกค้ารองรับการใช้ Global ID เป็นแกนหลัก เพื่อดึง Insight ที่กระจัดกระจายมารวมที่จุดเดียว

---

## ฟีเจอร์หลัก (Core Features)

### 1. ระบบแต้มสะสม (Loyalty Points)

แต่ละองค์กรกำหนดกฎการได้รับแต้มและการแลกแต้มเป็นของตนเอง

- **กฎการได้รับแต้ม:** เช่น "ซื้อครบ 100 บาท ได้ 1 แต้ม", "บริการหัตถการได้แต้มพิเศษ x2"
- **อัตราแลกแต้ม:** เช่น "100 แต้ม = ส่วนลด 50 บาท"
- **วันหมดอายุของแต้ม:** กำหนดได้ว่าแต้มหมดอายุภายใน X วันหลังได้รับ หรือสิ้นปีปฏิทิน
- **ประวัติแต้ม:** ทุกรายการได้/เสียแต้มถูกบันทึกครบถ้วน (Point Transaction Log)
- **ขอบเขตสาขา:** สามารถกำหนดให้แต้มใช้ได้ข้ามสาขาในองค์กรเดียวกันได้

### 2. ระบบคูปอง (Coupons / Vouchers)

- **รหัสคูปอง (Code):** ออกรหัสส่วนลดแบบ Code เฉพาะ (เช่น `CLINIC20`) หรือ QR Code
- **ประเภทส่วนลด:** ลดเป็นจำนวนเงิน (฿) หรือลดเป็นเปอร์เซ็นต์ (%)
- **เงื่อนไขการใช้:** ยอดซื้อขั้นต่ำ, จำกัดสินค้า/บริการที่ใช้ได้, จำกัดจำนวนครั้งต่อลูกค้า
- **อายุคูปอง:** กำหนดวันเริ่มต้น-สิ้นสุด (Validity Period)
- **ขอบเขตสาขา:** ใช้ได้เฉพาะสาขาที่ระบุ หรือทุกสาขาในองค์กร (`branch_id = NULL`)

### 3. ระบบโปรโมชัน (Promotions)

- **โปรโมชันตามช่วงเวลา:** กำหนดวันเริ่ม-สิ้นสุด และเลือกสินค้า/บริการที่เข้าร่วม
- **ประเภทโปรโมชัน:** 
  - ลดราคา (Price Discount)
  - ซื้อ X แถม Y (Buy X Get Y)
  - แพ็กเกจมัดรวม (Bundle Pricing)
  - แต้มพิเศษ (Bonus Points)
- **ขอบเขตสาขา:** กำหนดสาขาที่เข้าร่วมโปรโมชันได้
- **ลำดับความสำคัญ:** กำหนดลำดับการใช้โปรโมชันเมื่อมีหลายรายการพร้อมกัน

### 4. ระบบสมาชิกและแพ็กเกจ (Memberships & Packages)

- **ระดับสมาชิก (Member Tier):** เช่น Bronze / Silver / Gold / Platinum — แต่ละองค์กรกำหนด Tier ของตนเอง
- **สิทธิ์ตาม Tier:** ส่วนลดประจำ, แต้มพิเศษ, สิทธิ์จองก่อน ฯลฯ
- **แพ็กเกจล่วงหน้า (Prepaid Package):** เช่น "คอร์สเลเซอร์ 10 ครั้ง 9,900 บาท" — ซื้อล่วงหน้าแล้วตัดเครดิตทีละครั้ง
- **การตัดคอร์ส:** POS สามารถตรวจสอบยอดคงเหลือและตัดเครดิตแพ็กเกจได้อัตโนมัติ

### 5. ประวัติลูกค้าและการติดตาม (Customer Profile & Follow-up)

- **Customer Profile:** ประวัติการซื้อ, ความสนใจ, วันเกิด, หมายเหตุ, ประวัติการรักษา (ถ้า HR เปิดใช้)
- **Follow-up Tasks:** ระบบแจ้งเตือนพนักงานให้ติดตามลูกค้า เช่น "โทรสอบถามอาการหลังรับยา 3 วัน"
- **Birthday Promotion:** ส่งโปรโมชันหรือแต้มพิเศษอัตโนมัติในวันเกิดลูกค้า

### 6. ระบบนัดหมาย (Appointment Scheduling) — สมบูรณ์ครบวงจร

จัดอยู่ใน CRM เพราะการนัดหมายเป็นส่วนสำคัญของ **Patient Journey** — ตั้งแต่จองนัดจนถึงชำระเงินและสะสมแต้ม

#### 6.1 การจัดการ Slot เวลา (Time Slot Management)
- **ตารางให้บริการ (Service Schedule):** แต่ละองค์กรกำหนดวันทำการ, ช่วงเวลาเปิดปิด, และระยะเวลาต่อ Slot (เช่น 15, 30, 60 นาที)
- **ห้องหรือสถานี (Room / Station):** รองรับหลายห้องให้บริการพร้อมกัน เช่น ห้องตรวจ 1, ห้องเลเซอร์
- **แพทย์/ผู้ให้บริการ (Practitioner):** กำหนด Slot เฉพาะสำหรับแพทย์หรือผู้ให้บริการแต่ละคน เชื่อมกับ HR
- **วันหยุดพิเศษ (Block-out Dates):** บล็อควันหยุด, ซ่อมบำรุง, หรือกิจกรรมพิเศษล่วงหน้า
- **การคำนวณ Slot อัตโนมัติ:** ระบบสร้าง Slot ว่างอัตโนมัติตามกำหนดการ โดยหัก Slot ที่มีนัดหมายแล้ว

#### 6.2 การจองนัดหมาย (Booking)
- **จองได้หลายช่องทาง:** ผ่านแอปของผู้ป่วย (Consumer App), พนักงานจองให้ที่เคาน์เตอร์, หรือ Walk-in
- **เลือกบริการ:** ผู้ป่วยเลือกประเภทบริการที่ต้องการ (เช่น ปรึกษาแพทย์, ฉีดวิตามิน, เลเซอร์)
- **เลือกแพทย์/ผู้ให้บริการ:** เลือกได้ หรือ "แล้วแต่ระบบจัดให้"
- **เลือกวันเวลา:** แสดง Calendar พร้อม Slot ว่างแบบ Real-time
- **หมายเหตุผู้ป่วย:** กรอกข้อมูลเพิ่มเติม เช่น อาการ, แพ้ยา
- **Deposit / มัดจำ:** รองรับการเก็บมัดจำออนไลน์ (เชื่อมกับ Payment Gateway)

#### 6.3 การจัดการนัดหมาย (Appointment Management)
- **สถานะนัดหมาย:** `pending` → `confirmed` → `checked_in` → `in_progress` → `completed` / `no_show` / `cancelled`
- **Queue Management:** แสดงคิวผู้ป่วยที่เช็คอินแล้วสำหรับพนักงานหน้าเคาน์เตอร์แบบ Real-time
- **แก้ไข/ยกเลิก:** ทั้งผู้ป่วยและพนักงานสามารถแก้ไขหรือยกเลิกนัดได้ (กำหนดนโยบายการยกเลิกล่วงหน้าได้)
- **Waitlist:** เมื่อ Slot เต็ม สามารถเพิ่มเข้า Waitlist และแจ้งเตือนอัตโนมัติเมื่อมี Slot ว่าง

#### 6.4 การแจ้งเตือน (Notifications)
- **ยืนยันการจอง (Booking Confirmation):** แจ้งเตือนทันทีทาง Push Notification / SMS / Line
- **Reminder:** แจ้งเตือนก่อนนัด 24 ชั่วโมง และ 2 ชั่วโมง
- **แจ้งเตือนพนักงาน:** แจ้งเตือนแพทย์/ผู้ให้บริการเมื่อมีนัดหมายใหม่หรือมีการเปลี่ยนแปลง
- **Follow-up หลังการรักษา:** ส่งข้อความติดตามอาการอัตโนมัติ X วันหลังนัด

#### 6.5 รายงานและวิเคราะห์ (Reports & Analytics)
- **Appointment Summary:** จำนวนนัดทั้งหมด, แยกตามสถานะ, แยกตามบริการ, แยกตามแพทย์
- **No-show Rate:** อัตราการไม่มาตามนัด แยกตามช่วงเวลา/บริการ
- **Utilization Rate:** อัตราการใช้งาน Slot รวมถึง Slot ว่างที่ไม่ได้ใช้
- **Revenue from Appointments:** รายได้จากนัดหมาย เชื่อมกับ Accounting
- **ยอดนัดหมายของพนักงาน:** สรุปภาระงานของแพทย์/ผู้ให้บริการแต่ละคน

### 7. ระบบจัดการเนื้อหาและเคสรีวิว (Content & Case Review Management — Phase ท้าย)

ฟีเจอร์ที่เปิดโอกาสให้แพทย์หรือผู้เชี่ยวชาญขององค์กรสามารถเขียนและแชร์บทความหรือ "เคสรีวิว" เพื่อสร้างความน่าเชื่อถือ และกระตุ้นให้ลูกค้าเกิดปฏิสัมพันธ์กับศูนย์บริการผ่านระบบ CRM

- **การตีพิมพ์และเชื่อมโยงโปรไฟล์:** ใช้หน้าแสดงผลบทความเดิมของระบบ (`articles_page.dart` และ `health_article_page.dart`) โดยนำบทความที่เขียนจาก ERP มาเชื่อมโยง (Link) เข้ากับโปรไฟล์ของผู้เชี่ยวชาญ/แพทย์ในองค์กรที่เป็นเจ้าของบทความ
- **อิสระในการนำเสนอ (Freedom to Publish):** เจ้าของบทความ (ผู้เชี่ยวชาญ) มีสิทธิ์ในการเขียนและเผยแพร่บทความของตนเองได้ทันที โดยไม่ต้องผ่านขั้นตอนการขออนุมัติ (No Approval Workflow)
- **การดึงข้อมูล HIS (Anonymization):** สามารถอ้างอิงข้อมูลเคสการรักษาจาก HIS มาใช้ประกอบบทความได้ โดยระบบจะปิดบังข้อมูลส่วนบุคคล (Masking) ของผู้ป่วยเป็นค่าเริ่มต้น (Default) อย่างไรก็ตาม ผู้ป่วย (ในฐานะเจ้าของเคส/ผู้รีวิว) สามารถเลือกตั้งค่าเปิดเผยข้อมูลของตนเองในรีวิวได้หากต้องการ
- **การให้แต้มสะสมสำหรับนักรีวิว (Reviewer Incentives):** เมื่อลูกค้าหรือผู้ป่วยเข้ามาอ่านและเขียนความเห็น (Review) ในเคสรีวิว ระบบจะมอบ "แต้มสะสม (Loyalty Points)" ให้ และจะถูกอัปเดตลงตารางเก็บแต้มสะสมจริง เพื่อใช้เป็นส่วนลดในระบบ CRM ต่อไป

### 8. ระบบประเมินความพึงพอใจและรับฟังความคิดเห็น (Rating & Feedback System)

ระบบนี้ถูกออกแบบมาเพื่อเก็บรวบรวมประสบการณ์ของลูกค้า (Customer Experience) โดยเชื่อมโยงกับสถานะการรับบริการ (Appointments) หรือการสั่งซื้อ (POS)

- **กรณีรับบริการหรือซื้อสินค้าสำเร็จ (Completed / Served):**
  - **การทำงาน:** เมื่อออเดอร์ใน POS หรือนัดหมายมีสถานะเป็น `completed` ระบบจะทริกเกอร์แจ้งเตือนให้ลูกค้าทำแบบประเมินความพึงพอใจ
  - **รูปแบบประเมิน:** เป็นการให้คะแนน 1-5 ดาว (CSAT) พร้อมกล่องข้อความรีวิว (สามารถเชื่อมโยงให้แสดงเป็น Public Review ในหน้าโปรไฟล์คลินิกได้)
  - **Incentive:** ระบบสามารถผูกกับระบบสมาชิกเพื่อแจก "แต้มสะสม" ให้ลูกค้าที่สละเวลามาให้คะแนนและคำติชมได้

- **กรณีลูกค้ายกเลิกสินค้าหรือบริการ (Cancelled / Refunded):**
  - **การทำงาน:** หากมีการยกเลิกนัดหมาย (Cancelled) หรือคืนเงิน (Refunded) ระบบจะ **ไม่ส่งแบบให้คะแนนดาว (No Star Rating)** เพื่อป้องกันคะแนนเรตติ้งของคลินิกติดลบจากอารมณ์ชั่ววูบ
  - **รูปแบบประเมิน (Cancellation/Churn Survey):** ระบบจะเปลี่ยนไปส่งแบบฟอร์ม "สอบถามสาเหตุการยกเลิก" แทน เช่น การให้ติ๊กเลือกเหตุผล (รอนานไป, เปลี่ยนใจ, ราคาไม่เหมาะสม) พร้อมกล่องข้อความ
  - **การจัดการ (Internal Use Only):** ข้อมูลจากการยกเลิกนี้ จะไม่ถูกเปิดเผยสู่สาธารณะ แต่จะวิ่งตรงเข้าสู่ **KPI Dashboard** และรายงาน CRM เพื่อให้ผู้จัดการหรือเจ้าของนำไปปรับปรุงปัญหาคอขวด (Bottleneck) ภายในองค์กรต่อไป

---

## Database Schema

```sql
-- ============================================================
-- 1. กฎการได้รับแต้มสะสม (Loyalty Point Rules)
--    แต่ละองค์กรกำหนดกฎของตนเอง
-- ============================================================
CREATE TABLE loyalty_point_rules (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID REFERENCES organization_branches(id), -- NULL = ใช้ได้ทุกสาขา
  rule_name         TEXT NOT NULL,                             -- เช่น 'ซื้อยา', 'บริการหัตถการ'
  points_per_baht   DECIMAL(10,4) NOT NULL DEFAULT 0.01,       -- แต้มต่อบาท เช่น 0.01 = 100 บาท = 1 แต้ม
  bonus_multiplier  DECIMAL(5,2) NOT NULL DEFAULT 1.0,         -- ตัวคูณพิเศษ เช่น 2.0 = แต้มคูณสอง
  min_purchase      DECIMAL(12,2) DEFAULT 0,                   -- ยอดซื้อขั้นต่ำ
  applies_to        TEXT DEFAULT 'all'
                      CHECK (applies_to IN ('all', 'products', 'services', 'specific_items')),
  item_ids          UUID[],                                    -- ระบุรายการสินค้า/บริการที่เข้าร่วม
  valid_from        DATE,
  valid_until       DATE,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, rule_name)
);

-- ============================================================
-- 2. กระเป๋าแต้มสะสมของลูกค้า (Customer Loyalty Wallets)
--    แยกกระเป๋าตามองค์กร — ลูกค้า 1 คนมีแต้มแยกต่างหากต่อแต่ละคลินิก
-- ============================================================
CREATE TABLE customer_loyalty_wallets (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES users(id),         -- ลูกค้า (สมาชิก Sheserved)
  total_points      DECIMAL(12,2) NOT NULL DEFAULT 0,
  lifetime_points   DECIMAL(12,2) NOT NULL DEFAULT 0,          -- สะสมรวมตลอดชีพ (ใช้คำนวณ Tier)
  tier              TEXT NOT NULL DEFAULT 'bronze'
                      CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum', 'custom')),
  tier_name         TEXT,                                       -- ชื่อ Tier ที่องค์กรกำหนดเอง
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, user_id)
);

-- ============================================================
-- 3. ประวัติรายการแต้ม (Point Transaction Log)
-- ============================================================
CREATE TABLE loyalty_point_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  wallet_id         UUID NOT NULL REFERENCES customer_loyalty_wallets(id),
  branch_id         UUID REFERENCES organization_branches(id), -- สาขาที่เกิดรายการ
  order_id          UUID REFERENCES orders(id),                -- อ้างอิงบิล POS (ถ้ามี)
  transaction_type  TEXT NOT NULL
                      CHECK (transaction_type IN ('earn', 'redeem', 'expire', 'adjust', 'bonus')),
  points            DECIMAL(12,2) NOT NULL,                    -- บวก = ได้แต้ม, ลบ = ใช้แต้ม
  balance_after     DECIMAL(12,2) NOT NULL,
  description       TEXT,
  expires_at        TIMESTAMPTZ,                               -- วันหมดอายุของแต้มที่ได้รับ
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 4. คูปองและรหัสส่วนลด (Coupons)
-- ============================================================
CREATE TABLE coupons (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID REFERENCES organization_branches(id), -- NULL = ใช้ได้ทุกสาขา
  code              TEXT NOT NULL,                             -- รหัสคูปอง เช่น 'CLINIC20'
  description       TEXT,
  discount_type     TEXT NOT NULL CHECK (discount_type IN ('fixed', 'percent')),
  discount_value    DECIMAL(12,2) NOT NULL,                    -- จำนวนเงิน หรือ เปอร์เซ็นต์
  max_discount_baht DECIMAL(12,2),                             -- เพดานส่วนลด (กรณีเป็น %)
  min_purchase      DECIMAL(12,2) DEFAULT 0,
  usage_limit_total INTEGER,                                   -- จำกัดจำนวนการใช้รวม
  usage_limit_per_user INTEGER DEFAULT 1,                      -- จำกัดต่อลูกค้า 1 คน
  usage_count       INTEGER NOT NULL DEFAULT 0,
  applies_to        TEXT DEFAULT 'all'
                      CHECK (applies_to IN ('all', 'products', 'services', 'specific_items')),
  item_ids          UUID[],
  valid_from        TIMESTAMPTZ NOT NULL,
  valid_until       TIMESTAMPTZ,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, code)
);

-- ============================================================
-- 5. ประวัติการใช้คูปอง (Coupon Usage Log)
-- ============================================================
CREATE TABLE coupon_usages (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id         UUID NOT NULL REFERENCES coupons(id),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  user_id           UUID REFERENCES users(id),
  order_id          UUID REFERENCES orders(id),
  discount_applied  DECIMAL(12,2) NOT NULL,
  used_at           TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 6. โปรโมชัน (Promotions)
-- ============================================================
CREATE TABLE promotions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID REFERENCES organization_branches(id), -- NULL = ทุกสาขา
  name              TEXT NOT NULL,
  description       TEXT,
  promotion_type    TEXT NOT NULL
                      CHECK (promotion_type IN ('price_discount', 'buy_x_get_y', 'bundle', 'bonus_points')),
  priority          INTEGER DEFAULT 0,                         -- ยิ่งสูง ยิ่งใช้ก่อน
  conditions        JSONB NOT NULL DEFAULT '{}',               -- เงื่อนไข เช่น {"min_qty": 2, "item_ids": [...]}
  benefits          JSONB NOT NULL DEFAULT '{}',               -- ผลลัพธ์ เช่น {"discount_percent": 15, "free_item_id": "..."}
  valid_from        TIMESTAMPTZ NOT NULL,
  valid_until       TIMESTAMPTZ,
  is_stackable      BOOLEAN DEFAULT false,                     -- ใช้ซ้อนกับโปรโมชันอื่นได้หรือไม่
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 7. ระดับสมาชิก (Member Tiers) — กำหนดได้เองต่อองค์กร
-- ============================================================
CREATE TABLE member_tiers (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  tier_key              TEXT NOT NULL,                          -- 'bronze', 'silver', 'gold', 'platinum', หรือชื่อที่กำหนดเอง
  tier_display_name     TEXT NOT NULL,                          -- ชื่อที่แสดงผล เช่น 'สมาชิกทอง'
  min_lifetime_points   DECIMAL(12,2) NOT NULL DEFAULT 0,       -- แต้มสะสมขั้นต่ำสำหรับ Tier นี้
  discount_percent      DECIMAL(5,2) DEFAULT 0,                 -- ส่วนลดประจำ Tier
  point_multiplier      DECIMAL(5,2) DEFAULT 1.0,               -- ตัวคูณแต้มประจำ Tier
  sort_order            INTEGER DEFAULT 0,
  UNIQUE (profession_id, tier_key)
);

-- ============================================================
-- 8. แพ็กเกจล่วงหน้า (Prepaid Packages)
-- ============================================================
CREATE TABLE customer_packages (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id),
  user_id           UUID NOT NULL REFERENCES users(id),
  package_name      TEXT NOT NULL,
  total_sessions    INTEGER NOT NULL,
  used_sessions     INTEGER NOT NULL DEFAULT 0,
  purchase_price    DECIMAL(12,2) NOT NULL,
  order_id          UUID REFERENCES orders(id),                -- บิลที่ซื้อแพ็กเกจ
  valid_until       DATE,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 9. ประวัติการตัดแพ็กเกจ (Package Session Log)
-- ============================================================
CREATE TABLE package_session_logs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id        UUID NOT NULL REFERENCES customer_packages(id),
  order_id          UUID REFERENCES orders(id),
  sessions_used     INTEGER NOT NULL DEFAULT 1,
  note              TEXT,
  used_at           TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 10. กำหนดการให้บริการ (Service Schedules)
--     แต่ละองค์กร/สาขากำหนดวันทำการและช่วงเวลา
-- ============================================================
CREATE TABLE service_schedules (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id             UUID NOT NULL REFERENCES organization_branches(id),
  day_of_week           INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=อาทิตย์, 1=จันทร์, ..., 6=เสาร์
  open_time             TIME NOT NULL,                         -- เวลาเปิด เช่น 09:00
  close_time            TIME NOT NULL,                         -- เวลาปิด เช่น 18:00
  slot_duration_minutes INTEGER NOT NULL DEFAULT 30,           -- ระยะเวลาต่อ Slot (นาที)
  is_active             BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id, day_of_week)
);

COMMENT ON COLUMN service_schedules.day_of_week IS 'วันในสัปดาห์ (0=อาทิตย์)';
COMMENT ON COLUMN service_schedules.slot_duration_minutes IS 'ระยะเวลาต่อ Slot (นาที)';

-- ============================================================
-- 11. ห้อง/สถานีให้บริการ (Service Rooms / Stations)
-- ============================================================
CREATE TABLE service_rooms (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID NOT NULL REFERENCES organization_branches(id),
  room_name         TEXT NOT NULL,                             -- เช่น 'ห้องตรวจ 1', 'ห้องเลเซอร์'
  room_type         TEXT DEFAULT 'general'
                      CHECK (room_type IN ('general', 'consultation', 'treatment', 'lab', 'other')),
  capacity          INTEGER DEFAULT 1,                         -- จำนวนผู้ป่วยพร้อมกัน
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now()
);

COMMENT ON COLUMN service_rooms.room_name IS 'ชื่อห้อง/สถานี';
COMMENT ON COLUMN service_rooms.room_type IS 'ประเภทห้อง';
COMMENT ON COLUMN service_rooms.capacity IS 'ความจุผู้ป่วยพร้อมกัน';

-- ============================================================
-- 12. ผู้ให้บริการ (Practitioners)
--     เชื่อมกับ HR (employee_roles) แต่เพิ่มข้อมูลเฉพาะการนัดหมาย
-- ============================================================
CREATE TABLE practitioners (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID NOT NULL REFERENCES organization_branches(id),
  user_id           UUID NOT NULL REFERENCES users(id),        -- เชื่อมกับ users (ต้องเป็นพนักงาน)
  display_name      TEXT NOT NULL,                             -- ชื่อที่แสดงในหน้าจองนัด
  specialty         TEXT,                                      -- ความเชี่ยวชาญ เช่น 'แพทย์ผิวหนัง'
  bio               TEXT,
  avatar_url        TEXT,
  max_daily_appointments INTEGER DEFAULT 20,                  -- จำนวนนัดสูงสุดต่อวัน
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, user_id)
);

COMMENT ON COLUMN practitioners.display_name IS 'ชื่อที่แสดงในหน้าจอจองนัด';
COMMENT ON COLUMN practitioners.specialty IS 'ความเชี่ยวชาญ/สาขา';
COMMENT ON COLUMN practitioners.max_daily_appointments IS 'จำนวนนัดสูงสุดต่อวัน';

-- ============================================================
-- 13. วันบล็อคพิเศษ (Block-out / Holiday Dates)
-- ============================================================
CREATE TABLE schedule_blockouts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  branch_id         UUID REFERENCES organization_branches(id), -- NULL = ทุกสาขา
  practitioner_id   UUID REFERENCES practitioners(id),         -- NULL = ทุกผู้ให้บริการ
  room_id           UUID REFERENCES service_rooms(id),         -- NULL = ทุกห้อง
  blockout_date     DATE NOT NULL,
  start_time        TIME,                                      -- NULL = ทั้งวัน
  end_time          TIME,
  reason            TEXT,                                      -- เช่น 'วันหยุดนักขัตฤกษ์', 'ซ่อมบำรุง'
  created_at        TIMESTAMPTZ DEFAULT now()
);

COMMENT ON COLUMN schedule_blockouts.blockout_date IS 'วันที่บล็อค';
COMMENT ON COLUMN schedule_blockouts.reason IS 'เหตุผลการบล็อค';

-- ============================================================
-- 14. ประเภทบริการสำหรับนัดหมาย (Appointment Service Types)
-- ============================================================
CREATE TABLE appointment_service_types (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id             UUID REFERENCES organization_branches(id), -- NULL = ทุกสาขา
  name                  TEXT NOT NULL,                          -- เช่น 'ปรึกษาแพทย์', 'เลเซอร์', 'ฉีดวิตามิน'
  description           TEXT,
  duration_minutes      INTEGER NOT NULL DEFAULT 30,            -- ระยะเวลาการให้บริการ (นาที)
  buffer_minutes        INTEGER DEFAULT 5,                      -- เวลาพักระหว่าง Slot
  price                 DECIMAL(12,2),                         -- ราคาตั้งต้น (ถ้ามี)
  requires_deposit      BOOLEAN DEFAULT false,                  -- ต้องมัดจำหรือไม่
  deposit_amount        DECIMAL(12,2),                         -- จำนวนมัดจำ
  color_hex             TEXT DEFAULT '#4A90D9',                 -- สีแสดงในปฏิทิน
  is_active             BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

COMMENT ON COLUMN appointment_service_types.duration_minutes IS 'ระยะเวลาการให้บริการ (นาที)';
COMMENT ON COLUMN appointment_service_types.buffer_minutes IS 'เวลาพักระหว่าง Slot (นาที)';
COMMENT ON COLUMN appointment_service_types.requires_deposit IS 'ต้องมัดจำก่อนยืนยันนัดหรือไม่';
COMMENT ON COLUMN appointment_service_types.color_hex IS 'สีแสดงในปฏิทินการนัด';

-- ============================================================
-- 15. การนัดหมาย (Appointments) — ตารางหลัก
-- ============================================================
CREATE TABLE appointments (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id),
  branch_id             UUID NOT NULL REFERENCES organization_branches(id),
  appointment_no        TEXT NOT NULL,                          -- เลขที่นัดหมาย เช่น 'APT-20260601-0001'
  patient_user_id       UUID NOT NULL REFERENCES users(id),    -- ผู้ป่วย (สมาชิก Sheserved)
  practitioner_id       UUID REFERENCES practitioners(id),     -- ผู้ให้บริการ (NULL = ยังไม่ได้กำหนด)
  room_id               UUID REFERENCES service_rooms(id),     -- ห้องให้บริการ
  service_type_id       UUID NOT NULL REFERENCES appointment_service_types(id),
  package_id            UUID REFERENCES customer_packages(id), -- ใช้แพ็กเกจล่วงหน้าหรือไม่
  appointment_date      DATE NOT NULL,                         -- วันที่นัด
  start_time            TIME NOT NULL,                         -- เวลาเริ่ม
  end_time              TIME NOT NULL,                         -- เวลาสิ้นสุด (คำนวณจาก duration)
  status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN (
                            'pending',      -- รอยืนยัน
                            'confirmed',    -- ยืนยันแล้ว
                            'checked_in',   -- เช็คอินแล้ว (อยู่ที่คลินิก)
                            'in_progress',  -- กำลังรับบริการ
                            'completed',    -- เสร็จสิ้น
                            'no_show',      -- ไม่มาตามนัด
                            'cancelled'     -- ยกเลิก
                          )),
  booking_channel       TEXT NOT NULL DEFAULT 'app'
                          CHECK (booking_channel IN ('app', 'staff', 'walk_in', 'phone')),
  patient_note          TEXT,                                  -- หมายเหตุจากผู้ป่วย
  staff_note            TEXT,                                  -- หมายเหตุจากพนักงาน
  cancellation_reason   TEXT,                                  -- เหตุผลการยกเลิก
  cancelled_by          UUID REFERENCES users(id),             -- ใครยกเลิก
  deposit_paid          DECIMAL(12,2) DEFAULT 0,               -- มัดจำที่ชำระแล้ว
  deposit_order_id      UUID REFERENCES orders(id),            -- อ้างอิงบิลมัดจำ
  order_id              UUID REFERENCES orders(id),            -- อ้างอิงบิลหลังเสร็จบริการ
  reminder_sent_24h     BOOLEAN DEFAULT false,                 -- ส่ง reminder 24 ชม แล้วหรือยัง
  reminder_sent_2h      BOOLEAN DEFAULT false,                 -- ส่ง reminder 2 ชม แล้วหรือยัง
  followup_sent         BOOLEAN DEFAULT false,                 -- ส่ง follow-up หลังนัดแล้วหรือยัง
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, appointment_no)
);

COMMENT ON COLUMN appointments.appointment_no IS 'เลขที่นัดหมาย';
COMMENT ON COLUMN appointments.patient_user_id IS 'ผู้ป่วย/ผู้รับบริการ';
COMMENT ON COLUMN appointments.practitioner_id IS 'แพทย์/ผู้ให้บริการ';
COMMENT ON COLUMN appointments.appointment_date IS 'วันที่นัดหมาย';
COMMENT ON COLUMN appointments.start_time IS 'เวลาเริ่มต้น';
COMMENT ON COLUMN appointments.end_time IS 'เวลาสิ้นสุด';
COMMENT ON COLUMN appointments.status IS 'สถานะนัดหมาย';
COMMENT ON COLUMN appointments.booking_channel IS 'ช่องทางการจอง';
COMMENT ON COLUMN appointments.patient_note IS 'หมายเหตุจากผู้ป่วย';
COMMENT ON COLUMN appointments.staff_note IS 'หมายเหตุจากพนักงาน';
COMMENT ON COLUMN appointments.deposit_paid IS 'จำนวนมัดจำที่ชำระ';
COMMENT ON COLUMN appointments.reminder_sent_24h IS 'ส่งแจ้งเตือนล่วงหน้า 24 ชม แล้วหรือยัง';
COMMENT ON COLUMN appointments.reminder_sent_2h IS 'ส่งแจ้งเตือนล่วงหน้า 2 ชม แล้วหรือยัง';
COMMENT ON COLUMN appointments.followup_sent IS 'ส่ง follow-up หลังนัดแล้วหรือยัง';

-- ============================================================
-- 16. ประวัติการเปลี่ยนสถานะนัดหมาย (Appointment Status Log)
-- ============================================================
CREATE TABLE appointment_status_logs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id    UUID NOT NULL REFERENCES appointments(id),
  from_status       TEXT,
  to_status         TEXT NOT NULL,
  changed_by        UUID REFERENCES users(id),
  note              TEXT,
  changed_at        TIMESTAMPTZ DEFAULT now()
);

COMMENT ON COLUMN appointment_status_logs.from_status IS 'สถานะก่อนเปลี่ยน';
COMMENT ON COLUMN appointment_status_logs.to_status IS 'สถานะใหม่';
COMMENT ON COLUMN appointment_status_logs.changed_by IS 'ผู้เปลี่ยนสถานะ';

-- ============================================================
-- 17. Waitlist — รายชื่อรอ Slot ว่าง
-- ============================================================
CREATE TABLE appointment_waitlist (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID NOT NULL REFERENCES professions(id),
  branch_id             UUID NOT NULL REFERENCES organization_branches(id),
  patient_user_id       UUID NOT NULL REFERENCES users(id),
  service_type_id       UUID NOT NULL REFERENCES appointment_service_types(id),
  practitioner_id       UUID REFERENCES practitioners(id),     -- NULL = ไม่ระบุ
  preferred_date_from   DATE,
  preferred_date_until  DATE,
  preferred_time_from   TIME,
  preferred_time_until  TIME,
  status                TEXT NOT NULL DEFAULT 'waiting'
                          CHECK (status IN ('waiting', 'notified', 'booked', 'expired')),
  notified_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT now()
);

COMMENT ON COLUMN appointment_waitlist.preferred_date_from IS 'วันที่ต้องการตั้งแต่';
COMMENT ON COLUMN appointment_waitlist.preferred_date_until IS 'วันที่ต้องการถึง';
COMMENT ON COLUMN appointment_waitlist.status IS 'สถานะ Waitlist';

-- ============================================================
-- 18. การตั้งค่านโยบายการนัดหมาย (Appointment Policy)
-- ============================================================
CREATE TABLE appointment_policies (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id                 UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id                     UUID REFERENCES organization_branches(id), -- NULL = ทุกสาขา
  min_advance_booking_hours     INTEGER DEFAULT 1,              -- จองล่วงหน้าขั้นต่ำ (ชั่วโมง)
  max_advance_booking_days      INTEGER DEFAULT 90,             -- จองล่วงหน้าสูงสุด (วัน)
  free_cancel_hours_before      INTEGER DEFAULT 24,             -- ยกเลิกฟรีก่อนนัดกี่ชั่วโมง
  no_show_penalty_baht          DECIMAL(12,2) DEFAULT 0,        -- ค่าปรับ No-show
  max_active_bookings_per_user  INTEGER DEFAULT 3,              -- จองพร้อมกันได้สูงสุดกี่นัดต่อลูกค้า
  allow_patient_reschedule      BOOLEAN DEFAULT true,           -- ผู้ป่วยเปลี่ยนนัดเองได้หรือไม่
  allow_patient_cancel          BOOLEAN DEFAULT true,           -- ผู้ป่วยยกเลิกเองได้หรือไม่
  followup_days_after           INTEGER DEFAULT 3,              -- ส่ง follow-up หลังนัดกี่วัน
  updated_at                    TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, branch_id)
);

COMMENT ON COLUMN appointment_policies.min_advance_booking_hours IS 'จองล่วงหน้าขั้นต่ำ (ชั่วโมง)';
COMMENT ON COLUMN appointment_policies.free_cancel_hours_before IS 'ยกเลิกฟรีก่อนนัดกี่ชั่วโมง';
COMMENT ON COLUMN appointment_policies.no_show_penalty_baht IS 'ค่าปรับกรณีไม่มาตามนัด (บาท)';
COMMENT ON COLUMN appointment_policies.followup_days_after IS 'ส่ง follow-up หลังนัดกี่วัน';

-- ============================================================
-- 19. ระบบประเมินและรับฟังความคิดเห็น (Customer Feedbacks)
-- ============================================================
CREATE TABLE customer_feedbacks (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID REFERENCES organization_branches(id),
  user_id           UUID NOT NULL REFERENCES users(id),
  
  reference_type    TEXT NOT NULL,                         -- 'pos_order', 'appointment'
  reference_id      UUID NOT NULL,                         -- ID ของออเดอร์ หรือ คิวนัดหมาย
  provider_id       UUID REFERENCES practitioners(id),     -- พนักงานผู้ให้บริการ/แพทย์ที่รับการประเมิน (กรณีให้ดาว/รีวิวรายบุคคล)
  
  feedback_type     TEXT NOT NULL,                         -- 'rating' (กรณีสำเร็จ), 'cancellation_reason' (กรณียกเลิก)
  rating_score      INTEGER,                               -- 1-5 ดาว (เฉพาะ feedback_type = 'rating')
  reason_code       TEXT,                                  -- โค้ดสาเหตุ (เฉพาะ feedback_type = 'cancellation_reason')
  comment           TEXT,                                  -- ข้อความเพิ่มเติม
  
  is_public         BOOLEAN DEFAULT false,                 -- อนุญาตให้แสดงผลต่อสาธารณะหรือไม่ (เฉพาะเรตติ้งปกติ)
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 20. รายการยา/สินค้าโปรดของผู้ป่วย (Medication Favorites)
-- ============================================================
CREATE TABLE medication_favorites (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  medication_id     UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
  
  created_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, user_id, medication_id)
);

-- ============================================================
-- Row Level Security (RLS)
-- ============================================================
ALTER TABLE loyalty_point_rules          ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_loyalty_wallets     ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_point_transactions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupons                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupon_usages                ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotions                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_tiers                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_packages            ENABLE ROW LEVEL SECURITY;
ALTER TABLE package_session_logs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_schedules            ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_rooms                ENABLE ROW LEVEL SECURITY;
ALTER TABLE practitioners                ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_blockouts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_service_types    ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_status_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_waitlist         ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_policies         ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_feedbacks           ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_favorites         ENABLE ROW LEVEL SECURITY;

-- ตัวอย่าง RLS: พนักงานเห็นเฉพาะข้อมูลขององค์กรตนเอง
-- หมายเหตุ: auth.uid() ใช้ได้ถูกต้องใน PostgreSQL RLS (server-side) ไม่ใช่ Dart/Flutter code
CREATE POLICY crm_tenant_isolation ON coupons
  USING (profession_id IN (
    SELECT profession_id FROM employee_roles WHERE user_id = auth.uid()
  ));

-- RLS สำหรับตารางนัดหมาย: ผู้ป่วยเห็นเฉพาะนัดของตนเอง, พนักงานเห็นทุกนัดในองค์กร
CREATE POLICY appointment_patient_isolation ON appointments
  USING (
    patient_user_id = auth.uid()
    OR profession_id IN (
      SELECT profession_id FROM employee_roles WHERE user_id = auth.uid()
    )
  );

-- RLS สำหรับรายการยาโปรด: ผู้ป่วยเห็นและจัดการได้เฉพาะของตนเอง
CREATE POLICY medication_favorites_patient_isolation ON medication_favorites
  USING (user_id = auth.uid());
```

> **⚠️ Auth Guidelines (สำหรับ Flutter/Dart เท่านั้น):**  
> ใน Dart/Flutter code ห้ามใช้ `Supabase.instance.client.auth.currentUser` หรือ `_client.auth.currentUser`  
> ให้ดึง `userId` ผ่าน `ServiceLocator.instance.currentUser?.id` เสมอ  
> (ดูรายละเอียดใน [auth_data_guidelines.md](../.agent/workflows/auth_data_guidelines.md))

---

## ขั้นตอนการทำงาน (User Flow)

### เจ้าของ/ผู้มีสิทธิ์ CRM (Full/Edit Access)

1. เข้าสู่ **ERP Dashboard > CRM Management** ของสาขาหรือ HQ
2. สร้าง **กฎแต้ม** เช่น "ซื้อสินค้าทุก 100 บาท ได้ 1 แต้ม" (กำหนดขอบเขตสาขาได้)
3. สร้าง **คูปอง** โดยกรอกรหัส, ประเภทส่วนลด, วันหมดอายุ, และเงื่อนไขการใช้
4. สร้าง **โปรโมชัน** กำหนดช่วงเวลาและสินค้า/บริการที่เข้าร่วม
5. กำหนด **ระดับสมาชิก (Tier)** พร้อมสิทธิพิเศษของแต่ละระดับ
6. ตั้งค่า **ตารางให้บริการ** (วันทำการ, เวลา, ระยะเวลาต่อ Slot) สำหรับแต่ละสาขา
7. เพิ่ม **ห้อง/สถานีให้บริการ** และ **ผู้ให้บริการ** (เชื่อมกับ HR)
8. กำหนด **ประเภทบริการนัดหมาย** พร้อมราคา, ระยะเวลา, และสีปฏิทิน
9. กำหนด **นโยบายการนัดหมาย** เช่น จองล่วงหน้าขั้นต่ำ, ค่าปรับ No-show

### พนักงานเคาน์เตอร์ (POS Integration)

1. ลูกค้าชำระเงินผ่าน POS
2. POS ตรวจสอบ `loyalty_point_rules` ขององค์กรนั้นๆ → คำนวณแต้มที่ลูกค้าจะได้รับ
3. หากลูกค้าต้องการใช้คูปอง → กรอก Code → POS ตรวจสอบ `coupons` และ `coupon_usages`
4. หากลูกค้าต้องการแลกแต้ม → ตรวจสอบ `customer_loyalty_wallets` และหักแต้ม
5. เมื่อยืนยันการชำระเงิน → บันทึก `loyalty_point_transactions` และ `coupon_usages` อัตโนมัติ

### ผู้ป่วย (Patient Booking Flow — Consumer App)

1. เปิดแอป → เลือกศูนย์บริการสุขภาพ
2. เลือก **ประเภทบริการ** (เช่น ปรึกษาแพทย์, เลเซอร์)
3. เลือก **แพทย์/ผู้ให้บริการ** (หรือ "ไม่ระบุ")
4. ระบบแสดง **ปฏิทิน + Slot ว่าง** แบบ Real-time
5. เลือก **วันและเวลา** → กรอกหมายเหตุ (อาการ, แพ้ยา)
6. หากต้องมัดจำ → ชำระผ่าน Payment Gateway
7. รับ **Push Notification / SMS** ยืนยันการจอง
8. รับ **Reminder** ก่อนนัด 24 ชม และ 2 ชม
9. มาถึง → **เช็คอิน** ผ่านแอปหรือที่เคาน์เตอร์
10. หลังเสร็จบริการ → POS รับชำระ → แต้มสะสมอัตโนมัติ
11. รับ **Follow-up message** หลังนัด X วัน

### พนักงาน (Staff Appointment Management Flow)

1. เข้าหน้า **Appointment Dashboard** → ดู Queue ผู้ป่วยวันนี้
2. เช็คอินผู้ป่วยที่มาถึง → เปลี่ยนสถานะเป็น `checked_in`
3. เรียกผู้ป่วย → เปลี่ยนสถานะเป็น `in_progress`
4. เมื่อเสร็จบริการ → เปลี่ยนสถานะเป็น `completed` → POS เปิดบิลต่อได้เลย
5. หากผู้ป่วยไม่มา → บันทึก `no_show` → ระบบตรวจสอบค่าปรับตาม Policy

---

## การเชื่อมโยงกับระบบอื่น (Integrations)

| ระบบ | ทิศทาง | รายละเอียด |
|------|--------|-----------|
| **POS System** | ↔ สองทาง | คำนวณและหักแต้ม, ตรวจสอบและใช้คูปอง, ตัดเครดิตแพ็กเกจ, เปิดบิลหลังนัดเสร็จ |
| **Accounting System** | → ออก | บันทึก Deferred Revenue กรณีขายแพ็กเกจล่วงหน้า; บันทึกส่วนลดจากคูปอง/แต้มเป็นค่าใช้จ่าย; บันทึกรายได้จากมัดจำนัดหมาย |
| **HR System** | ↔ สองทาง | ดึงข้อมูลพนักงาน/แพทย์มาสร้าง Practitioners; ดึงตารางกะ (Shift) มาคำนวณ Slot ว่าง; ส่งข้อมูลภาระงานนัดหมายกลับไปคำนวณค่าคอมมิชชั่น |
| **Inventory System** | → ออก | โปรโมชันประเภท "Buy X Get Y" สั่งให้ตัดสต๊อกสินค้าแถม |
| **Notification System** | → ออก | ส่ง Push Notification / SMS / Line สำหรับยืนยันนัด, Reminder, Follow-up |

---

## Flutter UI (แผนการพัฒนา)

```
lib/features/crm/
├── data/
│   ├── models/
│   │   ├── coupon_model.dart
│   │   ├── promotion_model.dart
│   │   ├── loyalty_wallet_model.dart
│   │   ├── customer_package_model.dart
│   │   ├── appointment_model.dart           -- [NEW] โมเดลนัดหมาย
│   │   ├── practitioner_model.dart          -- [NEW] โมเดลผู้ให้บริการ
│   │   ├── service_schedule_model.dart      -- [NEW] โมเดลตารางบริการ
│   │   └── appointment_service_type_model.dart -- [NEW] โมเดลประเภทบริการ
│   └── repositories/
│       ├── coupon_repository.dart
│       ├── promotion_repository.dart
│       ├── loyalty_repository.dart
│       ├── appointment_repository.dart      -- [NEW] CRUD นัดหมาย + Slot query
│       ├── practitioner_repository.dart     -- [NEW] จัดการผู้ให้บริการ
│       └── schedule_repository.dart         -- [NEW] ตารางบริการ + Blockout
├── domain/
│   └── services/
│       ├── crm_pos_service.dart             -- บริการคำนวณแต้ม/ส่วนลด ณ จุดขาย
│       ├── appointment_service.dart         -- [NEW] Business Logic นัดหมาย (Slot calc, validation)
│       ├── slot_calculator_service.dart     -- [NEW] คำนวณ Slot ว่างแบบ Real-time
│       └── appointment_notification_service.dart -- [NEW] ส่ง Reminder / Follow-up
└── presentation/
    ├── pages/
    │   ├── crm_dashboard_page.dart          -- ภาพรวม CRM
    │   ├── coupon_management_page.dart      -- สร้าง/แก้ไข/ลบคูปอง
    │   ├── promotion_management_page.dart   -- สร้าง/แก้ไขโปรโมชัน
    │   ├── loyalty_rules_page.dart          -- กำหนดกฎแต้ม
    │   ├── member_tier_page.dart            -- จัดการระดับสมาชิก
    │   ├── customer_profile_page.dart       -- ประวัติลูกค้า/แต้ม/แพ็กเกจ/นัดหมาย
    │   │
    │   ├── -- [NEW] Appointment Management (ฝั่งพนักงาน/ERP)
    │   ├── appointment_dashboard_page.dart  -- Queue วันนี้ + Calendar ภาพรวม
    │   ├── appointment_calendar_page.dart   -- ปฏิทินนัดหมาย (รายวัน/สัปดาห์/เดือน)
    │   ├── appointment_detail_page.dart     -- รายละเอียด + เปลี่ยนสถานะ
    │   ├── appointment_create_page.dart     -- สร้างนัดแทนลูกค้า (Staff booking)
    │   ├── practitioner_management_page.dart-- จัดการผู้ให้บริการ
    │   ├── service_schedule_page.dart       -- ตั้งค่าตารางบริการ/วันหยุด
    │   ├── appointment_service_type_page.dart -- ประเภทบริการนัดหมาย
    │   ├── appointment_policy_page.dart     -- นโยบายการนัดหมาย
    │   ├── appointment_reports_page.dart    -- รายงาน: No-show, Utilization, Revenue
    │   │
    │   └── -- [NEW] Appointment Booking (ฝั่งผู้ป่วย/Consumer App)
    │       ├── book_appointment_page.dart   -- เลือกบริการ > แพทย์ > วันเวลา
    │       ├── appointment_slot_picker.dart  -- ปฏิทิน + Slot ว่าง Real-time
    │       ├── my_appointments_page.dart    -- ประวัติ + นัดที่กำลังจะมา
    │       └── appointment_checkin_page.dart -- เช็คอินผ่านแอป
    └── widgets/
        ├── coupon_card.dart
        ├── loyalty_points_widget.dart
        ├── appointment_queue_card.dart      -- [NEW] การ์ดแสดง Queue ผู้ป่วย
        ├── appointment_status_badge.dart    -- [NEW] Badge แสดงสถานะ
        ├── slot_grid_widget.dart            -- [NEW] Grid แสดง Slot ว่าง
        └── appointment_calendar_widget.dart -- [NEW] Mini Calendar widget
```

---

## แผนการพัฒนา (Roadmap)

| Phase | งาน | สถานะ |
|-------|-----|-------|
| **Phase 1** | สร้าง DB Schema + RLS ทั้งหมด (CRM + Appointment) | ☐ TODO |
| **Phase 2** | Loyalty Point Repository + การคำนวณแต้มใน POS | ☐ TODO |
| **Phase 3** | Coupon Repository + การตรวจสอบและใช้คูปองใน POS | ☐ TODO |
| **Phase 4** | Promotion Engine (คำนวณส่วนลดอัตโนมัติ) | ☐ TODO |
| **Phase 5** | Flutter UI: CRM Dashboard, Coupon/Promotion Management | ☐ TODO |
| **Phase 6** | Member Tier + Prepaid Package | ☐ TODO |
| **Phase 7** | Follow-up & Birthday Promotion (Notification) | ☐ TODO |
| **Phase 8** | Appointment: DB Schema, RLS, Service Schedule, Practitioners | ☐ TODO |
| **Phase 9** | Appointment: `slot_calculator_service` + `appointment_repository` | ☐ TODO |
| **Phase 10** | Appointment: Staff UI — Queue Dashboard, Calendar, Status Management | ☐ TODO |
| **Phase 11** | Appointment: Consumer App UI — Booking Flow, Slot Picker, My Appointments | ☐ TODO |
| **Phase 12** | Appointment: Notification — Reminder 24h/2h, Follow-up, Waitlist Alert | ☐ TODO |
| **Phase 13** | Appointment: Reports — No-show Rate, Utilization, Revenue Integration | ☐ TODO |

---

## สิ่งที่ต้องทำต่อ (Next Steps)

### 🗄️ ฝั่ง Database (PostgreSQL RLS)
- RLS policies ใช้ `auth.uid()` ได้ปกติ — เป็นฟังก์ชัน server-side ของ PostgreSQL/Supabase ไม่ขัดแย้งกับ auth_data_guidelines
- ทดสอบ RLS: พนักงานเห็นข้อมูลองค์กร, ผู้ป่วยเห็นนัดของตนเองเท่านั้น
- สร้าง unit test / integration test สำหรับการเข้าถึงนัดหมายตามสิทธิ์

### 📱 ฝั่ง Flutter/Dart (สำคัญ — ตาม auth_data_guidelines)
- **ห้าม** ใช้ `Supabase.instance.client.auth.currentUser` หรือ `_client.auth.currentUser` ใน Repository ใด ๆ
- **ต้อง** ดึง `userId` ผ่าน `ServiceLocator.instance.currentUser?.id` เสมอ เช่น:
  ```dart
  // ✅ ถูกต้อง
  final userId = ServiceLocator.instance.currentUser?.id;
  await _appointmentRepo.createAppointment(userId: userId, ...);

  // ❌ ผิด — จะได้ค่า null เสมอ
  final userId = _client.auth.currentUser?.id;
  ```
- ทุก Repository ที่เกี่ยวกับ appointment ต้องรับ `userId` เป็น parameter จาก UI layer


*หมายเหตุ: ทุกหน้าจอใน CRM Management จะแสดงผลเฉพาะข้อมูลขององค์กรและสาขาที่พนักงานมีสิทธิ์เข้าถึงเท่านั้น ตามระบบสิทธิ์ที่กำหนดไว้ใน [ERP_CORE_ARCHITECTURE.md](ERP_CORE_ARCHITECTURE.md)*
