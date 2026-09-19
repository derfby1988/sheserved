# Phase 13.3 — Preflight Inventory & Rollout Baseline

> **สถานะ:** P0 preflight record — สร้างตาม Match_Sport_PLAN Phase 13.3 ขั้นที่ 1
> **วันที่:** 2026-09-19
> **ขอบเขต:** websocket-server (Express + Socket.IO), Flutter client baseline
> **วัตถุประสงค์:** identity-contract verification, HTTP/socket surface inventory,
> public allowlist, compatibility baseline, rollback unit — เป็น input ของทุก wave

---

## 1. Identity Contract Verification (P0-1 ข้อ 1)

ตรวจแล้วว่า component ทั้งหมดใช้ identity contract เดียวกัน:

| Component | สถานะ | หมายเหตุ |
|---|---|---|
| `lib/jwt.js` | ✅ | HS256 เท่านั้น, kid allowlist (active/previous), iss/aud/exp verified, `typ` ∈ {access, refresh}; ไม่ log token |
| `middleware/auth.js` `verifyToken` | ✅ | JWT → gateway pool verify users.is_active + sessions.revoked_at; legacy `x-user-id` → local pool (compat window เท่านั้น); แนบ `req.userId/userRole/sessionId/identitySource` |
| `db/supabase-gateway-pool.js` | ✅ | `SET LOCAL ROLE sheserved_app` + `app.user_id/session_id/role` GUCs; UUID assert; ไม่มี service_role ใน request path |
| `lib/session.js` | ✅ | revoke ผ่าน `public.sessions.revoked_at` — ตรงกับ query ใน verifyToken |
| Session-revocation query | ✅ สอดคล้อง | auth.js อ่าน `public.sessions.revoked_at` ผ่าน gateway tx เดียวกับ user check (atomic) |

### Findings (ต้องแก้ใน wave ถัดไป)

| # | Finding | ที่อยู่ | Wave ที่แก้ |
|---|---|---|---|
| F-1 | **role column mismatch** — socket `io.use` อ่าน `users.role` (coarse: consumer/provider/admin) แต่ HTTP + JWT ใช้ `user_category_id` (fine-grained, source of JWT role ตาม migration `20260912100000`) → `socket.userRole` ไม่ตรง `req.userRole` | `server.js:169-194` | Step 4 (socket-auth.js ใช้ `user_category_id`) |
| F-2 | **socket handshake ไม่ verify signature** — `io.use` decode JWT payload โดยไม่ verify + เชื่อ `auth.userId`/`x-user-id` ตรงๆ → impersonate ได้ทุกคน | `server.js:124-207` | Step 4 |
| F-3 | **`user-connected` ตั้ง `socket.userId` จาก payload** — anonymous socket emit `user-connected{userId:X}` แล้วกลายเป็น X ได้ + เข้า `user-{X}` room | `server.js:835,840` | Step 4 |
| F-4 | **`subscribe-user` เข้า `user-{id}` ของใครก็ได้** — ฟัง emergency-notification / rescue-incoming / donation status / app notifications ของคนอื่น | `server.js:1050-1054` | Step 4 |
| F-5 | **pool=null ⇒ ไม่มี verifyToken เลย** — `app.use('/api', verifyToken(pool))` อยู่ใน `if(pool)` → เมื่อ `USE_DATABASE=false` inline endpoints ทั้งหมดรันแบบไม่มี identity context | `server.js:367-384` | Step 5 (guard note — dev-only path) |
| F-6 | `send-emergency-message`, `save-ui-preference`, `join-emergency-chat` เชื่อ payload `userId` เต็มจำนวน (persist sender_id / preference / presence ปลอมได้) | `server.js:1728-1755,1764` | Step 5 |
| F-7 | `admin-release-escrow`, `donate-closure-vote`, `donation-*` events ไม่มี role/actor check เทียบ verified identity | `server.js:1648-1727` | Step 5 |

---

## 2. HTTP Surface Inventory (P0-1 ข้อ 2)

### 2.1 Mounted routers

