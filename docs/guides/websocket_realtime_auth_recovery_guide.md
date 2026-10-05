# WebSocket Realtime Auth Recovery — วิเคราะห์สาเหตุและแนวทางแก้ระยะยาว

> **Status:** Root cause verified; client and server fixes implemented in the worktree (2026-10-05) — unit tests pass; on-device expiry-cycle verification pending
> **Owner:** Backend/DevOps + Flutter Lead
> **ขอบเขต:** Socket.IO handshake auth, token refresh recovery, circuit breaker, observability
> **อ้างอิงแผน:** `docs/plans/VIDEO_SYSTEM_PLAN.md` §"🔧 Network & Configuration Runbook"
> (บรรทัด 290–413) — คู่มือนี้ **ไม่แก้** พฤติกรรม realtime/ภารกิจ/ตัวกรอง Phase 20 และ
> ไม่แทนที่ runbook เดิม แต่เสริมส่วน auth recovery + การเก็บ log ที่ runbook ยังไม่มี

---

## 1. อาการที่พบ

แอปยังใช้งาน HTTP API ได้ปกติ แต่ realtime ขาด และ log ขึ้นวนซ้ำตลอด session:

```
flutter: WebSocket: token refresh result=refreshed
flutter: WebSocket error: {message: Authentication failed: invalid or expired token}
flutter: WebSocket: handshake authentication rejected; refreshing tokens
flutter: WebSocket: token refresh result=refreshed
flutter: WebSocket error: {message: Authentication failed: invalid or expired token}
...
```

ไม่มีบรรทัด `WebSocket connected` เลยตลอด session ⇒ **handshake ไม่เคยสำเร็จ** และ
refresh token ถูก **rotate จริงทุกครั้งที่ล้ม** (ดู §2.3)

---

## 2. หลักฐานที่ยืนยันแล้ว (verified evidence)

### 2.1 ข้อความ error มาจากจุดเดียวในระบบ

ข้อความ `Authentication failed: invalid or expired token` เกิดเมื่อ `verifyAccessToken()`
ล้มเหลว (ลายเซ็น / `kid` / `iss` / `aud` / `exp` / `typ`) — ยังไม่ถึงขั้นตรวจ session ใน DB
(เช่น session revoked จะได้ `session_revoked`). Server คงข้อความทั่วไปไว้เพื่อ compatibility
แต่ส่ง stable `error.data.code` ให้ client และ log `reason` แบบ structured โดยไม่ log token
หรือ user/session id แล้ว

### 2.2 Taxonomy ของเหตุผลจริง (ทดสอบซ้ำได้)

รัน handshake ปลอม 3 แบบเข้า server จริงระหว่างสืบสวน (diagnostic ที่บันทึกไว้ใน §2.7):

| token ที่ส่ง | reason ที่ server เก็บ | ความหมาย |
|---|---|---|
| JWT ที่ `exp` ผ่านแล้ว | `Token expired` | **socket ถือ token เก่า** — ตัวที่ตรงกับ incident |
| opaque refresh token (ไม่ใช่ JWT) | `Malformed token header` | client ส่ง token ผิดชนิด |
| JWT ที่เซ็นด้วย secret อื่น | `Invalid token` | คนละ key / คนละ server |

ใน `websocket-server/server.log` (session 2026-10-03, pid 15479) พบของจริง 4 ครั้ง
ห่างกัน 4–7 วินาที — **รูปแบบ burst เดียวกับ log ของผู้ใช้** และ reason คือ
**`Token expired`**:

```
{"level":"warn",...,"msg":"[SocketAuth] token rejected: Token expired"}
```

### 2.3 ฝั่ง server mint/verify สอดคล้องกัน — ไม่ใช่บั๊กการเซ็น token

```
$ cd websocket-server && node -e "
require('dotenv').config(); const j=require('./lib/jwt');
const t=j.signAccessToken({userId:'...',role:'admin'});
console.log(j.verifyAccessToken(t).typ);"
access
```

