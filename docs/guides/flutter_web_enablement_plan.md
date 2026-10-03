# แผนเปิดใช้งาน Flutter Web สำหรับ Sheserved

> **วันที่สร้าง:** 2026-09-19
> **อัปเดต:** 2026-09-19 — ปรับให้เข้ากับ Phase 13 (Trusted Backend Identity Bridge Rollout) ใน `docs/plans/Match_Sport_PLAN.md`
> **อัปเดต:** 2026-09-20 — เพิ่ม mobile-safety guardrails, UI layout invariants และ release gates หลัง dependency map ในส่วน 3
> **อัปเดต:** 2026-09-21 — re-baseline กับ Phase 13.3 ที่มี implementation บางส่วนแล้ว และเพิ่ม socket token lifecycle, CSP external origins, passkeys, domain/cache delivery checks
> **สถานะ:** ✅ **W0/W1 implement + verify แล้ว (2026-09-21) + mobile baseline §4.2 เก็บครบแล้ว (2026-10-03)** — web build/serve ผ่าน, analyzer diff 0, Android/iOS build ผ่าน, device smoke+screenshots บน 4 form factors (หลักฐานท้าย W1); ✅ **W2 ตัดสิน + implement แล้ว**; ✅ **W3 verify ครบแล้ว (2026-10-03: login Argon2id + Google GIS credential flow + `/me` restore + disabled providers + socket lifecycle refresh/revoke บน Android + 426 contract + direct-mode smoke ผ่าน )**; ✅ **W4 dev-serving implement+verify แล้ว (2026-10-03: Caddy `:8081` เสิร์ฟ build/web + SPA fallback + CSP + cache profile ผ่าน curl; staging block + cloudflared config พร้อม)** — ⏸️ **พักที่ domain purchase**: `sheserved.com` อยู่ใน GoDaddy account ที่ไม่ทราบเจ้าของ (recover แยกต่างหาก), ผู้ใช้กำลังตัดสินใจซื้อโดเมนใหม่ที่ Cloudflare — ขั้นตอนต่อจากซื้อจดครบในหมายเหตุใต้ตาราง W4; 📋 W5 รอ decisions
> **ขอบเขต:** ทำให้ `flutter run -d chrome` / `flutter build web` ทำงานได้โดยไม่ขัดกับ `docs/infrastructure/`, `docs/secure/` และ Phase 13 contract
> **กติกา rollout:** ทุก phase ต้องเป็น release ที่ deploy ได้อิสระตามกฎ Q1-B (ปล่อยค้างได้โดยระบบไม่แย่ลง), มี tests + rollback และห้ามเปลี่ยน `AuthService`/`ServiceLocator` ไปใช้ `Supabase.instance.client.auth.currentUser` (ตาม `.agent/workflows/auth_data_guidelines.md`)

---

## 1. สถานะปัจจุบัน (As-Is, ตรวจสอบ 2026-09-19)

**`flutter run -d chrome` ไม่ผ่านตั้งแต่ขั้น compile** — ปัญหาแบ่งเป็น 5 กลุ่ม:

| # | ปัญหา | ระดับ | หลักฐาน |
|---|--------|-------|----------|
| P1 | `import 'dart:io'` ใน 23 ไฟล์ที่พบจาก inventory (ต้องยืนยันอีกครั้งว่าไฟล์ใด reachable จาก `main.dart`) — **อัปเดตจากการทำ W0 จริง:** dart2js/DDC compile `dart:io` ผ่านแล้ว (SDK stub — API throw `UnsupportedError` ตอน runtime) จึงเป็น 🔴 runtime fail ไม่ใช่ compile fail; compile blocker จริงคือ icon tree-shake ที่ `expert_status_helpers.dart` (dynamic `IconData` จาก DB — ต้อง `--no-tree-shake-icons`) | 🔴 runtime fail (dart:io stub) + icon tree-shake | `lib/features/chat/`, `lib/features/admin/`, `lib/features/health/`, `lib/shared/widgets/` และไฟล์ video/profile/donation ที่เกี่ยวข้อง |
| P2 | `package:health` import `dart:io` ภายใน (`health-13.3.1/lib/health.dart:5`) | 🔴 compile fail | `health_connect_source.dart`, `apple_health_source.dart` |
| P3 | Plugin native-only: `google_mlkit_face_detection`, `flutter_compass`, `health` | � compile/runtime fail — ML Kit/health มี import chain ที่ชน `dart:io`; compass เป็น runtime-only | `chat_room_page.dart`, `chart_board_page.dart`, `emergency_live_page.dart`, `rescue_page.dart` |
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
- 🟡 **13.3** (staged implementation มีบางส่วนแล้ว): `middleware/socket-auth.js` ถูกสร้างและ wired ใน `server.js`; `STRICT_SOCKET_AUTH`/`STRICT_SOCKET_EVENTS`/`STRICT_ROOM_AUTH` เป็น rollout flags และมี socket revocation wiring แล้ว — room authorization, event coverage, Flutter token lifecycle และ strict cutover ยังต้องผ่าน gate ตาม `Match_Sport_PLAN.md`
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

> **Dependency map:** W0–W2 ทำได้ทันทีไม่ต้องรอ Phase 13; W3 ใช้สิ่งที่ 13.2 ส่งมอบแล้ว (`/api/auth/*`, `AuthenticatedHttpClient`, social verify) และตรวจผลของ 13.3 ที่ implement บางส่วนแล้ว; W4 ใช้สิ่งที่ 13.0 ส่งมอบแล้ว (CORS fail-closed, Caddyfile.staging); W5 ต้องปิด gate ของ 13.3 ที่ยังเหลือ (room auth, event coverage, token lifecycle และ strict cutover)

> **Guardrails ข้าม phase (mobile safety) — บังคับทุก phase ที่แตะ shared code:**
> 1. **IO คง path-based, web ใช้ bytes — ห้ามแปลง unconditional:** `MultipartFile.fromPath`, `Image.file`/`FileImage`, `VideoPlayerController.file`, `getTemporaryDirectory()`, `FilePicker.files.single.path` ทำงานบน iOS/Android ปกติ — ห้ามแทนทับด้วย bytes/memory ทั้งแอป เพราะ (a) `fromBytes`/`Image.memory` โหลดไฟล์ทั้งก้อนเข้า RAM (วิดีโอ emergency หลักร้อย MB → memory spike บนมือถือ), (b) `fromBytes`/`uploadBinary` ต้องส่ง `filename`+`contentType` เอง ไม่งั้น mime หลุดเป็น `application/octet-stream`, (c) `FilePicker.bytes` เป็น null บน mobile ถ้าไม่ส่ง `withData: true` — ให้แยกผ่าน conditional import/`kIsWeb` เสมอ (ข้อยกเว้นที่เช็คแล้ว: `storage_client 2.5.7` อ่าน `file.readAsBytesSync()` เต็มไฟล์อยู่แล้วและเดา mime จาก path — `upload(File)` → `uploadBinary` จึงปลอดภัย แต่ต้องคง extension ใน storage path)
> 2. **Mobile regression check ทุก phase ที่แตะ repository/shared widget:** หลังจบ W0/W1 (และ W5.1 sanitize-on-render) ต้องทดสอบบน iOS+Android จริง: upload วิดีโอ emergency, upload รูป chat + PDPA blur, avatar upload, preview รูป/วิดีโอ, FilePicker icon/model ใน admin — behavior ต้องเหมือนเดิมก่อนปล่อย
> 3. **UI layout invariant:** แยก web/mobile ที่ leaf implementation ด้วย conditional import หรือ `kIsWeb` โดยคง mobile widget tree, constraints และ design tokens เดิม; web fallback ต้องรักษาขนาด/ตำแหน่งของ parent ด้วย `SizedBox`/`AspectRatio`/`ConstrainedBox` ที่เทียบเท่า; ห้ามถอด child จาก `Row`/`Column`/`Stack` หรือเปลี่ยน `Expanded`/`SafeArea`/`MediaQuery.viewInsets` แบบ unconditional; ต้องคง `BoxFit`, typography, line limit และ touch target เดิมบน iOS/Android

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

