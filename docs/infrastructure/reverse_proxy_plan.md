# 🌐 แผนยุทธศาสตร์และโครงสร้าง Reverse Proxy สำหรับ Sheserved
เอกสารนี้กำหนดแผนการใช้งาน **Reverse Proxy** สำหรับระบบ Sheserved เพื่อเพิ่มความปลอดภัย จัดการการเข้าถึง และสอดรับการให้บริการทราฟฟิกสูงในอนาคต โดยมุ่งเน้นแนวทาง **ไม่มีค่าใช้จ่ายเพิ่มเติม (Zero-Cost)** ในช่วงเริ่มต้นพัฒนาและ Deploy

---

## 1. ทำไม Sheserved ต้องใช้ Reverse Proxy?

ในการประยุกต์ใช้งานจริง การให้เครื่องไคลเอนต์ติดต่อกับเซิร์ฟเวอร์ Backend (Node.js/Supabase/WebSocket) โดยตรงโดยผ่าน Port ของแอปพลิเคชันนั้นมีจุดบกพร่องหลายประการ ซึ่ง Reverse Proxy จะเข้ามาช่วยแก้ปัญหาดังต่อไปนี้:

*   **ซ่อน Backend Server (Backend Shield):** ซ่อนพอร์ตจริงที่ Node.js ทำงานอยู่ภายในเครื่อง (เช่น Port `3000`, `3001`) จากสาธารณะ ทำให้ปลอดภัยจากการโจมตีพอร์ตตรงหรือสแกนพอร์ตหาช่องโหว่ทาง OS
*   **จัดการ HTTPS/SSL (SSL Termination):** จัดการเรื่องการรับส่งข้อมูลแบบเข้ารหัส (HTTPS) ที่ด่านหน้า ช่วยลดความซับซ้อนของโค้ด Node.js backend ที่ไม่จำเป็นต้องจัดการไฟล์ Certificate โดย Caddy หรือ Nginx + Certbot จะทำหน้าที่ขอและต่ออายุใบรับรองความปลอดภัยฟรี 100%
*   **การกำหนดเส้นทางทราฟฟิก (Routing):** ช่วยรวมบริการต่างๆ ที่มีโดเมนต่างกันแต่รันอยู่ใน VPS ตัวเดียวกันให้เรียกใช้งานผ่านช่องทางหลัก (Port 80/443) จุดเดียวได้ เช่น:
    *   `api.sheserved.com` ➡️ Node.js Backend API
    *   `socket.sheserved.com` ➡️ WebSocket Server (Socket.io)
    *   `admin.sheserved.com` ➡️ ERP Web Dashboard / Static Files
*   **Load Balancing และ Caching (รองรับอนาคต):** ทำหน้าที่จัดลำดับโหลด ทราฟฟิกกระจายความร้อน และทำแคชข้อมูลหน้าเว็บ/Assets บางประเภทโดยตรงช่วยลด CPU cycle ของ Node.js

---

## 2. โครงสร้างการเชื่อมต่อ (Architecture Flow)

```
[📱 Flutter App / Web] ➡️ [🌐 Cloudflare (Edge CDN / SSL / WAF)]
                                        ⬇️ (Port 443 HTTPS)
                         [🔌 Reverse Proxy (Caddy / Nginx on VPS)]
                                        ⬇️ (Local Network Routing)
             ┌──────────────────────────┼──────────────────────────┐
             ▼                          ▼                          ▼
   [Node.js API Server]       [WebSocket Server]          [Static Web Assets]
     (localhost:3000)           (localhost:3001)           (Dist files on disk)
```

---

## 3. การตรวจสอบความสอดคล้อง (Alignment Check) กับแผนงานย่อยอื่น ๆ

แผนการใช้ Reverse Proxy นี้ได้รับการตรวจสอบอย่างละเอียดและออกแบบมาให้ **ไม่เกิดการขัดแย้ง** กับเอกสารแผนงานสำคัญทั้ง 6 ระบบ ดังนี้:

### 3.1 ระบบบริจาค ([DONATION_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/DONATION_SYSTEM_PLAN.md))
*   **ความสอดคล้อง:** 
    *   การทำกิจกรรมอนุมัติผ่าน Multi-Category Approval ที่ต้องการความแม่นยำสูง จะส่งตรงไปยัง Node.js ผ่าน `api.sheserved.com` 
    *   ทราฟฟิก WebSocket สำหรับอัปเดตยอดบริจาค Real-time จะได้รับการส่งผ่าน Reverse Proxy เพื่อเปิดฟีเจอร์ WebSockets Upgrade (เช่น Connection Multiplexing) ให้ไม่เกิดทราฟฟิกหลุด

