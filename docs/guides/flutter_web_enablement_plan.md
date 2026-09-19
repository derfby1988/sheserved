# แผนเปิดใช้งาน Flutter Web สำหรับ Sheserved

> **วันที่สร้าง:** 2026-09-19
> **อัปเดต:** 2026-09-19 — ปรับให้เข้ากับ Phase 13 (Trusted Backend Identity Bridge Rollout) ใน `docs/plans/Match_Sport_PLAN.md`
> **สถานะ:** 📋 แผนเพื่อการตัดสินใจ — ยังไม่ลงมือ implement จนกว่าจะได้รับอนุมัติ
> **ขอบเขต:** ทำให้ `flutter run -d chrome` / `flutter build web` ทำงานได้โดยไม่ขัดกับ `docs/infrastructure/`, `docs/secure/` และ Phase 13 contract
> **กติกา rollout:** ทุก phase ต้องเป็น release ที่ deploy ได้อิสระตามกฎ Q1-B (ปล่อยค้างได้โดยระบบไม่แย่ลง), มี tests + rollback และห้ามเปลี่ยน `AuthService`/`ServiceLocator` ไปใช้ `Supabase.instance.client.auth.currentUser` (ตาม `.agent/workflows/auth_data_guidelines.md`)

---

## 1. สถานะปัจจุบัน (As-Is, ตรวจสอบ 2026-09-19)

**`flutter run -d chrome` ไม่ผ่านตั้งแต่ขั้น compile** — ปัญหาแบ่งเป็น 5 กลุ่ม:

| # | ปัญหา | ระดับ | หลักฐาน |
|---|--------|-------|----------|
| P1 | `import 'dart:io'` ใน 22 ไฟล์ (reachable จาก `main.dart` ทั้งหมด) | 🔴 compile fail | `lib/features/chat/`, `lib/features/admin/`, `lib/features/health/`, `lib/shared/widgets/` |
| P2 | `package:health` import `dart:io` ภายใน (`health-13.3.1/lib/health.dart:5`) | 🔴 compile fail | `health_connect_source.dart`, `apple_health_source.dart` |
| P3 | Plugin native-only: `google_mlkit_face_detection`, `flutter_compass`, `health` | 🟡 runtime fail | `chat_room_page.dart`, `chart_board_page.dart`, `emergency_live_page.dart`, `rescue_page.dart` |
| P4 | File/path semantics บน web: `File(xfile.path)`, `FilePicker.path=null`, `getTemporaryDirectory()`, `MultipartFile.fromPath`, `VideoPlayerController.file` | 🟡 runtime fail | 15+ จุดใน chat/admin/video/donation |
| P5 | Network: backend `http://192.168.1.111:8080` ต้อง origin อยู่ใน `ALLOWED_ORIGINS`; `flutter_polyline_points` เรียก Directions REST โดน CORS block | 🟡 runtime fail | `app_config.dart:26-32` |

**สิ่งที่พร้อมแล้ว (ไม่ต้องทำซ้ำ):**
- `web/` + `index.html` + `manifest.json` ครบ พร้อม model-viewer JS และ corbado passkeys bundle
- `PlatformService` — central platform gate พร้อม `isWeb/isAndroid/isIOS` และ `_isWebMapEnabled = false`
- `AppScrollBehavior` รองรับ mouse drag บน web แล้ว (`main.dart:133`)
- Plugin ที่มี web impl อยู่แล้ว: `flutter_webrtc`, `camera` (camera_web), `record_web`, `geolocator`, `permission_handler` (html), `flutter_secure_storage`, `hive`, `socket_io_client`, `image_picker`, `file_picker`, `video_player`, `audioplayers`, `model_viewer_plus` 1.10.0, `google_maps_flutter_web`, `google_sign_in_web`, `flutter_facebook_auth_web`

