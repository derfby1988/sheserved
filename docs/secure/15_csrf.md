# แผนป้องกัน 15: CSRF (Cross-Site Request Forgery)

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P2
> **เกี่ยวข้องกับแผน:** 09 (AuthN/AuthZ), 14 (XSS), 08 (Session/Token)
> **ผลทบทวน 2026-07-27:** คงเป็น **Phase S1 ลำดับ 3 แบบ trigger-based**; ปัจจุบัน bearer/custom header ไม่ถูกแนบอัตโนมัติแบบ cookie จึงมีความเสี่ยง CSRF ต่ำกว่า BOLA และ identity spoofing
> **เหตุผล:** ต้องยกระดับเป็น P0 ทันทีเมื่อมี browser cookie/session, `credentials: include` หรือ endpoint ที่รับ state-changing request จาก browser; ก่อนถึงจุดนั้นให้ปิด CORS wildcard ในแผน 04 และบันทึก decision ไม่ทำ CSRF token ซ้ำซ้อน

---

## 1. สถานะปัจจุบัน (As-Is)

### บริบทสำคัญ: ระดับความเสี่ยงขึ้นกับวิธีส่ง credential

CSRF เกิดได้เมื่อเบราว์เซอร์แนบ credential **อัตโนมัติ** (cookie, HTTP Basic) ไปกับ cross-origin request

| วิธีส่ง identity | เสี่ยง CSRF? |
|-----------------|-------------|
| Cookie (`SameSite=None`) | 🔴 ใช่ |
| Cookie (`SameSite=Lax/Strict`) | 🟡 ลดลงมาก |
| `Authorization: Bearer` header | 🟢 ไม่ (ต้องเขียน JS แนบเอง) |
| Custom header (`x-user-id`) | 🟢 ไม่ (trigger CORS preflight) |

**สถานะ Sheserved ปัจจุบัน:** ใช้ `x-user-id` custom header + ไม่มี cookie session → **ความเสี่ยง CSRF ต่ำโดยธรรมชาติ**

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| C1 | **CORS ตั้งเป็น `*` ได้** | 🟡 กลาง | `ALLOWED_ORIGINS` default = `'*'` พร้อม `credentials: true` — โค้ดมี warning แล้วแต่ยังอนุญาต |
| C2 | **ไม่มี CSRF token** | 🟢 ต่ำ (ตอนนี้) | จะกลายเป็น 🔴 ทันทีถ้าเปลี่ยนไปใช้ cookie session |
| C3 | **`credentials: true` กับ origin แบบยืดหยุ่น** | 🟡 กลาง | ถ้ามี cookie ในอนาคตจะเปิดช่องทันที |
| C4 | **ไม่มี Origin/Referer validation** | 🟡 กลาง | ไม่มีการตรวจ header เหล่านี้ในชั้น middleware |
| C5 | **Socket.IO CORS ใช้ config เดียวกัน** | 🟡 กลาง | WebSocket ไม่มี same-origin policy — ต้อง verify origin เอง |
| C6 | **Deep link / custom URL scheme** | 🟡 กลาง | Mobile equivalent ของ CSRF — เว็บใด ๆ เปิด `sheserved://` ทำ action ได้ |
| C7 | **แผน ERP web dashboard** | 🔴 สูง (อนาคต) | ถ้าใช้ cookie session ตามแบบ web app ปกติ จะเสี่ยงเต็มรูปแบบ |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 Endpoint ที่มีผลกระทบสูงถ้าถูก CSRF

| ระบบ | Action ที่เสี่ยง | ผลกระทบ |
|------|-----------------|---------|
| **Donation + Escrow** | release escrow, approve donation, transfer เงิน | 🔴 การเงินเสียหาย |
| **Admin** | update watermark, platform settings, user role change | 🔴 ยึดระบบ |
| **Profile** | เปลี่ยนเบอร์/อีเมล/รหัสผ่าน | 🔴 account takeover |
| **Auth** | logout (nuisance), เปลี่ยนรหัส | 🟡–🔴 |
| **Consultation** | finish consultation, ส่งใบสั่งยา | 🔴 ผลทางการแพทย์ |
| **Pharmacy** | set/remove drug risk override | 🔴 ความปลอดภัยผู้ป่วย |
| **Emergency** | trigger SOS ปลอม | 🟡 ทรัพยากรถูกใช้ผิด |
| **Video** | upload, delete | 🟡 |