| Mount | Router | Identity | หมายเหตุ |
|---|---|---|---|
| `/api/auth/*` | `routes/auth.js` | login/register/refresh/social = public; `/me`, `/logout-all`, `/sessions` ผ่าน verifyToken mount | Phase 13.2 ✅ |
| `/api/consultations` | `routes/consultation.js` | verifyToken mount | pilot HTTP (Step 3) |
| `/api/admin` | `routes/admin.js` | verifyToken mount | ใน `if(pool)` |
| `/api/videos` | `routes/video.js` | verifyToken mount; per-route `requireAuth` บน mutation | ใน `if(pool)`; GET reads public |
| `/api/incidents`, `/api/victims` | `routes/victims.js` | verifyToken mount; per-route `requireAuth` | ใน `if(pool)` |
| `/api/notifications*`, `/api/profession-change` | inline (server.js:401-473) | verifyToken per-route | ✅ ใช้ `req.userId` เท่านั้นแล้ว |

### 2.2 Inline endpoints (server.js) — ผ่าน `app.use('/api', verifyToken)` เมื่อ pool มีอยู่

| Endpoint | Auth state | Trust issue |
|---|---|---|
| `GET /api/videos/:id/chat` (+`/archived`) | anonymous OK | public read — allowlist |
| `POST /api/chat/archive/:videoId` | anonymous OK | ควร strict (Step 5) |
| `GET/POST /api/users/:userId/preferences*` | anonymous OK | **BOLA** — param userId เชื่อตรงๆ |
| `POST /api/users`, `GET/PUT /api/users/:id` | anonymous OK | **BOLA สูงสุด** — PUT แก้ user ใครก็ได้ |
| `GET /api/locations/:userId` | anonymous OK | BOLA — ตำแหน่ง user คนอื่น |
| `POST /api/applications*` (submit/approve/reject) | anonymous OK | approve/reject = admin op แต่ไม่มี auth |
| `GET /api/applications*` | anonymous OK | PII list |
| `GET /api/professions*` | anonymous OK | public read — allowlist |
| `POST /api/emergency-health/*`, `GET .../settings/:userId`, `/dead-man/:userId` | anonymous OK | BOLA + health data |
| `POST /api/*/sync` (professions, registration_field_configs, users) | anonymous OK | bulk write — ควร strict/admin |
| `GET /api/sync/status`, `/health*` | public | ops read-only — allowlist |

> **ข้อสังเกต:** ทุก endpoint หลัง `server.js:377` ผ่าน verifyToken → forged JWT ถูก 401 แล้ววันนี้
> แต่ anonymous + `x-user-id` ยังเดินต่อได้ตาม compatibility window — งานของ Step 2/5 คือ
> opt-in strict + actor-match ทีละ wave

### 2.3 Public allowlist (P0-1 ข้อ 3) — HTTP

อนุญาต anonymous เฉพาะ:
- `POST /api/auth/{login,register,refresh,social/:provider}`
- `GET /api/videos` + `GET /api/videos/:id*` reads (list, detail, gallery, interactions read, likes, gps-tracks, responders, chat history)
- `GET /api/incidents/:id/victims`, `GET /api/incidents/:id/triage-summary` (public triage read)
- `GET /api/professions*`, `GET /api/sync/status`, `GET /health*`
- static: `/temp/videos`, `/uploads/thumbnails`, `/uploads/watermarks`

ทุก mutation และ private read อื่น = ไม่ใช่ public → candidate ของ STRICT_AUTH_ROUTES

### 2.4 Socket.IO event inventory (25 events)

| Event | ปัจจุบัน | Trust class (เป้าหมาย) |
|---|---|---|
| `user-connected` | ตั้ง socket.userId จาก payload (F-3) | **verified-only** |
| `subscribe-user`/`unsubscribe-user` | เข้า user-{id} ใครก็ได้ (F-4) | **verified-only** (เฉพาะตัวเอง) |
| `join-room`/`leave-room` | เข้า room-* ใครก็ได้ | public เฉพาะ `video-*`; อื่นๆ verified + membership (Step 6-7) |
| `video-interaction`, `like-toggled` | mismatch-check เทียบ socket.userId | identity-required (legacy OK ช่วง compat) |
| `location-update` | mismatch-check | identity-required |
| `volunteer-route`, `request-yield-way-notification` | mismatch-check | identity-required |
| `emergency-alert` | เชื่อ payload userId | identity-required (sender = socket.userId) |
| `rescue-status-update` | mismatch + owner check ใน DB | **verified-only** (strict candidate) |
| `join/leave/send-emergency-message` | เชื่อ payload userId (F-6) | identity-required + membership (Step 7) |
| `donation-*`, `donate-closure-vote`, `admin-release-escrow` | ไม่มี actor check (F-7) | **verified-only** + role check |
| `fitness_booking_status` | actor match เทียบ socket.userId | verified-only |
| `application-review-notification` | ต้อง socket.userRole='admin' | **verified-only** + admin |
| `save-ui-preference` | เชื่อ payload userId (F-6) | identity-required |
| `archive-chat` | ไม่มี check | verified + reporter/admin |
| `disconnect`, `viewer-count` (emit) | system | n/a |