**Phase 13 ที่ implement แล้วและเกี่ยวข้องกับ web โดยตรง (baseline จาก `Match_Sport_PLAN.md`):**
- ✅ **13.0** `ALLOWED_ORIGINS` fail-closed (เลิก default `*`), env validator บังคับใน staging/production, `Caddyfile.staging` พร้อม TLS/WSS, service_key silent fallback ถูกลบ
- ✅ **13.1** DB roles (`sheserved_app`/`sheserved_gateway`/...), `app.current_user_id()` unified helper, Supabase direct-pool adapter (`withTransaction` + `SET LOCAL`) — spike ผ่าน 2026-09-06
- ✅ **13.2** `/api/auth/*` ครบ (register/login/social/refresh/logout/me/sessions), Argon2id, refresh rotation + grace 60 วิ, `audit_logs` + worker, PostgREST token mint (TTL ≤5 นาที), Google/Apple JWKS verify, `helmet()` wired, `x-app-version` min-version middleware — E2E 37/37 + device-verified
- ✅ **Flutter switch เสร็จแล้ว:** `AuthenticatedHttpClient` (refresh-once/single-flight, Bearer, `x-app-version`), `AuthService.restoreSession()` ถูกเรียกใน `main()` ก่อน UI, `useBackendAuth` dart-define flag
- ⏳ **13.3** (วางแผน staged): `socket-auth.js`, room authorization, verified `req.userId`/`socket.userId` — ยังไม่ implement
- **Dev policy 2026-09-15:** `useBackendAuth` default `false` + `mainMachineIp` ชี้เครื่องหลัก — dev ไม่ต้องเปิด server ทุกครั้ง; security test ใช้ `--dart-define=USE_BACKEND_AUTH=true`

---

## 2. Alignment Check กับ docs/infrastructure, docs/secure และ Phase 13

### 2.1 จุดที่แนวทางเดิมต้องแก้ (Conflict Resolutions)

| # | แนวทางเดิม | เอกสารที่ขัด/กำกับ | ข้อสรุปที่แก้ไข |
|---|-----------|---------------------|----------------|
| C1 | ใส่ Google Maps JS API key ใน `index.html` | `docs/plans/Delivery_PLAN.md:98` (หลีกเลี่ยง Maps JS API บน web เพื่อคุมต้นทุนเป็นศูนย์); `reverse_proxy_plan.md` §3.5; `google_maps_key_restriction_guide.md` (key เดิม restrict เป็น iOS bundle — ใช้ JS API ไม่ได้) | **ห้ามเปิด Maps JS เป็นค่า default** — คง `_isWebMapEnabled = false` + fallback image; ถ้าต้องการจริงให้สร้าง key แยกแบบ HTTP-referrer restriction และบันทึกเป็น cost decision |
| C2 | "flutter_secure_storage บน web เป็น deviation จากแผน 08" | **Phase 13.2 implement แล้ว:** `AuthenticatedHttpClient` เก็บ access+refresh ใน `FlutterSecureStorage` (`authenticated_http_client.dart:51-56`) — architecture decision ของ Phase 13 คือ "platform secure storage" ทุก platform | บน web = localStorage **ตามสัญญา Phase 13.2 ที่ approve แล้ว** — ไม่ใช่ deviation; แต่บันทึกว่า doc 08 เสนอ httpOnly cookie เป็น target ที่เข้มกว่า และ implementation จริง persist access token ด้วย (ไม่ใช่ memory-only ตาม doc 08:116) — ถ้าอนาคตย้าย web เป็น cookie → trigger แผน 15 (CSRF) เป็น P0 |
| C3 | "ตั้ง CORS ที่ backend" | `04_security_misconfiguration.md` เจ้าของ CORS (M1); **13.0 ทำเสร็จแล้ว** — `ALLOWED_ORIGINS` fail-closed + `validate-env.js` บังคับไม่ใช่ `*` ใน staging/prod | ไม่ใช่งาน code อีกต่อไป — เหลือเพียง **env ops**: เพิ่ม origin ของ web (dev `http://localhost:*`, staging/prod domain) เข้า `ALLOWED_ORIGINS` แบบ explicit |
| C4 | — | `14_xss.md` X1 flag Flutter web + HtmlElementView = attack surface ใหม่; X6 stored payload; X9 SVG | Phase W5 hardening: sanitize-on-render, CSP (implement ที่แผน 04 จุดเดียว), `/uploads` force-download ตามแผน 14 C |
| **C5** *(ใหม่ — Phase 13.3)* | "web ใช้ auth เหมือน mobile ได้เลย" | **Coexistence matrix (Match_Sport line 1584-1587):** `USE_BACKEND_AUTH=false` = direct Supabase login ได้เฉพาะ dev/test, **strict protected HTTP/private WebSocket ไม่รับรอง**, public/anonymous เฉพาะตาม allowlist, production ห้ามใช้; "ห้ามส่ง `x-user-id` หรือ Supabase user ID เพื่อยกระดับเป็น trusted actor" | **web ต้องเข้าใจ 2 mode ชัดเจน:** `false` = anonymous/public only (ไม่มี personal room `user-{id}`, ไม่มี private chat/strict routes); `true` = Backend JWT เต็มรูปแบบ (ต้องเปิด server + origin allowlisted) — dev web ส่วนใหญ่จะอยู่ mode `false` ตาม dev policy |
| **C6** *(ใหม่ — Phase 13.2)* | "เติม FB SDK + Apple config ให้ครบใน index.html" | `social/:provider`: Google/Apple verify ผ่าน server-side JWKS แล้ว; **Facebook/LINE/TikTok = 501 fail-closed** (deferred จนกว่าจะมี credentials ที่อนุมัติ); Apple บน device ถูกบล็อกโดย free/personal team | บน web **มีแค่ Google** (และ Apple ถ้า config) ที่ใช้ได้จริง — ต้องซ่อน/ปิดปุ่ม Facebook/LINE/TikTok ใน login UI บน web; Google ต้องใช้ **Web OAuth client ID** ใน meta tag และ server `GOOGLE_CLIENT_IDS` ต้องรวม `aud` ตัวนั้น (pattern เดียวกับที่ iOS เพิ่มเมื่อ 13.2) |