### 2.2 ระบบตามแผน `docs/ERP/`

| แผน | Action ที่ต้องป้องกัน |
|-----|---------------------|
| `ACCOUNTING_SYSTEM_PLAN.md` | 🔴 GL posting, journal entry, period close |
| `POS System_plan.md` | 🔴 refund, void transaction, cash drawer |
| `PROCUREMENT_SYSTEM_PLAN.md` | 🔴 PO approval, supplier payment |
| `HR_SYSTEM_PLAN.md` | 🔴 payroll run, role assignment, permission change |
| `INVENTORY_SYSTEM_PLAN.md` | 🟡 stock adjustment, transfer |
| `ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | 🔴 tier change, billing |
| `HIS_SYSTEM_PLAN.md` / `LAB_SYSTEM_PLAN.md` | 🔴 order entry, result approval |
| `CRM_SYSTEM_PLAN.md` | 🟡 bulk email, data export |

### 2.3 ระบบตามแผน `docs/plans/`

| แผน | ประเด็น |
|-----|---------|
| `Delivery_PLAN.md` | Tracking page แบบ public link — ถ้ามี action (confirm delivery) ต้องมี token |
| `SHOPPING_CART_PLAN.md` | Checkout, apply coupon |
| `DONATION_SYSTEM_PLAN.md` | ทุก action การเงิน |
| `VIDEO_SYSTEM_PLAN.md` | Admin watermark config |

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: คงสถาปัตยกรรม Token-in-Header (แนะนำ) ⭐

**หลักการ:** ไม่ใช้ cookie สำหรับ authentication เลย ใช้ `Authorization: Bearer <jwt>` เท่านั้น (สอดคล้องกับแผน 09 ตัวเลือก A และแผน 08)

```
Mobile:  เก็บ token ใน secure storage → แนบ header เอง
Web:     เก็บ access token ใน memory (ไม่ใช่ localStorage/cookie)
         refresh token ใน httpOnly cookie + SameSite=Strict (+ CSRF token สำหรับ /refresh)
```

**ข้อดี**
- CSRF ไม่เกิดขึ้นเลยโดยธรรมชาติของสถาปัตยกรรม
- ไม่ต้องดูแล CSRF token ทุก endpoint
- สอดคล้องกับ mobile-first ของ Sheserved

**ข้อเสีย**
- Web: token ใน memory หายเมื่อ refresh หน้า → ต้องมี refresh flow
- refresh endpoint ยังต้องป้องกัน CSRF แยก

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: CORS Allowlist เข้มงวด + Origin Validation

```js
// บังคับให้ต้องตั้งค่า ALLOWED_ORIGINS ใน production
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean);
if (process.env.NODE_ENV === 'production' && allowedOrigins.length === 0) {
  throw new Error('ALLOWED_ORIGINS must be set in production');
}

const corsOptions = {
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);            // mobile app / server-to-server
    if (allowedOrigins.includes(origin)) return cb(null, true);
    cb(new Error('CORS blocked'));
  },
  credentials: true,
};

