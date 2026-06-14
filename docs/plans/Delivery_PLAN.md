# Delivery & Logistics Management Plan

> **📌 Canonical Schema Reference:** เอกสารฉบับนี้อ้างอิง schema และแนวคิดหลักจาก `ERP_CORE_ARCHITECTURE.md` ในส่วนของ **Delivery Core** หากมีความขัดแย้ง ให้ถือ `ERP_CORE_ARCHITECTURE.md` เป็นหลัก

---

## ภาพรวม (Overview)

โมดูล **Delivery Core** เป็น **Execution Layer** ที่รับคำสั่งซื้อจาก **Commerce Core** (Order & Checkout) และประสานงานกับระบบย่อยต่าง ๆ ดังนี้:

**Commerce Core (Order/Checkout) ➡️ Inventory Core (แพ็ค/ตัดสต๊อก) ➡️ Delivery Core (จัดส่ง) ➡️ Accounting (รับรู้รายได้ค่าขนส่ง)**

ระบบรองรับ:
- คำสั่งซื้อจาก **POS** (`source_type = 'pos'`)
- คำสั่งซื้อจาก **Telemedicine** (`source_type = 'telemedicine'`)
- คำสั่งซื้อจาก **Platform/Universal Cart** (`source_type = 'platform'`)
- คำสั่งซื้อที่สร้าง **ด้วยตนเอง** (`source_type = 'manual'`)

การเชื่อมต่อกับระบบอื่นใช้ **Reliability Core** (`outbox_events` / `stock_movements`) เพื่อความปลอดภัยของข้อมูลและ traceability

---

## ฟีเจอร์หลัก (Core Features)

### 1. การคำนวณระยะทางและค่าส่ง (Distance & Shipping Fee Calculation)
- **พิกัดที่แม่นยำ:** รับพิกัดจุดหมายปลายทางจากแอปฯ ผู้ใช้ (Mobile SDK)
- **Fee Rule Engine:** รองรับหลายประเภท
  - `distance` — ตามระยะทาง (km)
  - `zone` — ตามเขตพื้นที่ (polygon)
  - `weight` — ตามน้ำหนัก (kg)
  - `time_window` — ตามช่วงเวลา (rush hour multiplier)
  - `urgency` — ตามความเร่งด่วน
  - `flat_rate` — อัตราเหมา
- **Snapshot ค่าส่ง:** ค่าส่งจะถูกคำนวณครั้งเดียวตอนสร้าง `delivery_orders` แล้ว snapshot ไว้ใน `fee_snapshot` (JSONB) เพื่อป้องกันการเปลี่ยนแปลงย้อนหลัง
- **Commerce Core Integration:** ค่าส่งถูกส่งไปรวมใน checkout total ก่อนชำระเงิน ไม่ใช่คำนวณหลังจาก POS สร้างบิลแล้ว

### 2. State Machine แบบเต็มรูปแบบ (13 สถานะ)
แยกเป็น 3 ระดับ พร้อม validation และ audit log ทุกการเปลี่ยน state:

- **Pre-dispatch:** `pending` → `packed` → `ready_for_pickup`
- **In-transit:** `assigned` → `picked_up` → `in_transit` → `at_dropoff` → `delivered`
- **Exception:** `failed_attempt` → `reattempt_scheduled` / `returned_to_warehouse` / `cancelled`

ทุก transition ต้องผ่าน validation (เช่น ห้าม `delivered` ถ้ายังไม่ `in_transit`) และบันทึก `status_changed_at` + `status_change_reason`

### 3. การจัดการไรเดอร์และกะ (Rider & Shift Management)
- **`riders` table:** เก็บข้อมูล vehicle_type, max_capacity_weight_kg, max_capacity_volume_l, zone_coverage, current_status (`offline` | `online` | `on_delivery` | `on_break` | `unavailable`), current_location (lat/lng)
- **`rider_shifts` table:** กำหนด shift_date, start_time, end_time, is_available, max_orders, assigned_orders
- **`rider_assignments` table:** บันทึกการมอบหมายงาน พร้อมสถานะ `pending` | `accepted` | `rejected` | `expired` | `cancelled` และ rejection_reason
- **Geospatial Index:** ค้นหาไรเดอร์ที่พร้อมและใกล้ที่สุดได้เร็วผ่าน index บน `current_latitude, current_longitude`
- **HR Integration:** บันทึกรอบวิ่ง (`delivery_runs`) เพื่อคำนวณค่าตอบแทน/commission ต่อไป

### 4. การวางแผนเส้นทางและจัด Batch (Dispatch & Route Planning)
- **`delivery_runs`:** รวมหลายออเดอร์เป็นรอบวิ่งเดียว พร้อม estimated_start_time, estimated_end_time, total_distance_km
- **`route_stops`:** ลำดับการจัดส่งแต่ละจุด (stop_sequence) พร้อม estimated_arrival, actual_arrival, status (`pending` | `arrived` | `completed` | `skipped`)
- **Algorithm:** เริ่มต้นด้วย nearest-neighbor + time window constraint (ยังไม่ต้องใช้ external routing engine จนกว่า load สูง)
- **Batch Assignment:** ลดจำนวนรอบวิ่ง ประหยัดเวลาและน้ำมัน

### 5. หลักฐานการส่ง (Proof-of-Delivery — POD)
- **`proof_of_deliveries` table:**
  - `recipient_name` — ชื่อผู้รับ (ถ้าไม่ใช่ผู้สั่ง)
  - `recipient_signature_url` — รูปลายเซ็น
  - `delivery_photo_url` — รูปถ่ายตอนส่ง
  - `verification_code` — รหัสยืนยันที่ลูกค้ากรอก (SMS/Notification)
  - `latitude`, `longitude` — พิกัดตอนยืนยัน
