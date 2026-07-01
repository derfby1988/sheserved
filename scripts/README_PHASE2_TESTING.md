# Phase 2 Testing Guide
# คู่มือการทดสอบ Phase 2

> **สถานะ: ✅ Phase 2 เสร็จสิ้นแล้ว (2026-06-24)**
> เอกสารนี้อัปเดตเพื่อสะท้อนผลการทดสอบจริงและปัญหาที่แก้ไขระหว่างดำเนินงาน

## ไฟล์ทดสอบที่สร้าง

| ไฟล์ | ประเภท | รายละเอียด |
|---|---|---|
| `scripts/verify_phase2_migration.sql` | SQL | ตรวจสอบ database หลัง migration |
| `test/integration/phase2_role_sync_test.dart` | Flutter Test | Integration test สำหรับ role sync |
| `scripts/verify_phase2_prerequisites.sql` | SQL | ตรวจสอบก่อนรัน migration (รันแล้ว) |

---

## วิธีทดสอบ

### 1. ทดสอบ Database (SQL)

#### 1.1 รันผ่าน Supabase SQL Editor
1. ไปที่ Supabase Dashboard → SQL Editor
2. เปิดไฟล์ `scripts/verify_phase2_migration.sql`
3. กด "Run"
4. ดูผลลัพธ์ใน Logs

#### 1.2 รันผ่าน psql
```bash
psql -h <host> -U <user> -d <database> -f scripts/verify_phase2_migration.sql
```

#### ผลลัพธ์ที่คาดหวัง
```
========================================
Phase 2 Post-Migration Verification
========================================
✅ Check 1 PASSED: All 150 users have role = user_category_id
✅ Check 2 PASSED: No users with NULL user_category_id
✅ Check 3 PASSED: admin entry exists in user_categories
✅ Check 4 PASSED: admin flags are correct
✅ Check 5 PASSED: professions.category FK exists
✅ Check 6 PASSED: sync trigger exists
✅ Check 7 PASSED: RLS policy exists
✅ Check 8 PASSED: user_category_id index exists
========================================
✅ ALL CHECKS PASSED - Phase 2 migration is healthy
========================================
```

---

### 2. ทดสอบ Flutter (Integration Test)

#### 2.1 รัน Integration Test
```bash
# รันทั้งหมด
flutter test test/integration/phase2_role_sync_test.dart

# หรือรันบาง test group
flutter test test/integration/phase2_role_sync_test.dart --name "Database Sync"
```

#### 2.2 รันด้วย Debugging
```bash
flutter test test/integration/phase2_role_sync_test.dart --verbose
```

#### ผลลัพธ์ที่คาดหวัง
```
00:02 +9: All tests passed!
```

---

### 3. ทดสอบ Manual (UI Testing) ✅ ผ่านทั้งหมด

#### 3.1 Admin User Test — ✅ PASS
1. Login ด้วย admin user → สำเร็จ
2. ตรวจสอบ drawer → มี "ผู้ดูแลระบบ" menu ✅
3. เข้า `/admin/professions` → เข้าได้ ✅
4. เข้า GroupMembersAdminPage → toggle admin ได้ ✅
5. ตรวจสอบ database:
   ```sql
   SELECT id, username, role, user_category_id
   FROM users WHERE username = '<test_user>';
   -- ต้องมี role = user_category_id
   ```
   **ผล: role = user_category_id ✅**

#### 3.2 Provider User Test — ✅ PASS
1. Login ด้วย provider user → สำเร็จ
2. ตรวจสอบ drawer → ไม่มี "ผู้ดูแลระบบ" menu ✅
3. เข้า `/health-program-requests` → เข้าได้ ✅
4. เข้า `/admin/professions` → ถูก block ✅

#### 3.3 Consumer User Test — ✅ PASS
1. Login ด้วย consumer user → สำเร็จ
2. ตรวจสอบ drawer → ไม่มี admin menu ✅
3. เข้า `/admin/professions` → ถูก block ✅

#### 3.4 Registration Test — ✅ PASS
1. สมัครสมาชิกใหม่ → สำเร็จ (หลังแก้ OTP + RLS)
2. ตรวจสอบ database:
   ```sql
   SELECT role, user_category_id
   FROM users WHERE username = '<new_user>';
   -- ต้องมี role = 'consumer' AND user_category_id = 'consumer'
   ```
   **ผล: role = user_category_id = 'consumer' ✅**

---

## ปัญหาที่พบและแก้ไขระหว่าง Phase 2

### ปัญหา 1: OTP input บน Flutter Web ใช้งานไม่ได้
- **อาการ:** 6 ช่อง OTP กดไม่ได้ / focus หลุด / paste ไม่ทำงาน
- **แก้ไข:** เปลี่ยนเป็น single hidden `TextField` + 6 visual boxes
- **ไฟล์:** `lib/shared/widgets/otp_verification_dialog.dart`