**Verification:** `flutter build web --no-tree-shake-icons` compile ผ่าน; `flutter run -d chrome` เปิด `MainAppLayout` ได้; login/home render; ผ่าน UI/mobile gate W0 ใน §4.4 (รวม no-overflow และ iOS/Android smoke)
**Rollback:** conditional import เป็น additive — revert ไฟล์ stub ได้โดยไม่กระทบ mobile; หาก UI mobile ต่างจาก baseline ให้ revert ทั้ง phase
**Safe stop:** ✅ หยุดค้างได้ — ระบบดีขึ้น (compile web ผ่าน) โดยไม่เปลี่ยน behavior mobile

---

### Phase W1 — File/Media Abstraction 🟢 ฟรี

**เป้าหมาย:** upload/preview/export ทำงานบน web ผ่าน bytes

| # | งาน | หมายเหตุ |
|---|-----|----------|
| W1.1 | `MultipartFile.fromPath` → `MultipartFile.fromBytes` **เฉพาะ web path** (คง `fromPath` บน IO ตาม guardrail 1; `fromBytes` ต้องส่ง `filename`+`contentType` เอง) | `video_repository.dart:762,833`, `watermark_repository.dart:123`, `body_region_repository.dart` |
| W1.2 | แทน `getTemporaryDirectory()/getApplicationDocumentsDirectory()` ด้วย abstraction — web: เก็บ bytes ใน memory แล้ว `uploadBinary` (มีอยู่ใน `supabase_service.dart:201`) | `chat_room_page.dart:496,627`, `profile_page.dart:3154`, `chart_board_page.dart:1533,1613`, `image_upload_field.dart:136` |
| W1.3 | Preview รูป/วิดีโอ เฉพาะ web path (conditional — คง `Image.file`/`.file()` บน IO ตาม guardrail 1): `Image.file`/`FileImage`/`VideoPlayerController.file` → `Image.memory`/`MemoryImage`/`.network()` หรือ blob URL | `video_player_widget.dart:205`, `fullscreen_video_viewer.dart:225,289`, `incident_report_widget.dart:152,557` |
| W1.4 | CSV export ใน `donation_report_panel.dart:125` — web: สร้าง download ผ่าน anchor/blob แทนเขียนลง documents dir | ใช้ conditional import (`package:web`/`dart:js_interop`) |
| W1.5 | `FilePicker.files.single.path` = null บน web → web ใช้ `.bytes`; IO คง `.path` หรือส่ง `withData: true` (bytes เป็น null บน mobile ถ้าไม่ส่ง — guardrail 1c) | `body_region_admin_page.dart:606-608` |

**Verification:** upload รูปแชท/avatar/เอกสารจาก Chrome สำเร็จ; CSV download ทำงาน; preview รูปก่อนส่งแสดงผล; mobile IO path และ preview geometry ผ่าน Gate W1 ใน §4.4 บน iOS/Android

> **หลักฐาน W0+W1 จริง (2026-09-21):**
> - ✅ `flutter build web --no-tree-shake-icons` → `Built build/web` (45.9s; Wasm dry-run warnings เฉพาะ `flutter_secure_storage_web`/`ua_client_hints_web`/`dart:html`/`package:js` — ไม่ใช่ blocker ของ JS build)
> - ✅ `flutter run -d web-server` → serve `main.dart` สำเร็จ, HTTP 200 + `<title>Sheserved</title>` (DDC compile path ผ่าน)
> - ✅ `dart analyze` → 2409 issues = baseline เดิมเป๊ะ (0 issue ใหม่จากการแก้; error ที่เหลืออยู่ใน dead/orphan files `video/.../controllers/` + `presentation/parts/` ที่เสียอยู่ก่อนแล้ว)
> - ✅ `flutter test` → +175 ~11 −2 — fail ทั้ง 2 เป็น pre-existing environmental: `phase2_role_sync_test` + `widget_test` ต้องการ `Supabase.instance` ที่ initialize แล้ว (ไม่เกี่ยวกับไฟล์ที่แก้)
> - ✅ `flutter build apk --debug` → `app-debug.apk` (59s)
> - ✅ `flutter build ios --simulator --debug` → `Runner.app` (118.6s; ต้อง `pod update GoogleUtilities/UserDefaults` → 8.1.3 ก่อน — Podfile.lock stale อยู่ก่อนแล้ว; มี warning MLKit pods ไม่รองรับ arm64 sim แต่ build ผ่าน)
> - ⚠️ **ยังขาด:** browser smoke จริงบน Chrome (upload/CSV/preview/face-blur fallback ต้องคลิกทดสอบ), iOS/Android device UI smoke + screenshot diff, `flutter analyze` (analysis server exit code 64 — ใช้ `dart analyze` แทน)
> - `dart:io` API ที่เหลือใน `chat_room_page`/`chart_board_page`/`group_invite_poster_sheet`/`chat_repository` ทั้งหมดอยู่หลัง `kIsWeb` guard หรือใน IO-only branch แล้ว
>
> **หลักฐาน mobile baseline §4.2 (2026-10-03, commit `8ac4099`, Flutter 3.38.1 / Dart 3.10.0, debug build, `USE_BACKEND_AUTH` default false → direct Supabase, account `moter`):**
> - ✅ `dart analyze lib test` → **2342 issues** (59 error / 574 warning / 1709 info — ลดจาก 2409 ตอน 2026-09-21; error ทั้งหมดอยู่ใน dead/orphan files เดิม)
> - ✅ `flutter test` → **+508 ~11 −2** — fail 2 ตัวเดิม (`widget_test` + `phase2_role_sync_test`, environmental: ต้องการ `Supabase.instance`)
> - ✅ `git diff --check` clean; `flutter build apk --debug` (151s) + `flutter build ios --simulator --debug` (135.1s) → install ลง device จริงทั้งคู่
> - ✅ **Screenshots → `docs/evidence/w0w1_mobile_baseline/`** (ครอบคลุม §4.2 matrix):
>   - **iOS 393×852** — iPhone 16 sim `A692F954` (iOS 18.1): launch+permission dialog, home guest, profile tab (guest+logged-in), login page, drawer, chat list (empty), consultation card → `/health-data-entry`
>   - **iOS compact ~375×667** — iPhone SE (3rd gen) sim `EA8D160B` (iOS 18.2): home guest — ใกล้สุดที่มีกับ 320×568
>   - **Android 360×879** — emulator-5554 `Copy_of_6.7_API_30` (sdk_gphone_arm64, API 33): home guest+logged-in, login, drawer, shop page, chat list (empty), `/health-data-entry`, profile
>   - **Android 411×868** — emulator-5556 `Sunmi_V2s_PLUS_API_30` (API 30): home guest — ใกล้สุดกับ 412×915
>   - **Landscape: N/A** — `main.dart:167` lock `portraitUp` ทั้งแอป (by design; `radial_question_view` unlock ชั่วคราวแล้ว re-lock)
> - ไม่พบ `RenderFlex overflow`/layout exception ในหน้าที่จับภาพทั้งหมด; bottom nav, drawer, consultation card, profile avatar badge ตำแหน่งตรงกันทั้งสอง platform
> - **หมายเหตุ ops:** physical devices ที่มีอยู่ = iPhone 14 Pro Max (wireless, iOS 27.0) + CPH1989 `DMM7OZFESSFA995L` (Android 11, 360×693dp) — ใช้เสริมได้ในรอบถัดไป
> - **ข้อสังเกตจากการทดสอบ:**
>   - account `test`/`dave` ใน `login_CPH1989.yaml` เป็นบัญชี backend-auth — direct-Supabase mode (`USE_BACKEND_AUTH=false`) ต้องใช้ `moter`/`fater` + `12345678`; login flow iOS ต้องเขียนแยก (subflow เดิมใช้ `hideKeyboard` ที่ทำงานไม่ได้บน iOS sim)
>   - iOS sim: relaunch แอปแล้วกด consultation card ทันที → `restoreSession` ยังไม่เสร็จ ถูก route ไป `/login` — timing ปกติของ session restore ไม่ใช่ bug; `simctl privacy grant location` ไม่ปิด dialog ถาวรในเคสนี้ ต้อง tap dismiss ครั้งเดียว
>   - Android emulator UiAutomation หลุดระหว่างใช้ Maestro (บ่อยบน fresh boot) — ใช้ `adb shell input tap/text` + `exec-out screencap` แทนได้; `input keyevent 4` บนหน้า login จะ pop route กลับ home อย่าใช้ปิด keyboard (tap field ใหม่ก่อน)
>   - guest profile tab กลับ state guest ชั่วคราวได้ถ้าอ่าน auth ก่อน session restore เสร็จ (เจอครั้งเดียว ตอนถอยกลับจาก `/health-data-entry`)
> - ⚠️ **ยังขาด (blocked evidence):** preview/upload บนเนื้อหาจริงใน `chat_room_page`/`chart_board_page`/`incident_report_widget`/`fullscreen_video_viewer` (ไม่มี chat room/media test data), iOS physical screenshot, browser smoke บน Chrome

