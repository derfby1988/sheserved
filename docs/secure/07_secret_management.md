# แผนป้องกัน 07: Secret Management

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** 09 (AuthN/AuthZ), 08 (Session/Token), 12 (Least Privilege), 06 (Dependencies)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 7** สำหรับ secret scanning, environment separation, inventory และ rotation runbook; secret ที่ใช้ลงนาม token ต้องพร้อมก่อน Phase S0-B
> **เหตุผล:** Supabase URL/anon key เป็น public configuration ไม่ใช่ server secret แต่จะปลอดภัยได้ต่อเมื่อ RLS ครบ; ห้ามอ้างว่า “ซ่อนใน Flutter binary” เป็นการป้องกัน และต้องแยกการแก้ config จากการหมุน server credentials จริง

---

## 1. สถานะปัจจุบัน (As-Is)

### Secrets ที่พบในโค้ด

| Secret | ตำแหน่ง | สถานะ | ระดับ |
|--------|---------|-------|-------|
| Supabase URL | `lib/config/app_config.dart:40` | hardcode ในซอร์ส | 🟡 (ไม่ลับโดยธรรมชาติ แต่ควรกำหนดค่าได้) |
| Supabase anon key | `lib/config/app_config.dart:44` | hardcode ในซอร์ส (JWT string) | 🟡 (ออกแบบมาให้ public แต่**ต้องมี RLS คุ้มกัน**) |
| Local API URL | `lib/config/app_config.dart` | hardcode | 🟢 |
| WebSocket URL | `lib/config/app_config.dart` | hardcode | 🟢 |
| DB connection string | `websocket-server` (`.env`) | ใช้ env ✅ | 🟢 |
| Redis connection | `websocket-server/middleware/redis-client.js` | ใช้ env ✅ | 🟢 |
| `ALLOWED_ORIGINS` | env, default `'*'` | ✅ แต่ default ไม่ปลอดภัย | 🟡 |
| Google/Facebook/Apple OAuth client ID | ไฟล์ config ของแต่ละ platform | ตามมาตรฐาน platform | 🟢 |
| Google Maps API key | `AndroidManifest.xml` / `AppDelegate.swift` | ตามมาตรฐาน platform | 🟡 (ต้องจำกัด API restriction) |

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| K1 | **Config hardcode ในซอร์ส** | 🔴 สูง | เปลี่ยนสภาพแวดล้อม (dev/staging/prod) ต้องแก้โค้ด + rebuild |
| K2 | **Anon key ใน binary โดยไม่มี RLS ครบ** | 🔴 วิกฤต | anon key ออกแบบมาให้ public **ก็ต่อเมื่อ RLS ครอบคลุมทุกตาราง** ซึ่งปัจจุบันยังไม่ครบ |
| K3 | **ไม่มีการแยก environment** | 🔴 สูง | dev/test ใช้ Supabase production เดียวกัน — test data ปนกับข้อมูลจริง |
| K4 | **ไม่มี key rotation process** | 🟡 กลาง | ถ้า key รั่ว ไม่มีขั้นตอนหมุนเวียนที่ชัดเจน |
| K5 | **ไม่มี secret scanning ใน CI** | 🟡 กลาง | secret ใหม่หลุดเข้า repo ได้โดยไม่มีใครสังเกต |
| K6 | **`.env` ไม่มี `.env.example`** | 🟡 กลาง | นักพัฒนาใหม่ไม่รู้ว่าต้องตั้งค่าอะไรบ้าง |
| K7 | **Git history อาจมี secret เก่า** | 🟡 กลาง | ต้อง audit ประวัติ commit |
| K8 | **ไม่มี secret สำหรับ JWT signing** | 🔴 สูง | แผน 08 ต้องการ — ต้องเตรียมกลไกก่อน |
| K9 | **Google Maps API key ไม่มี restriction (ต้องยืนยัน)** | 🟡 กลาง | ถ้าไม่จำกัด bundle ID/SHA จะถูกนำไปใช้จนเกิดค่าใช้จ่าย |
| K10 | **ไม่มี service_role key management** | 🟡 กลาง | ถ้าจะทำ backend gateway (แผน 09 A) ต้องใช้ service_role key ซึ่งอันตรายมาก |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 Secret ที่ระบบปัจจุบันต้องใช้

