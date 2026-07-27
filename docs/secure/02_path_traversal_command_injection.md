# แผนป้องกัน 02: Path Traversal และ Command Injection

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P0-A (มีหลักฐานในโค้ดปัจจุบัน)
> **เกี่ยวข้องกับแผน:** 11 (Input Validation), 13 (SQL Injection — คนละชนิดของ injection), 14 (XSS), 12 (Least Privilege)
> **ความแตกต่างจากแผน 13:** แผน 13 ครอบคลุมเฉพาะ **SQL** · แผนนี้ครอบคลุม **filesystem path, OS command, NoSQL/Redis, XML** ซึ่ง Sheserved มี attack surface สูงมากจาก video/photo pipeline (ffmpeg, face blur, watermark)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 2** ก่อนเพิ่มความสามารถ video/photo หรือเปลี่ยน pipeline
> **เหตุผล:** `incidentId` จาก request ถูกนำไปประกอบ path และ media pipeline แตะ filesystem/เครื่องมือประมวลผลโดยตรง จึงต้องบังคับ UUID/safe-path, filename isolation และ command argument allowlist ก่อนขยาย feature

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ทำได้ดีอยู่แล้ว ✅
| จุด | รายละเอียด |
|-----|------------|
| ชื่อไฟล์อัปโหลด | `video.js` ใช้ `${uuidv4()}${path.extname(...)}` — ไม่ใช้ชื่อจาก client โดยตรง |
| ffmpeg | ใช้ `fluent-ffmpeg` (argument array) ไม่ใช่ `exec()` ต่อ string |
| Multer | จำกัดขนาดไฟล์, มี fileFilter บาง route |

### จุดที่ต้องปิด — พร้อมหลักฐานจากโค้ดจริง

**1. `incidentId` จาก request body ถูกนำไปประกอบ path โดยตรง** 🔴
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:193-202
            let reportDir;
            if (isThaiMhung && incidentId) {
                reportDir = path.join(baseDir, incidentId, 'thaimhung', videoId);
            } else {
                reportDir = path.join(baseDir, videoId);
            }

            if (!fs.existsSync(reportDir)) {
                fs.mkdirSync(reportDir, { recursive: true });
            }
```
`incidentId` มาจาก `req.body` (บรรทัด 179) โดยไม่ผ่านการตรวจรูปแบบ UUID — `path.join` จะ normalize `../` ให้ ทำให้เขียนไฟล์ออกนอก `baseDir` ได้ และมีการ `fs.readdirSync`, `fs.mkdirSync`, `fs.renameSync`, `fs.unlinkSync` ตามมาทั้งหมด

**2. นามสกุลไฟล์จาก client ถูกใช้ตั้งชื่อไฟล์ที่เขียนลงดิสก์** 🔴
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/admin.js:26-28
        filename: (req, file, cb) => {
            cb(null, 'watermark' + path.extname(file.originalname));
        }
```
`path.extname` ของ `originalname` ที่ client ควบคุมได้ → เขียนไฟล์นามสกุลใดก็ได้ลงใน `uploads/watermarks/` ซึ่งถูก **เสิร์ฟเป็น static** (เชื่อมโยงกับแผน 14 X8)

**3. ตรวจชนิดไฟล์จาก MIME ที่ client ส่งมา** 🟡
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/admin.js:34-40
        fileFilter: (req, file, cb) => {
            if (file.mimetype === 'image/png') {
                cb(null, true);
            } else {
                cb(new Error('Only PNG format is allowed for watermark images!'));
            }
        }
