# แผนป้องกัน 04: Security Misconfiguration และ Error Handling

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 14 (XSS — security headers), 15 (CSRF — CORS), 07 (Secrets — environment), 06 (Dependencies), 05 (Logging)
> **ขอบเขต:** ช่องโหว่ที่เกิดจาก **การตั้งค่า** ไม่ใช่ business logic — OWASP จัดเป็นอันดับต้น ๆ เพราะพบบ่อยและแก้ง่ายที่สุด
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 4** และเป็น deployment gate ทุก environment
> **เหตุผล:** CORS wildcard, error leakage และ startup config ที่ไม่บังคับเป็นความเสี่ยงที่แก้ได้เร็วและลด blast radius ของแผนอื่น; `helmet`/headers และ CORS ให้ implement ที่แผนนี้เพียงจุดเดียวตาม dependency map

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ทำได้ดีอยู่แล้ว ✅
| จุด | รายละเอียด |
|-----|------------|
| CORS มี warning | โค้ดเตือนเมื่อ `ALLOWED_ORIGINS = '*'` |
| Error message ส่วนใหญ่เป็นข้อความทั่วไป | `{ error: 'Failed to fetch videos' }` ไม่เปิดเผยรายละเอียด |
| DB credentials อยู่ใน env | ไม่ hardcode |
| Rate limiting มีอยู่ | middleware พร้อมใช้ |

### จุดที่ต้องปิด — พร้อมหลักฐานจากโค้ดจริง

**1. CORS default เป็น `*` พร้อม `credentials: true`** 🔴
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/server.js:67-87
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '*')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

const corsOptions = {
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, server-to-server)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes('*')) {
      console.warn('[Security] CORS is set to "*" — restrict ALLOWED_ORIGINS in production');
      return callback(null, true);
    }
```
ถ้าลืมตั้ง env ใน production ระบบจะเปิดกว้างโดยเงียบ ๆ (มีแค่ warning ใน log)

**2. Error message รั่วรายละเอียดภายในถึง client** 🟡
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:565-568
        } catch (error) {
            console.error('Accept Incident Error:', error.message);
            res.status(500).json({ error: 'Failed to accept incident', detail: error.message });
        }
```
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/admin.js:105-108
        } catch (err) {
            console.error('Error uploading watermark image:', err);
            res.status(500).json({ error: err.message || 'Server error during upload' });
        }
```
`detail: error.message` และ `err.message` จาก PostgreSQL/multer เปิดเผยชื่อตาราง, constraint, path ภายใน

**3. ไม่มี security headers**
ไม่พบการใช้ `helmet` หรือการตั้ง header ด้าน security ใด ๆ ใน `server.js`

**4. ไม่มี global error handler**
แต่ละ route จัดการ error เอง รูปแบบไม่สม่ำเสมอ — บาง route ไม่มี catch เลย (เช่น async ที่ไม่ห่อ)

**5. Placeholder credentials ในโค้ด**
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/services/video-service.js:65-68
    if (!apiKey || !storageZone || apiKey === 'your_api_key_here') {
        console.warn('[Bunny.net] API Key not configured. Skipping upload.');
        return;
    }
```
รูปแบบ "ถ้าไม่ตั้งค่าก็ข้ามไปเงียบ ๆ" ปรากฏหลายจุด (`BUNNY_CDN_URL === 'https://your-pull-zone.b-cdn.net'`) — production อาจทำงานผิดโดยไม่มีใครรู้

**6. `console.log` ข้อมูลละเอียดใน production**
`[Gallery] Returning ... photos`, `[ThaiMhung] Inserting photo: incidentId=..., url=...` — log ระดับ debug ทำงานตลอดเวลา

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| M1 | **CORS default เปิดกว้าง** | 🔴 สูง | fail-open แทนที่จะ fail-closed |
| M2 | **Error detail รั่วถึง client** | 🟡 กลาง | `detail: error.message`, `err.message` |
| M3 | **ไม่มี security headers** | 🟡 กลาง | ไม่มี HSTS, nosniff, frame-options, CSP |
| M4 | **ไม่มี global error handler** | 🟡 กลาง | unhandled error อาจส่ง stack trace ผ่าน Express default handler |
| M5 | **ไม่แยก environment ชัดเจน** | 🔴 สูง | dev/staging/prod ใช้ Supabase เดียวกัน (ทับกับแผน 07 K3) |
| M6 | **Debug log เปิดตลอดเวลา** | 🟡 กลาง | ไม่มี log level |
| M7 | **`X-Powered-By: Express` เปิดอยู่** | 🟢 ต่ำ | เปิดเผย technology stack |
| M8 | **ไม่มี request body size limit ต่อ endpoint** | 🟡 กลาง | (ทับกับแผน 03) |
| M9 | **Config ผิดพลาดแล้วระบบยังทำงานต่อ** | 🟡 กลาง | ควร fail fast ตอน startup |
| M10 | **ไม่มี HTTPS enforcement** | 🔴 สูง | ต้องยืนยันว่า reverse proxy บังคับ TLS |
| M11 | **ไม่มี graceful shutdown ที่สมบูรณ์** | 🟢 ต่ำ | มี `shutdownConsultationQueue` แล้ว แต่ยังไม่ครบทุก service |
| M12 | **Static file directory listing** | 🟡 กลาง | ต้องยืนยันว่าปิดแล้ว |
| M13 | **ไม่มี health check ที่แยก public/internal** | 🟢 ต่ำ | health endpoint ไม่ควรเปิดเผยเวอร์ชัน/สถานะ dependency ต่อสาธารณะ |
| M14 | **Redis/PostgreSQL อาจ bind ทุก interface** | 🔴 สูง | ต้องยืนยันว่า bind เฉพาะ localhost/private network |
| M15 | **ไม่มี startup config validation** | 🟡 กลาง | ไม่ตรวจว่า env ที่จำเป็นถูกตั้งครบ |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 มิติของการตั้งค่าที่ต้องดูแล