| ระบบ | Secret ที่เกี่ยวข้อง |
|------|---------------------|
| Auth & Registration | Supabase key, (อนาคต) JWT signing secret, OTP provider API key |
| Social Login | Google/Facebook/Apple client ID + secret |
| Chat & Video | WebRTC TURN server credentials, Socket.IO config |
| Emergency & Rescue | Google Maps API key, (อนาคต) SMS gateway |
| Donation + Escrow | (อนาคต) Payment gateway API key — **ระดับสูงสุด** |
| Health sync | Device API credentials, health platform token |
| Video System | Storage credentials, transcoding service |
| Admin | — |

### 2.2 Secret ที่แผนอนาคตจะต้องใช้

| แผน | Secret ที่จะเพิ่มเข้ามา | ระดับความอ่อนไหว |
|-----|----------------------|-----------------|
| `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` | Bank API, e-Tax invoice (RD), accounting software integration | 🔴 สูงสุด |
| `docs/ERP/POS System_plan.md` | Payment gateway (Omise/2C2P/SCB), EDC terminal key | 🔴 สูงสุด |
| `docs/ERP/PROCUREMENT_SYSTEM_PLAN.md` | Supplier EDI credentials | 🟡 |
| `docs/ERP/HR_SYSTEM_PLAN.md` | Payroll bank transfer API, SSO (ประกันสังคม) | 🔴 สูงสุด |
| `docs/ERP/CRM_SYSTEM_PLAN.md` | Email service (SendGrid/SES), SMS gateway, LINE OA | 🟡 |
| `docs/ERP/ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Billing/subscription provider | 🔴 |
| `docs/ERP/LAB_SYSTEM_PLAN.md` | LIS interface credentials (HL7) | 🔴 |
| `docs/ERP/HIS_SYSTEM_PLAN.md` | HIS integration, สปสช./ประกันสังคม API | 🔴 |
| `docs/plans/Delivery_PLAN.md` | Delivery partner API (Grab/Lalamove), map routing | 🟡 |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | CDN, transcoding, storage | 🟡 |
| `docs/plans/health_data_sync_plan.md` | Apple HealthKit / Google Fit / device vendor API | 🟡 |

> **ข้อสรุปสำคัญ:** ระบบกำลังจะมี secret ระดับการเงินและการแพทย์จำนวนมาก — **ต้องวางระบบจัดการ secret ให้เรียบร้อยก่อนเริ่ม ERP**

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Dart Define + Build Flavor (แนะนำสำหรับฝั่งแอป) ⭐

```dart
// lib/config/app_config.dart
class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dev-project.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const String environment = String.fromEnvironment('ENV', defaultValue: 'dev');
}
```

```bash
flutter build ios --dart-define-from-file=config/prod.json
flutter run --dart-define-from-file=config/dev.json
```

```
config/
  dev.json        (commit ได้ — ชี้ไป dev project)
  staging.json    (.gitignore)
  prod.json       (.gitignore — จาก secret store ของ CI)
  example.json    (commit — เป็น template)
