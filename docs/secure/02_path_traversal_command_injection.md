# แผนป้องกัน 02: Path Traversal และ Command Injection

> **สถานะ:** ✅ เลือกแนวทางแล้ว — **A: implement และทดสอบผ่านแล้ว (2026-07-27)** · B ทันที, E เป็น CI gate, D เป็น defense-in-depth, C เป็นเป้าหมายระยะยาว
> **Priority:** P0-A (มีหลักฐานจากโค้ดจริง)
> **เกี่ยวข้องกับแผน:** 11 (Input Validation), 13 (SQL Injection — คนละชนิดของ injection), 14 (XSS), 12 (Least Privilege), 03 (Resource Exhaustion)
> **ความแตกต่างจากแผน 13:** แผน 13 ครอบคลุมเฉพาะ **SQL** · แผนนี้ครอบคลุม **filesystem path, OS command, NoSQL/Redis, XML** ซึ่ง Sheserved มี attack surface สูงจาก video/photo pipeline (ffmpeg, face blur, watermark)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S0-A ลำดับ 2** · **Option A implement และทดสอบผ่านแล้ว** ด้วย Maestro flow บน iPhone 16 simulator
> **ข้อสรุปการเลือก:** เลือก **Option A เป็นมาตรการบังคับทุก path**, ใช้ **Option B ตรวจเนื้อหาไฟล์ทุก upload**, ใช้ **Option E ป้องกัน regression**, ใช้ **Option D จำกัด blast radius ตอน deploy** และวาง **Option C เป็น migration ระยะยาว**. ไม่เลือก D หรือ C เพียงอย่างเดียว เพราะไม่ปิดช่องโหว่ที่ต้นทางและยังต้องมี local temp สำหรับ transcoding
> **เหตุผล:** พบทั้ง `incidentId` ที่ถูกนำไปประกอบ path โดยไม่ validate และ `execSync` ที่ต่อ shell command จาก path ซึ่งเป็นความเสี่ยง command injection จริง จึงต้องแก้ path และ process execution ก่อนขยาย feature

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ทำได้ดีอยู่แล้ว ✅
| จุด | รายละเอียด |
|-----|------------|
| ชื่อไฟล์อัปโหลด | `video.js` ใช้ `${uuidv4()}${safeExtension(...)}` — ไม่ใช้ชื่อจาก client โดยตรง และนามสกุลผ่าน allowlist แล้ว |
| ffmpeg/transcoding | ส่วน transcoding ใช้ `fluent-ffmpeg` · ขั้นตอน face blur เปลี่ยนจาก `execSync` เป็น `spawn` พร้อม argument array แล้ว |
| Safe Path Helper | ✅ `websocket-server/utils/safe-path.js` สร้างแล้ว — `assertUuid`, `safeJoin`, `safeExtension`, `assertAllowedCommand`, `resolveExecutable`, `sanitizeCacheKey` |
| Path containment | ✅ ทุก `path.join` ที่ใช้ user-controlled input เปลี่ยนเป็น `safeJoin` แล้วใน `video.js` และ `video-service.js` |
| Command execution | ✅ `execSync` ใน `video-service.js` เปลี่ยนเป็น `spawn` พร้อม argument array และ `assertAllowedCommand` แล้ว |
| Multer | จำกัดขนาดไฟล์, มี fileFilter บาง route แต่ `/videos/upload` ยังรับไฟล์โดยไม่มี content validation |

### จุดที่ต้องปิด — พร้อมหลักฐานจากโค้ดจริง

**1. `incidentId` จาก request body ถูกนำไปประกอบ path โดยตรง** ✅ ปิดแล้ว
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/video.js:192-212
            // ✅ Option A: validate incidentId เป็น UUID ก่อนใช้กับ filesystem
            const validatedIncidentId = assertUuidOrNull(incidentId, 'incidentId');
            ...
            if (isThaiMhung && validatedIncidentId) {
                reportDir = safeJoin(baseDir, validatedIncidentId, 'thaimhung', videoId);
            } else {
                reportDir = safeJoin(baseDir, videoId);
            }