และ handshake จริงผ่าน Caddy (:8080) ด้วย token ที่ mint จาก `.env` ปัจจุบัน **ถูกตอบรับ**
(`40{"sid":...}`) ⇒ process ที่รันอยู่ยอมรับ token ที่ตัวเองออก ⇒ **ต้นตอไม่ใช่ server**
และ `.env` ครบถ้วน (`JWT_ACTIVE_KID/SECRET`, `JWT_PREVIOUS_*`, `ISSUER`, `AUDIENCE`,
`ACCESS_TTL=900`) ⇒ `exp` ของ token ที่ mint ใหม่ = 900 วินาที ทุก role

### 2.4 loop นี้ rotate refresh token จริง (หลักฐานจาก DB)

```sql
select id, created_at, rotated_at, expires_at, ip_address, device_info
from public.sessions where user_id = '<user-id>' order by created_at desc limit 6;
```

ผลจริง: rotation เป็น **ชุดละ 3 ครั้ง** ห่างกัน ~5 วินาที
(`03:53:16 → 03:53:21 → 03:53:23`, แล้ว `04:12:32 → 04:12:38 → 04:12:43`)
ทุกแถวมาจาก `ip_address = 127.0.0.1`, `device_info.userAgent = "Dart/3.11 (dart:io)"`

- ชุดละ 3 = `_maxAuthRecoveries = 3` (`websocket_service.dart:40`) ⇒ หนึ่งรอบ breaker
- แต่ละครั้งคือ refresh token ถูก rotate + เขียน audit จริง ⇒ **token churn**
- burst ใหม่เกิดทุกครั้งที่ UI เรียก `connect()` อีก (ดู §3.2)

ใน log ชุดเดียวกันพบ `[NotificationRepo] getUnreadCount error: 429`; เป็นอาการร่วมตามเวลา
แต่ยังไม่มีหลักฐานพอยืนยันว่า socket refresh storm เป็นสาเหตุโดยตรง ต้องตรวจ rate-limit
logs/metrics แยกหลังแก้

### 2.5 หลักฐานชี้ขาด: server เห็น "token เก่า" ทุกครั้ง ขณะที่ refresh สำเร็จ

จับคู่เวลาจริงจาก server (2026-10-05, token หมดอายุ 04:27:44 UTC) — คอลัมน์ซ้ายคือ
handshake ที่เข้ามา, ขวาคือ refresh ที่สำเร็จ (จาก `public.sessions` + `audit_logs`):

| เวลา (UTC) | handshake ที่เข้ามา (`iat`) | refresh/rotate ที่สำเร็จ |
|---|---|---|
| 04:26:13.997 | `iat=04:12:44` (ยังไม่หมดอายุ) → **รับ** | – |
| 04:27:44.956 | – | rotate #1 |
| 04:27:47.955 | `iat=04:12:44` `exp=04:27:44` → **`Token expired`** | – |
| 04:27:48.099 | – | rotate #2 |
| 04:27:49.700 | `iat=04:12:44` → **`Token expired`** | – |
| 04:27:49.706 | – | rotate #3 |
| 04:27:51.250 | `iat=04:12:44` → **`Token expired`** | – |
| 04:27:51.261 | – | rotate #4 |
| 04:27:52.698 | `iat=04:12:44` → **`Token expired`** | – |
| 04:27:52+ | (ไม่มี handshake อีก — breaker หยุด) | – |

**สรุปจากตาราง:** client rotate refresh token สำเร็จ 4 ครั้ง และได้ access token ใหม่
ทุกครั้ง แต่ **handshake ทุกครั้งยังส่ง token เดิม (`iat=04:12:44`)** ⇒ ต้นตออยู่ที่ client
ไม่ยอมใช้ token ใหม่กับ socket (server ถูกต้อง)

### 2.6 หลักฐานระดับ library: `IO.io()` คืน socket เดิมพร้อม auth เดิม

ทดลองกับ `socket_io_client` 2.0.3+1 โดยตรง (สร้าง socket ใหม่ด้วย token ต่างกัน):

```
s1.auth = {userId: u, token: TOKEN_A}
s2.auth = {userId: u, token: TOKEN_A}   ← สร้างใหม่ด้วย TOKEN_B แต่ได้ TOKEN_A
identical(s1, s2) = true                ← ได้ object เดิม (ไม่ใช่ตัวใหม่)
s3.auth = {userId: u, token: TOKEN_C}   (enableForceNew)   ← แก้ได้
s4.auth = {userId: u, token: TOKEN_A}   (disableMultiplex) ← ไม่ช่วย
```

