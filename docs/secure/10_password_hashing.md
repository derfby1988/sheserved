# แผนป้องกัน 10: Password Hashing

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-B
> **เกี่ยวข้องกับแผน:** 09 (AuthN/AuthZ), 08 (Session/Token)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-B ลำดับ 3** ไม่ควรทำเป็นงานแรกแยกเดี่ยว เพราะ server-side password verification ต้องเปิดใช้พร้อม signed session และ endpoint authentication ก่อน
> **เหตุผล:** การเปลี่ยน hash โดยยังปล่อยให้ `x-user-id` เป็น identity หลักไม่ปิดช่องโหว่ authorization; ใช้ Argon2id เป็นค่าเริ่มต้น (bcrypt เป็น fallback หาก native build/deployment ไม่พร้อม) และต้องรองรับ legacy SHA-256 แบบจำกัดเวลา พร้อม rehash หลัง login สำเร็จ

---

## 1. สถานะปัจจุบัน (As-Is)

### วิธีการที่ใช้อยู่
```dart
// lib/features/auth/data/repositories/user_repository.dart:202
String _hashPassword(String password) {
  var bytes = utf8.encode(password);
  var digest = crypto.sha256.convert(bytes);
  return digest.toString();
}
```

จุดที่เรียกใช้:
- `createUser()` — บันทึก `password_hash` ตอนสมัคร
- `login()` — hash แล้วเทียบกับค่าใน DB
- Local API mode — ส่ง `passwordHash` ไปยัง `/api/users`

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| P1 | **ไม่มี salt** | 🔴 วิกฤต | รหัสผ่านเดียวกัน → hash เดียวกันทุกบัญชี; rainbow table ใช้ได้ทันที |
| P2 | **SHA-256 เร็วเกินไป** | 🔴 วิกฤต | ออกแบบมาเพื่อความเร็ว ไม่ใช่ password hashing; GPU คำนวณได้พันล้าน hash/วินาที |
| P3 | **Hash ฝั่ง client** | 🔴 สูง | hash ที่ส่งไปกลายเป็น "รหัสผ่านจริง" — ใครได้ hash จาก DB ก็ login ได้โดยไม่ต้อง crack |
| P4 | **ไม่มี work factor ปรับได้** | 🟡 กลาง | ไม่สามารถเพิ่มความยากตามฮาร์ดแวร์ที่พัฒนาขึ้น |
| P5 | **ไม่มี password policy** | 🟡 กลาง | ไม่บังคับความยาว/ความซับซ้อน (test account ใช้ `123456`) |
| P6 | **ไม่มี password history / rotation** | 🟢 ต่ำ | ERP/HIS อาจต้องการตามมาตรฐาน |
| P7 | **`password_hash` อยู่ใน `UserModel`** | 🟡 กลาง | field หลุดไปถึงชั้น presentation ได้ |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 จุดที่แตะรหัสผ่านในระบบปัจจุบัน

| ระบบ | จุดที่เกี่ยวข้อง | ไฟล์ |
|------|-----------------|------|
| Login | `UserRepository.login()` | `user_repository.dart:140` |
| Register wizard | `createUser()` ผ่าน `RegistrationRepository` | `registration_repository.dart` |
| Register simple | `createUser()` | `login_page.dart` / register pages |
| Social login | ไม่มี password (`social_provider` + `social_id`) | `social_auth_service.dart` |
| Local API mode | ส่ง `passwordHash` เป็น plain field ใน JSON body | `user_repository.dart:61` |
| Profile — เปลี่ยนรหัสผ่าน | ยังไม่มี feature นี้ | — |
| Reset password | ยังไม่มี feature นี้ | — |

### 2.2 ผลกระทบต่อระบบตามแผน

| แผน | ความเกี่ยวข้อง |
|-----|---------------|
| `docs/ERP/HR_SYSTEM_PLAN.md` | Employee login เข้า ERP ใช้ credential เดียวกัน → payroll เสี่ยงตาม |
| `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` | GL posting ต้องพิสูจน์ตัวตนที่เชื่อถือได้ |
| `docs/ERP/HIS_SYSTEM_PLAN.md` / `LAB_SYSTEM_PLAN.md` | PHI access ต้องผ่านมาตรฐาน authentication ที่แข็งแรง |
| `docs/ERP/POS System_plan.md` | Cashier PIN (ถ้ามี) ต้องใช้ hashing แยกจาก password หลัก |
| `docs/plans/Delivery_PLAN.md` | Courier account ใหม่ — ควรเริ่มด้วย scheme ที่ถูกต้องตั้งแต่แรก |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: bcrypt ฝั่ง Server (แนะนำ) ⭐

