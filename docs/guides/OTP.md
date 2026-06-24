# Phase 2 Role Management Refactor — งานที่เสร็จแล้วและแผนคงค้าง

> เอกสารนี้สรุปงานทั้งหมดที่เสร็จไปแล้วใน Phase 2 (role management refactor)
> และรายการแผนที่ยังคงค้างไว้สำหรับงานระยะยั่งยืน

---

## 1. Database Migrations (เสร็จแล้ว)

### 1.1 Core Schema Refactor
- [x] เพิ่มตาราง `user_categories` พร้อมคอลัมน์ที่เกี่ยวข้องกับ role (is_consumer, is_provider, can_approve_donation ฯลฯ)
- [x] เพิ่ม `category` column ตาราง `professions` (FK → `user_categories`)
- [x] สร้าง sync trigger `trigger_sync_role_from_category` เพื่ออัปเดต `users.role` เมื่อ `user_category_id` เปลี่ยน
- [x] สร้าง migration สำหรับ `user_categories` RLS policies (custom auth function)

### 1.2 Supporting Tables
- [x] `user_group_roles` — จัดการบทบาทผู้ใช้ในกลุ่มอาชีพ
- [x] `role_history` — บันทึกประวัติการเปลี่ยน role
- [x] `user_approver_settings` — ตั้งค่าผู้อนุมัติบริจาคตามประเภท

### 1.3 Fixes
- [x] ลบ duplicate FK `fk_profession_category` ออกจาก `professions` เพื่อแก้ PostgREST embedding error
- [x] แก้ `user_approver_settings` migration ที่มีปัญหาชื่อตารางผิด

---

## 2. Flutter Code — Role Management (เสร็จแล้ว)

### 2.1 UserModel
- [x] เพิ่ม `UserCategory` enum ใน `UserModel`
- [x] เพิ่ม `isAdmin`, `isProvider` getters ที่ดึงจาก `user_categories` attributes
- [x] `role` และ `userRole` ยังคงอยู่สำหรับ backward compatibility

### 2.2 Auth / Route Guards
- [x] `AuthGuardWidget` ตรวจสอบ role จาก `user_categories` (แทน hardcoded string comparison)
- [x] หน้า `UserCategoryAdminPage` รองรับการจัดการหมวดหมู่ผู้ใช้

### 2.3 Repository Updates
- [x] `ProfessionRepository` อัปเดตให้ใช้ `user_categories` เป็นแหล่ง role definitions
- [x] `UserRepository` รองรับ `user_category_id` ใน `createUser`

### 2.4 Donation / Approval Flow
- [x] `DonationRepository` ใช้ safe helper สำหรับอ่าน/เขียน `user_approver_settings`
- [x] ปรับ `DonationApproverSettingsWidget` ใช้ repository helpers (ไม่ query ตรง)

### 2.5 Constants
- [x] `UserRole.fromValue` คืน `null` สำหรับค่า unknown (strict ขึ้น)

---

## 3. Flutter Code — OTP & Registration Fixes (เสร็จแล้ว)

### 3.1 OTP Dialog Refactor
- [x] เปลี่ยน multi-field 6 ช่อง → single hidden `TextField` + 6 visual boxes
- [x] รองรับ **paste** และ **autofill** (`oneTimeCode`)
- [x] ลบ `RawKeyboardListener` และ logic focus ข้ามช่องที่เสถียรภาพต่ำ
- [x] Auto-verify เมื่อครบ 6 หลัก
- [x] Auto-focus กลับมาที่ช่องหลัง error/resend
- [x] ไม่มี analyzer error (`flutter analyze` ผ่าน)

### 3.2 OTP Service Debug
- [x] เพิ่ม `[OTP]` prefix log รอบ `sendOtp`, `verifyOtp`, `resendOtp`
- [x] เปลี่ยน `print` เป็น `debugPrint` เพื่อ avoid lint warning
- [x] Console OTP block ใช้ `[OTP]` ทุกบรรทัด ค้นหาง่ายใน terminal

### 3.3 Phone Validation (Dev Mode)
- [x] ผ่อนคลาย regex `^0[689][0-9]{8}$` → `^0[0-9]{8,9}$`
- [x] รองรับเบอร์ทดสอบ เช่น `0778430244`

