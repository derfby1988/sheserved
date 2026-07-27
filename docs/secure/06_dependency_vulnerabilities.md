# แผนป้องกัน 06: Dependency Vulnerabilities

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A
> **เกี่ยวข้องกับแผน:** ทุกแผน (dependency เป็นพื้นฐานของทุกมาตรการ)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 6** และทำทันทีเป็น CI control โดยไม่ต้องรอการเลือก auth/hash library
> **เหตุผล:** scanning, lockfile verification และ policy gate มีต้นทุนต่ำและลด supply-chain risk ได้ทันที; การอัปเกรด package แบบกว้างควรแยกจาก security fix และต้องผ่าน test suite เพื่อไม่ทำให้ runtime behavior เปลี่ยนโดยไม่ตั้งใจ

---

## 1. สถานะปัจจุบัน (As-Is)

### Dependency Surface

| ส่วน | ตัวจัดการ | จำนวนโดยประมาณ |
|-----|----------|----------------|
| Flutter app | `pubspec.yaml` | 47 direct + transitive จำนวนมาก |
| websocket-server | `package.json` | Node.js (express, socket.io, pg, redis, multer, ...) |
| iOS | CocoaPods (`Podfile.lock`) | ตาม Flutter plugins |
| Android | Gradle | ตาม Flutter plugins |

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| D1 | **ไม่มี automated vulnerability scanning** | 🔴 สูง | ไม่มี CI ตรวจ CVE — dependency ที่มีปัญหาอยู่ในระบบได้โดยไม่มีใครรู้ |
| D2 | **ไม่มี dependency update process** | 🟡 กลาง | ไม่มีรอบตรวจสอบ/อัปเดตที่ชัดเจน |
| D3 | **Caret constraints (`^`) ทุกตัว** | 🟡 กลาง | build ไม่ deterministic ถ้าไม่มี lockfile committed |
| D4 | **ไม่ทราบสถานะ lockfile ใน git** | 🟡 กลาง | ต้องยืนยันว่า `pubspec.lock` / `package-lock.json` ถูก commit |
| D5 | **Package ที่ deprecated/ไม่ maintain** | 🟡 กลาง | มีหลายตัวที่ต้องประเมิน (ดูตาราง section 2) |
| D6 | **Native dependency (iOS/Android)** | 🟡 กลาง | CocoaPods/Gradle dependency ไม่ค่อยถูกตรวจ |
| D7 | **ไม่มี SBOM** | 🟢 ต่ำ | ERP/HIS ที่มีข้อกำหนดอาจต้องการ Software Bill of Materials |
| D8 | **ไม่มี license compliance check** | 🟢 ต่ำ | GPL ใน commercial product เป็นความเสี่ยงทางกฎหมาย |
| D9 | **ไม่มี supply chain protection** | 🟡 กลาง | typosquatting, compromised package |

---

## 2. การวิเคราะห์ Dependency ที่ต้องจับตา

### 2.1 Flutter — Package ที่มีผลด้านความปลอดภัยโดยตรง

| Package | เวอร์ชัน | บทบาทด้านความปลอดภัย | ข้อสังเกต |
|---------|---------|---------------------|----------|
| `supabase_flutter` | ^2.12.0 | เชื่อมต่อ DB ทั้งหมด | ต้องตาม release note ทุกเวอร์ชัน |
| `crypto` | ^3.0.6 | password hashing ปัจจุบัน | จะเลิกใช้ถ้าย้ายไป server-side (แผน 10) |
| `google_sign_in` | ^6.2.1 | OAuth | มี v7 แล้ว — breaking changes ต้องประเมิน |
| `flutter_facebook_auth` | ^7.1.1 | OAuth | ตาม Facebook SDK policy |
| `sign_in_with_apple` | ^6.1.3 | OAuth | บังคับโดย App Store ถ้ามี social login อื่น |
| `http` | ^1.2.0 | network | ต้องบังคับ HTTPS |
| `shared_preferences` | ^2.5.5 | เก็บข้อมูลบนเครื่อง | ⚠️ **ไม่เข้ารหัส** — ห้ามเก็บ token (ดูแผน 08) |
| `hive` | ^2.2.3 | local cache (chat) | ⚠️ ไม่เข้ารหัสโดย default; Hive v2 อยู่ใน maintenance — `hive_ce` เป็นทางเลือก |
| `file_picker` | ^10.3.10 | เลือกไฟล์ | permission scope |
| `image_picker` | ^1.1.2 | เลือกรูป | permission scope |
| `permission_handler` | ^11.3.1 | จัดการสิทธิ์ | ควรขอเฉพาะที่จำเป็น |
| `geolocator` | ^12.0.0 | ตำแหน่ง | ข้อมูลอ่อนไหว; มี v13/v14 แล้ว |
| `flutter_webrtc` | ^0.12.3 | video call | attack surface สูง (media parsing) |
| `model_viewer_plus` | ^1.7.0 | 3D viewer | ใช้ WebView ภายใน (ดูแผน 14 X2) |
| `google_maps_flutter` | ^2.14.2 | แผนที่ | ต้องจำกัด API key (แผน 07 K9) |
| `health` | ^13.3.1 | ข้อมูลสุขภาพ | PHI — ต้องจัดการ permission เข้มงวด |
| `google_mlkit_face_detection` | ^0.13.2 | biometric-ish | ข้อมูลชีวมิติ — มีข้อกำหนดทางกฎหมาย |
| `record` | ^6.0.0 | บันทึกเสียง | permission + storage |
| `camera` | ^0.12.0 | กล้อง | permission |
| `xml` | ^6.6.1 | parse XML | ⚠️ XXE risk — ต้องปิด external entity |
| `csv` | ^6.0.0 | CSV | ⚠️ formula injection ตอน export (แผน 14) |

