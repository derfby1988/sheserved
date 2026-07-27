# แผนป้องกัน 05: Logging, Audit Trail และ Monitoring

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** ทุกแผน (logging เป็นเครื่องมือตรวจสอบว่ามาตรการอื่นทำงานจริงหรือไม่)
> **หลักการ:** *"ระบบที่ไม่มี log = ไม่รู้ว่าถูกโจมตีหรือไม่"* — OWASP จัด Security Logging and Monitoring Failures เป็นหนึ่งใน Top 10 เพราะทำให้ตรวจจับและตอบสนองไม่ได้
> **ผลทบทวน 2026-07-27:** แบ่งเป็นสองช่วง: **Phase S0-A ลำดับ 5** ทำ structured logging, request ID, redaction และ security-event baseline; **Phase S1 ลำดับ 5** ทำ audit table, aggregation และ alerting
> **เหตุผล:** logging พื้นฐานต้นทุนต่ำและช่วยยืนยันผลของแผนอื่น จึงควรทำก่อน migration ใหญ่ แต่ audit PHI/การเงินต้องออกแบบ schema, retention และ access control ให้ถูกต้อง ไม่ควรรีบสร้างตารางที่เก็บข้อมูลอ่อนไหวโดยไม่มี policy

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่มีอยู่
| องค์ประกอบ | รายละเอียด |
|-----------|------------|
| `console.log` / `console.error` | ใช้ทั่วทั้ง `websocket-server` พร้อม prefix เช่น `[API]`, `[Worker]`, `[ThaiMhung]`, `[AuthMiddleware]` |
| Prefix pattern | สม่ำเสมอพอสมควร — เป็นพื้นฐานที่ดีสำหรับการย้ายไป structured logging |
| Error logging | ทุก catch block มี `console.error` |

### ตัวอย่างที่แสดงปัญหา
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:617
                console.log(`[Gallery] Returning ${mapped.length} photos for incident ${id}:`, mapped.map(p => ({ id: p.id, blur_status: p.blur_status })));
```
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:356
                        console.log(`[ThaiMhung] Inserting photo: incidentId=${incidentId}, url=${url}`);
```
- Debug-level log ทำงานตลอดเวลาใน production
- ไม่มี timestamp, request ID, user ID, severity level
- Log ข้อมูลที่อาจอ่อนไหว (URL, ID) โดยไม่มีการควบคุม

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| G1 | **ไม่มี structured logging** | 🟡 กลาง | ข้อความอิสระ — query/วิเคราะห์ไม่ได้ |
| G2 | **ไม่มี log level** | 🟡 กลาง | debug log ทำงานใน production |
| G3 | **ไม่มี request ID / correlation ID** | 🟡 กลาง | ตาม trace request ข้าม service ไม่ได้ |
| G4 | **ไม่มี security event log** | 🔴 สูง | login สำเร็จ/ล้มเหลว, permission denied, rate limit hit ไม่ถูกบันทึกแยก |
| G5 | **ไม่มี audit trail สำหรับข้อมูลอ่อนไหว** | 🔴 วิกฤต | ไม่รู้ว่าใครเข้าถึงข้อมูลสุขภาพ/การเงินเมื่อไหร่ |
| G6 | **ไม่มี log retention policy** | 🟡 กลาง | log อยู่ที่ไหน เก็บนานเท่าไหร่ ไม่ชัดเจน |
| G7 | **ไม่มีการป้องกัน log tampering** | 🟡 กลาง | ผู้ที่เข้าถึง server ได้สามารถลบ/แก้ log |
| G8 | **ไม่มี alerting** | 🔴 สูง | ไม่มีใครรู้เมื่อเกิดเหตุผิดปกติ |
| G9 | **ไม่มี PII/secret redaction** | 🟡 กลาง | log อาจมีเบอร์โทร, token, URL ที่มี signature |
| G10 | **ไม่มี log aggregation** | 🟡 กลาง | log กระจายอยู่หลายที่ (app, DB, proxy, Flutter) |
| G11 | **ไม่มี audit ฝั่ง Flutter** | 🟡 กลาง | crash/error ของแอปไม่ถูกรวบรวม |
| G12 | **Log injection** | 🟢 ต่ำ | ค่าจาก user ที่มี newline ปลอมบรรทัด log ได้ |
| G13 | **ไม่มี metrics / health monitoring** | 🟡 กลาง | ไม่รู้สถานะระบบแบบ real-time |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 เหตุการณ์ที่ต้องบันทึก (Security Events)

