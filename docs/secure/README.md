# แผนความปลอดภัย Sheserved (Security Plans)

> **วันที่สร้าง:** 2026-07-26
> **สถานะ:** 📋 แผนเพื่อการตัดสินใจ — **ยังไม่ลงมือ implement จนกว่าจะได้รับอนุมัติ**
> **ขอบเขต:** ครอบคลุมทุกระบบใน Sheserved ทั้งที่ implement แล้ว, ที่วางแผนไว้ใน `docs/plans/`, และแผนย่อยทั้งหมดใน `docs/ERP/`
> **ข้อจำกัด:** ทุกแผนต้องสอดคล้องกับ `docs/infrastructure/` และ `.agent/workflows/auth_data_guidelines.md` (custom AuthService — ไม่ใช้ Supabase Auth session)

---

## สารบัญแผน

| # | หัวข้อ | ไฟล์ | ระดับความเสี่ยงปัจจุบัน | Priority |
|---|--------|------|------------------------|----------|
| 1 | Broken Object Level Authorization (BOLA/IDOR) | `01_broken_object_level_authorization.md` | 🔴 สูง | P0-A |
| 2 | Path Traversal & Command Injection | `02_path_traversal_command_injection.md` | 🔴 สูง | P0-A |
| 3 | Rate Limiting & Resource Exhaustion | `03_rate_limiting_resource_exhaustion.md` | 🔴 สูง | P0-A |
| 4 | Security Misconfiguration & Error Handling | `04_security_misconfiguration.md` | 🔴 สูง | P0-A |
| 5 | Logging, Audit Trail & Monitoring | `05_logging_audit_monitoring.md` | 🔴 สูง | P0-A |
| 6 | Dependency Vulnerabilities | `06_dependency_vulnerabilities.md` | 🔴 สูง | P0-A |
| 7 | Secret Management | `07_secret_management.md` | 🔴 สูง | P0-A |
| 8 | Session & Token Security | `08_session_token_security.md` | 🔴 สูง | P0-A |
| 9 | Authentication & Authorization | `09_authentication_authorization.md` | 🔴 สูง | P0-A |
| 10 | Password Hashing | `10_password_hashing.md` | 🔴 สูง | P0-B |
| 11 | Input Validation | `11_input_validation.md` | 🟡 กลาง | P0-B |
| 12 | Principle of Least Privilege | `12_least_privilege.md` | 🔴 สูง | P0-C |
| 13 | SQL Injection | `13_sql_injection.md` | 🟢 ต่ำ–กลาง | P1 |
| 14 | Cross-Site Scripting (XSS) | `14_xss.md` | 🟡 กลาง | P1 |
| 15 | CSRF | `15_csrf.md` | 🟡 ต่ำปัจจุบัน | P2 / trigger-based |
| 16 | Server-Side Request Forgery (SSRF) | `16_ssrf.md` | 🟡 กลาง / P0 ก่อน integration | P1 / trigger-based |

> **แผน 01–07** — Containment และ Quick Wins (Phase S0-A): ปิดช่องโหว่ที่มีหลักฐานในโค้ดจริงและต้นทุนต่ำ
> **แผน 08–11** — Identity Foundation (Phase S0-B): สร้าง signed identity ก่อน migration authentication/RLS
> **แผน 12** — Data Authorization (Phase S0-C): RLS/tenant/branch policies หลัง identity พร้อมใช้งาน
> **แผน 13–16** — Defense in Depth (Phase S1): regression control และ trigger-based measures

### ความสัมพันธ์ระหว่างแผน (กันทำงานซ้ำ)

| หัวข้อที่ทับซ้อน | แผนที่เกี่ยวข้อง | ข้อตกลง |
|-----------------|------------------|---------|
| `helmet` / security headers | 14 (XSS) + 04 (Misconfig) | implement ครั้งเดียวในแผน 04 |
| CORS allowlist | 15 (CSRF) + 04 (Misconfig) | implement ครั้งเดียวในแผน 04 |
| Account lockout | 09 (G5) + 03 (R7) | implement ครั้งเดียวในแผน 03 |
| Audit log | 09 (G6) + 12 (L10) + 05 | ใช้ตาราง `audit_logs` เดียวตามแผน 05 |
| Row Level Security | 12 (L2) + 01 (O2) | เป็นงานเดียวกัน — ดำเนินการในแผน 12 |
| Disk quota / cleanup | 02 (PT10) + 03 (R9) | implement ในแผน 03 |
| Static file headers | 14 (X8) + 02 (PT6) | implement ครั้งเดียว |
| UUID validation | 11 (V7) + 02 (PT1) | schema เดียวกัน |
| Environment separation | 07 (K3) + 04 (M5) | งานเดียวกัน |