### 3.2 ระบบวิดีโอ ([VIDEO_SYSTEM_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/VIDEO_SYSTEM_PLAN.md))
*   **ความสอดคล้อง:** 
    *   การประมวลผลวิดีโอ (FFmpeg) และการซิงค์วิดีโอจะรันหลังบ้านโดยไม่ผ่าน API ภายนอกตรงๆ 
    *   ตัววิดีโอ HLS ถูกอัปโหลดขึ้น Bunny.net ไปแล้ว ดังนั้น Reverse Proxy จะมีหน้าที่เพียงรับคำสั่งอัปโหลดเริ่มต้นผ่าน API และส่งสัญญาณผ่าน WebSocket โดยไม่บล็อกแบนด์วิดท์ของระบบจัดส่งวิดีโอ

### 3.3 ระบบปรึกษาแพทย์ ([CHAT_CONSULTATION_IMPROVEMENT_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/CHAT_CONSULTATION_IMPROVEMENT_PLAN.md))
*   **ความสอดคล้อง:**
    *   สำหรับระบบแชทที่เปิดใช้เซสชันแพทย์จำกัดสิทธิ์ผู้ใช้ (Custom Auth) ตัว Reverse Proxy จะช่วยปกป้อง headers สำคัญ เช่น `x-idempotency-key` และข้อมูลยืนยันตัวตนของผู้ใช้จากการถอดรหัสในระหว่างทางด้วย HTTPS/SSL บังคับ
    *   Caddy จะช่วยส่งผ่านสัญญาณ Realtime Stream จาก Supabase ในระดับ Network ได้อย่างโปร่งใส

### 3.4 ระบบแกนหลัก ERP ([ERP_CORE_ARCHITECTURE.md](file:///Users/dave_macmini/sheserved/docs/ERP/ERP_CORE_ARCHITECTURE.md))
*   **ความสอดคล้อง:**
    *   ระบบ ERP รองรับ Multi-Tenant และ Multi-Branch ตัว Reverse Proxy จะรับผิดชอบการ Route ทราฟฟิกแยกตามโดเมนหรือ Tenant Path ได้อย่างดีโดยไม่มีข้อจำกัด
    *   ในโหมด Hybrid/Self-host: Reverse Proxy ในเครือข่ายภายในจะทำหน้าที่เชื่อมต่อ `self_host_api_url` เข้ากับ Database ที่เครื่องหลักฝั่งคลินิก

### 3.5 ระบบจัดส่งพัสดุ ([Delivery_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/Delivery_PLAN.md))
*   **ความสอดคล้อง:**
    *   แผนจัดส่งพัสดุเน้นการควบคุมค่าใช้จ่ายโดยใช้งาน Mobile-Only Map SDK บนสมาร์ทโฟนเป็นหลัก ตัว Reverse Proxy จะช่วยลดการเรียกใช้ APIs แผนที่ในส่วนกลาง เว็บบอร์ดแอดมินจะอ่านพิกัด text ตรงจาก API Backend ที่ถูกแคชไว้บน Reverse Proxy ช่วยคุมต้นทุน Google Maps API เป็นศูนย์ดั่งที่ระบุไว้ในแผน

### 3.6 ระบบตะกร้าสินค้า ([SHOPPING_CART_PLAN.md](file:///Users/dave_macmini/sheserved/docs/plans/SHOPPING_CART_PLAN.md))
*   **ความสอดคล้อง:**
    *   รายการ Universal Cart และ API ตรวจสต๊อกจะยิงผ่าน Reverse Proxy ด่านหน้าเพื่อรับบริการ Caching และ Rate Limit เพื่อกันไม่ให้บอทกระหน่ำยิงเช็คราคาสต๊อกในฝั่ง POS/Inventory โดยตรง

---

## 4. แผนปฏิบัติการติดตั้งและคอนฟิกูเรชัน (ไม่มีค่าใช้จ่าย 🟢)

### ทางเลือกที่ 1: Caddy Server (แนะนำสำหรับความง่ายและออโต้ SSL)
Caddy ทำหน้าที่เป็น Reverse Proxy ที่ติดตั้งและดูแลได้ง่ายที่สุด เนื่องจากรองรับระบบ Auto SSL จาก Let's Encrypt ในตัวโดยไม่ต้องลง Certbot เพิ่มเติม

1. **การติดตั้ง (บน Ubuntu/Debian VPS):**
   ```bash
   sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
   sudo apt update
   sudo apt install caddy
   ```