- **Dispute Protection:** กัน dispute "ไม่ได้รับของ" โดยมีหลักฐานชัดเจน (รูป/ลายเซ็น/code + geotag)

### 6. การจัดการข้อยกเว้น (Exception Handling)
- **`delivery_exceptions` table:**
  - `exception_type`: `recipient_not_home`, `wrong_address`, `vehicle_breakdown`, `damaged_goods`, `refused_delivery`, `rider_emergency`, `traffic_delay`, `weather_delay`, `customer_cancelled`
  - `resolution_type`: `reattempt_same_day`, `reattempt_next_day`, `return_to_warehouse`, `cancel_and_refund`
- **Workflow:** ไรเดอร์ report ผ่าน mobile app → ระบบ auto-assign resolution workflow → อัปเดต `delivery_orders.status` → trigger `outbox_events` ไปยัง Inventory/Accounting ตาม resolution

### 7. การติดตามแบบ Real-time (Real-time Tracking)
- **`delivery_tracking`:** บันทึกพิกัดไรเดอร์ทุก X วินาที (ตั้งค่าได้) พร้อม `accuracy_meters`, `speed_kmh`
- **Index:** `idx_tracking_order` (order + time DESC) และ `idx_tracking_rider` (rider + time DESC) สำหรับ query ประวัติเส้นทาง

### 8. การรองรับ 3PL (3PL Adapter Layer)
- **`carrier_configs`:** เก็บ carrier_name, carrier_code, api_base_url, api_key_encrypted, api_secret_encrypted, tracking_url_template
- **`carrier_tracking_mappings`:** แปลง status จาก 3PL → canonical Sheserved status (เช่น Kerry "Picked Up" → `picked_up`)
- **`delivery_orders.carrier_id`:** NULL = in-house fleet, มีค่า = ใช้ 3PL
- **Security:** API key เก็บ encrypted ไม่เก็บ plain text
- **Cost-conscious:** เปิดใช้เมื่อมี carrier จริงเท่านั้น ถ้ายังไม่ใช้ 3PL ให้ปิดโมดูลนี้ไว้

### 9. การจัดตารางเวลาส่ง (Delivery Scheduling)
- **`delivery_orders.delivery_type`:** `asap` หรือ `scheduled`
- **`delivery_window_start` / `delivery_window_end`:** ช่วงเวลาที่ลูกค้าต้องการรับ
- **ASAP:** assign ทันทีเมื่อ `packed`
- **Scheduled:** ไม่ assign ก่อนถึงเวลา แต่ reserve ไว้ใน `rider_shift` → ระบบ batch assign ตามเวลานัด

---

## 🔒 มาตรการควบคุมต้นทุนแผนที่ (Maps Cost Prevention)

เพื่อให้การคำนวณระยะทางและการติดตามพิกัดมีประสิทธิภาพโดย**ไม่เกิดค่าใช้จ่าย API ล่าช้า (Zero Billing Cost)**:

### 1. Mobile-Only Maps (Display & Search)
- การแสดงผลแผนที่, การค้นหาสถานที่, และระบบ Tracking ทั้งหมดใช้ **Google Maps SDK for iOS/Android** เท่านั้น และหลีกเลี่ยงการใช้ **Maps JavaScript API** บน web dashboard
- **Web Dashboard:** แสดงผลเฉพาะ "ข้อความสถานะ" หรือตัวเลขระยะทางที่บันทึกในฐานข้อมูล **ห้าม** โหลด Google Maps JavaScript API

### 2. Backend Distance Calculation (Zero-Cost Strategy)
- **Cache ระยะทาง:** หลังจากคำนวณระยะทางครั้งแรก (ไม่ว่าจาก Mobile หรือ Backend) ให้เก็บ `distance_km` ลง `delivery_orders` และ `route_stops` ทันที ไม่คำนวณซ้ำ
- **OpenStreetMap (OSRM) เป็นทางเลือก:** หากต้องการคำนวณระยะทางหลายจุดพร้อมกัน (batch route optimization) ใช้ **OSRM** (Open Source Routing Machine) หรือ **Valhalla** แทน Google Maps Distance Matrix API
  - OSRM สามารถ host เองได้ฟรี หรือใช้ public demo server สำหรับ development
  - เหมาะกับการคำนวณเส้นทางหลาย stop ใน `delivery_runs`
- **Mapbox เป็นทางเลือกที่ 2:** หากต้องการความแม่นยำสูงกว่า OSM แต่ราคาถูกกว่า Google Maps API
- **กฎเหล็ก:** ไม่มีการเรียก Maps API ในฝั่ง backend โดยตรงจาก Google ยกเว้นกรณีที่ OSRM ไม่เพียงพอจริง ๆ และต้องมีการอนุมัติ budget ก่อน

---

## Integration กับระบบอื่น ๆ ใน Sheserved

นอกจาก ERP Core แล้ว Delivery Core ต้องทำงานร่วมกับระบบย่อยต่อไปนี้อย่างสมบูรณ์:

### 1. CRM / Notification (แจ้งเตือนลูกค้า)
- **Trigger:** ทุกครั้งที่ `delivery_orders.status` เปลี่ยน ให้ insert `outbox_events` (type=`delivery.status_changed`) พร้อม `payload` ที่มี `status`, `recipient_phone`, `recipient_name`
- **Channel:**
  - SMS ผ่านระบบ SMS gateway ที่ Sheserved มีอยู่แล้ว (ไม่เพิ่มค่าใช้จ่ายถ้าใช้ provider เดิม)
  - Push Notification ผ่าน Firebase Cloud Messaging (FCM) ที่เชื่อมกับ Mobile App อยู่แล้ว