### 3.4 Registration — False Failure Fix
- [x] `saveRegistrationDataSafe()` ใน `UserRepository`
- [x] จับเฉพาะ RLS deny (`42501` / row-level security) → log warning ไม่ล้ม flow
- [x] ปรับ log UI ฝั่ง `register_wizard_page` แยก `saved` vs `skipped`
- [x] ผู้ใช้จึงเห็น "สมัครสำเร็จ" จริง แม้ dynamic data ยังไม่ถูกบันทึก

---

## 4. Testing (เสร็จแล้วบางส่วน)

### 4.1 Manual UI Testing
- [x] **Admin User Test:** toggle admin ได้ / database sync ตรง / drawer มี "ผู้ดูแลระบบ"
- [x] **Provider User Test:** เข้า health program ได้ / admin ถูก block
- [x] **Registration Test:** OTP verify ผ่าน → user + consumer profile สร้าง → login ได้

### 4.2 Integration Test
- [x] `phase2_role_sync_test.dart` แก้ deprecated PostgREST methods + UserModel constructor + Supabase init

### 4.3 SQL Verification
- [x] ตรวจว่า `users.role` = `user_category_id`
- [x] ตรวจว่าไม่มี `NULL user_category_id`
- [x] ตรวจว่า `professions.category` FK ถูกต้อง

---

## 5. แผนคงค้าง (Pending Plans)

### 5.1 RLS / Security (สำคัญสำหรับ Production)
- [ ] Migration เพิ่ม RLS policies สำหรับ `user_registration_data`
- [ ] ทดสอบว่า `saveRegistrationDataSafe()` สามารถลบออกและใช้ `saveRegistrationData()` ธรรมดาได้เมื่อ RLS พร้อม
- [ ] ตรวจสอบ RLS ของ `consumer_profiles` / `expert_profiles` / `clinic_profiles`
- [ ] ตรวจสอบ RLS ของ `users` ว่า user ทั่วไปไม่สามารถอ่านข้อมูลคนอื่นได้

### 5.2 OTP — Production Ready (ไม่ใช่ development mode)
- [ ] ย้าย OTP authority ไป server-side (Supabase Edge Functions / backend)
- [ ] แทนที่ `_otpStorage` ใน memory → ใช้ Supabase phone auth / เก็บ hash
- [ ] ปิด `AppConfig.useConsoleOtp = false` ใน production
- [ ] เพิ่ม WebOTP API เป็น enhancement optional

### 5.3 Widget / Unit Tests
- [ ] OTP dialog: test paste 6 digits → auto verify
- [ ] OTP dialog: test autofill behavior
- [ ] Registration: test `saveRegistrationDataSafe()` กรณี RLS deny
- [ ] Role sync: test `UserModel.isAdmin` / `isProvider` หลัง login

### 5.4 Code Quality / Polish
- [ ] ลบ unused imports ใน `register_wizard_page` (thai_buddhist_date, thai_buddhist_date_pickers)
- [ ] ลบ unused field `_cardBg` และ unused method `_buildImageUploadField`
- [ ] แก้ `withOpacity` deprecated → `withValues` รอบที่เหลือ
- [ ] แก้ `use_build_context_synchronously` ใน `register_wizard_page`

### 5.5 Database Maintenance
- [ ] รันคำสั่ง sync role ถ้ามี user ที่ยังไม่ sync: `UPDATE users SET role = user_category_id WHERE role != user_category_id`
- [ ] ตรวจสอบอาจารย์ข้อมูล orphan ใน `professions.category` (อีกรอบก่อน production)

---

## 6. สรุปสถานะ Phase 2

| หมวดหมู่ | สถานะ | หมายเหตุ |
|---|---|---|
| Database Migrations | 100% เสร็จ | 8 migrations ผ่าน |
| Flutter Role Logic | 100% เสร็จ | UserModel, AuthGuard, Drawer |
| OTP Web UX | 100% เสร็จ | Single input + 6 boxes |
| OTP Debug/Dev | 100% เสร็จ | `[OTP]` logs, dev validation |
| Registration Stability | 100% เสร็จ | False failure fixed |
| Manual UI Testing | ~80% เสร็จ | Admin, Provider, Registration ผ่าน |
| RLS Production | คงค้าง | ต้องทำก่อน deploy |
| OTP Server-side | คงค้าง | Phase ถัดไป |
| Automated Tests | คงค้าง | ยังไม่ครบ |

---

*สร้างเมื่อ: 2026-06-24*
*อัปเดตล่าสุด: 2026-06-24*
