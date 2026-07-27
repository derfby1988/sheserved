# แผนป้องกัน 16: Server-Side Request Forgery (SSRF)

> **สถานะ:** 📋 รอการตัดสินใจ — ยังไม่ implement
> **Priority:** P2 ปัจจุบัน → **P0 ทันทีที่เริ่มแผน integration ใด ๆ**
> **เกี่ยวข้องกับแผน:** 11 (Input Validation), 07 (Secrets — cloud metadata), 02 (Injection), 04 (Misconfiguration)
> **ลักษณะพิเศษของแผนนี้:** เป็นแผน **เชิงป้องกันล่วงหน้า** — ระบบปัจจุบันยังมีความเสี่ยงต่ำ แต่แผนอนาคตเกือบทุกแผนจะเพิ่ม outbound request ที่รับ URL/parameter จากภายนอก
> **ผลทบทวน 2026-07-27:** คงเป็น **Phase S1 ลำดับ 4 แบบ trigger-based** แต่ต้องสร้าง safe-http client เป็น gate ก่อน integration ที่รับ URL/redirect/remote resource จาก user หรือ third party
> **เหตุผล:** จุด outbound ปัจจุบันใช้ host จาก environment/literal และยังไม่พบ user-controlled SSRF ที่ exploit ได้ จึงไม่ควรแย่งทรัพยากรจาก P0 แต่ต้องห้ามเพิ่ม integration ใหม่โดยไม่มี timeout, redirect policy, DNS/IP validation และ egress restriction

---

## 1. สถานะปัจจุบัน (As-Is)

### สิ่งที่ทำได้ดีอยู่แล้ว ✅

