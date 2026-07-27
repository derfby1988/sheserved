# แผนป้องกัน 11: Input Validation

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-B
> **เกี่ยวข้องกับแผน:** 13 (SQL Injection), 14 (XSS), 12 (Least Privilege)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-B ลำดับ 4** โดยเริ่มจาก auth, upload, financial และ clinical endpoints ก่อน แล้วค่อยขยายให้ครบทุก route
> **เหตุผล:** client-side validator เป็นเพียง UX ไม่ใช่ security boundary; schema validation ต้องอยู่ก่อน business logic/DB และต้องทำคู่กับ DB constraints สำหรับข้อมูลสำคัญ เพื่อลด payload abuse และข้อมูลเสียหายโดยไม่รอ refactor ทั้งระบบ

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่มีอยู่ ✅
| องค์ประกอบ | รายละเอียด | ตำแหน่ง |
|-----------|------------|---------|
| Flutter `TextFormField.validator` | ตรวจ required / รูปแบบพื้นฐาน กระจายตามหน้า | หน้า register, login, forms ต่าง ๆ |
| Multer file filter | จำกัดชนิดไฟล์ (PNG เท่านั้นสำหรับ watermark), ขนาด 5MB | `websocket-server/routes/admin.js` |
| Video upload limit | ตรวจขนาดไฟล์ 20MB ซ้ำอีกชั้นนอกเหนือจาก multer | `websocket-server/routes/video.js:97` |
| Idempotency / duplicate check | ป้องกันการส่งซ้ำ | `websocket-server/middleware/idempotency.js` |
| Rate limiting | จำกัดความถี่ request | `websocket-server/middleware/rate-limiter.js` |
| Type safety | Dart strong typing + `UserModel.fromJson` | ทั่วโปรเจกต์ |

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| V1 | **ไม่มี validation layer กลาง** | 🟡 กลาง | แต่ละหน้าเขียน validator เอง กฎไม่ตรงกัน (เช่น เบอร์โทร 10 หลัก vs 9 หลัก) |
| V2 | **Backend รับ `req.body` โดยไม่ validate schema** | 🔴 สูง | routes ส่วนใหญ่ destructure `req.body` แล้วใส่ลง SQL ทันที — ค่า null/ผิดชนิด/เกินความยาวเข้าถึง DB ได้ |
| V3 | **ไม่มี allowlist สำหรับ enum fields** | 🟡 กลาง | เช่น `status`, `type`, `position`, `animation_type` รับค่าอะไรก็ได้ |
| V4 | **ไม่มีการจำกัดความยาว string** | 🟡 กลาง | `title`, `description`, `text_content` ไม่จำกัด → DoS ผ่าน payload ขนาดใหญ่ |
| V5 | **ไม่ validate ชนิดตัวเลข/ช่วงค่า** | 🟡 กลาง | `opacity`, `alert_radius`, `amount` (การเงิน) — ค่าติดลบหรือเกินขอบเขตผ่านได้ |
| V6 | **File upload: ตรวจแค่ MIME type** | 🟡 กลาง | MIME จาก client ปลอมได้ ควรตรวจ magic bytes ด้วย |
| V7 | **ไม่ validate UUID format** | 🟢 ต่ำ | ป้องกันได้บางส่วนจาก PostgreSQL type แต่ทำให้เกิด 500 แทน 400 |
| V8 | **ไม่มี body size limit ชัดเจน** | 🟡 กลาง | `express.json()` default 100kb แต่ควรกำหนดตาม endpoint |
| V9 | **ไม่ validate ข้อมูลจาก Supabase Realtime** | 🟢 ต่ำ | payload ที่ push มาถือว่าเชื่อถือได้ แต่ควร defensive parse |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | Input ที่รับ | ความเสี่ยงหลัก | สิ่งที่ต้องเพิ่ม |
|------|-------------|---------------|-----------------|
| **Auth & Registration** | username, phone, email, password, profession_id, ไฟล์เอกสาร | username format, phone format, duplicate, file type | schema validation + normalize phone (+66 vs 0) |
| **Home & Navigation** | search query | ความยาว, อักขระพิเศษ | จำกัดความยาว, debounce |
| **Consultation** | ข้อความ, note, body area selection, prescription | ความยาวข้อความ, medication ID ต้องมีจริง, dosage ต้องเป็นตัวเลข | schema + referential check |
| **Chat & Video** | text, image, voice, video file | file size/type, message length, room membership | magic byte check, length cap |
| **Pharmacy & Drug Risk** | drug risk level, override reason, profession_id | enum allowlist, ownership | allowlist + FK validate |
| **Donation + Escrow** | amount, beneficiary info, bank account, slip image | **ตัวเลขการเงิน** — ต้องเข้มที่สุด | decimal precision, ค่า > 0, ceiling, currency |
| **Emergency & Rescue** | GPS coordinates, radius, incident description | lat/lng range, radius ceiling | numeric range validation |
| **Health & Articles** | ค่าสุขภาพ (BP, HR, glucose), บทความ HTML | ช่วงค่าทางการแพทย์, HTML content (ดูแผน 14) | medical range + sanitize |
| **Profile & Settings** | ชื่อ, รูป, radius, availability | image size/type, enum status | file validation |
| **Admin & KPI** | config ทุกชนิด, watermark, platform settings | enum, numeric range, JSON structure | strict schema |