### 2.2 จุดที่สอดคล้องอยู่แล้ว (ไม่ขัด)

| แนวทาง | เอกสาร/implementation รองรับ |
|--------|--------------|
| dart-define สำหรับ config | `07_secret_management.md` Option A + Phase 13.2 ใช้ `USE_BACKEND_AUTH`/`BACKEND_API_URL`/`GOOGLE_SERVER_CLIENT_ID` อยู่แล้ว |
| เสิร์ฟ web build ผ่าน Caddy | `reverse_proxy_plan.md` ช่อง `admin.sheserved.com`; `Caddyfile.staging` (13.0) เป็น template TLS/WSS พร้อม |
| Auth ผ่าน backend + custom `AuthService` | `auth_data_guidelines.md` + Phase 13 architecture decision — `social_auth_service.dart` → `AuthenticatedHttpClient.socialLogin` เป็นไปตามนี้อยู่แล้ว |
| Google client ID ใน meta tag | `07` classification: client ID = P1 client-embedded ได้ |
| Bearer token (ไม่ใช่ cookie) | `15_csrf.md` — CSRF ต่ำโดยธรรมชาติ; Phase 13 ไม่ใช้ cookie ใน request path |
| Refresh-once/single-flight บน web | `AuthenticatedHttpClient` เป็น pure-Dart HTTP — ทำงานบน web ได้ทันที (http package รองรับ) |
| Session restore บน web | `AuthService.restoreSession()` → `loadTokens()` + `/api/auth/me` — flow เดียวกับ mobile |
| Refactor file ops เป็น abstraction | ไม่ขัดเอกสารใด — pattern conditional import เดียวกับ `model_viewer_plus`/`flutter_webrtc` |

---

## 3. แผนเป็น Phase (เรียงลำดับใหม่, อิง Phase 13 contract)

```
Phase W0 — Compile Unblock          (อิสระจาก Phase 13 — ทำได้เลย)
Phase W1 — File/Media Abstraction   (อิสระจาก Phase 13)
Phase W2 — Feature Parity Decisions (อิสระจาก Phase 13)
Phase W3 — Web Auth per Phase 13    (พึ่ง 13.2 ✅ เสร็จแล้ว + 13.3 contract)
Phase W4 — Serving & CORS           (พึ่ง 13.0 ✅ เสร็จแล้ว — เหลือ env ops)
Phase W5 — Web Hardening            (ก่อน production — รวม 13.3 socket-auth contract)
```

> **Dependency map:** W0–W2 ทำได้ทันทีไม่ต้องรอ Phase 13; W3 ใช้สิ่งที่ 13.2 ส่งมอบแล้ว (`/api/auth/*`, `AuthenticatedHttpClient`, social verify); W4 ใช้สิ่งที่ 13.0 ส่งมอบแล้ว (CORS fail-closed, Caddyfile.staging); W5 ต้องรวมสัญญา 13.3 (socket-auth, room auth) ที่กำลังจะ implement