2. **การตั้งค่าไฟล์คอนฟิก (`/etc/caddy/Caddyfile`):**
   ```caddy
   # 1. จัดการ Endpoint API
   api.sheserved.com {
       reverse_proxy localhost:3000
   }

   # 2. จัดการ Endpoint WebSockets
   socket.sheserved.com {
       reverse_proxy localhost:3001
   }

   # 3. จัดการ Frontend Admin Web ( static files )
   admin.sheserved.com {
       root * /var/www/sheserved-admin/dist
       file_server
       try_files {path} /index.html
   }
   ```

---

### ทางเลือกที่ 2: Nginx + Certbot (มาตรฐานสำหรับการตั้งค่า Caching ขั้นสูง)
เหมาะสำหรับการใช้งานที่เน้นความสามารถในการปรับจูน Caching ในเครื่องสูง

1. **การตั้งค่า Nginx เสมือนเป็น Gateway แยกตามบริการ (`/etc/nginx/sites-available/sheserved`):**
   ```nginx
   # การอัปสตรีมสำหรับ Node.js API
   upstream nodejs_backend {
       server 127.0.0.1:3000;
   }

## 4. แผนการดำเนินงานและขั้นตอนการทดสอบ (Testing & Rollout Phases)

เพื่อให้การทดสอบความถูกต้องของเครือข่ายและการรับส่งข้อมูลสามารถทำได้ง่ายในทุกระดับสภาพแวดล้อม (Zero-Cost Setup) แผนงานจะถูกจัดแบ่งเป็น 3 เฟสที่ง่ายต่อการทดสอบดังนี้:

---

### 🟢 Phase 1: การทดสอบบนเครื่องพัฒนาจำลองผ่านเครือข่ายท้องถิ่น (Local Sandbox Testing via mDNS)
เฟสนี้มีเป้าหมายเพื่อทดสอบระบบจำลองบนเครื่อง Mac ด้วยสถาปัตยกรรมเครือข่ายท้องถิ่น (Multicast DNS / Bonjour) เพื่อให้เครื่องมือถือจริง (Physical Device) หรือ Emulator สามารถเชื่อมต่อมาทดสอบ Reverse Proxy ได้ง่ายโดยไม่ต้องแก้ไขไฟล์ hosts และรองรับการเปลี่ยนวง IP (Dynamic IP) อัตโนมัติ

1. **การค้นหา Local Hostname (บน macOS):**
   * ไปที่ **System Settings > General > Sharing** ตรวจสอบชื่อในส่วน **Local Hostname** (ตัวอย่างเช่น: `dave-macmini.local`)
   * หรือรันคำสั่งใน Terminal: `dns-sd -G v4 dave-macmini.local` หรือดูผ่านคำสั่ง `hostname`

2. **รัน Caddy บนเครื่อง Mac สำหรับทดสอบ (แนะนำสำหรับ Caddy):**
   ติดตั้ง Caddy ผ่าน Homebrew ด้วยคำสั่ง `brew install caddy` จากนั้นสร้างไฟล์คอนฟิก `Caddyfile.local` ในโฟลเดอร์สำหรับทดสอบ:
   ```caddy
   # 1. จัดการ Endpoint API
   dave-macmini.local:80/api {
       reverse_proxy localhost:3000
   }

   # 2. จัดการ Endpoint WebSockets
   dave-macmini.local:80/ws {
       reverse_proxy localhost:3001
   }

   # 3. จัดการ Frontend Admin Web ( static files )
   dave-macmini.local:8080 {
       root * ./web_build
       file_server
       try_files {path} /index.html
   }
   ```
   รัน Caddy ด้วยคำสั่ง `caddy run --config Caddyfile.local`

3. **ขั้นตอนการทดสอบ (Verification checklist):**
   * [ ] **Test API Route:** ใช้ Postman หรืออุปกรณ์มือถือที่เชื่อม Wi-Fi วงเดียวกัน เรียกดู `http://dave-macmini.local/api/health` ต้องตอบกลับได้โดยตรง
   * [ ] **Test WS Connection:** ทดสอบต่อระบบแชทหรือแจ้งเตือนเหตุฉุกเฉินผ่าน `ws://dave-macmini.local/ws`
   * [ ] **Test Flutter Target:** ปรับ `app_config.dart` ของแอป Flutter ชี้มาที่ `http://dave-macmini.local` (โทรศัพท์จริงที่เชื่อมวง Wi-Fi เดียวกันจะเรียกใช้ได้ทันทีโดยไม่ต้องระบุ IP และไม่ต้องกรอกพอร์ต)