```

**ข้อดี**
- แยก environment ได้จริง (ปิด K1, K3)
- ไม่มี secret ใน git
- รองรับ CI/CD ตรงไปตรงมา
- ค่าถูก inline ตอน compile — ไม่มี runtime overhead

**ข้อเสีย**
- ⚠️ **ค่ายังอยู่ใน binary** — reverse engineering ยังหาได้ (นี่เป็นข้อจำกัดของ client app ทุกตัว ไม่ใช่ของวิธีนี้)
- ต้องจัดการไฟล์ config หลายชุด

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — มาตรฐานของ Flutter

---

### ตัวเลือก B: Remote Config / Runtime Config Endpoint

```
แอปเปิด → GET /api/config/public → { supabaseUrl, features, ... }
```

**ข้อดี:** เปลี่ยนค่าโดยไม่ต้อง rebuild/redeploy app; รองรับ feature flag (ตรงกับ `FeatureFlagsPage` ที่มีในแผน HR); kill switch ได้
**ข้อเสีย:** ต้องมี bootstrap URL hardcode อยู่ดี; แอปพึ่งพา network ตอนเปิด; ไม่เหมาะกับ secret ที่ต้องลับจริง
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ดีสำหรับ config **ที่ไม่ลับ** และ feature flag

---

### ตัวเลือก C: Backend Proxy — ไม่ให้ client ถือ secret เลย

Client ไม่รู้จัก Supabase key เลย ทุกอย่างผ่าน backend ที่ถือ `service_role` key

**ข้อดี:** ✅ **แก้ปัญหาที่รากจริง** — secret ไม่มีทางหลุดจาก client; ปิด K2, K10 อย่างสมบูรณ์; สอดคล้องกับแผน 09 ตัวเลือก A
**ข้อเสีย:** refactor ใหญ่มาก; backend เป็น single point of failure; `service_role` key ที่ backend = target ที่มีค่าสูงมาก ต้องป้องกันแน่นหนา
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — เป้าหมายสุดท้าย แต่ต้องทำเป็นขั้นตอน

---

### ตัวเลือก D: Secret Manager Service (สำหรับ Backend)

| ตัวเลือก | เหมาะกับ | ต้นทุน |
|---------|---------|-------|
| `.env` + file permission 600 | ปัจจุบัน (single server) | ฟรี |
| Docker Secrets / systemd credentials | Container deployment | ฟรี |
| HashiCorp Vault | Multi-service, audit ครบ | สูง (self-host หรือ cloud) |
| AWS Secrets Manager / GCP Secret Manager | ถ้าย้ายขึ้น cloud | ตามการใช้งาน |
| Doppler / Infisical | ทีมเล็ก, UX ดี | ฟรี tier มี |

**คำแนะนำสำหรับ Sheserved:**
- **ระยะสั้น:** `.env` + permission เข้มงวด + `.env.example` (ปิด K6)
- **ระยะกลาง:** Infisical/Doppler เมื่อมีทีมหลายคนหรือหลาย environment
- **ระยะยาว:** Vault เมื่อ ERP มีหลาย service และต้องการ audit

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐

---

### ตัวเลือก E: Secret Scanning + Pre-commit Hook (ทำทันที ต้นทุนต่ำ)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

```yaml
# CI
- name: Secret Scan
  uses: gitleaks/gitleaks-action@v2
```

**ข้อดี:** ปิด K5, K7; ตั้งค่าได้ใน 1 วัน; ป้องกันการถดถอยถาวร
**ข้อเสีย:** false positive บ้าง; ไม่แก้ secret ที่มีอยู่แล้ว
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **ควรทำทันที**

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **E ทันที → A + D(.env) → B(feature flag) → C เมื่อทำ gateway** | เริ่มจากป้องกันการถดถอย แล้วแยก environment แล้วค่อยย้าย secret ออกจาก client |
| 2 | **A + E + D พร้อมกัน** | ถ้าต้องการจัดการเรื่อง config ให้จบในรอบเดียว |
| 3 | **C เป็นเป้าหมายหลัก ทำ A/E เป็นทางผ่าน** | ถ้าตัดสินใจทำ backend gateway ตามแผน 09 ตัวเลือก A แน่นอนแล้ว |
| 4 | **คงสถานะเดิม** | ไม่แนะนำ — K2/K3 เป็นความเสี่ยงจริงที่ต้องจัดการก่อนเปิดใช้งานจริง |

---

## 5. การจำแนกประเภท Secret (Classification)

| ระดับ | นิยาม | ตัวอย่างใน Sheserved | ที่เก็บที่อนุญาต |
|------|-------|---------------------|-----------------|
| **P0 — Public** | เปิดเผยได้โดยออกแบบ | Supabase URL, App version, Maps API key (มี restriction) | ในซอร์สได้ |
| **P1 — Client-embedded** | อยู่ใน client ได้ แต่ต้องมีชั้นป้องกันอื่นรองรับ | Supabase anon key (ต้องมี RLS), OAuth client ID | dart-define, ไม่ commit prod value |
| **P2 — Server-only** | ห้ามอยู่ใน client เด็ดขาด | DB password, Redis password, JWT signing secret, Supabase service_role key | env / secret manager |
| **P3 — Regulated** | มีผลทางกฎหมาย/การเงิน | Payment gateway key, Bank API, e-Tax cert, สปสช. credentials | secret manager + audit log + rotation บังคับ |

### กฎการจัดการตามระดับ
```
P0: commit ได้
P1: ห้าม commit prod value; ต้องมี RLS/restriction รองรับ; rotate ปีละครั้ง
P2: secret manager เท่านั้น; rotate ทุก 90 วัน; access log
P3: secret manager + HSM/KMS ถ้าเป็นไปได้; rotate ตามข้อกำหนดผู้ให้บริการ;
    dual control (2 คนอนุมัติ); audit log ทุกการเข้าถึง; ห้ามอยู่บนเครื่อง dev