---

### Phase W0 — Compile Unblock 🟢 ฟรี, ต้นทุนต่ำสุด

**เป้าหมาย:** `flutter run -d chrome` boot ได้ หน้า native-only แสดง fallback แทนพัง

| # | งาน | ไฟล์ |
|---|-----|------|
| W0.1 | ลบ `import 'dart:io'` ที่ไม่ได้ใช้ | `emergency_live_page.dart`, `emergency_reporting_mixin.dart` |
| W0.2 | เปลี่ยน `Platform.isX` → `PlatformService.isAndroid/isIOS` | `tlz_bottom_navigation_bar.dart:107`, `health_connect_source.dart:29`, `apple_health_source.dart:31`, `health_provider.dart:350` |
| W0.3 | สร้าง file abstraction ด้วย conditional import (pattern เดียวกับ `model_viewer_plus`): `import 'file_ops_io.dart' if (dart.library.js_interop) 'file_ops_web.dart'` — API รับ/คืน `XFile`/`Uint8List` ไม่ใช่ `File` | สร้าง `lib/core/utils/file_ops*.dart` |
| W0.4 | แก้ signature `uploadFile(File ...)` → `uploadFile(XFile ...)` หรือ bytes + filename | `chat_repository.dart:321`, `video_repository.dart:717,762`, `body_region_repository.dart:28,115`, `watermark_repository.dart:105` |
| W0.5 | Guard หน้าที่ใช้ `dart:io` หนัก (chat_room PDPA blur, chart_board, body_region_admin) — แยก widget ที่ใช้ `File` ออกเป็น conditional import หรือ `kIsWeb` early-return placeholder | `chat_room_page.dart`, `chart_board_page.dart`, `body_region_admin_page.dart` |
| W0.6 | Guard `health` sources — `health_provider._initSource` มี `kIsWeb` check อยู่แล้ว แต่ import chain ยังชน `dart:io` → แยก source impl เป็น conditional import (web = `NullHealthSource`) | `health_connect_source.dart`, `apple_health_source.dart`, `health_provider.dart` |

**Verification:** `flutter build web` compile ผ่าน; `flutter run -d chrome` เปิด `MainAppLayout` ได้; login/home render
**Rollback:** conditional import เป็น additive — revert ไฟล์ stub ได้โดยไม่กระทบ mobile
**Safe stop:** ✅ หยุดค้างได้ — ระบบดีขึ้น (compile web ผ่าน) โดยไม่เปลี่ยน behavior mobile

---

### Phase W1 — File/Media Abstraction 🟢 ฟรี

**เป้าหมาย:** upload/preview/export ทำงานบน web ผ่าน bytes

| # | งาน | หมายเหตุ |
|---|-----|----------|
| W1.1 | `MultipartFile.fromPath` → `MultipartFile.fromBytes` | `video_repository.dart:742,807`, `watermark_repository.dart:115`, `body_region_repository.dart` |
| W1.2 | แทน `getTemporaryDirectory()/getApplicationDocumentsDirectory()` ด้วย abstraction — web: เก็บ bytes ใน memory แล้ว `uploadBinary` (มีอยู่ใน `supabase_service.dart:201`) | `chat_room_page.dart:496,627`, `profile_page.dart:3154`, `chart_board_page.dart:1533,1613`, `image_upload_field.dart:136` |
| W1.3 | Preview รูป/วิดีโอ: `Image.file`/`FileImage`/`VideoPlayerController.file` → `Image.memory`/`MemoryImage`/`.network()` หรือ blob URL | `video_player_widget.dart:205`, `fullscreen_video_viewer.dart:225,289`, `incident_report_widget.dart:152,557` |
| W1.4 | CSV export ใน `donation_report_panel.dart:125` — web: สร้าง download ผ่าน anchor/blob แทนเขียนลง documents dir | ใช้ conditional import (`package:web`/`dart:js_interop`) |
| W1.5 | `FilePicker.files.single.path` = null บน web → ใช้ `.bytes` แทน | `body_region_admin_page.dart:606-608` |

**Verification:** upload รูปแชท/avatar/เอกสารจาก Chrome สำเร็จ; CSV download ทำงาน; preview รูปก่อนส่งแสดงผล

---

### Phase W2 — Feature Parity Decisions 🟡 ต้องตัดสินใจทีละฟีเจอร์