| ประเภท | เหตุการณ์ | ความสำคัญ |
|--------|----------|-----------|
| **Authentication** | login สำเร็จ / ล้มเหลว, logout, token refresh, session revoke | 🔴 |
| | password change, OTP request/verify, social login | 🔴 |
| | account lockout, การพยายามเข้าจากอุปกรณ์ใหม่ | 🔴 |
| **Authorization** | permission denied (403), ownership check ล้มเหลว (404 จาก BOLA) | 🔴 |
| | role/permission change, admin bypass | 🔴 |
| **Data access** | อ่านข้อมูลสุขภาพ, EMR, payroll, GL | 🔴 (บังคับตาม compliance) |
| | export/download ข้อมูลจำนวนมาก | 🔴 |
| **Data modification** | CRUD บนข้อมูลการเงิน, escrow release, GL posting | 🔴 |
| | drug risk override, prescription | 🔴 |
| | ลบข้อมูล (soft/hard delete) | 🟡 |
| **Configuration** | เปลี่ยน platform settings, watermark, feature flag | 🟡 |
| **Abuse signals** | rate limit hit, validation ล้มเหลวถี่ผิดปกติ, input ที่ดูเป็นการทดสอบระบบ | 🟡 |
| **System** | startup/shutdown, DB/Redis connection loss, queue backlog | 🟡 |

### 2.2 ระบบที่ implement แล้ว

| ระบบ | สิ่งที่ต้อง log | สถานะ |
|------|----------------|-------|
| Auth | ทุก login attempt + ผลลัพธ์ | ❌ |
| Consultation | เริ่ม/จบเคส, การเข้าถึง chartboard | ❌ |
| Chat | ไม่ต้อง log เนื้อหา แต่ต้อง log การเข้าห้อง | ❌ |
| Video | upload, delete, admin action | บางส่วน (console) |
| Donation/Escrow | 🔴 ทุก transaction + approval + release | ❌ |
| Emergency | SOS trigger, responder accept — สำคัญทั้งด้าน security และ operational | บางส่วน |
| Health | 🔴 ทุกการอ่าน/เขียน + consent change | ❌ |
| Pharmacy | drug risk override ทุกครั้ง | ❌ |
| Profile | เปลี่ยนข้อมูลสำคัญ (เบอร์, อีเมล) | ❌ |
| Admin | 🔴 ทุก action | ❌ |

### 2.3 ระบบตามแผน `docs/ERP/` — ข้อกำหนด audit

| แผน | ข้อกำหนด |
|-----|---------|
| `ACCOUNTING_SYSTEM_PLAN.md` | 🔴 **บังคับตามหลักบัญชี** — GL entry ต้อง immutable + audit trail ครบ ใครสร้าง ใครอนุมัติ เมื่อไหร่ |
| `HR_SYSTEM_PLAN.md` | 🔴 การเข้าถึง payroll ต้อง log ทุกครั้ง; การเปลี่ยนเงินเดือนต้องมี before/after |
| `HIS_SYSTEM_PLAN.md` | 🔴 **PHI access log บังคับ** — ใครดูเวชระเบียนใคร เมื่อไหร่ เหตุผลอะไร; break-glass ต้อง alert ทันที |
| `LAB_SYSTEM_PLAN.md` | 🔴 ผล lab: ใครบันทึก ใครแก้ ใครอนุมัติ — ต้องมี chain of custody |
| `INVENTORY_SYSTEM_PLAN.md` | Stock adjustment ต้องมีเหตุผล + ผู้อนุมัติ |
| `PROCUREMENT_SYSTEM_PLAN.md` | PO approval chain ต้อง traceable |
| `POS System_plan.md` | Refund/void ต้อง log พร้อมผู้อนุมัติ; cash drawer open |
| `CRM_SYSTEM_PLAN.md` | Export รายชื่อลูกค้า = PII export ต้อง log |
| `ERP_CORE_ARCHITECTURE.md` | Audit ต้อง scope ตาม organization; cross-tenant access = alert ทันที |
| `KPI_DASHBOARD_PLAN.md` | Log ใครดู KPI อะไร (ข้อมูลเชิงกลยุทธ์) |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Tier change, billing event |

