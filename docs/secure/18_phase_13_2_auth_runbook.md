# Phase 13.2 — Backend Auth Runbook

> **Status:** Implemented + local E2E passed + **device-verified บน Android (2026-09-06)** — **ยังไม่ production rollout**
> **Owner:** Backend/DevOps
> **อ้างอิง:** `docs/plans/Match_Sport_PLAN.md` หัวข้อ "Phase 13.2 — Implementation status (2026-09-06)"

---

## 1. สรุปสถานะ gate

| รายการ | สถานะ |
|---|---|
| Migration `audit_logs` + `auth_user_grants` | ✅ applied บน Supabase hosted |
| Backend auth routes (register/login/refresh/logout/me/sessions) | ✅ E2E 31/31 |
| Refresh rotation (parallel idempotent, reuse → revoke family) | ✅ ทดสอบแล้ว |
| `SUPABASE_JWT_SECRET` จริง + PostgREST live check | ✅ ตอบ 200 |
| Social provider verification | ✅ **Google device-verified ครบทั้ง Android + iOS** (`POST /api/auth/social/google` → 200 ทั้งสอง platform); ⚠️ **Apple E2E บน device ถูกบล็อกโดย free account** — Xcode: *"Personal development teams... do not support the Sign In with Apple capability"* → ต้อง paid Apple Developer ($99/ปี) → production-readiness blocker; server-side Apple JWKS verify พร้อม+test แล้ว |
| Flutter switch (login/register/social → Backend) | ✅ implement + tests ผ่าน — `useBackendAuth` default true |
| Production OTP provider | ⏸️ dev/staging ใช้ console mock — production blocker |
| B2 residual (client-side `password_hash` query) | ⚠️ โค้ดใหม่ผ่าน backend แล้ว; ยังต้อง monitor client เก่าแล้ว revoke (step 3–4) |

**Gate 13.2 ผ่านเฉพาะระดับ local E2E — ห้ามเคลม production-ready**

### Free-only policy

- Development/staging ทำเฉพาะงานที่ไม่มีค่าใช้จ่ายเพิ่ม: backend auth, Flutter switch, Google/Apple verification ผ่าน public keys/JWKS, PostgREST token, existing Redis/DB และ automated tests
- ห้ามผูก paid OTP/SMS, ส่ง SMS จริง, ใช้ paid quota, เปิด free trial ที่ auto-renew หรือสร้าง resource ที่คิดเงินโดยไม่ได้รับอนุมัติ
- ใช้ console OTP mock และ local/provider fixtures ต่อได้ใน dev/staging; ห้ามเปิด mock นี้ใน production
- Google/Apple verification code ทำและทดสอบได้โดยไม่ซื้อ service ใหม่; สถานะ Apple Developer membership/team และ provider terms/quota ต้องตรวจอีกครั้งก่อน production
- **Free-only gate = development/staging completion เท่านั้น**; production readiness ต้องมี OTP provider/reset channel, secret management, provider/account review และ cost approval แยกต่างหาก

### Social verification (lib/social.js) — วิธีตั้งค่าให้ใช้งานจริง

- `GOOGLE_CLIENT_ID` = OAuth 2.0 client ID (Web/Server type) จาก Google Cloud Console — ใช้เป็น `aud` ของ ID token; Flutter ฝั่งต้องตั้ง `serverClientId` เดียวกันบน `GoogleSignIn` เพื่อให้ได้ `idToken`
- `APPLE_BUNDLE_ID` = bundle identifier ของแอป (เช่น `com.sheserved.app`) — ใช้เป็น `aud` ของ identity token; ต้องเปิด Sign in with Apple capability + nonce ใน Flutter
- Facebook/LINE/TikTok ยัง 501 fail-closed — รอ credentials/requirement ที่อนุมัติ
- จุดที่ verify: RS256-only, known `kid`, `iss`/`aud`/`exp`, nonce (Google as-is / Apple SHA-256), JWKS cache 1 ชม.

---

## 2. Environment variables ที่ต้องมี (`websocket-server/.env`)

| Variable | ความหมาย | ข้อกำหนด |
|---|---|---|
| `JWT_ACTIVE_KID` / `JWT_ACTIVE_SECRET` | key ปัจจุบันสำหรับ sign access token | secret ≥32 chars |
| `JWT_PREVIOUS_KID` / `JWT_PREVIOUS_SECRET` | key รอ rotation | ว่างได้ถ้ายังไม่เคย rotate |
| `JWT_ISSUER` / `JWT_AUDIENCE` | iss/aud ที่ verify | ต้องตรงกันทุก env |
| `ACCESS_TTL` / `REFRESH_TTL` | TTL หลัก (วินาที) | per-role override ได้ |
| `SUPABASE_JWT_SECRET` | sign PostgREST token (TTL ≤5 นาที) | **ค่าจริงจาก Dashboard → Settings → API → JWT Secret** — ✅ แทนที่แล้ว (ห้าม commit/log) |
| `MIN_APP_VERSION` / `MIN_APP_VERSION_ENFORCE` | force-update policy | enforce → ตอบ `426` + `x-force-update` |
| `REFRESH_GRACE_SECONDS` | grace ของ refresh reuse | default 60 |
| `ARGON2_TIME_COST` / `ARGON2_MEMORY_COST` / `ARGON2_PARALLELISM` | tuning Argon2id | bcryptjs cost 12 เป็น fallback |
| `POSTGREST_TOKEN_TTL` | TTL PostgREST token | ≤300 วินาที |
| `AUTH_RATE_LIMIT_MAX` | override rate limit dev/E2E | **production คง 5 req/min — ห้ามตั้งสูงใน prod** |
| `SUPABASE_DB_*` | pooler credentials (Phase 13.1) | ใช้ transaction pooler `:6543` + user `postgres.<project-ref>` |
| `GOOGLE_CLIENT_IDS` | Google client IDs เพิ่มเติมที่ยอมรับเป็น `aud` (comma-separated) | **จำเป็นสำหรับ iOS** — Google คืน `aud` = iOS client ID แม้ตั้ง serverClientId; ใส่ iOS client ID จาก `Info.plist` (`GIDClientID`) |