| ฟีเจอร์ | ตัวเลือก | ข้อเสนอแนะ |
|---------|---------|-----------|
| PDPA face blur (`google_mlkit_face_detection`) | (a) ซ่อนบน web (b) server-side blur ผ่าน backend (websocket-server มี FFmpeg pipeline อยู่แล้ว) | **(a) ก่อน** — blur ฝั่ง client เป็น UX convenience; ถ้าเป็น PDPA requirement จริงควรทำ server-side อยู่แล้ว |
| Compass (`flutter_compass`) | ซ่อน widget บน web | ซ่อน — แสดงแผนที่/ตัวเลข heading แทน |
| Health Connect/Apple Health | แสดง "ไม่รองรับบน web" | คง guard เดิม — manual entry ใช้ได้ |
| Camera (`camera_web`) | ทดสอบจริง — ต้อง HTTPS/localhost + permission prompt | verify ใน W4 |
| Video call (`flutter_webrtc`) | มี web impl — ต้อง TURN/signaling เหมือนเดิม | verify flow; signaling ต้องผ่าน socket-auth เมื่อ 13.3 พร้อม |
| Voice record (`record_web`) | รองรับเฉพาะ audio บาง codec | verify chat voice message |
| `flutter_polyline_points` (Directions REST → CORS) | (a) ปิด route drawing บน web (b) proxy ผ่าน backend | **(a)** สอดคล้องกับ maps-off policy (C1) |
| Offline mutation | — | ตาม Q8-A: Fitness = online-only fail closed — web เป็นไปตามนี้อยู่แล้ว |

---

### Phase W3 — Web Auth ตามสัญญา Phase 13 🔴 ก่อน production เท่านั้น

> **ข้อผูกมัดจาก Phase 13 ที่ตัดสินใจแล้ว (ห้ามตัดสินใจซ้ำ):** Q6-B refresh rotation + grace 60s; Q7-C สาม data paths (anon+VIEW / PostgREST token / gateway mutation); Q11-B audit_logs; Q12-B ไม่มี service_role ใน request path; coexistence matrix ของ 13.3

| # | งาน | รายละเอียด / เอกสารอ้างอิง |
|---|-----|---------------------------|
| W3.1 | `index.html`: `<meta name="google-signin-client_id" content="...">` ด้วย **Web OAuth client ID** | client ID = P1 (`07` §5); server `GOOGLE_CLIENT_IDS`/`GOOGLE_CLIENT_ID` env ต้องรวม `aud` ตัวนี้ — pattern เดียวกับที่ 13.2 เพิ่ม iOS client ID (`Match_Sport` line 1568, 1840) |
| W3.2 | **Web auth mode matrix** — เขียนลง UI/dev docs ชัดเจน: `USE_BACKEND_AUTH=true` (เปิด server + origin ใน ALLOWED_ORIGINS) = login/register/social/private paths ครบ; `false` = **anonymous/public allowlist เท่านั้น** (browse ได้ แต่ไม่มี personal room `user-{id}`, private chat, strict routes — ตาม coexistence policy 13.3 line 1584-1587) | บัญชี Argon2id login ไม่ได้ใน direct mode (line 1575) — dev web ที่ใช้ `false` ต้องสร้าง dev account แยก |
| W3.3 | ซ่อน/ปิด social provider ที่ backend ยัง 501 บน web — **เหลือ Google (+Apple ถ้า config)**; Facebook/LINE/TikTok แสดง disabled หรือซ่อน | `routes/auth.js` social/:provider fail-closed (`Match_Sport` line 1551, 1563) |
| W3.4 | Token storage: ใช้ `AuthenticatedHttpClient` + `flutter_secure_storage` ตาม Phase 13.2 ที่ approve แล้ว — บน web = localStorage (ทั้ง access+refresh ตาม implementation จริง) | บันทึก: doc 08 เสนอ httpOnly cookie เป็น hardening ระยะยาว — ถ้าเลือกทางนั้นต้องเปิดแผน 15 (CSRF) เป็น P0 พร้อมกัน |
| W3.5 | WebSocket handshake: `websocket_service.dart:257` ปัจจุบันส่ง `{'userId': userId, 'token': authToken}` เป็น raw identity — เมื่อ 13.3 implement `socket-auth.js` ต้องส่ง **Backend access token** ใน `setAuth`; direct mode = anonymous เท่านั้น | 13.3 P0-4; web เป็นไปตาม contract เดียวกัน — ห้ามเพิ่ม path พิเศษสำหรับ web |
| W3.6 | Private Supabase reads บน web ต้องใช้ **PostgREST token** (backend mint, TTL ≤5 นาที, sign ด้วย `SUPABASE_JWT_SECRET`) เมื่อ data path migrate — ไม่ใช้ anon key กับ private data | Q7-C (`Match_Sport` line 1385, 1535); `lib/postgrest-token.js` มีแล้ว + live check ผ่าน |
| W3.7 | `x-app-version` ถูกส่งทุก request โดย `AuthenticatedHttpClient` อยู่แล้ว — ตรวจ `AppVersionChecker`/426 handling ทำงานบน web build; `MIN_APP_VERSION_ENFORCE=false` ใน dev | 13.2 amendment (line 1801); เมื่อเปิด enforce ต้องให้ web build ส่งเวอร์ชันถูก |

