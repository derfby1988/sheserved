# แผนป้องกัน 08: Session และ Token Security

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 09 (AuthN/AuthZ), 10 (Password), 07 (Secrets)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-B ลำดับ 1** และต้องออกแบบร่วมกับแผน 09/10/07 ก่อน rollout
> **เหตุผล:** backend ต้องมี identity ที่ตรวจลายเซ็นได้ก่อนจึงจะเลิกเชื่อ `x-user-id`, ผูก authorization และ migrate password ได้อย่างปลอดภัย; ใช้ compatibility window, token rotation, revoke และ rollback plan เพื่อไม่ตัด session ผู้ใช้ทั้งหมดพร้อมกัน

---

## 1. สถานะปัจจุบัน (As-Is)

### กลไก session ที่ใช้อยู่
```dart
// lib/services/auth_service.dart
class AuthService extends ChangeNotifier {
  UserModel? _currentUser;              // เก็บใน memory เท่านั้น
  Future<void> login(UserModel user) async { _currentUser = user; ... }
  Future<void> logout() async { _currentUser = null; ... }
}
```

```js
// websocket-server/middleware/auth.js
// identity มาจาก x-user-id header หรือ JWT payload (ไม่ verify signature)
```

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| T1 | **ไม่มี token เลย** | 🔴 วิกฤต | ไม่มีหลักฐานที่ตรวจสอบได้ว่า request มาจากผู้ที่ login จริง |
| T2 | **Session ไม่ persist** | 🔴 สูง | ปิดแอป = หลุด login (ผู้ใช้ต้อง login ใหม่ทุกครั้ง — UX แย่ และผลักดันให้ใช้รหัสง่าย ๆ) |
| T3 | **ไม่มี session expiry** | 🟡 กลาง | ตราบใดที่แอปเปิดอยู่ session ไม่มีวันหมดอายุ |
| T4 | **ไม่มี refresh token** | 🔴 สูง | ไม่มีทางออก token อายุสั้นได้ |
| T5 | **ไม่มี server-side session registry** | 🔴 สูง | เพิกถอน session (revoke) ไม่ได้ — บังคับ logout จากระยะไกลไม่ได้ |
| T6 | **JWT ไม่ verify signature** | 🔴 สูง | ดูแผน 09 G3 |
| T7 | **ไม่มี device/session management** | 🟡 กลาง | ผู้ใช้ดูไม่ได้ว่า login จากอุปกรณ์ใดบ้าง |
| T8 | **`password_hash` อยู่ใน `UserModel` ที่อยู่ใน memory** | 🟡 กลาง | ควรลบทิ้งทันทีหลัง authenticate |
| T9 | **PresenceService heartbeat ไม่ผูกกับ session validity** | 🟢 ต่ำ | อาจแสดง online ทั้งที่ session ควรหมดอายุ |
| T10 | **ไม่มี concurrent session policy** | 🟢 ต่ำ | ERP/HIS มักต้องการจำกัด 1 session ต่อผู้ใช้ |
| T11 | **Redis session helper มีอยู่แต่ไม่ได้ใช้** | 🟡 กลาง | `getSession/setSession/deleteSession` ใน `cache-aside.js` พร้อมใช้แล้ว |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ผลกระทบต่อระบบที่ implement แล้ว

| ระบบ | ผลกระทบจากช่องว่าง session |
|------|---------------------------|
| **Auth** | AUTH-05 (session persist) test ผ่านไม่ได้จริง — แอปกลับเป็น guest mode หลัง restart |
| **Consultation** | Provider ที่ทำเคสอยู่ ถ้าแอป crash = หลุด session กลางเคส; มี workaround `_fixStaleBusyStatusIfNeeded` ซึ่งเป็นอาการของปัญหานี้ |
| **Chat & Video** | Socket connection auth ใช้ `x-user-id` — reconnect หลัง network drop ไม่มีการพิสูจน์ตัวตนใหม่ |
| **Donation + Escrow** | Action การเงินไม่มี token ที่ตรวจสอบได้ = audit trail อ่อน |
| **Emergency** | SOS ต้องทำงานได้แม้ network ไม่เสถียร — ต้องออกแบบ token ที่ทนทาน |
| **Pharmacy & Drug Risk** | Override action ต้องระบุผู้กระทำได้อย่างแน่ชัด |
| **Admin** | Admin session ควรอายุสั้นกว่าและ revoke ได้ |
| **Health** | ข้อมูลสุขภาพ — session ค้างบนอุปกรณ์ที่หายเป็นความเสี่ยง |

