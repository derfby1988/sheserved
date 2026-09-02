# แผนออกแบบ UI เปลี่ยนรหัสผ่าน

## 1. เป้าหมาย

เพิ่มเมนูและแบบฟอร์มสำหรับเปลี่ยนรหัสผ่านภายในแท็บโปรไฟล์เดิมของผู้ใช้งานทั่วไป โดยไม่สร้าง `ChangePasswordPage` และไม่เพิ่มแท็บใหม่

เส้นทางการใช้งาน:

```text
Profile tab
→ ความปลอดภัยของบัญชี
→ เปลี่ยนรหัสผ่าน
→ Bottom Sheet แบบฟอร์มเปลี่ยนรหัสผ่าน
```

## 2. ตำแหน่งเมนูใน Profile

เพิ่ม section ต่อจากข้อมูลส่วนตัว/ข้อมูลพื้นฐาน และก่อนฟิลด์ข้อมูลเพิ่มเติมใน `ProfilePage`:

```text
ข้อมูลส่วนตัว
[รูปโปรไฟล์]
ชื่อ
เบอร์โทรศัพท์
...

ความปลอดภัยของบัญชี
[กุญแจ] เปลี่ยนรหัสผ่าน                         >
เปลี่ยนรหัสผ่านเพื่อรักษาความปลอดภัยของบัญชี
```

ไฟล์หลัก:

```text
lib/features/profile/presentation/pages/profile_page.dart
```

ไม่เพิ่ม `ProfileTab` ใหม่ และไม่เพิ่ม route ใหม่

## 3. รูปแบบฟอร์ม

เมื่อกดเมนู ให้เปิด `showModalBottomSheet` ภายใน `ProfilePage` โดยใช้ `isScrollControlled: true` เพื่อรองรับ keyboard และหน้าจอขนาดเล็ก

**การตั้งค่าเพิ่มเติมของ `showModalBottomSheet` (แก้ช่องว่าง R3):**
- ครอบ content ด้วย `Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom))` เพื่อกันปุ่ม submit ถูก keyboard บัง (`isScrollControlled: true` อย่างเดียวไม่พอ)
- ระหว่าง `_isChangingPassword == true` ตั้ง `isDismissible: false` และ `enableDrag: false` (ต้องใช้ `StatefulBuilder`/`setState` ของ sheet เอง controll ค่านี้ dynamic) เพื่อกันผู้ใช้ปัดปิด sheet กลาง request แล้วเกิด state ค้าง

### สถานะเริ่มต้น: ไม่เปิดการมองเห็นรหัสผ่าน

```text
เปลี่ยนรหัสผ่าน

รหัสผ่านปัจจุบัน
[ รหัสผ่านปัจจุบัน                 👁 ]

รหัสผ่านใหม่
[ รหัสผ่านใหม่                     👁 ]

ยืนยันรหัสผ่านใหม่
[ ยืนยันรหัสผ่านใหม่               👁 ]

รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร

[ยกเลิก]              [เปลี่ยนรหัสผ่าน]
```

ค่าเริ่มต้นต้องซ่อนรหัสผ่านทั้งหมด (`obscureText: true`)

## 4. พฤติกรรมการเปิดการมองเห็น

### 4.0 Semantics ของไอคอนแต่ละช่อง (แก้ช่องว่าง R3)

มี eye icon ทั้ง 3 ช่องแต่ทำหน้าที่ต่างกัน ต้องระบุให้ชัดเพื่อไม่ให้ทีม implement เข้าใจผิดว่าทุกไอคอนควบคุม mode เดียวกัน:

| ช่อง | ไอคอนควบคุมอะไร | ผลกระทบ |
|---|---|---|
| `รหัสผ่านปัจจุบัน` | เฉพาะการแสดง/ซ่อนค่าของช่องตัวเอง (`obscureText` ของ field นี้เท่านั้น) | ไม่กระทบ mode อื่น |
| `รหัสผ่านใหม่` | **ตัวควบคุม global mode** (`_isPasswordVisibleMode`) | เปิด → ซ่อนช่อง `ยืนยัน` ทั้งช่อง (ดูหัวข้อ "เมื่อเปิดการมองเห็น" ด้านล่าง); ปิด → แสดงช่อง `ยืนยัน` กลับมา |
| `ยืนยันรหัสผ่านใหม่` | เฉพาะการแสดง/ซ่อนค่าของช่องตัวเอง | มีผลเฉพาะตอนช่อง `ยืนยัน` แสดงอยู่ (global mode = ปิด) |