**Verification:** login (backend mode) + Google social บน Chrome ผ่าน; `/me` restore session ทำงาน; direct mode เห็นเฉพาะ public; ไม่มี `x-user-id`/Supabase ID ถูกส่งเพื่อยกระดับ

---

### Phase W4 — Serving & CORS 🟢 ใช้ infra เดิม (13.0 พร้อมแล้ว)

| # | งาน | รายละเอียด |
|---|-----|-----------|
| W4.1 | `ALLOWED_ORIGINS` เพิ่ม web origin แบบ explicit — **env ops เท่านั้น ไม่แก้ code**: dev เพิ่ม origin ของ `flutter run` (เช่น `http://localhost:5000`); staging/prod เพิ่ม domain web จริง — ห้าม `*` | 13.0 ทำ fail-closed + validator แล้ว (`Match_Sport` line 1463); Socket.IO ใช้ allowlist เดียวกัน (`server.js:114-116`) |
| W4.2 | เสิร์ฟ `build/web` หลัง Caddy — เพิ่ม site block ตาม pattern `Caddyfile.staging` (TLS auto + HSTS + security headers) ด้วย `try_files {path} /index.html` (SPA fallback); ช่อง `admin.sheserved.com` ใน `reverse_proxy_plan.md` รออยู่ | ไม่เพิ่ม infra (zero-cost); ใช้ `CADDY_STAGING_DOMAIN`/`CADDY_ACME_EMAIL` env เดิม |
| W4.3 | HTTPS: web served ผ่าน https → backend calls ต้อง https (mixed content) — `backendApiUrl`/websocket ต้องเป็น `https://`/`wss://` ผ่าน dart-define; dev ใช้ `http://<IP>:8080` ได้ถ้า origin allowlisted | `Caddyfile.staging` ทำ WSS ผ่าน `/socket.io/*` แล้ว (13.0 line 1464) |
| W4.4 | Security headers: `helmet()` wired แล้วใน 13.2 — เหลือ CSP สำหรับ web host (implement ที่แผน 04 จุดเดียวตาม dependency map) | `14_xss.md` ตัวเลือก C |
| W4.5 | คง `_isWebMapEnabled = false` — ถ้าเปิดต้องมี web Maps key แยก (HTTP referrer restriction) เป็น cost decision | `Delivery_PLAN.md:98`, key guide |

---

### Phase W5 — Web Hardening (ก่อน production web) 🔴

| # | งาน | เอกสาร/Phase 13 อ้างอิง |
|---|-----|------------------------|
| W5.1 | Audit sanitize-on-render: user content ที่ render ใน DOM (chat, articles, rich text); `HtmlElementView`/`dart:html` ทุกจุด | `14_xss.md` X1/X6 |
| W5.2 | SVG upload policy — เสิร์ฟผ่าน browser จะ execute script | `14_xss.md` X9 |
| W5.3 | CSRF review: คง Bearer header auth (ต่ำ) — **ถ้า W3.4 เปลี่ยนเป็น cookie ในอนาคต → implement แผน 15 เต็มก่อน deploy** | `15_csrf.md` trigger |
| W5.4 | Socket contract ตาม 13.3: ห้ามส่ง `auth.userId`/raw identity จาก web client; anonymous socket = public allowlist เท่านั้น; strict/private rooms ต้อง Backend JWT | 13.3 P0-4, line 1683-1686 |
| W5.5 | `gitleaks` scan `web/` + `index.html` — ยืนยันไม่มี P2/P3; meta client ID (P1) และ maps key (P0+restriction) เท่านั้น | `07` ตัวเลือก E |
| W5.6 | CI: เพิ่ม `flutter build web` ใน pipeline เพื่อกัน dart:io ถดถอย | `06_dependency_vulnerabilities.md` |
| W5.7 | Token storage hardening decision: ยืนยันคง localStorage (Phase 13.2 contract) หรือเลื่อนเป็น memory-only access token / httpOnly cookie ตาม doc 08 — ถ้าเลือก cookie ให้เปิดแผน 15 พร้อมกัน | `08:116`, `15:87`; บันทึกว่า impl ปัจจุบัน persist access token ด้วย |