```
`file.mimetype` มาจาก header ของ client — ปลอมได้ ต้องตรวจ magic bytes เพิ่ม

**4. `POST /videos/upload` ไม่มี fileFilter เลย** 🟡
`video.js:42-45` — multer รับไฟล์อะไรก็ได้ ขนาดถึง 500MB

**5. path ที่สร้างจาก `incidentId` ถูกใช้ต่อในหลายจุด**
`thaimhungBaseDir` (บรรทัด 248), `destDirForThumb` (277), `thumbLocalPath` (278) — ทั้งหมดสืบทอดค่าที่ยังไม่ validate

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| PT1 | **ID จาก request ถูกใช้ประกอบ filesystem path** | 🔴 วิกฤต | `incidentId`, `videoId` ไม่ validate รูปแบบ |
| PT2 | **นามสกุลไฟล์จาก client** | 🔴 สูง | `path.extname(file.originalname)` |
| PT3 | **ไม่มี containment check** | 🔴 สูง | ไม่ตรวจว่า path ผลลัพธ์ยังอยู่ใน base directory |
| PT4 | **ตรวจชนิดไฟล์จาก MIME เท่านั้น** | 🟡 กลาง | ไม่ตรวจ magic bytes |
| PT5 | **บาง upload route ไม่มี fileFilter** | 🟡 กลาง | `/videos/upload` |
| PT6 | **Static serving ของไฟล์ที่ผู้ใช้อัปโหลด** | 🟡 กลาง | `/uploads/`, `/temp/videos/` ไม่มี `Content-Disposition`/`nosniff` |
| PT7 | **ffmpeg filter string ประกอบจากตัวแปร** | 🟡 กลาง | `-vf` options สร้างจาก watermark config (ค่าจาก DB ที่ admin กรอก) |
| PT8 | **Redis key ประกอบจาก input** | 🟡 กลาง | cache key มี `${id}` ตรง ๆ — `*` ใน key ทำให้ `invalidateCachePattern` ลบเกินขอบเขต |
| PT9 | **XML parser (`xml: ^6.6.1`)** | 🟡 กลาง | XXE — ต้องยืนยันว่าปิด external entity |
| PT10 | **ไม่มี disk quota / cleanup policy** | 🟡 กลาง | เขียนไฟล์ได้ไม่จำกัด (เชื่อมโยงแผน 03) |
| PT11 | **Process ทำงานด้วยสิทธิ์สูง** | 🟡 กลาง | ถ้ารันเป็น root ผลกระทบจากการเขียนไฟล์ผิดที่จะรุนแรง |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | การจัดการไฟล์ / คำสั่งภายนอก | ความเสี่ยง |
|------|----------------------------|-----------|
| **Video System** | multer → ffmpeg transcode → HLS → thumbnail → Bunny upload | 🔴 สูงสุด — pipeline ยาว หลายจุดสัมผัส path |
| **Thai Mhung Photos** | multer → rename → face blur → watermark → thumbnail | 🔴 `incidentId` ในทุก path |
| **Face Blur** | `face-blur-service` อ่าน/เขียนไฟล์ | 🟡 |
| **Watermark** | `watermark-service` + ffmpeg overlay | 🟡 config จาก DB เข้า filter string |
| **Admin watermark upload** | multer → static serve | 🔴 นามสกุลจาก client |
| **Chat attachments** | Supabase Storage | 🟢 (Storage จัดการ path เอง — แต่ต้องตรวจ bucket policy, ดูแผน 12 L6) |
| **Registration documents** | Supabase Storage | 🟢 เช่นกัน |
| **Profile image** | `image_picker` + compress → upload | 🟡 |
| **Voice message** | `record` → upload | 🟡 |
| **CSV import/export** | `csv` package | 🟡 formula injection (แผน 14) |

### 2.2 ระบบตามแผน — จุดที่จะเพิ่ม attack surface

| แผน | ประเด็น |
|-----|---------|
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | 🔴 transcoding, CDN sync, HLS segment path — pipeline ขยายใหญ่ขึ้น |
| `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` | 🔴 PDF/Excel generation, e-Tax XML, bank statement import — ทุกอย่างเกี่ยวกับไฟล์ |
| `docs/ERP/PROCUREMENT_SYSTEM_PLAN.md` | Report export, แนบเอกสาร PO, supplier catalog import |
| `docs/ERP/HR_SYSTEM_PLAN.md` | เอกสารพนักงาน, payslip PDF, bank transfer file |
| `docs/ERP/INVENTORY_SYSTEM_PLAN.md` | Barcode label printing, stock import CSV |
| `docs/ERP/LAB_SYSTEM_PLAN.md` | 🔴 HL7 message parsing, DICOM/ผลตรวจแนบไฟล์ |
| `docs/ERP/HIS_SYSTEM_PLAN.md` | 🔴 เอกสารผู้ป่วย, ภาพทางการแพทย์ |
| `docs/ERP/CRM_SYSTEM_PLAN.md` | Email attachment, template file |
| `docs/ERP/POS System_plan.md` | Receipt printing (ESC/POS command), cash drawer trigger |
| `docs/plans/Delivery_PLAN.md` | Proof-of-delivery photo, signature image |
| `docs/plans/SHOPPING_CART_PLAN.md` | Product image import จาก supplier |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Safe Path Helper + Containment Check (แนะนำ) ⭐

```js
// websocket-server/utils/safe-path.js
const path = require('path');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function assertUuid(value, fieldName) {
  if (typeof value !== 'string' || !UUID_RE.test(value)) {
    const err = new Error(`Invalid ${fieldName}`);
    err.statusCode = 400;
    throw err;
  }
  return value;
}