### 2.2 ความต้องการจากแผน `docs/ERP/`

| แผน | ความต้องการเฉพาะ |
|-----|-----------------|
| `ERP_CORE_ARCHITECTURE.md` | Session ต้องเก็บ `organization_id` + `branch_id` ปัจจุบัน; สลับสาขา = re-issue token |
| `HR_SYSTEM_PLAN.md` | Payroll session ต้อง timeout สั้น (15 นาที idle) + re-auth |
| `ACCOUNTING_SYSTEM_PLAN.md` | ทุก GL transaction ต้อง trace ถึง session ID ที่ตรวจสอบได้ |
| `HIS_SYSTEM_PLAN.md` / `LAB_SYSTEM_PLAN.md` | PHI access — session timeout สั้น + auto-lock; audit ทุก session |
| `POS System_plan.md` | Cashier shift session แยกจาก user session; shift close = revoke |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Token ควรมี subscription tier claim เพื่อบังคับ feature flag |
| `KPI_DASHBOARD_PLAN.md` | Dashboard refresh ระยะยาว — ต้อง refresh token ไม่ให้หลุดกลางคัน |

### 2.3 ความต้องการจากแผน `docs/plans/`

| แผน | ความต้องการ |
|-----|------------|
| `health_data_sync_plan.md` | Background sync ต้องใช้ token ที่ยังไม่หมดอายุ → ต้องมี refresh ที่ทำงานเบื้องหลังได้ |
| `device_connection_ui_plan.md` | อุปกรณ์สวมใส่ควรมี device token แยก ไม่ใช้ user token |
| `VIDEO_SYSTEM_PLAN.md` | Upload ไฟล์ใหญ่ — token ต้องไม่หมดอายุกลางการอัปโหลด |
| `Delivery_PLAN.md` | Courier app session ระหว่างวิ่งงาน — ต้องทน network ขาด |
| `CHAT_CONSULTATION_IMPROVEMENT_PLAN.md` | Session timer ต้อง server-authoritative ผูกกับ consultation ไม่ใช่ user session |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: JWT Access Token + Opaque Refresh Token (แนะนำ) ⭐

```
POST /api/auth/login
  → access_token  (JWT, HS256/RS256, TTL 15 นาที, ไม่เก็บใน DB)
  → refresh_token (random 256-bit, TTL 30 วัน, เก็บ hash ใน DB/Redis)

Access token claims:
{
  "sub": "<user_id>",
  "role": "provider",
  "org": "<organization_id>",
  "branch": "<branch_id>",
  "perms": ["erp.inventory.read", ...],   // หรือ reference ไป permission set
  "sid": "<session_id>",                   // สำหรับ revoke
  "iat": ..., "exp": ..., "iss": "sheserved", "aud": "sheserved-app"
}

POST /api/auth/refresh  (rotate: ออก refresh ใหม่ทุกครั้ง, invalidate ตัวเก่า)
POST /api/auth/logout   (revoke session + ลบ refresh token)
GET  /api/auth/sessions (แสดงอุปกรณ์ที่ login อยู่)
DELETE /api/auth/sessions/:id (revoke จากระยะไกล)
```

**การเก็บฝั่ง client**
| Platform | Access token | Refresh token |
|----------|-------------|---------------|
| iOS | memory | Keychain (ผ่าน `flutter_secure_storage`) |
| Android | memory | EncryptedSharedPreferences |
| Web | memory | httpOnly cookie + SameSite=Strict |

**ข้อดี**
- ปิด T1–T7, T10, T11 ครบ
- Stateless verification (เร็ว) + revocable ผ่าน `sid` + refresh registry
- Token rotation ตรวจจับการนำ refresh token ไปใช้ซ้ำได้
- รองรับความต้องการ ERP ทั้งหมด (org/branch/perms ใน claims)

