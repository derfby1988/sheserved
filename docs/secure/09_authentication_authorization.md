# แผนป้องกัน 09: Authentication และ Authorization

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 10 (Password), 08 (Session/Token), 07 (Secrets), 12 (Least Privilege)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-B ลำดับ 2** หลังแผน 08 และทำคู่กับแผน 10/11 แบบ compatibility window เนื่องจาก backend ปัจจุบันยังเชื่อ `x-user-id` ที่ปลอมได้ การแก้ UI guard อย่างเดียวไม่ใช่มาตรการรักษาความปลอดภัย
> **เหตุผล:** ต้องมี signed identity ก่อนจึงจะบังคับ ownership, role และ RLS ได้อย่างถูกต้อง; ห้ามตัดสินใจใช้ `Supabase.instance.client.auth.currentUser` เพราะขัดกับ custom AuthService และ `auth_data_guidelines.md`

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ implement แล้ว ✅
| องค์ประกอบ | รายละเอียด | ไฟล์ |
|-----------|------------|------|
| Custom AuthService | Singleton เก็บ `currentUser` ใน memory, มี `isAdmin`/`isProvider` getters | `lib/services/auth_service.dart` |
| Login flow | username/phone + password → query ตาราง `users` | `lib/features/auth/data/repositories/user_repository.dart` |
| AuthGuardWidget | Route-level guard ตรวจ login + role (admin/provider/consumer) แสดงหน้า 403 | `lib/core/guards/auth_guard_widget.dart` |
| Backend middleware | `verifyToken(pool)`, `requireRole`, `requireAuth` — ตรวจ user กับ DB | `websocket-server/middleware/auth.js` |
| Socket.IO auth | Connection-level auth ตรวจ user กับ DB ก่อนรับ events | `websocket-server/server.js` |
| Role source of truth | `user_categories` attributes (`is_consumer`, `is_provider`) + sync trigger | migrations + `UserModel` |
| Rate limiting | `authRateLimiter` / `strictRateLimiter` บน route สำคัญ | `websocket-server/middleware/rate-limiter.js` |
| OTP | OTP dialog + service สำหรับ phone verification | `lib/shared/widgets/otp_verification_dialog.dart` |

### ช่องว่างที่ต้องปิด (Gaps)
| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| G1 | Authorization บังคับใช้ที่ client เป็นหลัก | 🔴 วิกฤต | `AuthGuardWidget` คุมเฉพาะการแสดงผล UI ยังไม่มีชั้นบังคับที่ฝั่ง server/ฐานข้อมูลครบทุกตาราง |
| G2 | Identity ฝั่ง backend อ้างอิง header ที่ไม่ได้ลงลายเซ็น | 🔴 วิกฤต | `x-user-id` เป็นค่าที่ client กำหนดเอง แม้จะเช็คว่ามีใน DB แต่ยังไม่พิสูจน์ว่า "เป็นเจ้าของบัญชีจริง" |
| G3 | JWT ยังไม่ตรวจ signature | 🔴 สูง | `_extractUserId` decode payload อย่างเดียว (มี TODO กำกับในโค้ดแล้ว) |
| G4 | ไม่มีชั้น token/refresh | 🔴 สูง | ดูรายละเอียดในแผน 08 |
| G5 | ไม่มี account lockout / brute-force protection ระดับบัญชี | 🟡 กลาง | มี rate limit ระดับ IP แต่ไม่มี counter ต่อ username |
| G6 | ไม่มี audit log การ login/permission change | 🟡 กลาง | ERP/HIS/LAB ต้องการ audit trail ตามมาตรฐาน |
| G7 | Social login (Google/Facebook/Apple) ยังไม่ verify id_token ฝั่ง server | 🟡 กลาง | `SocialAuthService` เชื่อผลลัพธ์จาก SDK ฝั่ง client |
| G8 | ไม่มี MFA สำหรับ admin / ERP | 🟡 กลาง | บัญชี admin เข้าถึง ERP Finance/HR ได้ทั้งหมด |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | จุดที่ต้องมี AuthN/AuthZ | สถานะ | สิ่งที่ต้องเพิ่ม |
|------|--------------------------|-------|-----------------|
| **Auth & Registration** | login, register, OTP, social login | บางส่วน | server-side token issuance, verify social id_token, account lockout |
| **Home & Navigation** | guest mode vs logged-in, bottom nav redirect | ✅ | — (แต่ redirect logic ควรรวมศูนย์) |
| **Consultation & ChartBoard** | provider เท่านั้นเข้า dashboard, เจ้าของ consultation เท่านั้นเข้า chartboard | client-only | RLS บน `consultation_requests`, `consultation_messages` |
| **Chat & Video Call** | participant เท่านั้นอ่าน/เขียนห้อง | client-only | RLS บน `chat_rooms`, `chat_messages`, `chat_participants` + socket room authorization |
| **Pharmacy & Drug Risk** | `can_manage_drug_risk` permission, org-scoped override | มี permission model ✅ | บังคับที่ DB (RLS) ไม่ใช่แค่ UI |
| **Donation + Escrow** | leader verification, admin approval, escrow release | บางส่วน (server routes) | ทุก endpoint การเงินต้อง `requireRole` + audit log |
| **Emergency & Rescue** | SOS ต้อง login, ผู้รับแจ้งต้องเป็น volunteer/responder | บางส่วน | validate `is_volunteer` ฝั่ง server ก่อน broadcast |
| **Health & Articles** | health data เป็นข้อมูลอ่อนไหว, permission model แยก | มี `HealthDataPermissionRepository` | RLS + explicit consent record |
| **Profile & Settings** | แก้ไขได้เฉพาะโปรไฟล์ตนเอง | client-only | RLS `auth.uid() = id` หรือ equivalent |
| **Admin & KPI** | admin only | client guard ✅ + `requireRole('admin')` บาง route | ครบทุก admin endpoint + MFA |