---

### Phase W2 — Feature Parity Decisions 🟡 ต้องตัดสินใจทีละฟีเจอร์

| ฟีเจอร์ | ตัวเลือก | ข้อเสนอแนะ |
|---------|---------|-----------|
| PDPA face blur (`google_mlkit_face_detection`) | (a) ซ่อนบน web (b) server-side blur ผ่าน backend | ✅ **ตัดสินแล้ว: (b)** — `websocket-server/services/face-blur-service.js` มี `blurFacesInImage` (Python `deface`+CenterFace, open source, ไม่มี license/API cost) ใช้จริงใน `routes/video.js:488` แล้ว; เพิ่ม `POST /api/media/face-blur` หลัง `verifyToken` + web path ใน chat/chart เรียกแทน ML Kit; **fail-closed** เมื่อ backend down (ไม่ upload ภาพ unblurred) |
| Compass (`flutter_compass`) | ซ่อน widget บน web | ✅ **ตัดสินแล้ว: ซ่อน** — แสดงแผนที่/ตัวเลข heading แทนถ้าจำเป็น |
| Health Connect/Apple Health | แสดง "ไม่รองรับบน web" | ✅ ทำแล้วใน W0.6 — `NullHealthSource` บน web |
| Camera (`camera_web`) | ทดสอบจริง — ต้อง HTTPS/localhost + permission prompt | verify ใน W4 |
| Video call (`flutter_webrtc`) | มี web impl — ต้อง TURN/signaling เหมือนเดิม | verify flow; signaling ต้องผ่าน socket-auth เมื่อ 13.3 พร้อม |
| Voice record (`record_web`) | รองรับเฉพาะ audio บาง codec | verify chat voice message |
| `flutter_polyline_points` (Directions REST → CORS) | (a) ปิด route drawing บน web (b) proxy ผ่าน backend | ✅ **ตัดสินแล้ว: (a) ปิดบน web** — สอดคล้องกับ maps-off policy (C1) |
| Offline mutation | — | ตาม Q8-A: Fitness = online-only fail closed — web เป็นไปตามนี้อยู่แล้ว |

---

### Phase W3 — Web Auth ตามสัญญา Phase 13 🔴 ก่อน production เท่านั้น

> **ข้อผูกมัดจาก Phase 13 ที่ตัดสินใจแล้ว (ห้ามตัดสินใจซ้ำ):** Q6-B refresh rotation + grace 60s; Q7-C สาม data paths (anon+VIEW / PostgREST token / gateway mutation); Q11-B audit_logs; Q12-B ไม่มี service_role ใน request path; coexistence matrix ของ 13.3

| # | งาน | รายละเอียด / เอกสารอ้างอิง |
|---|-----|---------------------------|
| W3.1 | ✅ `index.html`: เพิ่ม `<meta name="google-signin-client_id">` ด้วย Web OAuth client ID แล้ว (`web/index.html`) | client ID = P1 (`07` §5); backend `GOOGLE_CLIENT_ID` ตรงกับ `aud` ตัวนี้แล้ว — **ops prerequisite ที่เหลือ:** เพิ่ม `http://localhost:<port>` (dev) และ `https://<web-domain>` (prod) ใน Authorized JavaScript origins ของ Web client ใน GCP Console — ทำจาก code ไม่ได้ |
| W3.2 | ✅ **ตัดสินแล้ว: `USE_BACKEND_AUTH=true`** สำหรับ dev web — login/register/social/private paths ครบ; `false` ยังคงเป็น anonymous/public allowlist เท่านั้น | ต้องเปิด backend + origin ของ `flutter run` อยู่ใน `ALLOWED_ORIGINS`; บัญชี Argon2id login ไม่ได้ใน direct mode (line 1575) |
| W3.3 | ✅ **ตัดสินแล้ว: แสดงทุกปุ่มแต่ disabled บน web เว้น Google** — `lib/features/auth/data/services/social_provider_policy.dart` เป็น central flag (`webEnabled`); `login_page`/`register_page` render ปุ่มเดิมทุกตำแหน่ง ปิด `onTap` + opacity 0.45 + tooltip เฉพาะบน web — **ยกเว้น Google บน web** ใช้ปุ่ม GIS ทางการ (`renderButton` type icon) ในวงกลม 50px เดิม ตาม incident note ด้านล่าง | `routes/auth.js` social/:provider fail-closed 501 (`Match_Sport` line 1551, 1563); เปิด provider เพิ่ม = backend support + เพิ่มใน `webEnabled` |
| W3.4 | Token storage: ใช้ `AuthenticatedHttpClient` + `flutter_secure_storage` ตาม Phase 13.2 ที่ approve แล้ว — บน web = localStorage (ทั้ง access+refresh ตาม implementation จริง) | บันทึก: doc 08 เสนอ httpOnly cookie เป็น hardening ระยะยาว — ถ้าเลือกทางนั้นต้องเปิดแผน 15 (CSRF) เป็น P0 พร้อมกัน |
| W3.5 | ✅ WebSocket handshake ส่ง Backend access token ใน `setAuth` แล้ว (`websocket_service.dart`); identity ฝั่ง server มาจาก `socket.userId` (JWT verified) เท่านั้น — `auth.userId` เป็น legacy compat ไม่ใช่ trusted actor | `socket-auth.js` wired ใน 13.3; STRICT_SOCKET_AUTH=true จะ reject legacy — ห้ามเพิ่ม path พิเศษสำหรับ web |
| W3.6 | ✅ Socket token lifecycle implement แล้ว: `AuthenticatedHttpClient.tokenChanges` broadcast → `WebSocketService` dispose+reconnect ด้วย token ใหม่ (socket.io bake `auth` ตอน construction เปลี่ยนไม่ได้); `null` (logout/revoke) → disconnect ไม่ retry; handshake `Authentication failed` → `refreshTokens()` ครั้งเดียว (single-flight) → ล้มเหลว = clear tokens + หยุด | 13.3 P0-4; ไม่เพิ่ม auth path หรือยืด TTL — ใช้ connect_error contract เดิมของ socket-auth.js |
| W3.7 | Private Supabase reads บน web ต้องใช้ **PostgREST token** (backend mint, TTL ≤5 นาที, sign ด้วย `SUPABASE_JWT_SECRET`) เมื่อ data path migrate — ไม่ใช้ anon key กับ private data | Q7-C (`Match_Sport` line 1385, 1535); `websocket-server/lib/postgrest-token.js` มีแล้ว — **defer ไป data-path phase** ไม่ block W3 core |
| W3.8 | ✅ `x-app-version` ถูกส่งทุก request โดย `AuthenticatedHttpClient` (`putIfAbsent` ทุก path) — 426 contract ทดสอบสดแล้ว 2026-10-03: ไม่มี header→426, `0.0.1`<min→426, `99.0.0`→200; `MIN_APP_VERSION_ENFORCE=false` คงไว้ใน dev (flip ชั่วคราวเพื่อทดสอบแล้ว revert) | 13.2 amendment (line 1801); เมื่อเปิด enforce ต้องให้ web build ส่งเวอร์ชันถูก — ✅ header ถูกส่งทุก request ครอบคลุม web |
| W3.9 | ✅ Passkeys: bundle ใน `web/index.html` ถูก annotate แล้วว่าเป็น **capability เท่านั้น ไม่ใช่ auth path** — ไม่มี Flutter/backend flow ที่อนุมัติ | Corbado คิดตาม MAU เมื่อเปิดใช้จริง → ต้องมี decision + budget approval; CSP ของ W4.4 ต้องไม่ทำให้ bundle เสีย |