### 2.4 ระบบตามแผน `docs/plans/`

| แผน | ประเด็น |
|-----|---------|
| `DONATION_SYSTEM_PLAN.md` | 🔴 การเงิน — ต้อง audit ครบทุก state transition |
| `Delivery_PLAN.md` | Courier เข้าถึงที่อยู่ลูกค้า = ต้อง log |
| `health_data_sync_plan.md` | Device sync = การเข้าถึงข้อมูลสุขภาพ |
| `DRUG_RISK_OVERRIDE_PLAN.md` | ทุก override ต้องมีเหตุผล + ผู้กระทำ |
| `VIDEO_SYSTEM_PLAN.md` | Unblurred access ต้อง log (ข้อมูลใบหน้าบุคคล) |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Structured Logging + Correlation ID (แนะนำ) ⭐

```js
// websocket-server/utils/logger.js
const pino = require('pino');

const logger = pino({
  level: process.env.LOG_LEVEL || (process.env.NODE_ENV === 'production' ? 'info' : 'debug'),
  redact: {
    paths: ['req.headers.authorization', 'req.headers["x-user-id"]',
            '*.password', '*.token', '*.phone', '*.refresh_token', '*.api_key'],
    censor: '[REDACTED]',
  },
  formatters: { level: (label) => ({ level: label }) },
});

// middleware แนบ request ID
function requestContext(req, res, next) {
  req.id = req.headers['x-request-id'] || crypto.randomUUID();
  res.setHeader('x-request-id', req.id);
  req.log = logger.child({ requestId: req.id, userId: req.userId, path: req.path });
  next();
}
```

```js
// การใช้งาน — แทน console.log
req.log.info({ event: 'gallery.read', incidentId, count: mapped.length });
req.log.warn({ event: 'auth.login.failed', identifier, reason: 'bad_password' });
```

**ข้อดี**
- ปิด G1, G2, G3, G9 พร้อมกัน
- `pino` เร็วมาก (overhead ต่ำ) และเป็นมาตรฐานใน Node.js
- JSON output ส่งเข้า log aggregator ได้ทันที
- Redaction ในตัว — ป้องกัน secret หลุดเข้า log
- Request ID เชื่อมกับ error response (แผน 04 ตัวเลือก B)

**ข้อเสีย**
- ต้องแทนที่ `console.log` ทุกจุด (~200+ จุด) — แต่ทำทีละส่วนได้
- เพิ่ม dependency

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Audit Log Table ในฐานข้อมูล

```sql
CREATE TABLE audit_logs (
  id            BIGSERIAL PRIMARY KEY,
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_id      UUID,
  actor_role    VARCHAR(30),
  organization_id UUID,
  event_type    VARCHAR(60) NOT NULL,   -- 'health.record.read'
  resource_type VARCHAR(60),
  resource_id   TEXT,
  action        VARCHAR(20),            -- read | create | update | delete | approve
  outcome       VARCHAR(20),            -- success | denied | error
  reason        TEXT,                   -- break-glass, override reason
  before_state  JSONB,
  after_state   JSONB,
  ip_address    INET,
  user_agent    TEXT,
  request_id    UUID,
  session_id    UUID
);

CREATE INDEX ON audit_logs (actor_id, occurred_at DESC);
CREATE INDEX ON audit_logs (resource_type, resource_id, occurred_at DESC);
CREATE INDEX ON audit_logs (event_type, occurred_at DESC);
CREATE INDEX ON audit_logs (organization_id, occurred_at DESC);

-- immutable: ไม่ให้ app user แก้/ลบ
REVOKE UPDATE, DELETE ON audit_logs FROM app_user;
```