```

---

## 6. แผน Key Rotation ที่เสนอ

| Secret | รอบหมุนเวียน | ขั้นตอน |
|--------|-------------|---------|
| Supabase anon key | ปีละครั้ง หรือเมื่อสงสัยว่ารั่ว | สร้าง key ใหม่ → deploy app version ใหม่ → รอ adoption → revoke ตัวเก่า |
| Supabase service_role | 90 วัน | rotate ที่ backend (ไม่กระทบ client) |
| JWT signing secret | 90 วัน | dual-key period — verify ด้วย key เก่าและใหม่, sign ด้วยใหม่เท่านั้น |
| DB password | 90 วัน | สร้าง user ใหม่ → migrate → drop เก่า |
| Payment gateway | ตามผู้ให้บริการ | ต้องมี runbook เฉพาะ |

### เหตุการณ์ที่ต้อง rotate ทันที
- นักพัฒนาที่มีสิทธิ์ออกจากทีม
- ตรวจพบ secret ใน git/log/screenshot
- อุปกรณ์ที่มี secret สูญหาย
- ตรวจพบการใช้งานผิดปกติ

---

## 7. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/infrastructure/SETUP_NEW_MACHINE.md` | ต้องเพิ่มขั้นตอนดึง secret จาก secret store แทนการ copy `.env` มือ |
| `docs/infrastructure/SETUP_DATABASE_SERVER.md` | ต้องระบุการจัดการ DB credential ตามระดับ P2 |
| `docs/infrastructure/DATABASE_SERVER_COMPLETE.md` | ตรวจว่าไม่มี credential จริงเขียนอยู่ในเอกสาร |
| `docs/infrastructure/reverse_proxy_plan.md` | TLS certificate management เป็น secret ประเภทหนึ่ง |
| `docs/infrastructure/architecture_analysis.md` | เพิ่ม secret flow ในผัง |
| `docs/ERP/*` (ทุกแผนที่มี integration) | ต้องระบุระดับ secret classification ในแต่ละแผน |

---

## 8. งานที่ต้องทำทันทีเมื่ออนุมัติ (Immediate Actions)

- [ ] Audit git history หา secret ที่เคย commit (`gitleaks detect --log-opts="--all"`)
- [ ] ตรวจสอบว่า Supabase anon key ปัจจุบันมี RLS คุ้มกันเพียงพอหรือไม่ (**ตัวชี้วัดสำคัญที่สุด**)
- [ ] ตรวจสอบ restriction ของ Google Maps API key
- [ ] สร้าง `.env.example` ใน `websocket-server/`
- [ ] เปลี่ยน `ALLOWED_ORIGINS` default จาก `'*'` เป็นบังคับตั้งค่าใน production

---

## 9. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติการเพิ่ม secret scanning ใน CI/pre-commit (แนะนำ: ใช่ ทำทันที)
- [ ] ตัดสินใจสร้าง Supabase project แยกสำหรับ dev/staging (ปิด K3)
- [ ] เลือกวิธีจัดการ config ฝั่งแอป: dart-define (A) / remote config (B) / proxy (C)
- [ ] เลือก secret manager สำหรับ backend: `.env` / Infisical / Doppler / Vault
- [ ] อนุมัติ secret classification (ตาราง section 5)
- [ ] อนุมัติแผน rotation (ตาราง section 6)
- [ ] ตัดสินใจว่าใครมีสิทธิ์เข้าถึง secret ระดับ P2/P3 (ร่วมกับแผน 12)