**⚠️ Incident — Google sign-in บน web (เจอ+แก้แล้ว 2026-10-03; browser smoke ผ่านจริง):** จดจำสาเหตุกันซ้ำ

1. **`google_sign_in_web.signIn()` deprecated และไม่เคยได้ `idToken`** — popup flow คืนเฉพาะ access token + profile สังเคราะห์จาก People API → backend `/api/auth/social/google` verify ด้วย JWKS ไม่ผ่านเสมอ → **ต้องใช้ `GoogleSignInPlugin.renderButton()`** (credential flow — คืน JWT จริงผ่าน `GoogleSignInPlatform.userDataEvents`) แล้วส่ง `user.idToken` เข้า `_backendSocialLogin` path เดิมกับ mobile — ไม่สร้าง endpoint/auth path แยก (`widgets/google_web_sign_in_button*.dart`, `social_auth_service.signInWithGoogleCredential`)
2. **`serverClientId` ใช้ไม่ได้บน web** — plugin assert ทิ้ง (`serverClientId is not supported on Web`) → ส่งเฉพาะ mobile; client id บน web มาจาก meta `google-signin-client_id` ใน `index.html` เท่านั้น
3. **`GoogleSignIn()` constructor eager-init บน web** (`unawaited(_ensureInitialized())` ใน ctor) → `initWithParams` ชนกับ call อื่น → completer complete ซ้ำ → `Bad state: Future already completed` → widget ที่เรียก `initWithParams` ต้อง **swallow error นี้** (ไม่ถือ failure) แล้วให้ `renderButton` รอ `initialized` ของ plugin ต่อ — ดู `_ensureInitialized` ใน `google_web_sign_in_button_web.dart`
4. **People API** ถูกเรียกเฉพาะ flow เดิม (ดึง profile จาก access token); credential flow อ่าน claims จาก JWT — เปิดไว้ไม่เสียหายแต่ไม่จำเป็นแล้ว
5. **ops ที่ทำใน GCP แล้ว:** เพิ่ม `http://localhost:5050` + `http://127.0.0.1:5050` ใน Authorized JavaScript origins ของ Web client `…7ri50tfm…` (dev fix port 5050 เพราะ 5000 ชน macOS AirPlay/ControlCenter)
6. **`signOut()` บน web ต้องข้าม `_googleSignIn`** — `isSignedIn()`/method ใด ๆ ของ wrapper จะทริกเกอร์ `signInSilently` → One Tap prompt เองโดยไม่ตั้งใจ (guard `!kIsWeb` ไว้แล้ว)
7. **Android/iOS ต้องส่ง `--dart-define=GOOGLE_SERVER_CLIENT_ID=<Web client ID>` เสมอ** (run จาก IDE ที่ไม่ได้ใส่ run args จะลืมบ่อย) — ไม่มี `serverClientId` → Google ไม่คืน `idToken` → เจอ error "ไม่ได้รับ ID token จาก Google — ตรวจสอบ GOOGLE_CLIENT_ID/serverClientId" ทั้งที่ account picker ทำงานปกติ; default ใน `AppConfig` คือ `''` (เจอจริง 2026-10-03 บน physical Android)
8. **`Permission.locationAlways` throw `UnimplementedError` บน web** — `permission_handler_html` รองรับเฉพาะ mic/camera/notification/`location` (ไม่ใช่ `locationAlways`/`locationWhenInUse` เวอร์ชัน always) → บล็อก volunteer background-tracking ใน `HomePage._loadHomeData` ที่อยู่ใน try เดียวกันกับ article fetch พา exception ไป outer catch → **public articles/cards ไม่โหลดทั้งที่ Supabase ปกติ** → guard บล็อกด้วย `!kIsWeb` (เจอจริง 2026-10-03 ตอน direct-mode smoke; อาการ: บูตได้ การ์ดว่าง ไม่มี error ที่ชัดเพราะถูก catch กลืน)

**ค่าใช้จ่ายของ W3 — ทุกอย่างที่เปิดใช้อยู่ = 0 บาท:**

| รายการ | ตอนนี้ | ถ้าจะเปิดในอนาคต (ต้องอนุมัติก่อน) |
|--------|--------|-----------------------------------|
| Google OAuth (W3.1) | ฟรี — Web client ID มีใน GCP เดิม ไม่ต้องเปิด billing | — |
| Backend auth/socket/face-blur | self-hosted บน infra เดิม — ไม่มี per-request cost | — |
| Facebook/LINE/TikTok login | **ปิดบน web** (backend 501 fail-closed) | developer account ฟรี แต่ต้องสร้าง app + config credentials ฝั่ง backend ก่อนเพิ่มใน `webEnabled` |
| Apple Sign-In | **ปิดบน web** | ต้อง paid Apple Developer **$99/ปี** + Services ID (blocker เดิมจาก 13.2) |
| Corbado passkeys | bundle เป็น capability เท่านั้น ไม่มี flow เรียกใช้ | Corbado pricing ตาม MAU → อนุมัติ plan + `CORBADO_PROJECT_ID` + backend verify endpoint + ขยาย CSP `connect-src` |
| Google Maps บน web | `_isWebMapEnabled=false` คงเดิม (W4.5) | web Maps key แยก + HTTP referrer restriction → cost decision |
| httpOnly cookie token storage | คง localStorage ตาม 13.2 | เปิดแผน 15 (CSRF) เป็น P0 พร้อมกัน (W5.7) |