**ข้อดี**
- ปิด G5 — ตอบข้อกำหนด compliance ของ HIS/LAB/Accounting ได้
- Query ได้ด้วย SQL, join กับข้อมูลอื่นได้
- แสดงในแอปได้ (ผู้ใช้ดูประวัติการเข้าถึงข้อมูลตนเอง — เพิ่มความไว้วางใจ)
- `before_state`/`after_state` ตอบคำถาม "ใครแก้อะไร"

**ข้อเสีย**
- ตารางโตเร็วมาก → ต้อง partition ตามเดือน + archive
- เพิ่มภาระ DB write (ควรทำแบบ async ผ่าน queue)
- ถ้า DB ล่ม audit หายไปด้วย → สำคัญมากควรเขียนคู่ขนานไปที่ log stream

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **จำเป็นสำหรับ ERP/HIS**

---

### ตัวเลือก C: Log Aggregation + Alerting

| ตัวเลือก | เหมาะกับ | ต้นทุน |
|---------|---------|-------|
| ไฟล์ + logrotate + grep | ปัจจุบัน (server เดียว) | ฟรี |
| **Grafana Loki + Promtail + Grafana** | ทีมเล็ก self-host ⭐ | ฟรี (self-host) |
| ELK / OpenSearch | ต้องการ search ขั้นสูง | ทรัพยากรสูง |
| Sentry | error tracking + Flutter SDK ⭐ | ฟรี tier ดี |
| Datadog / New Relic | ครบที่สุด | สูง |
| Better Stack / Axiom | ทีมเล็ก UX ดี | ฟรี tier มี |

**Alert ที่เสนอ**
| เงื่อนไข | ระดับ | ช่องทาง |
|---------|-------|---------|
| Login ล้มเหลว > 20 ครั้ง/นาที จาก IP เดียว | 🟡 | Slack/LINE |
| Login สำเร็จจากประเทศ/อุปกรณ์ใหม่ (admin) | 🔴 | ทันที |
| Permission denied > 10 ครั้ง/นาที จากผู้ใช้เดียว | 🔴 | ทันที |
| Break-glass access (clinical) | 🔴 | ทันที |
| Escrow release / payroll run | 🟡 | สรุปรายวัน |
| Cross-tenant access attempt | 🔴 | ทันที |
| Error rate > 5% | 🟡 | Slack |
| Queue backlog > 1000 | 🟡 | Slack |
| DB/Redis connection loss | 🔴 | ทันที |
| Disk usage > 85% | 🟡 | Slack |

**ข้อดี:** ปิด G8, G10, G13; ตรวจจับได้จริง ไม่ใช่แค่มี log
**ข้อเสีย:** ต้องดูแล infrastructure เพิ่ม; alert fatigue ถ้าตั้งไม่ดี
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก D: Client-Side Error Tracking (Flutter)

```dart
// Sentry / Firebase Crashlytics
await SentryFlutter.init((options) {
  options.dsn = AppConfig.sentryDsn;
  options.environment = AppConfig.environment;
  options.beforeSend = (event, hint) => scrubPii(event);   // ล้าง PII ก่อนส่ง
});
```

**ข้อดี:** ปิด G11; เห็นปัญหาที่ผู้ใช้เจอจริง; crash report พร้อม stack trace
**ข้อเสีย:** ⚠️ ต้องระวังส่ง PII/ข้อมูลสุขภาพออกไปยัง service ภายนอก — ต้อง scrub ให้ดี; อาจมีข้อกำหนดเรื่องข้อมูลข้ามพรมแดน
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ระวังเรื่องความเป็นส่วนตัว

---

### ตัวเลือก E: Append-Only / Tamper-Evident Log

```
1. PostgreSQL: REVOKE UPDATE/DELETE + trigger ป้องกันการแก้ไข
2. Hash chain: แต่ละ record มี hash ของ record ก่อนหน้า
3. ส่ง log ไปยัง server แยกที่ผู้ดูแล app ไม่มีสิทธิ์ลบ
4. WORM storage สำหรับ archive
```