- **Template:** ไม่ต้องสร้าง service ใหม่ เก็บ template ใน `organization_feature_flags` หรือ JSONB config ของ `professions`
  - `assigned` → "ไรเดอร์ [ชื่อ] กำลังไปส่งยาถึงคุณ"
  - `at_dropoff` → "ไรเดอร์ถึงจุดหมายแล้ว กรุณาเตรียมรับยา"
  - `delivered` → "จัดส่งสำเร็จ กรุณาตรวจสอบยา"
  - `failed_attempt` → "จัดส่งไม่สำเร็จ กรุณาติดต่อกลับ"

### 2. KPI Dashboard (Executive View)
- **Metrics ที่ต้อง expose ให้ KPI Dashboard:**
  - `avg_delivery_time_minutes` — ระยะเวลาจาก `packed_at` ถึง `delivered_at`
  - `on_time_delivery_rate` — เปรียบเทียบ `delivered_at` กับ `delivery_window_end`
  - `exception_rate` — จำนวน `delivery_exceptions` / จำนวน `delivery_orders`
  - `rider_utilization_rate` — `assigned_orders` / `max_orders` ใน `rider_shifts`
- **วิธีดึง:** ใช้ PostgreSQL Materialized View หรือ Pre-computed Snapshot (ตามแนวทาง Read Model / Analytics Core ใน `ERP_CORE_ARCHITECTURE.md`) ไม่ต้องสร้าง data warehouse ใหม่

### 3. Telemedicine / Chat Consultation (ใบสั่งยา → Delivery)
- **Flow:**
  1. แพทย์สั่งจ่ายยาในระบบแชท/วิดีโอคอล (HIS/Chat Consultation)
  2. ระบบ HIS สร้าง `prescriptions` record พร้อม `patient_id`, `medication_ids`
  3. ห้องยา (Pharmacy) ยืนยันการจ่ายยา → สร้าง `delivery_orders` ด้วย `source_type = 'telemedicine'` และ `source_order_id = prescription_id`
  4. ระบบ Inventory ทำการ `pack` (ตัด `inventory_reservations` หรือ `stock_movements`) แล้วอัปเดต `delivery_orders.status = 'packed'`
  5. Delivery Core ดำเนินการตามปกติ
- **สิ่งที่ต้องเพิ่มใน schema:** `prescriptions` ต้องมี `delivery_needed BOOLEAN DEFAULT false` เพื่อให้ห้องยารู้ว่าต้องสร้าง delivery order หรือไม่

### 4. Donation System (จัดส่งของบริจาค/ของที่ระลึก)
- **Use case:** ผู้บริจาคอาจได้รับของที่ระลึกหรือของขวัญจากแคมเปญ ซึ่งต้องจัดส่งทางไปรษณีย์หรือไรเดอร์
- **Integration:** สร้าง `delivery_orders` ด้วย `source_type = 'manual'` และ `source_order_id` = `donation_request_id` หรือ `donation_transaction_id`
- **Rider/Volunteer reuse:** ไรเดอร์ใน `riders` table อาจเป็น "จิตอาสา" จาก Donation System ที่มี `user_group_roles` เป็น volunteer ได้ (ไม่ต้องสร้างตารางใหม่)

### 5. Lab System (การส่งตัวอย่าง — Sample Collection)
- **Use case:** การเก็บตัวอย่างเลือด/ปัสสาวะที่บ้านผู้ป่วยแล้วส่งไปยัง Lab
- **Integration:**
  - `source_type = 'manual'` หรือเพิ่ม `'lab'` ใน CHECK constraint
  - ไรเดอร์รับตัวอย่างจากบ้านผู้ป่วย (ใช้ `proof_of_deliveries` เป็นหลักฐานรับตัวอย่าง)
  - ส่งต่อไปยัง Lab โดยใช้ `delivery_runs` + `route_stops` (stop_type = `pickup` ที่บ้านผู้ป่วย → `delivery` ที่ Lab)

### 6. Inventory Core (ตัดสต๊อกอย่างปลอดภัย)
- **ปัญหา:** `Delivery_PLAN.md` เก่ากล่าวถึง "Inventory Sync" แบบง่าย ๆ แต่ไม่ได้อธิบายว่าใช้ `stock_movements` หรือ `inventory_reservations` อย่างไร
- **แนวทางที่ถูกต้อง (ตาม `ERP_CORE_ARCHITECTURE.md`):**
  - `pending` → ยังไม่ตัดสต๊อก อาจมี `inventory_reservations` (ถ้ามีการจอง)
  - `packed` → แพ็คยาจาก `inventory_lots` ตาม FEFO (First Expired First Out) → สร้าง `stock_movements` (type='sale') พร้อม `lot_id`
  - `delivered` → ไม่ต้องตัดสต๊อกอีก เพราะตัดตอน `packed` แล้ว แต่ต้อง `release reservation`
  - `cancelled` / `returned_to_warehouse` → สร้าง `stock_movements` (type='return') เพื่อคืนสต๊อก
- **Outbox:** ทุกการเปลี่ยน `status` ที่กระทบสต๊อก ต้องผ่าน `outbox_events` → worker อ่านแล้วสร้าง `stock_movements` (แยก transaction ป้องกัน rollback ยาก)