ใช้ไอคอนแสดง/ซ่อนที่ช่อง `รหัสผ่านใหม่` เป็นตัวควบคุมหลักของ global mode ตามตารางข้างบน

### เมื่อไม่เปิดการมองเห็น

- แสดงช่อง `ยืนยันรหัสผ่านใหม่`
- บังคับกรอกรหัสผ่านใหม่ซ้ำ
- ตรวจว่ารหัสผ่านใหม่และค่าซ้ำตรงกัน

### เมื่อเปิดการมองเห็น

- แสดงค่ารหัสผ่านใหม่
- ซ่อนช่อง `ยืนยันรหัสผ่านใหม่`
- ไม่บังคับกรอกช่องยืนยัน
- ใช้ค่าจากช่อง `รหัสผ่านใหม่` เป็นค่าหลักในการ submit
- แสดงข้อความช่วยเหลือว่า `เปิดการมองเห็นแล้ว ไม่ต้องกรอกรหัสผ่านซ้ำ`

### เมื่อเปิด/ปิดสลับไปมา

- ห้ามล้างค่าที่ผู้ใช้กรอกไว้ในช่องยืนยันโดยอัตโนมัติ
- เก็บค่า `confirmPassword` ไว้ใน state ขณะซ่อนช่อง
- เมื่อปิดการมองเห็นและแสดงช่องยืนยันอีกครั้ง ให้ตรวจความตรงกันใหม่
- หากผู้ใช้เปิดการมองเห็นตั้งแต่เริ่มต้น ไม่ต้องสร้าง validation ของช่องยืนยัน

## 5. Validation

### 5.1 Password policy กลาง (แก้ช่องว่าง C2)

ปัจจุบัน `register_page.dart:668-669` และ `register_wizard_page.dart:1606-1608` ตรวจความยาวขั้นต่ำ **6** ตัวอักษร ในขณะที่แผนเดิมของหน้านี้กำหนด **8** ตัวอักษร — ค่าที่ไม่ตรงกันจะทำให้ผู้ใช้ที่ตั้งรหัส 6-7 ตัวอักษรไว้ตอน register สับสนตอนเปลี่ยนรหัสผ่าน

**ตัดสินใจ:** สร้างค่ากลางไว้ที่เดียวและใช้ร่วมกันทั้ง register และ change-password

```dart
// lib/core/constants/password_policy.dart
class PasswordPolicy {
  static const int minLength = 8;
  static String get minLengthMessage =>
      'รหัสผ่านต้องมีอย่างน้อย $minLength ตัวอักษร';
}
```

- Change-password ใช้ `PasswordPolicy.minLength` ทันที (เป็นฟีเจอร์ใหม่ ไม่ต้อง backward-compat)
- Register page/register wizard: อัปเดตให้ใช้ `PasswordPolicy.minLength` เดียวกัน (แก้ `< 6` → `< PasswordPolicy.minLength` ในทั้งสองไฟล์) เพื่อไม่ให้เกิดรหัสผ่านสองมาตรฐานอยู่ในระบบเดียวกัน
- ผู้ใช้เดิมที่ตั้งรหัสผ่านไว้สั้นกว่า 8 ตัวอักษรก่อนเปลี่ยนนโยบาย **ยัง login ได้ปกติ** (ไม่บังคับ reset จากเหตุผลความยาว) — นโยบายนี้บังคับเฉพาะเมื่อ "ตั้งรหัสผ่านใหม่" เท่านั้น
- Phase 13.2 (server-side auth) ต้องใช้ `PasswordPolicy.minLength` เดียวกันนี้ เพื่อไม่ให้ client/server policy เพี้ยนกัน

ตรวจทุกครั้งก่อน submit:

- ต้องมีผู้ใช้ที่ login อยู่
- รหัสผ่านปัจจุบันต้องไม่ว่าง
- รหัสผ่านใหม่ต้องไม่ว่าง
- รหัสผ่านใหม่ต้องมีความยาว ≥ `PasswordPolicy.minLength`
- รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน

ตรวจเพิ่มเฉพาะเมื่อไม่ได้เปิดการมองเห็น:

- ช่องยืนยันรหัสผ่านต้องไม่ว่าง
- รหัสผ่านใหม่และรหัสยืนยันต้องตรงกัน

ข้อความ validation:

```text
กรุณากรอกรหัสผ่านปัจจุบัน
กรุณากรอกรหัสผ่านใหม่
รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร  (PasswordPolicy.minLengthMessage)
รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม
กรุณายืนยันรหัสผ่านใหม่
รหัสผ่านใหม่และการยืนยันไม่ตรงกัน
```

## 6. Repository และการบันทึกข้อมูล

ปัจจุบันมี `UserRepository.updatePassword(id, newPassword)` (`user_repository.dart:217-231`) แต่:
- ไม่ตรวจรหัสผ่านเดิม
- รับ `id` จากภายนอกโดยตรง (ใครก็เรียกเปลี่ยนรหัสผ่านของ user ไหนก็ได้ถ้ารู้ id)
- **ไม่มี caller ในโค้ดปัจจุบัน** (dead code หลัง Phase 12.9 hotfix)

### 6.0 กำจัด footgun เดิม (แก้ช่องว่าง C5)

เพื่อไม่ให้เกิด call site ใหม่ที่ bypass การตรวจรหัสผ่านเดิม (ผิดกฎ B2 "ห้ามเพิ่ม call site ใหม่" ของ Phase 12.9):

- เปลี่ยน `updatePassword(String id, String newPassword)` จาก public เป็น **private** `_setHashedPassword(String id, String hashedPassword)` และให้ `changeCurrentUserPassword()` เป็นจุดเดียวที่เรียกใช้
- ห้ามเปิด public method ที่รับ `id` จากภายนอกโดยไม่ตรวจรหัสผ่านเดิมอีกต่อไป
- ถ้ามี use case future ที่ต้อง reset โดย admin (ไม่ผ่าน current-password check) ให้แยกเป็น method ใหม่ชื่อสื่อความหมาย เช่น `adminForcePasswordReset()` และต้องมี authorization check ของตัวเอง — ไม่ใช้ `updatePassword` เดิม

### 6.1 Method ใหม่

```dart
Future<PasswordChangeResult> changeCurrentUserPassword({
  required String currentPassword,
  required String newPassword,
})
```

### 6.2 การตรวจรหัสผ่านเดิมโดยไม่ดึง `password_hash` กลับมา (แก้ช่องว่าง C1)

**ห้าม** `select('password_hash')` แล้วเทียบค่าใน Dart เพราะจะทำให้ hash หลุดเข้า client memory/log ซึ่งขัดกับ containment B2 ที่ปิดไปแล้วใน Phase 12.9 (ดู `Match_Sport_PLAN.md` P0 blocker B2)

ให้ตรวจแบบเดียวกับ `login()` ที่มีอยู่ — filter `.eq('password_hash', hash)` ในระดับ query แล้วเช็คว่ามีแถวที่ match หรือไม่ โดย **ไม่ select column `password_hash` ออกมา**:

```dart
Future<bool> _verifyCurrentPassword(String userId, String currentPassword) async {
  final hashed = _hashPassword(currentPassword);
  final match = await _client
      .from('users')
      .select('id') // ห้ามมี password_hash ใน select list
      .eq('id', userId)
      .eq('password_hash', hashed)
      .eq('is_active', true)
      .maybeSingle();
  return match != null;
}
```