เหตุผลในโค้ด library (`socket_io_client.dart` `_lookup`):

```dart
var path = parsed.path;                                     // '' สำหรับ http://host:port
var sameNamespace = cache.containsKey(id) && cache[id].nsps.containsKey(path); // เช็ค ''
...
return io.socket(parsed.path.isEmpty ? '/' : parsed.path, opts);  // แต่ลงทะเบียนที่ '/'
```

⇒ `sameNamespace` เป็น false เสมอ → ไม่สร้าง Manager ใหม่ → ใช้ Manager ที่ cache ไว้
→ `Manager.socket('/', opts)` เจอ socket เดิมใน `nsps` จึง **คืน socket เดิมโดยไม่สนใจ
`auth` ใหม่** (`manager.dart:274-283`) ⇒ token ที่จะส่งใน handshake คือ token ของ
**socket ตัวแรกที่ถูกสร้างใน process นั้น** เท่านั้น

### 2.7 ช่องทางอ่านเหตุผลจริง (diagnostic ชั่วคราว — ลบแล้วหลังวินิจฉัย)

ระหว่างสืบสวนเคยใช้ diagnostic ชั่วคราวเขียน claims ลง `/tmp/socket-auth-diag.log`;
โค้ดและไฟล์ log ถูกลบหลังยืนยัน root cause แล้ว. **ไม่ควรนำ diagnostic นั้นกลับมาใช้** —
ปัจจุบัน server log แบบ structured มี `reason`, `code`, `kid`, `algorithm`, `tokenType`,
`iat`, `exp` และ `tokenLength` โดยไม่บันทึก raw token, user id หรือ session id (ดู §7.2).

---

## 3. กลไกการเกิด loop

### 3.1 ลำดับที่เกิดจริง

1. socket ถูกสร้างพร้อม token (socket.io **bake `auth` ไว้ตอนสร้าง socket**)
2. token หมดอายุ / ถูก invalidate ระหว่างที่ socket ยังมีชีวิต
3. handshake (หรือ handshake ซ้ำตอน reconnect) ส่ง token เก่า → server ตอบ
   `invalid or expired token`
4. client เรียก `refreshTokens()` → **สำเร็จ** (`/api/auth/refresh` ตอบ 200, rotate จริง)
5. recovery สร้าง socket ใหม่ด้วย token ใหม่ — **แต่ได้ object socket เดิมกลับมา** (D5)
   ⇒ token ใหม่ไม่เคยถูกใช้ใน handshake
6. handshake รอบถัดไปจึงยังส่ง token เก่า → กลับไปข้อ 3 (และ refresh ถูก rotate ใหม่ทุกครั้ง)

### 3.2 Defect ใน build ที่เกิด incident และสถานะหลังแก้

| # | Defect ก่อนแก้ | สถานะหลังแก้ |
|---|---|---|
| D5 (root cause) | `socket_io_client` 2.0.3+1 แคช Socket/Manager; `IO.io(url, opts)` คืน object เดิมพร้อม `auth` เดิม (§2.6) | แก้แล้ว: `SocketAuthSocketFactory` ตั้ง `enableForceNew()` และมี regression test ตรวจ `auth.token` |
| D3 | สร้าง socket โดยไม่ตั้ง `forceNew`; token ใหม่จึงไม่ถึง handshake | แก้แล้ว: ผูก `_socketAuthToken`/user id กับ socket และ dispose+rebuild เมื่อ mismatch |
| D1 | `disconnect()` reset auth recovery count ทำให้ retry จากหน้าจอเริ่ม budget ใหม่ | แก้แล้ว: disconnect ไม่ reset breaker; reset เฉพาะ connect success, auth session เปลี่ยน/ถูกล้าง หรือ `resetAuthRecovery()` ที่เรียกชัดเจน |
| D2 | เมื่อ refresh สำเร็จ handler พึ่ง `tokenChanges` listener อย่างเดียว | แก้แล้ว: auth-failure path ประสาน token listener แล้ว rebuild ด้วย token ใหม่โดยตรง |
| D4 | auth retry ใช้ delay capped แต่จำนวนครั้งไม่จำกัด | แก้แล้ว: recovery สูงสุด 3 ครั้งต่อ session ก่อน latch terminal state |
| D6 | ไม่มี refresh ก่อนหมดอายุ | แก้แล้ว: ก่อน connect/reconnect จะ refresh เมื่อ token เหลืออายุไม่เกิน 60 วินาที; `exp` ใช้เพื่อกำหนดเวลาเท่านั้น ไม่ใช้แทนการ verify |
| D7 | ไม่ track token ที่ socket ถูกสร้างด้วย และ reuse socket โดยดูแค่ `_isConnected` | แก้แล้ว: ตรวจ `_socketAuthToken`, user id และ socket connection state ก่อน reuse |