### 7. Accounting / General Ledger (รับรู้รายได้ค่าขนส่ง)
- **ปัญหา:** แผนเก่ากล่าวถึง "Accounting Sync" แบบง่าย ๆ แต่ไม่ได้อธิบายว่าค่าส่งถูกบันทึกใน GL อย่างไร
- **แนวทางที่ถูกต้อง:**
  - ค่าส่ง (`shipping_fee`) ถูก snapshot ใน `delivery_orders.fee_snapshot` ตอนสร้าง order (ไม่เปลี่ยนแปลงได้)
  - เมื่อ `status = 'delivered'` ให้ insert `outbox_events` (type='delivery.revenue_recognized')
  - Worker อ่าน outbox → สร้าง GL Entry (Double-entry):
    - Debit: Cash / Accounts Receivable
    - Credit: Revenue - Delivery Fee (account code ตาม Chart of Accounts)
  - หากมี COD (เก็บเงินปลายทาง) ให้ Debit: Accounts Receivable - COD → Credit: Revenue

---

## ข้อเสนอเพิ่มเติมเพื่อความเร็วและความปลอดภัยแบบไม่เพิ่มค่าใช้จ่าย (No-cost Hardening)

### 1. บังคับใช้ state transition ที่ database layer
- สร้าง trigger หรือ stored procedure เพื่ออนุญาตเฉพาะ transition ที่ถูกต้อง เช่น `packed -> ready_for_pickup -> assigned`
- ป้องกันการเขียนสถานะข้ามขั้นตอนจาก client หรือ worker ที่ผิดพลาด
- บันทึก `status_changed_at` ทุกครั้งที่ state เปลี่ยน เพื่อใช้ตรวจสอบย้อนหลังได้ทันที

### 2. ใช้ partial index กับ query ที่เกิดบ่อย
- `delivery_orders(profession_id, status, created_at DESC)` สำหรับงาน dashboard และรายชื่อออเดอร์วันนี้
- `delivery_orders(delivery_window_start, status)` สำหรับงาน scheduled delivery
- `delivery_tracking(delivery_order_id, recorded_at DESC)` สำหรับเส้นทางล่าสุดของแต่ละออเดอร์
- `delivery_exceptions(resolved_at) WHERE resolved_at IS NULL` สำหรับรายการค้างแก้ไข

### 3. ลดการ lock นานเกินจำเป็น
- ใช้ `SELECT ... FOR UPDATE` เฉพาะตอน reserve / assign / confirm เท่านั้น
- หลีกเลี่ยงการถือ lock ระหว่างเรียก API ภายนอก เช่น 3PL หรือ notification service
- หากเกิด contention สูง ให้ retry แบบสั้นแทนการรอ lock นาน

### 4. ใช้ outbox pattern สำหรับผลกระทบข้ามระบบ
- ทุก event ที่กระทบ Inventory หรือ Accounting ควรออกผ่าน `outbox_events`
- ทำให้การเปลี่ยนสถานะ delivery ไม่ผูกกับการ call service อื่นแบบ synchronous
- ลดโอกาสข้อมูลค้างครึ่งทางและ rollback ยาก

### 5. ควบคุมข้อมูล tracking ให้เหมาะกับโหลด
- เก็บตำแหน่งไรเดอร์เป็นช่วงเวลา ไม่ต้องบันทึกถี่เกินจำเป็น
- ปรับ interval ตาม run / shift / zone เพื่อประหยัด write volume
- ถ้า volume โตในอนาคต ค่อยพิจารณา partition ตาราง `delivery_tracking` ตามเดือนโดยไม่ต้องเพิ่ม service ใหม่

---

## Database Schema (Canonical — อ้างอิง ERP_CORE_ARCHITECTURE.md)

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
  zone_coverage     TEXT[] DEFAULT '{}',
  is_active         BOOLEAN DEFAULT true,
  current_status    TEXT DEFAULT 'offline'
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
  source_type         TEXT NOT NULL DEFAULT 'pos'
                        CHECK (source_type IN ('pos', 'telemedicine', 'platform', 'manual')),
  source_order_id     UUID,
  rider_id            UUID REFERENCES riders(id),
  carrier_id          UUID,
  recipient_name      TEXT NOT NULL,
  recipient_phone     TEXT NOT NULL,
  dest_address        TEXT,
  dest_latitude       DECIMAL(10, 8),
  dest_longitude      DECIMAL(11, 8),
  distance_km         DECIMAL(10, 2),
  shipping_fee        DECIMAL(12, 2) DEFAULT 0,
  fee_snapshot        JSONB DEFAULT '{}',
  delivery_type       TEXT NOT NULL DEFAULT 'asap'
                        CHECK (delivery_type IN ('asap', 'scheduled')),
  delivery_window_start TIMESTAMPTZ,
  delivery_window_end   TIMESTAMPTZ,
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
  package_count       INTEGER DEFAULT 1,
  package_weight_kg   DECIMAL(8,2) DEFAULT 0,
  special_instructions TEXT,
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
  stop_type         TEXT NOT NULL DEFAULT 'delivery'
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
-- 5. RIDER ASSIGNMENTS
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
  expires_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_rider_assignments_order ON rider_assignments(delivery_order_id);
CREATE INDEX idx_rider_assignments_rider ON rider_assignments(rider_id, status);
CREATE INDEX idx_rider_assignments_pending ON rider_assignments(status, expires_at)
  WHERE status = 'pending';

-- ============================================
-- 6. PROOF OF DELIVERY (POD)
-- ============================================
CREATE TABLE proof_of_deliveries (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_order_id       UUID NOT NULL REFERENCES delivery_orders(id),
  delivered_by            UUID NOT NULL REFERENCES riders(id),
  recipient_name          TEXT,
  recipient_signature_url TEXT,
  delivery_photo_url      TEXT,
  verification_code       TEXT,
  notes                   TEXT,
  latitude                DECIMAL(10, 8),
  longitude               DECIMAL(11, 8),
  delivered_at            TIMESTAMPTZ DEFAULT now(),
  created_at              TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_pod_order ON proof_of_deliveries(delivery_order_id);

-- ============================================
-- 7. DELIVERY EXCEPTIONS
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
  reason            TEXT NOT NULL,
  reported_by       UUID NOT NULL REFERENCES users(id),
  photo_url         TEXT,
  resolved_by       UUID REFERENCES users(id),
  resolution_type   TEXT
                    CHECK (resolution_type IN ('reattempt_same_day', 'reattempt_next_day', 'return_to_warehouse', 'cancel_and_refund')),
  resolution_notes  TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  resolved_at       TIMESTAMPTZ
);
CREATE INDEX idx_exceptions_order ON delivery_exceptions(delivery_order_id);
CREATE INDEX idx_exceptions_unresolved ON delivery_exceptions(resolved_at)
  WHERE resolved_at IS NULL;