| ชั้น | สิ่งที่ต้องตรวจ | สถานะ |
|-----|----------------|-------|
| **Flutter app** | build mode (release ไม่มี debug banner/log), obfuscation, `flutter_launcher_icons`, network security config | ต้องตรวจ |
| **Express server** | headers, CORS, body limit, error handler, trust proxy | 🔴 ต้องเพิ่ม |
| **Socket.IO** | CORS, transport, ping timeout, max buffer size | ต้องตรวจ |
| **PostgreSQL** | bind address, `ssl`, connection limit, log level, default user | ต้องตรวจ |
| **Redis** | bind address, `requirepass`, protected mode, maxmemory policy | ต้องตรวจ |
| **Reverse proxy** | TLS version, cipher, HSTS, redirect HTTP→HTTPS | ตาม `reverse_proxy_plan.md` |
| **Supabase** | RLS enabled, bucket public/private, API settings | 🔴 (แผน 12) |
| **OS / Container** | non-root user, firewall, open ports, automatic updates | ต้องตรวจ |
| **CI/CD** | secret handling, artifact retention, branch protection | ต้องตรวจ |

### 2.2 ผลกระทบต่อระบบตามแผน

| แผน | ประเด็นการตั้งค่าเฉพาะ |
|-----|----------------------|
| `docs/infrastructure/reverse_proxy_plan.md` | 🔴 จุดศูนย์กลางของ TLS + security headers — ควร implement พร้อมแผนนี้ |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | bind address, SSL mode, user privilege |
| `docs/infrastructure/caching_strategy.md` | Redis maxmemory policy, eviction, persistence |
| `docs/infrastructure/SETUP_NEW_MACHINE.md` | ต้องเพิ่ม security baseline checklist |
| `docs/ERP/ERP_CORE_ARCHITECTURE.md` | Multi-tenant — config ต่อ tenant ต้องไม่รั่วข้ามกัน |
| `docs/ERP/HIS_SYSTEM_PLAN.md` / `LAB_SYSTEM_PLAN.md` | ข้อกำหนด compliance เรื่อง encryption at rest / in transit |
| `docs/ERP/POS System_plan.md` | Payment terminal — มักมีข้อกำหนดการตั้งค่าเฉพาะจากผู้ให้บริการ |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | CDN config, signed URL, cache-control |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Startup Config Validation — Fail Fast (แนะนำ) ⭐

```js
// websocket-server/config/validate-env.js
const REQUIRED_IN_PRODUCTION = [
  'DATABASE_URL', 'REDIS_URL', 'ALLOWED_ORIGINS', 'JWT_SECRET',
];
const FORBIDDEN_VALUES = ['your_api_key_here', 'changeme', 'secret', '*'];

function validateEnv() {
  const env = process.env.NODE_ENV || 'development';
  const problems = [];

  if (env === 'production') {
    for (const key of REQUIRED_IN_PRODUCTION) {
      if (!process.env[key]) problems.push(`Missing required env: ${key}`);
    }
    if (process.env.ALLOWED_ORIGINS === '*') {
      problems.push('ALLOWED_ORIGINS must not be "*" in production');
    }
    for (const [k, v] of Object.entries(process.env)) {
      if (FORBIDDEN_VALUES.includes(v)) problems.push(`Placeholder value in ${k}`);
    }
  }

  if (problems.length) {
    console.error('[Config] Startup validation failed:\n  - ' + problems.join('\n  - '));
    process.exit(1);          // fail fast — ไม่ปล่อยให้รันแบบไม่ปลอดภัย
  }
}
```