### 3.3 สาเหตุราก (ยืนยันแล้ว)

**สาเหตุรากของ incident:** `WebSocketService` เรียก `IO.io(_serverUrl, opts)` โดยไม่มี
`forceNew`; `socket_io_client` 2.0.3+1 จึงคืน **Socket object เดิมที่มี `auth` เดิม**
เมื่อ token ถูก refresh ทำให้ handshake ยังใช้ token หมดอายุ

**ตัวกระตุ้น:** access token หมดอายุ (TTL 900 วินาที) ขณะที่ socket เดิมยังมีชีวิต/กำลัง reconnect

**ตัวขยายความเสียหาย:** recovery listener ไม่ได้เปลี่ยน Socket object จริง + budget ถูก reset
ตอน disconnect + retry ไม่มีขอบเขต ⇒ refresh rotation/audit ซ้ำและเกิด `429`

**สถานะหลังแก้:** client บังคับ socket ใหม่ด้วย token ปัจจุบัน, refresh ก่อน token หมดอายุ,
จำกัด recovery และหยุดเมื่อ server ปฏิเสธ token ที่เพิ่งออก; server ส่ง stable reason code และ
มี structured log/counter โดยไม่ log raw token.

**หลักฐานยืนยัน root cause:** §2.5 (server เห็น `iat` เดิมทุกครั้ง) + §2.6 (ทดลอง `IO.io`
คืน socket เดิม)

---

## 4. ขั้นตอนตรวจซ้ำเมื่อเจออาการเดิม (1 นาที)

```bash
# 1) รัน Node โดยเก็บ structured log ไว้ตรวจย้อนหลัง
cd websocket-server && npm run dev 2>&1 | tee -a /tmp/socket-auth-server.log

# 2) เปิดแอปที่ build ด้วย --dart-define=USE_BACKEND_AUTH=true แล้วทำให้ socket เชื่อมใหม่

# 3) อ่าน reason/code ที่ server บันทึก
grep 'SocketAuth.*token rejected' /tmp/socket-auth-server.log | tail -5
```

| `error.data.code` / log reason | แนวทาง |
|---|---|
| `token_expired` | client ควร refresh 1 ครั้งและสร้าง socket ใหม่ด้วย token ใหม่; `iat` ซ้ำชี้ว่า socket ยังถือ auth snapshot เก่า |
| `malformed_token` | ตรวจว่า client ส่ง access token ไม่ใช่ refresh token |
| `invalid_signature` / `unknown_kid` | ตรวจ active/previous JWT key และยืนยันว่า API กับ Socket.IO ใช้ backend instance/config เดียวกัน |
| `session_revoked` / `user_inactive` / `user_not_found` | session/identity ถูกปฏิเสธ — client ต้องหยุด recovery และให้ผู้ใช้ login ใหม่ |
| `auth_backend_unavailable` | เป็นปัญหา backend/DB ชั่วคราว — retry จำกัดพร้อม backoff โดยไม่ rotate refresh token |

---

## 5. ผลกระทบต่อระบบย่อย

| ส่วน | ผลกระทบ |
|---|---|
| Realtime ทุกชนิด (แชทเหตุ, สถานะกู้ภัย, viewer/thumbnail, donation) | **ขาดทั้ง session** เพราะ handshake ไม่ผ่าน |
| Trending/Popular refresh (Phase 20) | กล่องยังโหลดผ่าน HTTP ได้ แต่ refresh จาก socket ไม่มา — ตัวกรองยังทำงานตามเดิม (ไม่กระทบ policy §20) |
| ภารกิจ/ผู้แจ้ง | ไม่กระทบ logic — แต่สัญญาณ realtime ไม่ถึง |
| Auth HTTP | ทำงานปกติ (refresh 200) ⇒ ผู้ใช้ไม่รู้ว่ามีปัญหา |
| DB/Redis | refresh token + audit ถูกเขียนซ้ำทุก burst (churn) |
| Rate limit | `429` ที่ notification gateway จาก retry storm |