-- ============================================
-- 8. 3PL CARRIER CONFIGS
-- ============================================
CREATE TABLE carrier_configs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id       UUID NOT NULL REFERENCES professions(id),
  carrier_name        TEXT NOT NULL,
  carrier_code        TEXT NOT NULL,
  api_base_url        TEXT,
  api_key_encrypted   TEXT,
  api_secret_encrypted TEXT,
  tracking_url_template TEXT,
  is_active           BOOLEAN DEFAULT true,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, carrier_code)
);

CREATE TABLE carrier_tracking_mappings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carrier_id      UUID NOT NULL REFERENCES carrier_configs(id),
  carrier_status  TEXT NOT NULL,
  canonical_status TEXT NOT NULL,
  description     TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 9. DELIVERY FEE RULES
-- ============================================
CREATE TABLE delivery_fee_rules (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id),
  rule_name         TEXT NOT NULL,
  rule_type         TEXT NOT NULL
                    CHECK (rule_type IN ('distance', 'zone', 'weight', 'time_window', 'urgency', 'flat_rate')),
  priority          INTEGER NOT NULL DEFAULT 100,
  zone_polygon      JSONB,
  min_distance_km   DECIMAL(8, 2) DEFAULT 0,
  max_distance_km   DECIMAL(8, 2) DEFAULT 9999,
  min_weight_kg     DECIMAL(8, 2) DEFAULT 0,
  max_weight_kg     DECIMAL(8, 2) DEFAULT 9999,
  time_window_start TIME,
  time_window_end   TIME,
  base_fee          DECIMAL(12, 2) NOT NULL DEFAULT 0,
  per_km_fee        DECIMAL(12, 2) DEFAULT 0,
  per_kg_fee        DECIMAL(12, 2) DEFAULT 0,
  time_multiplier   DECIMAL(4, 2) DEFAULT 1.00,
  urgency_multiplier DECIMAL(4, 2) DEFAULT 1.00,
  is_active         BOOLEAN DEFAULT true,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_fee_rules_profession ON delivery_fee_rules(profession_id, is_active, priority DESC);

-- ============================================
-- 10. DELIVERY TRACKING (location updates)
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

---

## ตำแหน่งใน ERP Phase Ordering

Delivery Core อยู่ใน **ERP Phase 2** (หลังจาก Inventory Core และ Commerce Core เสร็จสิ้นใน Phase 1) โดยมีลำดับความสำคัญดังนี้:

| ลำดับ | โมดูล | ความสำคัญ | หมายเหตุ |
|---|---|---|---|
| 2.1 | `riders` + `rider_shifts` | สูง | ต้องมีก่อนจึงจะ assign งานได้ |
| 2.2 | `delivery_orders` (เต็มรูป) + `delivery_fee_rules` | สูง | รองรับ state machine และ fee engine |
| 2.3 | `delivery_tracking` + `rider_assignments` | สูง | Real-time tracking และ dispatch |
| 2.4 | `proof_of_deliveries` | ปานกลาง | จำเป็นต่อการยืนยันการส่ง |
| 2.5 | `delivery_exceptions` | ปานกลาง | รองรับ exception หลัง go-live |
| 2.6 | `delivery_runs` + `route_stops` | ต่ำ-ปานกลาง | ใช้เมื่อมี batch delivery หลายออเดอร์ |
| 2.7 | `carrier_configs` + `carrier_tracking_mappings` | ต่ำ | เปิดใช้เมื่อมี 3PL จริงเท่านั้น |
| 2.8 | **Delivery Provider Selection** | ต่ำ (Phase ท้าย) | องค์กรและลูกค้าเลือกผู้ให้บริการส่งได้ |

---

## การเลือกผู้ให้บริการจัดส่ง (Delivery Provider Selection) — Phase ท้าย

ระบบรองรับ **3 รูปแบบการจัดส่ง** โดยให้ **องค์กร (ERP)** เลือกเปิดใช้รูปแบบใดบ้าง และ **ลูกค้า** เลือกได้ตามรูปแบบที่องค์กรเปิดไว้

### รูปแบบการจัดส่งทั้ง 3 ประเภท

| รูปแบบ | ชื่อ | รายละเอียด | ผู้รับผิดชอบค่าส่ง |
|---|---|---|---|
| **A** | **In-House Delivery** (ส่งเอง) | ใช้ไรเดอร์/พนักงานของร้าน/คลินิกเอง (`riders` table) | องค์กรเป็นผู้กำหนดค่าส่ง |
| **B** | **Sheserved Platform Delivery** | ใช้ fleet กลางของ Sheserved (ไรเดอร์ที่ Sheserved จัดหา คล้าย Grab/LINE MAN) | Sheserved เป็นผู้กำหนดค่าส่ง หักจากยอดขาย |
| **C** | **Third-Party Provider** (ผู้ให้บริการภายนอก) | เชื่อมต่อ API กับ GrabExpress, LINE MAN, Foodpanda (pandago), ShopeeFood ฯลฯ | ผู้ให้บริการภายนอกเป็นผู้กำหนด |