> คำสั่ง SQL ตรวจสอบใน §10 (Functional regression #7) เป็น query ที่รันจาก DB console/admin เท่านั้น **ไม่ใช่ query ที่ client เรียก** — ต้องระบุไว้ในเอกสารทดสอบเพื่อไม่ให้เข้าใจผิดว่าแอปอ่าน `password_hash` ได้

### 6.3 เงื่อนไขตาม DatabaseMode (แก้ช่องว่าง C3)

`AppConfig.databaseMode` มี 3 ค่า (`unified` / `localOnly` / `supabaseOnly`) แต่ local API (`websocket-server/server.js` `PUT /api/users/:id`) มี `allowedFields` ที่ **ไม่รวม password** (`first_name, last_name, email, phone, profile_image_url` เท่านั้น — `server.js:1895`) ดังนั้นถ้า mode เป็น `localOnly` การเปลี่ยนรหัสผ่านจะไม่มีทางไปถึง DB ได้เลยด้วย code ปัจจุบัน

**ตัดสินใจสำหรับรอบนี้:** `changeCurrentUserPassword()` ทำงานผ่าน Supabase `_client` เท่านั้น (เหมือน `login()`/`createUser()` เดิม) และ:
- ถ้า `AppConfig.databaseMode == DatabaseMode.localOnly` → แสดงข้อความ `ฟีเจอร์นี้ต้องเชื่อมต่ออินเทอร์เน็ต ไม่รองรับในโหมด Local Only ขณะนี้` แทนการเปิดฟอร์ม หรือ disable เมนู `เปลี่ยนรหัสผ่าน` ทั้งหมดเมื่ออยู่ใน mode นี้
- `unified`/`supabaseOnly` ทำงานได้ตามแผนปกติ
- การเพิ่ม `password` เข้า local API `allowedFields` (เพื่อรองรับ `localOnly` เต็มรูปแบบ) เลื่อนไปทำใน Phase 13.2 พร้อมกับ server-side hashing เพื่อไม่เพิ่ม attack surface ใหม่บน local API ที่ยังไม่มี auth ที่แข็งพอ

### 6.4 Rate limiting / brute-force ของรหัสผ่านเดิม (แก้ช่องว่าง C4)

การตรวจรหัสผ่านเดิมใน §6.2 เป็น client-side query ตรงไป Supabase ไม่มี rate limiter ฝั่ง server คุมอยู่ (Phase 13.2 เท่านั้นที่จะมี `loginLockoutLimiter`/`authRateLimiter`) จึงมี **residual risk ที่ยอมรับได้ชั่วคราว**: ผู้ใช้ที่ login ค้างอยู่แล้วสามารถลองรหัสผ่านเดิมซ้ำได้ไม่จำกัดจากอุปกรณ์เดียวกัน

Mitigation ระดับ client (บังคับใช้ในรอบนี้):
- นับจำนวนครั้งที่ `currentPasswordIncorrect` ติดกันใน state ของ Bottom Sheet (`_currentPasswordFailCount`)
- หลังผิดครบ 3 ครั้ง → disable ปุ่ม `เปลี่ยนรหัสผ่าน` เป็นเวลา 30 วินาที พร้อมข้อความ `ลองผิดหลายครั้ง กรุณารอสักครู่`
- reset counter เมื่อ submit สำเร็จหรือปิด Bottom Sheet
- บันทึกไว้ใน residual risk ของแผนนี้ว่า cooldown ระดับ client ไม่ใช่ตัวป้องกันจริง (ผู้ใช้ปิดแอปแล้วเปิดใหม่ก็ reset ได้) การป้องกันจริงต้องรอ server-side rate limiter ใน Phase 13.2

### 6.5 ขั้นตอนการทำงานใน compatibility phase

1. อ่าน current user จาก `AuthService.instance.currentUser`
2. ปฏิเสธทันทีถ้าไม่มีผู้ใช้ login → `PasswordChangeResult.unauthorized`
3. ถ้า `AppConfig.databaseMode == DatabaseMode.localOnly` → `PasswordChangeResult.unsupportedOffline` (ดู §6.3)
4. ถ้า current user เป็น social login ล้วน (ไม่มี `password_hash`) → `PasswordChangeResult.socialAccountNoPassword` (ดู §8)
5. ตรวจ cooldown จาก brute-force counter (§6.4); ถ้ายังล็อกอยู่ → `PasswordChangeResult.tooManyAttempts`
6. ตรวจรหัสผ่านเดิมด้วยวิธีใน §6.2 (ไม่ดึง `password_hash` กลับมา); ผิด → เพิ่ม fail counter, คืน `PasswordChangeResult.currentPasswordIncorrect`
7. ตรวจ `newPassword` ตาม policy ใน §5.1; ไม่ผ่าน → `PasswordChangeResult.invalidPassword`
8. hash `newPassword` ด้วย `_hashPassword()` เดิม (SHA-256) — **ยังไม่เปลี่ยนเป็น Argon2id ในรอบนี้** เพราะนั่นเป็นงานของ Phase 13.2 ที่ต้องมี server-side hashing ก่อน
9. เรียก `_setHashedPassword(id, hashedPassword)` (private ตาม §6.0) update เฉพาะ current user (`eq('id', userId)`)
10. ตั้งค่า metadata ในแถวเดียวกัน:
    - `password_algo = 'sha256'`
    - `password_updated_at = now`
    - `requires_password_reset = false`
    - `updated_at = now`
    - **ห้ามตั้งหรือแก้ `password_migrated_at`** (คอลัมน์นี้สงวนไว้สำหรับ cutover เป็น Argon2id ใน Phase 13.2 เท่านั้น — ตั้งตอนนี้จะทำให้ metadata สื่อความหมายผิดว่า migrate ไป Argon2id แล้ว) — (R1)
11. ห้ามคืนหรือ log ค่า `password_hash` ในทุกขั้น (รวม error path)
12. reset fail counter จาก §6.4
13. refresh ข้อมูล current user ใน `AuthService` ด้วย method ใหม่ `AuthService.applyUserUpdate(UserModel)` (ดู §6.6)

### 6.6 เพิ่ม method ใน `AuthService` (แก้ช่องว่าง C6)

`AuthService` ปัจจุบัน (`lib/services/auth_service.dart`) มีแค่ `login()`, `logout()`, getters และ internal `copyWith()` สำหรับ auto-reset busy status — **ไม่มี method สำหรับ refresh ข้อมูล user หลัง mutation อื่น** ต้องเพิ่ม:

```dart
/// อัปเดต currentUser ในหน่วยความจำหลังข้อมูลผู้ใช้เปลี่ยน (เช่น เปลี่ยนรหัสผ่าน)
/// ไม่ fetch ใหม่จาก DB เพื่อลด round-trip — ใช้ user object ที่ caller มีอยู่แล้ว
void applyUserUpdate(UserModel updatedUser) {
  if (_currentUser?.id != updatedUser.id) return; // ป้องกัน user ผิดคน
  _currentUser = updatedUser;
  notifyListeners();
}
```

`changeCurrentUserPassword()` เรียก `AuthService.instance.applyUserUpdate(...)` ด้วย `UserModel` ที่ merge `updated_at`/`password_updated_at` ใหม่ (ไม่มี `passwordHash` เพราะ field นี้ถูกลบออกจาก `UserModel` แล้วใน Phase 12.9)

### 6.7 ผลลัพธ์ (ปรับปรุงตาม R4)

```dart
enum PasswordChangeResult {
  success,
  unauthorized,
  currentPasswordIncorrect,
  invalidPassword,
  socialAccountNoPassword,   // เพิ่ม: บัญชี social login ไม่มีรหัสผ่านเดิมให้ตรวจ (§8)
  tooManyAttempts,           // เพิ่ม: ติด client-side cooldown จาก §6.4
  unsupportedOffline,        // เพิ่ม: DatabaseMode.localOnly ยังไม่รองรับ (§6.3)
  failed,
}
```

### 6.8 Known limitations ที่ต้องบันทึกไว้อย่างชัดเจน (R2)

- **ไม่มี audit log**: ตาราง `audit_logs` ยังไม่ถูกสร้างจนกว่า Phase 13.2 — การเปลี่ยนรหัสผ่านรอบนี้จะไม่มี audit trail ถาวร (มีเพียง `password_updated_at` เป็นหลักฐานเดียว)
- **ไม่ revoke session/device อื่น**: ยังไม่มี refresh-token registry (มาใน Phase 13.2 โดย reuse/extend `public.sessions`) ดังนั้นเปลี่ยนรหัสผ่านรอบนี้ **ไม่ทำให้ device อื่นที่ login ค้างอยู่ถูก logout** ต้องบันทึกเป็น residual risk ที่ยอมรับใน compatibility phase และปิดจริงใน Phase 13.2

> หมายเหตุ: วิธีทั้งหมดข้างบนเป็น compatibility path ระหว่างรอ Phase 13.2 ซึ่งจะย้ายการตรวจและเปลี่ยนรหัสผ่านไป Backend พร้อม Argon2id, rate limiting และ audit log ตาม `docs/plans/Match_Sport_PLAN.md`

## 7. State ของ Bottom Sheet

ควรมี state อย่างน้อย:

```text
_obscureCurrentPassword
_obscureNewPassword
_obscureConfirmPassword
_isPasswordVisibleMode
_isChangingPassword
_currentPasswordFailCount   // เพิ่ม: นับ currentPasswordIncorrect ติดกัน (§6.4)
_cooldownUntil               // เพิ่ม: DateTime? เวลาที่ปลดล็อกปุ่มได้ (§6.4)
```

ปุ่ม `เปลี่ยนรหัสผ่าน` ต้อง disabled หรือแสดง loading ระหว่าง request เพื่อป้องกันการ submit ซ้ำ และต้อง disabled เพิ่มระหว่าง `_cooldownUntil` ยังไม่ผ่าน (แสดง countdown/ข้อความ `ลองผิดหลายครั้ง กรุณารอสักครู่` ตาม §6.4)

เมื่อสำเร็จ:

1. แสดงข้อความ `เปลี่ยนรหัสผ่านเรียบร้อยแล้ว`
2. ปิด Bottom Sheet
3. กลับไปที่ Profile tab
4. ไม่แสดงค่า password ใด ๆ ในหน้าจอหรือ log

เมื่อผิดพลาด:

- คง Bottom Sheet ไว้
- แสดง error ใกล้ฟอร์มหรือผ่าน SnackBar
- อนุญาตให้แก้ไขแล้ว submit ใหม่

## 8. ผู้ใช้ Social Login และ forced reset

### Social Login

ถ้าไม่มีรหัสผ่านเดิม (`password_hash IS NULL`) ให้แสดงข้อความ:

```text
บัญชีนี้ยังไม่ได้ตั้งรหัสผ่าน
```

ไม่ควรแสดงฟอร์มเปลี่ยนรหัสผ่านปกติที่บังคับกรอกรหัสผ่านเดิมจนกว่าจะมี flow ตั้งรหัสผ่านโดยเฉพาะ — ตรวจเงื่อนไขนี้ **ก่อน**เปิด Bottom Sheet (เช็คจาก `UserModel`/state ที่มีอยู่ ไม่ต้อง query เพิ่ม) เพื่อคืน `PasswordChangeResult.socialAccountNoPassword` ตามลำดับใน §6.5 ขั้นที่ 4

### `requires_password_reset = true` (ปรับปรุงตาม R5)

ให้แสดงข้อความเตือนใน section:

```text
จำเป็นต้องเปลี่ยนรหัสผ่านเพื่อความปลอดภัยของบัญชี
```

**สำคัญ:** สถานะนี้ **ไม่ข้าม** การตรวจรหัสผ่านเดิม — ผู้ใช้ยังต้องกรอกรหัสผ่านปัจจุบันให้ถูกต้องก่อนตั้งรหัสใหม่เสมอ (ยึดตามลำดับ §6.5 ปกติทุกขั้น) เหตุผล: แถวที่ถูก mark `requires_password_reset = true` จาก migration `20260831120000_phase_12_9_password_hotfix.sql` คือรูปแบบที่ **ไม่ผ่านการตรวจ SHA-256/Argon2** (มักเป็น plaintext เดิม) — ถ้าปล่อยให้ตั้งรหัสใหม่โดยไม่ตรวจอะไรเลย จะเป็นการเปิดช่องให้ใครก็ตั้งรหัสผ่านใหม่ให้บัญชีนั้นได้โดยไม่ต้องรู้อะไรเกี่ยวกับบัญชีเลย

เมื่อเปลี่ยนรหัสผ่านสำเร็จ (ผ่าน §6.5 ขั้นที่ 10) ให้ตั้ง `requires_password_reset = false` เหมือนเดิม ไม่ต้อง flow พิเศษเพิ่ม

การบังคับ reset เต็มรูปแบบ (เช่น บล็อกการใช้แอปจนกว่าจะ reset, ส่ง OTP ยืนยันตัวตนแทนรหัสผ่านเดิมสำหรับกรณีจำรหัสผ่านเดิมไม่ได้) ให้ดำเนินการใน Backend auth ของ Phase 13.2 ตาม Q4-B ("ครบ 90 วันหลัง password cutover ผู้ใช้ที่ยังไม่เป็น argon2id ต้อง reset ผ่าน OTP")

## 9. ไฟล์ที่คาดว่าจะเปลี่ยน

```text
lib/features/profile/presentation/pages/profile_page.dart
lib/features/auth/data/repositories/user_repository.dart
lib/services/auth_service.dart                          # เพิ่ม applyUserUpdate() (§6.6)
lib/core/constants/password_policy.dart                 # ใหม่ (§5.1)
lib/features/auth/presentation/pages/register_page.dart         # ปรับให้ใช้ PasswordPolicy.minLength (§5.1)
lib/features/auth/presentation/pages/register_wizard_page.dart  # ปรับให้ใช้ PasswordPolicy.minLength (§5.1)
```

ไฟล์ทดสอบที่ควรเพิ่มตามโครงสร้างโปรเจกต์:

```text
test/features/auth/data/repositories/user_repository_test.dart
test/features/profile/presentation/pages/profile_page_test.dart
test/core/constants/password_policy_test.dart
```

ไม่สร้าง:

```text
ChangePasswordPage
เส้นทางใหม่
แท็บ Profile ใหม่
```

## 10. Test plan

### UI test

- เห็น section `ความปลอดภัยของบัญชี` ใน Profile tab
- กดเมนูแล้วเปิด Bottom Sheet ได้
- ค่าเริ่มต้นซ่อนรหัสผ่าน
- เปิดการมองเห็นแล้วช่องยืนยันหายไป
- ปิดการมองเห็นแล้วช่องยืนยันกลับมา
- ค่าช่องยืนยันไม่หายเมื่อสลับการมองเห็น
- keyboard ไม่บังปุ่ม submit
- กด submit ซ้ำระหว่าง loading ไม่ได้
- ปัด/แตะนอก sheet เพื่อปิดระหว่าง loading ไม่ได้ (`isDismissible: false` ตาม §3)
- ไอคอนของช่อง `รหัสผ่านปัจจุบัน`/`ยืนยัน` ควบคุมเฉพาะช่องตัวเอง ไม่กระทบ global mode (§4.0)

### Validation test

- รหัสผ่านเดิมว่าง
- รหัสผ่านใหม่สั้นกว่า `PasswordPolicy.minLength`
- รหัสผ่านใหม่กับยืนยันไม่ตรงกัน
- รหัสผ่านใหม่ซ้ำกับรหัสผ่านเดิม
- เปิดการมองเห็นแล้ว submit ได้โดยไม่มีช่องยืนยัน
- ผิดรหัสผ่านเดิมติดกัน 3 ครั้ง → ปุ่มถูก disable ตาม cooldown (§6.4); ครบเวลาแล้วปุ่มกลับมาใช้ได้
- บัญชี social-login-only เปิด Bottom Sheet แล้วได้ผลลัพธ์ `socialAccountNoPassword` ไม่ใช่ฟอร์มเปลี่ยนรหัสผ่านปกติ (§8)

### Functional regression

1. กรอกรหัสผ่านเดิมผิด → เปลี่ยนไม่ได้
2. กรอกข้อมูลไม่ครบ → ไม่ส่ง request
3. เปลี่ยนรหัสผ่านสำเร็จ → แสดง success
4. Logout
5. Login ด้วยรหัสผ่านใหม่ → สำเร็จ
6. Login ด้วยรหัสผ่านเดิม → ไม่สำเร็จ
7. ตรวจ DB โดยไม่แสดงค่า hash:

```sql
SELECT
  id,
  username,
  password_algo,
  password_updated_at,
  requires_password_reset,
  length(password_hash) AS hash_length
FROM public.users
WHERE username = 'dave';
```

ผลที่คาดหวังใน compatibility phase:

```text
password_algo = sha256
password_updated_at IS NOT NULL
password_migrated_at IS NULL      -- ต้องยังไม่ถูกตั้ง (R1, §6.5 ขั้นที่ 10)
requires_password_reset = false
hash_length = 64
```

> Query ข้างบนรันจาก DB console/admin เท่านั้นเพื่อยืนยันผลลัพธ์ระหว่างทดสอบ — **ไม่ใช่ query ที่แอปไคลเอนต์เรียก** (ดู §6.2)

### Security test

- ไม่สามารถระบุ user ID คนอื่นจาก UI เพื่อเปลี่ยนรหัสผ่าน
- ไม่ส่ง password/hash ไปใน log
- ไม่เก็บรหัสผ่านใน persistent storage
- ไม่คืน `password_hash` ให้ UI หรือ `UserModel`
- **Mock `SupabaseClient` แล้วตรวจว่า select list ของ query ตรวจรหัสผ่านเดิม (§6.2) ไม่มี `password_hash` อยู่ใน column list ที่ขอ** (unit test ตรง ๆ ไม่ใช่แค่ตรวจ response)
- หลัง `changeCurrentUserPassword()` สำเร็จ ตรวจว่า `AuthService.instance.currentUser` (ที่ผ่าน `applyUserUpdate`) ไม่มี field ใดเก็บ hash หรือ plaintext ของรหัสผ่านใหม่/เดิมค้างอยู่ใน memory
- ยืนยันด้วย `dart analyze`/type system ว่า `UserModel` ไม่มี field `passwordHash` อีก (Phase 12.9 ลบไปแล้ว — ทดสอบนี้กันการเผลอเพิ่มกลับมา)

## 11. Acceptance criteria

งานถือว่าเสร็จเมื่อ:

- มีเมนู `เปลี่ยนรหัสผ่าน` ใน Profile tab เดิม
- ไม่สร้างหน้า `ChangePasswordPage`
- Bottom Sheet รองรับทั้งโหมดซ่อนและแสดงรหัสผ่าน
- โหมดซ่อนบังคับกรอกรหัสผ่านซ้ำ
- โหมดแสดงรหัสผ่านไม่แสดงช่องยืนยัน
- การสลับโหมดไม่ทำให้ค่าที่กรอกหาย
- ตรวจรหัสผ่านเดิมก่อนเปลี่ยน
- เปลี่ยนได้เฉพาะ current user
- เปลี่ยนสำเร็จแล้ว login ด้วยรหัสใหม่ได้
- รหัสผ่านเดิมใช้ login ไม่ได้
- metadata ของ password ถูกอัปเดตครบ (`password_algo`, `password_updated_at`, `requires_password_reset` — และ `password_migrated_at` ต้องยังเป็น `NULL`)
- มีผลการทดสอบบันทึกไว้ในแผน Phase 12.9
- `PasswordPolicy.minLength` ถูกใช้ร่วมกันระหว่าง register และ change-password (ไม่มีค่าฮาร์ดโค้ด 6/8 หลุดคู่ขนานอีก)
- `UserRepository.updatePassword` เดิมถูกเปลี่ยนเป็น private (`_setHashedPassword`) หรือถูกลบ — ไม่มี public method ที่ set password โดยไม่ผ่านการตรวจรหัสผ่านเดิม
- `AuthService.applyUserUpdate()` มีอยู่และถูกเรียกหลังเปลี่ยนรหัสผ่านสำเร็จ
- เมนู `เปลี่ยนรหัสผ่าน` ถูก disable/แสดงข้อความอธิบายเมื่อ `AppConfig.databaseMode == DatabaseMode.localOnly`
- brute-force cooldown ของรหัสผ่านเดิมทำงานตาม §6.4 และถูกบันทึกเป็น residual risk (ไม่ใช่ทางแก้ถาวร)
- known limitations (ไม่มี audit log, ไม่ revoke session อื่น) ถูกบันทึกไว้ในแผนนี้อย่างชัดเจน ไม่ใช่ความเงียบที่อาจทำให้เข้าใจผิดว่า Phase 12.9/13.2 ปิดครบแล้ว

## 12. อ้างอิง

เอกสารนี้เป็น implementation detail ของ Phase 12.9 hotfix ตามที่ระบุใน `docs/plans/Match_Sport_PLAN.md` (P0 blocker B1/B2, Decision Q4-B lazy rehash) — การเปลี่ยนแปลงใด ๆ ในแผนนี้ที่กระทบ compatibility window (เช่น เปลี่ยนจาก SHA-256 เป็น Argon2id, เพิ่ม server-side rate limiter, สร้าง audit log) ต้องซิงก์กลับไปที่ `Match_Sport_PLAN.md` Phase 13.2 ด้วย เพื่อไม่ให้เอกสารสองฉบับขัดกัน