---

## 6. หลักการของแนวทางแก้ (สำคัญ)

1. **ห้ามลดความปลอดภัย**: ไม่ fallback ไปใช้ `auth.userId`/`x-user-id` เป็น trusted actor,
   ไม่ปิด `verifyAccessToken`, ไม่ตั้ง `STRICT_SOCKET_AUTH=false` เพื่อหลบปัญหา
2. **แก้ที่ต้นเหตุ**: ทำให้ token ที่ socket ใช้ตรงกับ token ล่าสุดเสมอ + ให้ loop มีเพดาน
3. **fail-closed แต่ต้องเงียบและบอกผู้ใช้ได้**: หยุดวน + ส่งสถานะ actionable แทน retry ไม่จำกัด
4. **กระทบต่ำ**: ไม่แตะ event semantics, mission flow, Phase 20 filter, หรือโครงสร้าง payload
5. **observability ก่อน**: ทำให้เหตุผลจริงอ่านได้จาก log/metrics ก่อนแก้ เพื่อยืนยันผลหลังแก้

---

## 7. แนวทางแก้ระยะยาว

### 7.1 Client — `lib/services/websocket_service.dart` (implemented)

1. **บังคับให้ socket ใหม่รับ token ใหม่จริง (root fix)**
   - `SocketAuthSocketFactory.create()` ใช้ `.enableForceNew()`; ทดสอบแล้วว่าการสร้าง
     socket ด้วย token B ให้ object ใหม่และ `auth.token == B` (§2.6)
   - ไม่ใช้ `disableMultiplex()` เพราะทดลองแล้วไม่ช่วย
   - `_socketAuthToken` และ `_socketUserId` ผูกกับ socket จริง; ถ้า identity/token ล่าสุด
     ไม่ตรง ให้ dispose แล้วสร้างใหม่
2. **breaker latch**
   - `disconnect()` และ `resetTransportConnectionAttempts()` ไม่ reset auth recovery budget
     (emergency page เรียก transport reset อัตโนมัติ)
   - `resetConnectionAttempts()`/`resetAuthRecovery()` เป็น explicit reset สำหรับ manual retry
   - budget สูงสุด 3 ครั้ง; reset เมื่อ socket เชื่อมสำเร็จหรือ auth user/session ถูกล้าง/เปลี่ยน.
     token ใหม่อาจปลด terminal latch เพื่อ revalidate ได้ แต่ไม่ reset budget
3. **หยุดเมื่อ token ที่เพิ่งออกยังถูกปฏิเสธ**
   - track `_authRecoveryToken`; ถ้า handshake ของ token นี้ล้มอีก ให้ latch
     `_authRecoveryBlocked`, dispose socket และไม่ refresh ซ้ำ
   - retry แบบ `SocketReconnectPolicy` มีขอบเขต; `auth_backend_unavailable` retry โดยไม่
     rotate refresh token, reason ที่บ่งชี้ session/user ถูกปฏิเสธจะ logout
   - `HomePage` รับเฉพาะ terminal auth errors จาก `errorStream` แล้วแสดง SnackBar;
     transient retry ไม่รบกวนผู้ใช้ด้วยข้อความซ้ำ
4. **pre-emptive refresh**
   - `SocketAuthRecoveryPolicy` อ่าน JWT `exp` แบบ unverified เพื่อกำหนดเวลาเท่านั้น
     (ไม่ใช้ claims นี้ยืนยัน identity)
   - ถ้าเหลืออายุ ≤60 วินาทีหรืออ่าน token ไม่ได้ ให้ refresh ก่อนสร้าง/reconnect socket;
     หาก refresh unavailable จะ backoff และ retry แบบจำกัด
5. **socket reuse guard**
   - reuse ได้เฉพาะเมื่อ socket ปัจจุบันยัง connected และ user/token ตรงกัน
   - ถ้าตรง token แต่ disconnected จึงเรียก `connect()` กับ socket เดิม; ถ้า token/user
     เปลี่ยนให้ rebuild