Outbound request ที่พบทั้งหมดใช้ URL จาก **environment variable** ไม่ใช่จาก user input
```@/Users/apisekpanyakong/ProjectFlutter/sheserved/websocket-server/services/video-service.js:61-83
async function uploadToBunny(outputDir, videoId) {
    const apiKey = process.env.BUNNY_API_KEY;
    const storageZone = process.env.BUNNY_STORAGE_ZONE;
...
        const bunnyUrl = `https://storage.bunnycdn.com/${storageZone}/${videoId}/${file}`;

        try {
            await axios.put(bunnyUrl, fileData, {
```
- Host เป็น literal `storage.bunnycdn.com` ✅
- `storageZone` จาก env ✅
- `videoId` เป็น UUID ที่ระบบสร้างเอง (แต่ยังไม่ validate — ดูแผน 02 PT1)

**สรุป:** ยังไม่พบ SSRF ที่ใช้ประโยชน์ได้ในโค้ดปัจจุบัน แต่โครงสร้างยังไม่มีการป้องกันเชิงระบบ

### ช่องว่างที่ต้องปิด

| # | ช่องว่าง | ระดับ | คำอธิบาย |
|---|---------|-------|----------|
| F1 | **ไม่มี HTTP client กลางที่มีการป้องกัน** | 🟡 กลาง | ใช้ `axios` ตรง — คนต่อไปที่เขียน integration จะไม่มี guardrail |
| F2 | **ไม่มี URL allowlist policy** | 🟡 กลาง | ไม่มีรายการปลายทางที่อนุญาต |
| F3 | **ไม่มีการบล็อก private IP / metadata endpoint** | 🟡 กลาง | `169.254.169.254`, `127.0.0.1`, `10.x`, `192.168.x` |
| F4 | **Redirect ไม่ถูกตรวจสอบ** | 🟡 กลาง | axios ตาม redirect โดย default — allowlist ที่ตรวจแค่ URL แรกจะถูกข้าม |
| F5 | **ไม่มี timeout ใน outbound request** | 🟡 กลาง | `axios.put` ไม่ระบุ timeout → connection ค้าง |
| F6 | **Network segmentation ไม่ชัดเจน** | 🟡 กลาง | app server เข้าถึง Redis/PostgreSQL/internal service ได้โดยตรง |
| F7 | **`LOCAL_API_URL` ถูกใช้สร้าง URL ที่ส่งให้ client** | 🟢 ต่ำ | ถ้า env ถูกแก้ = redirect ผู้ใช้ไปที่อื่น (แผน 07) |
| F8 | **ไม่มี egress filtering** | 🟡 กลาง | server ยิงออกอินเทอร์เน็ตได้ทุกที่ |
| F9 | **`model_viewer_plus` โหลด URL** | 🟡 กลาง | ฝั่ง client แต่หลักการเดียวกัน — ต้อง allowlist |
| F10 | **Webhook (ในอนาคต)** | 🔴 สูง | ถ้ามีฟีเจอร์ "ส่ง webhook ไป URL ที่ผู้ใช้กำหนด" = SSRF โดยการออกแบบ |

---

## 2. การวิเคราะห์รายระบบ

### 2.1 Outbound request ในระบบปัจจุบัน

| ระบบ | ปลายทาง | แหล่งที่มาของ URL | ความเสี่ยง |
|------|---------|------------------|-----------|
| Video upload → CDN | `storage.bunnycdn.com` | literal + env | 🟢 |
| Video URL generation | `BUNNY_CDN_URL` / `LOCAL_API_URL` | env | 🟢 (F7) |
| Thumbnail upload | Bunny | env | 🟢 |
| Supabase (จาก Flutter) | Supabase URL | hardcode/config | 🟢 |
| Social login | Google/Facebook/Apple | SDK | 🟢 |
| Maps | Google Maps API | SDK | 🟢 |
| `cached_network_image` | URL จาก DB | ⚠️ ฝั่ง client — URL ที่ผู้ใช้อื่นใส่ได้ | 🟡 |
| `url_launcher` | URL จากเนื้อหา | ⚠️ ต้อง allowlist scheme (แผน 14) | 🟡 |

### 2.2 ระบบตามแผน — จุดที่จะเกิดความเสี่ยง SSRF

| แผน | ฟีเจอร์ที่จะสร้าง outbound request | ความเสี่ยง |
|-----|-----------------------------------|-----------|
| `docs/ERP/CRM_SYSTEM_PLAN.md` | 🔴 Email/SMS gateway, LINE OA, **webhook ไป CRM ภายนอก**, import ข้อมูลจาก URL | สูงสุด |
| `docs/ERP/ACCOUNTING_SYSTEM_PLAN.md` | 🔴 Bank API, e-Tax (RD), accounting software sync, ดึง statement จาก URL | สูงสุด |
| `docs/ERP/PROCUREMENT_SYSTEM_PLAN.md` | 🔴 Supplier EDI/API, **catalog import จาก URL ที่ supplier ให้มา** | สูง |
| `docs/ERP/POS System_plan.md` | Payment gateway callback, receipt printer (network) | สูง |
| `docs/ERP/HR_SYSTEM_PLAN.md` | Bank transfer file upload, ประกันสังคม API | สูง |
| `docs/ERP/LAB_SYSTEM_PLAN.md` | 🔴 HL7 interface ไปยัง LIS — มักเป็น internal network | สูง |
| `docs/ERP/HIS_SYSTEM_PLAN.md` | สปสช./ประกันสังคม API, HIS integration | สูง |
| `docs/ERP/ERP_SUBSCRIPTION_MANAGEMENT_PLAN.md` | Billing provider webhook | กลาง |
| `docs/ERP/ERP_NOTIFICATION_SYSTEM_PLAN.md` | Push notification service, **webhook ที่ผู้ใช้กำหนด** | 🔴 สูง |
| `docs/plans/Delivery_PLAN.md` | 🔴 Grab/Lalamove API, **tracking callback URL** | สูง |
| `docs/plans/VIDEO_SYSTEM_PLAN.md` | CDN purge API, transcoding service, **import วิดีโอจาก URL** | สูง |
| `docs/plans/SHOPPING_CART_PLAN.md` | **Product image import จาก URL ของ supplier** | 🔴 คลาสสิก |
| `docs/plans/health_data_sync_plan.md` | Apple HealthKit / Google Fit / vendor cloud API | กลาง |

> **ข้อสรุป:** ทุกแผน ERP และ integration จะเพิ่มความเสี่ยง SSRF — **ควรวางกลไกป้องกันไว้ก่อนเริ่มแผนแรก** ถูกกว่าการไล่แก้ทีหลัง

---

## 3. ทางเลือกในการแก้ไข (Options)

### ตัวเลือก A: Safe HTTP Client กลาง (แนะนำ) ⭐

```js
// websocket-server/utils/safe-http.js
const axios = require('axios');
const dns = require('dns').promises;
const net = require('net');
const ipaddr = require('ipaddr.js');

const ALLOWED_HOSTS = new Set(
  (process.env.OUTBOUND_ALLOWED_HOSTS || '').split(',').map(s => s.trim()).filter(Boolean)
);

function isPrivateAddress(ip) {
  const addr = ipaddr.parse(ip);
  const range = addr.range();
  return ['private', 'loopback', 'linkLocal', 'uniqueLocal',
          'reserved', 'unspecified', 'carrierGradeNat'].includes(range);
}

async function assertSafeUrl(rawUrl) {
  let url;
  try { url = new URL(rawUrl); } catch { throw new Error('Invalid URL'); }

  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Protocol not allowed');
  if (url.port && !['', '80', '443'].includes(url.port)) throw new Error('Port not allowed');
  if (!ALLOWED_HOSTS.has(url.hostname)) throw new Error('Host not in allowlist');

  // ป้องกัน DNS rebinding — resolve แล้วตรวจทุก IP
  const records = await dns.lookup(url.hostname, { all: true });
  for (const r of records) {
    if (isPrivateAddress(r.address)) throw new Error('Resolved to private address');
  }
  return { url, addresses: records.map(r => r.address) };
}

const safeHttp = axios.create({
  timeout: 10000,
  maxRedirects: 0,          // ❗ ปิด redirect — ตรวจเองถ้าจำเป็น
  maxContentLength: 10 * 1024 * 1024,
  maxBodyLength: 10 * 1024 * 1024,
});

safeHttp.interceptors.request.use(async (config) => {
  await assertSafeUrl(config.url);
  return config;
});

module.exports = { safeHttp, assertSafeUrl };
```

**ข้อดี**
- ปิด F1–F5 ในที่เดียว
- Integration ในอนาคตได้การป้องกันฟรีถ้าใช้ client นี้
- Allowlist ผ่าน env — เพิ่มปลายทางใหม่ได้โดยไม่แก้โค้ด
- `maxRedirects: 0` ปิด F4 ตั้งแต่ต้น

**ข้อเสีย**
- DNS resolve ก่อนแต่ละ request เพิ่ม latency (แก้ด้วย DNS cache สั้น ๆ)
- ยังมีช่องว่าง TOCTOU ระหว่าง resolve กับ connect (แก้ได้สมบูรณ์ด้วย custom agent ที่ pin IP)
- ต้องบังคับให้ทุกคนใช้ client นี้ (ต้องมี lint rule)

**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐

---

### ตัวเลือก B: Network Egress Control

```
1. Firewall: อนุญาต outbound เฉพาะ IP/domain ของ partner ที่รู้จัก
2. Forward proxy: ทุก outbound ผ่าน proxy ที่มี allowlist + logging
3. Container network policy: แยก network ของ app จาก internal service
4. ปิดการเข้าถึง cloud metadata endpoint ที่ระดับ network
```

**ข้อดี:** ✅ **ป้องกันได้แม้โค้ดมีช่องโหว่**; ครอบคลุมทุก library ไม่ใช่แค่ที่เราเขียน; ได้ log outbound ครบ
**ข้อเสีย:** ต้องจัดการ infrastructure; เพิ่ม partner ใหม่ต้องแก้ firewall (กระบวนการช้าลง); debug ยาก
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **เป็นการป้องกันที่แข็งแรงที่สุด**

---

### ตัวเลือก C: ห้ามรับ URL จากผู้ใช้โดยสิ้นเชิง

แทนที่จะรับ URL ให้รับ **identifier** แล้ว map เป็น URL ฝั่ง server

```js
// ❌ { "imageUrl": "https://..." }
// ✅ { "provider": "bunny", "assetId": "abc-123" }
const PROVIDERS = {
  bunny:  (id) => `https://storage.bunnycdn.com/${ZONE}/${id}`,
  grab:   (id) => `https://partner-api.grab.com/deliveries/${id}`,
};
```
สำหรับกรณีที่ต้อง import จาก URL จริง ๆ (product image, supplier catalog):
```
1. รับ URL → คิวงาน (ไม่ทำทันทีใน request)
2. Worker ที่อยู่ใน network segment แยกเป็นผู้ดึง
3. ตรวจ content-type + ขนาด + magic bytes
4. Re-host เป็นไฟล์ของเราเอง ไม่เก็บ URL ต้นทาง
```

**ข้อดี:** ✅ ปลอดภัยที่สุด — ไม่มี URL จาก user = ไม่มี SSRF; API contract ชัดเจนกว่า
**ข้อเสีย:** ยืดหยุ่นน้อย; บางฟีเจอร์ (webhook, import) จำเป็นต้องรับ URL จริง ๆ
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — **ควรเป็นค่าเริ่มต้นของการออกแบบ API**

---

### ตัวเลือก D: Lint Rule + Code Review Gate

```yaml
# ห้ามใช้ axios/fetch ตรง ต้องผ่าน safeHttp
- run: |
    ! grep -rnE "require\('axios'\)|from 'axios'" websocket-server/ --include='*.js' \
      | grep -v 'utils/safe-http.js'
    ! grep -rn 'maxRedirects' websocket-server/ | grep -v 'safe-http'
```

**ข้อดี:** บังคับใช้ตัวเลือก A ได้จริง; ต้นทุนต่ำมาก
**ข้อเสีย:** ไม่ครอบคลุม library ที่ยิง request เอง
**ความเหมาะสมระยะยาว:** ⭐⭐⭐⭐⭐ — ทำคู่กับ A

---

## 4. ข้อเสนอแนะเรียงตามความเหมาะสมกับ Sheserved

| อันดับ | แนวทาง | เหตุผล |
|-------|--------|--------|
| 1 | **C เป็นหลักการออกแบบ + A เป็นเครื่องมือ + D บังคับใช้ → B ตอน deploy production** | ป้องกันตั้งแต่การออกแบบ API ถูกกว่าการไล่แก้ทีหลังมาก |
| 2 | **A + D ทันที + B ภายหลัง** | ถ้ามีแผน integration ที่ต้องรับ URL แน่นอนแล้ว |
| 3 | **B อย่างเดียว** | ถ้าทีม infrastructure แข็งแรงและอยากป้องกันครอบคลุมโดยไม่แตะโค้ด |
| 4 | **รอจนกว่าจะมี integration จริง** | ⚠️ ไม่แนะนำ — เมื่อถึงตอนนั้นจะมีหลาย integration พร้อมกัน แก้ยากกว่า |

---

## 5. กฎมาตรฐานที่เสนอ (Sheserved Outbound Request Standard)

```
🎯 การออกแบบ API
  1. ค่าเริ่มต้น: ห้ามรับ URL จากผู้ใช้ — ใช้ identifier + mapping ฝั่ง server
  2. ถ้าจำเป็นต้องรับ URL ต้องได้รับอนุมัติเป็นรายกรณี พร้อมระบุเหตุผล

🌐 การเรียก outbound
  3. ทุก outbound request ต้องผ่าน safeHttp client เท่านั้น
  4. Protocol: https เท่านั้น (http อนุญาตเฉพาะ internal ที่ระบุชัด)
  5. Host ต้องอยู่ใน allowlist (OUTBOUND_ALLOWED_HOSTS)
  6. Port: 443 เท่านั้น (80 เฉพาะกรณีที่อนุมัติ)
  7. ปฏิเสธ IP: private, loopback, link-local, metadata (169.254.169.254),
     unique-local, reserved, CGNAT
  8. maxRedirects = 0 — ถ้าต้องตาม redirect ให้ validate URL ใหม่ทุก hop (สูงสุด 3)
  9. timeout ≤ 10 วินาที
 10. จำกัดขนาด response (maxContentLength)
 11. ตรวจ Content-Type ของ response ก่อนประมวลผล
 12. ไม่ส่ง credential ภายในไปกับ request ที่ไปยัง host ภายนอก

📥 การนำเข้าไฟล์จาก URL (ถ้ามี)
 13. ทำแบบ async ผ่าน queue ไม่ทำใน request cycle
 14. Worker ที่ดึงต้องอยู่ใน network segment ที่จำกัด
 15. ตรวจ magic bytes + ขนาด (ร่วมกับแผน 02)
 16. Re-host เป็นไฟล์ของเรา ไม่เก็บและไม่แสดง URL ต้นทาง

🔔 Webhook ขาออก (ถ้ามี)
 17. URL ปลายทางต้องผ่านการยืนยันความเป็นเจ้าของ (challenge-response)
 18. ผ่าน allowlist + private IP block เช่นเดียวกัน
 19. ลงลายเซ็น payload (HMAC) เพื่อให้ผู้รับตรวจสอบได้
 20. Retry แบบ exponential backoff + จำกัดจำนวนครั้ง

🚫 Error handling
 21. ไม่ส่ง response/error จากปลายทางภายนอกกลับถึง client โดยตรง
     (blind SSRF จะกลายเป็น non-blind ทันที)
 22. ไม่เปิดเผยเวลาที่ใช้ (timing) แบบละเอียด
```

### รายการที่ต้องบล็อกเสมอ
```
127.0.0.0/8        loopback
10.0.0.0/8         private
172.16.0.0/12      private
192.168.0.0/16     private
169.254.0.0/16     link-local (รวม cloud metadata 169.254.169.254)
100.64.0.0/10      CGNAT
::1/128            IPv6 loopback
fc00::/7           IPv6 unique local
fe80::/10          IPv6 link-local
0.0.0.0/8          unspecified
metadata.google.internal
```

---

## 6. ความสอดคล้องกับเอกสารที่มีอยู่

| เอกสาร | ผลกระทบ |
|--------|---------|
| `.agent/workflows/auth_data_guidelines.md` | ✅ ไม่ขัด |
| `docs/secure/11_input_validation.md` | URL validation เป็นส่วนหนึ่งของ validation layer — เพิ่ม type `url` ในมาตรฐาน |
| `docs/secure/14_xss.md` | กฎ `url_launcher` scheme allowlist เป็นฝั่ง client ของหลักการเดียวกัน |
| `docs/secure/07_secret_management.md` | 🔴 SSRF ไปยัง cloud metadata = ขโมย credential ได้ — เชื่อมโยงกับ K10 |
| `docs/secure/02_path_traversal_command_injection.md` | หลักการเดียวกัน (allowlist, containment) คนละทรัพยากร |
| `docs/secure/04_security_misconfiguration.md` | F6/F8 (network segmentation, egress) อยู่ในขอบเขต configuration baseline |
| `docs/secure/03_rate_limiting_resource_exhaustion.md` | Outbound request ก็ต้องมี rate limit (ป้องกันใช้ระบบเราเป็นเครื่องมือโจมตีผู้อื่น) |
| `docs/infrastructure/reverse_proxy_plan.md` | Forward proxy สำหรับ egress ควรระบุในแผนนั้น |
| `docs/infrastructure/architecture_analysis.md` | ควรเพิ่ม network zone diagram (public / app / data / egress) |
| ทุกแผนใน `docs/ERP/` ที่มี integration | ⚠️ **ต้องเพิ่มหัวข้อ "outbound request security" ในแต่ละแผน** |

---

## 7. งานที่ต้องตรวจสอบทันทีเมื่ออนุมัติ

- [ ] Grep หา `axios`, `fetch`, `http.request`, `https.get` ทุกจุดใน `websocket-server/`
- [ ] ตรวจว่า outbound request ทุกจุดมี timeout หรือไม่ (ปัจจุบัน `uploadToBunny` ไม่มี)
- [ ] ตรวจว่า server สามารถเข้าถึง cloud metadata endpoint ได้หรือไม่
- [ ] ตรวจ network topology: app server เข้าถึงอะไรได้บ้าง
- [ ] ตรวจว่ามี dependency ตัวไหนที่ยิง outbound request เองบ้าง

---

## 8. Checklist ก่อน implement (รอการตัดสินใจ)

- [ ] อนุมัติหลักการ "ห้ามรับ URL จากผู้ใช้เป็นค่าเริ่มต้น" (C) — แนะนำ: ใช่
- [ ] อนุมัติการสร้าง `utils/safe-http.js` (A)
- [ ] อนุมัติการเพิ่ม `ipaddr.js` เป็น dependency (ร่วมกับแผน 06)
- [ ] กำหนดรายการ `OUTBOUND_ALLOWED_HOSTS` เริ่มต้น
- [ ] ตัดสินใจเรื่อง network egress control / forward proxy (B)
- [ ] อนุมัติ lint rule บังคับใช้ safeHttp (D)
- [ ] ตัดสินใจว่าจะมีฟีเจอร์ webhook ที่ผู้ใช้กำหนด URL หรือไม่ (ถ้ามี ต้องออกแบบเพิ่ม)
- [ ] กำหนดว่าใครอนุมัติการเพิ่ม host ใหม่เข้า allowlist