/** ประกอบ path แล้วยืนยันว่าผลลัพธ์ยังอยู่ภายใน baseDir */
function safeJoin(baseDir, ...segments) {
  const base = path.resolve(baseDir);
  const target = path.resolve(base, ...segments);
  if (target !== base && !target.startsWith(base + path.sep)) {
    const err = new Error('Path escapes base directory');
    err.statusCode = 400;
    throw err;
  }
  return target;
}

const ALLOWED_EXT = { image: ['.jpg','.jpeg','.png','.webp'], video: ['.mp4','.mov'] };

function safeExtension(originalName, kind) {
  const ext = path.extname(originalName || '').toLowerCase();
  return ALLOWED_EXT[kind].includes(ext) ? ext : ALLOWED_EXT[kind][0];
}
```

**การนำไปใช้กับจุดที่พบ**
```js
// video.js — upload-photos
assertUuid(incidentId, 'incidentId');
const reportDir = isThaiMhung && incidentId
  ? safeJoin(baseDir, incidentId, 'thaimhung', videoId)
  : safeJoin(baseDir, videoId);

// admin.js — watermark filename
cb(null, 'watermark' + safeExtension(file.originalname, 'image'));
```

**ข้อดี**
- ปิด PT1, PT2, PT3 ด้วยโค้ดไม่กี่สิบบรรทัด
- ใช้ซ้ำได้ทุกจุด; ทดสอบ helper ตัวเดียวได้ครบ
- ไม่มี dependency เพิ่ม

**ข้อเสีย**
- ต้องไล่แก้ทุกจุดที่ประกอบ path (แต่มีไม่มาก — ประมาณ 10–15 จุด)

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **ต้นทุนต่ำมาก ผลตอบแทนสูงสุด**

---

### ตัวเลือก B: Content-Based File Validation (Magic Bytes)

```js
const { fileTypeFromFile } = require('file-type');