ตรวจ placeholder ทั้งหมดก่อน production ผ่าน `config/validate-env.js` (run อัตโนมัติตอน server start)

---

## 3. การรันระบบ (dev/staging)

```bash
cd websocket-server
node server.js                 # auth API พร้อมที่ /api/auth/*
node scripts/audit-worker.js   # worker ส่ง audit_events → audit_logs (รันแยก process)
```

- `audit-worker` ใช้ role `sheserved_worker` เท่านั้น — ห้ามถือ service_role
- `sheserved_app` มีสิทธิ์บน `users` เฉพาะ INSERT/SELECT + column-scoped UPDATE (password columns) และห้าม UPDATE/DELETE บน `audit_logs`

---

## 4. Smoke test หลัง deploy/เปลี่ยน config

```bash
cd websocket-server
node scripts/test-phase-13-2-auth.js      # unit/integration (JWT, password, session, audit)
node scripts/e2e-phase-13-2-gate.js       # E2E gate — ต้อง 31/31 ผ่าน
```

PostgREST token live check (ไม่พิมพ์ secret):

```bash
node -e "require('dotenv').config(); const {mintPostgrestToken}=require('./lib/postgrest-token'); \
  const t=mintPostgrestToken({userId:'<test-user-uuid>'}); \
  fetch(process.env.SUPABASE_URL+'/rest/v1/users?select=id&limit=1', \
    {headers:{apikey:process.env.SUPABASE_ANON_KEY,Authorization:'Bearer '+t}}) \
  .then(r=>console.log('PostgREST:',r.status))"
```

คาดหวัง `200`; ถ้า `401` → secret ผิดหรือไม่ตรง project

---

## 5. Rollback / ข้อควรระวัง

- ปิด auth path ชั่วคราวได้ด้วยการ unmount `/api/auth/*` ใน `server.js` — แต่ **อย่า** revert migration grants ถ้ามีผู้ใช้ลงทะเบียนผ่าน path ใหม่แล้ว
- ห้ามลบ `password_hash` compat logic (SHA-256 + bcrypt fallback) ก่อนครบ 90 วันหลัง password cutover
- Refresh reuse หลัง grace จะ revoke ทั้ง family โดยออกแบบ — ไม่ใช่ bug
- `AUTH_RATE_LIMIT_MAX` ใน dev ตั้งสูงเพื่อ E2E — ตรวจว่าไม่ถูก copy ไป production
- ห้ามเพิ่ม log ที่มี password, raw refresh/access token, OTP หรือ signing key — audit redaction อยู่ที่ `lib/audit.js`

---

## 6. งานที่เหลือก่อนปิด free-only development/staging scope

1. **ตั้งค่าจริง — Google เสร็จ + เทสจริงบน device แล้ว (2026-09-06):** OAuth clients ครบ 3 type ใน GCP (Web `…7ri` → `GOOGLE_CLIENT_ID`/dart-define; Android `…7gu` ผูก `com.sheserved.app`+SHA-1 — ไม่ต้องใส่ repo; iOS `…qdeg` → `GIDClientID`+reversed URL scheme ใน `Info.plist`) + Flutter `serverClientId` ผ่าน `--dart-define=GOOGLE_SERVER_CLIENT_ID`; **Apple** — `APPLE_BUNDLE_ID=com.sheserved.app` ใน `.env` แล้ว แต่ **เปิด entitlement ไม่ได้กับ free/personal team** (Xcode ปฏิเสธ *"Personal development teams... do not support the Sign In with Apple capability"*) → รอ paid Apple Developer ($99/ปี) ก่อนเทส E2E บน device; `Runner.entitlements` ถูก revert กลับเหลือ HealthKit เท่านั้นเพื่อให้ build/install ทำงานได้
2. **ปิด B2** — revoke direct `password_hash` query + สิทธิ์ anon read บน `users` หลัง monitor ว่าไม่มี client เก่าค้าง (compatibility step 3–4)
3. **Facebook/LINE/TikTok verification** — ยัง 501; implement เมื่อมี requirement/credentials ที่อนุมัติ
4. **13.3 preparation/enforcement ใน staging** — ทดสอบ Bearer/JWT, socket auth, room membership และ `x-user-id` rejection ด้วย test clients โดยไม่เปิด production enforcement ก่อน compatibility/rollback review