### สิทธิ์การเลือก

```
┌─────────────────────────────────────────────────────────────┐
│  ERP Dashboard — Organization Settings                      │
│  [Delivery Settings]                                        │
│                                                             │
│  ☑ เปิดใช้ In-House Delivery                               │
│     └─ ค่าส่ง: [กำหนดเอง / ตามระยะทาง / ฟรี]              │
│                                                             │
│  ☑ เปิดใช้ Sheserved Platform Delivery                    │
│     └─ ค่าส่ง: [ตาม Sheserved rate card]                    │
│                                                             │
│  ☑ เปิดใช้ Third-Party Providers                           │
│     └─ เลือกผู้ให้บริการ:                                   │
│        ☑ GrabExpress                                        │
│        ☑ LINE MAN                                           │
│        ☑ Foodpanda (pandago)                                │
│        ☐ ShopeeFood                                         │
│                                                             │
│  [บันทึกการตั้งค่า]                                         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Checkout Page — Customer View                              │
│  "เลือกวิธีการจัดส่ง:"                                       │
│                                                             │
│  ○ ส่งโดยร้าน (In-House) — ฿30                              │
│  ○ ส่งโดย Sheserved — ฿45                                   │
│  ○ ส่งโดย GrabExpress — ฿52 (ประมาณ)                       │
│                                                             │
│  (แสดงเฉพาะที่องค์กรเปิดใช้ และคำนวณราคา real-time)        │
└─────────────────────────────────────────────────────────────┘
```

### Schema — เพิ่มตารางและฟิลด์

#### 1. `organization_delivery_settings` (ตั้งค่าระดับองค์กร)

```sql
CREATE TABLE organization_delivery_settings (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID REFERENCES professions(id) UNIQUE,
                          -- NULL = ตั้งค่าระดับ Platform (default สำหรับทุกองค์กร)
                          -- มีค่า = override เฉพาะองค์กรนั้น

  -- In-House (ใช้ได้เฉพาะเมื่อมี profession_id — ต้องมีองค์กร)
  enable_in_house       BOOLEAN DEFAULT true,
  in_house_fee_type     TEXT DEFAULT 'custom'
                            CHECK (in_house_fee_type IN ('custom', 'distance', 'free')),
  in_house_custom_fee   DECIMAL(12,2) DEFAULT 0,

  -- Sheserved Platform (ใช้ได้แม้ไม่มีองค์กร — เป็น Fleet กลางของ Platform)
  enable_sheserved      BOOLEAN DEFAULT false,

  -- Third-Party (ใช้ได้แม้ไม่มีองค์กร — เป็น Integration ระดับ Platform)
  enable_third_party    BOOLEAN DEFAULT false,

  -- ลำดับความชอบ (priority) สำหรับแสดงใน UI
  provider_priority     TEXT[] DEFAULT ARRAY['in_house', 'sheserved', 'third_party'],

  -- ค่าส่งขั้นต่ำที่ลูกค้าต้องจ่าย (subsidize จากองค์กรได้)
  minimum_shipping_fee  DECIMAL(12,2) DEFAULT 0,
  free_shipping_threshold DECIMAL(12,2) DEFAULT NULL, -- ยอดซื้อถึงส่งฟรี

  is_platform_default   BOOLEAN DEFAULT false, -- true = ตั้งค่า default ของ Platform

  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- Index สำหรับหา platform default เร็ว
CREATE UNIQUE INDEX idx_platform_default ON organization_delivery_settings(profession_id, is_platform_default)
  WHERE profession_id IS NULL;
```

#### 2. `organization_third_party_carriers` (เปิดใช้ carrier ใดบ้าง)

```sql
CREATE TABLE organization_third_party_carriers (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id         UUID REFERENCES professions(id),
                          -- NULL = Platform-level integration (ใช้ได้กับทุกองค์กร)
                          -- มีค่า = Override ระดับองค์กร (เช่น ใช้ API key ขององค์กรเอง)
  carrier_code          TEXT NOT NULL
                            CHECK (carrier_code IN (
                              'grab_express', 'line_man', 'foodpanda',
                              'shopee_food', 'kerry', 'flash_express', 'thai_post'
                            )),
  is_active             BOOLEAN DEFAULT true,
  api_key_encrypted     TEXT,        -- ถ้าต้องใช้ API key ขององค์กรเอง (NULL = ใช้ Platform key)
  contract_rate_json    JSONB DEFAULT '{}', -- rate card ที่ตกลงกับ carrier
  is_platform_default   BOOLEAN DEFAULT false,
  created_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE (profession_id, carrier_code)
);
```

> **หมายเหตุ:** Model B (Sheserved Platform) และ Model C (Third-Party) ทำงานได้แม้ไม่มี `profession_id` (ไม่มีองค์กรเข้าร่วม) เพราะเป็น **บริการระดับ Platform** ที่ Sheserved เป็นผู้ดูแล fleet/API key เอง ส่วน Model A (In-House) จำเป็นต้องมี `profession_id` เสมอ

#### 3. `delivery_orders` เพิ่มฟิลด์

```sql
ALTER TABLE delivery_orders ADD COLUMN IF NOT EXISTS provider_type TEXT DEFAULT 'in_house'
  CHECK (provider_type IN ('in_house', 'sheserved', 'third_party'));
ALTER TABLE delivery_orders ADD COLUMN IF NOT EXISTS carrier_code TEXT;
  -- NULL = in_house / sheserved, มีค่า = third_party carrier code
ALTER TABLE delivery_orders ADD COLUMN IF NOT EXISTS customer_selected_provider BOOLEAN DEFAULT false;
  -- true = ลูกค้าเป็นผู้เลือก, false = ระบบ auto-assign หรือ default
ALTER TABLE delivery_orders ADD COLUMN IF NOT EXISTS provider_fee_estimate DECIMAL(12,2);
  -- ค่าส่งประมาณการตอน checkout (real-time quote จาก third-party)
ALTER TABLE delivery_orders ADD COLUMN IF NOT EXISTS provider_fee_actual DECIMAL(12,2);
  -- ค่าส่งจริงหลังส่งเสร็จ (อาจต่างจากประมาณการ)
```