---

## 4. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติ Phase W0/W1 (compile unblock + file abstraction — อิสระจาก Phase 13)
- [ ] ตัดสินใจ W2: ซ่อน face blur บน web หรือ server-side blur ผ่าน FFmpeg pipeline
- [ ] ยืนยัน W3.2: web dev ใช้ `USE_BACKEND_AUTH=false` (anonymous/public only) หรือ `true` (ต้องเปิด server เสมอ) — แนะนำ `true` สำหรับทดสอบ web จริง
- [ ] ยืนยัน W3.3: ซ่อน Facebook/LINE/TikTok บน web (backend 501) — Apple รอ paid dev account ตาม 13.2 blocker
- [ ] ตัดสินใจ W5.7: token storage บน web — คง localStorage ตาม 13.2 หรือลงทุน httpOnly cookie + CSRF (แผน 15) พร้อมกัน
- [ ] ตัดสินใจ W4.5: เปิด Google Maps บน web หรือไม่ (cost decision — ขัด intent ของ Delivery plan)
- [ ] ตัดสินใจ domain เสิร์ฟ web (`admin.sheserved.com` ตาม reverse proxy plan หรือแยก)

## 5. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `docs/plans/Match_Sport_PLAN.md` Phase 13 | **แผนนี้อยู่ภายใต้สัญญา Phase 13** — W3/W4/W5 อิงสิ่งที่ 13.0/13.1/13.2 ส่งมอบแล้วและ contract ของ 13.3; ห้ามสร้าง auth path แยกสำหรับ web |
| `docs/design/PHASE_13_2_TEMPORARY_DIRECT_AUTH_DEVELOPMENT_PLAN.md` | W3.2 coexistence matrix ตามเอกสารนี้ |
| `docs/secure/README.md` rollout rules | ✅ Q1-B ทุก phase deploy ได้อิสระ; ไม่เปลี่ยน AuthService/ServiceLocator |
| `docs/secure/04_security_misconfiguration.md` | W4.1/W4.4 เป็นงานเดียวกับแผน 04 (M1, headers) — CORS ทำเสร็จใน 13.0 แล้ว |
| `docs/secure/07_secret_management.md` | dart-define เดิม; client ID = P1, maps key = P0+restriction |
| `docs/secure/08_session_token_security.md` | W3.4 บันทึก deviation ที่เป็นรูปธรรม (impl persist access token) + target httpOnly cookie |
| `docs/secure/14_xss.md` | W5 ครอบคลุม X1/X6/X9 |
| `docs/secure/15_csrf.md` | trigger-based — activate เมื่อใช้ cookie |
| `docs/secure/17_phase_13_1_supabase_spike_runbook.md` | ไม่เกี่ยวข้องโดยตรง (DB-side) — web ใช้ผลลัพธ์ของ 13.1 ผ่าน API เท่านั้น |
| `docs/infrastructure/reverse_proxy_plan.md` | เสิร์ฟ web ผ่าน Caddy slot ที่เตรียมไว้; `Caddyfile.staging` เป็น template (zero-cost) |
| `docs/infrastructure/architecture_analysis.md` | web client เข้าผ่าน path เดิม (Caddy → websocket-server) ไม่เปลี่ยน architecture |
| `docs/plans/Delivery_PLAN.md` | คง maps-off บน web ตาม cost-zero intent |
| `.agent/workflows/auth_data_guidelines.md` | ใช้ `ServiceLocator.instance.currentUser` เท่านั้น |