```
Flutter → POST /api/auth/login { username, password }  (ผ่าน TLS)
                    ↓
websocket-server:  bcrypt.compare(password, row.password_hash)
                    ↓
              ออก JWT (แผน 08)
```

**Spec ที่เสนอ**
- Algorithm: `bcrypt` cost factor **12** (ปรับเพิ่มได้ตามเวลา)
- Library: `bcrypt` (native) หรือ `bcryptjs` (pure JS, ช้ากว่า) บน Node.js
- Password ถูกส่งเป็น plaintext ผ่าน TLS เท่านั้น (มาตรฐานสากล) — **ห้าม hash ฝั่ง client**
- Column: `password_hash VARCHAR(60)` (bcrypt output = 60 ตัวอักษร)

**ข้อดี**
- ปิด P1–P4 ทั้งหมด
- bcrypt ผ่านการพิสูจน์มายาวนาน, library เสถียร, ทีมงานคุ้นเคย
- ทำงานได้กับทั้ง Supabase mode และ local-only mode

**ข้อเสีย**
- ต้องมี backend endpoint สำหรับ login (ปัจจุบันแอปยิง Supabase ตรง)
- ต้อง migrate hash เดิม
- cost 12 ใช้ CPU ~250ms/ครั้ง → ต้องมี rate limit (มีแล้ว ✅)

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Argon2id ฝั่ง Server

**Spec ที่เสนอ**
- Algorithm: `argon2id`, memory 64MB, iterations 3, parallelism 4
- Library: `argon2` (Node.js native binding)

**ข้อดี**
- ผู้ชนะ Password Hashing Competition; ต้านทาน GPU/ASIC ดีกว่า bcrypt
- ปรับ memory cost ได้ (bcrypt ปรับได้แค่ time cost)
- เป็นคำแนะนำอันดับ 1 ของ OWASP ปัจจุบัน

**ข้อเสีย**
- ต้องคอมไพล์ native module → ยุ่งยากบน Docker/deploy บางสภาพแวดล้อม
- ใช้ RAM มาก (64MB × concurrent logins) — ต้องคำนวณ capacity
- ทีมอาจไม่คุ้นเคยเท่า bcrypt

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ (ถ้ายอมรับความยุ่งยากของ native build)

---

### ตัวเลือก C: PostgreSQL `pgcrypto` (hash ในฐานข้อมูล)

```sql
-- สมัคร
INSERT INTO users (..., password_hash)
VALUES (..., crypt($1, gen_salt('bf', 12)));

-- ตรวจสอบ
SELECT id FROM users
WHERE username = $1 AND password_hash = crypt($2, password_hash);
```

**ข้อดี**
- ไม่ต้องมี backend endpoint ใหม่ — เรียกผ่าน Supabase RPC (`SECURITY DEFINER` function) ได้
- ลด refactor ฝั่งแอปมาก
- salt + bcrypt ครบในตัว

**ข้อเสีย**
- Password plaintext ผ่าน SQL parameter → อาจติดใน DB query log ถ้าตั้งค่าผิด
- ใช้ CPU ของ DB server (ซึ่ง scale ยากกว่า app server)
- ผูกติดกับ PostgreSQL (ระบบยังมี local API mode ที่ควรทำงานสอดคล้องกัน)

**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — เป็นทางลัดที่ดีถ้าอยากได้ผลเร็ว

---

### ตัวเลือก D: Supabase Auth จัดการให้

**ข้อดี:** ไม่ต้องเขียน password logic เอง; ได้ reset password / email verify / MFA ฟรี
**ข้อเสีย:** ขัด `auth_data_guidelines.md` (ดูแผน 09 ตัวเลือก B); local-only mode ใช้ไม่ได้
**ความเหมาะสมระยะยาว:** ⭐⭐

---

## 4. แผน Migration (ใช้ได้กับตัวเลือก A / B / C)