async function validateFileContent(filePath, allowedMimes) {
  const type = await fileTypeFromFile(filePath);
  if (!type || !allowedMimes.includes(type.mime)) {
    fs.unlinkSync(filePath);
    throw Object.assign(new Error('Invalid file content'), { statusCode: 400 });
  }
  return type;
}
```
+ สำหรับรูปภาพ: re-encode ผ่าน `sharp`/`image` เพื่อล้าง metadata และ payload ที่ฝังมา

**ข้อดี:** ปิด PT4, PT5; re-encoding ล้าง EXIF (ซึ่งอาจมี GPS ของผู้ใช้ — ประเด็นความเป็นส่วนตัวด้วย)
**ข้อเสีย:** ต้องเขียนไฟล์ลงดิสก์ก่อนตรวจ (ยกเว้นใช้ memory storage); เพิ่ม CPU
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก C: แยก Storage ออกจาก Application Filesystem

ย้ายไฟล์ทั้งหมดไป Supabase Storage / S3-compatible / Bunny Storage แทนการเขียนลง local disk

**ข้อดี:** ✅ **แก้ที่รากเลย** — ไม่มี local path = ไม่มี path traversal; ได้ CDN, backup, quota มาด้วย; scale ได้; สอดคล้องกับ `reverse_proxy_plan.md`
**ข้อเสีย:** transcoding ยังต้องใช้ local temp อยู่ดี; ต้นทุนเพิ่ม; refactor video pipeline ใหญ่; local-only mode ใช้ไม่ได้
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — เป้าหมายที่ดี แต่ยังต้องมี A สำหรับ temp directory

---

### ตัวเลือก D: OS-Level Sandboxing

```
1. รัน websocket-server ด้วย user ที่ไม่ใช่ root
2. Container: read-only root filesystem + tmpfs mount เฉพาะ temp dir
3. ffmpeg รันใน container/process แยกที่ไม่มีสิทธิ์เขียนนอก temp
4. AppArmor/SELinux profile จำกัด path ที่เข้าถึงได้
5. Disk quota ต่อ directory
```

**ข้อดี:** ปิด PT10, PT11; จำกัดผลกระทบแม้มีช่องโหว่หลุด; ป้องกัน ffmpeg exploit (media parser มีประวัติ CVE)
**ข้อเสีย:** ต้องปรับ deployment; debug ยากขึ้น; ต้องความรู้ระบบปฏิบัติการ
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — ควรทำร่วมกับแผน 04 (misconfiguration)

---

### ตัวเลือก E: Static Analysis + Lint Rules

```yaml
# ตรวจหา path.join ที่มีตัวแปรจาก req
- run: |
    ! grep -rnE 'path\.(join|resolve)\([^)]*req\.' websocket-server/
    ! grep -rn 'child_process' websocket-server/
    ! grep -rnE '\bexec\(|\bexecSync\(' websocket-server/
```
+ `eslint-plugin-security`: `detect-non-literal-fs-filename`, `detect-child-process`

**ข้อดี:** ป้องกัน regression; ต้นทุนต่ำมาก (1 วัน)
**ข้อเสีย:** false positive; ไม่แก้ของเดิม
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — ทำคู่กับ A

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **A + B ทันที + E เป็น CI gate + D ตอน deploy** | A/B แก้ต้นเหตุด้วยต้นทุนต่ำ, E กันถดถอย, D จำกัดผลกระทบ |
| 2 | **A + E ก่อน แล้ว C ระยะยาว** | ถ้าวางแผนย้ายไป cloud storage อยู่แล้ว |
| 3 | **C เป็นหลัก + A สำหรับ temp** | ถ้า video pipeline จะ refactor ใหญ่อยู่แล้วตาม `VIDEO_SYSTEM_PLAN.md` |
| 4 | **D อย่างเดียว** | ไม่พอ — sandbox ไม่ป้องกันการเขียนทับไฟล์ภายใน temp dir เดียวกัน |

---

## 5. กฎมาตรฐานที่เสนอ (Sheserved File & Command Standard)

```
📁 Filesystem
  1. ห้ามนำค่าจาก request ไปประกอบ path โดยไม่ validate รูปแบบ (UUID/allowlist)
  2. ทุก path ที่ประกอบขึ้นต้องผ่าน containment check กับ base directory
  3. ชื่อไฟล์บนดิสก์ต้องสร้างเองเสมอ (UUID) — ห้ามใช้ originalname
  4. นามสกุลต้องมาจาก allowlist ไม่ใช่จาก originalname
  5. ตรวจ magic bytes ทุกไฟล์ที่อัปโหลด ไม่เชื่อ MIME header
  6. รูปภาพควร re-encode เพื่อล้าง metadata/payload (และล้าง EXIF GPS)
  7. Static serving ของไฟล์ผู้ใช้: Content-Disposition: attachment + nosniff
  8. Temp file ต้องมี TTL และ cleanup job