// เพิ่ม Origin validation middleware สำหรับ state-changing methods
function validateOrigin(req, res, next) {
  if (['POST','PUT','PATCH','DELETE'].includes(req.method)) {
    const origin = req.headers.origin || req.headers.referer;
    if (origin && !allowedOrigins.some(o => origin.startsWith(o))) {
      return res.status(403).json({ error: 'Invalid origin' });
    }
  }
  next();
}
```

**ข้อดี:** ปิด C1, C3, C4, C5; ทำได้เร็ว (1 วัน); ไม่กระทบ mobile app
**ข้อเสีย:** Origin header ปลอมได้จาก non-browser client (แต่ non-browser ไม่ใช่ CSRF vector)
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **ควรทำแน่นอน ต้นทุนต่ำ**

---

### ตัวเลือก C: Double Submit Cookie / Synchronizer Token

```js
const csrf = require('csurf');
app.use(csrf({ cookie: { httpOnly: true, sameSite: 'strict', secure: true } }));
```

**ข้อดี:** มาตรฐานคลาสสิก; จำเป็นถ้าเลือกใช้ cookie session
**ข้อเสีย:** เพิ่มความซับซ้อนโดยไม่จำเป็นถ้าเลือกตัวเลือก A; `csurf` deprecated แล้ว (ต้องใช้ `csrf-csrf` แทน)
**ความเหมาะสมระยะยาว:** ⭐⭐⭐ — **เฉพาะกรณีตัดสินใจใช้ cookie session สำหรับ ERP web**

---

### ตัวเลือก D: SameSite Cookie + Custom Header Requirement

ถ้าจำเป็นต้องใช้ cookie: `SameSite=Strict` + บังคับ custom header (`X-Requested-With`) ทุก state-changing request

**ข้อดี:** เบากว่า CSRF token; ป้องกันได้ดีในเบราว์เซอร์สมัยใหม่
**ข้อเสีย:** `SameSite=Strict` ทำให้ลิงก์จากภายนอกเข้ามาแล้วไม่ login (UX แย่); เบราว์เซอร์เก่าไม่รองรับ
**ความเหมาะสมระยะยาว:** ⭐⭐⭐

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **B ทันที + A เป็นสถาปัตยกรรมหลัก** | ปิดช่องว่าง config เร่งด่วนก่อน แล้วยึดหลัก token-in-header ตลอดไป → CSRF หมดปัญหาเชิงโครงสร้าง |
| 2 | **B + A + C เฉพาะ `/auth/refresh`** | ถ้า web ต้องมี refresh token ใน cookie |
| 3 | **B + C ครบทุก endpoint** | ถ้าตัดสินใจว่า ERP web จะใช้ cookie session แบบดั้งเดิม |
| 4 | **ไม่ทำอะไร** | ไม่แนะนำ — อย่างน้อย C1 (CORS `*` + credentials) ควรปิดทันที |

---

## 5. มาตรการเสริมที่เสนอ

### 5.1 Re-authentication สำหรับ Action สำคัญ
บังคับกรอกรหัสผ่าน/OTP ซ้ำก่อนทำ action ที่ผลกระทบสูง — ป้องกันได้ทั้ง CSRF, XSS และ session hijacking

| Action | มาตรการ |
|--------|---------|
| เปลี่ยนรหัสผ่าน | กรอกรหัสเดิม |
| เปลี่ยนเบอร์/อีเมล | OTP |
| Escrow release | OTP หรือ re-auth |
| Payroll run | re-auth + approval คนที่สอง |
| GL period close | re-auth |
| Role/permission change | re-auth |
| POS refund เกินวงเงิน | supervisor PIN |

### 5.2 Deep Link Security (C6 — mobile equivalent)
```
1. ใช้ App Links (Android) / Universal Links (iOS) แทน custom scheme
2. Deep link ทำได้แค่ "นำทาง" ห้ามทำ state-changing action โดยตรง
3. Action ที่มาจาก deep link ต้องมีหน้ายืนยันเสมอ
4. Validate parameter ทุกตัวก่อนใช้ (ร่วมกับแผน 11)
```

### 5.3 Socket.IO Origin Check (C5)
```js
io.use((socket, next) => {
  const origin = socket.handshake.headers.origin;
  if (origin && !allowedOrigins.includes(origin)) {
    return next(new Error('Origin not allowed'));
  }
  next();
});
```

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด — ตัวเลือก A สอดคล้องกับ custom AuthService |
| `docs/infrastructure/reverse_proxy_plan.md` | Origin validation ควรทำที่ proxy layer ด้วย (defense in depth) |
| `docs/infrastructure/architecture_analysis.md` | ต้องระบุว่า authentication ใช้ header ไม่ใช่ cookie เป็น architectural decision |
| `docs/ERP/ERP_DASHBOARD_UI_PLAN.md` | ต้องตัดสินใจ session mechanism ก่อนเริ่มพัฒนา web dashboard |
| `docs/guides/TEST_PLAN.md` | เพิ่ม SEC-08: cross-origin request ต้องถูกปฏิเสธ |

---

## 7. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติการบังคับตั้ง `ALLOWED_ORIGINS` ใน production (แนะนำ: ใช่ — ทำทันที)
- [ ] ยืนยันสถาปัตยกรรม session: **header-based token** (A) หรือ **cookie** (C/D)
- [ ] ตัดสินใจว่า ERP web dashboard จะใช้กลไกเดียวกับ mobile หรือแยก
- [ ] อนุมัติรายการ action ที่ต้อง re-authentication (ตาราง 5.1)
- [ ] ตัดสินใจเรื่อง App Links / Universal Links แทน custom scheme