---

## สถาปัตยกรรมปัจจุบัน (สรุปเพื่ออ้างอิงทุกแผน)

### องค์ประกอบหลัก
- **Flutter App** (`lib/`) — iOS / Android / Web
- **Supabase Cloud** (`psxcgdwcwjdbpaemkozq.supabase.co`) — PostgreSQL + Storage + Realtime, client เชื่อมด้วย **anon key** โดยตรง
- **websocket-server** (Node.js/Express + Socket.IO) — Local API, video upload, escrow, queues (Redis), PostgreSQL local
- **Custom AuthService** — session ใน memory ฝั่งแอป (ตาม `auth_data_guidelines.md` **ห้าม**ใช้ `Supabase.instance.client.auth.currentUser`)

### จุดที่ตรวจพบจากโค้ดจริง (Snapshot 2026-07-26)
| ประเด็น | สถานะปัจจุบัน | ไฟล์อ้างอิง |
|---------|--------------|-------------|
| Password hashing | SHA-256 **ไม่มี salt**, hash ฝั่ง client | `lib/features/auth/data/repositories/user_repository.dart` |
| Object ownership | หลาย endpoint รับ `userId` จาก request body แทน `req.userId` | `websocket-server/routes/video.js:89, 159, 536, 699` |
| Filesystem path | `incidentId` จาก body ถูกนำไปประกอบ path โดยไม่ validate | `websocket-server/routes/video.js:195` |
| Upload limit | multer 500MB แต่ business rule 20MB (เขียนก่อนปฏิเสธ) | `websocket-server/routes/video.js:44, 97` |
| Error response | บาง route ส่ง `err.message` กลับถึง client | `video.js:567`, `admin.js:107` |
| Logging | `console.log` อย่างเดียว — ไม่มี level / requestId / audit trail | ทั่ว `websocket-server/` |
| Outbound request | ใช้ URL จาก env เท่านั้น ✅ (แต่ไม่มี timeout/allowlist) | `services/video-service.js:61` |
| Session | in-memory เท่านั้น หายเมื่อปิดแอป, ไม่มี token | `lib/services/auth_service.dart` |
| Backend identity | เชื่อ `x-user-id` header (spoofable), JWT decode แบบไม่ verify signature | `websocket-server/middleware/auth.js` |
| Secrets | Supabase URL + anon key hardcode ในโค้ด | `lib/config/app_config.dart` |
| SQL | ใช้ parameterized query (`$1`) สม่ำเสมอ ✅ | `websocket-server/routes/*.js` |
| Rate limiting | มี authRateLimiter / strictRateLimiter ✅ | `websocket-server/middleware/rate-limiter.js` |
| Route guard (แอป) | `AuthGuardWidget` role-based ✅ (client-side เท่านั้น) | `lib/core/guards/auth_guard_widget.dart` |
| RLS | มีบางส่วน (registration RLS 42501) แต่ไม่ครบทุกตาราง | Supabase migrations |

### ระบบที่ต้องครอบคลุม (17 ระบบหลัก + แผนอนาคต)
1. Auth & Registration · 2. Home & Navigation · 3. Consultation & ChartBoard · 4. Chat & Video Call · 5. Pharmacy & Drug Risk · 6. Donation (รวม escrow) · 7. Emergency & Rescue · 8. Health & Articles · 9. Profile & Settings · 10–15. ERP (Dashboard, Inventory, Procurement, Sales/POS, Finance/HR, Clinical) · 16. Admin & KPI · 17. Community
+ แผนอนาคต: Delivery, Shopping Cart, Video System, CRM, HIS, LAB, Accounting, Subscription (ตาม `docs/plans/` และ `docs/ERP/`)

---