---

### 🟢 Phase 2: การทดสอบในสภาพแวดล้อมจำลอง (Staging & SSL Verification)
เฟสนี้ย้ายระบบขึ้นไปจำลองบน VPS จริง เพื่อทดสอบการรับส่งข้อมูลผ่าน HTTPS (SSL Termination) และระบบต่ออายุใบรับรองฟรีจาก Let's Encrypt

1. **การติดตั้ง Reverse Proxy บนเซิร์ฟเวอร์:**
   * **ทางเลือก A (Caddy):** คอนฟิกง่ายและขอ SSL อัตโนมัติ:
     ```caddy
     # /etc/caddy/Caddyfile
     api.sheserved-staging.com {
         reverse_proxy localhost:3000
     }
     socket.sheserved-staging.com {
         reverse_proxy localhost:3001
     }
     ```
   * **ทางเลือก B (Nginx):** กำหนดสิทธิ์และ Forward Proxy (สร้างไฟล์ที่ `/etc/nginx/sites-available/sheserved`):
     ```nginx
     upstream backend_servers {
         server 127.0.0.1:3000;
     }
     upstream websocket_servers {
         server 127.0.0.1:3001;
     }

     server {
         listen 80;
         server_name api.sheserved-staging.com;
         location / {
             proxy_pass http://backend_servers;
             proxy_set_header Host $host;
             proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
         }
     }
     ```
     แล้วรัน Certbot เพื่อขอ SSL: `sudo certbot --nginx -d api.sheserved-staging.com`

2. **ขั้นตอนการทดสอบ (Verification checklist):**
   * [ ] **SSL Security Test:** ตรวจสอบแม่กุญแจความปลอดภัยบน Browser เมื่อเข้าสู่ `https://api.sheserved-staging.com` (ต้องได้เกรด A จาก SSL Labs)
   * [ ] **WSS Test:** ทดสอบเชื่อมต่อผ่าน `wss://socket.sheserved-staging.com` จากแอป Flutter (การเข้าคู่ wss ปลอดภัย)
   * [ ] **SSL Auto-Renewal Test:** รันคำสั่ง `sudo certbot renew --dry-run` เพื่อยืนยันว่าการขอ SSL ทำงานใหม่ได้เมื่อครบกำหนด

---

### 🟢 Phase 3: ระบบจริงและการแคชข้อมูลระดับสูง (Production & Edge Security)
เฟสปรับปรุงระบบขึ้นใช้จริงร่วมกับ Cloudflare เพื่อป้องกันการเจาะและเปิดใช้งาน CDN Caching

1. **การเชื่อมต่อ Cloudflare Edge Proxy (ฟรี 🟢):**
   * ชี้ Domain DNS หลักเข้าสู่ระบบคลาวด์ของ Cloudflare
   * เปิดสถานะ **Proxy (ก้อนเมฆสีส้ม)** สำหรับ `api.sheserved.com` และ `socket.sheserved.com`
   * ตั้งค่าโหมด SSL/TLS ใน Cloudflare เป็น **Full (Strict)** เพื่อเข้ารหัสข้อมูลตั้งแต่ต้นทางถึง VPS

2. **ขั้นตอนการทดสอบ (Verification checklist):**
   * [ ] **Cloudflare Edge Test:** ยิง API และตรวจเช็ค HTTP Headers ใน Response ต้องมีฟิลด์ `cf-ray`, `cf-cache-status` ปรากฏ
   * [ ] **Client IP Forwarding Test:** ตรวจสอบ Log ของ Node.js backend ว่ายังสามารถอ่าน IP จริงของลูกค้าได้ผ่าน Header `X-Forwarded-For` หรือ `CF-Connecting-IP` (ไม่ใช่ได้ IP ของ Proxy เสมอไป)
   * [ ] **WebSocket Proxy Test:** ตรวจสอบว่า WebSocket ของระบบจองและแชทยังใช้งานได้ลื่นไหลผ่าน Cloudflare (เนื่องจาก Cloudflare ซัพพอร์ต WebSocket proxy อัตโนมัติ)
   * [ ] **DDoS Mitigation Check:** ทดสอบยิง Request ถี่ๆ เพื่อเช็คว่า Rate Limit ด่านแรกของ Cloudflare และด่านสองที่ Redis Middleware ทำงานร่วมกันได้อย่างดีโดยไม่ปิดกั้นการทำงานของทราฟฟิกปกติ