### 2.2 ระบบตามแผน `docs/plans/`

| แผน | Input ที่ต้องระวังเป็นพิเศษ |
|-----|---------------------------|
| `DONATION_SYSTEM_PLAN.md` | จำนวนเงิน, เลขบัญชี, เลขบัตรประชาชน (PII) — ต้อง validate + mask |
| `Delivery_PLAN.md` | ที่อยู่, GPS, ค่าส่ง, น้ำหนัก/ขนาดพัสดุ |
| `SHOPPING_CART_PLAN.md` | quantity (ต้อง > 0, ≤ stock), price ต้องมาจาก server ไม่ใช่ client |
| `VIDEO_SYSTEM_PLAN.md` | video metadata, GPS tracks JSON (parse แบบปลอดภัย), watermark config |
| `health_data_sync_plan.md` | ค่าจากอุปกรณ์ — ต้อง sanity check (HR 300 bpm = ผิดปกติ) |
| `DRUG_RISK_OVERRIDE_PLAN.md` | risk level enum, override reason ความยาว, scope |

### 2.3 ระบบตามแผน `docs/ERP/`

| แผน | Input ที่ต้องระวัง |
|-----|-------------------|
| `ACCOUNTING_SYSTEM_PLAN.md` | GL amount (debit=credit ต้องบาลานซ์), account code, fiscal period |
| `INVENTORY_SYSTEM_PLAN.md` | quantity (ห้ามติดลบเว้นแต่ระบุ), lot/batch, expiry date |
| `PROCUREMENT_SYSTEM_PLAN.md` | PO amount, supplier ID, delivery date, tax rate |
| `POS System_plan.md` | ราคา/ส่วนลด **ต้องคำนวณฝั่ง server** ห้ามเชื่อ client, การชำระเงิน |
| `HR_SYSTEM_PLAN.md` | เงินเดือน, ชั่วโมงทำงาน, วันลา (ต้องไม่ทับซ้อน), เลขประกันสังคม |
| `HIS_SYSTEM_PLAN.md` / `LAB_SYSTEM_PLAN.md` | ค่าผลแล็บ (ช่วงอ้างอิง), ICD code, drug dosage — ผิดพลาด = อันตรายต่อผู้ป่วย |
| `CRM_SYSTEM_PLAN.md` | customer PII, email/phone format |
| `KPI_DASHBOARD_PLAN.md` | target value, date range, aggregate params |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | tier enum, billing amount |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Schema Validation Library ทั้ง 2 ฝั่ง (แนะนำ) ⭐