### 2.2 ระบบตามแผน `docs/plans/`

| แผน | ประเด็น AuthN/AuthZ ที่ต้องออกแบบล่วงหน้า |
|-----|------------------------------------------|
| `CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` | quick replies / note editor ต้องผูกกับ provider เจ้าของเคส; session timer ต้อง server-authoritative |
| `DONATION_SYSTEM_PLAN.md` | beneficiary verification, fee handling — ต้องแยก role `donation_admin` ไม่ใช้ `admin` รวม |
| `DRUG_RISK_OVERRIDE_PLAN.md` | 3 ระดับ override (personal / organization / system) — ต้อง map เป็น permission ที่บังคับใน DB |
| `Delivery_PLAN.md` | courier role ใหม่ + การเข้าถึงที่อยู่ลูกค้าแบบจำกัดเวลา |
| `SHOPPING_CART_PLAN.md` | cart ownership, guest cart merge เมื่อ login |
| `VIDEO_SYSTEM_PLAN.md` | unblurred video เฉพาะ `unblurred_profession_ids`; watermark admin config |
| `health_data_sync_plan.md` | device sync token แยกจาก user session |
| `device_connection_ui_plan.md` | pairing token, ห้ามใช้ user token ตรง |

### 2.3 ระบบตามแผน `docs/ERP/`

| แผน | ประเด็นเฉพาะ |
|-----|-------------|
| `ERP_CORE_ARCHITECTURE.md` | multi-tenant (organization_id) — ทุก query ต้อง scope ด้วย org; branch switching ต้อง re-authorize |
| `HR_SYSTEM_PLAN.md` | payroll = ข้อมูลอ่อนไหวสูงสุด; ต้อง permission แยก `hr.payroll.read/write` + MFA |
| `ACCOUNTING_SYSTEM_PLAN.md` | GL entries ต้อง immutable + approval workflow; segregation of duties |
| `PROCUREMENT_SYSTEM_PLAN.md` | PO approval limit ตามวงเงิน (amount-based authorization) |
| `POS System_plan.md` | cashier session, refund ต้อง supervisor override |
| `INVENTORY_SYSTEM_PLAN.md` | stock adjustment ต้อง approval; transfer ระหว่างสาขาต้องสิทธิ์ทั้งสองฝั่ง |
| `HIS_SYSTEM_PLAN.md` / `LAB_SYSTEM_PLAN.md` | patient data = PHI; ต้อง break-glass access + audit ทุกครั้งที่อ่าน |
| `CRM_SYSTEM_PLAN.md` | customer PII scope ตาม sales territory |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | feature flag ตาม subscription tier ต้องบังคับฝั่ง server |
| `KPI_DASHBOARD_PLAN.md` | KPI ข้ามแผนกต้อง aggregate-only ไม่เปิด row-level |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Server-issued JWT + Backend Gateway (แนะนำ) ⭐

