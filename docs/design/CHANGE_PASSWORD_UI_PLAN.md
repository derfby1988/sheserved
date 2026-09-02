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

ใช้ไอคอนแสดง/ซ่อนที่ช่อง `รหัสผ่านใหม่` เป็นตัวควบคุมหลัก

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

ตรวจทุกครั้งก่อน submit:

- ต้องมีผู้ใช้ที่ login อยู่
- รหัสผ่านปัจจุบันต้องไม่ว่าง
- รหัสผ่านใหม่ต้องไม่ว่าง
- รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร
- รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน

ตรวจเพิ่มเฉพาะเมื่อไม่ได้เปิดการมองเห็น:

- ช่องยืนยันรหัสผ่านต้องไม่ว่าง
- รหัสผ่านใหม่และรหัสยืนยันต้องตรงกัน

ข้อความ validation:

```text
กรุณากรอกรหัสผ่านปัจจุบัน
กรุณากรอกรหัสผ่านใหม่
รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร
รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม
กรุณายืนยันรหัสผ่านใหม่
รหัสผ่านใหม่และการยืนยันไม่ตรงกัน
```

## 6. Repository และการบันทึกข้อมูล

ปัจจุบันมี `UserRepository.updatePassword(id, newPassword)` แต่ยังไม่ตรวจรหัสผ่านเดิมและรับ user ID จากภายนอกโดยตรง

ควรเพิ่ม method ใหม่แทนการเรียก method เดิมจาก UI:

```dart
Future<PasswordChangeResult> changeCurrentUserPassword({
  required String currentPassword,
  required String newPassword,
})
```

หลักการทำงานใน compatibility phase:

1. อ่าน current user จาก `AuthService.instance.currentUser`
2. ปฏิเสธทันทีถ้าไม่มีผู้ใช้ login
3. hash `currentPassword` ด้วย SHA-256 ตามระบบเดิม
4. ตรวจสอบกับรหัสผ่านของ current user
5. hash `newPassword`
6. update เฉพาะ current user
7. ตั้งค่า metadata:
   - `password_algo = 'sha256'`
   - `password_updated_at = now`
   - `requires_password_reset = false`
   - `updated_at = now`
8. ห้ามคืนหรือ log ค่า `password_hash`
9. refresh ข้อมูล current user ใน `AuthService`

ผลลัพธ์ควรแยกสถานะให้ UI แสดงข้อความได้ถูกต้อง เช่น:

```dart
enum PasswordChangeResult {
  success,
  unauthorized,
  currentPasswordIncorrect,
  invalidPassword,
  failed,
}
```

> หมายเหตุ: วิธีนี้เป็น compatibility path ระหว่างรอ Phase 13.2 ซึ่งจะย้ายการตรวจและเปลี่ยนรหัสผ่านไป Backend พร้อม Argon2id และ audit log

## 7. State ของ Bottom Sheet

ควรมี state อย่างน้อย:

```text
_obscureCurrentPassword
_obscureNewPassword
_obscureConfirmPassword
_isPasswordVisibleMode
_isChangingPassword
```

ปุ่ม `เปลี่ยนรหัสผ่าน` ต้อง disabled หรือแสดง loading ระหว่าง request เพื่อป้องกันการ submit ซ้ำ

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

ถ้าไม่มีรหัสผ่านเดิม ให้แสดงข้อความ:

```text
บัญชีนี้ยังไม่ได้ตั้งรหัสผ่าน
```

ไม่ควรแสดงฟอร์มเปลี่ยนรหัสผ่านปกติที่บังคับกรอกรหัสผ่านเดิมจนกว่าจะมี flow ตั้งรหัสผ่านโดยเฉพาะ

### `requires_password_reset = true`

ให้แสดงข้อความเตือนใน section:

```text
จำเป็นต้องเปลี่ยนรหัสผ่านเพื่อความปลอดภัยของบัญชี
```

การบังคับ reset เต็มรูปแบบให้ดำเนินการใน Backend auth ของ Phase 13.2

## 9. ไฟล์ที่คาดว่าจะเปลี่ยน

```text
lib/features/profile/presentation/pages/profile_page.dart
lib/features/auth/data/repositories/user_repository.dart
```

ไฟล์ทดสอบที่ควรเพิ่มตามโครงสร้างโปรเจกต์:

```text
test/features/auth/data/repositories/user_repository_test.dart
test/features/profile/presentation/pages/profile_page_test.dart
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

### Validation test

- รหัสผ่านเดิมว่าง
- รหัสผ่านใหม่สั้นกว่า 8 ตัว
- รหัสผ่านใหม่กับยืนยันไม่ตรงกัน
- รหัสผ่านใหม่ซ้ำกับรหัสผ่านเดิม
- เปิดการมองเห็นแล้ว submit ได้โดยไม่มีช่องยืนยัน

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
requires_password_reset = false
hash_length = 64
```

### Security test

- ไม่สามารถระบุ user ID คนอื่นจาก UI เพื่อเปลี่ยนรหัสผ่าน
- ไม่ส่ง password/hash ไปใน log
- ไม่เก็บรหัสผ่านใน persistent storage
- ไม่คืน `password_hash` ให้ UI หรือ `UserModel`

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
- metadata ของ password ถูกอัปเดตครบ
- มีผลการทดสอบบันทึกไว้ในแผน Phase 12.9