### กลไกการเลือก (Selection Engine)

```dart
class DeliveryProviderSelector {
  /// ดึงรายการผู้ให้บริการที่เปิดใช้ พร้อมค่าส่งประมาณการ
  /// 
  /// - ถ้ามี professionId (มีองค์กร): ใช้ setting ขององค์กร + fallback ไป Platform default
  ///   สำหรับ Model B และ C
  /// - ถ้าไม่มี professionId (ไม่มีองค์กร/สั่งผ่าน Platform โดยตรง): 
  ///   ใช้ได้แค่ Model B (Sheserved) และ Model C (Third-Party)
  Future<List<ProviderOption>> getAvailableProviders({
    String? professionId,      // NULL = ไม่มีองค์กร (Platform direct order)
    required LatLng origin,
    required LatLng destination,
    required Decimal orderAmount,
    required Decimal packageWeightKg,
  }) async {
    final options = <ProviderOption>[];

    // ดึง setting องค์กร (ถ้ามี) และ Platform default (สำหร fallback)
    final orgSettings = professionId != null
        ? await _settingsRepo.getSettings(professionId)
        : null;
    final platformSettings = await _settingsRepo.getPlatformDefault();

    // A. In-House — ใช้ได้เฉพาะเมื่อมีองค์กรเท่านั้น
    if (professionId != null && orgSettings?.enableInHouse == true) {
      final fee = await _calculateInHouseFee(
        orgSettings!.inHouseFeeType,
        origin: origin,
        destination: destination,
      );
      options.add(ProviderOption(
        type: ProviderType.inHouse,
        name: 'ส่งโดยร้าน',
        estimatedFee: fee,
        estimatedMinutes: await _estimateInHouseTime(origin, destination),
      ));
    }

    // B. Sheserved Platform — ใช้ได้ทั้งมี/ไม่มีองค์กร
    // ถ้ามี orgSettings เปิดไว้ → ใช้ org, ไม่มี → fallback ไป platform default
    final sheservedEnabled = orgSettings?.enableSheserved
        ?? platformSettings.enableSheserved;
    if (sheservedEnabled) {
      final fee = await _sheservedApi.getQuote(
        origin: origin,
        destination: destination,
        weightKg: packageWeightKg,
      );
      options.add(ProviderOption(
        type: ProviderType.sheserved,
        name: 'ส่งโดย Sheserved',
        estimatedFee: fee,
        estimatedMinutes: fee.estimatedMinutes,
      ));
    }

    // C. Third-Party — ใช้ได้ทั้งมี/ไม่มีองค์กร
    // ถ้ามี orgSettings เปิดไว้ → ใช้ org carriers, ไม่มี → ใช้ Platform carriers
    final thirdPartyEnabled = orgSettings?.enableThirdParty
        ?? platformSettings.enableThirdParty;
    if (thirdPartyEnabled) {
      final carriers = professionId != null
          ? await _carrierRepo.getActiveCarriersForOrg(professionId)
          : await _carrierRepo.getPlatformDefaultCarriers();

      for (final carrier in carriers) {
        final quote = await _thirdPartyAdapters[carrier.code]!.getQuote(
          origin: origin,
          destination: destination,
          weightKg: packageWeightKg,
          orderAmount: orderAmount,
        );
        options.add(ProviderOption(
          type: ProviderType.thirdParty,
          name: carrier.displayName,
          carrierCode: carrier.code,
          estimatedFee: quote.fee,
          estimatedMinutes: quote.estimatedMinutes,
        ));
      }
    }

    // จัดลำดับตาม priority (org ถ้ามี, ไม่มี → platform default)
    final priority = orgSettings?.providerPriority
        ?? platformSettings.providerPriority;
    return _sortByPriority(options, priority);
  }

  /// ตรวจสอบ free shipping threshold
  /// ถ้ามีองค์กร → ใช้ threshold ขององค์กร, ไม่มี → ใช้ platform default (หรือไม่มี)
  Decimal? applyFreeShipping(Decimal orderAmount, {
    OrganizationDeliverySettings? orgSettings,
    required OrganizationDeliverySettings platformSettings,
  }) {
    final threshold = orgSettings?.freeShippingThreshold
        ?? platformSettings.freeShippingThreshold;
    if (threshold != null && orderAmount >= threshold) {
      return Decimal.zero;
    }
    return null;
  }
}
```

### การชำระเงินค่าส่ง (Fee Settlement)

| รูปแบบ | มีองค์กร | ไม่มีองค์กร (Platform Direct) | ผู้รับเงิน | การตั้งบัญชี |
|---|---|---|---|---|
| **A: In-House** | ✅ ใช้ได้ | ❌ ใช้ไม่ได้ | องค์กร | ไม่ต้อง split — รวมใน revenue ขององค์กร |
| **B: Sheserved** | ✅ ใช้ได้ | ✅ ใช้ได้ | Sheserved Platform | หักค่าส่งจากยอดขายก่อน payout ให้องค์กร (commission model) หรือเก็บจากลูกค้าโดยตรงถ้าไม่มีองค์กร |
| **C: Third-Party** | ✅ ใช้ได้ | ✅ ใช้ได้ | Carrier ภายนอก | องค์กรเป็นผู้จ่ายตรง / Sheserved เป็นตัวกลางจ่ายแล้วเก็บจากองค์กร (bill later) หรือเก็บจากลูกค้าโดยตรงถ้าไม่มีองค์กร |