⚙️ OS Command
  9. ห้ามใช้ exec/execSync/shell:true กับค่าจาก user
 10. ใช้ spawn + argument array เท่านั้น
 11. ffmpeg: ใช้ fluent-ffmpeg API ห้ามต่อ filter string จาก user input
 12. Path ที่ส่งให้ external binary ต้องผ่าน safeJoin แล้ว

🗄️ อื่น ๆ
 13. Redis key: sanitize อักขระ glob (* ? [ ]) ก่อนใช้ โดยเฉพาะกับ pattern delete
 14. XML parser: ปิด external entity และ DTD
 15. JSON.parse ค่าจาก user: ห่อ try/catch + จำกัดขนาด
 16. Archive extraction (ถ้ามีในอนาคต): ตรวจ zip-slip ทุก entry
```

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/secure/11_input_validation.md` | ต่อเนื่องกัน — UUID validation (V7) เป็น prerequisite ของแผนนี้ |
| `docs/secure/13_sql_injection.md` | คนละชนิดของ injection แต่ใช้หลักการเดียวกัน (allowlist, ไม่ต่อ string) |
| `docs/secure/14_xss.md` | PT6 ทับกับ X8/X9 — ควร implement พร้อมกัน |
| `docs/secure/12_least_privilege.md` | PT11 (process privilege) และ L6 (Storage bucket policy) เกี่ยวข้องโดยตรง |
| `docs/secure/03_rate_limiting_resource_exhaustion.md` | PT10 (disk quota) อยู่ในขอบเขตแผน 03 ด้วย |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | ⚠️ ต้องเพิ่มข้อกำหนดความปลอดภัยของ pipeline ในแผนนั้น |
| `docs/infrastructure/reverse_proxy_plan.md` | Static file serving headers ควรตั้งที่ proxy |
| `docs/guides/TEST_PLAN.md` | ควรเพิ่ม SEC test: อัปโหลดไฟล์ที่ MIME ไม่ตรงกับเนื้อหา, ส่ง incidentId รูปแบบผิด |

---

## 7. งานที่ต้องตรวจสอบทันทีเมื่ออนุมัติ

- [ ] ไล่ทุกจุดที่ใช้ `path.join` / `path.resolve` กับค่าที่มาจาก request
- [ ] ตรวจ `websocket-server` รันด้วย user อะไร (root หรือไม่)
- [ ] ตรวจ permission ของ `temp/videos/` และ `uploads/`
- [ ] ตรวจว่ามีการใช้ `child_process` / `exec` ที่ไหนหรือไม่
- [ ] ตรวจ config ของ `xml` parser (XXE)
- [ ] ตรวจ Supabase Storage bucket policy ว่าเป็น private
- [ ] ตรวจว่า `invalidateCachePattern` รับ pattern จาก user ได้หรือไม่

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติการเพิ่ม `utils/safe-path.js` helper (A) — แนะนำ: ใช่ ทำทันที
- [ ] อนุมัติการเพิ่ม `file-type` สำหรับ magic byte validation (B)
- [ ] ตัดสินใจว่าจะ re-encode รูปภาพเพื่อล้าง EXIF หรือไม่ (กระทบความเป็นส่วนตัวด้วย)
- [ ] ตัดสินใจเรื่องย้ายไป cloud storage (C) — สอดคล้องกับ `VIDEO_SYSTEM_PLAN.md` หรือไม่
- [ ] อนุมัติการเพิ่ม lint rules ใน CI (E)
- [ ] ตัดสินใจเรื่อง containerization / non-root user (D) — ร่วมกับแผน 04
- [ ] กำหนด TTL และ cleanup policy ของ temp files