**งานค้างของ W3 ที่ทำจาก code ไม่ได้ (ops + smoke prerequisites):**

1. **GCP Console — Authorized JavaScript origins** (blocker เดียวของ Google sign-in บน web):
   - เข้า Google Cloud Console → APIs & Services → Credentials → เปิด **Web OAuth client** ตัวเดียวกับ `GOOGLE_CLIENT_ID` ใน `websocket-server/.env`
   - เพิ่ม `http://localhost:<port>` (dev — แนะนำ fix port ของ `flutter run -d web-server --web-port`) และ `https://<web-domain>` (prod เมื่อตัดสิน domain ใน W4)
   - ไม่ต้องแก้ Authorized redirect URIs (Flutter web ใช้ GIS ฝั่ง client)
   - ถ้าข้ามขั้นนี้ sign-in จะล้มด้วย `idpiframe_initialization_failed` / origin mismatch
2. **Backend ต้องรันและเข้าถึงได้**: `cd websocket-server && npm start` — IP ตาม `mainMachineIp` ใน `lib/config/app_config.dart` (ปัจจุบัน `192.168.0.123:8080`; เปลี่ยนเครือข่ายให้ทำตาม checklist ใน `docs/plans/VIDEO_SYSTEM_PLAN.md`) → browser smoke ทุกขั้นต้องให้ server up; dev web origin ต้องอยู่ใน `ALLOWED_ORIGINS` ของ `.env` ด้วย (W4.1 — env ops เท่านั้น)
3. **Browser smoke เมื่อ 1+2 พร้อม** (คำสั่งที่ใช้ verify):
   ```bash
   flutter run -d web-server --web-port=<port> \
     --dart-define=USE_BACKEND_AUTH=true \
     --dart-define=BACKEND_API_URL=http://<backend-host>:8080 \
     --dart-define=GOOGLE_SERVER_CLIENT_ID=<Web OAuth client ID>
   ```
   - login (Argon2id) + Google social บน Chrome ผ่าน; `/me` restore session หลัง reload
   - ปุ่ม provider: Google กดได้ / FB, Apple, LINE, TikTok แสดง disabled (opacity + tooltip) และไม่ยิง request
   - socket lifecycle: refresh → reconnect ด้วย token ใหม่ (ดู `auth.token` ใน handshake ใหม่); revoke/logout → disconnect และไม่ retry ด้วย token เดิม; direct mode (`USE_BACKEND_AUTH` ไม่ส่ง) เห็นเฉพาะ public allowlist
   - `x-app-version` header ถูกส่งทุก request; ทดสอบ 426 เมื่อ `MIN_APP_VERSION_ENFORCE=true`

**Verification:** login (backend mode) + Google social บน Chrome ผ่าน; `/me` restore session ทำงาน; direct mode เห็นเฉพาะ public; ไม่มี `x-user-id`/Supabase ID ถูกส่งเพื่อยกระดับ; token refresh แล้ว socket reconnect ด้วย token ใหม่; token หมดอายุ/revoke ไม่ retry ด้วย token เดิม; mobile provider/session UI ผ่าน Gate W3 ใน §4.4

---

### Phase W4 — Serving & CORS 🟢 ใช้ infra เดิม (13.0 พร้อมแล้ว)

| # | งาน | รายละเอียด |
|---|-----|-----------|
| W4.1 | ✅ **dev ทำแล้ว (2026-10-03):** `ALLOWED_ORIGINS` เพิ่ม `localhost/127.0.0.1` พอร์ต `:5050` `:5051` (flutter run 2 mode) และ `:8081` (Caddy-served web) + `192.168.0.123:8081` — verify preflight 204+ACAO ถูก origin, origin แปลกถูก reject (fail-closed); **staging/prod ต้องเพิ่ม domain web จริงเมื่อ deploy — ห้าม `*`** | 13.0 ทำ fail-closed + validator แล้ว (`Match_Sport` line 1463); Socket.IO ใช้ allowlist เดียวกัน (`server.js:114-116`) |
| W4.2 | ✅ **implement แล้ว (2026-10-03):** site block `:8081` ใน `Caddyfile.dev` เสิร์ฟ `{$CADDY_WEB_ROOT}` (default `../build/web` ผ่าน `start-caddy.sh`) + `{$CADDY_WEB_DOMAIN}` block ใน `Caddyfile.staging` (TLS auto + HSTS) — SPA `try_files {path} /index.html` verify แล้ว; **decision:** dev ทดสอบด้วย `admin.sheserved.com`, prod domain เปลี่ยนได้เมื่อเปิดใช้จริง; deploy host = Mac mini เครื่องหลัก | ไม่เพิ่ม infra (zero-cost); env ใหม่: `CADDY_WEB_DOMAIN`/`CADDY_WEB_ROOT` (template ใน `.env.example`) |
| W4.3 | ✅ **contract บันทึกแล้ว:** dev `http://<IP>:8080`/`ws://` ต่อไปได้ (origin allowlisted); **เมื่อเสิร์ฟ web ผ่าน HTTPS ต้อง build ด้วย** `--dart-define=BACKEND_API_URL=https://{$CADDY_STAGING_DOMAIN}` (websocket derive เป็น `wss://` จากค่าเดียวกัน — `AppConfig.backendApiUrl`) มิฉะนั้น mixed content block | `Caddyfile.staging` ทำ WSS ผ่าน `/socket.io/*` แล้ว (13.0) |
| W4.4 | ✅ **CSP implement แล้ว (2026-10-03)** ทั้ง dev (`:8081`) และ staging web block — allowlist: `script-src 'self' 'wasm-unsafe-eval' unpkg.com accounts.google.com/gsi/client`, `connect-src` = backend+Supabase REST/Realtime+GIS+fonts+unpkg, `frame-src accounts.google.com`, `worker-src 'self' blob:`, `object-src 'none'`, `frame-ancestors 'none'` — ไม่มี `unsafe-eval`; `unsafe-inline` เฉพาะ style (Flutter web จำเป็น) | `14_xss.md` ตัวเลือก C; ปรับ header ที่ host เท่านั้น ไม่เปลี่ยน Flutter auth/data path |
| W4.5 | ✅ **ตัดสินแล้ว (2026-10-03): คง `_isWebMapEnabled = false`** — เปิดเมื่อไหร่ต้องมี web Maps key แยก (HTTP referrer restriction) = cost decision ใหม่ | `Delivery_PLAN.md:98`, key guide |
| W4.6 | ✅ **profile กำหนดแล้ว (2026-10-03):** renderer = canvaskit (default, bundle ใน `/canvaskit/` — ไม่พึ่ง CDN); **build flag บังคับ: `--no-tree-shake-icons`** — icon code points ถูกเก็บใน DB แล้ว construct `IconData(raw)` ตอน runtime (เช่น `expert_status_helpers.dart:55`) → tree-shake build ล้ม; PWA/service worker = Flutter default; **cache headers ที่ host:** ทุกอย่าง `no-cache` ยกเว้น `/canvaskit/ /assets/ /icons/` = `max-age=86400` — verify ผ่าน curl; ⚠️ gotcha: Caddy เรียง header matcher ตาม specificity → ต้องใช้ `not path` disjoint matchers แทน global+override | ตรวจด้วย clean browser profile + hard reload ตอน staging; ไม่เพิ่ม runtime dependency หรือเปลี่ยน mobile build |