**ข้อเสีย**
- ต้องเพิ่ม `flutter_secure_storage` + `jsonwebtoken` (ดูแผน 06)
- ต้องมี endpoint `/api/auth/*` ใน websocket-server
- Access token ที่ออกไปแล้วเพิกถอนทันทีไม่ได้ (รอ ≤15 นาที) — แก้ได้ด้วย denylist ใน Redis
- ต้อง refactor ทุกจุดที่เรียก API ให้แนบ token + จัดการ 401 → refresh → retry

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Opaque Session Token + Redis (Server-side Session)

```
login → session_token (random 256-bit)
Redis: session:<token> → { userId, role, org, branch, expiresAt }  TTL 24h
ทุก request: lookup Redis → ถ้าไม่มี = 401
```

**ข้อดี**
- Revoke ทันที 100% (ลบ key)
- ไม่มีข้อมูลรั่วในตัว token (opaque)
- ใช้ Redis helper ที่มีอยู่แล้ว (`getSession/setSession/deleteSession`) — โครงพร้อม
- เข้าใจง่าย debug ง่าย

**ข้อเสีย**
- ทุก request ต้อง hit Redis (แต่ Redis เร็วมาก ~1ms; และมี cache layer อยู่แล้ว)
- Redis ล่ม = ทุกคนหลุด login → ต้องมี HA/persistence
- Supabase RLS ใช้ token นี้ไม่ได้ (ถ้าเลือกแผน 09 ตัวเลือก C)

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — เรียบง่ายและตรงไปตรงมา เหมาะถ้าไม่ทำ RLS-with-JWT

---

### ตัวเลือก C: Hybrid — JWT สำหรับ Supabase RLS + Redis Registry สำหรับ Revoke

ออก JWT ด้วย Supabase JWT secret (ให้ RLS อ่าน claims ได้) + เก็บ `sid` ใน Redis เพื่อ revoke

**ข้อดี:** ได้ทั้ง RLS ที่ DB และความสามารถ revoke; รองรับแผน 09 ตัวเลือก C
**ข้อเสีย:** ซับซ้อนที่สุด; ต้องจัดการ Supabase JWT secret อย่างระมัดระวัง (แผน 07); Supabase ตรวจ JWT เองไม่รู้จัก denylist ของเรา
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ทรงพลังแต่ต้องการวินัยสูง

---

### ตัวเลือก D: Persist Session แบบง่าย (Quick Win — ไม่แก้ปัญหาหลัก)

เก็บ `userId` ใน `shared_preferences` (มีใน pubspec แล้ว) แล้วโหลดตอนเปิดแอป

**ข้อดี:** แก้ T2 ได้ทันที (~1 วัน); ทำให้ AUTH-05 test ผ่าน; ไม่กระทบสถาปัตยกรรม
**ข้อเสีย:** ❗ **ไม่แก้ T1/T5/T6** และอาจทำให้แย่ลง — `userId` ใน plain SharedPreferences อ่านได้บนเครื่อง rooted/jailbroken
**ความเหมาะสมระยะยาว:** ⭐⭐ — ทำได้เฉพาะกรณีใช้ `flutter_secure_storage` และรู้ว่าเป็นมาตรการชั่วคราว

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A (JWT + refresh rotation)** | ครอบคลุมความต้องการทั้งปัจจุบันและ ERP/HIS ในอนาคต; เป็นมาตรฐานที่ทีมใหม่เข้าใจได้ |
| 2 | **B (Redis session)** | ถ้าต้องการความเรียบง่ายและ revoke ทันที; โครงสร้าง Redis พร้อมแล้ว |
| 3 | **C (Hybrid)** | ถ้าตัดสินใจทำ RLS-with-JWT ตามแผน 09 ตัวเลือก C |
| 4 | **D** | เฉพาะเป็นมาตรการชั่วคราวระหว่างรอ A/B และต้องใช้ secure storage เท่านั้น |

---

## 5. นโยบาย Session ที่เสนอ