## ลำดับการ implement ใหม่ (ผลทบทวน 2026-07-27)

การจัดลำดับเดิมเริ่มจาก password hashing ทั้งที่ backend ยังยืนยันตัวตนจาก header ที่ปลอมได้ และยังมี BOLA/path/upload vulnerabilities ที่แก้ได้ทันที ดังนั้นลำดับใหม่ให้ **ปิดช่องโหว่ที่ exploit ได้จริงก่อน**, วาง observability, แล้วจึงทำ migration authentication/RLS แบบมีแผน rollback

```
Phase S0-A — Containment และ Quick Wins (ทำก่อน deploy ฟีเจอร์ใหม่, 1–2 สัปดาห์):
  1. 01 BOLA: ใช้ req.userId, ownership-scoped query, หยุดรับ userId/role/status จาก body
  2. 02 Path/Command: safe-path + UUID validation + upload filename/path isolation
  3. 03 Resource: จำกัด upload ก่อนเขียนดิสก์, cleanup, pagination/queue/timeout limits
  4. 04 Misconfiguration: ALLOWED_ORIGINS แบบบังคับ, helmet, generic errors, startup validation
  5. 05 Logging: structured logs, requestId, redaction, security event baseline
  6. 06 Dependencies: CI vulnerability scan + lockfile verification
  7. 07 Secrets: secret scanning, env separation, key inventory/rotation runbook

Phase S0-B — Identity foundation (ทำเป็นชุดเดียวและมี compatibility window):
  8. 08 Session/Token: signed access token + refresh/revocation design
  9. 09 AuthN/AuthZ: เลิกเชื่อ x-user-id, verify token signature, server-side authorization
  10. 10 Password: server-side Argon2id (bcrypt เป็น fallback) + migration/rehash strategy
  11. 11 Input Validation: schema/DTO/allowlist layer ที่ใช้ร่วมกับ auth และ endpoint สำคัญ

Phase S0-C — Data authorization (หลัง identity ใช้งานจริง):
  12. 12 Least Privilege: RLS/tenant/branch/field-level policies + service-account separation

Phase S1 — Defense in depth:
  13. 13 SQL Injection: audit/lint และ dynamic-query allowlist (แม้ปัจจุบันใช้ parameters ดี)
  14. 14 XSS: sanitize rich text, safe URL/WebView, CSP/static file isolation สำหรับ web
  15. 15 CSRF: ทำเมื่อใช้ cookie/session บน browser; ปัจจุบันใช้ bearer/custom header จึงเป็น trigger-based
  16. 16 SSRF: สร้าง safe-http client ก่อนเพิ่ม integration ที่รับ URL จาก user/env ที่เปลี่ยนได้
```

### เหตุผลที่เปลี่ยนลำดับ

- **BOLA/path/resource/misconfiguration** มีหลักฐานจากโค้ดปัจจุบันและมีผลกระทบโดยตรง จึงต้องมาก่อนงานออกแบบใหญ่
- **Logging และ dependency scanning** เป็น control ที่ต้นทุนต่ำ แต่จำเป็นต่อการตรวจสอบว่าแผนอื่นทำงานจริง
- **Token ต้องมาก่อน authorization** เพราะ backend ปัจจุบันยังมี identity spoofing; password migration ต้องอยู่หลัง endpoint auth พร้อมและต้องรองรับ hash เดิมชั่วคราว
- **RLS/least privilege ต้องหลัง identity** เพราะ policy ต้องรู้วิธีส่ง identity ที่ verify แล้วเข้า DB และต้อง rollout ตามกลุ่มข้อมูล ไม่เปิดใช้รวดเดียวทั้งระบบ
- **CSRF และ SSRF เป็น trigger-based**: CSRF จะเร่งด่วนเมื่อใช้ cookie; SSRF ต้องยกระดับก่อน integration ที่รับ URL ภายนอก ไม่ควรใช้ทรัพยากร P0 ก่อนพบ attack surface จริง

> **กติกา rollout:** ทุก phase ต้องมี tests, metrics, rollback plan และไม่เปลี่ยน `AuthService`/`ServiceLocator` ไปใช้ `Supabase.instance.client.auth.currentUser` ซึ่งขัดกับ `.agent/workflows/auth_data_guidelines.md`