**ข้อดี:** ปิด G7; ตอบข้อกำหนด compliance ระดับสูง (การเงิน/การแพทย์)
**ข้อเสีย:** ซับซ้อน; hash chain ทำให้ insert ขนานยาก; ต้องมี infrastructure แยก
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — ทำเมื่อเข้าสู่ระยะ compliance จริง

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A ก่อน (2 สัปดาห์) → B สำหรับข้อมูลอ่อนไหว → C(Loki+Sentry) → E ตอน ERP compliance** | ต้องมี structured log ก่อนถึงจะทำ aggregation/alert ได้มีประโยชน์ |
| 2 | **A + B + D** | ถ้าต้องการเห็นภาพทั้ง server และ client เร็ว |
| 3 | **B ก่อน (audit table) แล้ว A ตาม** | ถ้า ERP/HIS เป็นความเร่งด่วนอันดับหนึ่ง (compliance บังคับ) |
| 4 | **C อย่างเดียว** | ไม่มีประโยชน์มาก — aggregate log ที่ไม่มีโครงสร้างก็ยัง query ยาก |

---

## 5. มาตรฐาน Logging ที่เสนอ (Sheserved Logging Standard)

### 5.1 Log Level
| Level | ใช้เมื่อ | Production |
|-------|---------|-----------|
| `fatal` | ระบบทำงานต่อไม่ได้ | ✅ + alert |
| `error` | operation ล้มเหลว ต้องการการแก้ไข | ✅ |
| `warn` | ผิดปกติแต่ยังทำงานได้ (rate limit hit, retry) | ✅ |
| `info` | เหตุการณ์สำคัญทางธุรกิจ + security event | ✅ |
| `debug` | รายละเอียดสำหรับพัฒนา | ❌ |
| `trace` | ละเอียดมาก | ❌ |

### 5.2 โครงสร้าง Log Entry
```json
{
  "level": "info",
  "time": "2026-07-26T08:12:33.123Z",
  "requestId": "0f9c...",
  "sessionId": "a71b...",
  "userId": "3d2e...",
  "userRole": "provider",
  "organizationId": "88ff...",
  "event": "consultation.chartboard.read",
  "resourceType": "consultation_request",
  "resourceId": "c19a...",
  "outcome": "success",
  "durationMs": 42,
  "ip": "203.0.113.5",
  "msg": "Chartboard accessed"
}
```

### 5.3 สิ่งที่ **ห้าม** บันทึกลง log
```
❌ รหัสผ่าน (แม้จะ hash แล้ว)
❌ Token, refresh token, session ID เต็ม (log แค่ 8 ตัวแรก)
❌ API key, secret
❌ เลขบัตรประชาชนเต็ม (mask: 1-2345-xxxxx-xx-x)
❌ เลขบัญชีธนาคารเต็ม
❌ เนื้อหาแชท / consultation note
❌ ค่าผลตรวจสุขภาพ (log แค่ว่ามีการเข้าถึง ไม่ log ค่า)
❌ พิกัด GPS ที่ละเอียด (ปัดเป็น ~1km ถ้าจำเป็นต้อง log)
❌ Signed URL ที่ยังใช้งานได้
⚠️ เบอร์โทร / อีเมล → mask (08x-xxx-1234)
```

### 5.4 Retention Policy
| ประเภท | เก็บออนไลน์ | Archive | ลบ |
|--------|-----------|---------|-----|
| Application log (info/warn) | 30 วัน | 90 วัน | 1 ปี |
| Error log | 90 วัน | 1 ปี | 2 ปี |
| Security event log | 1 ปี | 3 ปี | ตามกฎหมาย |
| Audit log (การเงิน) | 2 ปี | 5 ปี | ตามกฎหมายบัญชี |
| Audit log (การแพทย์/PHI) | 5 ปี | 10 ปี | ตามข้อกำหนด |
| Access log (proxy) | 30 วัน | 90 วัน | 6 เดือน |

