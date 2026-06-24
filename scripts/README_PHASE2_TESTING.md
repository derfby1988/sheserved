# Phase 2 Testing Guide
# คู่มือการทดสอบ Phase 2

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

### 3. ทดสอบ Manual (UI Testing)

#### 3.1 Admin User Test
1. Login ด้วย admin user
2. ตรวจสอบ drawer → มี "ผู้ดูแลระบบ" menu
3. เข้า `/admin/professions` → ต้องเข้าได้
4. เข้า GroupMembersAdminPage → toggle admin ได้
5. ตรวจสอบ database:
   ```sql
   SELECT id, username, role, user_category_id
   FROM users WHERE username = '<test_user>';
   -- ต้องมี role = user_category_id
   ```

#### 3.2 Provider User Test
1. Login ด้วย provider user
2. ตรวจสอบ drawer → ไม่มี "ผู้ดูแลระบบ" menu
3. เข้า `/health-program-requests` → ต้องเข้าได้
4. เข้า `/admin/professions` → ต้องถูก block

#### 3.3 Consumer User Test
1. Login ด้วย consumer user
2. ตรวจสอบ drawer → ไม่มี admin menu
3. เข้า `/admin/professions` → ต้องถูก block

#### 3.4 Registration Test
1. สมัครสมาชิกใหม่
2. ตรวจสอบ database:
   ```sql
   SELECT role, user_category_id
   FROM users WHERE username = '<new_user>';
   -- ต้องมี role = 'consumer' AND user_category_id = 'consumer'
   ```

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

## สรุป

| การทดสอบ | ความถี่ | ผู้รับผิดชอบ |
|---|---|---|
| SQL verification | หลังรัน migration | Developer |
| Flutter integration test | ก่อน deploy | QA / Developer |
| Manual UI testing | ก่อน release | QA |
| Database sync check | วันละครั้ง (1 สัปดาห์แรก) | Developer |