| พารามิเตอร์ | Consumer | Provider | Admin / ERP | Clinical (HIS/LAB) |
|------------|----------|----------|-------------|-------------------|
| Access token TTL | 15 นาที | 15 นาที | 10 นาที | 5 นาที |
| Refresh token TTL | 30 วัน | 14 วัน | 7 วัน | 1 วัน |
| Idle timeout | ไม่มี | 8 ชม. | 30 นาที | 15 นาที |
| Absolute timeout | 90 วัน | 30 วัน | 7 วัน | 12 ชม. |
| Concurrent sessions | ไม่จำกัด | 3 อุปกรณ์ | 2 อุปกรณ์ | 1 อุปกรณ์ |
| Refresh rotation | ✅ | ✅ | ✅ | ✅ |
| Re-auth สำหรับ action สำคัญ | — | ✅ | ✅ | ✅ |
| Auto-lock หน้าจอ | — | — | ✅ | ✅ |

### เหตุการณ์ที่ต้อง revoke session ทั้งหมด
- เปลี่ยนรหัสผ่าน
- เปลี่ยน role / permission
- บัญชีถูกปิดใช้งาน (`is_active = false`)
- ผู้ใช้กด "ออกจากระบบทุกอุปกรณ์"
- ตรวจพบการใช้ refresh token ซ้ำ (สัญญาณ token ถูกขโมย)

---

## 6. ประเด็นเพิ่มเติมที่ต้องตัดสินใจ

### 6.1 Signing Algorithm
| ตัวเลือก | ข้อดี | ข้อเสีย |
|---------|-------|--------|
| **HS256** (symmetric) | เร็ว, ง่าย, ใช้ secret เดียว | ทุกบริการที่ verify ได้ก็ sign ได้ด้วย |
| **RS256** (asymmetric) | แยก signer/verifier; Supabase RLS verify ได้ด้วย public key | ช้ากว่า; ต้องจัดการ key pair (แผน 07) |

**คำแนะนำ:** เริ่มด้วย HS256 (บริการเดียว) → ย้ายไป RS256 เมื่อ ERP แยกเป็นหลาย service

### 6.2 Token Binding
ผูก token กับ device fingerprint / IP เพื่อลดผลกระทบถ้าถูกขโมย
- ✅ เพิ่มความปลอดภัย
- ⚠️ IP เปลี่ยนบ่อยบนมือถือ (WiFi ↔ 4G) → ควรผูกกับ device ID ไม่ใช่ IP

### 6.3 Offline Support
Sheserved มี local-only mode และ emergency features ที่ต้องทำงานแม้ออฟไลน์
- ต้องออกแบบ grace period ให้ token ที่หมดอายุยังใช้ได้กับ local operation
- Sync กลับเมื่อออนไลน์แล้วค่อย validate

---

## 7. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด — `ServiceLocator.instance.currentUser` ยังเป็นแหล่งข้อมูลเดิม เพียงแต่ข้างในมี token เพิ่ม; **ควรอัปเดต guideline** ให้ระบุว่า API call ต้องแนบ token ด้วย |
| `docs/infrastructure/caching_strategy.md` | Redis session helper มีอยู่แล้ว (`getSession/setSession/deleteSession`) — ต่อยอดได้ทันที |
| `docs/infrastructure/architecture_analysis.md` | ต้องเพิ่ม token lifecycle ในผังสถาปัตยกรรม |
| `docs/infrastructure/reverse_proxy_plan.md` | Token validation สามารถทำที่ proxy layer เพื่อลดภาระ app server |
| `docs/infrastructure/role_management_refactor_plan.md` | Permission ที่ refactor แล้วจะกลายเป็น token claims |
| `docs/guides/TEST_PLAN.md` | AUTH-05 (session persist) จะทดสอบได้จริงหลัง implement; SEC-05 (session expiry) ต้องเพิ่ม |

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] เลือกกลไก: JWT+refresh (A) / Redis session (B) / Hybrid (C)
- [ ] เลือก signing algorithm: HS256 / RS256
- [ ] อนุมัตินโยบาย TTL แต่ละ role (ตาราง section 5)
- [ ] ตัดสินใจเรื่อง concurrent session limit
- [ ] ตัดสินใจเรื่อง token binding (device ID)
- [ ] ยืนยันว่าจะเพิ่ม `flutter_secure_storage` เข้า pubspec
- [ ] ออกแบบ offline grace period สำหรับ emergency features
- [ ] ตัดสินใจว่าจะทำหน้า "จัดการอุปกรณ์ที่ login" หรือไม่