**Package ที่ควรพิจารณาเพิ่ม (จากแผนอื่น)**
| Package | สำหรับ | แผน |
|---------|--------|-----|
| `flutter_secure_storage` | เก็บ refresh token | 07 |
| `flutter_html` (+ sanitizer) | render rich text ปลอดภัย | 05 |
| `local_auth` | biometric unlock สำหรับ ERP/clinical | 07 |

### 2.2 Node.js — Package ที่ต้องจับตา

| Package | บทบาท | ข้อสังเกต |
|---------|-------|----------|
| `express` | web framework | ต้องอยู่บนเวอร์ชันที่ยัง support |
| `socket.io` | realtime | ตรวจ CVE เป็นระยะ |
| `pg` | PostgreSQL driver | ปลอดภัยดี ใช้ parameterized ถูกต้อง |
| `multer` | file upload | ⚠️ จุดเสี่ยงคลาสสิก — ต้องอัปเดตสม่ำเสมอ |
| `redis` / `ioredis` | cache/session | |
| **ที่ต้องเพิ่ม** | `jsonwebtoken` (แผน 08), `bcrypt`/`argon2` (แผน 10), `zod`/`joi` (แผน 11), `helmet` (แผน 14) | ต้องประเมินก่อนเพิ่ม |
| **ที่ต้องหลีกเลี่ยง** | `csurf` (deprecated) → ใช้ `csrf-csrf` แทน (แผน 15) | |

### 2.3 ผลกระทบต่อระบบตามแผน

| แผน | Dependency ที่จะเพิ่ม | ความเสี่ยง |
|-----|---------------------|-----------|
| `docs/ERP/POS System_plan.md` | Payment SDK, printer driver, barcode scanner | 🔴 payment SDK ต้อง audit เข้ม |
| `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` | PDF generation, Excel export, e-Tax library | 🟡 PDF/Excel lib มี CVE บ่อย |
| `docs/ERP/HR_SYSTEM_PLAN.md` | Payroll calculation, bank file format | 🔴 |
| `docs/ERP/LAB_SYSTEM_PLAN.md` | HL7 parser | 🟡 parser = attack surface |
| `docs/ERP/CRM_SYSTEM_PLAN.md` | Email/SMS SDK, template engine | 🟡 template engine → SSTI risk |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | ffmpeg/transcoding, CDN SDK | 🔴 media parsing = attack surface สูงมาก |
| `docs/plans/Delivery_PLAN.md` | Routing/map SDK, delivery partner SDK | 🟡 |
| `docs/plans/health_data_sync_plan.md` | Device SDK (BLE) | 🟡 |
| `docs/ERP/KPI_DASHBOARD_PLAN.md` | Charting library | 🟢 (มี `fl_chart` แล้ว) |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Automated Scanning ใน CI (แนะนำ) ⭐

```yaml
# .github/workflows/security.yml
name: Dependency Security
on: [push, pull_request, schedule: {cron: '0 2 * * 1'}]

jobs:
  flutter:
    steps:
      - run: flutter pub get
      - run: flutter pub outdated --show-all
      - run: dart pub audit          # ถ้ามีใน SDK version ที่ใช้

  node:
    steps:
      - run: npm ci --prefix websocket-server
      - run: npm audit --audit-level=high --prefix websocket-server

  osv:
    steps:
      - uses: google/osv-scanner-action@v1
        with:
          scan-args: |-
            --lockfile=pubspec.lock
            --lockfile=websocket-server/package-lock.json
```