```
Flutter App
   │  POST /api/auth/login (username, password)
   ▼
websocket-server (Express)
   │  1. bcrypt.compare
   │  2. sign JWT (HS256/RS256) + refresh token
   ▼
Flutter เก็บ access token (memory) + refresh token (secure storage)
   │  ทุก request แนบ Authorization: Bearer <jwt>
   ▼
Backend verify signature → req.user → requireRole → query DB
   │
   └─ Supabase: ใช้ผ่าน backend เท่านั้น (service_role key อยู่ฝั่ง server)
```

**ข้อดี**
- ปิด G1, G2, G3 พร้อมกันในสถาปัตยกรรมเดียว
- Secret ไม่หลุดไปฝั่ง client (สอดคล้องแผน 07)
- ควบคุม authorization ที่จุดเดียว ขยายไป ERP ได้ตรงไปตรงมา
- ไม่ขัดกับ `auth_data_guidelines.md` เพราะยังไม่ใช้ Supabase Auth

**ข้อเสีย**
- ต้อง refactor ทุก repository ที่ยิง Supabase ตรง (~40+ repositories)
- เพิ่ม latency 1 hop; backend กลายเป็น single point of failure
- งานใหญ่: ประเมิน 6–10 สัปดาห์

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — เป็นทิศทางที่ ERP/HIS/Accounting ต้องการอยู่แล้ว

---

### ตัวเลือก B: Supabase Auth + RLS เต็มรูปแบบ

ย้ายไปใช้ Supabase Auth (`auth.users`) แล้วเขียน RLS policy ทุกตารางโดยใช้ `auth.uid()`

**ข้อดี**
- Supabase จัดการ password hashing, session, refresh, MFA ให้ครบ
- RLS ทำงานที่ระดับ DB — ปิด G1 อย่างสมบูรณ์
- ลดโค้ด auth ที่ต้องดูแลเอง

**ข้อเสีย**
- **ขัดกับ `auth_data_guidelines.md` โดยตรง** — ต้องแก้ไข guideline และ refactor ทุกจุดที่ใช้ `ServiceLocator.instance.currentUser`
- ต้อง migrate ผู้ใช้เดิม (SHA-256 hash ย้ายเข้า Supabase Auth ไม่ได้ตรง ๆ → ต้องบังคับ reset password)
- Local-only mode / UnifiedRepository ใช้ Supabase Auth ไม่ได้ → ขัดกับ `docs/infrastructure/architecture_analysis.md`
- ERP local PostgreSQL ยังต้องมี auth แยกอยู่ดี

**ความเหมาะสมระยะยาว:** ⭐⭐ — ขัดสถาปัตยกรรม hybrid local/cloud ที่วางไว้

---

### ตัวเลือก C: Hybrid — Custom JWT + Supabase RLS ผ่าน Custom Claims

ออก JWT เองด้วย Supabase JWT secret แล้วให้ Supabase RLS อ่าน claims ได้

```sql
-- RLS policy อ่าน custom claim
CREATE POLICY user_owns_row ON profiles
  USING (id = (auth.jwt() ->> 'sub')::uuid);
```

**ข้อดี**
- Client ยิง Supabase ตรงได้ต่อไป (ไม่ต้อง refactor repository ทั้งหมด)
- ได้ RLS ระดับ DB — ปิด G1
- ยังคง custom AuthService ตาม guideline

**ข้อเสีย**
- ต้องเก็บ Supabase JWT secret ฝั่ง server (แผน 07)
- RLS policy ต้องเขียนครบทุกตาราง (~80+ ตาราง) — งานมาก และผิดพลาดง่าย
- Debug ยากเมื่อ policy ซับซ้อน (org + branch + role + ownership)

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ทางสายกลางที่ดี ถ้าไม่พร้อมทำตัวเลือก A ทั้งหมด

---

### ตัวเลือก D: Incremental Hardening (ทำทันทีได้ ต้นทุนต่ำ)

ไม่เปลี่ยนสถาปัตยกรรม แต่ปิดช่องว่างเร่งด่วนก่อน