**ข้อดี**
- ปิด M1, M9, M15 พร้อมกัน; ระบบไม่มีทางรันด้วย config ที่ไม่ปลอดภัย
- ต้นทุนต่ำมาก (~100 บรรทัด, 1 วัน)
- เป็นเอกสารในตัวว่าระบบต้องการ env อะไรบ้าง (ช่วยแผน 07 K6)

**ข้อเสีย**
- ถ้าตั้งกฎเข้มเกินไปอาจทำให้ deploy สะดุด → ต้องทดสอบใน staging ก่อน

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **แนะนำอย่างยิ่ง**

---

### ตัวเลือก B: Global Error Handler + Error Taxonomy

```js
// websocket-server/middleware/error-handler.js
class AppError extends Error {
  constructor(code, message, statusCode = 400, details = null) {
    super(message);
    this.code = code; this.statusCode = statusCode; this.details = details;
    this.isOperational = true;
  }
}

function errorHandler(err, req, res, next) {
  const isProd = process.env.NODE_ENV === 'production';
  const requestId = req.id || crypto.randomUUID();

  // log เต็มรูปแบบฝั่ง server เสมอ
  logger.error({ requestId, err: err.stack, path: req.path, userId: req.userId });

  if (err.isOperational) {
    return res.status(err.statusCode).json({
      error: { code: err.code, message: err.message, requestId },
    });
  }

  // unexpected error → ไม่เปิดเผยรายละเอียด
  res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'เกิดข้อผิดพลาดภายในระบบ',
      requestId,                             // ให้ผู้ใช้แจ้ง support ได้
      ...(isProd ? {} : { debug: err.message }),
    },
  });
}
```

**ข้อดี:** ปิด M2, M4; error response สม่ำเสมอทุก endpoint; `requestId` เชื่อมกับ log (แผน 05); dev ยังเห็นรายละเอียดใน non-production
**ข้อเสีย:** ต้อง refactor try/catch ทุก route ให้ `next(err)` แทนการตอบเอง
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก C: Security Headers ด้วย Helmet

```js
const helmet = require('helmet');
app.disable('x-powered-by');
app.set('trust proxy', 1);          // อยู่หลัง reverse proxy

app.use(helmet({
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
  noSniff: true,
  frameguard: { action: 'deny' },
  referrerPolicy: { policy: 'no-referrer' },
  contentSecurityPolicy: { /* ดูแผน 14 */ },
}));
```

**ข้อดี:** ปิด M3, M7; ทำได้ใน 1 วัน; ทับซ้อนกับแผน 14 ตัวเลือก C — **ควร implement ครั้งเดียว**
**ข้อเสีย:** CSP อาจกระทบฟีเจอร์ web ต้องทดสอบ
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก D: Environment Separation + Infrastructure as Code

```
environments/
  development/   → Supabase dev project, local PostgreSQL, log level debug
  staging/       → Supabase staging, ข้อมูลจำลอง, log level info
  production/    → Supabase prod, log level warn, monitoring เต็มรูปแบบ
```
+ Docker Compose / Terraform / Ansible playbook สำหรับ reproducible setup

**ข้อดี:** ปิด M5; test ไม่ปนข้อมูลจริง; deploy ซ้ำได้ผลเหมือนเดิม; rollback ง่าย
**ข้อเสีย:** ต้นทุน Supabase เพิ่ม (มี free tier); ต้องเรียนรู้เครื่องมือ; migration ต้องรันหลาย environment
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **จำเป็นก่อนเปิดใช้งานจริง**

---

### ตัวเลือก E: Configuration Audit Checklist + Automated Scan

```bash
# ตรวจ config ก่อน deploy
- ss -tlnp                          # port ที่เปิดอยู่
- psql -c "SHOW listen_addresses"   # PostgreSQL bind
- redis-cli CONFIG GET bind         # Redis bind
- curl -I https://api.sheserved.com # ตรวจ headers
- testssl.sh https://api.sheserved.com
- docker scan / trivy config
```

**ข้อดี:** ตรวจสิ่งที่โค้ดตรวจไม่ได้ (ระดับ OS/network); ทำเป็น runbook ใช้ซ้ำได้
**ข้อเสีย:** ต้องรันมือหรือเขียน automation เพิ่ม
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A + B + C ทันที (1 สัปดาห์) → D ก่อน production → E เป็น runbook** | ทั้งสามตัวแรกต้นทุนต่ำและปิดช่องว่างส่วนใหญ่ |
| 2 | **A + C + D** | ถ้ายังไม่พร้อม refactor error handling ทุก route |
| 3 | **D เป็นหลัก** | ถ้าปัญหาหลักคือการปนกันของ environment |
| 4 | **ไม่ทำอะไร** | ไม่แนะนำ — M1 และ M14 เป็นความเสี่ยงที่แก้ได้ด้วยต้นทุนต่ำมาก |

---

## 5. Configuration Baseline ที่เสนอ