6. **pure policy + regression tests**
   - `lib/services/socket_auth_recovery_policy.dart` แยกการตัดสินใจ reuse/rebuild/
     pre-refresh/stop และ auth failure disposition
   - `test/core/socket_auth_recovery_policy_test.dart` ทดสอบ expiry window, decision,
     retry budget และ regression ของ Socket.IO auth snapshot
7. **single-flight refresh**
   - socket auth ใช้ `AuthenticatedHttpClient.refreshTokens()` ตัวเดิม; `_handlingAuthFailure`
     กัน concurrent recovery และ token-change listener ไม่ rebuild ซ้ำระหว่าง handler ทำงาน

### 7.2 Server — observability + reason code (implemented)

1. `socket-auth.js` ใช้ `utils/logger.js` (pino) บันทึก `reason`, `code`, `kid`, `algorithm`,
   `tokenType`, `iat`, `exp`, `tokenLength`; ไม่ log token, `sub` หรือ `sid`
2. `socketAuthError()` คงข้อความเดิมเพื่อ compatibility และแนบ `error.data.code`:
   `token_expired`, `token_not_active`, `malformed_token`, `unknown_kid`,
   `unsupported_algorithm`, `wrong_token_type`, `invalid_signature`, `session_revoked`,
   `user_inactive`, `user_not_found`, `verified_login_required`, `auth_backend_unavailable`
3. นับการปฏิเสธต่อ reason ด้วย Redis key รายชั่วโมง (TTL 48 ชั่วโมง); metric fail-open
   เพื่อไม่ให้ Redis ขัดขวาง handshake denial
4. คง dual-key `JWT_PREVIOUS_KID/SECRET` ตาม runbook เดิม

### 7.3 Ops / Runbook (สอดคล้องกับแผน)

1. ก่อนเปลี่ยน `JWT_*` ให้ใช้ `JWT_PREVIOUS_*` เป็น overlap ตามขั้นตอน secret rotation;
   restart Node หลังแก้ `.env` ตาม Network & Configuration Runbook
2. เก็บ server log ระหว่างทดสอบ:
   `cd websocket-server && npm run dev 2>&1 | tee -a /tmp/socket-auth-server.log`
3. เพิ่มอาการ `invalid or expired token` หลัง refresh สำเร็จซ้ำในตาราง “อาการ → สาเหตุ”
   ของ `VIDEO_SYSTEM_PLAN.md` แล้ว (ดู §11)
4. หลัง reboot/เปลี่ยน network ตรวจ 4 services ตามแผนและอ่าน code ล่าสุดด้วย:
   `grep 'SocketAuth.*token rejected' /tmp/socket-auth-server.log | tail -3`

---

## 8. Test & verification

| ระดับ | Test | สถานะ |
|---|---|---|
| Dart unit | socket ใหม่ด้วย token A/B; ตรวจ object ใหม่และ `auth.token == B` | ผ่าน |
| Dart unit | token expiry window, missing/malformed token, reuse/rebuild/refresh/stop, recovery budget และ terminal user copy | ผ่าน |
| Node unit | reason-code mapping + Redis metric stub + ตรวจว่า structured log ไม่เก็บ token | ผ่าน |
| Node suite | `npm test` (`node --test 'test/**/*.test.js'`) | ผ่าน 13/13 |
| Socket.IO protocol smoke | ส่ง expired JWT ผ่าน Caddy :8080 | ผ่าน; response มีข้อความเดิมและ `data.code=token_expired` |
| Analyzer | core socket files: `dart analyze` | ไม่มี errors/warnings; 4 info-level style items |
| Analyzer (UI/part files) | `home_page.dart`, `emergency_websocket_logic.dart` | มี warning/info เดิมในส่วนอื่นของไฟล์ (เช่น part-file `setState`, unused import); บรรทัดที่เพิ่ม/เปลี่ยนไม่มี diagnostic |
| Device integration | ปล่อย access token ให้หมดอายุจริง แล้วตรวจ refresh 1 ครั้ง → socket ใหม่เชื่อมสำเร็จ | **ยังต้องยืนยันบน device หลัง build ใหม่นี้** |
| Runtime gate | ตรวจว่าไม่มี refresh storm/429 ในรอบ token expiry | **ต้องยืนยันจาก log หลัง device run** |