### 2.5 Public allowlist — Socket

Anonymous socket เข้าร่วมได้เฉพาะ: `join-room`/`leave-room` กับ `video-*`, รับ `viewer-count` —
ตรงกับแผน "join-room เฉพาะ video-*, viewer-count, public video/list endpoints"

---

## 3. Client Baseline (P0-1 ข้อ 2 — x-user-id/direct auth)

### Flutter callers ที่ส่ง `x-user-id` วันนี้ (ตรง pilot list ของแผน)

| Repository | จุด | Endpoint |
|---|---|---|
| `consultation_repository.dart` | :69 | `/api/consultations` |
| `victim_repository.dart` | :15 | `/api/incidents|victims` |
| `watermark_repository.dart` | :67, :112 | `/api/admin/watermarks` |
| `video_repository.dart` | :382, :615, :732, :792, :986, :1096 (+fallback Supabase) | `/api/videos/*` |

### Socket client

`websocket_service.connect({userId, authToken})` — signature รองรับ token แล้วแต่
**caller ทุกจุดส่งแค่ userId** (`home_page.dart:391`, `emergency_websocket_logic.dart:9`,
`emergency_reporting_logic.dart:317`) → Step 4 ส่ง `AuthenticatedHttpClient().accessToken`

### นโยบายที่ต้องคงไว้ระหว่าง rollout

- `x-user-id` ยังใช้ได้กับ route/event ที่ยังไม่เข้า strict list (compat window ถึง 13.5)
- ห้ามขยายขอบเขต: endpoint/event ใหม่ต้อง verified identity เท่านั้น
- ห้าม revoke direct/legacy auth ก่อน Phase 13.5

---

## 4. Rollback Unit (P0-1 ข้อ 5)

| Flag | ค่าเริ่มต้น | หน่วย rollback |
|---|---|---|
| `STRICT_AUTH_ROUTES` | unset (compat) | ลบ prefix ออกจาก list = route นั้นกลับเข้า compat ทันที ไม่ต้อง deploy |
| `STRICT_SOCKET_AUTH` | `false` | `false` = socket กลับรับ legacy handshake ทั้งหมด |
| `STRICT_SOCKET_EVENTS` | unset | ลบ event ออกจาก list = event นั้นรับ identity-required (legacy OK) อีกครั้ง |

Implementation: `config/rollout-flags.js` (เพิ่มใน wave นี้) — parse ครั้งเดียวตอน boot,
restart เพื่อเปลี่ยนค่า (ตามข้อห้าม "ห้ามเปิด strict enforcement มากกว่าหนึ่ง wave พร้อมกัน"
การเปลี่ยนค่าจึงต้องเป็น ops action ที่ตั้งใจ)

### Rollback note

- ทุก wave deploy ได้โดยไม่เปลี่ยน flag → พฤติกรรมเดิม 100%
- เปิด strict ผิด route → unset flag + restart → กลับ compat ใน <1 restart
- socket-auth.js มี bug → `STRICT_SOCKET_AUTH=false` คืน legacy io.use path ทั้งหมด
  (เก็บ code path เดิมไว้ใน else-branch จนถึง 13.5)
- ห้ามลบ legacy path จนกว่า Phase 13.5 จะผ่าน gate

---

## 5. P0-1 Gate Checklist