### 5.1 Express / Node.js
| การตั้งค่า | ค่าที่แนะนำ |
|-----------|------------|
| `NODE_ENV` | `production` (บังคับ) |
| `x-powered-by` | disabled |
| `trust proxy` | ตามจำนวน proxy hop |
| `express.json()` | `{ limit: '100kb' }` (ปรับต่อ endpoint) |
| CORS origin | allowlist ชัดเจน ห้าม `*` |
| Error response | code + ข้อความไทย + requestId เท่านั้น |
| Log level | `warn` ใน production |
| Graceful shutdown | ปิด server → queue → DB pool → Redis |

### 5.2 Security Headers
| Header | ค่า |
|--------|-----|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `no-referrer` |
| `Content-Security-Policy` | ดูแผน 14 |
| `Permissions-Policy` | ปิด feature ที่ไม่ใช้ |
| `Cache-Control` (API) | `no-store` สำหรับข้อมูลอ่อนไหว |

### 5.3 PostgreSQL / Redis
| การตั้งค่า | ค่าที่แนะนำ |
|-----------|------------|
| PostgreSQL `listen_addresses` | `localhost` หรือ private IP เท่านั้น |
| PostgreSQL `ssl` | `on` ถ้าเชื่อมข้ามเครื่อง |
| PostgreSQL `log_statement` | `ddl` (ไม่ใช่ `all` — กัน password ติด log) |
| Redis `bind` | `127.0.0.1` หรือ private IP |
| Redis `requirepass` | ตั้งเสมอ |
| Redis `protected-mode` | `yes` |
| Redis `maxmemory-policy` | `allkeys-lru` (สำหรับ cache) — แต่ session ควรแยก instance/db |

### 5.4 Flutter Build
| การตั้งค่า | ค่าที่แนะนำ |
|-----------|------------|
| Release build | `--obfuscate --split-debug-info=...` |
| Debug print | ต้องไม่มีใน release (ใช้ `kDebugMode` guard) |
| Android `usesCleartextTraffic` | `false` |
| iOS ATS | ไม่มี exception ที่ไม่จำเป็น |
| Certificate pinning | พิจารณาสำหรับ endpoint การเงิน |

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/secure/14_xss.md` | ตัวเลือก C ทับกับแผน 14 ตัวเลือก C — **implement ครั้งเดียว** |
| `docs/secure/15_csrf.md` | M1 (CORS) ทับกับแผน 15 C1 — **implement ครั้งเดียว** |
| `docs/secure/07_secret_management.md` | ตัวเลือก A/D ทับกับ K3, K6 — ทำร่วมกัน |
| `docs/secure/05_logging_audit_monitoring.md` | `requestId` ในตัวเลือก B เป็นพื้นฐานของแผน 05 |
| `docs/infrastructure/reverse_proxy_plan.md` | 🔴 **จุดตัดสำคัญ** — headers/TLS ควรตั้งที่ proxy; ควร implement พร้อมกัน |
| `docs/infrastructure/SETUP_NEW_MACHINE.md` | ต้องเพิ่ม security baseline (section 5) เข้าไป |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | ต้องเพิ่ม bind address และ SSL config |
| `docs/infrastructure/DATABASE_SERVER_COMPLETE.md` | ตรวจว่าไม่มี config ที่ไม่ปลอดภัยระบุไว้ |

---

## 7. งานที่ต้องตรวจสอบทันทีเมื่ออนุมัติ

- [ ] ตรวจว่า production ตั้ง `ALLOWED_ORIGINS` แล้วหรือยัง
- [ ] ตรวจว่า `NODE_ENV=production` ถูกตั้งจริงบน server
- [ ] `ss -tlnp` ดูว่ามี port อะไรเปิดสู่ภายนอกบ้าง
- [ ] ตรวจ PostgreSQL `listen_addresses` และ `pg_hba.conf`
- [ ] ตรวจ Redis `bind` และ `requirepass`
- [ ] ตรวจว่า reverse proxy บังคับ HTTPS และ redirect HTTP หรือไม่
- [ ] ตรวจว่า static directory listing ปิดอยู่
- [ ] ตรวจว่า Flutter release build ไม่มี debug log

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติ startup config validation แบบ fail-fast (A) — แนะนำ: ใช่
- [ ] อนุมัติ global error handler + error taxonomy (B)
- [ ] อนุมัติการเพิ่ม `helmet` (C) — ทำร่วมกับแผน 14
- [ ] ตัดสินใจสร้าง Supabase project แยกตาม environment (D) — ทำร่วมกับแผน 07
- [ ] อนุมัติ configuration baseline (section 5)
- [ ] ตัดสินใจเรื่อง certificate pinning สำหรับ endpoint การเงิน
- [ ] กำหนดผู้รับผิดชอบ pre-deploy configuration review