คำสั่งตรวจ:

```bash
flutter test test/core/socket_auth_recovery_policy_test.dart test/core/socket_reconnect_policy_test.dart
cd websocket-server && npm test
dart analyze lib/services/websocket_service.dart lib/services/socket_auth_recovery_policy.dart lib/services/socket_auth_socket_factory.dart test/core/socket_auth_recovery_policy_test.dart
```

---

## 9. Rollout / rollback

1. Server reason codes/logging/counters เป็น backward-compatible; deploy server ก่อน Flutter ได้
   เพราะ client เก่ายังคงเห็นข้อความ error เดิม
2. ปล่อย Flutter ที่ใช้ `SocketAuthSocketFactory` + bounded recovery แล้วทดสอบบน device
   จนผ่าน access-token expiry cycle อย่างน้อย 1 รอบ
3. ตรวจ `public.sessions` และ server rejection counters ว่าการหมดอายุ 1 ครั้งไม่ทำให้เกิด
   refresh storm/notification `429`
4. Rollback ได้โดยย้อน Flutter build; server ยังเก็บ reason code/log/counter ที่ไม่เปลี่ยน
   authorization behavior
5. ห้าม rollback ด้วยการปิด JWT verification หรือเปิด legacy identity

---

## 10. Acceptance criteria

- [x] Socket.IO regression test ยืนยันว่า token B ถูกใช้จริงหลังสร้าง socket ใหม่
- [x] Policy tests ครอบคลุม expiry window, rebuild/reuse/stop และ auth recovery budget
- [x] Server reason-code tests ผ่าน และ log/counter ไม่เก็บ raw token/user/session id
- [x] ไม่มีการลดทอน security policy หรือเปลี่ยน event/mission/Phase 20 semantics
- [x] terminal auth failure ส่ง user-facing SnackBar; transient retry ไม่แสดงซ้ำ
- [ ] บน device: token หมดอายุแล้ว reconnect สำเร็จด้วย token ใหม่ภายใน 1 refresh
- [ ] บน device: refresh rotation ไม่เกิน 1 ครั้งต่อ token expiry และไม่มี 429 จาก retry storm
- [ ] หลัง repeated failure ระบบหยุด retry และส่งสถานะที่ตรวจสอบได้

---

## 11. ความสอดคล้องกับ `docs/plans/VIDEO_SYSTEM_PLAN.md`

- Network & Configuration Runbook เดิมและ checklist 4 services ยังเหมือนเดิม; เพิ่มเพียง
  symptom row ในตาราง “อาการ → สาเหตุ” เพื่อชี้มายังคู่มือนี้และห้ามลด JWT verification
- ไม่เปลี่ยนพฤติกรรม realtime refresh ใน Phase 20 (ไม่ auto-switch player), mission rules,
  event semantics หรือ category filter — socket auth เป็นชั้น transport ก่อนถึง events
- สอดคล้องกับ `--dart-define=USE_BACKEND_AUTH=true` และ single canonical
  `backendApiUrl`/`websocketUrl`; ไม่เสนอการแยก host หรือ fallback ไป legacy identity

---

## 12. Quick reference

```bash
# เหตุผลจริงของการปฏิเสธ handshake
grep 'SocketAuth.*token rejected' /tmp/socket-auth-server.log | tail -5

# ตรวจว่า server mint/verify ตรงกัน (ไม่ต้องพึ่งแอป)
cd websocket-server && node -e "require('dotenv').config();const j=require('./lib/jwt');
const t=j.signAccessToken({userId:'<uuid>',role:'admin'});
console.log('minted typ=',j.verifyAccessToken(t).typ)"

# ดู refresh rotation และ socket rejection counters
psql "$SUPABASE_DB_URL" -c "select created_at, rotated_at, ip_address
  from public.sessions where user_id='<uuid>' order by created_at desc limit 10;"
redis-cli --scan --pattern 'socket:auth:rejections:*'

# ตรวจ process/พอร์ต (กัน server เก่าถือ .env เดิม)
lsof -nP -iTCP:3000 -sTCP:LISTEN; curl -s localhost:8080/health
```

diagnostic file ที่ใช้ชั่วคราวระหว่างสืบสวนถูกลบแล้ว; ใช้ structured server logs ตาม §7.2