**Backend (Node.js):** `zod` หรือ `joi`
```js
// websocket-server/schemas/video.schema.js
const uploadVideoSchema = z.object({
  userId: z.string().uuid(),
  title: z.string().min(1).max(200),
  description: z.string().max(2000).optional(),
  type: z.enum(['normal', 'emergency', 'donation']),
  categoryId: z.string().uuid().nullable().optional(),
});

// middleware
router.post('/upload', validate(uploadVideoSchema), requireAuth, handler);
```

**Frontend (Dart):** สร้าง `lib/core/validation/` รวม validator กลาง
```dart
class Validators {
  static String? thaiPhone(String? v) { ... }
  static String? username(String? v) { ... }
  static String? amount(String? v, {double? min, double? max}) { ... }
  static String? medicalRange(String? v, MedicalMetric metric) { ... }
}
```

**ข้อดี**
- กฎเดียวกันทั้งระบบ, ทดสอบได้, error message สม่ำเสมอ
- Zod ให้ TypeScript-style type inference ใน JS
- ปิด V1–V5, V7, V8 พร้อมกัน

**ข้อเสีย**
- ต้องเขียน schema สำหรับทุก endpoint (~100+ endpoints)
- เพิ่ม dependency (ดูแผน 06)
- งานเยอะ: ประเมิน 3–5 สัปดาห์สำหรับระบบปัจจุบัน

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Database Constraints เป็นหลัก

```sql
ALTER TABLE videos ADD CONSTRAINT title_length CHECK (char_length(title) <= 200);
ALTER TABLE videos ADD CONSTRAINT valid_type CHECK (type IN ('normal','emergency','donation'));
ALTER TABLE donations ADD CONSTRAINT positive_amount CHECK (amount > 0);
CREATE DOMAIN thai_phone AS VARCHAR(10) CHECK (VALUE ~ '^0[0-9]{9}$');
```

**ข้อดี**
- บังคับที่ชั้นสุดท้าย — ไม่มีทางเลี่ยงได้ไม่ว่า request มาจากไหน (รวมทั้ง Supabase ตรง)
- ป้องกันข้อมูลเสียหายจาก bug ในโค้ด
- เขียนครั้งเดียวใช้ได้ทั้ง local PostgreSQL และ Supabase

**ข้อเสีย**
- Error message ไม่เป็นมิตรกับผู้ใช้ (ต้อง map เป็นข้อความไทย)
- ตรวจได้แค่ระดับ field ไม่ครอบคลุม business rule ข้าม field
- แก้ constraint = migration ทุกครั้ง

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — **ควรทำควบคู่กับ A เสมอ (defense in depth)**

---

### ตัวเลือก C: Validation ที่ Supabase RPC / Edge Function

ห่อ operation สำคัญไว้ใน PostgreSQL function ที่ validate ก่อนเขียน

**ข้อดี:** ใช้ได้แม้ client ยิง Supabase ตรง; รวม business logic + validation ในที่เดียว
**ข้อเสีย:** เขียน PL/pgSQL ยากกว่า; debug/test ลำบาก; ผูกติด PostgreSQL
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — เหมาะเฉพาะ operation การเงิน/คลินิกที่สำคัญมาก

---

### ตัวเลือก D: Incremental — เริ่มจาก endpoint ที่เสี่ยงสูง

จัดลำดับตามผลกระทบ:
```
Tier 1 (ทำก่อน): การเงิน — donation, escrow, POS, accounting, payroll
Tier 2: การแพทย์ — prescription, health data, lab results
Tier 3: ไฟล์อัปโหลด — video, image, document
Tier 4: ที่เหลือทั้งหมด
```