### กลยุทธ์ที่ 1: Lazy Migration (แนะนำ) ⭐
```
เพิ่ม column: password_algo VARCHAR(20) DEFAULT 'sha256'

ตอน login:
  if password_algo == 'sha256':
      ตรวจด้วย sha256(input) == password_hash
      ถ้าถูก → hash ใหม่ด้วย bcrypt → UPDATE password_hash, password_algo='bcrypt'
  else:
      bcrypt.compare(input, password_hash)
```
- ✅ ผู้ใช้ไม่รู้สึกถึงการเปลี่ยนแปลง, ไม่ต้อง reset password
- ⚠️ ต้องคง code path เก่าไว้ระยะหนึ่ง (แนะนำ 6–12 เดือน) แล้วบังคับ reset ที่เหลือ

### กลยุทธ์ที่ 2: Double Hashing (ทันทีทั้งหมด)
```
password_hash_new = bcrypt(existing_sha256_hash)
ตอน login: bcrypt.compare(sha256(input), password_hash_new)
```
- ✅ ปิดช่องว่างทันทีทุกบัญชี ไม่ต้องรอ user login
- ⚠️ ยังคงคุณสมบัติ "ไม่มี salt" ของชั้นใน; ต้องวางแผนย้ายไป pure bcrypt อีกรอบ

### กลยุทธ์ที่ 3: Force Reset ทุกบัญชี
- ✅ สะอาดที่สุด
- ⚠️ กระทบผู้ใช้ทุกคน; ต้องมีช่องทาง reset ที่ใช้งานได้ (ปัจจุบัน**ยังไม่มี**)

**คำแนะนำ:** กลยุทธ์ 2 → 1 ผสมกัน — double hashing ทันทีเพื่อปิดความเสี่ยงเฉพาะหน้า แล้วค่อย lazy migrate เป็น pure bcrypt เมื่อผู้ใช้ login ครั้งถัดไป

---

## 5. Password Policy ที่เสนอ

| ข้อกำหนด | ผู้ใช้ทั่วไป (consumer) | Provider | Admin / ERP |
|---------|------------------------|----------|-------------|
| ความยาวขั้นต่ำ | 8 | 10 | 12 |
| ตรวจ common password list | ✅ | ✅ | ✅ |
| ห้ามใช้ username/phone ในรหัส | ✅ | ✅ | ✅ |
| บังคับตัวพิมพ์ใหญ่/เล็ก/ตัวเลข | ❌ (ใช้ความยาวแทน ตาม NIST) | ❌ | ✅ |
| Password history | ❌ | 3 รายการ | 5 รายการ |
| บังคับเปลี่ยนตามรอบ | ❌ (NIST ไม่แนะนำ) | ❌ | 180 วัน (ถ้ามาตรฐานบังคับ) |
| MFA | optional | optional | **บังคับ** (ดูแผน 09) |

> **หมายเหตุ:** ตาม NIST SP 800-63B การบังคับเปลี่ยนรหัสตามรอบและกฎความซับซ้อนที่เข้มงวดเกินไปมักลดความปลอดภัยลง แนะนำเน้น **ความยาว + ตรวจ breach list** แทน

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ตัวเลือก A/B/C ไม่ขัด (ยังคง custom AuthService) |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | ต้องเพิ่มขั้นตอน `CREATE EXTENSION pgcrypto` ถ้าเลือก C |
| `docs/infrastructure/architecture_analysis.md` | ตัวเลือก A/B เพิ่ม auth endpoint ใน websocket-server |
| `docs/guides/TEST_PLAN.md` | Test account `123456` จะใช้ไม่ได้ถ้าบังคับ policy → ต้องอัปเดต SEC-04 และ test accounts |

---

## 7. สิ่งที่ต้องเพิ่มควบคู่ (Feature Gaps)

- [ ] หน้า "เปลี่ยนรหัสผ่าน" ใน Profile (ยังไม่มี)
- [ ] Flow "ลืมรหัสผ่าน" ผ่าน OTP (มี OTP service แล้ว — ต่อยอดได้)
- [ ] เอา `passwordHash` ออกจาก `UserModel` ที่ส่งไปชั้น UI
- [ ] Rate limit + lockout ต่อ username (ดูแผน 09 G5)

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] เลือก algorithm: bcrypt (A) / Argon2id (B) / pgcrypto (C)
- [ ] เลือกกลยุทธ์ migration: lazy / double-hash / force-reset
- [ ] อนุมัติ password policy แต่ละ role
- [ ] ยืนยันว่าจะสร้าง `/api/auth/login` endpoint หรือใช้ Supabase RPC
- [ ] กำหนด timeline ปิด code path SHA-256 เดิม