### UI — Organization Delivery Settings Page (สำหรับ Admin ขององค์กร)

```dart
class OrganizationDeliverySettingsPage extends StatelessWidget {
  // ── Model A: In-House Delivery ────────────────────────
  // ✅ แก้ไขได้ — องค์กรกำหนดเอง
  //    - Toggle เปิด/ปิด
  //    - Fee type: fixed / distance / free
  //    - Custom fee amount (ถ้า fixed)
  //    - Distance tiers (ถ้า distance)
  //    - Zone polygon (ถ้า zone-based)
  //
  // ── Model B: Sheserved Platform Delivery ──────────────
  // 🔒 อ่านอย่างเดียว — แก้ไขไม่ได้
  //    - Toggle เปิด/ปิด ใช้งานได้ ✅
  //    - Rate card แสดงเป็น read-only (Sheserved เป็นผู้กำหนด)
  //    - แสดง fee estimate sample ตามระยะทาง
  //
  // ── Model C: Third-Party Providers ────────────────────
  // ✅ Toggle เปิด/ปิดได้
  //    - เลือก carrier ที่องค์กรต้องการใช้
  //    - ใส่ API key ขององค์กรเอง (ถ้ามี contract ตรงกับ carrier)
  //    - ถ้าไม่ใส่ API key → ใช้ Platform API key (fallback)
  //    - Contract rate แสดงเป็น read-only ถ้าใช้ Platform key
  //
  // ── ลำดับความชอบ + Free Shipping Threshold ───────────
  //    - Drag & drop reorder ทุก provider ที่เปิดไว้
  //    - Free shipping threshold (ยอดซื้อถึงส่งฟรี)
}
```

### UI — Platform Admin Delivery Settings Page (สำหรับ Admin ระบบ Sheserved)

```dart
class PlatformDeliverySettingsPage extends StatelessWidget {
  // เข้าถึงได้เฉพาะ role_level = 1 (Sheserved Super Admin)
  //
  // ── Model B: Sheserved Platform Rate Card ─────────────
  //    - Base fee (THB)
  //    - Per km fee
  //    - Per kg fee
  //    - Rush hour multiplier
  //    - Urgency multiplier
  //    - Zone-based rates (polygon map)
  //    - บันทึกเป็น `platform_delivery_rate_cards` (versioned)
  //
  // ── Model C: Third-Party Platform Defaults ────────────
  //    - จัดการ Platform API key แต่ละ carrier (encrypted)
  //    - Platform contract rate (default สำหรับทุกองค์กร)
  //    - Toggle เปิด/ปิด carrier ระดับ Platform
  //
  // ── Organization Override View ────────────────────────
  //    - ดูรายการองค์กรที่เปิดใช้แต่ละรูปแบบ
  //    - ดู aggregated usage ต่อรูปแบบ (reporting)
}
```

#### Schema — `platform_delivery_rate_cards` (ตั้งค่าระดับ Platform)

```sql
CREATE TABLE platform_delivery_rate_cards (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_type         TEXT NOT NULL
                            CHECK (provider_type IN ('sheserved', 'third_party')),
  carrier_code          TEXT,        -- NULL ถ้า sheserved, มีค่าถ้า third_party

  -- Fee structure
  base_fee              DECIMAL(12,2) NOT NULL DEFAULT 0,
  per_km_fee            DECIMAL(12,2) DEFAULT 0,
  per_kg_fee            DECIMAL(12,2) DEFAULT 0,
  time_multiplier       DECIMAL(4,2) DEFAULT 1.00,
  urgency_multiplier    DECIMAL(4,2) DEFAULT 1.00,

  -- Zone-based (optional)
  zone_json             JSONB DEFAULT NULL, -- { "zones": [{ "name": "กรุงเทพฯ", "polygon": [...], "fee": 30 }] }

  -- Versioning
  version               INTEGER NOT NULL DEFAULT 1,
  is_active             BOOLEAN DEFAULT true,
  effective_from        TIMESTAMPTZ DEFAULT now(),
  effective_to          TIMESTAMPTZ,
  created_by            UUID REFERENCES users(id),

  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- อนุญาติให้มีได้แค่ 1 active version ต่อ provider_type+carrier_code
CREATE UNIQUE INDEX idx_platform_rate_active
  ON platform_delivery_rate_cards(provider_type, carrier_code)
  WHERE is_active = true;
```

### UI — Customer Checkout

```dart
class DeliveryProviderSelectorWidget extends StatelessWidget {
  // แสดงรายการ provider พร้อมค่าส่งประมาณการ + เวลาถึงประมาณการ
  // ลูกค้าเลือก 1 รายการ
  // ถ้ามี free shipping → แสดง badge "ส่งฟรี"
}
```

---

## หมายเหตุสำคัญ

- **Canonical Schema:** หาก schema ในส่วนนี้มีความขัดแย้งกับ `ERP_CORE_ARCHITECTURE.md` ให้ถือ `ERP_CORE_ARCHITECTURE.md` เป็นหลัก
- **Commerce Core เป็น upstream:** `delivery_orders` ไม่ควรสร้างโดยตรงจาก POS อีกต่อไป แต่ควรสร้างผ่าน `Commerce Core` (ผ่าน `source_type`/`source_order_id`)
- **Reliability Core:** ทุกการเปลี่ยนแปลงสถานะที่กระทบ Inventory หรือ Accounting ต้องผ่าน `outbox_events` + `stock_movements` เพื่อความปลอดภัยของข้อมูล