> **W4.2 exposure path — ตัดสินแล้ว (2026-10-03): Cloudflare Tunnel** (Option B) — เข้า router admin ไม่ได้ + ISP อาจ CGNAT → ไม่ port forward, TLS จบที่ Cloudflare edge; `admin.<domain>`→tunnel→`:8081` (web), `api.<domain>`→tunnel→`:8080` (API+socket); config template = `websocket-server/cloudflared/config.yml.example`; `Caddyfile.staging` + `CADDY_WEB_DOMAIN` คงไว้สำหรับอนาคตถ้าเปลี่ยนเป็น direct DNS/VPS

> **⏸️ W4 พักไว้ที่ domain purchase (2026-10-03)** — สิ่งที่ค้างรอดำเนินการต่อ:
>
> 1. **โดเมน (user's decision ค้างชำระ):** `sheserved.com` จดที่ GoDaddy แต่ account เจ้าของไม่ทราบ (account `Apisek.pu@gmail.com` ไม่มีโดเมน; whois ซ่อนด้วย Domains By Proxy; หมดอายุ 2027-01-17) → zone เพิ่มไว้ใน Cloudflare แล้วแต่ขึ้น "Invalid nameservers"; Cloudflare nameservers ที่ assign: `kia`/`todd.ns.cloudflare.com` — **แผนสำรองระหว่างรอ recover: ผู้ใช้อยู่หน้า checkout `sheserved.me` ($16.56/ปี)** — ทางเลือกถูกกว่า: `sheservedclinic.com`/`sheservedhub.com` (~$9.7/ปี, whois ว่าง ณ วันนั้น); ถ้าจ่ายเสร็จ → โดเมน active บน Cloudflare ทันที
> 2. **เมื่อได้โดเมน (ขั้นพร้อมรันทั้งหมด):** `cloudflared tunnel login` → `tunnel create sheserved` → `tunnel route dns` ให้ `admin.`+`api.` → copy `cloudflared/config.yml.example`→`~/.cloudflared/config.yml` แทน `<TUNNEL_ID>`+ชื่อโดเมนจริง → `tunnel run` ทดสอบ → `sudo cloudflared service install`
> 3. **ต้องแก้ตามโดเมนจริง:** `cloudflared/config.yml.example` (ตอนนี้เขียน `*.sheserved.com`), `ALLOWED_ORIGINS` (เพิ่ม `https://admin.sheserved.com` ล่วงหน้า — แก้เป็นโดเมนที่ซื้อจริง), GCP OAuth Authorized JavaScript origins, และ rebuild web: `flutter build web --no-tree-shake-icons --dart-define=USE_BACKEND_AUTH=true --dart-define=BACKEND_API_URL=https://api.<domain> --dart-define=GOOGLE_SERVER_CLIENT_ID=…`
> 4. **recover `sheserved.com` (งานแยก ไม่ block):** deep links ในแผน (`https://sheserved.com/sport-club/group/…`) ผูกกับโดเมนนี้ → ทาง recover: GoDaddy retrieve-by-domain (`account.godaddy.com/retrieve`), ถามคนเคยจด/ขอ Delegate Access, หรือฟอร์ม account recovery + เอกสารยืนยันตัวตน
> 5. **ทางลัดทดสอบทันที (ฟรี):** `cloudflared tunnel --url http://localhost:8081` → ephemeral `*.trycloudflare.com` URL (เปลี่ยนทุกครั้งรัน — เหมาะทดสอบ HTTPS/TLS path เท่านั้น ไม่เหมาะ OAuth origin)

---

### Phase W5 — Web Hardening (ก่อน production web) 🔴

| # | งาน | เอกสาร/Phase 13 อ้างอิง |
|---|-----|------------------------|
| W5.1 | Audit sanitize-on-render: user content ที่ render ใน DOM (chat, articles, rich text); `HtmlElementView`/`dart:html` ทุกจุด | `14_xss.md` X1/X6 |
| W5.2 | SVG upload policy — เสิร์ฟผ่าน browser จะ execute script | `14_xss.md` X9 |
| W5.3 | CSRF review: คง Bearer header auth (ต่ำ) — **ถ้า W3.4 เปลี่ยนเป็น cookie ในอนาคต → implement แผน 15 เต็มก่อน deploy** | `15_csrf.md` trigger |
| W5.4 | Socket contract ตาม 13.3: ห้ามส่ง `auth.userId`/raw identity จาก web client; anonymous socket = public allowlist เท่านั้น; strict/private rooms ต้อง Backend JWT; หลัง refresh/re-auth หรือ token expiry/revoke ต้อง reconnect ด้วย token ใหม่และห้าม retry ด้วย token เดิม | 13.3 P0-4, line 1693-1700; ใช้ `socket-auth.js`/rollout flags ที่มีอยู่ ไม่สร้าง path พิเศษสำหรับ web |
| W5.5 | `gitleaks` scan `web/` + `index.html` — ยืนยันไม่มี P2/P3; meta client ID (P1) และ maps key (P0+restriction) เท่านั้น | `07` ตัวเลือก E |
| W5.6 | CI: เพิ่ม `flutter build web` ใน pipeline เพื่อกัน dart:io ถดถอย | `06_dependency_vulnerabilities.md` |
| W5.7 | Token storage hardening decision: ยืนยันคง localStorage (Phase 13.2 contract) หรือเลื่อนเป็น memory-only access token / httpOnly cookie ตาม doc 08 — ถ้าเลือก cookie ให้เปิดแผน 15 พร้อมกัน | `08:116`, `15:87`; บันทึกว่า impl ปัจจุบัน persist access token ด้วย |

---

## 4. UI Regression Strategy และ Release Gate

### 4.1 Implementation contract สำหรับ UI mobile

กติกานี้เป็นส่วนหนึ่งของ definition of done ทุก phase ไม่ใช่คำแนะนำหลังเกิด regression:

- **Branch ที่ขอบระบบ:** ใช้ conditional import หรือ `kIsWeb` ที่ leaf implementation; ห้ามครอบ parent layout ทั้งหน้าเพื่อแก้ compile แล้วทำให้ widget tree ของ mobile เปลี่ยน
- **Geometry ต้องคงเดิม:** web fallback/placeholder ต้องอยู่ใน constraints เดิมและรักษา `SizedBox`, `AspectRatio`, `ConstrainedBox`, `Expanded`, `SafeArea`, `MediaQuery.padding/viewInsets`, `BoxFit`, typography, line limit และลำดับปุ่มเดิม เว้นแต่มี design decision ระบุไว้ใน phase นั้น
- **Native-only feature:** เมื่อ web ไม่รองรับ ให้แทนด้วย placeholder ที่มีขนาดเทียบเท่าและข้อความที่อ่านได้ ไม่ใช่ลบ child จน parent ยุบหรือเกิดช่องว่างที่ไม่ตั้งใจ
- **Provider/feature list:** สร้างรายการปุ่มหรือ feature ตาม platform ที่ boundary; mobile ต้องคงรายการ/ตำแหน่งเดิม ส่วน web จึงกรอง provider ที่ backend ยังไม่รองรับตาม W3.3
- **Content hardening:** sanitize user content โดยคง TextStyle, max lines, overflow และ constraints เดิม; ต้องทดสอบข้อความยาว ภาษาไทย/emoji และ payload ที่ถูกตัดออกแล้วไม่ทำให้ layout overflow
- **Shared widget safety:** การเปลี่ยน shared widget ต้องมี test อย่างน้อยหนึ่งกรณีสำหรับ iOS และ Android semantics; ห้ามถือว่า `kIsWeb` guard เพียงอย่างเดียวพิสูจน์ว่า mobile UI ไม่เปลี่ยน

### 4.2 Baseline และ device matrix

ก่อนเริ่ม W0 ต้องเก็บ baseline ไว้ในผลทดสอบของ phase (ไม่จำเป็นต้อง commit binary screenshot หาก repo ไม่เก็บ artifact):

1. ผล `flutter analyze`, `flutter test` และ `git diff --check`
2. Screenshot/golden ของ Login, MainAppLayout/Home, bottom navigation, Chat/preview และหน้าที่ W0/W1 จะแตะ
3. ผล no-overflow และ interaction smoke บนขนาดหน้าจอด้านล่าง
4. Flutter/Dart version, OS, device model, orientation และสถานะ keyboard/safe-area ของการทดสอบ

| กลุ่ม | ขนาด logical ที่ต้องตรวจ | ประเด็นเฉพาะ |
|---|---:|---|
| iOS compact | `320×568` | ข้อความยาว, bottom inset, keyboard |
| iOS standard/notch | `393×852` | SafeArea, home indicator, overlay |
| Android compact | `360×800` | gesture/navigation bar, bottom navigation |
| Android large | `412×915` | การขยายของ Row/Expanded และ preview |
| Landscape | `844×390` หรือเทียบเท่า | overflow, sheet/dialog, video/map |

ใช้ iPhone 16 Simulator และ iPhone physical ตาม `docs/guides/TEST_PLAN.md`; ต้องเพิ่ม Android emulator/device ที่ระบุรุ่นและ device ID ก่อนถือว่า mobile gate ครบ — **iOS ผ่านเพียงแพลตฟอร์มเดียวไม่ถือว่าผ่าน**

### 4.3 Automated และ device verification gate

คำสั่งขั้นต่ำต่อ phase ที่มีการแก้ Dart/shared code:

```bash
flutter analyze
flutter test
flutter build web --no-tree-shake-icons   # IconData แบบ dynamic จาก DB (expert_status_helpers.dart) ปิด tree-shake ทั้งแอป — flag นี้คง behavior เดิม
flutter build apk --debug
flutter build ios --simulator --debug
```

หมายเหตุ WASM (พบจาก build จริง): `flutter_secure_storage_web`/`ua_client_hints` ใช้ `dart:html`/`dart:js_util` → เสิร์ฟได้เฉพาะ JS build; หากต้องการ `--wasm` ต้องเปลี่ยน storage impl ใน W5

`flutter build apk`/`flutter build ios` ให้รันใน runner หรือเครื่องที่รองรับ platform นั้น หาก environment ไม่พร้อมต้องระบุเป็น **blocked evidence** ไม่ใช่ข้าม gate เงียบ ๆ ส่วน UI/device gate ต้องตรวจเพิ่ม:

- ไม่มี `RenderFlex overflow`, layout exception, missing asset หรือ `setState() after dispose`
- screenshot เทียบ baseline ไม่มีการเปลี่ยน mobile layout โดยไม่มี decision ที่บันทึกไว้
- primary action, bottom navigation, keyboard avoidance, SafeArea และ touch target ใช้งานได้
- upload/preview flow ผ่านโดยคง IO path บน mobile และไม่เพิ่ม memory spike ที่ยอมรับไม่ได้
- Maestro smoke/regression รันบน iOS และ Android ตาม flow ที่แตะต้อง; เก็บผล, screenshot, device และ commit SHA เป็น evidence

### 4.4 Acceptance gate ราย phase

| Phase | Gate ที่ต้องผ่านก่อน merge/deploy | หลักฐานผ่าน |
|---|---|---|
| **W0** | Web compile/boot ผ่าน; `dart:io`/native-only import ถูกแยก; Login/Home/MainAppLayout และ bottom navigation ไม่ overflow บน iOS/Android; health/map ยังใช้ native path บน mobile | `flutter build web`, analyzer/tests, mobile build + UI smoke, screenshot baseline diff |
| **W1** | Web upload/preview/export ผ่าน; mobile คง `fromPath`/`File` path และ preview geometry เดิม; chat/avatar/emergency media ผ่าน | web media evidence, iOS+Android upload/preview smoke, memory/overflow check |
| **W2** | ทุก feature decision มี owner/behavior ระบุ; web fallback ไม่ทำให้ parent ยุบ; compass/health/camera/WebRTC บน mobile ไม่ถูกซ่อนหรือเปลี่ยนโดยไม่ตั้งใจ | decision record, feature smoke, mobile screenshot/no-overflow evidence |
| **W3** | Backend auth/social web flow ผ่าน; mobile login/session/provider UI เหมือน baseline; การกรอง provider เกิดเฉพาะ web; socket reconnect ใช้ token ใหม่หลัง refresh และ fail closed เมื่อ token หมดอายุ/revoke; passkeys status ไม่อ้างเกิน implementation จริง | Chrome auth evidence, socket lifecycle evidence, iOS+Android login/session smoke, provider layout comparison |
| **W4** | Caddy/CORS/HTTPS/WSS ผ่าน staging; mobile app build และ core smoke ผ่านโดยไม่มี source/config regression | staging evidence, web smoke, mobile build/smoke result |
| **W5** | sanitize/SVG/CSP/socket hardening ผ่าน; content ยาว/unsafe ไม่ทำให้ mobile chat/article overflow; CI/gitleaks/build gate ผ่าน | security evidence, mobile content regression, CI artifacts และ rollback readiness |

### 4.5 Stop และ rollback criteria

- ทำแต่ละ phase เป็น commit แยก; ห้าม merge phase ถัดไปเมื่อ gate ของ phase ปัจจุบันไม่ผ่าน
- หากพบ mobile screenshot/layout/interaction regression ให้หยุด rollout, ปิด web branch/feature flag ที่เกี่ยวข้องชั่วคราว และ revert เฉพาะ commit ของ phase นั้น — ห้ามแก้ด้วยการเพิ่ม `try/catch`, ลดความเข้มของ test หรือซ่อน widget แบบไม่มี constraints
- หลัง rollback ต้องรัน `git diff --check`, `flutter analyze`, regression tests และ mobile smoke ซ้ำ พร้อมเก็บผลเทียบ baseline
- ความแตกต่างของ mobile UI ที่ตั้งใจให้เกิดต้องมี design decision, screenshot ใหม่, เหตุผล และผู้อนุมัติใน evidence ของ phase; มิฉะนั้นถือเป็น regression
- เมื่อ gate ผ่านแล้วจึง deploy ได้ตาม Q1-B; ทุก artifact ต้องระบุ commit SHA, build mode, device/OS และ test command ที่ใช้

---

## 5. Checklist ก่อน implement (รอการตัดสินใจ)

- [x] อนุมัติ Phase W0/W1 (compile unblock + file abstraction — อิสระจาก Phase 13) — ✅ implement+verify แล้ว
- [x] ตัดสินใจ W2: face blur = server-side ผ่าน `POST /api/media/face-blur` (deface ท้องถิ่น ไม่มีค่าใช้จ่าย); compass ซ่อนบน web; polyline ปิดบน web — ✅ implement แล้ว
- [x] ยืนยัน W3.2: web dev ใช้ `USE_BACKEND_AUTH=true` — ต้องเปิด server + origin ใน `ALLOWED_ORIGINS`
- [x] ยืนยัน W3.3: แสดงทุก provider แต่ disabled บน web เว้น Google — `SocialProviderPolicy.webEnabled` เป็น flag เดียว; Apple รอ paid dev account ($99/ปี)
- [x] ยืนยัน W3.6 socket token lifecycle: implement ผ่าน `tokenChanges` + `refreshTokens()` — refresh → reconnect ด้วย token ใหม่, revoke/expiry → หยุดไม่ retry token เดิม
- [x] ตรวจ W3.9 passkeys bundle: คงไว้เป็น capability เท่านั้น ไม่ประกาศเป็น auth flow — Corbado คิดตาม MAU เมื่อเปิดจริง
- [x] บันทึก mobile baseline (screenshot/no-overflow/analyze/test) ตาม matrix ในส่วน 4.2 — ✅ 2026-10-03, ดูหลักฐานท้าย W1 + `docs/evidence/w0w1_mobile_baseline/`
- [x] เตรียม Android emulator/device และระบุรุ่น/device ID สำหรับ mobile gate — ✅ `Copy_of_6.7_API_30` (emulator-5554, 360×879), `Sunmi_V2s_PLUS_API_30` (emulator-5556, 411×868), physical CPH1989 `DMM7OZFESSFA995L` (360×693, Android 11)
- [x] ops (ทำจาก code ไม่ได้): เพิ่ม web origin ใน Authorized JavaScript origins ของ Google Web client ใน GCP Console (W3.1) — ✅ 2026-10-03 เพิ่ม `http://localhost:5050` + `http://127.0.0.1:5050` ใน Web client `1075504521633-7ri50…` แล้ว (prod origin เมื่อตัดสิน domain ใน W4)
- [x] ops (ทำจาก code ไม่ได้): เปิด backend (`websocket-server`) + เพิ่ม dev web origin ใน `ALLOWED_ORIGINS` แล้วรัน browser smoke ตามขั้นตอนในตาราง W3 — ✅ 2026-10-03 `ALLOWED_ORIGINS=http://localhost:5050,http://127.0.0.1:5050`; browser smoke ผ่าน (login Argon2id + Google GIS credential + session restore + disabled providers + socket lifecycle บน Android + 426 contract) — ✅ direct-mode smoke ผ่านครบ (`:5051` ไม่ส่ง `USE_BACKEND_AUTH`, verify 2026-10-03): บูต + public articles/cards โหลด (หลังแก้ incident #8 — guard `!kIsWeb` บล็อก volunteer location ใน `home_page.dart`); **Argon2id account login ไม่ผ่าน = expected** (verify ได้เฉพาะ backend — บัญชี sha256 ที่ยังไม่ migrate ยัง login ผ่าน legacy `.eq('password_hash', …)` path ได้แต่จะไม่ upgrade เอง, lazy rehash เกิดเฉพาะผ่าน `/api/auth/login`); ไม่มี private data รั่ว; ⚠️ ระวังรัน 2 `flutter run` พร้อมกันใน repo เดียว — ชน `build/flutter_assets` → `ShaderCompilerException` ให้ start ทีละตัว
- [ ] ตัดสินใจ W5.7: token storage บน web — คง localStorage ตาม 13.2 หรือลงทุน httpOnly cookie + CSRF (แผน 15) พร้อมกัน
- [x] ตัดสินใจ W4.5: **คงปิด Google Maps บน web** (2026-10-03) — เปิดในอนาคต = web Maps key แยก + referrer restriction (cost decision)
- [ ] ตัดสินใจ domain เสิร์ฟ web — ⏸️ **พักที่ checkout** (2026-10-03): `sheserved.com` เข้าถึง account เจ้าของไม่ได้ → ผู้ใช้พิจารณาซื้อ `sheserved.me` ($16.56/ปี) หรือ `.com` แปรผัน (~$9.7) ที่ Cloudflare Registrar — เมื่อได้โดเมน: sync ชื่อเดียวกันใน tunnel config, `ALLOWED_ORIGINS`, GCP OAuth origins, build define; deploy host = Mac mini เครื่องหลัก (ผ่าน Cloudflare Tunnel, ไม่ port forward)
- [x] ยืนยัน W4.4 external origins ใน CSP และ W4.6 renderer/service-worker/cache-busting profile — ✅ implement + curl verify แล้ว (เหลือ staging verify ด้วย clean browser profile เมื่อ deploy)

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `docs/plans/Match_Sport_PLAN.md` Phase 13 | **แผนนี้อยู่ภายใต้สัญญา Phase 13** — W3/W4/W5 อิงสิ่งที่ 13.0/13.1/13.2 ส่งมอบแล้วและ 13.3 ที่มี `socket-auth`/rollout wiring บางส่วน; room/event/token-lifecycle gate ที่เหลือต้องใช้ contract เดิมและห้ามสร้าง auth path แยกสำหรับ web |
| `docs/design/PHASE_13_2_TEMPORARY_DIRECT_AUTH_DEVELOPMENT_PLAN.md` | W3.2 coexistence matrix ตามเอกสารนี้ |
| `docs/secure/README.md` rollout rules | ✅ Q1-B ทุก phase deploy ได้อิสระ; ไม่เปลี่ยน AuthService/ServiceLocator |
| `docs/secure/04_security_misconfiguration.md` | W4.1/W4.4 เป็นงานเดียวกับแผน 04 (M1, headers) — CORS ทำเสร็จใน 13.0 แล้ว |
| `docs/secure/07_secret_management.md` | dart-define เดิม; client ID = P1, maps key = P0+restriction |
| `docs/secure/08_session_token_security.md` | W3.4 บันทึก deviation ที่เป็นรูปธรรม (impl persist access token) + target httpOnly cookie |
| `docs/secure/14_xss.md` | W5 ครอบคลุม X1/X6/X9 |
| `docs/secure/15_csrf.md` | trigger-based — activate เมื่อใช้ cookie |
| `docs/secure/17_phase_13_1_supabase_spike_runbook.md` | ไม่เกี่ยวข้องโดยตรง (DB-side) — web ใช้ผลลัพธ์ของ 13.1 ผ่าน API เท่านั้น |
| `docs/infrastructure/reverse_proxy_plan.md` | เสิร์ฟ web ผ่าน Caddy slot ที่เตรียมไว้; `Caddyfile.staging` เป็น template (zero-cost); domain จริงต้องถูกยืนยันก่อนผูก Caddy/CORS/OAuth/CSP |
| `docs/infrastructure/architecture_analysis.md` | web client เข้าผ่าน path เดิม (Caddy → websocket-server) ไม่เปลี่ยน architecture |
| `docs/plans/Delivery_PLAN.md` | คง maps-off บน web ตาม cost-zero intent |
| `docs/guides/TEST_PLAN.md` | ใช้ Maestro smoke/regression, iOS simulator/physical device และต้องเพิ่ม Android device evidence ตาม UI release gate §4 |
| `.agent/workflows/auth_data_guidelines.md` | ใช้ `ServiceLocator.instance.currentUser` เท่านั้น |