1. เพิ่ม `jsonwebtoken` และ verify signature จริงใน `middleware/auth.js` (ปิด G3)
2. เพิ่ม HMAC request signing ระหว่างแอปกับ backend (ลด G2)
3. เพิ่ม account lockout table + counter (ปิด G5)
4. เพิ่ม `auth_audit_log` table (ปิด G6)
5. เปิด RLS เฉพาะตารางอ่อนไหวสูง 10 ตารางแรก (health, chat, consultation, payroll, gl_entries)

**ข้อดี:** ทำได้ใน 1–2 สัปดาห์, ไม่กระทบ feature อื่น
**ข้อเสีย:** ไม่ปิด G1/G2 อย่างสมบูรณ์ — เป็นการซื้อเวลา
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — ควรทำเป็น Phase 0 ควบคู่กับการตัดสินใจตัวเลือกหลัก

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **D → C → A** (แบบขั้นบันได) | เริ่มปิดช่องว่างเร่งด่วนทันที (D), เพิ่ม RLS เป็นชั้นป้องกันที่ DB (C), แล้วค่อยย้ายไป gateway เมื่อ ERP โตพอ (A) |
| 2 | **D → A ตรง** | ถ้าตัดสินใจว่า ERP จะเป็นแกนหลัก การมี backend gateway ตั้งแต่แรกจะประหยัดกว่าในระยะยาว |
| 3 | **C อย่างเดียว** | ถ้าทรัพยากรจำกัดและ ERP ยังไม่เร่ง |
| 4 | **B** | ไม่แนะนำ — ขัด guideline และสถาปัตยกรรม hybrid |

---

## 5. Authorization Model ที่เสนอ (ใช้ร่วมทุกตัวเลือก)

```
User
 ├─ role: consumer | provider | admin           (coarse-grained, มีอยู่แล้ว)
 ├─ organization_id                             (multi-tenant scope, ERP)
 ├─ branch_ids[]                                (branch scope, ERP)
 └─ permissions[]                               (fine-grained)
      เช่น  erp.inventory.read
            erp.inventory.adjust
            erp.hr.payroll.read
            erp.finance.gl.post
            clinical.emr.read
            drug_risk.override.organization
            donation.escrow.release
```

**กฎการตรวจสอบ (ทุกชั้น):**
```
1. Authenticated?           → 401
2. Tenant match?            → 404 (ไม่บอกว่ามีอยู่จริง)
3. Role/permission?         → 403
4. Resource ownership?      → 403
5. Amount/limit threshold?  → 403 + require approval
6. Log ทุก decision ที่เป็น deny และทุก sensitive read
```

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ | การจัดการ |
|--------|---------|-----------|
| `.agent/workflows/auth_data_guidelines.md` | ตัวเลือก A, C, D ✅ ไม่ขัด · ตัวเลือก B ❌ ขัดโดยตรง | ถ้าเลือก B ต้อง rewrite guideline ทั้งฉบับ |
| `docs/infrastructure/architecture_analysis.md` | ตัวเลือก A ต้องเพิ่ม gateway layer ในผัง | อัปเดตผังเมื่ออนุมัติ |
| `docs/infrastructure/role_management_refactor_plan.md` | สอดคล้อง — Phase 3 ของแผนนั้นคือ permission granularity | ต่อยอดตรง ไม่ต้องแก้ |
| `docs/infrastructure/reverse_proxy_plan.md` | ตัวเลือก A เข้ากันดี — proxy เป็นจุดวาง auth gateway | ระบุเป็น prerequisite |
| `docs/infrastructure/caching_strategy.md` | ต้องระวัง cache ข้าม tenant/user | เพิ่ม cache key prefix ด้วย user/org |

---

## 7. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] เลือกตัวเลือกหลัก (A / B / C / D หรือ combination)
- [ ] ยืนยันว่าจะคง custom AuthService หรือย้าย Supabase Auth
- [ ] กำหนด permission taxonomy ฉบับสมบูรณ์ (ร่วมกับแผน 12)
- [ ] ตัดสินใจเรื่อง MFA สำหรับ admin/ERP (บังคับ / optional / ไม่ทำ)
- [ ] กำหนด audit log retention policy
- [ ] วางแผน migration สำหรับผู้ใช้เดิม (ร่วมกับแผน 10)