- [x] pool/role assumptions verified (gateway pool = `sheserved_app`, JWT path; local pool = legacy only)
- [x] test harness: `scripts/test-phase-13-3-auth.js` — 18 tests (forged/expired/revoked/inactive/actor-mismatch/anonymous/strict/flags) ผ่านทั้งหมด
- [x] public allowlist กำหนดชัดเจน (§2.3, §2.5)
- [x] compatibility baseline บันทึก (§3)
- [x] rollback unit + rollback note (§4)
- [ ] users table consistency local↔Supabase — *pending runtime check* (users อาจ drift ระหว่าง local mirror กับ Supabase source of truth; legacy path ใช้ local — จุดเสี่ยงที่ต้องยืนยันก่อน 13.5, ไม่ block 13.3 waves)

**Gate → Step 2 (HTTP identity contract): พร้อมดำเนินการ**

---

## 6. Implementation Progress (2026-09-19, continued)

### Step 2 — HTTP identity contract ✅
- `strictRouteGuard()` + `whenStrictRoute()` + `assertActorMatches()` in `middleware/auth.js`
- `STRICT_AUTH_ROUTES` opt-in pilot; strict routes reject legacy `x-user-id` (401) and actor mismatch (403)
- Pilot routes: preferences, emergency-health, user update, locations, application approve/reject
- ⚠️ Fix: `isStrictRoute` now reads `req.originalUrl` — `req.path` is stripped inside mounted routers (was silently non-strict)

### Step 3 — Flutter HTTP pilot ✅
- `AuthenticatedHttpClient`: + `PATCH`, + `sendMultipart` (rebuildable request for refresh-retry), + `backendApiUrl` getter; `configure()` now unconditional in `main.dart` (both auth modes)
- `consultation_repository.dart` — Bearer path; **fixed live bug**: previously sent Supabase JWT as Bearer → always 401 under backend auth
- `victim_repository.dart` — all 8 methods via client
- `watermark_repository.dart` — 3 sites incl. multipart
- `video_repository.dart` — 9 sites; `acceptIncident`/`addInteraction` now **fail closed on 401/403** (no silent Supabase dual-write on auth error)
- `x-user-id` kept as compat fallback on all migrated calls (server prefers Bearer)

### Step 4 — Socket connection auth ✅
- New `middleware/socket-auth.js`: verified JWT only = trusted actor (`identitySource='jwt'`); legacy `auth.userId`/`x-user-id` = `'legacy'` compat; else `'anonymous'`
- Fixes F-1 (role uses `user_category_id`), F-2 (signature now verified — no more payload decode), F-3 (`user-connected` binds verified `socket.userId`), F-4 (`subscribe-user` strict-gated + self-only under flag)
- `STRICT_SOCKET_AUTH` + `STRICT_SOCKET_EVENTS` flags wired
- Flutter: 3 `connect()` callers pass `authToken: AuthenticatedHttpClient.instance.accessToken`
- Harness extended: 27/27 tests (incl. forged-token socket, revoked session, strict handshake reject)

### Step 5 — Remaining HTTP/BOLA + event actors ✅
- **Route extraction**: 9 new files — `routes/{notifications,chat-api,health,emergency-health,professions,users,applications,locations,sync}.js`; `services/chat-archive-service.js`; server.js 2840→1830 lines
- **Event actors**: `socket.userId` only for `video-interaction`, `location-update` (removed auto-create-Guest-user on forged id), `volunteer-route`, `emergency-alert`, `rescue-status-update`, `save-ui-preference`, `send-emergency-message`, `join/leave-emergency-chat`, `donate-closure-vote`, `admin-release-escrow` (+server-side role check), `archive-chat` (+admin), `donation-request-status-updated`, `donation-closed`; payload `userId` mismatch → `authz.denied` event
- **Middleware identity migration**: `rate-limiter` (verified userId or IP — raw `x-user-id` no longer keys buckets), `idempotency` (`req.userId` first), `request-context` + `error-handler` (no raw `x-user-id` in logs)
- `emergency-health` writes now bind `req.userId` via `verifyToken` (compat: body fallback)
- `applications` approve/reject: `reviewedBy` = bound identity; submit uses `req.userId || body.userId`

### Known follow-ups (recorded, not blocking)
- `subscribe-user` strict mode = self-only → cross-user location sharing needs dedicated `location-{id}` channel (Step 6/7 design)
- `fitness_booking_status` recipient list comes from payload (business data, sender verified) — review in Step 7 membership model
- Users local↔Supabase drift still open (P0 gate note)