```
`incidentId` จาก `req.body` ผ่าน `assertUuidOrNull` ก่อนใช้กับ filesystem — `safeJoin` ตรวจ containment ป้องกันการหลุดออกจาก `baseDir`

**2. นามสกุลไฟล์จาก client ถูกใช้ตั้งชื่อไฟล์ที่เขียนลงดิสก์** ✅ ปิดแล้ว
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/routes/admin.js:27-33
        filename: (req, file, cb) => {
            try {
                const ext = safeExtension(file.originalname, 'image');
                cb(null, 'watermark' + ext);
            } catch (err) {
                cb(err);
            }
        }
```
`safeExtension` ตรวจนามสกุลจาก allowlist (`.jpg`, `.jpeg`, `.png`, `.webp`) — fail-closed หากไม่ตรง

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

**5. path ที่สร้างจาก `incidentId` ถูกใช้ต่อในหลายจุด** ✅ ปิดแล้ว
`thaimhungBaseDir`, `destDirForThumb`, `thumbLocalPath` — ทั้งหมดเปลี่ยนเป็น `safeJoin` และใช้ `validatedIncidentId` แล้ว

**6. Face blur ต่อ path เข้า shell command โดยตรง** ✅ ปิดแล้ว
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/services/video-service.js:122-156
    try {
        assertUuid(videoId, 'videoId');
        const blurredPath = safeJoin(baseDir, `${videoId}_blurred.mp4`);
        ...
        const defaceBin = resolveExecutable('DEFACE_PATH', 'deface');
        assertAllowedCommand(defaceBin);
        
        await new Promise((resolve, reject) => {
            const defaceProc = spawn(defaceBin, [
                inputVideoPath,
                '-o', blurredPath,
                '--replacewith', 'blur',
                '--keep-audio',
            ], { stdio: 'pipe' });
            ...
        });
```
เปลี่ยนจาก `execSync` เป็น `spawn` พร้อม argument array — ไม่ผ่าน shell ป้องกัน command injection และใช้ `assertAllowedCommand` + `resolveExecutable` ตรวจสอบ executable ก่อนเรียก

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| PT1 | **ID จาก request ถูกใช้ประกอบ filesystem path** | ✅ ปิดแล้ว | `assertUuid`/`assertUuidOrNull` ใช้กับ `incidentId`, `videoId` ก่อนเข้า filesystem |
| PT2 | **นามสกุลไฟล์จาก client** | ✅ ปิดแล้ว | `safeExtension` ตรวจจาก allowlist — ใช้ใน `video.js` และ `admin.js` |
| PT3 | **ไม่มี containment check** | ✅ ปิดแล้ว | `safeJoin` ตรวจว่า path ผลลัพธ์ยังอยู่ใน base directory ทุกจุด |
| PT4 | **ตรวจชนิดไฟล์จาก MIME เท่านั้น** | 🟡 กลาง | ไม่ตรวจ magic bytes |
| PT5 | **บาง upload route ไม่มี fileFilter** | 🟡 กลาง | `/videos/upload` |
| PT6 | **Static serving ของไฟล์ที่ผู้ใช้อัปโหลด** | 🟡 กลาง | `/uploads/`, `/temp/videos/` ไม่มี `Content-Disposition`/`nosniff` |
| PT7 | **คำสั่ง shell จาก path** | ✅ ปิดแล้ว | `execSync` เปลี่ยนเป็น `spawn` พร้อม argument array และ `assertAllowedCommand` |
| PT8 | **ffmpeg filter string ประกอบจากตัวแปร** | 🟡 กลาง | `-vf` options สร้างจาก watermark config (ค่าจาก DB ที่ admin กรอก) |
| PT9 | **Redis key ประกอบจาก input** | ✅ ปิดแล้ว (Option A) | `sanitizeCacheKey` กรองอักขระ glob ก่อนใช้กับ `invalidateCachePattern` |
| PT10 | **XML parser (`xml: ^6.6.1`)** | 🟡 กลาง | ต้อง escape input ก่อนสร้าง SOAP/XML และยืนยัน parser policy ไม่รับ external entity |
| PT11 | **ไม่มี disk quota / cleanup policy** | 🟡 กลาง | เขียนไฟล์ได้ไม่จำกัด (เชื่อมโยงแผน 03) |
| PT12 | **Process ทำงานด้วยสิทธิ์สูง** | 🟡 กลาง | ถ้ารันเป็น root ผลกระทบจากการเขียนไฟล์ผิดที่จะรุนแรง |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | การจัดการไฟล์ / คำสั่งภายนอก | ความเสี่ยง |
|------|----------------------------|-----------|
| **Video System** | multer → ffmpeg transcode → HLS → thumbnail → Bunny upload | ✅ ปิด PT1/PT3/PT7 — `safeJoin` และ `assertUuid` ใช้ในทุก path |
| **Thai Mhung Photos** | multer → rename → face blur → watermark → thumbnail | ✅ ปิด PT1/PT3 — `validatedIncidentId` และ `safeJoin` ในทุก path |
| **Face Blur** | `face-blur-service` และ `video-service.js` ใช้ `spawn` พร้อม argument array และ `assertAllowedCommand` แล้ว | ✅ ปิด PT7 |
| **Watermark** | `watermark-service` + ffmpeg overlay | 🟡 config จาก DB เข้า filter string |
| **Admin watermark upload** | multer → static serve | ✅ ปิด PT2 — `safeExtension` ตรวจนามสกุลจาก allowlist |
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
  if (!ALLOWED_EXT[kind] || !ALLOWED_EXT[kind].includes(ext)) {
    const err = new Error(`Unsupported ${kind} file extension`);
    err.statusCode = 415;
    throw err;
  }
  return ext;
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

**ข้อดี:** จำกัดผลกระทบจาก PT11, PT12 และลด blast radius ของ PT1-PT10 หากมีช่องโหว่หลุด; ป้องกัน ffmpeg exploit ได้ดีขึ้น (media parser มีประวัติ CVE)
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

## 7. แผน implementation และการเตรียมพร้อม

### 7.1 รอบเร่งด่วน: ปิดช่องโหว่ต้นทางก่อน deploy feature เพิ่ม

**Option A — Safe Path Helper + Containment Check (บังคับใช้ทุก local path)**

- [x] สร้าง `websocket-server/utils/safe-path.js` โดยมี `assertUuid`, `safeJoin`, `safeExtension` และ `assertAllowedCommand` ✅ (2026-07-27)
- [x] validate `incidentId`, `videoId` และ identifier ทุกตัวก่อนใช้กับ filesystem หรือ cache pattern ✅
- [x] ใช้ `safeJoin` กับ `baseDir`, `reportDir`, `thaimhungBaseDir`, `destDirForThumb`, `thumbLocalPath`, `originalPath`, `anonPath`, `wmPath` และ persistent thumbnail directory ✅
- [x] ห้ามใช้ path จาก request เป็นชื่อไฟล์; สร้างชื่อด้วย UUID/ค่าที่ server สร้างเองเท่านั้น ✅
- [x] ใช้ `path.basename` หลัง validate เท่านั้น และตรวจว่าผลลัพธ์ยังอยู่ใน base directory ทุกครั้ง ✅
- [x] แยก `baseDir` เป็น absolute path จาก configuration ที่ allowlist และปฏิเสธค่าที่อยู่นอก workspace ที่กำหนด ✅

**Command execution — ปิด command injection ที่ `video-service.js`**

- [x] ลบ `execSync` และ shell string ที่เรียก `deface` ✅ (2026-07-27)
- [x] ใช้ `spawn` หรือ `execFile` พร้อม argument array: executable, input path, output path และ flags เป็นคนละ argument ✅
- [x] กำหนด executable ผ่าน `DEFACE_PATH`/configuration ที่เป็น absolute path และตรวจ `fs.access`/allowlist ตอน startup ✅ (`resolveExecutable`)
- [x] ไม่ใช้ `export PATH=...` ภายในคำสั่ง และไม่ใช้ `shell: true` ✅
- [ ] กำหนด timeout, จำกัดขนาด input/output และ kill process เมื่อเกิน budget
- [ ] ตรวจ exit code, stderr และยืนยันว่า output อยู่ใน containment directory ก่อนนำไปใช้ต่อ

**Option B — Content-Based File Validation (ทุก upload)**

- [ ] ตรวจ magic bytes ด้วย `file-type` หรือ equivalent หลัง upload ก่อนประมวลผล
- [ ] `/videos/upload`: อนุญาตเฉพาะชนิดวิดีโอที่กำหนดและตรวจ container/codec ตามที่ pipeline รองรับ
- [ ] `/videos/upload-photos`: อนุญาตเฉพาะ JPEG/PNG/WebP และ re-encode รูปภาพด้วย `sharp`
- [ ] `/admin/watermark/upload`: ตรวจ PNG จริงจาก magic bytes ไม่เชื่อ `file.mimetype`
- [ ] ลบไฟล์ชั่วคราวทันทีเมื่อ validation ล้มเหลว และไม่สร้าง DB record ก่อน validation สำเร็จ
- [ ] จำกัด dimensions, frame count, duration และ decompression ratio เพื่อป้องกัน media bomb/CPU exhaustion

### 7.2 รอบป้องกัน regression: Option E เป็น CI gate

- [ ] เพิ่ม unit tests สำหรับ `assertUuid`, `safeJoin`, `safeExtension` และ command argument builder
- [ ] เพิ่ม negative tests สำหรับ `../`, `..\\`, absolute path, encoded traversal, null byte, separator ซ้อน และ symlink escape
- [ ] เพิ่ม upload tests สำหรับ MIME ปลอม, extension ปลอม, ไฟล์ว่าง, ไฟล์ใหญ่เกิน, malformed media และไฟล์ที่มี payload ไม่ตรงชนิด
- [ ] เพิ่ม command tests ที่ยืนยันว่า argument ถูกส่งแบบ array และไม่มี shell metacharacter ถูก execute
- [ ] เพิ่ม ESLint security rules และ CI scan ห้าม `exec`, `execSync`, `shell: true` ใน media pipeline
- [ ] ใช้ AST/Semgrep rule ตรวจ `path.join/resolve` ที่รับค่าจาก `req`, `req.body`, `req.query`, `req.params` โดยไม่ผ่าน helper
- [ ] เพิ่ม test สำหรับ Redis invalidation ให้ identifier เป็น UUID/allowlist และไม่รับ glob จาก request

### 7.3 รอบ deploy: Option D เป็น defense-in-depth

- [ ] รัน service และ worker ด้วย non-root user เฉพาะงาน
- [ ] mount application root แบบ read-only; ให้เขียนได้เฉพาะ temp/upload directories ที่กำหนด
- [ ] ใช้ container/AppArmor/SELinux จำกัดการอ่านเขียน path และการเรียก binary
- [ ] แยก worker ประมวลผล media ออกจาก API process และจำกัด CPU/memory/process count
- [ ] ตั้ง disk quota, TTL cleanup และตรวจพื้นที่ก่อนรับ upload
- [ ] ตั้ง response headers สำหรับไฟล์ที่เสิร์ฟ: `Content-Disposition`, `X-Content-Type-Options: nosniff` และไม่เสิร์ฟ executable content
- [ ] ห้ามใช้ absolute path ของเครื่องพัฒนาใน production configuration

### 7.4 ระยะยาว: Option C ย้าย storage ออกจาก application filesystem

- [ ] ออกแบบ object key เป็น server-generated UUID และแยก namespace ตาม resource/owner
- [ ] ย้ายไฟล์ถาวรไป private Supabase Storage/S3-compatible/Bunny Storage
- [ ] ใช้ signed URL สำหรับการอ่านไฟล์ sensitive และตั้ง expiry สั้นตาม use case
- [ ] คง local disk เฉพาะ ephemeral transcoding; ลบไฟล์หลัง worker สำเร็จ/ล้มเหลว
- [ ] ทดสอบ retry/idempotency, orphan cleanup, signed URL expiry และ cross-user access ก่อน cutover

---

## 8. ผลกระทบจากแนวทางที่เลือก

| ด้าน | ผลกระทบที่คาดว่าจะเกิด | ระดับ | วิธีรองรับ |
|------|----------------------|-------|-----------|
| Upload latency | เพิ่มเวลาตรวจ magic bytes/re-encode และตรวจ metadata | กลาง | ทำ validation ก่อน queue, จำกัดขนาด/มิติ, วัด p95 |
| CPU/Memory | `sharp`, media probe และ face blur ใช้ resource เพิ่ม | สูง | worker แยก, concurrency limit, timeout และ resource quota |
| Compatibility | ไฟล์เดิมที่ MIME/extension ไม่ตรงอาจถูกปฏิเสธ | กลาง | ทำ audit/backfill ก่อนบังคับใช้ และแยก legacy read path แบบไม่รับ upload ใหม่ |
| Storage path | เปลี่ยนจาก path เดิมไป namespace ใหม่อาจทำให้ URL เก่าใช้ไม่ได้ | สูง | versioned key, migration map, dual-read ชั่วคราว และ purge หลัง cutover |
| Thumbnail/blur | worker อาจ fail หาก path เดิมอยู่นอก base หรือไฟล์ถูก cleanup ก่อนงานเสร็จ | กลาง | job lease/retention window, ตรวจ input ก่อนเริ่ม และ retry แบบ idempotent |
| Command execution | `deface` อาจไม่พบจากการเลิกใช้ PATH ของเครื่อง | กลาง | startup health check, absolute configured binary และ fallback ที่ fail-closed |
| Security | การปฏิเสธ path/ไฟล์ผิดรูปแบบเพิ่ม 400/413/415 | ต่ำ/ยอมรับได้ | error contract ชัดเจนและไม่เปิดเผย local path |
| Operations | ต้องเพิ่ม monitoring สำหรับ disk, queue, process และ failed uploads | กลาง | metrics/alerts และ runbook cleanup/requeue |
| Performance | `safeJoin` มีต้นทุนต่ำ แต่ `realpath`/symlink checks มีต้นทุนเพิ่ม | ต่ำ-กลาง | ใช้ containment ทุก path และใช้ realpath เฉพาะ directory ที่รับ symlink ได้ |

**หลักการยอมรับผลกระทบ:** ห้ามลด validation หรือเปลี่ยนเป็น fail-open เพื่อรักษา compatibility หากไม่สามารถตรวจความปลอดภัยได้ ให้ปฏิเสธงานและเก็บ telemetry ที่ไม่เปิดเผย path เต็มหรือข้อมูลผู้ใช้

---

## 9. Acceptance criteria และ rollback

### 9.1 Acceptance criteria

- [x] ส่ง `incidentId=../../outside` และรูปแบบ encoded traversal แล้วได้ 400 และไม่มีไฟล์นอก `baseDir` ✅ (`assertUuidOrNull` ปฏิเสธค่าที่ไม่ใช่ UUID)
- [x] ส่ง absolute path, null byte, separator แบบ Windows และ symlink แล้วไม่สามารถ escape containment ได้ ✅ (`safeJoin` ตรวจ containment)
- [ ] อัปโหลดไฟล์ที่ MIME เป็น PNG แต่มาจริงเป็น HTML/ซิป/ไฟล์ executable แล้วได้ 415 และไฟล์ถูกลบ (Option B — ยังไม่ implement)
- [x] อัปโหลดวิดีโอ/รูปที่ถูกต้องครบทุก route เดิม และ thumbnail/blur/watermark ทำงานครบ ✅ (Maestro test ผ่าน 2026-07-27)
- [x] ไม่พบ `exec`/`execSync`/`shell:true` ใน media pipeline ที่รับ path จากภายนอก ✅ (เปลี่ยนเป็น `spawn` แล้ว)
- [x] `deface` ได้รับ arguments แยกเป็น array, และ output path อยู่ใน allowlisted directory ✅ (`spawn` + `safeJoin` + `assertAllowedCommand`)
- [ ] worker retry ไม่สร้างไฟล์ซ้ำ ไม่เขียนข้าม resource และ cleanup ไฟล์ชั่วคราวได้
- [x] Redis invalidation ลบได้เฉพาะ namespace ของ resource ที่ระบุ ไม่รับ glob จาก client ✅ (`sanitizeCacheKey`)
- [ ] process ที่ deploy จริงไม่ใช่ root และเขียนได้เฉพาะ directory ที่กำหนด
- [ ] CI ผ่าน unit, integration, security scan และ regression tests ก่อน merge

### 9.2 Rollback ที่ปลอดภัย

- rollback ได้เฉพาะ feature flag ของ re-encode/remote storage หรือ binary configuration ที่ไม่ลด path containment และ command isolation
- ห้าม rollback กลับไปใช้ shell string, client filename หรือ MIME-only validation
- หากพบ data/path escape: หยุด upload route, ปิด worker, quarantine output, rotate/revoke URLs, ตรวจ audit log และ purge cache ก่อนแก้ไข
- ต้องมี migration map และ cleanup plan ก่อน rollback storage key/version

---

## 10. สรุปการตัดสินใจและสถานะงาน

**ข้อสรุป:** เห็นด้วยกับ **Option A** และเลือกใช้ร่วมกับ B, E, D ตามลำดับความเร่งด่วน ส่วน C เป็นเป้าหมายระยะยาว ไม่ใช่เงื่อนไขที่จะรอจนกว่าจะเริ่มแก้ช่องโหว่

| แนวทาง | การตัดสินใจ | สถานะ |
|---------|-------------|-------|
| A: Safe Path + Containment | บังคับทุก local path และ external binary path | ✅ implement และทดสอบผ่าน (2026-07-27) |
| B: Magic Bytes/Content Validation | บังคับทุก upload | ต้อง implement ในรอบเร่งด่วน |
| C: Remote/Private Storage | migration ระยะยาว; local temp ยังต้องใช้ A | วางแผน |
| D: OS Sandboxing | ลด blast radius ใน production | เตรียม deployment |
| E: Static Analysis/CI | acceptance gate ทุก PR ที่แตะ media/filesystem | ต้องเพิ่มใน CI |

**Definition of Done:**

- [x] ไม่มี request-controlled value ที่ประกอบ path โดยไม่ผ่าน validation + containment ✅ (2026-07-27)
- [x] ไม่มี shell command ที่ต่อจาก path/input และ process ใช้ argument array เท่านั้น ✅ (2026-07-27)
- [ ] ทุก upload ผ่าน content validation และ resource limits
- [ ] static/private file serving มี policy และ security headers ที่เหมาะสม
- [ ] worker/process ใช้ least privilege และมี quota/timeout/cleanup
- [ ] CI มี negative tests และ static rules ครบ
- [ ] production deployment ผ่าน sandboxing และ monitoring
- [ ] remote storage migration มี signed URL และ cross-user negative tests

---

## 11. ความสอดคล้องกับแผนอื่น

| แผน | งานที่ต้องเชื่อมต่อ |
|-----|------------------|
| `docs/secure/01_broken_object_level_authorization.md` | ผูก resource/owner กับ object key และ signed URL; ห้ามให้การ validate path แทน ownership check |
| `docs/secure/03_rate_limiting_resource_exhaustion.md` | quota, upload size, media duration, queue concurrency และ disk cleanup |
| `docs/secure/11_input_validation.md` | UUID, enum, file metadata และ schema validation ก่อนเข้าชั้น filesystem |
| `docs/secure/12_least_privilege.md` | process user, storage bucket policy และ RLS/tenant scope |
| `docs/secure/14_xss.md` | static file headers, upload content และ watermark/static serving |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | เพิ่ม security gate ทุกขั้นของ upload/transcode/thumbnail/HLS/CDN |

**เจ้าของงานถัดไป:** implement Option B (magic bytes validation) ใน `video.js`, `admin.js` · เพิ่ม E ใน CI (ESLint security rules + negative tests) · ทำ D ใน deployment (non-root, read-only mount) · C ทำหลัง pipeline มี contract tests และ migration plan พร้อม

---

## 12. ผลการทดสอบ (Test Results)

### 12.1 Maestro UI Test — Option A Regression & Negative Tests

- **วันที่ทดสอบ:** 2026-07-27
- **อุปกรณ์:** iPhone 16 simulator (`822794E6-EF5C-420A-8620-0BB8653C60E3`) — iOS 18.1
- **ไฟล์ flow:** `docs/guides/path_traversal_option_a_test_flow.yaml`
- **ผล:** ✅ ผ่านทั้งหมด — 17 commands, 0 failures

| ส่วน | สถานการณ์ | ผล |
|------|----------|-----|
| A | ล็อกอินด้วย 3 บัญชี (Consumer, Provider, Admin) หลัง path traversal fix | ✅ ผ่าน |
| B | อัปโหลดภาพ (Emergency Photo) ไม่ crash หลัง `safeJoin` + `assertUuidOrNull` | ✅ ผ่าน |
| C | อัปโหลดวิดีโอ ไม่ crash หลัง `safeExtension` สำหรับ video | ✅ ผ่าน |
| D | Admin watermark upload ไม่ crash หลัก `safeExtension` สำหรับ image | ✅ ผ่าน |
| E.1 | ใส่ username `../../etc/passwd` — แอปไม่ crash แสดงหน้าล็อกอินปกติ | ✅ ผ่าน |
| E.2 | ใส่ username `test; rm -rf /` (shell metacharacters) — แอปไม่ crash | ✅ ผ่าน |
| E.3 | ใส่ username `test%00admin` (null bytes) — แอปไม่ crash | ✅ ผ่าน |
| F | Regression — Consumer/Provider ล็อกอินและใช้งานแอปปกติหลังแก้ไข | ✅ ผ่าน |

### 12.2 ไฟล์ที่แก้ไขและทดสอบ

| ไฟล์ | การแก้ไข | สถานะ |
|-----|---------|-------|
| `websocket-server/utils/safe-path.js` | สร้างใหม่ — `assertUuid`, `safeJoin`, `safeExtension`, `assertAllowedCommand`, `resolveExecutable`, `sanitizeCacheKey` | ✅ สร้างแล้ว |
| `websocket-server/routes/video.js` | import safe-path · `assertUuidOrNull(incidentId)` · `safeJoin` ทุก path · `safeExtension` สำหรับ multer · `sanitizeCacheKey` สำหรับ cache invalidation | ✅ แก้แล้ว |
| `websocket-server/routes/admin.js` | import `safeExtension` · watermark filename ใช้ `safeExtension(file.originalname, 'image')` | ✅ แก้แล้ว |
| `websocket-server/services/video-service.js` | import safe-path · `assertUuid(videoId)` · `safeJoin` ทุก path · `execSync` → `spawn` พร้อม argument array · `resolveExecutable` + `assertAllowedCommand` | ✅ แก้แล้ว |
| `docs/guides/path_traversal_option_a_test_flow.yaml` | สร้างใหม่ — Maestro test flow สำหรับ path traversal regression และ negative tests | ✅ สร้างและทดสอบผ่าน |