### 5.5 กฎเสริม
```
1. ทุก log entry ต้องมี requestId
2. Security event ต้องใช้ event name จาก taxonomy ที่กำหนด (ไม่ใช่ข้อความอิสระ)
3. ค่าจาก user ที่ log ต้อง escape newline/control character (กัน log injection)
4. Log ต้องเขียนแบบ async ไม่บล็อก request
5. Audit log ต้องเขียนใน transaction เดียวกับ operation (หรือ outbox pattern)
6. การ log ล้มเหลว ต้องไม่ทำให้ operation ล้มเหลว (ยกเว้น audit ที่ compliance บังคับ)
7. ผู้ใช้ควรดู audit log ของตนเองได้ (ข้อมูลสุขภาพ: ใครเข้าถึงบ้าง)
```

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/secure/09_authentication_authorization.md` | G6 ในแผนนั้น (audit log) = แผนนี้ — **implement ครั้งเดียว** |
| `docs/secure/12_least_privilege.md` | `permission_audit_log` ที่เสนอในแผน 12 ควรรวมเป็นตาราง `audit_logs` เดียวกัน |
| `docs/secure/04_security_misconfiguration.md` | `requestId` จาก error handler เป็นพื้นฐานของแผนนี้ — ทำพร้อมกัน |
| `docs/secure/03_rate_limiting_resource_exhaustion.md` | Rate limit hit ต้อง log เพื่อแยก abuse จาก bug |
| `docs/secure/01_broken_object_level_authorization.md` | Ownership check ล้มเหลว = security event ที่ต้อง alert |
| `docs/secure/07_secret_management.md` | ⚠️ Redaction (G9) สำคัญมาก — log เป็นช่องทางที่ secret รั่วบ่อยที่สุด |
| `docs/infrastructure/caching_strategy.md` | Cache hit/miss metrics ควรอยู่ในระบบ monitoring เดียวกัน |
| `docs/infrastructure/reverse_proxy_plan.md` | Access log จาก proxy ควรส่งเข้า aggregator เดียวกัน |
| `docs/ERP/*` (HIS, LAB, Accounting, HR) | 🔴 **audit requirement ของแผนเหล่านั้นต้องอ้างอิงมาตรฐานในเอกสารนี้** |
| `docs/guides/TEST_PLAN.md` | ควรเพิ่ม test ว่า security event ถูกบันทึกจริง |

---

## 7. งานที่ต้องตรวจสอบทันทีเมื่ออนุมัติ

- [ ] ตรวจว่า log ปัจจุบันถูกเก็บที่ไหน (stdout? pm2? systemd journal?)
- [ ] ตรวจว่ามี log ไหนที่มี secret/PII หลุดอยู่แล้วบ้าง
- [ ] ตรวจ disk usage ของ log ปัจจุบัน
- [ ] ตรวจว่ามี logrotate ตั้งไว้หรือไม่
- [ ] รวบรวมรายการ event taxonomy จากทุกระบบ

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติการเพิ่ม `pino` + structured logging (A) — แนะนำ: ใช่
- [ ] อนุมัติโครงสร้างตาราง `audit_logs` (B)
- [ ] ตัดสินใจว่า audit log เขียน sync (ปลอดภัยกว่า) หรือ async (เร็วกว่า)
- [ ] เลือกเครื่องมือ aggregation: Loki / ELK / Better Stack / ไฟล์อย่างเดียว
- [ ] ตัดสินใจเรื่อง Sentry สำหรับ Flutter (D) — **พิจารณาเรื่องข้อมูลข้ามพรมแดน**
- [ ] อนุมัติรายการ "ห้าม log" (section 5.3)
- [ ] อนุมัติ retention policy (section 5.4)
- [ ] กำหนดรายการ alert + ช่องทาง + ผู้รับผิดชอบ (section ตัวเลือก C)
- [ ] ตัดสินใจว่าจะเปิดให้ผู้ใช้ดู audit log ของตนเองหรือไม่
- [ ] กำหนด event taxonomy ฉบับสมบูรณ์
