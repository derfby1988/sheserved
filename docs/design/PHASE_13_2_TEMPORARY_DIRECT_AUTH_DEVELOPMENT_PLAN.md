# Phase 13.2 — Temporary Direct Auth Development Plan

> **สถานะ:** อนุมัติสำหรับ development/testing เท่านั้น
> **วันที่บันทึก:** 2026-09-07
> **อ้างอิง:** `docs/plans/Match_Sport_PLAN.md`, `docs/secure/18_phase_13_2_auth_runbook.md`

## 1. มติและเหตุผล

ระหว่างที่ยังไม่เปิดใช้ Phase 13.2 เป็น authentication path หลัก ให้ทีมพัฒนาใช้ legacy direct Supabase auth ชั่วคราวได้ เพื่อทดสอบ UI และฟีเจอร์ทั่วไปโดยไม่ต้องเปิดเครื่อง `websocket-server` ตลอดเวลา

การตัดสินใจนี้เป็น **compatibility/testing window** ไม่ใช่การยกเลิก Phase 13.2 และไม่เปลี่ยนเป้าหมาย trusted backend identity boundary ในแผนหลัก

## 2. โหมดการทำงาน

### 2.1 Temporary direct-auth mode

รัน Flutter ด้วย:

```bash
flutter run \\
  -d <device-id> \\
  --dart-define=USE_BACKEND_AUTH=false
```

เส้นทางหลัก:

- password login/register → Supabase client ตรง
- Google/social login → legacy client-side path
- ไม่ต้องใช้ `/api/auth/*` สำหรับ authentication
- ยังต้องมีอินเทอร์เน็ตเพื่อเข้าถึง Supabase
- ฟีเจอร์อื่นที่ใช้ local API/WebSocket อาจยังต้องใช้ backend และ Caddy

### 2.2 Phase 13.2 backend-auth mode

ใช้สำหรับ security testing, staging gate และ device verification:

```bash
flutter run \\
  -d <device-id> \\
  --dart-define=USE_BACKEND_AUTH=true \\
  --dart-define=BACKEND_API_URL=http://<backend-host>:8080
```

เส้นทางหลัก:

- password register/login → backend
- password hashing/verification → server-side Argon2id และ compatibility verifier
- social provider token verification → backend JWKS verifier
- session restore/refresh/logout → backend JWT/refresh-session path
- actor identity → backend-derived identity เท่านั้น

`AppConfig.useBackendAuth` ยังคงมีค่า default เป็น `true` เพื่อป้องกันไม่ให้ release build เผลอใช้ legacy path

## 3. การลงทะเบียน user ใหม่

### 3.1 ลงทะเบียนผ่าน Backend Auth — path ที่ต้องใช้สำหรับ security gate

เมื่อ `USE_BACKEND_AUTH=true`:

1. UI ส่งข้อมูลไป `POST /api/auth/register`
2. Backend hash password ด้วย Argon2id
3. Backend บันทึก user และออก access/refresh token
4. User ใหม่สามารถ login ต่อด้วย Backend Auth ได้

ตรวจสอบโดยไม่ดึงหรือแสดง `password_hash`:

```sql
select username, password_algo, is_active, requires_password_reset
from public.users
where username = '<test-username>';
```

คาดหวัง `password_algo = 'argon2id'`

### 3.2 ลงทะเบียนผ่าน direct mode — compatibility เท่านั้น

เมื่อ `USE_BACKEND_AUTH=false`:

1. UI คำนวณ legacy SHA-256 ที่ client
2. Client insert เข้า `public.users` ผ่าน Supabase
3. User จะอยู่ใน legacy compatibility path

ห้ามใช้ path นี้กับ production หรือข้อมูลที่ใช้เป็นหลักฐานว่า Phase 13.2 security gate ผ่าน

## 4. ข้อจำกัดที่ต้องจำ

- Legacy direct password login รองรับเฉพาะแถวที่มี `password_algo = 'sha256'`
- User ที่เป็น `argon2id` ต้อง login ผ่าน Backend Auth
- User ที่มี `password_algo = null` เป็น social-only หรือยังไม่มี password
- ห้ามลด Argon2id กลับเป็น SHA-256 เพื่อให้ direct mode ผ่าน
- ห้าม select หรือ log `password_hash` จาก client
- ห้ามเพิ่ม fallback จาก direct mode ไป backend แบบเงียบ ๆ เพราะจะทำให้ผลทดสอบและ security boundary ไม่ชัดเจน
- `USE_BACKEND_AUTH=false` ไม่ได้ปิด local API, WebSocket หรือ sync ทั้งหมด; ฟีเจอร์เหล่านั้นอาจยังต้องใช้ backend

## 5. Coexistence matrix ระหว่าง Phase 13.3

การเลือกแนวทาง **Security-first staged rollout** ไม่ได้ revoke direct Supabase auth ทันที แต่จำกัด direct mode ให้เป็น UI/Supabase compatibility path เท่านั้น:

| ความสามารถ | `USE_BACKEND_AUTH=false` | `USE_BACKEND_AUTH=true` |
|---|---|---|
| Direct Supabase login/register/social | อนุญาตเฉพาะ development/testing | ไม่ใช่ path หลัก |
| Strict protected HTTP | ไม่รับรอง; อาจถูกปฏิเสธด้วย `401` | ใช้ verified Backend Bearer JWT |
| Private WebSocket connection/room | ไม่รับรอง; ใช้ได้เฉพาะ public/anonymous allowlist | ใช้ verified Backend access token หลัง socket/room gates |
| `x-user-id` หรือ Supabase user ID เป็น actor | ห้ามใช้เพื่อยกระดับสิทธิ์ | ห้ามใช้โดยเด็ดขาด |
| Silent fallback จาก strict backend path | ห้าม | ห้าม |
| Production/release build | ห้าม | ต้องผ่าน production gates เพิ่มเติม |

ข้อกำหนดสำคัญ:

- Direct mode ยังใช้ทดสอบ UI และ Supabase compatibility ได้ โดยไม่ต้องเปิด `websocket-server` สำหรับ authentication
- Direct mode ไม่ได้สร้าง Backend access/refresh JWT และไม่ถือเป็น verified backend identity
- Phase 13.3 strict routes และ private WebSocket rooms ต้อง fail closed เมื่อไม่มี verified Backend JWT
- Public/anonymous features อนุญาตได้เฉพาะ endpoint/event ที่อยู่ใน allowlist และห้ามนำไปใช้กับ private data
- ห้ามส่ง `x-user-id`, `userId` หรือ Supabase user ID เพื่อหลบ strict identity boundary
- ยังไม่ revoke direct Supabase auth จนกว่าจะผ่าน compatibility/cutover gate ของ Phase 13.5

### 5.1 ฟีเจอร์ที่ direct mode จะใช้ไม่ได้หลัง Phase 13.3 (ต้องใช้ `USE_BACKEND_AUTH=true`)

| ฟีเจอร์ | เหตุผล |
|---|---|
| Personal socket room `user-{id}` และ targeted emergency alert | server join room จาก verified `socket.userId` เท่านั้น; anonymous socket ไม่มี personal room |
| Private chat/room (consultation, emergency chat, fitness group) | ต้องผ่าน membership check ด้วย verified identity |
| `location-update`, `volunteer-route`, `video-interaction` แบบมี actor | payload `userId` ที่ไม่มี verified socket identity จะถูกปฏิเสธ |
| Local API ของ video/victim/consultation/watermark ที่เป็น protected route | strict route รับเฉพาะ `Authorization: Bearer <Backend JWT>` |
| Session restore/refresh ของ Backend | direct mode ไม่มี Backend access/refresh token |

สิ่งที่ direct mode ยังใช้ได้: login/register/social ผ่าน Supabase, UI ทั่วไป, Supabase read/write ตาม RLS เดิม, public video browsing/viewer-count และ endpoint/event ที่อยู่ใน public allowlist

**ข้อควรระวังเรื่อง fallback:** เมื่อ Local API ตอบ `401/403` ให้ถือเป็น auth error และ fail closed — ห้าม fallback ไปเขียน Supabase แทน (มิฉะนั้นจะเกิด data split Local/Cloud และ bypass strict path)

## 6. การย้ายกลับไป Backend Auth

เมื่อพร้อมเปิดใช้ Phase 13.2 เป็น path หลัก:

1. ใช้ `USE_BACKEND_AUTH=true` ใน development/staging
2. ทดสอบ register/login/refresh/logout/session restore
3. ยืนยัน Google/Apple provider verification ตาม entitlement และ credentials ที่มี
4. monitor client เก่าที่ใช้ direct `password_hash` query
5. ปิด B2 และ revoke สิทธิ์/เส้นทาง direct ตาม compatibility plan
6. ตรวจ canary, rollback, audit และ minimum-version policy
7. กำหนดวัน revoke legacy path อย่างเป็นทางการ

ห้ามลบ backend implementation, migrations หรือ audit/session logic ระหว่าง temporary window

## 7. Test matrix

| กรณีทดสอบ | โหมด | ผลที่คาดหวัง |
|---|---|---|
| Existing `sha256` password user | direct | login ได้ถ้า credential ตรง |
| Existing `argon2id` password user | direct | ไม่รองรับ; ต้องใช้ backend |
| Existing `argon2id` password user | backend | login ผ่านเมื่อ backend พร้อม |
| New registration | direct | สร้าง legacy SHA-256 user; compatibility only |
| New registration | backend | สร้าง Argon2id user; security path |
| Google social login | direct | ใช้ legacy social path |
| Google social login | backend | token verify ผ่าน backend JWKS |
| Session restore | direct | ไม่มี Phase 13.2 JWT restore; เริ่มเป็น anonymous ได้ |
| Session restore | backend | restore ผ่าน access/refresh session |

## 8. Production guard

`USE_BACKEND_AUTH=false` ห้ามใช้ใน:

- release build
- production
- staging security gate
- device verification ที่ใช้รับรอง Phase 13.2
- การประเมินว่า password/session identity boundary พร้อมใช้งานจริง

ก่อน production ต้องผ่าน production OTP/reset policy, secret management, provider/account review, cost approval, canary, monitoring, rollback และการปิด legacy direct mutation/auth paths ตาม `Match_Sport_PLAN.md`
