# แผนป้องกัน 14: Cross-Site Scripting (XSS)

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P1 (เร่งก่อนเปิดใช้ web ERP/admin)
> **เกี่ยวข้องกับแผน:** 11 (Input Validation), 15 (CSRF)
> **ผลทบทวน 2026-07-27:** จัดอยู่ใน **Phase S1 ลำดับ 2** โดยให้ทำ static upload isolation, URL scheme allowlist และ rich-text sanitization ก่อนเปิดใช้ web ERP/admin
> **เหตุผล:** Flutter mobile ไม่ได้ execute HTML เป็น DOM แต่ stored data อาจถูกนำไปใช้โดย web dashboard, WebView, export หรือ email จึงไม่ควรละเลย และไม่ควรใช้มาตรการ web-heavy เป็น P0 ก่อนมี web attack surface จริง

---

## 1. สถานะปัจจุบัน (As-Is)

### บริบทสำคัญ: Flutter ลดความเสี่ยง XSS ลงมาก

Flutter วาด UI ด้วย Skia/Impeller canvas ไม่ใช่ DOM — `Text('<script>...')` จะแสดงเป็นข้อความธรรมดา ไม่ execute
ดังนั้น **XSS ไม่ใช่ความเสี่ยงหลักของ mobile app** แต่ยังมีจุดเสี่ยงที่ต้องดูแล

### จุดเสี่ยงที่มีจริงในระบบ

| # | จุดเสี่ยง | ระดับ | คำอธิบาย |
|---|----------|-------|----------|
| X1 | **Flutter Web target** | 🟡 กลาง | ถ้า build เป็น web (โดยเฉพาะ ERP Dashboard) จะรันบน DOM จริง; `HtmlElementView`, `dart:html` มีความเสี่ยง |
| X2 | **WebView / `model_viewer_plus`** | 🟡 กลาง | `model_viewer_plus` ใช้ WebView ภายใน — ถ้า URL/content มาจาก user input ต้องระวัง |
| X3 | **Rich text บทความสุขภาพ** | 🟡 กลาง | `HealthArticlePage` — ถ้าเก็บ/แสดง HTML ต้อง sanitize |
| X4 | **`url_launcher` กับ URL จากผู้ใช้** | 🟡 กลาง | `javascript:` scheme หรือ deep link ที่ไม่คาดคิด |
| X5 | **Admin panel ในอนาคต (web)** | 🔴 สูง | แผน ERP Dashboard บน web จะแสดงข้อมูลที่ผู้ใช้กรอก — stored XSS ที่ admin panel = ยึด admin session ได้ |
| X6 | **Stored payload ใน DB** | 🟡 กลาง | ข้อมูลที่ปลอดภัยใน Flutter อาจอันตรายเมื่อถูก consume โดย client อื่น (web dashboard, export HTML, email) |
| X7 | **ไม่มี CSP header** | 🟡 กลาง | `websocket-server` ไม่ตั้ง Content-Security-Policy |
| X8 | **Static file serving** | 🟡 กลาง | `/uploads/watermarks/` เสิร์ฟไฟล์ที่อัปโหลด — ถ้าอัปโหลด HTML/SVG ได้จะรันในโดเมนเดียวกัน |
| X9 | **SVG upload** | 🟡 กลาง | SVG สามารถฝัง `<script>` ได้; `flutter_svg` ปลอดภัยแต่ถ้าเสิร์ฟผ่าน browser จะรัน |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 ระบบที่ implement แล้ว

| ระบบ | เนื้อหาจากผู้ใช้ | ความเสี่ยงบน Flutter | ความเสี่ยงถ้าเป็น Web |
|------|-----------------|---------------------|---------------------|
| Auth & Registration | ชื่อ, username, bio | 🟢 | 🟡 แสดงในรายชื่อ/admin |
| Consultation & ChartBoard | ข้อความ, note, prescription instruction | 🟢 | 🔴 ERP clinical view |
| Chat & Video | ข้อความ, caption, ชื่อไฟล์ | 🟢 | 🟡 |
| Pharmacy & Drug Risk | override reason, drug note | 🟢 | 🟡 |
| Donation | คำอธิบายคำขอ, ชื่อผู้รับ | 🟢 | 🔴 admin approval page |
| Emergency | incident description | 🟢 | 🟡 dispatcher console |
| Health & Articles | **บทความ (อาจเป็น HTML)** | 🟡 ขึ้นกับ renderer | 🔴 |
| Profile | display name, สถานะ | 🟢 | 🟡 |
| Admin & KPI | config, watermark text | 🟢 | 🔴 |
| Community | โพสต์, คอมเมนต์ | 🟢 | 🔴 |