**ข้อดี:** เห็นผลเร็ว, ทรัพยากรน้อย
**ข้อเสีย:** ระบบไม่สม่ำเสมอระหว่างทาง
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — เป็นวิธี rollout ที่ดีของตัวเลือก A

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A + B พร้อมกัน rollout แบบ D** | Schema validation ให้ UX ดี + DB constraint เป็นตาข่ายนิรภัย; rollout ตาม tier ความเสี่ยง |
| 2 | **B ก่อน แล้ว A ตาม** | ถ้าทรัพยากรจำกัด — DB constraint ให้ ROI สูงสุดต่อบรรทัดโค้ด |
| 3 | **A + C สำหรับ operation การเงิน** | ถ้ายังยิง Supabase ตรงอยู่และไม่พร้อมทำ gateway (แผน 09) |
| 4 | **A อย่างเดียว** | ไม่พอ — client ยิง Supabase ตรงข้าม validation ได้ |

---

## 5. กฎ Validation มาตรฐานที่เสนอ (Sheserved Standard)

| ประเภทข้อมูล | กฎ |
|-------------|-----|
| Username | 3–30 ตัว, `[a-zA-Z0-9_.]`, ไม่ขึ้นต้นด้วยตัวเลข, unique |
| เบอร์โทรไทย | normalize เป็น `0XXXXXXXXX` (10 หลัก), รับ input ทั้ง `+66` และ `0` |
| Email | RFC 5322 แบบผ่อนปรน + ตรวจ MX (optional) |
| ชื่อ-นามสกุล | 1–100 ตัว, อนุญาตไทย/อังกฤษ/เว้นวรรค/`-` |
| จำนวนเงิน | `NUMERIC(15,2)`, > 0, ≤ ceiling ตาม context, ห้ามรับเป็น float |
| GPS lat/lng | lat −90..90, lng −180..180, precision 6 ตำแหน่ง |
| รัศมี (เมตร) | 100..50000 |
| ข้อความแชท | 1–5000 ตัว |
| Title | 1–200 ตัว |
| Description | ≤ 2000 ตัว |
| Rich text / บทความ | sanitize (ดูแผน 14) + ≤ 100KB |
| UUID | RFC 4122 v4 format |
| วันที่ | ISO 8601, ตรวจช่วงที่สมเหตุสมผล (เช่น วันเกิดไม่อยู่อนาคต) |
| ไฟล์รูป | ≤ 10MB, magic bytes = JPEG/PNG/WebP, ตรวจ dimension |
| ไฟล์วิดีโอ | ≤ 20MB (ปัจจุบัน), magic bytes = MP4/MOV |
| เอกสาร | ≤ 5MB, PDF magic bytes |
| Enum ทุกชนิด | allowlist ที่ประกาศไว้ในที่เดียว (shared constant) |

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด — `userId` ยังมาจาก `ServiceLocator` แต่ backend ต้อง **validate ว่าตรงกับ authenticated user** ไม่ใช่เชื่อค่าที่ส่งมา |
| `docs/infrastructure/architecture_analysis.md` | เพิ่ม validation layer ในผัง — ควรอยู่ก่อน business logic |
| `docs/infrastructure/caching_strategy.md` | Validate ก่อน cache เสมอ — ห้าม cache ผลจาก input ที่ยังไม่ validate |
| `docs/plans/ui_rendering_standards.md` | Error message ต้องตามมาตรฐาน UI ที่กำหนด |
| `docs/guides/TEST_PLAN.md` | SEC-01 (Input Validation) ครอบคลุมเรื่องนี้ — ควรขยายเป็นหลาย scenario ตาม tier |

---

## 7. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] เลือก library ฝั่ง backend: `zod` / `joi` / เขียนเอง
- [ ] อนุมัติกฎ validation มาตรฐาน (ตาราง section 5)
- [ ] ตัดสินใจว่าจะเพิ่ม DB CHECK constraints หรือไม่ (แนะนำ: ใช่)
- [ ] กำหนดลำดับ tier ที่จะทำก่อน
- [ ] กำหนดรูปแบบ error response มาตรฐาน (code + ข้อความไทย + field)
- [ ] ตัดสินใจเรื่อง magic-byte checking สำหรับไฟล์อัปโหลด