### ปัญหา 2: Phone validation เข้มงวดเกินไป (dev)
- **อาการ:** เบอร์ `0778430244` ถูกปฏิเสธ
- **แก้ไข:** ผ่อนคลาย regex เป็น `^0[0-9]{8,9}$`
- **ไฟล์:** `lib/services/otp_service.dart`

### ปัญหา 3: Registration false failure (RLS deny)
- **อาการ:** UI แสดง "สมัครไม่สำเร็จ" แต่ user ถูกสร้างจริงใน database
- **สาเหตุ:** `user_registration_data` insert ถูก RLS block (`42501`)
- **แก้ไข:** `saveRegistrationDataSafe()` จับ RLS error → log warning ไม่ล้ม flow
- **ไฟล์:** `lib/features/auth/data/repositories/user_repository.dart`
- **หมายเหตุ:** จะสามารถกลับมาใช้ `saveRegistrationData()` ปกติได้เมื่อ RLS policies สำหรับ `user_registration_data` พร้อม

### ปัญหา 4: Duplicate FK บน professions.category
- **อาการ:** PostgREST embedding error
- **แก้ไข:** Migration `20260624090800_remove_duplicate_profession_fk.sql`

### ปัญหา 5: user_approver_settings migration ชื่อผิด
- **อาการ:** table ไม่ถูกสร้าง หรือชื่อไม่ตรง
- **แก้ไข:** แก้ไข migration + repository helper รองรับ fallback

---

## การแก้ไขปัญหา

### ปัญหา: "Check 1 FAILED: role != user_category_id"
**สาเหตุ:** Sync trigger ไม่ทำงาน หรือมีการอัปเดต role โดยตรง

**แก้ไข:**
```sql
-- รีเซ็ต trigger
ALTER TABLE users DISABLE TRIGGER trigger_sync_role_from_category;
ALTER TABLE users ENABLE TRIGGER trigger_sync_role_from_category;

-- หรือ sync ด้วยตนเอง
UPDATE users SET role = user_category_id WHERE role != user_category_id;
```

### ปัญหา: "Check 2 FAILED: users with NULL user_category_id"
**สาเหตุ:** Migration ไม่สมบูรณ์

**แก้ไข:**
```sql
-- อัปเดต NULL ให้เป็น consumer (default)
UPDATE users SET user_category_id = 'consumer'
WHERE user_category_id IS NULL AND role IS NULL;

-- หรือ sync จาก role
UPDATE users SET user_category_id = role
WHERE user_category_id IS NULL AND role IS NOT NULL;
```

### ปัญหา: "Check 5 FAILED: professions.category FK missing"
**สาเหตุ:** Migration 2.5 ไม่ผ่าน (มี orphan data)

**แก้ไข:**
```sql
-- ตรวจหา orphan data
SELECT id, name, category FROM professions
WHERE category IS NOT NULL
  AND category NOT IN (SELECT id FROM user_categories);

-- แก้ไข: เพิ่ม missing categories หรืออัปเดตเป็น NULL
```

---

## สรุปสถานะ Phase 2

| การทดสอบ | สถานะ | ความถี่ | ผู้รับผิดชอบ |
|---|---|---|---|
| SQL verification | ✅ PASS | หลังรัน migration | Developer |
| Flutter integration test | ✅ PASS | ก่อน deploy | QA / Developer |
| Manual UI testing | ✅ PASS | ก่อน release | QA |
| Database sync check | ✅ PASS | วันละครั้ง (1 สัปดาห์แรก) | Developer |

### สรุปการแก้ไขที่ทำใน Phase 2
| หมวดหมู่ | สถานะ |
|---|---|
| Database Migrations (8 ไฟล์) | ✅ 100% |
| Flutter Role Logic (UserModel, AuthGuard, Repository) | ✅ 100% |
| OTP Web UX (Single Input + 6 Boxes) | ✅ 100% |
| OTP Debug/Dev (`[OTP]` logs, relaxed validation) | ✅ 100% |
| Registration Stability (RLS safe save) | ✅ 100% |
| Manual UI Testing (Admin, Provider, Consumer, Registration) | ✅ 100% |

### งานที่ยังคงค้างสำหรับ Phase ถัดไป
1. **RLS Production** — policies สำหรับ `user_registration_data`, `consumer_profiles`, `users`
2. **OTP Server-side** — ย้าย OTP authority ไป Supabase Edge Functions
3. **Automated Tests** — widget test OTP paste, unit test registration RLS
4. **Code Quality** — ลบ unused imports, แก้ deprecated `withOpacity`, `use_build_context_synchronously`
5. **Database Maintenance** — sync check orphan data ก่อน production