### 2.2 ระบบตามแผน — จุดที่ต้องออกแบบล่วงหน้า

| แผน | ประเด็น |
|-----|---------|
| `docs/ERP/ERP_DASHBOARD_UI_PLAN.md` | 🔴 ถ้า ERP Dashboard เป็น web → ทุก field ที่ผู้ใช้กรอกต้อง escape; ต้องมี CSP |
| `docs/ERP/ERP_SIDEBAR_NAV_WIREFRAME.md` | Menu label จาก config ผู้ใช้ |
| `docs/ERP/CRM_SYSTEM_PLAN.md` | Customer note, email template — email HTML คือช่องทาง XSS คลาสสิก |
| `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` | Report export เป็น HTML/PDF |
| `docs/ERP/PROCUREMENT_SYSTEM_PLAN.md` | `ProcurementReportPage` export |
| `docs/ERP/HIS_SYSTEM_PLAN.md` | Clinical note ที่อาจใช้ rich text |
| `docs/ERP/KPI_DASHBOARD_PLAN.md` | Chart label/tooltip จาก data |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | Video title/description ใน web player page |
| `docs/plans/Delivery_PLAN.md` | Tracking page ถ้าเปิดเป็น public web link |
| `docs/plans/SHOPPING_CART_PLAN.md` | Product description จาก supplier |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Output Encoding + Sanitization Library (แนะนำ) ⭐

**ฝั่งที่แสดงผลเป็น HTML (web/email/export):**
```js
// Backend — sanitize ตอนแสดงผล ไม่ใช่ตอนบันทึก
const createDOMPurify = require('dompurify');
const { JSDOM } = require('jsdom');
const DOMPurify = createDOMPurify(new JSDOM('').window);

const safe = DOMPurify.sanitize(userContent, {
  ALLOWED_TAGS: ['p','br','strong','em','ul','ol','li','a','h2','h3'],
  ALLOWED_ATTR: ['href'],
  ALLOWED_URI_REGEXP: /^https?:\/\//,
});
```

**ฝั่ง Flutter (สำหรับ rich text):**
- ใช้ `flutter_html` พร้อมกำหนด allowlist tag
- หรือแปลง HTML → Markdown → render ด้วย widget ที่ปลอดภัย

**หลักการ:** เก็บ raw ใน DB, sanitize ตอน render ตาม context (HTML / plain text / JSON / URL)

**ข้อดี**
- ปลอดภัยตาม context ที่ถูกต้อง
- ข้อมูลต้นฉบับไม่เสียหาย, เปลี่ยนกฎ sanitize ภายหลังได้
- ปิด X3, X5, X6

**ข้อเสีย**
- ต้องระวังทุกจุดที่ render — ลืมจุดเดียวก็พลาด
- เพิ่ม dependency

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Sanitize ตอนบันทึก (Input Sanitization)

Strip HTML tag ทั้งหมดก่อนบันทึกลง DB

**ข้อดี:** ทำที่เดียว (validation layer แผน 11); DB สะอาดแน่นอน; client ทุกตัวปลอดภัยอัตโนมัติ
**ข้อเสีย:** ข้อมูลต้นฉบับสูญหายถาวร; แก้กฎย้อนหลังไม่ได้; ผู้ใช้พิมพ์ `<3` หรือสูตรเคมี `H2O <br` แล้วโดนตัด
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — เหมาะกับ field ที่ควรเป็น plain text อยู่แล้ว (ชื่อ, username, title)

---

### ตัวเลือก C: Content Security Policy + Security Headers

```js
// websocket-server/server.js
const helmet = require('helmet');
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:', 'https:'],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"],
    },
  },
  crossOriginResourcePolicy: { policy: 'same-site' },
}));

// เสิร์ฟไฟล์อัปโหลดแบบบังคับดาวน์โหลด — ปิด X8/X9
app.use('/uploads', express.static(uploadDir, {
  setHeaders: (res) => {
    res.setHeader('Content-Disposition', 'attachment');
    res.setHeader('X-Content-Type-Options', 'nosniff');
  },
}));
```

**ข้อดี:** ป้องกันชั้นเบราว์เซอร์แม้มี XSS หลุด; ทำได้เร็ว (1–2 วัน); ปิด X7, X8, X9
**ข้อเสีย:** ใช้ได้เฉพาะ browser context; ต้องปรับ policy ให้ไม่พังฟีเจอร์
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **ต้นทุนต่ำมาก ควรทำแน่นอน**