**เครื่องมือที่แนะนำ**
| เครื่องมือ | ครอบคลุม | ต้นทุน |
|-----------|---------|-------|
| `npm audit` | Node.js | ฟรี (built-in) |
| **OSV-Scanner** (Google) | Dart/Flutter + Node + อื่น ๆ | ฟรี ⭐ |
| Dependabot | ทุก ecosystem + auto PR | ฟรีบน GitHub ⭐ |
| Renovate | เหมือน Dependabot แต่ config ยืดหยุ่นกว่า | ฟรี |
| Snyk | ครอบคลุมที่สุด + fix suggestion | ฟรี tier จำกัด |
| Trivy | container + dependency + IaC | ฟรี |

**ข้อดี:** ปิด D1, D2; ทำได้ใน 1–2 วัน; ทำงานอัตโนมัติตลอดไป
**ข้อเสีย:** false positive; ต้องมีคนดู alert (ไม่งั้นกลายเป็น noise)
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **ควรทำทันที ต้นทุนต่ำสุด ผลตอบแทนสูงสุด**

---

### ตัวเลือก B: Dependabot / Renovate — Auto Update PR

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/"
    schedule: { interval: "weekly" }
    open-pull-requests-limit: 5
    groups:
      minor-patch:
        update-types: ["minor", "patch"]

  - package-ecosystem: "npm"
    directory: "/websocket-server"
    schedule: { interval: "weekly" }

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "monthly" }
```

**ข้อดี:** อัปเดตต่อเนื่องไม่ค้างนาน; group minor/patch ลด PR noise; security update แยก priority
**ข้อเสีย:** PR เยอะถ้าไม่ config ดี; ต้องมี test ครอบคลุมถึงจะ merge ได้อย่างมั่นใจ
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — ควรทำคู่กับ A

---

### ตัวเลือก C: Version Pinning + Manual Review

เปลี่ยน `^1.2.0` → `1.2.0` แล้ว review manual ทุกการอัปเดต

**ข้อดี:** build deterministic 100%; ควบคุมเต็มที่; ไม่มี surprise
**ข้อเสีย:** ตกเวอร์ชันเร็ว; security patch ไม่ได้อัตโนมัติ; ภาระ manual สูง
**ความเหมาะสมระยะยาว:** ⭐⭐ — lockfile ให้ผลเดียวกันโดยไม่เสียความยืดหยุ่น

> **คำแนะนำที่ถูกต้อง:** คง `^` ใน `pubspec.yaml`/`package.json` + **commit lockfile** = ได้ทั้ง reproducible build และความยืดหยุ่น (ปิด D3, D4)

---

### ตัวเลือก D: SBOM + License Compliance

```bash
# สร้าง SBOM (CycloneDX format)
cyclonedx-npm --output-file sbom-node.json
# Dart: ใช้ cyclonedx-dart หรือ syft

# License check
license_checker --allowed "MIT,BSD-3-Clause,Apache-2.0"
```

**ข้อดี:** ตอบข้อกำหนด compliance (HIS/LAB/การเงินอาจต้องการ); รู้ทันทีว่ากระทบไหมเมื่อมี CVE ใหม่; ป้องกันปัญหา license
**ข้อเสีย:** ต้องดูแล SBOM ให้ทันสมัย; ทีมเล็กอาจยังไม่จำเป็น
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — ทำเมื่อเข้าสู่ระยะ compliance (ERP/HIS)

---

### ตัวเลือก E: Supply Chain Hardening

```
1. npm: ตั้ง registry allowlist + verify integrity hash
2. Pin GitHub Actions ด้วย commit SHA ไม่ใช่ tag
3. ตรวจสอบ package ใหม่ก่อนเพิ่ม: อายุ, จำนวนดาวน์โหลด, maintainer, การอัปเดตล่าสุด
4. ห้ามใช้ package ที่มี postinstall script โดยไม่ตรวจสอบ
5. Vendor package ที่สำคัญมากแต่ maintain น้อย
```

**ข้อดี:** ป้องกัน typosquatting และ compromised package; ปิด D9
**ข้อเสีย:** เพิ่ม friction ในการพัฒนา
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ควรมีอย่างน้อยเป็น checklist

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A + B ทันที + commit lockfile + E เป็น checklist** | ต้นทุนต่ำมาก (2–3 วัน) ได้ผลป้องกันต่อเนื่องตลอดไป |
| 2 | **A + B + D** | ถ้า ERP/HIS มีข้อกำหนด compliance ชัดเจนแล้ว |
| 3 | **A อย่างเดียว** | ขั้นต่ำที่ยอมรับได้ — อย่างน้อยต้องรู้ว่ามีปัญหา |
| 4 | **C** | ไม่แนะนำ — lockfile ทำหน้าที่นี้ได้ดีกว่า |

---

## 5. นโยบายจัดการ Dependency ที่เสนอ

### 5.1 SLA การแก้ไขตามระดับความรุนแรง
| ระดับ CVSS | SLA | การดำเนินการ |
|-----------|-----|-------------|
| Critical (9.0–10.0) | 24 ชม. | Hotfix ทันที, อาจต้อง emergency release |
| High (7.0–8.9) | 7 วัน | รวมใน release ถัดไป |
| Medium (4.0–6.9) | 30 วัน | รวมใน maintenance cycle |
| Low (0.1–3.9) | 90 วัน | รวมใน routine update |

### 5.2 เกณฑ์การเพิ่ม Dependency ใหม่
```
ก่อนเพิ่ม package ใหม่ ต้องตอบได้ว่า:
  [ ] จำเป็นจริงหรือเขียนเองได้ใน < 200 บรรทัด?
  [ ] อัปเดตล่าสุดภายใน 12 เดือน?
  [ ] มี maintainer มากกว่า 1 คน หรือมีองค์กรดูแล?
  [ ] License เข้ากันได้ (MIT/BSD/Apache-2.0)?
  [ ] ไม่มี CVE ที่ยังไม่แก้?
  [ ] transitive dependency ไม่มากเกินควร?
  [ ] มี postinstall script หรือไม่? ถ้ามี ตรวจแล้วหรือยัง?
  [ ] ถ้า package หายไป มีทางเลือกอื่นหรือไม่?
