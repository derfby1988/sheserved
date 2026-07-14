# E4 Test Plan — Maestro UI Tests

## ทดสอบตาม E4.9 Test Plan (14 ข้อ)

ใช้ Maestro เพื่อทดสอบ UI ของ E4 (Separating admin cancellation from invitee rejection)

## อุปกรณ์ทดสอบ

- **Device ID:** `R8YYA0G5S6J` (Android — SM X135G)
- **App ID:** `com.sheserved.app`

## บัญชีทดสอบ

| บทบาท | Username | Password | สิทธิ์ |
|-------|----------|----------|--------|
| Admin | `apisek` | `123456` | HR >= 2 (ยกเลิกคำเชิญได้) |
| Invitee | `firm` | `123456` | ผู้ถูกเชิญ (ตอบรับ/ปฏิเสธได้) |

## โครงสร้างไฟล์

```
docs/guides/e4_tests/
├── _login.yaml                      # Subflow: login ด้วย username/password
├── _navigate_to_invitations.yaml    # Subflow: Home → ERP → Employees → คำเชิญ tab
├── test_01_admin_cancel_pending.yaml        # Admin ยกเลิก pending invitation
├── test_02_invitee_reject.yaml              # ผู้ถูกเชิญปฏิเสธ
├── test_03_history_separate.yaml            # ประวัติแยก rejected vs cancelled
├── test_04_cancelled_no_reinvite.yaml       # Cancelled card ไม่มีปุ่มเชิญใหม่
├── test_05_rejected_has_reinvite.yaml       # Rejected card มีปุ่มเชิญใหม่
├── test_06_filter_sections.yaml             # กรอง pending/rejected/cancelled/expired
├── test_07_invitee_home_header_cancelled.yaml # Invitee เห็น cancelled read-only
├── test_08_pending_not_in_cancelled_feed.yaml # Pending ไม่ปะปนกับ cancelled
├── test_09_cancel_existing_user_invite.yaml # ยกเลิก existing user invite + ตรวจ feed
├── test_10_rpc_null_cancelled_by.yaml       # RPC reject NULL cancelled_by (DB test)
├── test_11_rpc_no_permission.yaml           # RPC reject user ไม่มี HR permission (DB test)
├── test_12_authservice_only.yaml            # ใช้ AuthService ไม่ใช่ Supabase Auth (code review)
├── test_13_concurrent_race.yaml             # Concurrent cancel + accept race (DB test)
└── test_14_cancelled_feed_rpc.yaml          # Cancelled feed RPC returns only cancelled
```

## วิธีรัน

### รันทั้งหมด

```bash
maestro test --device R8YYA0G5S6J docs/guides/e4_tests/
```

### รันเฉพาะไฟล์

```bash
maestro test --device R8YYA0G5S6J docs/guides/e4_tests/test_01_admin_cancel_pending.yaml
```

### รันเฉพาะ tag

```bash
maestro test --device R8YYA0G5S6J --include-tags e4 docs/guides/e4_tests/
maestro test --device R8YYA0G5S6J --include-tags admin docs/guides/e4_tests/
maestro test --device R8YYA0G5S6J --include-tags invitee docs/guides/e4_tests/
```

### รันบน Maestro Cloud

```bash
maestro cloud --device-model pixel_6 --app build/app/outputs/flutter-apk/app-release.apk docs/guides/e4_tests/
```

## ข้อกำหนดเบื้องต้น (Data Prerequisites)

### ข้อมูลในฐานข้อมูล
- **Admin (apisek)** ต้องมี `employee_roles` ที่ `is_active = true` เพื่อให้ ERP card แสดงบน Home page
  ```sql
  -- ตรวจสอบ
  SELECT * FROM employee_roles WHERE user_id = (SELECT id FROM users WHERE username = 'apisek') AND is_active = true;
  ```
- **ต้องมี pending invitation** อย่างน้อย 1 รายการสำหรับ test_01, test_06
- **ต้องมี rejected invitation** อย่างน้อย 1 รายการสำหรับ test_03, test_05, test_06
- **ต้องมี cancelled invitation** อย้างน้อย 1 รายการสำหรับ test_03, test_04, test_06
- **ต้องมี expired invitation** อย่างน้อย 1 รายการสำหรับ test_06
- **Admin (apisek)** ต้องมี HR access level >= 2 เพื่อยกเลิกคำเชิญได้

### ข้อจำกัดของอุปกรณ์ทดสอบ
- หน้าจอ 800x1340 px, density 213
- Flutter `content-desc` ไม่ถูก match โดย Maestro `text:` บนอุปกรณ์นี้ → ใช้ point-based tapping
- แอปเริ่มที่หน้า Home (ไม่บังคับ login) → ต้องนำทางผ่าน Profile tab เพื่อเข้าสู่หน้า login
- การเลื่อนหน้า Home อาจถูก map ดักจับ gesture → เลื่อนจากขอบขวา

## หมายเหตุ

- **Test 10, 11, 13** เป็น database-level tests ไม่สามารถตรวจสอบผ่าน UI ได้โดยตรง ไฟล์ YAML มีคำสั่ง SQL สำหรับรันใน Supabase SQL Editor
- **Test 12** เป็น code inspection test ใช้ `grep` ตรวจสอบว่าใช้ `AuthService` ไม่ใช่ `Supabase.instance.client.auth`
- ก่อนรัน test ที่เกี่ยวกับ cancelled invitations ต้องมี cancelled invitation ในระบบก่อน (รัน test_01 ก่อน)
- ก่อนรัน test ที่เกี่ยวกับ rejected invitations ต้องมี rejected invitation ในระบบก่อน (รัน test_02 ก่อน)
- ลำดับแนะนำ: test_01 → test_02 → test_03 → test_04 → test_05 → test_06 → test_07 → test_08 → test_09 → test_10..14
- ไฟล์ `_navigate_to_invitations_v2.yaml` เป็นเวอร์ชันที่ใช้ `scrollUntilVisible` แทน point-based