## 7. Production-readiness blockers ที่เลื่อนไปแผนอนาคต

1. **Production OTP/reset channel** — แทน console mock + ปิด `useConsoleOtp` ใน release; ห้ามส่ง SMS จริงใน free-only scope
2. **90-day forced-reset job** — ผู้ใช้ที่ยังไม่ `argon2id` หลัง cutover ต้อง reset ผ่าน OTP/provider ที่อนุมัติ
3. **Production secrets** — ย้ายจาก `.env` ไป secret manager ตาม `secret_rotation_runbook.md` และตรวจค่าใช้จ่ายก่อนเปิดใช้
4. **Provider/account/quota review** — ตรวจ Apple Developer membership/team entitlement และ terms/quota ของ provider ก่อน production social login — **ยืนยันแล้ว (2026-09-06) ว่า free/personal team เปิด Sign in with Apple ไม่ได้ → ต้อง paid membership ($99/ปี) + อนุมัติงบก่อน**
5. **Production rollout** — canary, minimum-version enforcement, monitoring, rollback และ cost approval ต้องผ่านแยกจาก free-only gate

---

## 8. Evidence

- E2E gate: `websocket-server/scripts/e2e-phase-13-2-gate.js` → **37/37 passed** (2026-09-06, เพิ่ม 6 social fail-closed tests)
- Unit/integration: `websocket-server/scripts/test-phase-13-2-auth.js` → **32/32 passed** (เพิ่ม 13 social JWKS tests + 1 multi-audience iOS test)
- Flutter auth suite: `flutter test test/features/auth ...` → **16/16 passed**
- PostgREST live check → `200` หลังแทนที่ `SUPABASE_JWT_SECRET` จริง
- Migrations: `supabase/migrations/20260906120000_phase_13_2_audit_logs.sql`, `20260906130000_phase_13_2_auth_user_grants.sql`
- Social verification: `websocket-server/lib/social.js` (Google/Apple JWKS, RS256, iss/aud/exp/nonce, cache 1 ชม.)
- **Device-verified (2026-09-06, Android ผ่าน Caddy :8080):** `POST /api/auth/logout` → 200 (session revoked), `POST /api/auth/social/google` → 200 — `idToken` RS256 verify ผ่าน Google JWKS → link เข้า user เดิม (`926b174a…`, ไม่สร้างซ้ำ); auth calls ส่ง `x-app-version: 1.0.0` ทุก request
- **Device-verified (2026-09-06, iOS iPhone 14 Pro Max):** email/password login ผ่าน backend สำเร็จ (`AuthService: User logged in - derfby`), session restore + logout ผ่าน backend, **Google Sign-In ผ่าน backend สำเร็จ** (link เข้า user เดิม `926b174a…` ตรงกับ Android), `Local DB connected` หลัง iPhone เข้า Wi-Fi เดียวกับ Mac
- **iOS Google `aud` fix (2026-09-06):** บน iOS Google คืน `idToken` ที่ `aud` = **iOS client ID** (ไม่ใช่ Web client เหมือน Android) → เพิ่ม env `GOOGLE_CLIENT_IDS` (comma-separated extra audiences, ใส่ iOS client) + `verifyGoogleIdToken` รับ `extraClientIds`; foreign `aud` ยังถูก reject (test ยืนยัน) → unit **32/32**
- **Apple social — E2E บน device ยังทำไม่ได้กับ free account:** error `AuthorizationError 1000` (ไม่มี entitlement) → เพิ่ม `com.apple.developer.applesignin` แล้ว Xcode ปฏิเสธ signing (*"Personal development teams... do not support the Sign In with Apple capability"*) → revert entitlement; server-side Apple JWKS verify (lib/social.js) พร้อม + test แล้ว; **ต้อง paid Apple Developer + อนุมัติงบ** ก่อน device E2E/production
- **Bring-up issues ที่พบและแก้ (อ้างอิงตอนเปลี่ยนเครื่อง/เครือข่าย):** ① local Postgres ไม่รัน (stale `postmaster.pid`) → legacy endpoints 503/500 — start ด้วย `pg_ctl -D /opt/homebrew/var/postgresql@14`; ② server process เก่าค้าง `:3000` → `EADDRINUSE` และ env เก่าไม่มี `GOOGLE_CLIENT_ID` — kill ก่อน `npm run dev`; ③ `MIN_APP_VERSION_ENFORCE=false` ใน dev (advertise-only) จนกว่า client ทุก path จะส่ง `x-app-version`; ④ `AuthenticatedHttpClient` ส่ง `x-app-version` ทุก request แล้ว
- Flutter switch: `AppConfig.useBackendAuth`/`backendApiUrl`, `AuthenticatedHttpClient` (register/socialLogin/getMe/restoreSession), `UserRepository` branch, `SocialAuthService` ส่ง providerToken, `AuthService.restoreSession`
- Fitness repository ยังไม่เปลี่ยน path (ตามแผน)