```

### 5.3 รอบการตรวจสอบ
| กิจกรรม | ความถี่ |
|---------|---------|
| Automated scan | ทุก PR + weekly |
| Dependabot PR review | สัปดาห์ละครั้ง |
| `flutter pub outdated` review | เดือนละครั้ง |
| Major version upgrade planning | ไตรมาสละครั้ง |
| Full dependency audit | ปีละครั้ง |
| Flutter/Dart SDK upgrade | ตาม stable release (ปัจจุบัน 3.38.1) |

---

## 6. งานที่ต้องตรวจสอบทันทีเมื่ออนุมัติ

- [ ] ยืนยันว่า `pubspec.lock` และ `websocket-server/package-lock.json` ถูก commit ใน git
- [ ] รัน `npm audit` ครั้งแรกเพื่อดู baseline
- [ ] รัน `flutter pub outdated` เพื่อดูว่าตกเวอร์ชันไปแค่ไหน
- [ ] ตรวจ `Podfile.lock` และ Gradle dependency
- [ ] ประเมิน `hive` v2 (maintenance mode) → ควรย้ายไป `hive_ce` หรือ `isar` หรือไม่
- [ ] ประเมิน `google_sign_in` v6 → v7 (breaking changes)
- [ ] ตรวจ `xml` parser config ว่าปิด external entity แล้วหรือยัง

---

## 7. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/infrastructure/SETUP_NEW_MACHINE.md` | ควรระบุเวอร์ชัน Flutter/Node ที่แน่นอน |
| `docs/infrastructure/architecture_analysis.md` | dependency ใหม่จากแผนอื่นต้องผ่านเกณฑ์ section 5.2 |
| `docs/plans/SETUP_PLAN_SUMMARY.md` | ควรเพิ่มขั้นตอน dependency check |
| `docs/guides/TEST_PLAN.md` | Test suite ต้องครอบคลุมพอที่จะ merge Dependabot PR ได้อย่างมั่นใจ — **นี่คือเหตุผลสำคัญที่ต้องมี E2E test ครบ** |
| ทุกแผนใน `docs/ERP/` | ต้องระบุ dependency ที่จะเพิ่มพร้อมเหตุผลในแต่ละแผน |

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติการเพิ่ม CI workflow สำหรับ dependency scanning (แนะนำ: ใช่ ทำทันที)
- [ ] เลือกเครื่องมือ: OSV-Scanner / Snyk / Trivy / npm audit อย่างเดียว
- [ ] อนุมัติการเปิด Dependabot หรือ Renovate
- [ ] อนุมัติ SLA การแก้ไข (ตาราง 5.1)
- [ ] อนุมัติเกณฑ์การเพิ่ม dependency ใหม่ (ตาราง 5.2)
- [ ] ตัดสินใจว่าต้องการ SBOM หรือไม่ (ขึ้นกับข้อกำหนด compliance ของ ERP/HIS)
- [ ] กำหนดผู้รับผิดชอบ review security alert