---

### ตัวเลือก D: แยก Domain สำหรับ User Content

เสิร์ฟไฟล์อัปโหลดจาก domain แยก (เช่น `usercontent.sheserved.com`) หรือใช้ Supabase Storage

**ข้อดี:** แม้มีสคริปต์ก็อยู่คนละ origin เข้าถึง session ของ app ไม่ได้; เป็นวิธีที่แพลตฟอร์มใหญ่ใช้
**ข้อเสีย:** ต้องมี domain/subdomain เพิ่ม + CORS config; กระทบ `reverse_proxy_plan.md`
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐ — คุ้มค่าถ้ามี user upload จำนวนมาก (ซึ่ง Sheserved มี: video, image, voice, เอกสาร)

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **C ทันที → B สำหรับ plain-text field → A ก่อนเปิด ERP web → D เมื่อ scale** | ต้นทุนต่ำก่อน แล้วขยายตามความจำเป็นจริง |
| 2 | **C + D** | ถ้าเน้นป้องกันเชิงโครงสร้างมากกว่าเชิงโค้ด |
| 3 | **A + B + C ครบชุด** | ถ้า ERP web เป็นแผนระยะสั้นและมีผู้ใช้ภายนอก |
| 4 | **ไม่ทำอะไร** | ยอมรับได้เฉพาะกรณี mobile-only ตลอดไป — แต่ ERP Dashboard บน web ขัดกับสมมติฐานนี้ |

---

## 5. กฎการ Render ที่เสนอ (Sheserved Output Standard)

| Context | วิธีที่ต้องใช้ |
|---------|--------------|
| Flutter `Text` widget | ✅ ปลอดภัยโดยธรรมชาติ |
| Flutter rich text | `flutter_html` + allowlist tag เท่านั้น |
| Flutter WebView / model_viewer | โหลดเฉพาะ URL จาก allowlist domain |
| `url_launcher` | ตรวจ scheme ต้องเป็น `https`/`tel`/`mailto` เท่านั้น — **ปฏิเสธ `javascript:`, `data:`, `file:`** |
| HTML response (web) | escape ทุกตัวแปร; ถ้าเป็น rich text → DOMPurify |
| Email template | sanitize + inline CSS เท่านั้น, ห้าม script |
| PDF/Excel export | escape formula injection ด้วย (`=`, `+`, `-`, `@` ขึ้นต้น cell → prefix `'`) |
| JSON API response | `Content-Type: application/json` + `X-Content-Type-Options: nosniff` |
| ไฟล์อัปโหลด | `Content-Disposition: attachment` + `nosniff` + domain แยก (ถ้าทำ D) |
| SVG | แปลงเป็น PNG ฝั่ง server หรือ sanitize ด้วย DOMPurify profile SVG |

> **หมายเหตุ CSV/Excel Formula Injection:** ระบบมี `csv: ^6.0.0` และแผน export หลายจุด (ERP report, KPI) — จุดนี้ควรอยู่ในขอบเขตแผนนี้ด้วย

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/infrastructure/reverse_proxy_plan.md` | ตัวเลือก C/D ต้องกำหนด header + subdomain ที่ proxy layer |
| `docs/plans/ui_rendering_standards.md` | ต้องเพิ่มกฎการ render user content เข้าไปในมาตรฐานนั้น |
| `docs/ERP/ERP_DASHBOARD_UI_PLAN.md` | ถ้าเป็น web target ต้องระบุ CSP + escaping ในแผนนั้น |
| `docs/ERP/ERP_GLASSMORPHISM_PLAN.md` | `unsafe-inline` style อาจจำเป็น — ต้องปรับ CSP ให้รองรับ |
| `docs/guides/TEST_PLAN.md` | ควรเพิ่ม SEC-07: XSS payload ใน field ต่าง ๆ → ต้องแสดงเป็นข้อความ |

---

## 7. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] ยืนยันว่า ERP Dashboard จะ deploy เป็น **web** หรือ mobile เท่านั้น (ตัวแปรสำคัญที่สุด)
- [ ] อนุมัติการเพิ่ม `helmet` + CSP (แนะนำ: ใช่)
- [ ] ตัดสินใจว่าบทความสุขภาพเก็บเป็น HTML / Markdown / plain text
- [ ] ตัดสินใจเรื่อง domain แยกสำหรับ user upload
- [ ] อนุมัติกฎ `url_launcher` scheme allowlist
- [ ] ตัดสินใจเรื่อง CSV formula injection prevention ใน export
