# Video Upload and Streaming System Plan

## Overview

แผนระบบวิดีโอสำหรับ Tree Law Zoo โดยใช้ Bunny.net + PostgreSQL + FFmpeg ทั้งหมดรันที่เครื่องหลัก (เครื่องเดียว)

## Architecture

### ทางเลือกที่เลือก: Bunny.net + PostgreSQL + FFmpeg (Self-hosted)

**Flow การทำงาน:**
1. **Upload**: รับไฟล์วิดีโอจาก Client (ระบุประเภท: Normal หรือ Emergency)
2. **Queue**: นำเข้า Queue โดยใช้ **Priority logic** (Emergency จะถูกแทรกไปหน้าสุด)
3. **Insert DB**: บันทึกข้อมูลเบื้องต้นและ GPS Path (ถ้ามี) ลง PostgreSQL
4. **Transcode**: ใช้ FFmpeg แปลงเป็น HLS format
5. **Upload to Bunny**: ส่งไฟล์ HLS ทั้งหมดขึ้น Bunny.net Storage
6. **Cleanup**: ลบไฟล์ชั่วคราวออกจากเครื่องหลักทันทีเมื่อสำเร็จ
7. **Update DB**: อัปเดตสถานะและ URL เพื่อพร้อมใช้งาน
8. **Notify**: แจ้งสถานะและความคืบหน้าผ่าน WebSocket

### 🚨 นโยบายการจัดการพื้นที่จัดเก็บข้อมูล (Storage Policy - Mandatory)

เพื่อให้ระบบทำงานได้เสถียรและป้องกันปัญหาพื้นที่เครื่องหลักเต็ม (Disk Full) ให้ยึดถือแนวทางดังนี้:

1. **บันทึกลง External Drive เท่านั้น**: ไฟล์วิดีโอ (Raw/Temp) และภาพหน้าปกวิดีโอ (Thumbnails) ทั้งหมด ต้องเก็บไว้ที่ `/Volumes/PostgreSQL/sheserved_videos`
2. **ห้ามย้ายไปเก็บที่ Local Harddisk**: ห้ามเปลี่ยน `TEMP_VIDEO_PATH` ใน `.env` กลับเป็น `./temp/videos` บน Macintosh HD โดยเด็ดขาด
3. **การจัดการหมายเลข IP เมื่อเปลี่ยนสถานที่ทำงาน (Dynamic IP Support)**: เนื่องจากผู้พัฒนาย้ายที่ทำงานหลายแห่ง ให้ตรวจสอบ IP ของเครื่องหลักในแต่ละสถานที่ (`ipconfig getifaddr en0`) และระบุค่าให้ตรงกันทั้งใน `AppConfig.mainMachineIp` (Flutter) และ `LOCAL_API_URL` ใน `.env` (Server) ทุกครั้งที่มีการเปลี่ยนวง Network — **ดูขั้นตอนละเอียดใน Section "🔧 Network & Configuration Runbook" ด้านล่าง**

### สถาปัตยกรรม

```
┌─────────────────────────────────────────────────┐
│  Main Machine (เครื่องหลัก)                      │
│                                                 │
│  ┌─────────────┐    ┌──────────────┐          │
│  │  Flutter    │    │  WebSocket   │          │
│  │  App        │◀───▶│  Server      │          │
│  └─────────────┘    │  (Node.js)   │          │
│          ▲          └──────┬───────┘          │
│          │                 │ (Likes/Gifts)     │
│          │          ┌──────▼───────┐          │
│          └──────────│  Real-time   │          │
│                     │  Interaction │          │
│                     └──────┬───────┘          │
│                            │                   │
│                     ┌──────▼───────┐          │
│                     │  Priority    │          │
│                     │  Queue (Bull)│          │
│                     └──────┬───────┘          │
│                            │                   │
│                     ┌──────▼───────┐          │
│                     │  PostgreSQL  │          │
│                     │  + GPS Data  │          │
│                     └──────┬───────┘          │
│                            │                   │
│                     ┌──────▼───────┐          │
│                     │  FFmpeg      │          │
│                     │  (Transcode) │          │
│                     └──────┬───────┘          │
│                            │                   │
│                     ┌──────▼───────┐          │
│                     │  Bunny.net   │          │
│                     │  (CDN/Storage│          │
│                     └──────────────┘          │
└─────────────────────────────────────────────────┘
```

---

### Emergency Alert Architecture (Level 3 — Best Fix, Updated 2026-03-14)

**หลักการ:** Emergency Alert ใช้ **Supabase Cloud เป็น Source of Truth** สำหรับการ lookup category และ volunteer list — ไม่ใช่ Local PostgreSQL เพื่อแก้ปัญหา Data Sync และรับประกัน Privacy-First Delivery

**Flow การทำงาน:**

```
Flutter App
    │
    ├── socket.emit('emergency-alert', { userId, categoryId, videoId, ... })
    │
    ▼
WebSocket Server (server.js)
    │
    ├── Step 1: GPS lookup ← Local PostgreSQL (เครื่องเดียวกัน, sync สมบูรณ์)
    │
    ├── Step 2: Category + Volunteer lookup ← SUPABASE CLOUD (Source of Truth)
    │       │
    │       ├── 2a. query donation_categories WHERE id = categoryId
    │       │        ↓ ถ้าไม่พบ → io.emit() Broadcast Fallback
    │       │
    │       ├── 2b. ถ้า volunteer_profession_ids ว่าง → Broadcast ทั้งหมด
    │       │
    │       └── 2c. query user_group_roles JOIN consumer_profiles
    │                WHERE profession_id IN [...] AND is_volunteer_active = true
    │                ↓
    └── Step 3: io.to('user-{id}').emit() เฉพาะ volunteer ที่ตรงสิทธิเท่านั้น
```

**Fallback Chain (ลำดับความปลอดภัย):**

| สถานการณ์ | พฤติกรรม |
|:---|:---|
| Supabase ตอบกลับปกติ + มี volunteer | ✅ ส่งเฉพาะ volunteer ที่ตรงสิทธิ (Privacy First) |
| Supabase ตอบกลับปกติ + ไม่มี volunteer | ⚠️ Silent — ไม่ส่งใคร (ถูกต้องตาม Policy) |
| Supabase ตอบกลับปกติ + category ไม่มี professions | 📢 Broadcast ทุกคน (Flutter กรองเอง) |
| Category ไม่พบใน Supabase | 📢 Broadcast ทุกคน (Fallback) |
| Supabase ล้มเหลว (network error) | 📢 Broadcast ทุกคน (Safety Fallback) |
| SUPABASE_URL ไม่ได้ตั้งค่า | 📢 Broadcast ทุกคน (Config Fallback) |

**Auth & Data Guidelines (ไม่ขัด `/auth_data_guidelines.md`):**
- ใช้ **Anon Key** เท่านั้น — อ่านข้อมูล Public (`donation_categories`, `user_group_roles`)
- **ไม่ใช้** `Supabase.instance.client.auth.currentUser` เลย
- **ไม่ใช้** `_client.auth.currentUser` เลย
- ข้อมูล User Identity (`userId`) มาจาก WebSocket payload ที่ Flutter ส่งมาผ่าน `AuthService.instance.currentUser?.id` ฝั่ง Client เท่านั้น

**Environment Variables ที่ต้องตั้งค่าใน `websocket-server/.env`:**
```env
SUPABASE_URL=https://[project-id].supabase.co
SUPABASE_ANON_KEY=[anon-key-จาก-supabase-dashboard]
```

**Privacy-First Design:**
> ระบบส่งข้อมูล Emergency Alert ไปยัง **Device ของ Volunteer ที่เกี่ยวข้องเท่านั้น** — ไม่มีการส่งข้อมูลไปยัง Device ที่ไม่มีสิทธิตั้งแต่ระดับ Server ผู้ใช้ที่มีสิทธิ Volunteer แต่ไม่ได้ถูก Map ไว้ใน `donation_categories.volunteer_profession_ids` จะไม่ได้รับ Socket Packet เลย ป้องกันการสิ้นเปลือง Data/แบตเตอรี่

---

## Database Schema


### SQL Schema Implemented (Watermark Configs — Added 2026-05-11)
```sql
CREATE TABLE IF NOT EXISTS watermark_configs (
    id SERIAL PRIMARY KEY,
    is_enabled BOOLEAN DEFAULT false,
    type VARCHAR(20) DEFAULT 'text', -- 'text' or 'image'
    text_content TEXT,
    image_url TEXT,
    position VARCHAR(20) DEFAULT 'bottom-right',
    animation_type VARCHAR(20) DEFAULT 'none',
    opacity DECIMAL(2,1) DEFAULT 0.5,
    show_incident_id BOOLEAN DEFAULT false,
    show_uploader_id BOOLEAN DEFAULT false,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Initialize default config if not exists
INSERT INTO watermark_configs (id, is_enabled, type, text_content, position)
VALUES (1, true, 'text', 'Sheserved Official', 'bottom-right')
ON CONFLICT (id) DO NOTHING;
```


## Technology Stack

### Backend (Node.js)
- **express** & **multer** - API และ Upload
- **pg** - PostgreSQL
- **fluent-ffmpeg** - Transcoding
- **axios** - Bunny.net API
- **bullmq** - สำหรับจัดการ **Priority Queue**
- **socket.io** - สำหรับ Progress และ Real-time Interactions

### Massive Scale Architecture (Trending Panel & Gallery — Updated 2026-05-07)
เพื่อให้หน้ารายงานเหตุฉุกเฉิน (Trending Panel) และแกลลอรี่ภาพไทยมุง (Thai Mhung Gallery) รองรับข้อมูลระดับหลักหมื่นถึงหลักแสนภาพ/การ์ดได้อย่างลื่นไหล ระบบถูกออกแบบด้วยเทคนิคดังต่อไปนี้:
1. **DB Cached Counters (Backend)**: ยกเลิกการใช้ `LEFT JOIN COUNT(*)` กับตาราง `video_interactions` ใน Query การดึงลิสต์เหตุการณ์ เพราะเมื่อตารางนี้ใหญ่ขึ้นจะทำให้ Query ช้ามาก เปลี่ยนมาเพิ่มคอลัมน์ `cached_view_count` และ `cached_like_count` ในตาราง `videos` โดยตรง และใช้ **Database Trigger** (`trg_update_interaction_counts`) เพื่ออัปเดต Counter เหล่านี้อัตโนมัติทุกครั้งที่มีการกด Like หรือ View ทำให้ Query ดึงข้อมูลหลักล้านได้ในเวลาไม่ถึงมิลลิวินาที
2. **Infinite Scroll Pagination (Backend & Frontend)**: API `/emergency/list` ถูกปรับแก้ให้รับพารามิเตอร์ `page` และ `limit` โดยทำ `LIMIT $1 OFFSET $2` ฝั่งแอปใช้ `ScrollController` คอยจับระยะขอบล่างของการ์ด (ห่างจากขอบล่าง 200px) เพื่อส่งคำสั่ง Load More ดึงข้อมูลหน้าที่สองมาต่อท้ายลิสต์อัตโนมัติแบบไร้รอยต่อ
3. **Gallery Data Indexing (Backend)**: เพิ่มคอลัมน์ `incident_id` ในตาราง `videos` ของ PostgreSQL โดยตรง เพื่อทำ Data Relation ระหว่างรูปภาพไทยมุงกับเหตุการณ์หลัก แทนการใช้วิธีค้นหาจาก URL (String Regex Matching) ซึ่งกินทรัพยากรสูง และสร้าง API `GET /api/videos/:id/gallery` แยกเฉพาะสำหรับการทำ Pagination (แบ่งหน้าละ 20 รูป)
4. **Image Cache Control (Frontend)**: เปลี่ยนการใช้ `Image.network` ที่เปลืองหน่วยความจำในกรณีข้อมูลล้นหลาม ไปใช้ `CachedNetworkImage` ในทุกจุดของแอป (Trending Panel, Gallery, Lightbox) เพื่อให้ระบบมี Cache Manager จัดการรูปภาพในเครื่อง จำกัดพื้นที่และเคลียร์รูปภาพที่ไม่ได้แสดงบนหน้าจอทิ้งอัตโนมัติ พร้อมทำ Loading Shimmer และ Error Builder เพื่อให้ UI สวยงามไม่กระตุกเมื่อเน็ตเวิร์คมีปัญหา

### Integrated Interaction & Merit Score System (Updated 2026-05-08)
ระบบแสดงผลสถิติการ "โต้ตอบ" และ "แต้มบุญ" (Interaction Buttons & Merit Score) ทั้งหมดในรูปแบบ Unified Dynamic Visualization เพื่อสร้างความโปร่งใสและกระตุ้นการมีส่วนร่วมในเหตุการณ์ฉุกเฉิน:
1. **Unified Dynamic Bar-Charts (Frontend)**: ปรับโครงสร้างปุ่มโต้ตอบทั้งหมด (Likes, Yield Way, Donation) ให้เป็นระบบ **Unified Layout Component** ที่สอดคล้องกัน:
    - **Shared Design Language**: ทุกปุ่มประกอบด้วย 3 ส่วน: [Left Box (ตัวเลข)] + [Middle Bar (กราฟ)] + [Right Button (ปุ่มกด)]
    - **Left Box (สถิติตัวเลข)**: กล่องพื้นหลังสีเทาทางซ้ายสุด แสดงจำนวนรวมพร้อมหน่วย (คน/บาท) โดยใช้เทคนิค **Dummy Invisible Text** ใน `Stack` เพื่อรักษาความสูงให้เท่ากับปุ่มกดด้านขวา 100% ตลอดเวลา และใช้ `FittedBox` ป้องกันตัวหนังสือล้นกรอบ
    - **Middle Bar (กราฟแถบความก้าวหน้า)**: แถบสีแนวนอนที่ยืดขยายตามสัดส่วน (Actual/Target Ratio) แบบ Real-time:
        - **Likes (ส่งกำลังใจ)**: แถบสีส้ม ยืดตามสัดส่วนยอดไลค์ปัจจุบันเทียบกับยอดสูงสุดในเหตุการณ์
        - **Yield Way (ให้ทาง)**: แถบสีฟ้า/น้ำเงิน ยืดตามสัดส่วน `yieldWayCount` เทียบกับ `yieldWayNotifiedCount` (จำนวนคนบนเส้นทางที่ถูกแจ้งเตือน)
        - **Donation (บริจาค)**: แถบสีทอง/ไล่เฉด ยืดตามสัดส่วน `currentAmount` เทียบกับ `goalAmountGross` ของคำร้องบริจาคใบนั้นๆ
    - **Right Button (ปุ่มโต้ตอบ)**: ปุ่มกดที่ติดอยู่ปลายขวาของแถบกราฟเสมอ โดยมัดรวมด้วย `IntrinsicHeight` เพื่อให้ทั้งแถบและปุ่มมีความสูงเท่ากันเป๊ะและจัดวางกึ่งกลางแนวตั้งเสมอ
2. **Atomic Interaction Logic (Backend)**: 
    - **Unique Likes**: ใช้ Database Constraint ป้องกันการกดไลค์ซ้ำและรองรับการ Toggle
    - **Yield Way Calculation**: Server คำนวณจำนวนผู้ที่อยู่บนเส้นทางที่แจ้งเตือนจริง (`notifiedCount`) เพื่อเป็นฐานสำหรับคำนวณเปอร์เซ็นต์ความสำเร็จของการขอทาง
3. **Real-time Syncing & Feedback**: 
    - ใช้ **WebSocket** กระจายอีเวนต์ `like-toggled`, `yield-way-updated` และ `donation-updated` เพื่อให้แถบกราฟขยับแบบแอนิเมชันบนหน้าจอของผู้ใช้ทุกคนทันที
    - **Interaction Feedback UI**: ปุ่มกดจะมีการเปลี่ยนสถานะสีและการเรืองแสง (BoxShadow) เมื่อผู้ใช้กดโต้ตอบสำเร็จ
4. **Consistency across Roles**: ระบบกราฟแบบใหม่นี้ถูกนำไปใช้ทั้งใน `ActionButtonsWidget` (สำหรับผู้ดู) และ `IncidentReportWidget` (สำหรับผู้รายงานเหตุ) เพื่อให้เกิดมาตรฐาน UX เดียวกันทั้งระบบ

### Flutter / Frontend
- **Supabase SDK** - สำหรับดึงข้อมูลวิดีโอและ GPS
- **DonationRepository** - เชื่อมโยงปุ่ม "บริจาค" เพื่อเรียกใช้ฟังก์ชัน `getRequests()` และการชำระเงินเดิม
- **video_player** / **chewie** - สำหรับเล่นวิดีโอ HLS
- **fl_chart** - สำหรับแสดงกราฟ Support Analytics (Trend Chart) แบบ Real-time

### CDN/Storage
- **Bunny.net** - HLS streaming & Storage (Thailand PoP)

### Video Processing & Management
- **Face Blurring (Privacy Mode)**: ใช้เครื่องมือ Open-Source `deface` (Python-based) ในการทำ Automated Face Anonymization ก่อนกระบวนการ Transcode หรือหลังการอัปโหลดภาพนิ่ง เพื่อเบลอเฉพาะใบหน้าบุคคลในเหตุการณ์ 
  - **Badge Visibility**: ผู้ใช้ทั่วไปหรือไทยมุงจะเห็นป้ายกำกับ "สงวนสิทธิ์ภาพบุคคล (Face Blur)" ที่มุมขวาบนของวิดีโอหรือภาพถ่าย
  - **Volunteer Privilege**: สำหรับผู้เป็นเจ้าของเหตุ หรือ **ผู้ได้รับสิทธิและผ่านระบบคัดกรองให้เป็นอาชีพจิตอาสา (Verified Volunteer)** ของเหตุการณ์นั้นๆ จะ **ไม่ต้องขึ้นป้ายกำกับนี้** เพราะถือว่ามีสิทธิประเมินร่องรอยและรายละเอียดบนวิดีโอในฐานะผู้ช่วยเหลือ
  - **Thai Mhung Photo Anonymization (New)**: ปรับปรุงจากการเบลอทั้งภาพด้วย UI ฟิลเตอร์ (Gallery Blur) มาเป็นการประมวลผลที่เซิร์ฟเวอร์เพื่อเบลอ **เฉพาะใบหน้าคน** วิธีนี้จะช่วยให้เจ้าหน้าที่และไทยมุงคนอื่นๆ เห็นรายละเอียดสภาพแวดล้อมและเหตุการณ์ได้ชัดเจน (เช่น ลักษณะบาดแผล, อุปกรณ์ประกอบฉาก) ในขณะที่ยังคงปกป้องตัวตนของบุคคลในภาพได้ 100%
- **Thumbnail Generation Pipeline (Async BullMQ — Updated 2026-05-07)**: ระบบสร้าง Thumbnail อัตโนมัติสำหรับทุกเหตุการณ์ โดยใช้ **Async Queue** เพื่อไม่ block HTTP Request:
  - **Non-blocking Flow**: Upload → Respond 200 ทันที → push job ไปยัง `thumbnail-generation` Queue → Worker generate WebP → UPDATE DB → emit `thumbnail-updated` socket → TrendingPanel refresh รูปพื้นหลัง Real-time
  - **Race Condition Fix**: ใช้ `resolveOnce()` + `clearTimeout()` ป้องกัน double-resolve ใน `thumbnail-service.js`
  - **Path Safety (JSON Array)**: ส่งไฟล์ path เป็น JSON Array แทน comma-separated string ระหว่าง JS→Python ป้องกัน path-with-comma bug
  - **Single Image**: Resize กว้าง 400px → WebP
  - **Multi-Image (2-5 ภาพ)**: Blurred Background + Photo Album Stack (400×300px) → WebP — รองรับ Portrait/Landscape ทุก aspect ratio
  - **Video Frame Extraction**: วิดีโอ HLS ได้ thumbnail จาก FFmpeg Extract Frame ที่วินาทีที่ 1 หลัง Transcode เสร็จ
  - **Bunny CDN Upload (Optional)**: Worker อัปโหลด thumbnail ไป Bunny.net ถ้า `BUNNY_API_KEY` ตั้งค่าแล้ว → CDN URL ใช้ได้ทั่วโลก ไม่ผูกกับ LAN
  - **Thumbnail Queue**: Concurrency 4, Retry 3 ครั้ง Exponential Backoff (2s/4s/8s), เก็บ log งานสำเร็จ 100 ชิ้นสุดท้าย
- **Dynamic Admin Watermarking (Server-side & Forensic Tracking — New 2026-05-11)**: ระบบประทับลายน้ำและ Forensic ID ลงในทุกสื่อ (วิดีโอ/ภาพถ่าย) เพื่อป้องกันการละเมิดลิขสิทธิ์และสืบหาต้นตอภาพหลุด:
  - **Admin Control Center**: แอดมินสามารถจัดการผ่านหน้า "จัดการลายน้ำ" ในแอป (Flutter) เพื่อเปิด/ปิด, เปลี่ยนข้อความ, อัปโหลดโลโก้ PNG, ปรับ Opacity, และเลือก Animation (Marquee, Bounce, Random) แบบ Real-time
  - **Video Watermarking (FFmpeg)**: ประทับลายน้ำแบบ Hardcode ลงในไฟล์วิดีโอ HLS ระหว่างขั้นตอน Transcoding โดยตรง รองรับทั้ง Text และ Image Overlay
  - **Image Watermarking (Sharp - Node.js)**: สำหรับภาพถ่ายในแกลลอรี่ (Thai Mhung) และภาพร้องขอเหตุฉุกเฉิน จะใช้ไลบรารี `Sharp` ประทับลายน้ำแบบ **Synchronous** ทันทีหลังขั้นตอน Face Blur ก่อนจะ Save ลง Disk เพื่อให้ภาพที่ถูก Broadcast มีลายน้ำ 100%
  - **Forensic ID Tracking**: หากเปิดใช้งาน ระบบจะฉีด `Incident ID` และ `Uploader ID` (User ID) เป็นข้อความจางๆ ไว้ที่มุมภาพโดยอัตโนมัติ เพื่อให้ระบุตัวบุคคลที่นำภาพออกไปเผยแพร่ในทางที่ผิดได้ (Traceability)
  - **Thumbnail Protection**: บูรณาการเข้ากับ `Thumbnail Queue` เพื่อให้ภาพ WebP ที่แสดงใน Trending Panel และ Gallery View ทั้งหมดมีลายน้ำประทับอยู่เสมอ
- **FFmpeg**: Transcoding เป็น HLS (รองรับทั้งวิดีโอปกติและวิดีโอที่ผ่านการทำ Face Blur แล้ว)
- **Priority Queue**: Priority 1 = Video Transcode, Priority 2 = Thumbnail Generation, Priority 3 = Watermark Processing (Sync/Async)
- **Auto Cleanup**: ลบไฟล์ชั่วคราวและไฟล์วิดีโอต้นฉบับหลังประมวลผลและอัปโหลดเสร็จสิ้น

## UI/UX Implementation Tips (Standard for Figma Design)

- **Map Integration**: ใช้ `video_gps_tracks` เพื่อขยับ Marker บนแผนที่ตาม `currentPosition` ของวิดีโอ
- **Donation Integration**:
  - เมื่อคลิกปุ่ม "บริจาค" ในหน้าวิดีโอ ให้ตรวจสอบ `donation_request_id` จากวิดีโอนั้น
  - เรียกใช้ `DonationRepository.getRequests()` เพื่อดึงข้อมูลปลายทาง และเริ่ม Flow การโอนเงิน/บริจาคเดิมที่มีอยู่
  - หลังการบริจาคสำเร็จ ให้ส่ง Event ผ่าน **Socket.io** เพื่อให้ระบบ Real-time Interactions แสดงข้อความขอบคุณหรือยอดรวมอัปเดตทันที
- **Glassmorphism Overlay**: ใช้ `BackdropFilter` ใน Flutter ซ้อนทับหน้าจอวิดีโอเพื่อให้ได้ลุคตาม Figma
- **Emergency Priority**: ในหน้า Dashboard ของเจ้าหน้าที่ วิดีโอประเภท `emergency` ต้องแสดงผลโดดเด่นและเข้าถึงง่ายที่สุด
- **Floating Back Button Strategy**:
  - **Layering**: ต้องวางไว้ที่ Layer บนสุดของ `Stack` หลัก (เหนือทั้ง Map และ UI Overlay) เพื่อป้องกันวิดีโอบัง
  - **Visibility Logic**:
    - แสดงผลเมื่อเปิดเครื่องมือควบคุม (`isUiVisible == true`)
    - **ซ่อนอัตโนมัติ** เมื่ออยู่ในโหมดแจ้งเหตุ (`selectedTab == 2`) หรือโหมดไทยมุงแจ้งเหตุ (`isThaiMhungReporting == true`) เพื่อไม่ให้รบกวนหน้ากล้อง
  - **Navigation**: ใช้สำหรับการย้อนกลับ (Standard Back Navigation) ไปยังหน้าก่อนหน้า

## Environment Variables

```env
# Database
DB_HOST=localhost
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=<password>
DB_PORT=5432

# Server
PORT=3000

# External Storage path (MANDATORY: MUST POINT TO EXTERNAL DRIVE)
TEMP_VIDEO_PATH=/Volumes/PostgreSQL/sheserved_videos

# Server Network
# Phase 1 (ผ่าน Caddy Reverse Proxy)
# LOCAL_API_URL ต้องชี้ไปที่ Caddy endpoint ไม่ใช่ Node.js port 3000 โดยตรง
LOCAL_API_URL=http://192.168.X.X:8080

# Bunny.net
BUNNY_API_KEY=<your_api_key>
BUNNY_STORAGE_ZONE=<your_storage_zone>
BUNNY_CDN_URL=<your_cdn_url>

# Config
MAX_CONCURRENT_TRANSCODES=2
REDIS_URL=redis://localhost:6379

# Supabase (MANDATORY for Emergency Health & Background Services)
# ต้องใช้ SERVICE_ROLE key เท่านั้น — ห้ามใช้ anon key เด็ดขาด
# รับค่าได้จาก: Supabase Dashboard → Settings → API → Project API keys → service_role
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service_role_key_from_dashboard>
```

---

## 🔧 Network & Configuration Runbook

> บันทึก ณ วันที่ 2026-05-07 — สร้างขึ้นจากปัญหาที่เกิดขึ้นจริง — ต้องเปิดอ่านและปฏิบัติตามทุกครั้งที่เปลี่ยนสถานที่ทำงานหรือเครือข่าย WiFi

---

### 🚨 Checklist: เมื่อเปลี่ยน Network / IP Address

**ปัญหาที่จะเกิดถ้าไม่ทำ**: การ์ดเหตุการณ์จะแสดงพื้นหลังเป็นสีดำ (thumbnail โหลดไม่ได้) เพราะ URL ใน DB ยังชี้ไป IP เก่า

#### ขั้นตอนที่ 1 — ตรวจสอบ IP ปัจจุบัน
```bash
# บน macOS (เครื่องหลัก)
ipconfig getifaddr en0   # WiFi
ipconfig getifaddr en1   # Ethernet / USB
```
> ใช้ IP ที่ device อื่น (iPhone/iPad) ในวงเดียวกันสามารถเข้าถึงได้ และให้จดไว้คู่กับ Caddy port `8080`

#### ขั้นตอนที่ 2 — อัปเดต Flutter App Config
```dart
// lib/config/app_config.dart
static const String mainMachineIp = '192.168.X.X:8080'; // ← เปลี่ยนตรงนี้ (IP/Host + Caddy port)
```
> **หมายเหตุ**: `bestThumbnailUrl` getter ใน `video_models.dart` จะ auto-normalize URL เก่าให้ชี้ไปที่ Caddy endpoint นี้เสมอ

#### ขั้นตอนที่ 3 — อัปเดต Server Environment
```bash
# websocket-server/.env
LOCAL_API_URL=http://192.168.X.X:8080  # ← เปลี่ยนตรงนี้
```

#### ขั้นตอนที่ 4 — Restart Node.js Server + Start Caddy
```bash
cd websocket-server
npm run dev

# terminal อีกอันสำหรับ reverse proxy
./start-caddy.sh
```
> ตรวจสอบ log ให้แน่ใจว่า Node.js รันที่ `:3000` และ Caddy รันที่ `:8080`

#### ขั้นตอนที่ 5 — ทดสอบ (Optional)
```bash
# จาก device อื่นในวง
curl http://192.168.X.X:8080/api/videos/emergency/list
# ต้องได้ JSON response ไม่ใช่ connection refused
```

---

### 📋 ไฟล์ทั้งหมดที่ต้องแก้เมื่อเปลี่ยน IP

| ไฟล์ | ค่าที่ต้องแก้ | หมายเหตุ |
|------|--------------|----------|
| `lib/config/app_config.dart` | `mainMachineIp` | Flutter auto-normalize URL เก่าใน DB ให้ชี้ไป Caddy (`:8080`) |
| `websocket-server/.env` | `LOCAL_API_URL` | URL ที่ Server ใช้ generate thumbnail URL ผ่าน Caddy |
| `websocket-server/start-caddy.sh` | Caddy startup script | ใช้ `Caddyfile.dev` สำหรับ Phase 1 (`:8080`) |
| `websocket-server/Caddyfile.dev` | Caddy dev config | bind port `8080` โดยไม่ต้อง sudo |

> **ไม่ต้องแก้**: DB records, ไฟล์ thumbnail ที่มีอยู่ — `_normalizeLocalUrl()` จัดการให้อัตโนมัติ

---

### 📁 Thumbnail Storage Architecture (Updated 2026-05-07)

ระบบใช้ **2 storage location** สำหรับ thumbnail ด้วยเหตุผลที่ต่างกัน:

| Location | Path | วัตถุประสงค์ | อายุ |
|----------|------|------------|------|
| **Temp** | `temp/videos/[id]/` | ไฟล์ thumbnail ที่ generate ระหว่างประมวลผล | ชั่วคราว — ถูก cleanup |
| **Persistent** | `uploads/thumbnails/[id]/` | ไฟล์ thumbnail สำหรับแสดง UI ถาวร | **ถาวร — ไม่ถูก cleanup** |
| **CDN** | `https://[zone].b-cdn.net/...` | Global delivery (ถ้า Bunny.net ตั้งค่า) | ถาวรบน CDN |

**URL Pattern ที่ถูกต้อง:**
```
# Local (LAN only, ผ่าน Caddy Phase 1)
http://192.168.X.X:8080/uploads/thumbnails/[incidentId]/thumb_[id].webp?t=[timestamp]

# CDN (Global)
https://[storage-zone].b-cdn.net/thumbnails/[incidentId]/thumb_[id].webp
```

> ⚠️ **สาเหตุที่รูปหาย**: URL เก่าชี้ไป `temp/videos/` ซึ่งถูก cleanup แล้ว URL ใหม่ทั้งหมดจะชี้ไป `uploads/thumbnails/` แทน

---

### 🔄 IP Normalization — กลไกป้องกันอัตโนมัติ

ระบบมี **auto-normalization** ที่ Flutter side เพื่อป้องกันรูปเสียเมื่อ IP เปลี่ยน และให้ทุกจุดใช้ URL pipeline เดียวกัน:

```dart
// lib/features/video/models/video_models.dart
String? get bestThumbnailUrl {
  // บังคับใช้ภาพจากไทยมุง (photoUrls) ก่อน ถ้ามี ค่อย fallback ไปใช้ thumbnailUrl
  final raw = photoUrls.isNotEmpty ? photoUrls.first : thumbnailUrl;
  return _normalizeLocalUrl(raw);
}

static String? _normalizeLocalUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('https://')) return url; // CDN — ไม่ต้อง normalize
  // Replace IPv4/port เก่าด้วย Caddy endpoint ปัจจุบัน
  return url.replaceFirst(
    RegExp(r'http://\d+\.\d+\.\d+\.\d+(:\d+)?'),
    'http://${AppConfig.mainMachineIp}',
  );
}
```

**ผลลัพธ์**: แม้ DB เก็บ URL ด้วย IP/port เก่า `192.168.0.116:3000` — getter จะ return `192.168.1.111:8080/...` ให้อัตโนมัติ โดยต้องอัปเดตแค่ `AppConfig.mainMachineIp` เพียงจุดเดียว

> ✅ จุดที่ใช้ pipeline นี้ร่วมกันแล้ว: trending cards, Thai Mhung gallery, fullscreen overlay/lightbox, photo detail dialog และ video player image fallback
> ✅ `ensureFullUrl()` และตัวตรวจจับไฟล์ภาพใน player รองรับทั้ง URL แบบ absolute, relative path และ URL ที่มี query string (`?t=...`)

---

### ⚡ Quick Commands Cheatsheet

```bash
# ดู IP ปัจจุบัน
ipconfig getifaddr en0

# เริ่ม server
cd websocket-server && npm run dev

# เริ่ม reverse proxy (Phase 1)
cd websocket-server && ./start-caddy.sh

# ตรวจสอบ thumbnail files
ls websocket-server/uploads/thumbnails/

# ดู URL ใน DB ว่าชี้ไป IP อะไร (ต้อง psql)
psql -U postgres -d sheserved -c \
  "SELECT id, LEFT(thumbnail_url,60) FROM videos WHERE type='emergency' LIMIT 5;"

# ตรวจ API response จริง
curl -s http://localhost:8080/api/videos/emergency/list | python3 -c \
  "import sys,json; [print(v.get('thumbnail_url','(null)')[:70]) for v in json.load(sys.stdin)[:5]]"
```

---

## Cost Estimation

### Bunny.net (สำหรับประเทศไทย)
- **Storage**: $0.01/GB/เดือน
- **Bandwidth**: $0.005/GB
- **ตัวอย่าง**: 100GB storage + 1TB bandwidth/เดือน = $1 + $5 = **$6/เดือน**

### Google Maps (Mobile Only)
- **Maps SDK for Android & iOS**: ฟรีไม่จำกัดจำนวนครั้ง (Unlimited)
- **Maps JavaScript API (Web)**: ป้องกันไม่ให้เปิดใช้งานเพื่อหลีกเลี่ยงค่าใช้จ่าย ($7/1,000 loads)
- **ค่าใช้จ่ายรายเดือน**: **$0** (ภายใต้การจำกัดการใช้งานเฉพาะแอปมือถือ)

### Self-hosted (FFmpeg, PostgreSQL, Queue, Face Blur AI)
- **ค่าใช้จ่าย**: $0 (รันบนเครื่องหลัก)
- **Face Blur AI (`deface`)**: เป็นไลบรารี Open Source ฟรี 100% ไม่เสียค่าใช้งาน API แต่จะใช้ Computing Power (CPU/GPU) ของเครื่องเซิร์ฟเวอร์ค่อนข้างสูง หากในอนาคตมีผู้ใช้จำนวนมากอาจต้องพิจารณาอัปเกรดสเปคเครื่องหรือเปลี่ยนไปใช้ Cloud API ที่คิดตามการใช้งานจริง (Pay-per-use)

### Firebase Cloud Messaging (FCM)
- **ค่าใช้จ่าย**: **$0** (FCM เปิดให้ใช้งานฟรีสำหรับการส่ง Push Notification ไปยัง Mobile Devices โดยไม่มีค่าใช้จ่ายในระดับการใช้งานทั่วไป)

## Cost Prevention: ป้องกันค่าใช้จ่าย Google Maps (Web)

เพื่อให้แน่ใจว่าจะไม่มีค่าใช้จ่ายจากการเรียกใช้บน Web App ให้ดำเนินการดังนี้บน [Google Cloud Console](https://console.cloud.google.com/):

1. **เปิดใช้งานเฉพาะ API ที่จำเป็น**:
   - ✅ เปิดใช้งาน: `Maps SDK for Android`
   - ✅ เปิดใช้งาน: `Maps SDK for iOS`
   - ❌ **ปิดการใช้งาน**: `Maps JavaScript API` (สำคัญมาก! เพื่อป้องกันไม่ให้นำ Key ไปใช้โหลดบน Web)
2. **ตั้งค่า API Key Restrictions (Application restrictions)**:
   - สร้าง API Key แยกสำหรับ Android และ iOS
   - **Android Key**: จำกัด (Restrict) ให้ใช้ได้เฉพาะกับ Android App โดยระบุ `Package name` และ `SHA-1 certificate fingerprint`
   - **iOS Key**: จำกัดให้ใช้ได้เฉพาะกับ iOS App โดยระบุ `Bundle ID`
3. **API Restrictions**:
   - จำกัดให้ Key ทั้งสองสามารถเรียกใช้ได้เฉพาะ `Maps SDK for Android` และ `Maps SDK for iOS` เท่านั้น

## Development Setup

### เครื่องหลัก (Main Machine)
- ✅ Flutter SDK
- ✅ Node.js
- ✅ PostgreSQL
- ✅ FFmpeg
- ✅ Redis (หากเลือกใช้ Bull Queue) หรือ local memory queue
- ✅ หน้าจอ
- ✅ GitHub sync

### ไม่ต้อง
- ❌ เครื่องที่ 2 (Client Machine) ไม่ต้องเปิดระหว่างพัฒนา
- ❌ SSH หรือ remote connection ไม่จำเป็น

## Implementation Files

### Backend
- `websocket-server/routes/video.js` - Video upload routes
- `websocket-server/services/video-service.js` - Video processing service + Queue logic
- `websocket-server/services/socket-service.js` - WebSocket progress updates

### Flutter
- `lib/services/video_service.dart` - Video API client + Polling logic (fallback)
- `lib/services/socket_service.dart` - Socket.io listener for progress

## Grip/Safety Net (Reliability System)

เพื่อความมั่นใจว่าระบบจะทำงานได้อย่างราบรื่นในทุกสถานการณ์ (เครื่องหลัก/เครื่องรอง/Offline/Hybrid) ได้มีการเพิ่มมาตรการความปลอดภัยดังนี้:

### 1. Local-First Hybrid Data Strategy
- **Priority Fetching**: แอปจะพยายามดึงข้อมูล (Video List, GPS, Interactions) จาก Local API (เครื่องหลัก) ก่อนเสมอ หากไม่สำเร็จใน 3 วินาที จะสลับไปใช้ Supabase Cloud อัตโนมัติ
- **Local Interactions**: เมื่อรันในโหมด Local แอปจะบันทึกยอด Views/Likes เข้าสู่ PostgreSQL ที่เครื่องหลักโดยตรง เพื่อแก้ปัญหา Foreign Key Error บน Cloud เมื่อวิดีโอยังไม่ได้ซิงค์

### 2. Robust Data Parsing (Safe Parsing)
- **Flex-Type Handling**: ระบบ Model ใน Flutter (Video, GPS, Interaction) ถูกปรับจูนให้รองรับข้อมูลทั้งที่เป็น String, int, double หรือ BigInt จากแหล่งที่มาที่ต่างกัน (PostgreSQL vs Supabase JSON)
- **UI Crash Prevention**: หากข้อมูลบางส่วนขาดหายหรือผิดประเภท ระบบจะมีค่า Default เสมอ เพื่อป้องกันหน้าจอ UI ยุบตัวหรือค้าง

### 3. Adaptive Assets Management
- **Smart Cleanup**: ระบบใน Node.js จะตรวจเช็คที่อยู่ไฟล์ (URL) ก่อนลบทิ้ง หากเป็นการใช้งานแบบ Local Server ไฟล์ HLS จะถูกเก็บรักษาไว้ไม่ให้ถูกลบ เพื่อให้เครื่องลูกสตรีมไปเล่นได้ตลอดเวลา
- **Local Network Permissions**: เพิ่มการอนุญาต HTTP สตรีมมิ่งใน `Info.plist` (iOS) และ `AndroidManifest` (Android) สำหรับ IP ภายในเครือข่าย WiFi เดียวกัน

### 4. Layout Resilience
- **Dynamic Flexible UI**: ปรับปรุงหน้า `EmergencyLivePage` ให้ใช้ `LayoutBuilder` และ `Positioned` เพื่อให้หน้าจอปรับขนาดตามสัดส่วนวิดีโออัติโนมัติ
- **Overflow Protection**: ใช้ `Flexible` และ `TextOverflow.ellipsis` ในทุกจุดที่มีข้อความ dynamic ป้องกันแถบลายทาง (Yellow/Black lines) บนอุปกรณ์ที่มีความกว้างจำกัด

### 5. Network Sync Persistence
- **Auto-Retry**: ระบบ WebSocket และ API มีกลไกการเชื่อมต่อใหม่ (Reconnection) อัตโนมัติเมื่อ WiFi กลับมาใช้งานได้
- **Conflict Resolution**: การบันทึกพิกัด GPS จะใช้ระบบ Timestamp Offset เพื่อให้มั่นใจว่าเส้นทางบนแผนที่จะตรงกับช่วงเวลาในวิดีโอเสมอ แม้การส่งข้อมูลจะดีเลย์

## Responder Response System (การตอบรับความช่วยเหลือ)

ระบบที่ออกแบบมาเพื่อให้ "อาชีพที่เกี่ยวข้อง" สามารถมองเห็นและกดตอบรับช่วยเหลือเหตุการณ์ได้ตามความเชี่ยวชาญ

### 1. Role-Category Matching (การจับคู่สิทธิอาชีพ)
กำหนดให้เฉพาะอาชีพที่ตรงกับหมวดหมู่เหตุการณ์เท่านั้นที่จะเห็นปุ่ม "ตอบรับช่วยเหลือ" (Accept Help):

| หมวดหมู่เหตุการณ์ (Category) | อาชีพที่มีสิทธิ (Eligible Professions) |
| :--- | :--- |
| **เจ็บป่วยฉุกเฉิน / อุบัติเหตุ** | หมอ, พยาบาล, กู้ชีพ, อาสาสมัครสาธารณสุข |
| **อัคคีภัย / เพลิงไหม้** | นักดับเพลิง, กู้ภัย, อาสาสมัครป้องกันภัย |
| **เหตุอาชญากรรม / ทะเลาะวิวาท** | ตำรวจ, เจ้าหน้าที่รักษาความปลอดภัย |
| **ขอความช่วยเหลือทั่วไป** | อาสาสมัครจราจร, จิตอาสา, ทุกอาชีพ |

### 2. UI/UX Flow สำหรับอาชีพ (Responder Flow)
1.  **Alert Phase**: เมื่อมีการแจ้งเหตุใหม่ที่ตรงกับอาชีพ จะมี Overlay หรือ Notification ปรากฏขึ้นพร้อมระบุระยะทางจากพิกัดปัจจุบัน
2.  **Screening Phase**: ผู้ใช้ (อาชีพ) สามารถกดดูวิดีโอสด (Live Video) และพิกัดบนแผนที่เพื่อประเมินสถานการณ์ก่อนตัดสินใจ
3.  **Acceptance Phase**: ปรากฏปุ่ม **"ฉันพร้อมช่วยเหลือ" (I'm ready to help)** แบบเด่นชัด
4.  **Operational Phase**:
    - เมื่อกด "ตอบรับ" ระบบจะเริ่มส่งพิกัด GPS ของอาชีพ (Responder) ไปยังผู้แจ้งเหตุทันที
    - หน้าจอเปลี่ยนเป็นโหมดนำทาง (Navigation) และแสดง ETA (เวลาที่คาดว่าจะถึง)
5.  **Completion Phase**: เมื่อถึงจุดเกิดเหตุ สามารถกด "ถึงที่เกิดเหตุแล้ว" เพื่อสรุปภารกิจ

### 3. Database & Tracking logic
- **Table: `incident_responses`**: เก็บข้อมูลว่าใคร (user_id) ตอบรับช่วยเหล้าวิดีโอไหน (video_id) และสถานะปัจจุบัน (en_route, arrived, completed)
### 4. Integration: Donation Management (หน้าจัดการระบบบริจาค)
เพื่อให้เข้าถึงระบบช่วยเหลือได้ง่ายสำหรับอาชีพที่ทำงานอยู่หน้าจอ จัดการระบบบริจาค:
1.  **Tab "ช่วยเหลือฉุกเฉิน"**: เพิ่มแถบที่ 5 ในหน้าจัดการระบบบริจาค
2.  **Incident List**: กรองวิดีโอประเภท `emergency` ที่ยังไม่จบภารกิจ และตรงกับอาชีพของผู้ใช้
3.  **One-Click Entry**: เมื่อกดปุ่ม "ฉันพร้อมช่วยเหลือ" ระบบจะ:
    - บันทึกยอดการตอบรับเข้า `incident_responses`
    - **Redirect ทันที**: พาย้ายหน้าไปยัง `EmergencyLivePage` เพื่อเข้าสู่โหมดหน้าจอศูนย์สั่งการ (Command Center) พร้อมเปิดวิดีโอเหตุการณ์นั้นทันที

## Real-time Alert & Work Queue Issues (Fix Summary - 2026-03-11)

สรุปปัญหาและการแก้ไขระบบแจ้งเตือนเหตุฉุกเฉินและคิวงาน (Work Queue) เพื่อให้ระบบทำงานได้เสถียร 100%

### 1. สาเหตุหลักของปัญหา (Root Causes)
- **Self-Filtering Logic**: เซิร์ฟเวอร์เดิมมีโค้ดกรองไม่ให้ส่งแจ้งเตือนกลับหาตัวเอง (`targetId !== userId`) ทำให้หากมีผู้ใช้งานคนเดียวที่เป็นทั้งคนแจ้งและอาชีพกู้ภัย (เช่น ตอนทดสอบ) จะไม่มีใครได้รับแจ้งเตือนเลย
- **WebSocket Race Condition**: ในหน้า `EmergencyLivePage` มีการเรียกคำสั่งส่ง Alert ทันทีหลังอัปโหลดรูป/วิดีโอเสร็จ โดยที่ WebSocket อาจยังเชื่อมต่อไม่สมบูรณ์ ทำให้ข้อมูลสูญหาย
- **Static Work Queue**: หน้าจัดการระบบบริจาค (Admin) โหลดข้อมูลใบงานช่วยเหลือฉุกเฉินครั้งเดียวใน `initState` ทำให้ใบงานใหม่ไม่แสดงผลโดยอัตโนมัติหากไม่กด Refresh เอง
- **Category Mismatch**: ID ของหมวดหมู่ (Category) ในเครื่อง Local กับ Cloud ไม่ตรงกัน ทำให้เวลา Server ค้นหาว่าต้องแจ้งเตือนอาชีพไหนแล้วไม่พบข้อมูล จึงไม่มีการส่ง Alert

### 2. วิธีการแก้ไข (Solutions)
- **Server Broadcast Optimization**: 
    - ปรับปรุงให้ Server ส่งแจ้งเตือนหาทุกคนที่เกี่ยวข้องรวมถึงตัวเอง (ในช่วงพัฒนาระบบ)
    - เพิ่มระบบ **Fallback Notification** หากหาหมวดหมู่ไม่เจอใน Local DB ให้ทำการแจ้งเตือนไปยังอาชีพกู้ภัย (Rescuer) ทุกคนทันที
- **Flutter Connection Guard**: 
    - เพิ่มฟังก์ชัน `_ensureWebSocketConnected()` เพื่อตรวจสอบและรอการเชื่อมต่อ WebSocket ให้พร้อมก่อนที่จะเรียกใช้ `sendEmergencyAlert`
    - เพิ่ม Debug Logging ทั้งฝั่ง Client และ Server เพื่อติดตามเส้นทางการเดินทางของข้อมูล Alert
- **Auto-Refresh System**: 
    - เพิ่มการดักฟัง (Listen) อีเวนต์ `emergency-notification` ในหน้าจัดการระบบบริจาคเพื่อให้รีโหลดข้อมูลทันทีเมื่อมีเหตุใหม่
    - เพิ่ม **Polling Timer** (ตาข่ายสำรอง) ให้ Refresh ข้อมูลทุกๆ 10 วินาที เพื่อป้องกันเหตุการณ์แจ้งเตือนตกหล่นจากปัญหา Network

### 3. แนวทางป้องกันในอนาคต (Prevention)
- **Robust Reconnection**: ตั้งค่า WebSocket ให้มีการเชื่อมต่อใหม่ (Auto-reconnect) อัตโนมัติ (10 attempts, delay 2s)
- **Log-First Development**: รักษา Debug Logging ไว้ในจุดยุทธศาสตร์ (Upload, Alert Send, Alert Receive) เพื่อให้ตรวจสอบปัญหาได้จาก Console ทันที
- **Hybrid Refresh**: สำหรับข้อมูลระดับวิกฤต (Emergency) ให้ใช้ระบบ Stream (WebSocket) ควบคู่กับ Periodic Polling เสมอเพื่อให้มั่นใจว่าข้อมูลหน้าจอตรงกับความจริง (Source of Truth)
## Thai Mhung (Community Support System) (New - 2026-03-13)

ระบบที่ออกแบบมาให้ผู้ใช้ทั่วไป (ที่ไม่ใช่อาสาอาชีพ) สามารถสนับสนุนการรายงานเหตุการณ์ในพื้นที่รอบข้าง (Crowdsourcing)

### 1. Core Logic & Visibility
- **Dynamic Visibility & Eligibility**: 
    - ปุ่ม "ไทยมุง" จะปรากฏขึ้นเฉพาะเมื่อผู้ใช้อยู่ในเหตุการณ์เท่านั้น
    - **Location Requirement**: ผู้ใช้ต้องเปิดระบบระบุตำแหน่ง (GPS) ของอุปกรณ์
    - **Proximity Filter**: ผู้ใช้ต้องอยู่ในระยะห่างจากจุดเกิดเหตุ **ไม่เกินรัศมี (alertRadius)** ที่ผู้ใช้กำหนดเองในหน้า Profile 
    - **Distance Alert**: หากโหมดไทยมุงถูกเรียกใช้งานแต่ระยะห่างเกินรัศมีที่กำหนด ระบบจะแจ้งเตือนให้ผู้ใช้ทราบว่า "คุณอยู่ไกลจากจุดเกิดเหตุเกินไปสำหรับการทำหน้าที่ไทยมุง"
    - **In-app Entry (HomeHeaderSection Badge)**: ใช้พื้นที่ด้านขวาของ `HomeHeaderSection` ในหน้า Home เพื่อแสดง Badge แจ้งเตือนเหตุการณ์ใกล้ตัวแบบเงียบ (Passive Notification) สำหรับผู้ใช้ทั่วไปที่ไม่ได้อยู่ใน "อาชีพจิตอาสา" ที่รับผิดชอบโดยตรง โดยจะคำนวณจาก **รัศมี (alertRadius)** ที่ผู้ใช้ตั้งไว้
    - **One-Click Navigation**: เมื่อกดที่ Badge แจ้งเตือนใน `HomeHeaderSection` ระบบจะนำผู้ใช้เข้าสู่หน้า `EmergencyLivePage` ทันที โดยไม่ส่งผลกระทบต่อตำแหน่งของ Consultation Widget
- **Crowd Support Display**: แสดงจุดหรือจำนวน "ไทยมุง" บนแผนที่รอบจุดเกิดเหตุ เพื่อให้เจ้าหน้าที่เห็นความหนาแน่นของพยานและผู้ช่วยในพื้นที่

### 2. Community Reporting (Thai Mhung Mode)
เมื่อผู้ใช้อยู่ในโหมด "ไทยมุง" และกดเมนูนี้ จะปรากฏ UI คล้ายกับ `IncidentReportWidget` แต่ปรับเปลี่ยนดังนี้:
- **Photo Only**: ปิดความสามารถในการถ่ายคลิปวิดีโอ ให้เหลือเพียงการถ่ายภาพนิ่งเท่านั้น
- **Quota Limit**: จำกัดการส่งภาพได้สูงสุด **3 ภาพ ต่อ 1 เหตุการณ์ ต่อคน**
- **Countdown Display**: มี UI แสดงตัวนับจำนวนภาพที่เหลืออยู่ (เช่น "เหลือโควตาถ่ายภาพ 2/3")

### 3. Thai Mhung Gallery (Vertical Ruler View)
ระบบออกแบบแกลลอรี่ภาพจาก "ไทยมุง" ให้แสดงผลบริเวณด้านข้างวิดีโอ Live PIP (มุมบนซ้าย) เพื่อจัดกลุ่มข้อมูลเหตุการณ์ไว้ด้วยกันและป้องกันการบังพื้นที่แผนที่หลัก (Decluttered UI) ดังนี้:

- **ตำแหน่งจัดวาง**: อยู่บรรทัดฝั่งขวาขนาบข้างวิดีโอ Live (Live View Widget) โดยมีความสูงเท่ากับตัววิดีโอพอดี
- **Wheel Carousel (Ruler Picker)**: ออกแบบในลักษณะ ListWheelScrollView หมุนขึ้นลงคล้ายกับหน้าปัดทรงกระบอก (3D Perspective) ทำให้ประหยัดพื้นที่บนหน้าจอ และให้ความรู้สึกทันสมัย
- **Real-Time Flashing**: เมื่อมีภาพใหม่จากไทยมุงอัปโหลดเข้ามา แผ่นภาพนั้นจะถูกแทรกเข้ามาใน Carousel พร้อม Effect **กระพริบกรอบสีเหลือง/ป้ายคำว่า "หมูงใหม่"** เพื่อดึงดูดสายตาเจ้าหน้าที่ที่กำลังโฟกัสวิดีโอหลักทันที
- **Trending Card Background Override**: ภาพหน้าปก (พื้นหลัง) ของการ์ดเหตุการณ์ในกล่องยอดนิยม (Trending Panel) จะถูกแทนที่ด้วยภาพแรกจากไทยมุงเสมอ หากมีภาพจากไทยมุงในระบบ เพื่อให้ผู้ใช้เห็นสถานการณ์ล่าสุดจากมุมมองของพยานในพื้นที่ หากยังไม่มีภาพจากไทยมุง จึงจะใช้ภาพหน้าปกวิดีโอจากผู้แจ้งเหตุตามปกติ
- **Privacy Enforcement**: มีระบบเบลอภาพอัตโนมัติ (Image Filter Blur) และขึ้นไอคอนรูปโล่ หากผู้ใช้ไม่ใช่ Responder ตัวจริง เพื่อคุ้มครองสิทธิส่วนบุคคลของภาพผู้ประสบเหตุ
- **Lightbox Preview**: เมื่อผู้ใช้มีสิทธิและแตะที่รูปภาพ ภาพจะขยายเต็มหน้าจอแบบ Popup (Interactive Viewer) เพื่อช่วยวิเคราะห์การทำงาน

### 4. Yield Way Feedback System (ระบบคัดกรองและแจ้งเตือนการให้ทาง - อัปเดตใหม่)
- **การเข้าถึงและการตั้งค่า (Access & Configuration):**
  - **Standard Tab:** แถบ "จิตอาสา" จะแสดงผลเป็นค่าเริ่มต้นสำหรับผู้ใช้งานทุกคนในหน้า Profile เพื่อให้สามารถเข้าถึงการตั้งค่าความปลอดภัยและชุมชนได้ตลอดเวลา
  - **Yield Way Toggle:** ผู้ใช้งานสามารถเปิด/ปิดการรับแจ้งเตือน "ช่วยเปิดทางให้รถฉุกเฉิน" ได้โดยตรงในแถบ "จิตอาสา"
  - **Dynamic UI Control:** เมื่อผู้ใช้ปิด Toggle ใดๆ ระบบจะซ่อนเครื่องมือกำหนดรัศมี (Radius Slider) ของฟีเจอร์นั้นโดยอัตโนมัติ เพื่อลดความซับซ้อนของ UI
  - **Database Integration:** บันทึกสถานะ `is_yield_way_enabled` และ `is_thai_mhung_enabled` พร้อมรัศมีที่เกี่ยวข้องลงในตาราง `users` ของฐานข้อมูลหลักเพื่อให้การตั้งค่าคงอยู่ถาวร
  - **ประวัติการให้ทาง (Yield History):** แสดงประวัติและจำนวนครั้งที่เคยให้ทาง เพื่อสะสมเป็น "แต้มบุญ" ใช้ประโยชน์ในอนาคต (แสดงในแถบจิตอาสา)
- **ระบบคัดกรองผู้ให้ทางตามเส้นทางจริง (Route-based Filtering - Type B):**
  - เมื่อจิตอาสากด **"รับเหตุ"** แอปฝั่งจิตอาสาจะต้องคำนวณและส่ง **Route Polyline** ไปยัง Server
  - ระบบจะคำนวณจาก **เส้นทางการเดินทางของจิตอาสาทุกคน (Combined Routes)** ที่กำลังเข้าช่วยเหลือในเหตุการณ์นั้น
  - Server จะคัดกรองผู้ใช้โดยใช้เงื่อนไข **Type B**:
    1. ผู้ใช้ต้องเปิดใช้งาน `is_yield_way_enabled`
    2. ผู้ใช้ต้องอยู่ภายใน "รัศมีจากจุดเกิดเหตุ" (ตามที่ตั้งค่าไว้) **และ** มีตำแหน่งอยู่บนหรือใกล้เคียงเส้นทางของจิตอาสาท่านใดท่านหนึ่งที่กำลังมุ่งหน้าไป
    3. **Reporter Exclusion:** ระบบจะไม่ส่งการแจ้งเตือนให้ทางแก่ผู้แจ้งเหตุ (Reporter/Victim) ของเหตุการณ์นั้นๆ เพื่อป้องกันการรบกวนขณะกำลังขอความช่วยเหลือ
- **ช่องทางการแจ้งเตือน (Notification Flow):**
  - ระบบแสดงการแจ้งเตือนแบบ "ช่วยเปิดทางให้รถฉุกเฉิน" ที่ **Headsector (มุมขวาบน) ในหน้า Home**
  - ผู้ใช้สามารถกดปิด (Dismiss) แต่ละการแจ้งเตือนได้
- **การโต้ตอบและแสดงผล (Interaction & Map Dialog):**
  - เมื่อผู้ใช้กดที่การแจ้งเตือนจาก Headsector จะนำเข้าสู่ `EmergencyLivePage` พร้อมแสดง **Dialog แผนที่** ทันที
  - แผนที่จะแสดง **ทิศทางที่รถฉุกเฉินกำลังวิ่งมา** (รวมทุกเส้นทางของจิตอาสา) เพื่อให้ผู้ใช้รู้ว่าตนอยู่บนเส้นทางและสามารถหลบได้ถูกฝั่ง
  - ภายใน Dialog จะมี 2 ตัวเลือก:
    1. **"ช่วยเปิดทาง" (Yield Way):** เมื่อกดแล้ว จะพับ Dialog เก็บ และให้ผู้ใช้คงอยู่ในหน้า Live ของเหตุการณ์นั้น พร้อมบันทึกประวัติ
    2. **"ไม่สะดวก" (Decline/Dismiss):** เมื่อกดแล้ว จะปิดหน้า Emergency กลับไปที่หน้า Home และลบการแจ้งเตือนของเหตุการณ์นี้ทิ้งไป
  - **Live Mode Animation:** เมื่อมีผู้กดปุ่มให้ทางสำเร็จ แผนที่ในหน้า Live Emergency ของทุกคนจะแสดง **แอนิเมชันพิเศษ** (เช่น พัลส์แสงหรือไอคอนกระพริบ) เพื่อบ่งบอกให้ผู้ใช้ทั่วไปและจิตอาสาได้รับรู้ว่ามีการให้ทางเกิดขึ้นบนเส้นทางนั้น
- **การประมวลผลหลังบ้าน (Backend Calculation):**
  - เมื่อกดให้ทาง จะบันทึกลงฐานข้อมูลจริง (อาจต้องสร้างตาราง `yield_way_histories` เพื่อบันทึกใคร/เมื่อไหร่/เหตุการณ์ไหน สำหรับนำไปรวมเป็นแต้มบุญ)
  - Server เปลี่ยนจากการคำนวณเปอร์เซ็นต์ เป็นการประมวลผล **"จำนวนรวมของผู้ให้ทาง (Raw Count)"** ที่เป็นผู้ใช้บนเส้นทางของจิตอาสาทุกคนที่กำลังมุ่งหน้าไปช่วยเหลือเหตุการณ์นั้น และ Broadcast แบบ Real-time
- **แนวทางการทดสอบและจำลองเหตุการณ์ (Yield Way Mock Testing Guidelines):**
  เพื่อป้องกันปัญหาการไม่ได้รับการแจ้งเตือนระหว่างการพัฒนาหรือทดสอบ ระบบได้กำหนดข้อปฏิบัติในการจำลองเหตุการณ์ (Mocking) ไว้อย่างเคร่งครัดดังนี้:
  1. **การตั้งค่าสถานะผู้รับ (Receiver State):** ผู้ใช้ (เครื่องรับแจ้งเตือน) จะต้องเข้าไปที่ Profile -> แถบตั้งค่าจิตอาสา และเปิดสวิตช์ **"สิทธิการแจ้งเตือนให้ทาง (Yield Way)"** (`isYieldWayEnabled: true`) หากปิดไว้ Server จะละเว้นการส่งข้อมูลทันที
  2. **ความแม่นยำของพิกัดจำลอง (Location Accuracy):** ใน Emulator ต้องจำลองพิกัด (Mock GPS) ให้อยู่ **กึ่งกลางถนน** บนเส้นทางระหว่าง "จุดเริ่มต้นของจิตอาสา" และ "จุดเกิดเหตุ" โดยต้องมีระยะคลาดเคลื่อนจากเส้น Polyline จริงไม่เกิน **80 เมตร**
  3. **การกระตุ้น Event ตำแหน่ง (Location Trigger):** เมื่อกำหนดพิกัดจำลองแล้ว ต้องขยับพิกัดเล็กน้อยเพื่อให้ OS ส่งสัญญาณ GPS ล่าสุด และกระตุ้นให้ Flutter ส่ง Event `location-update` พร้อมค่า `latitude`, `longitude` ไปยัง Server หาก Server ได้รับค่าพิกัดเป็น `null` จะข้ามผู้ใช้นั้นทันที
  4. **การแยกบัญชีผู้ใช้ (Reporter Exclusion):** การทดสอบต้องใช้ **2 บัญชีที่แตกต่างกัน** อย่างชัดเจน (เครื่องจิตอาสา 1 บัญชี, เครื่องผู้ใช้ทั่วไปบนถนนอีก 1 บัญชี) เพื่อป้องกันไม่ให้เข้าข่ายเงื่อนไขการบล็อกการแจ้งเตือนตนเอง (Reporter Exclusion)

---

## Strict Alert Policy & Rejected Enhancements (Updated 2026-03-13)

เพื่อให้ระบบมีความชัดเจนและไม่สร้างความสับสนให้กับผู้ใช้ (โดยเฉพาะกลุ่มวิชาชีพ) ได้มีการกำหนดนโยบายการแจ้งเตือนดังนี้:

### 1. No Professional Fallback (ยกเลิกการให้สิทธิอัตโนมัติ)
- **นโยบาย**: ระบบจะไม่ทำการ Fallback หรือให้สิทธิ "รับแจ้งเหตุ" แก่กลุ่มวิชาชีพ (Professional Responder) โดยอัตโนมัติ หากหมวดหมู่เหตุการณ์นั้นไม่ได้มีการระบุสิทธิของอาชีพนั้นๆ ไว้อย่างชัดเจนในฐานข้อมูล
- **เหตุผล**: เพื่อป้องกันไม่ให้ผู้ใช้สับสนเกี่ยวกับขอบเขตหน้าที่ (Scope of Duty) ของตนเอง และลดความถี่ของการแจ้งเตือนที่ไม่ตรงกับความเชี่ยวชาญ

### 2. Manual Distance Control (ควบคุมระยะทางด้วยตนเอง)
- **นโยบาย**: ระบบจะไม่ทำการขยายรัศมี (Distance expansion/buffer) หรือเพิ่มตัวคูณความแม่นยำใดๆ เหนือกว่าค่า **"พื้นที่รับผิดชอบ"** ที่ผู้ใช้กำหนดเองในหน้า Profile (ทั้งในฐานะไทยมุง และในแถบจัดการอาสาสมัครสำหรับอาชีพ)
- **เหตุผล**: เพื่อให้ผู้ใช้สามารถควบคุมขอบเขตการแจ้งเหตุได้อย่างแม่นยำตามความต้องการจริง โดยเฉพาะกลุ่มวิชาชีพที่ต้องการรับงานเฉพาะในระยะที่สามารถเข้าถึงที่เกิดเหตุได้รวดเร็ว และป้องกันการแจ้งเตือนที่ถี่เกินไป

### 3. Explicit Mapping First
- ทุกการแจ้งเตือนในหน้า Home ที่เป็นแบบ Stacked Cards จะต้องผ่านการตรวจสอบความตรวจสอบความสัมพันธ์ (Relevance Check) ระหว่าง `categoryId` และ `professionId` ในตาราง `donation_categories` และต้อง **อยู่ภายในรัศมีที่ผู้ใช้กำหนด** เท่านั้น หากไม่ครบเงื่อนไข ระบบจะไม่แสดงผลการแจ้งเตือนแบบเร่งด่วน (ยกเว้นโหมดไทยมุงที่มีเงื่อนไขเฉพาะ)

## Role-Based Dual-Channel Alert System (Final Architecture — Updated 2026-03-19)

นโยบายการแยกช่องทางแจ้งเตือนเพื่อความชัดเจนตามบทบาทผู้ใช้ (Role) และความเร่งด่วนของสถานการณ์:

### 1. ช่องทางจิตอาสา (Professional Channel — Mission Call)
- **กลุ่มเป้าหมาย:** อาชีพจิตอาสาที่มี `profession_id` ตรงกับสิทธิใน `volunteer_profession_ids` ของหมวดหมู่เหตุการณ์ และ **อยู่ในพิกัดที่สามารถช่วยเหลือได้ (ตามรัศมีที่ตั้งไว้ใน Profile)**
- **การแสดงผล:** **Stacked Red Cards (ลอยทับแผนที่)**
- **ผลข้างเคียง (Side Effects):**
    - บังคับ Consultation Widget เข้าสู่ Mini Mode และชิดขอบซ้าย (`leftCenter`) ทันที
    - แผนที่ทำการ Auto-Focus ไปยังตำแหน่งเหตุการณ์
- **เป้าหมาย:** เพื่อการตัดสินใจและ "ตอบรับเหตุ" (Accept Help) ทันทีในฐานะเจ้าหน้าที่
- **เงื่อนไขโค้ด (Flutter):** `isProfessional == true && hasLocation && distance <= user.alertRadius`

### 2. ช่องทางไทยมุง (Community Channel — Passive Notification)
- **กลุ่มเป้าหมาย:** ผู้ใช้ที่เปิดสวิตช์ **"แจ้งเหตุฉุกเฉินใกล้ตัว (ไทยมุง)"** ในแถบจิตอาสาหน้า Profile และ **ไม่ใช่** Professional สำหรับเหตุการณ์นั้นโดยตรง (เพื่อป้องกันการแจ้งซ้ำซ้อนกับ Stacked Cards)
- **การแสดงผล:** **Right-side Badge ใน HomeHeaderSection**
- **ผลข้างเคียง (Side Effects):**
    - **ไม่มี** การขยับตำแหน่งของ Consultation Widget (Non-intrusive)
    - ไม่มีการ์ดสีแดงเด้งขึ้นมาบังแผนที่
- **เป้าหมาย:** เพื่อ "แจ้งให้ทราบและเชิญชวน" สนับสนุนเหตุการณ์ใกล้ตัวโดยไม่รบกวนการใช้งานปกติ
- **เงื่อนไขโค้ด (Flutter):** `user.isThaiMhungEnabled == true && !isProfessional && hasLocation && distance <= user.alertRadius`

> **หมายเหตุสำคัญ:** `video.isThaiMhungEnabled` (ค่าที่ผู้แจ้งเหตุตั้งไว้) **ไม่ได้ใช้เป็นเงื่อนไขกรองผู้รับ** เพราะเป็นสิทธิ์ฝั่งผู้รับ ไม่ใช่ผู้ส่ง — การตัดสินใจว่าจะรับแจ้งเตือนหรือไม่อยู่ที่ `user.isThaiMhungEnabled` ของผู้รับ (Recipient-First Policy)

### 3. De-duplication Rule (กฎป้องกันการแจ้งเตือนซ้ำซ้อน)
- วิดีโอหนึ่งรายการจะแสดงผลได้บน**ช่องทางเดียวเท่านั้น**ต่อผู้ใช้หนึ่งคน:
  - ถ้า `isProfessional == true` → แสดงเฉพาะ **Stacked Cards** (ไม่แสดงใน Header)
  - ถ้า `isProfessional == false` และ `user.isThaiMhungEnabled == true` → แสดงเฉพาะ **Header Badge**
  - ถ้าทั้งสองเงื่อนไขไม่ตรง → ไม่แสดงผล

### 4. ตารางสรุปการทำงาน (Alert Routing Table — Updated 2026-03-19)

| สถานะผู้ใช้ | isProfessional | isThaiMhungEnabled | อยู่ในรัศมี | UI ที่หน้า Home |
| :--- | :---: | :---: | :---: | :--- |
| **เจ้าหน้าที่ตรงสายงาน** | ✅ | any | ✅ | **Stacked Cards** เท่านั้น |
| **เจ้าหน้าที่นอกสายงาน + เปิดไทยมุง** | ❌ | ✅ | ✅ | **Header Badge** เท่านั้น |
| **ผู้ใช้ทั่วไป + เปิดไทยมุง** | ❌ | ✅ | ✅ | **Header Badge** เท่านั้น |
| **ผู้ใช้ทั่วไป + ปิดไทยมุง** | ❌ | ❌ | any | **ไม่แสดงผล** |
| **ไม่อยู่ในรัศมี** | any | any | ❌ | **ไม่แสดงผล** |

### 5. กฎการยกเว้นแจ้งเตือนตัวเอง (Self-Reporter Exclusion — Strict Policy)
- **นโยบาย:** ระบบจะ **ไม่ทำการแจ้งเตือนทุกช่องทาง** (ทั้ง Stacked Cards และ Header Badge) ให้กับผู้ที่ส่งรายงานเหตุการณ์นั้นๆ ด้วยตนเอง (Self-Reporter) ไม่ให้เจ้าของ/ผู้แจ้งหน้าบ้านเห็นการ์ดของตัวเอง
- **การติดตามผล:** หากแจ้งเหตุสำเร็จ (Upload Success) ระบบจะนำผู้แจ้งเข้าสู่ "ระบบแผนที่ติดตามโดยอัตโนมัติ" ในแถบ Command Center ทันที (ไม่ต้องพึ่ง Stacked Cards แจ้งเตือนแต่อย่างใด)
- **เงื่อนไขทางเทคนิค:** ตรวจสอบจาก `video.userId != user.id` อย่างเคร่งครัดตั้งแต่ขั้นแรก (บรรทัดแรกสุด of loop) ก่อนตรวจสอบเงื่อนไขอื่นๆ

### 6. Tap-to-Navigate Flow (Optimistic UI & Persistence)
เพื่อให้ผู้ใช้รู้สึกถึงการตอบสนองที่รวดเร็ว (Fast Feedback) เมื่อมีการกดที่ Header Badge:
1.  **Optimistic UI Removal**: ระบบจะสั่งลบการแจ้งเตือนออกจากลิสต์ที่แสดงบนหน้าจอทันที (setState) พร้อมเพิ่ม ID ลงใน `_dismissedAlertIds` ในทันทีที่กด
2.  **Persistent Recording**: ระบบจะทำการบันทึกสถานะการปิด (Dismiss) ลงในฐานข้อมูลแบบ Background (Non-blocking) เพื่อไม่ให้การแจ้งเตือนเดิมกลับมาแสดงซ้ำอีกหลังเปลี่ยนหน้า
3.  **Instant Navigation**: นำทางผู้ใช้ไปยังหน้า `EmergencyLivePage` ทันที พร้อมเปิดโหมด Chat อัตโนมัติ (`autoOpenChat: true`)
4.  **Auto-Refresh on Back**: เมื่อผู้ใช้กดกลับมาจากหน้าเหตุการณ์ ระบบจะทำการโหลดข้อมูลสถานะการปิดและการแจ้งเตือนใหม่โดยอัตโนมัติ เพื่อให้หน้า Home เป็นปัจจุบันเสมอ

---

## Stacked Alert System & UI (Updated 2026-03-13)

การปรับปรุง UI/UX ของการแจ้งเตือนเหตุฉุกเฉินบนหน้า Home ให้มีระเบียบและใช้งานง่ายขึ้น

### 1. Chronological Stacking & Numbering
- **Latest First**: การ์ดแจ้งเหตุจะซ้อนทับกันแบบ Layer โดยนำเหตุการณ์ล่าสุดมาไว้ด้านบนสุดเสมอ
- **Visual Indexing**: ย้ายเลขระบุลำดับ (เช่น 3/3, 2/3) ไปไว้ที่ **มุมล่างซ้าย** ของการ์ด เพื่อให้มองเห็นลำดับความสำคัญได้ชัดเจนโดยไม่ทับซ้อนข้อความหลัก
- **Address Simplification**: ยกเลิกข้อความ "มีการแจ้งเหตุพบในพื้นที่ของคุณ" และใช้ที่อยู่ (Address) จริงจากระบบเพียงอย่างเดียว เพื่อประหยัดพื้นที่และสื่อสารได้ตรงจุด

### 2. Gesture-Driven Interaction
- **Swipe Right (ปัดขวา ➡️)**: เป็นทางลัดเพื่อ "เข้าดูเหตุการณ์" (Navigator to EmergencyLivePage) ทันที
- **Swipe Left (ปัดซ้าย ⬅️)**: เพื่อ "ปิด/ยกเลิก" การแจ้งเหตุการณ์นั้นออกจากการมองเห็น

### 3. Dismissal Persistence (ระบบจดจำการปิดการ์ด)
- **Database Recording**: เมื่อผู้ใช้กดปิดการ์ด (ไม่ว่าจะกด X หรือปัดซ้าย) ระบบจะบันทึก ID ของวิดีโอนั้นลงในตาราง `user_ui_preferences` ภายใต้คีย์ `dismissed_emergency_alert_ids` สำหรับ User ID นั้นๆ โดยเฉพาะ
- **Race Condition Prevention**: ในขั้นตอน `_loadHomeData` ระบบจะต้องทำการโหลดรายการ Dismissed IDs ให้เสร็จสิ้นสมบูรณ์ (await) ก่อนจะเริ่มโหลด Active Alerts เพื่อป้องกันปัญหาการ์ดแจ้งเหตุปรากฏขึ้นมาสลายตัวภายหลัง (Pop-in then disappear)
- **Proactive UI Cleanup**: ทุกครั้งที่มีการรีเฟรชข้อมูลหรือรับ Event ใหม่ ระบบจะตรวจสอบและสั่งลบ (removeWhere) รายการที่ตรงกับ Dismissed IDs ออกจาก Memory ทันที เพื่อให้ UI แม่นยำที่สุด
- **Sync Integration**: ข้อมูลจะถูกบันทึกลงทั้ง Local PostgreSQL (ผ่าน API ท้องถิ่น) และ Supabase Cloud เพื่อให้สถานะการปิดแจ้งเตือนซิงค์ข้ามอุปกรณ์และคงรอยู่หลังรีสตาร์ทแอป

### 4. Smart UI Syncing
- **Map Focus**: แผนที่จะทำการซูมและจัดกึ่งกลาง (Animate Camera) ไปยังพิกัดของเหตุการณ์ที่อยู่บนสุด (Latest Alert) โดยอัตโนมัติ
- **Widget Auto-Mini**: เมื่อมีเหตุฉุกเฉินค้างอยู่ (ตอนเปิดแอป) หรือมีเหตุใหม่เข้ามา ปุ่มปรึกษา (Consultation Widget) จะถูกย่อขนาดและเคลื่อนไปที่ขอบซ้าย (`leftCenter`) โดยอัตโนมัติ เพื่อเปิดพื้นที่ให้เห็นแผนที่และข้อมูลเหตุการณ์ได้ชัดเจนที่สุด

### 5. Auto-Refresh & Lifecycle Awareness (Updated 2026-03-13)
- **App Resume Refresh**: ใช้ `WidgetsBindingObserver` เพื่อตรวจจับเมื่อแอปกลับมาทำงาน (Resumed) ระบบจะทำการดึงข้อมูลเหตุฉุกเฉินล่าสุดและตรวจสอบการเชื่อมต่อ WebSocket ทันที เพื่อให้ผู้ใช้เห็นข้อมูลที่เป็นปัจจุบันที่สุดโดยไม่ต้องปิด-เปิดแอปใหม่
- **Periodic Timer (Fail-safe)**: ติดตั้ง `Timer.periodic` ทุกๆ 90 วินาที เพื่อทำการ Re-sync ข้อมูลเหตุฉุกเฉินจากฐานข้อมูลแบบเบื้องหลัง เป็นแผนสำรองกรณี WebSocket หรือ Push Notification ทำงานผิดพลาดหรือสัญญาณขาดหาย
- **Immediate Data Prioritization**: ปรับปรุงลำดับการโหลดข้อมูลในหน้า Home โดยกำหนดให้ดึงหมวดหมู่ (Emergency Categories) และรายการที่ถูกปิด (Dismissed IDs) มาเป็นลำดับแรกสุด เพื่อให้ระบบกรองเหตุการณ์ทำงานได้ทันทีตั้งแต่วินาทีแรกที่ข้อมูลถูกดึงมาแสดงผล

---

## 🚨 Critical Bug Fixes & Coding Rules
> บันทึก ณ วันที่ 2026-03-14 — กฎเหล่านี้ถูกสร้างขึ้นจากการพบและแก้ไขจุดบกพร่องจริง ห้ามละเมิดในทุกกรณี

---

### Bug Fix #1 — ห้ามใช้ `io` โดยตรงใน Route Files
**ไฟล์ที่เคยบกพร่อง:** `websocket-server/routes/video.js`

**สาเหตุ:** Route file ไม่มี access โดยตรงต่อ `io` instance ของ Socket.io — การเรียก `io.to(...).emit(...)` โดยตรงจะทำให้ Server crash ด้วย `ReferenceError: io is not defined`

**กฎที่ต้องปฏิบัติ:**
- ทุก Route file ที่ต้องการส่ง WebSocket event **ต้องใช้ผ่าน `socketService` เสมอ**
- ต้อง `require('../services/socket-service')` ที่ส่วนบนของไฟล์ก่อนใช้งาน
- ห้าม import หรือใช้ `io` object โดยตรงในไฟล์ใด ๆ นอกจาก `server.js` และ `services/socket-service.js`

```javascript
// ❌ ผิด — จะ crash
io.to(`video-${videoId}`).emit('video-status', { ... });

// ✅ ถูก — ใช้ socketService เสมอ
const socketService = require('../services/socket-service');
socketService.sendStatus(userId, videoId, 'ready', { progress: 100 });
```

---

### Bug Fix #1b — Stale IP ใน Thumbnail URL ทำให้การ์ดพื้นหลังเป็นสีดำ *(Updated 2026-05-07)*
**ไฟล์ที่เคยบกพร่อง:** `lib/features/video/models/video_models.dart`, `websocket-server/services/thumbnail-queue.js`

**สาเหตุ:** DB เก็บ `thumbnail_url` เป็น Full URL รวม IP (เช่น `http://192.168.0.116:3000/...`) ทุกครั้งที่เชื่อมต่อ WiFi ใหม่หรือย้ายสถานที่ IP จะเปลี่ยน → `Image.network()` โหลดรูปไม่ได้ → การ์ดแสดงพื้นหลังสีดำ

**กฎที่ต้องปฏิบัติ:**
- ห้าม hardcode IP ใน URL ที่จะเก็บลง DB — ให้ใช้ `process.env.LOCAL_API_URL` เสมอ
- ฝั่ง Flutter **ต้องใช้ `video.bestThumbnailUrl`** แทน `video.thumbnailUrl` ตรงๆ เสมอ เพราะ getter นี้มี IP normalization built-in
- อัปเดต `AppConfig.mainMachineIp` **เป็นจุดเดียว** ที่ต้องเปลี่ยนเมื่อ IP เปลี่ยน

```dart
// ❌ ผิด — อาจได้ URL ที่ชี้ไป IP เก่า
Image.network(video.thumbnailUrl!)

// ✅ ถูก — normalize IP อัตโนมัติ
Image.network(video.bestThumbnailUrl!)
```

---

### Bug Fix #1c — Thumbnail ถูกเก็บใน `temp/` ซึ่งถูก Cleanup *(Updated 2026-05-07)*
**ไฟล์ที่เคยบกพร่อง:** `websocket-server/services/thumbnail-queue.js`

**สาเหตุ:** Thumbnail Worker บันทึกไฟล์ `.webp` ลงใน `temp/videos/[id]/` ซึ่งเป็น directory เดียวกับไฟล์วิดีโอชั่วคราว — เมื่อ Auto Cleanup ทำงาน ไฟล์ thumbnail ถูกลบพร้อมกัน → URL ใน DB ชี้ไปไฟล์ที่ไม่มีอยู่แล้ว

**กฎที่ต้องปฏิบัติ:**
- Thumbnail ที่ใช้แสดง UI **ต้องเก็บใน `uploads/thumbnails/[id]/`** เท่านั้น (persistent directory)
- ห้ามเก็บ thumbnail ที่จะใช้แสดง UI ใน `temp/` directory ใดๆ ทั้งสิ้น
- Route `/uploads/thumbnails` ต้องถูก serve เป็น static files ใน `server.js` เสมอ

```javascript
// ❌ ผิด — จะถูก cleanup พร้อมวิดีโอ
const thumbPath = path.join(tempVideoDir, videoId, 'thumb.webp');

// ✅ ถูก — persistent location ไม่ถูก cleanup
const thumbPath = path.join(__dirname, '../uploads/thumbnails', videoId, 'thumb.webp');
```

---

### Bug Fix #2 — Dev Auto-Seeding ต้องถูก Guard ด้วย `NODE_ENV`

**ไฟล์ที่เคยบกพร่อง:** `websocket-server/server.js`

**สาเหตุ:** โค้ด Auto-Seeding ที่สร้างขึ้นเพื่อ Development ถูกปล่อยให้ทำงานทุก Environment — ทำให้ทุก user ที่ connect บน Production ถูก assign role "กู้ภัย" โดยอัตโนมัติ เป็น Security Risk ร้ายแรง

**กฎที่ต้องปฏิบัติ:**
- โค้ด Dev/Testing ทุกชิ้น **ต้อง wrap ด้วย `if (process.env.NODE_ENV === 'development')` เสมอ**
- ไฟล์ `.env` บนเครื่อง Development ต้องมี `NODE_ENV=development`
- ไฟล์ `.env` บน Production Server **ต้องตั้งค่า `NODE_ENV=production`** เพื่อ disable feature นี้โดยอัตโนมัติ

```javascript
// ❌ ผิด — ทำงานทุก Environment
if (pool) {
  await pool.query(`INSERT INTO user_group_roles ...`);
}

// ✅ ถูก — guard ด้วย NODE_ENV
if (process.env.NODE_ENV === 'development' && pool) {
  await pool.query(`INSERT INTO user_group_roles ...`);
}
```

---

### Bug Fix #4 — FFmpeg `drawtext` Filter Crash (Missing `libfreetype`) — *Added 2026-05-11*
**ไฟล์ที่บกพร่อง:** `websocket-server/services/video-service.js`

**สาเหตุ:** FFmpeg binary บนเครื่อง macOS ถูกคอมไพล์มาโดยไม่มี `--enable-libfreetype` ทำให้การใช้ฟิลเตอร์ `drawtext` เพื่อทำลายน้ำแบบ Dynamic ล้มเหลว (`Filter not found`) และส่งค่า Exit Code 8 ทำให้กระบวนการ Transcode หยุดชะงัก

**กฎที่ต้องปฏิบัติ:**
- **ห้ามใช้ `drawtext` โดยตรง**: หลีกเลี่ยงการใช้ FFmpeg filter สำหรับวาดข้อความเพื่อความยืดหยุ่นในการย้ายเซิร์ฟเวอร์
- **Sharp-based Overlays**: ให้ใช้ไลบรารี **Sharp (Node.js)** ในการสร้างไฟล์ภาพโปร่งใส (Transparent PNG) ที่มีข้อความหรือ Forensic ID ที่ต้องการ แล้วค่อยใช้ฟิลเตอร์ `overlay` ของ FFmpeg ในการซ้อนภาพลงบนวิดีโอแทน
- **Cleanup Requirement**: ต้องมีระบบลบไฟล์ PNG ชั่วคราวเหล่านี้ทิ้งทันทีเมื่อจบงาน (ทั้งในเคส Success และ Error)

```javascript
// ✅ ถูก — สร้างภาพข้อความด้วย Sharp แล้วซ้อนด้วย overlay
const watermarkImg = await sharp({
  create: { width: 1280, height: 720, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } }
}).composite([{ input: Buffer.from('<svg>...</svg>'), gravity: 'center' }]).png().toFile(tempPath);

ffmpegProcess.complexFilter([`overlay=10:10`]);
```

---

### Bug Fix #5 — Video Player Crash เมื่อเปิด URL ที่เป็นรูปภาพ — *Added 2026-05-11*
**ไฟล์ที่บกพร่อง:** `lib/features/video/presentation/pages/widgets/video_player_widget.dart`, `emergency_navigation_logic.dart`

**สาเหตุ:** `VideoPlayerController` และ `Chewie` ออกแบบมาสำหรับ Video Stream เท่านั้น เมื่อพยายามโหลด URL ที่เป็นภาพนิ่ง (เช่น `.jpg`, `.webp`) จะทำให้การ Initialize ล้มเหลว เกิด Error `Bad state: No active player` หรือหน้าจอค้างที่ "กำลังเชื่อมต่อสัญญาณ..." (Infinite Loading)

**กฎที่ต้องปฏิบัติ:**
- **Pre-Initialization Check**: ก่อนเรียก `controller.initialize()` ต้องตรวจสอบนามสกุลไฟล์ของ URL เสมอ หากเป็นไฟล์ภาพ (`.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`) ให้ **ข้าม (return)** การโหลด VideoPlayer
- **UI Hybrid Rendering**: ใน `VideoPlayerWidget` ต้องดักจับเคสที่เป็นรูปภาพ และสลับไปใช้ `Image.network` หรือ `Image.file` แทนการใช้ `Chewie` โดยรักษา `AspectRatio` ให้เท่ากับวิดีโอเพื่อไม่ให้ UI กระตุก
- **Consistent Privacy UI**: ต้องคงการแสดงผล "สิทธิ์ส่วนบุคคล (Blur)" สำหรับภาพนิ่งด้วย เพื่อให้เป็นมาตรฐานเดียวกับวิดีโอ

```dart
// ✅ ถูก — ตรวจสอบก่อนโหลด
if (url.toLowerCase().endsWith('.jpg')) return; // ข้ามใน logic

// ✅ ถูก — แสดงผลสลับตามประเภทสื่อใน UI
imageToDisplay != null 
  ? Image.network(imageToDisplay, fit: BoxFit.cover) 
  : Chewie(controller: chewieController!)
```

---

### Bug Fix #6 — Thai Mhung Distance ต้องใช้ `user.alertRadius` ไม่ใช่ Hardcoded
**ไฟล์ที่เคยบกพร่อง:** `lib/features/video/presentation/pages/emergency_live_page.dart`


**สาเหตุ:** การตรวจสอบระยะทางก่อนเข้า Thai Mhung Mode ใช้ค่า `500` เมตร hardcoded แทนที่จะดึงค่า `alertRadius` ที่ผู้ใช้ตั้งไว้ในหน้า Profile — ขัดกับนโยบาย Manual Distance Control

**กฎที่ต้องปฏิบัติ:**
- ทุกการตรวจสอบระยะทาง (Distance Check) สำหรับ Thai Mhung และ Emergency Alert **ต้องดึงค่าจาก `AuthService.instance.currentUser?.alertRadius` เสมอ**
- ค่า fallback = `500` เมตร **ใช้ได้เฉพาะกรณี guest (user == null) เท่านั้น**
- ข้อความแจ้งเตือนควรบอก **ทั้งระยะทางจริง และรัศมีที่ตั้งไว้** เพื่อให้ผู้ใช้รู้และปรับแก้ได้

```dart
// ❌ ผิด — hardcoded ขัดนโยบาย
if (distanceInMeters > 500) { ... }

// ✅ ถูก — ดึงจาก User Profile
final int userAlertRadius = AuthService.instance.currentUser?.alertRadius ?? 500;
if (distanceInMeters > userAlertRadius) { ... }
```

---

### Bug Fix #4 — ห้ามมี Fallback ให้สิทธิ Responder โดยไม่ตรวจ Category
**ไฟล์ที่เคยบกพร่อง:** `lib/features/video/presentation/pages/emergency_live_page.dart` (`_isEligibleResponder()`)

**สาเหตุ:** มี fallback `return user.isProfessionalResponder` ซึ่งจะให้สิทธิ "Accept" แก่ volunteer ทุกคนโดยอัตโนมัติ แม้ว่า profession ของพวกเขาจะไม่ถูกกำหนดไว้ใน `category.volunteerProfessionIds` — ขัดกับ **"No Professional Fallback Policy"** อย่างตรงไปตรงมา

**กฎที่ต้องปฏิบัติ:**
- `_isEligibleResponder()` **ต้อง return `false` เสมอ** ในทุกกรณีที่ `category.volunteerProfessionIds` ว่างเปล่าหรือไม่มี category
- **ห้าม Fallback** ไปยัง `user.isProfessionalResponder`, `user.isVolunteer`, หรือ property อื่นใดทั้งสิ้น
- หากปุ่ม Accept หายไปโดยไม่ตั้งใจ → ให้ตรวจสอบและแก้ไขข้อมูล `volunteer_profession_ids` ใน table `donation_categories` ของ Supabase แทน

```dart
// ❌ ผิด — Fallback ขัดนโยบาย
// Fallback: ถ้าเป็นอาสาสมัครอาชีพ ให้มีสิทธิช่วยเหลือเสมอ
return user.isProfessionalResponder;

// ✅ ถูก — "No Professional Fallback" Policy
// หาก category ไม่ได้กำหนด volunteerProfessionIds → ปฏิเสธเสมอ
// แก้ไขที่ DB ไม่ใช่ที่โค้ด
debugPrint('_isEligibleResponder: no mapped professions → denied.');
return false;
```

---

### Bug Fix #5 — iOS White Screen / Startup Hang (Timeout Management)
**ไฟล์ที่เกี่ยวข้อง:** `lib/services/sync_service.dart`, `lib/services/service_locator.dart`

**สาเหตุ:** แอปค้างที่หน้าจอขาว (White Screen) ตอนเริ่มต้นบน iOS เนื่องจาก `ServiceLocator.initialize()` ทำการ `await` คำสั่ง `fullSync()` ซึ่งมีการเรียก HTTP ไปที่เครื่องหลัก หากเครื่องหลักเข้าถึงไม่ได้ (เช่น ติด Firewall หรืออยู่คนละ WiFi) iOS จะรอจนกว่าจะครบ OS Timeout (60s+) ทำให้แอปดูเหมือนค้าง

**กฎที่ต้องปฏิบัติ:**
- **Non-blocking Init**: ห้าม `await` งานที่ต้องรอเครือข่ายภายนอก (ในส่วนที่ไม่จำเป็นต่อการวาด UI แรก) ภายใน `main()` หรือ `initialize()` — ให้ใช้ `unawaited(syncService.fullSync())` เพื่อรันเป็น Background Task แทน
- **Explicit Timeouts**: ทุกการเรียก HTTP ไปยัง Local Server **ต้องกำหนด `.timeout()` เสมอ** (แนะนำ 5-8 วินาที) เพื่อให้แอปทำงานต่อได้ทันทีหากเซิร์ฟเวอร์ไม่ตอบสนอง
- **Connection Guard**: ตรวจสอบสถานะการเชื่อมต่อด้วย `healthCheck()` แบบมี Timeout ก่อนเริ่มงานใหญ่

```dart
// ❌ ผิด — แอปจะค้างจนกว่าจะ Timeout (60s+)
await syncService.fullSync(); 

// ✅ ถูก — รันเบื้องหลัง ไม่ขวางหน้า Home
unawaited(syncService.fullSync()); 

// ✅ ถูก — มีตาข่ายดักเวลา
final response = await http.get(url).timeout(const Duration(seconds: 5));
```

---

---

## 🏥 Emergency Health Data Auto-Release System (Updated 2026-05-25 Rev.2)

ระบบปลดล็อกข้อมูลสุขภาพอัตโนมัติสำหรับทีมผู้ให้ช่วยเหลือ เมื่อเจ้าของอุปกรณ์หมดสติ/ไม่ตอบสนอง โดยผู้ใช้เป็นคนตั้งค่า scope, timer และ recipient เองทั้งหมดในแถบ **"จิตอาสา"** ของหน้า Profile — **ยังไม่ต้องสร้าง Tab ใหม่**

---

### 1. Data Sources (ตารางสุขภาพที่ใช้)

อิงตาม pattern ของ `HealthDataPermissionRepository` (`lib/features/consultation/data/repositories/health_data_permission_repository.dart`) ซึ่งมีโครงสร้างการดึงข้อมูลสุขภาพแบบ field-based อยู่แล้ว:

| ตาราง | ข้อมูลที่ดึง | ใช้ในสภาวะฉุกเฉิน |
|-------|-------------|-------------------|
| `consumer_profiles` | `health_info` (กลุ่มเลือด, แพ้ยา, โรคประจำตัว), `birthday`, `emergency_contact`, `emergency_phone` | ✅ ข้อมูลหลัก |
| `health_data_logs` | weight, height, BMI history (`field_type`) | ✅ ประวัติร่างกาย |
| `device_health_metrics` | heart rate, blood pressure, SpO2, blood sugar (`metric_type`) | ✅ ข้อมูลเซนเซอร์ |
| `consultation_notes` | `chief_complaint`, `diagnosis`, `treatment_plan`, `recommendations` | ✅ ประวัติการรักษา |
| `prescriptions` | `medications`, `notes`, `status`, `issued_at` | ✅ ยาประจำตัว |

> **หมายเหตุ:** ระบบนี้ไม่ได้สร้างตารางสุขภาพใหม่ แต่ใช้ **View/Join** จากตารางเดิมทั้งหมด และเพิ่มตารางควบคุมการเข้าถึง (`settings`, `sessions`, `tokens`, `logs`) เท่านั้น

#### 1.1 Field Key Mapping (enabled_fields ↔ แหล่งข้อมูล)

> ⚠️ **Critical** — ต้องกำหนดก่อน Phase 1c เพื่อให้ UI Checkbox ตรงกับ query จริง
> ต้องตรวจสอบก่อน deploy ว่า `health_info` JSONB ใน `consumer_profiles` มี key เหล่านี้จริงใน production

| Key ใน `enabled_fields` | แหล่งข้อมูล | Column / Query | หมายเหตุ |
|------------------------|------------|---------------|----------|
| `blood_type` | `consumer_profiles` | `health_info->>'blood_type'` | JSONB extract |
| `allergies` | `consumer_profiles` | `health_info->>'allergies'` | JSONB extract |
| `chronic_conditions` | `consumer_profiles` | `health_info->>'chronic_conditions'` | JSONB extract |
| `surgical_history` | `consumer_profiles` | `health_info->>'surgeries'` | ต้องตรวจสอบ key |
| `emergency_contact` | `consumer_profiles` | `emergency_contact`, `emergency_phone` | direct columns |
| `device_metrics` | `device_health_metrics` | query by `user_id` (ไม่ใช้ `consultation_id`) | latest 5 per metric_type |
| `prescriptions` | `prescriptions` | query by `patient_id` เท่านั้น — **ห้ามใช้ `consultation_id`** | ใช้ `_fetchRecentPrescriptions(patientId)` |
| `consultation_history` | `consultation_notes` | query by `patient_id` เท่านั้น — **ห้ามใช้ `consultation_id`** | ใช้ `_fetchRecentConsultationNotes(patientId)` |
| `weight_history` | `health_data_logs` | `field_type = 'weight'` by `user_id` | มีใน `HealthDataPermissionRepository` แล้ว |

> ⚠️ **Critical** — `HealthDataPermissionRepository._fetchPrescriptions()` และ `_fetchConsultationNotes()` ต้องสร้าง method ใหม่แยกต่างหากสำหรับ emergency context ที่ query โดย `patient_id` อย่างเดียว ไม่ใช่ `consultation_id` เพราะสภาวะฉุกเฉินไม่มี consultation

---

### 2. User Configurable Settings (UI ในแถบ "จิตอาสา")

#### 2.1 Full Tab Layout — แถบ "จิตอาสา" หลังเพิ่ม Section ใหม่

> ไม่เปลี่ยน Section 1–3 ที่มีอยู่แล้ว (**`_buildNotificationSettings()`**) เพียงต่อท้าย Section ที่ 4 ลงไป

```text
┌──────────────────────────────────────────┐
│  การตั้งค่าการแจ้งเตือน                   │  ← header (มีอยู่แล้ว)
├──────────────────────────────────────────┤
│  [1] แจ้งเหตุฉุกเฉินใกล้ตัว   [Switch]   │  ← Thai Mhung (มีอยู่แล้ว)
│       └─ Radius Slider (ถ้าเปิด)         │
├──────────────────────────────────────────┤
│  [2] แจ้งเตือนช่วยเปิดทาง      [Switch]   │  ← Yield Way (มีอยู่แล้ว)
│       └─ Radius Slider (ถ้าเปิด)         │
├──────────────────────────────────────────┤
│  [3] กำหนดอาชีพที่เห็นไม่เบลอ            │  ← Unblurred Profession (มีอยู่แล้ว)
│       (แสดงถ้า Thai Mhung หรือ YW เปิด)  │
├──────────────────────────────────────────┤
│  [4] ข้อมูลสุขภาพสำหรับผู้ช่วยเหลือ  🆕  │  ← Section ใหม่ (เพิ่มใน Phase 1c)
│       (แสดงเสมอ — ไม่ขึ้นกับ toggle อื่น) │
└──────────────────────────────────────────┘
```

> **Implementation**: ต่อท้าย `_buildUnblurredProfessionSection()` ด้วย `_buildEmergencyHealthSection()` ใหม่ใน `_buildNotificationSettings()`

---

#### 2.2 UI Proposal: "ข้อมูลสุขภาพฉุกเฉิน" — Section ที่ 4 ในแถบจิตอาสา

เพิ่ม Section ชื่อ **"ข้อมูลสุขภาพสำหรับผู้ช่วยเหลือ"** แบ่งเป็น **2 ระดับ**:

**ระดับที่ 1 — Card หลัก (แสดงเสมอ):** Master Toggle + สถานะปัจจุบัน
**ระดับที่ 2 — Sub-panels (แสดงเฉพาะเมื่อ Toggle = ON):** ตั้งค่า Timer, Granularity, Recipients

```text
╔══════════════════════════════════════════════╗
║  LEVEL 1 — Card หลัก (แสดงเสมอ)              ║
╠══════════════════════════════════════════════╣
║  🏥  ข้อมูลสุขภาพสำหรับผู้ช่วยเหลือ          ║
║      เปิดเผยข้อมูลสุขภาพอัตโนมัติเมื่อ       ║
║      เกิดเหตุฉุกเฉินและไม่มีการตอบสนอง       ║
║                              [Switch ON/OFF] ║
╠══════════════════════════════════════════════╣
║  LEVEL 2 — Sub-panels (เลื่อนลงมา เมื่อ ON)  ║
║  ┌──────────────────────────────────────┐   ║
║  │ ⏱ ระยะเวลาก่อนเปิดเผยอัตโนมัติ      │   ║
║  │ [3 นาที] [5 นาที] [15 นาที] [กำหนดเอง]│  ║
║  └──────────────────────────────────────┘   ║
║  ┌──────────────────────────────────────┐   ║
║  │ 📋 ข้อมูลที่จะเปิดเผย                │   ║
║  │ ☑ กลุ่มเลือด    ☑ โรคประจำตัว        │   ║
║  │ ☑ ยาที่แพ้      ☑ ผู้ติดต่อฉุกเฉิน   │   ║
║  │ ☐ ประวัติผ่าตัด ☐ ยาประจำตัว         │   ║
║  │ ☐ ข้อมูลเซนเซอร์ ☐ ประวัติแพทย์     │   ║
║  │ ☐ ใบสั่งยา                           │   ║
║  │  [chip "กรอกข้อมูล" → Health Profile] │   ║
║  └──────────────────────────────────────┘   ║
║  ┌──────────────────────────────────────┐   ║
║  │ 👥 เปิดเผยให้กับ                     │   ║
║  │ ☑ เฉพาะผู้ที่กด "ตอบรับช่วยเหลือ"   │   ║
║  │ ☐ เฉพาะอาชีพทางการแพทย์             │   ║
║  │ ☐ เฉพาะผู้ได้รับการรับรอง            │   ║
║  │ ☐ ระบุบุคคลเฉพาะ (Whitelist)         │   ║
║  │ ─────────────────────────────────── │    ║
║  │ ⚠ [Emergency Fallback Toggle]        │   ║
║  │   ถ้าไม่มีผู้ผ่านเงื่อนไข ให้ขยาย    │   ║
║  └──────────────────────────────────────┘   ║
╚══════════════════════════════════════════════╝
```

**Transition UX:**
- Switch ON ครั้งแรก → Consent Dialog → ถ้า confirm → `AnimatedSize` ขยาย Level 2 ลงมา
- Switch OFF → Level 2 ยุบขึ้น (`AnimatedSize`) → revoke tokens ทันที
- ใช้ `AnimatedSize` + `AnimatedOpacity` แทน `if (enabled) ...[]` เพื่อ UX นุ่มนวล

---

#### A. Level 1 — Master Toggle (Card หลัก)
```text
┌──────────────────────────────────────────────────────────┐
│  [Icon: medical_services]                                  │
│  เปิดให้ทีมช่วยเหลือเข้าถึงข้อมูลสุขภาพ                   │
│  เมื่อเกิดเหตุฉุกเฉินและไม่มีการตอบสนอง                   │
│                                          [Switch: ON/OFF]│
└──────────────────────────────────────────────────────────┘
```
- **Default = OFF** (Privacy-First)
- เมื่อ **ON ครั้งแรก** → แสดง **Consent Dialog** (PDPA) ก่อนบันทึก:
  ```text
  ┌──────────────────────────────────────────────────────────┐
  │  ข้อมูลที่คุณเลือกจะถูกเปิดเผยต่อผู้ช่วยเหลือที่กำหนด     │
  │  ในสภาวะฉุกเฉินเท่านั้น ระบบจะบันทึก Audit Trail ทุกครั้ง │
  │  ที่มีการเข้าถึงข้อมูลของคุณ                               │
  │                         [ยืนยัน — รับทราบและยินยอม]        │
  │                         [ยกเลิก]                          │
  └──────────────────────────────────────────────────────────┘
  ```
  บันทึก `consent_given_at` ลง `emergency_health_data_settings` — ถ้ายังไม่ยืนยัน ให้ Switch กลับเป็น OFF อัตโนมัติ
- เมื่อ **ON** (หลัง consent) → แสดง sub-panels B–E ด้านล่าง
- เมื่อ **OFF** → ซ่อนทั้งหมด และไม่มีการ auto-release ใดๆ
  - ถ้า OFF ระหว่าง incident ที่กำลังดำเนินอยู่ → Revoke tokens ทั้งหมด + session status → `expired`

#### B. Level 2 — Auto-Release Timer — "เวลารอก่อนเปิดเผยอัตโนมัติ"
```text
┌──────────────────────────────────────────────────────────┐
│  ระยะเวลาก่อนเปิดเผยข้อมูลอัตโนมัติ                      │
│  [ 3 นาที ] [ 5 นาที ] [ 15 นาที ] [ 30 นาที ] [กำหนดเอง]│
│                                                          │
│  หมายเหตุ: ระบบจะส่งการแจ้งเตือนให้คุณก่อนเสมอ          │
│  หากไม่ตอบสนองภายในเวลาที่กำหนด จึงจะเปิดเผยต่อทีมช่วยเหลือ│
└──────────────────────────────────────────────────────────┘
```
- ค่าที่เลือกได้: `3`, `5`, `15`, `30` นาที หรือ `custom` (1–120 นาที)
- UX แนว iPhone Emergency SOS / Apple Watch Fall Detection

#### C. Level 2 — Panic Cancel (Countdown Screen)
เมื่อ trigger เกิดขึ้น (ผู้ใช้กดปุ่มฉุกเฉิน / เซนเซอร์ตรวจจับ / Dead Man's Switch) ระบบจะ:
1. แสดง **Full-screen Alert** พร้อมเสียงดัง + นับถอยหลัง (Panic Countdown)
2. มีปุ่มใหญ่สีเขียว **"ฉันปลอดภัย — ยกเลิกการปลดล็อก"** (Panic Cancel)
3. หากผู้ใช้กดยกเลิก → สถานะ session เปลี่ยนเป็น `cancelled` → ไม่มีข้อมูลใดถูกส่ง
4. หากไม่กดภายในเวลาที่กำหนด → ระบบ auto-release ข้อมูลตาม scope ที่ผู้ใช้ตั้งไว้

> **นโยบาย:** การแจ้งเตือน Panic Cancel ต้องรบกวนผู้ใช้ให้มากที่สุดเท่าที่จะเป็นไปได้ (High-priority notification, sound, vibration) เพื่อป้องกันการปล่อยข้อมูลโดยไม่ตั้งใจ

#### D. Level 2 — Data Granularity — "ข้อมูลที่จะเปิดเผย"
Checkbox ต่อรายการ (ผู้ใช้เลือกเองได้ทุกรายการ):
- [ ] กลุ่มเลือด
- [ ] โรคประจำตัว
- [ ] ยาที่แพ้
- [ ] ผู้ติดต่อฉุกเฉิน
- [ ] ประวัติการผ่าตัด
- [ ] ยาประจำตัว
- [ ] ข้อมูลจากอุปกรณ์ (เซนเซอร์: ชีพจร, ความดัน)
- [ ] ประวัติการปรึกษาแพทย์
- [ ] ใบสั่งยา

> หากข้อมูลยังไม่ได้กรอกในระบบ ให้แสดง chip "กรอกข้อมูล" → navigate ไปหน้า Health Profile

#### E. Level 2 — Recipient Filtering — "เปิดเผยให้กับ"
**กรองคัดเฉพาะบุคคลที่เข้าร่วมช่วยเหลือ** (ไม่ใช่แค่ profession):
- [ ] **เฉพาะผู้ที่กด "ตอบรับช่วยเหลือ"** ในเหตุการณ์นั้น (Active Responder Only) — **ค่าเริ่มต้น และแนะนำให้เลือก**
- [ ] **เฉพาะอาชีพทางการแพทย์** (หมอ/พยาบาล/กู้ชีพ/ปฐมพยาบาล)
- [ ] **เฉพาะบุคคลที่ได้รับการรับรอง** (Verified Responder)
- [ ] **ระบุบุคคลเฉพาะเจาะจง** (Whitelist by User ID / Phone) — สำหรับผู้ใช้ที่ต้องการระบุคนที่ไว้ใจได้แบบรายบุคคล

> **หลักการ:** ระบบจะตรวจสอบเงื่อนไขแบบ **AND** — ต้องผ่านทุก checkbox ที่ผู้ใช้เปิดไว้จึงจะได้รับสิทธิ เช่น ถ้าเลือก "Active Responder Only" + "อาชีพทางการแพทย์" → มีสิทธิ์เฉพาะคนที่กดรับเหตุ **และ** เป็นอาชีพทางการแพทย์เท่านั้น

> ⚠️ **Emergency Fallback Warning** — ต้องแจ้งเตือนในหน้า settings: *"หากไม่มีผู้ช่วยเหลือที่ผ่านเงื่อนไขทั้งหมด ข้อมูลจะไม่ถูกส่งให้ใครเลย"* พร้อม option เสริม:
> - [ ] **Emergency Fallback** — ถ้าไม่มีผู้ผ่านเงื่อนไข ให้ขยายไปยัง Active Responder ทุกคนแทน

**Query สำหรับ Recipient Filtering** (ตาราง `incident_responses` ที่มีอยู่แล้ว):
```sql
SELECT ir.volunteer_id
FROM incident_responses ir
JOIN user_group_roles ugr ON ugr.user_id = ir.volunteer_id
JOIN professions p ON p.id = ugr.profession_id
WHERE ir.video_id = :incident_id
  AND ir.status IN ('en_route', 'arrived', 'accepted')  -- Active Responder
  AND (:require_medical = false OR p.category = 'medical')  -- Medical filter
  AND (:require_verified = false OR ugr.is_verified = true)  -- Verified filter
```

---

### 3. Trigger Architecture

ระบบรองรับ 3 ช่องทางการ trigger โดยเรียงตามความรุนแรง:

| ลำดับ | Trigger | วิธีตรวจจับ | ลำดับความสำคัญ |
|-------|---------|------------|---------------|
| 1 | **Manual Emergency** | อัปโหลดวิดีโอ/ภาพฉุกเฉินสำเร็จ (`_uploadIncident()` ใน `emergency_reporting_logic.dart`) | Phase 2b |
| 2 | **Sensor Anomaly** | ดึงข้อมูลจาก `device_health_metrics` หรือ Apple Health / Google Fit ที่มีค่าผิดปกติขั้นวิกฤต | Phase 4 |
| 3 | **Dead Man's Switch** | ผู้ใช้ไม่ Check-in ภายในเวลาที่กำหนด (เช่น 12–24 ชม.) ในขณะที่เปิดโหมดเฝ้าระวัง | Phase 4 |

> ⚠️ **Critical — Trigger Entry Point**: Manual Trigger ต้องเชื่อมที่ `ws.sendEmergencyAlert(...)` ใน `emergency_reporting_logic.dart` ไม่ใช่การ "กดปุ่ม" เพราะ `videoId` ยังไม่มีจนกว่า upload จะสำเร็จ

**Flow การทำงานเมื่อ Trigger:**
1. `_uploadIncident()` สำเร็จ → ได้ `videoId` → ตรวจสอบ `emergency_health_data_settings.is_enabled` → ถ้า OFF หยุดทันที
2. สร้าง record ใน `emergency_health_release_sessions` (status = `counting`) via **Node.js server** (service_role)
3. Flutter แสดง **Panic Cancel Notification** + นับถอยหลังตาม `release_delay_minutes`
4. หากผู้ใช้กด "ยกเลิก" → PATCH session → `cancelled` → Flutter subscribe realtime รับการเปลี่ยนแปลง
5. **Node.js cron** (ทุก 30 วินาที) ตรวจ sessions ที่ `status='counting'` และ `triggered_at + release_delay_minutes <= NOW()` → UPDATE → `released` → generate access tokens
6. Supabase Realtime broadcast → Flutter `EmergencyLivePage` รับ event → แสดง Floating Label บนหมุด

> ⚠️ **Critical — ห้ามทำ Countdown บน Client เท่านั้น**: iOS kill background services ภายใน 30 วินาที Countdown ต้องอยู่บน **Node.js server** (websocket-server ที่มีอยู่แล้ว) Flutter เป็นแค่ subscriber ผ่าน Supabase Realtime

**Node.js Server Cron (เพิ่มใน websocket-server):**
```javascript
// ตรวจทุก 30 วินาที — เพิ่มใน websocket-server/services/
setInterval(async () => {
  const due = await pool.query(`
    SELECT id, patient_id, incident_id, released_fields
    FROM emergency_health_release_sessions
    WHERE status = 'counting'
      AND triggered_at + (release_delay_minutes * interval '1 minute') <= NOW()
  `);
  for (const session of due.rows) {
    await pool.query(`UPDATE emergency_health_release_sessions SET status='released', auto_released_at=NOW() WHERE id=$1`, [session.id]);
    // generate access tokens สำหรับ active responders ของ incident นั้น
    await generateAccessTokensForResponders(session);
  }
}, 30_000);
```

---

### 4. Volunteer Map Dialog + Floating Label

เมื่อผู้มีสิทธิ (Responder ที่ผ่าน Recipient Filtering) เปิดแผนที่ใน `EmergencyLivePage`:

- **Floating Label บนหมุด**: เหตุการณ์ที่มีข้อมูลสุขภาพพร้อมใช้ จะแสดง **ป้ายลอยสีม่วง/แดง** เหนือหมุดแผนที่:
  ```text
  ┌──────────┐
  │ 🏥 ข้อมูลสุขภาพ │  ← Label ลอยปรากฏเหนือหมุด
  └──────────┘
        📍
  ```
- **Tap ที่หมุด → เปิด Dialog/Sheet** แสดงข้อมูลสุขภาพที่ผู้ใช้อนุญาตไว้
- **Token-based Access**: ข้อมูลใน Dialog ดึงผ่าน Node.js API ที่ต้องใช้ `emergency_access_token` จากตาราง `emergency_health_access_tokens` ซึ่ง:
  - หมดอายุเมื่อเหตุการณ์ `resolved` หรือ `expires_at` ครบ
  - ถูก revoke ทันทีถ้าเจ้าของปิด Master Toggle ระหว่าง incident (`revoked_at = NOW()`)
  - Token ผูกกับ `responder_id` — ใช้ข้ามคนไม่ได้
- **Privacy Mask**: หาก Responder ไม่ผ่านเงื่อนไขที่ผู้ใช้ตั้งไว้ → หมุดไม่แสดง Label และ Dialog แจ้ง "ยังไม่มีสิทธิเข้าถึง"
- **Realtime Subscription** ใน `EmergencyLivePage` (เพิ่มคล้าย `_supabaseInteractionSub` ที่มีอยู่แล้ว):
  ```dart
  // Subscribe เมื่อ session ของ incident นี้เปลี่ยนเป็น 'released'
  _healthReleaseSub = _client
    .channel('health_release:$videoId')
    .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'emergency_health_release_sessions',
      filter: PostgresChangeFilter(type: FilterType.eq, column: 'incident_id', value: videoId),
      callback: (payload) {
        if (payload.newRecord['status'] == 'released') {
          setState(() => _healthDataAvailable = true); // แสดง Floating Label
        }
      },
    ).subscribe();
  ```

---

### 5. Audit Trail

ตาราง `health_data_access_logs` บันทึกทุกการเข้าถึง:

| คอลัมน์ | รายละเอียด |
|---------|-----------|
| `id` | UUID Primary Key |
| `incident_id` | FK → `videos(id)` (เหตุการณ์) |
| `patient_id` | FK → `users(id)` (เจ้าของข้อมูล) |
| `accessor_id` | FK → `users(id)` (คนเปิดดู) |
| `accessor_profession_id` | FK → `professions(id)` |
| `accessed_fields` | JSONB — รายการ fields ที่เปิดดูตอนนั้น |
| `access_method` | `map_dialog`, `emergency_card`, `auto_release` |
| `token_id` | UUID ของ access token ที่ใช้ |
| `location_lat`, `location_lng` | พิกัดของผู้เข้าถึงตอนเปิดดู |
| `created_at` | Timestamp |

> ใช้สำหรับตรวจสอบย้อนหลัง 100% ว่าใครเข้าถึงข้อมูลอะไร เมื่อไหร่ ที่ไหน

---

### 6. Implementation Status

สถานะปัจจุบัน: งานใน Emergency Health Data Auto-Release System ทำเสร็จแล้วครบทุก Phase ที่วางไว้

- **Phase 1a — Schema + RLS + Realtime**: เสร็จแล้ว
  - Migrations อยู่ใน `supabase/migrations/`
  - RLS / policy / realtime ถูกเปิดแล้ว

- **Phase 1b — Field Key Verification**: เสร็จแล้ว
  - Emergency repositories แยกการ query `prescriptions` และ `consultation_notes` ตาม `patient_id`

- **Phase 1c — UI Settings + Consent Dialog**: เสร็จแล้ว
  - เพิ่ม section สำหรับตั้งค่า auto-release และ consent

- **Phase 2a — Node.js Server Cron**: เสร็จแล้ว
  - `emergency-health-release-checker.js` ตรวจ session และปล่อย token อัตโนมัติ

- **Phase 2b — Flutter Trigger Hook + Panic Cancel**: เสร็จแล้ว
  - Hook จาก `_uploadIncident()` / `ws.sendEmergencyAlert(...)` พร้อม panic cancel flow

- **Phase 3a — Token Validation + Realtime Sub**: เสร็จแล้ว
  - `GET /api/emergency-health/:incidentId` และ realtime subscription พร้อม revoke flow

- **Phase 3b — Floating Label + Map Dialog**: เสร็จแล้ว
  - แสดง badge/overlay และ privacy mask บนแผนที่

- **Phase 4 — Sensor Trigger + Dead Man's Switch**: เสร็จแล้ว
  - Sensor anomaly alerts, dead-man reminders, and check-in UI / repository wiring พร้อมใช้งาน

### 7. Database Schema

สคีมาถูกแยกไปไว้ใน migration แล้ว เพื่อให้เอกสารนี้เป็นแผนงานที่อ่านง่าย:

- `supabase/migrations/20260525_emergency_health_release_system.sql`
- `supabase/migrations/20260526090000_emergency_health_dead_man_checkins.sql`
- `supabase/migrations/20260519035023_create_device_health_metrics.sql`

---

## 5. การผนวกรวมระบบบริจาคเข้ากับวีดีโอฉุกเฉิน (Emergency Donation Integration)

จากแผนร่วมของระบบ Donation และ Video ได้ทำการบูรณาการการทำงานเพื่อให้วิดีโอฉุกเฉินหนึ่งรายการสามารถดึงดูดและรองรับยอดบริจาคได้หลายสาขาและหลากหมวดหมู่ โดยมีระบบที่ทำงานเสร็จสิ้นดังนี้:

### 1. การอนุมัติคำร้องแบบอัตโนมัติ (Role-based Auto-Approval)
- หากผู้เข้าให้ความช่วยเหลือ (Responder) ทำการสร้างคำร้องบริจาคในหน้า Live สถานะของคำร้องจะได้รับการตรวจสอบสิทธิและบันทึกข้อมูลตาราง `donation_request_approvals` ในขั้นแรกให้โดยอัตโนมัติ
- ใช้ `createRequestWithAutoApproval` ใน `DonationRepository` เพื่อเป็นสื่อกลางหลัก

### 2. ปุ่มบริจาคแบบทูเวย์ (Dual-mode Donation Button) ใน ActionButtonsWidget
- **ผู้สร้าง (Reporter)**: จะเห็นปุ่ม "**เปิดรับบริจาค**" สีเขียว ได้ก็ต่อเมื่อมีผู้ช่วยเหลือรายอื่นคนใดคนหนึ่งเดินทางมาถึงจุดเกิดเหตุแล้ว เพื่อให้เป็นพยานว่าเกิดเหตุการณ์นั้นจริง
- **ผู้ช่วยเหลือรายอื่น**: หากตรงกับ `volunteer_profession_ids` จะเห็นปุ่ม "**เปิดรับบริจาค**" สีเขียว หรือ "**รับบริจาค**" สีฟ้า
- **ผู้ชม (Viewer)**: จะไม่เห็นปุ่มใดๆ หากไม่มีคำร้องที่ Active เพื่อลดความสับสน หากมีคำร้องจะกลับกลายเป็นปุ่ม "**บริจาค**" สีส้ม
- การกดปุ่มสร้างคำร้อง ระบบจะส่งค่าตัวแปร `videoId` และ `defaultCategoryId` ไปยังหน้า `DonationCreatePage` แบบเต็มรูปแบบอัตโนมัติ
  - **เงื่อนไข Dropdown หมวดหมู่**: ทั้ง **ผู้สร้าง (Reporter)** และ **ผู้ช่วยเหลือรายอื่น (Responder)** มีสิทธิ์สลับเปลี่ยนประเภทความช่วยเหลือใน Dropdown ได้เท่าเทียมกัน
    - **ข้อจำกัด**: Dropdown จะแสดงเฉพาะ **หมวดหมู่บริจาคปกติ** (`is_emergency = false`) เท่านั้น — ไม่รวมหมวดหมู่ฉุกเฉิน เนื่องจากคำร้องบริจาคจากหน้า Live เป็นการขอสิ่งของหรือเงินทุน ไม่ใช่การแจ้งเหตุอีกรอบ
    - **Default**: ระบบจะ auto-select หมวดหมู่ที่มีค่า `display_order` น้อยที่สุดในตาราง `donation_categories` (เรียงจากน้อยไปมาก) โดยอัตโนมัติ — ค่า Default ปัจจุบันตามตารางจริงคือ **"ที่พัก"** (ผู้ดูแลระบบสามารถเปลี่ยนได้โดยปรับ `display_order` ในหน้าจัดการระบบบริจาค)
- ทันทีที่กดตกลง ระบบจะ Pop ปิดหน้ากลับมาโผล่ที่หน้า Live ปกติทันที พร้อมดึงคำร้องที่เพิ่งสร้างนี้มาเป็นที่คั่นหน้าหลักแสดงให้ผู้ใช้และผู้ชมคนอื่นๆ เห็น

### 3. ส่วนต่อประสานตัวแสดงคำร้องแบบซ้อน (Stacked Request Carousel)
- วิดีโอหนึ่งรายการสามารถมีคำร้องได้มากกว่าหนึ่งรายการ: 
  - การ์ดปุ่มกดบริจาค จะดึงเอาชื่อ **Title (หมวดหมู่ของคำร้อง)** มาแสดงแทนตัวเลข (เช่น `[ 250 ] [ ค่าพยาบาลฉุกเฉิน ]`) 
  - ผู้ชมสามารถกดลูกศร ซ้าย-ขวา ในบริเวณเดิมเพื่อสลับดูและตรวจสอบยอดของคำร้องต่างๆ (แยก Tracking ยอดผ่าน `_requestTotals` ผูกกับ `requestId` ทันทีที่ WebSocket Broadcast) โดยไม่พัง Aspect Ratio ของส่วน UI โคนวิดีโอ

---

## Emergency Donation Payment Flow (Updated 2026-04-08)

> **นโยบาย:** ยอดที่แสดงบนหน้าจอต้องสะท้อนเฉพาะการชำระเงินที่ **ยืนยันแล้วจริง** เท่านั้น
> ไม่ใช้ Optimistic Accumulation อีกต่อไป เพราะผู้ใช้อาจกดหลายครั้งโดยไม่ชำระจริง

---

### 🏦 Escrow-via-Beneficiary Architecture (นโยบายหลัก — Updated 2026-04-08)

**หลักการ:** เงินบริจาคทุกบาทที่ชำระสำเร็จจะถูกโอนไปยัง **บัญชีของหน่วยงานผู้รับมรดก (Beneficiary Escrow Account)** ทันที — ไม่เก็บไว้ในระบบ Sheserved และไม่โอนให้ผู้รับบริจาค (Reporter) จนกว่าภารกิจจะสมบูรณ์

**เหตุผลของ Architecture นี้:**

| เหตุผล | รายละเอียด |
|:---|:---|
| 🛡️ **ป้องกันภาษี** | Sheserved ไม่ "ถือ" เงินของผู้อื่น — เงินผ่านไปยัง Beneficiary (นิติบุคคล) โดยตรง ลดความเสี่ยงว่าระบบจะถูกตีความว่ารับเงิน |
| 🔒 **ลดความเสี่ยงการเรียกเงินคืน** | หากคำร้องถูกระงับหรือยกเลิก เงินยังอยู่ที่ Beneficiary — ไม่ต้องไล่เรียกคืนจากผู้รับบริจาคที่อาจใช้ไปแล้ว |
| ⚖️ **ความโปร่งใส** | บุคคลที่สาม (Beneficiary Org) ทำหน้าที่เหมือน "คนกลางกองกลาง" — ผู้บริจาคมีความมั่นใจว่าเงินอยู่ในมือที่ neutral |
| 🔁 **Refund ง่ายขึ้น** | การคืนเงิน (Refund/Cancel) ไม่ต้องเรียกเงินกลับจากผู้รับบริจาค — Beneficiary ถือเงินอยู่ครบ |

---

### Flow เปรียบเทียบ (เดิม vs ใหม่)

```
──────────────────────────────────────────────────────
❌ Flow เดิม (Direct Transfer — มีความเสี่ยง):
──────────────────────────────────────────────────────
ผู้บริจาค → Gateway → [ระบบ Sheserved ถือเงิน?]
                                ↓
                     → Reporter/Recipient (ทันที?)
                          ↑
                     ❌ ถ้า Cancel → ต้องเรียกเงินคืน
                     ❌ Sheserved อาจถูกตีความว่ารับเงิน

──────────────────────────────────────────────────────
✅ Flow ใหม่ (Escrow-via-Beneficiary):
──────────────────────────────────────────────────────
ผู้บริจาค → Gateway → Beneficiary Escrow Account
                              ↓ (พักไว้ตลอดภารกิจ)
                     ภารกิจสมบูรณ์ (Resolved + Consensus)
                              ↓
                     Beneficiary โอนให้ Reporter/Recipient
                              ↓
                     ✅ ถ้า Cancel → เงินยังอยู่ที่ Beneficiary
                     ✅ Sheserved ไม่แตะเงินเลย
```

---

### Flow ทั้งหมด (11 ขั้นตอน — Escrow Model)

```
1.  Viewer กดปุ่ม [บริจาค] → เลือกคำร้องและจำนวนเงิน
2.  ระบบสร้าง donation_transactions record (status: 'pending')
3.  Dev mode  → auto-confirm หลัง 1.5 วินาที (mock)
    Prod mode → แสดง PromptPay QR หรือ redirect Omise

4.  Payment Provider ส่ง Webhook ยืนยัน (Prod only)
5.  เรียก DB Function confirm_donation_transaction (atomic):
      a. donation_transactions.status = 'confirmed'
      b. donation_requests.current_amount += amount
      c. [NEW] ระบุ escrow_target = beneficiary_org_id ของ category
6.  [NEW] ทันทีที่ confirmed → ระบบสั่ง Gateway โอนเงินไปยัง
          Beneficiary Escrow Account แบบ batch (ไม่ใช่ทีละครั้ง)
          → donation_transactions.status = 'in_escrow'

7.  Emit WebSocket 'donation-confirmed' event พร้อม requestId + newTotal
8.  Real-time ตัวเลขอัปเดตบนจอผู้ชมทุกคนพร้อมกัน

──── ภารกิจสิ้นสุด ────
9.  Responder ทุกรายกด "เสร็จสิ้น" + Consensus ผ่าน
10. [NEW] ระบบส่งคำสั่ง "Release Escrow" ไปยัง Beneficiary Org
    → Beneficiary โอนยอดสะสมทั้งหมดให้ Reporter account
    → donation_transactions.status = 'disbursed'
11. Emit WebSocket 'donation-disbursed' + System Message ใน Chat
```

---

### Escrow Batch Transfer Policy

เพื่อลด transaction fees และ overhead ของ payment gateway:

| สถานการณ์ | วิธีโอนเข้า Escrow |
|:---|:---|
| **Real-time (Dev)** | mock — บันทึกสถานะ `in_escrow` ทันที ไม่โอนจริง |
| **Production (PromptPay)** | รวมยอดทุก `confirmed` ของวันแล้ว batch โอนรายวัน (End-of-Day) |
| **Production (Omise Card)** | โอนไปยัง Omise Recipient (Beneficiary) หลัง confirm ทันที |

> [!NOTE]
> Beneficiary Org ต้องลงทะเบียนเป็น **Omise Recipient** หรือ **PromptPay ที่ verify แล้ว** ก่อนจึงจะรับ escrow transfer ได้ — เป็นเงื่อนไขก่อน activate beneficiary

---

### สถานะใหม่ใน donation_transactions (Escrow States)

```
pending
  ↓ (payment confirmed)
confirmed
  ↓ (ส่งเข้า escrow)
in_escrow          ← เงินอยู่ที่ Beneficiary รอปล่อย
  ↓ (mission complete + consensus)
disbursed          ← โอนให้ Reporter สำเร็จ
  
  ─── กรณีพิเศษ ───
in_escrow → cancelled_refunded    ← คำร้องยกเลิก → Beneficiary คืนเงินผู้บริจาค
in_escrow → transferred_to_beneficiary ← ใช้ Beneficiary เก็บถาวร (ตามนโยบาย)
```

---

### Flow ใน Code (Flutter — Updated)

```dart
// เรียกจาก donation_sheet_widget.dart หรือ emergency_navigation_logic.dart
final result = await PaymentService.instance.initiateDonation(
  requestId: selectedRequestId,
  donorUserId: currentUser.id,
  amount: selectedAmount,
  method: PaymentMethod.mock, // Dev: ไม่เสียเงิน | Prod: .promptpay / .omiseCard
  // [NEW] escrow target ดึงจาก donation_categories.beneficiary_org_id
);

if (result.isConfirmed) {
  // เงินถูกส่งเข้า Escrow แล้ว — อัปเดต UI
  socket.emit('video-interaction', {
    'type': 'donation',
    'requestId': selectedRequestId,
    'amount': selectedAmount,
    'videoId': currentVideoId,
    'escrowStatus': 'in_escrow', // [NEW]
  });
} else if (result.isPending && result.qrPayload != null) {
  showPromptPayQrDialog(context, qrPayload: result.qrPayload!);
} else if (result.isFailed) {
  showErrorSnackbar(result.error ?? 'เกิดข้อผิดพลาด');
}
```

---

### ข้อแตกต่างจากระบบเดิม

| หัวข้อ | ระบบเดิม | ระบบใหม่ (Escrow) |
|:---|:---|:---|
| อัปเดตยอด | Optimistic (ทันที ไม่ verify) | หลังยืนยันการชำระจริงเท่านั้น |
| เงินพักอยู่ที่ไหน | ไม่ชัดเจน / Sheserved? | **Beneficiary Escrow Account** (บุคคลที่สาม) |
| โอนให้ผู้รับบริจาคเมื่อไหร่ | ทันที? | **หลัง Mission Complete + Consensus เท่านั้น** |
| กรณียกเลิก/ระงับ | ต้องเรียกเงินคืนจากผู้รับ | เงินยังอยู่ที่ Beneficiary — ไม่ต้องเรียกคืน |
| ภาษี / ข้อกฎหมาย | เสี่ยง | Sheserved ไม่ถือเงิน → ลดความเสี่ยงอย่างมาก |
| Audit Trail | ไม่มี | `donation_transactions` + `beneficiary_transfer_logs` |
| กันกด spam | ไม่มี | status `pending` ป้องกัน double-confirm |
| Dev ไม่เสียเงิน | เป็นแบบนี้อยู่แล้ว | Mock mode (1.5s delay → `in_escrow`) |
| Production | ไม่มีแผน | PromptPay batch / Omise Recipient ready |

---

### ข้อจำกัดและสิ่งที่ต้องพิจารณาเพิ่มเติม

> [!IMPORTANT]
> **Beneficiary Org ต้องเป็นนิติบุคคลที่จดทะเบียนถูกกฎหมาย** (มูลนิธิ / สมาคม / บริษัท) เพื่อให้การรับเงินและโอนต่อมีความถูกต้องตามกฎหมายไทย และสามารถออกใบเสร็จหรือหลักฐานการรับเงินได้

> [!WARNING]
> **กรณีที่ยังไม่มี Beneficiary Org ที่ verify แล้ว** → ให้ใช้ Dev/Mock mode เท่านั้น ห้ามรับเงินจริงจากผู้ใช้จนกว่า Beneficiary Org จะพร้อม

| ข้อจำกัด | แนวทาง |
|:---|:---|
| Beneficiary ต้องเป็นนิติบุคคล | ตรวจสอบเอกสารก่อน activate เสมอ |
| PromptPay batch มี delay 1 วัน | แสดง UI ชัดเจนว่า "ยอดแสดงบนจอ = ยอดสะสมที่รับรู้แล้ว" ไม่ใช่ยอดที่โอนจริงแล้ว |
| Beneficiary ต้อง agree เป็น escrow holder | ต้องมี MOU/ข้อตกลงกับ Org ก่อน |
| หาก Beneficiary ปฏิเสธ release | ต้องมี dispute mechanism (escrow release protocol) |

---




[SQL Schema Implemented]


---

## Donation Closure Policy (นโยบายปิดรับบริจาคหลังจบเหตุการณ์)

### หลักการหลัก: Donation follows Incident Lifecycle

```
สถานะ incident_responses.status:
  en_route  → resolved
                ↓
  donation_requests.approval_status:
  active    → closed
```

### รูปแบบการสิ้นสุดการรับบริจาค

#### รูปแบบที่ 1 — Consensus-Based Lifecycle: การจัดการยอดหลังจบภารกิจ

**ทริกเกอร์:** เมื่อ Responder **"ทุกราย"** กดปุ่ม **"เสร็จสิ้น"** (status: 'resolved')

**Action & Policy:**  
1. **สถานะเริ่มต้นหลังภารกิจจบ:** ระบบจะเปลี่ยนสถานะคำร้องบริจาคเป็น **"Pending Approval for Extension"** (หรือเข้าสู่โหมดพักชั่วคราว)
2. **เงื่อนไขการเปิดรับบริจาคต่อ:** 
   - ต้องได้รับการอนุญาต (Authorize) จาก **Responder "ทุกราย"** ที่ปฏิบัติหน้าที่ในเหตุการณ์นั้น
   - หากมี Responder **"แม้แต่เพียงรายเดียว"** ไม่อนุญาต → ระบบจะทำการ **"หยุดพักการรับบริจาค (Paused)"** ทันที
3. **การแจ้งเตือน (Notifications):**
   - **แจ้ง Reporter:** ส่งระบบแจ้งเตือนว่า "การรับบริจาคถูกระงับชั่วคราวเนื่องจากความเห็นของทีมช่วยเหลือไม่เป็นเอกฉันท์"
   - **แจ้งผู้บริจาค (Thai Mhung):** เมื่อกดปุ่มบริจาค ระบบจะแสดงข้อความแจ้งสาเหตุว่า "ระบบหยุดพักการรับบริจาคชั่วคราวเพื่อตรวจสอบความจำเป็นเพิ่มเติมโดยเจ้าหน้าที่"
4. **ความโปร่งใสผ่าน Live Chat (System Audit Trail):**
   - ทุกๆ การดำเนินการที่เกี่ยวข้องกับคำร้องบริจาค จะต้อง **ส่งข้อความระบบ (System Message)** ลงไปในแท็บ Chat ของ Live ทันที เพื่อบันทึกเป็นประวัติศาสตร์การเปิด-ปิด
   - **เหตุการณ์ที่จะส่งข้อความระบบ มีดังนี้:** 
     - **สร้างคำร้องใหม่:** *"[ระบบ] ผู้รายงาน/เจ้าหน้าที่ C ได้เปิดรับบริจาคใหม่: [ชื่อคำร้อง]"*
     - **อนุญาต/ระงับ (จาก Consensus):** 
       - *"[ระบบ] เจ้าหน้าที่ A อนุญาตให้เปิดรับบริจาคต่อหลังจบภารกิจ"*
       - *"[ระบบ] เจ้าหน้าที่ B โหวตระงับการรับบริจาค → ระบบเข้าสู่โหมดพักชั่วคราว"*
     - **ปิดรับบริจาค (Manual/Auto-Close):** *"[ระบบ] คำร้องบริจาค [ชื่อคำร้อง] ถูกปิดรับแล้ว"*
   - **เป้าหมาย:** เพื่อให้ทุกคนที่เข้ามารับชม รวมถึงผู้บริจาคไทยมุง ได้เห็นไทม์ไลน์และประวัติการตัดสินใจของเจ้าหน้าที่อย่างโปร่งใสว่าใครมีส่วนร่วมในการตัดสินใจบ้างตั้งแต่เริ่มเปิดจนถึงปิดรับบริจาค
5. **หากเห็นชอบครบทุกคน:** คำร้องจะคงสถานะ `active` เพื่อให้โอนเงินเข้าเหตุการณ์ที่จบไปแล้วได้ตามปกติ

> [!IMPORTANT]
> **ทำไมต้องมีระบบหยุดพัก?** เพื่อความโปร่งใสสูงสุด และป้องกันการเรียกร้องยอดบริจาคเกินความจำเป็นจริงหลังจบเหตุการณ์ หากผู้อยู่หน้างาน (Responder) เห็นว่าความช่วยเหลือนั้นเกินพอแล้ว ระบบต้องสามารถหยุดพักเพื่อตรวจสอบได้ทันที

> [!NOTE]
> คำร้องที่ status = 'pending' (ยังไม่ชำระ) ณ ขณะที่ระบบเข้าสู่โหมดพัก จะถูกระงับการจ่ายเงินจนกว่าจะได้รับความเห็นชอบครบจากทุกฝ่าย หรือถูกยกเลิกหากมีการโหวตระงับถาวร

---

#### รูปแบบที่ 2 — Manual Close: Reporter/Responder ปิดเอง

**ทริกเกอร์:** Reporter หรือ Responder กดปุ่ม **"ปิดรับบริจาค"** บนคำร้องของตนเอง

**Action:**  
→ อัปเดต `donation_requests.approval_status = 'closed'`  
→ Broadcast `'donation-request-closed'` เฉพาะคำร้องนั้น  

**เงื่อนไข:** เฉพาะเจ้าของคำร้อง (`user_id`) หรือ Responder ที่มีสิทธิ์เท่านั้น

---

#### รูปแบบที่ 3 — Time-Based Expiry (Optional)

**ทริกเกอร์:** คำร้องเปิดเกิน X วัน โดยไม่มีกิจกรรม (ยอดไม่ขยับ)

**Action:** Supabase Scheduled Function ตั้งค่า daily cron  
→ ปิดคำร้องที่ `approval_status = 'active'` และ `created_at < NOW() - INTERVAL '7 days'`

---

### DB Schema สำหรับปิดรับบริจาคและพักรับบริจาค


[SQL Schema Implemented]


---

### WebSocket Events ที่ต้องเพิ่ม (สำหรับการปิดรับบริจาค)

| Event | ทิศทาง | Payload | ผลลัพธ์ใน Flutter |
|:------|:-------|:--------|:----------------|
| `donation-request-closed` | Server → All Clients | `{ videoId, requestId, reason }` | คำร้องใน `_activeDonationRequests` ถูกเอาออก / UI เปลี่ยนสี |
| `incident-resolved` | Server → All Clients | `{ videoId }` | Auto-trigger การขอ Consent / ปิดคำร้องรับบริจาค |
| `donation-system-message` | Server → All Clients | `{ videoId, message, type }` | ส่ง System Message เข้า Live Chat แจ้งสถานการณ์รับบริจาคโปร่งใส |

---

## Beneficiary System (ระบบผู้รับมรดก — Updated 2026-04-08)

เพื่อความโปร่งใสและป้องกันเงินค้างระบบ ทุกหมวดหมู่การบริจาคต้องระบุ **หน่วยงานผู้รับมรดก (Beneficiary Organization)** ที่จะรับยอดเงินแทนผู้ร้องขอเดิม ในกรณีที่ไม่สามารถดำเนินการปกติได้

### นิยาม

> **ผู้รับมรดก** คือหน่วยงาน/บัญชีกองกลางที่ได้รับมอบหมายล่วงหน้า ให้รับยอดเงินบริจาคในกรณีพิเศษ 3 กรณีต่อไปนี้ โดยแต่ละ `donation_categories` ควรมี beneficiary ของตัวเอง และต้องมี **Global Default Beneficiary** เป็น fallback เสมอ หาก category ใดยังไม่ได้ตั้งค่า

---

### 1. กรณีที่ 1 — คำร้องถูกระงับจนถึง Deadline (Pause Expiry)

**ทริกเกอร์:** `is_paused = TRUE` และเวลาล่วงเลย `pause_deadline` ที่กำหนด

> **Grace Period** คำนวณจาก `donation_categories.pause_grace_period_hours` ของหมวดหมู่นั้นๆ (ค่า default = 72 ชั่วโมง หากยังไม่ได้ตั้งค่า)

**Flow:**
```
pause_deadline ถูก exceed
    ↓
ดึง pause_grace_period_hours จาก donation_categories
    ↓
ตรวจสอบ donation_transactions ที่ status = 'confirmed' แต่ยังไม่ disbursed
    ↓
ดึง beneficiary_org_id จาก donation_categories ของคำร้องนั้น
    ↓
โอนยอดสะสมทั้งหมดไปยัง beneficiary account
    ↓
อัปเดต donation_requests.closed_reason = 'transferred_to_beneficiary'
    ↓
Emit donation-system-message → Live Chat + FCM แจ้ง Reporter
```

**System Message ที่ต้องส่ง:**
- *"[ระบบ] คำร้องบริจาค [ชื่อ] หมดเวลาพักชั่วคราว → ยอดเงิน X บาท ถูกโอนให้ [ชื่อหน่วยงาน] ตามนโยบายผู้รับมรดก"*

---

### 2. กรณีที่ 2 — โอนเงินไปยังผู้ร้องขอไม่สำเร็จ (Transfer Failure)

**ทริกเกอร์:** Payment gateway ส่ง webhook `status = 'failed'` หรือ retry เกิน 3 ครั้ง

**Flow:**
```
transfer failed / retry หมดแล้ว
    ↓
บันทึก donation_transactions.status = 'transfer_failed'
    ↓
แจ้ง Reporter: "บัญชีปลายทางผิดพลาด — กรุณาแก้ไขภายใน 48 ชั่วโมง"
    ↓
  [A] Reporter แก้บัญชีสำเร็จ → โอนซ้ำปกติ
  [B] เกิน 48 ชั่วโมง → โอนให้ beneficiary_org_id อัตโนมัติ
    ↓
System Message + beneficiary_transfer_logs
```

> [!IMPORTANT]
> ต้องมี **grace period 48 ชั่วโมง** ให้ Reporter แก้ไขบัญชีก่อนโอนให้ Beneficiary เสมอ เพื่อไม่ให้ผู้เสียหายเสียสิทธิ์โดยไม่จำเป็น

---

### 3. กรณีที่ 3 — ยกเลิกการบริจาค (Donation Cancellation)

| สถานการณ์ย่อย | เงื่อนไข | การจัดการ |
|:---|:---|:---|
| **3a** | ยกเลิกก่อนชำระ (pending) | ลบ record ทิ้ง — ไม่มีเงินจริง ไม่ต้องโอนใคร |
| **3b** | ยกเลิกหลังชำระแล้ว (confirmed) ก่อนโอน | แจ้งผู้บริจาคเลือก: Refund หรือ Donate to Beneficiary |
| **3c** | Reporter ยกเลิกทั้งคำร้อง ขณะมียอดสะสม | Refund ทุก confirmed transaction หรือโอน Beneficiary ตาม Policy |

**นโยบาย:**
- ผู้บริจาคมีเวลาตามค่า `donation_categories.cancellation_grace_hours` (default 24 ชั่วโมง) เพื่อเลือก Refund หรือโอน Beneficiary
- หากหมดเวลา → ระบบโอนให้ Beneficiary อัตโนมัติ
- กำหนด Status Priority: `closed > cancelled > paused` — เมื่อ cancelled แล้ว ระบบหยุดรอ consensus ทันที

---

### 4. DB Schema — Beneficiary System


[SQL Schema Implemented]


> [!NOTE]
> สถานะ `'processing_transfer'` ใช้เป็น Lock ชั่วคราวเพื่อป้องกัน Race Condition ระหว่าง Refund กับ Beneficiary Transfer ที่อาจเกิดพร้อมกัน ต้องใช้ `SELECT ... FOR UPDATE` ใน DB Function คู่กันเสมอ

---

### 5. WebSocket Events — Beneficiary System

| Event | ทิศทาง | Payload | ผลลัพธ์ใน Flutter |
|:---|:---|:---|:---|
| `donation-transferred-to-beneficiary` | Server → All Clients | `{ videoId, requestId, beneficiaryName, amount, reason }` | System Message ใน Chat + อัปเดต UI สถานะคำร้อง |
| `donation-cancelled` | Server → All Clients | `{ videoId, requestId, refundType }` | แจ้งผู้บริจาคแต่ละราย เลือก Refund/Beneficiary |
| `beneficiary-transfer-pending` | Server → Reporter only | `{ requestId, deadline, reason }` | แจ้ง Reporter ให้แก้บัญชีก่อน deadline |

---

### 6. UI จัดการผู้รับมรดก (Admin UI)

ให้เพิ่ม UI จัดการผู้รับมรดกใน **2 จุด** เพื่อความโปร่งใส:

#### จุดที่ 1 — หน้าจัดการหมวดหมู่บริจาค (Category Admin Card — Full Wireframe)

การ์ดแต่ละหมวดหมู่ประกอบด้วย **3 ส่วนใหม่** ที่เพิ่มเข้ามาใน scroll view เดียวกัน:

> [!IMPORTANT]
> หมวดหมู่บริจาคทุกหมวดต้องระบุ **Beneficiary Org ที่เป็นนิติบุคคลที่จดทะเบียนถูกกฎหมาย** (มูลนิธิ / สมาคม / บริษัท) เนื่องจาก Beneficiary ทำหน้าที่เป็น **Escrow Account** รับเงินบริจาคทั้งหมดตลอดภารกิจ และค่าใช้จ่ายทุกรายการต้องแสดงให้ผู้บริจาค **acknowledge ก่อนชำระเงินทุกครั้ง**

```
┌──────────────────────────────────────────────────────────┐
│  📂 หมวดหมู่: ค่ารักษาพยาบาล          [✏️ แก้ชื่อ]       │
│  ══════════════════════════════════════════════         │
│                                                          │
│  ── ส่วนที่ 1: ผู้รับมรดก / Escrow Account ─────────── │
│                                                          │
│  ⚠️ IMPORTANT: ต้องเป็นนิติบุคคลที่จดทะเบียนถูกกฎหมาย   │
│  เงินบริจาคทั้งหมดจะพักที่บัญชีนี้จนภารกิจสมบูรณ์         │
│  ─────────────────────────────────────────────          │
│  🏥  มูลนิธิสาธารณสุขไทย                                  │
│      ธนาคาร: กสิกรไทย  |  บัญชี: 0XX-X-XXXXX-X           │
│      [✓ Verified] [✓ ใช้งาน]  [✏️ แก้ไข]                 │
│                                                          │
│  [+ เพิ่มผู้รับมรดกสำหรับหมวดหมู่นี้]                     │
│  ⚠️ (Warning ถ้า beneficiary_org_id = NULL)               │
│  🚫 (Block ถ้าไม่มี beneficiary + ไม่มี Global Default)   │
│                                                          │
│  ── ส่วนที่ 2: ระยะเวลาผ่อนผัน (Grace Period) ────────  │
│                                                          │
│  กรณีคำร้องถูกระงับจนถึง Deadline   (min: 12h)           │
│  [ 72  ] ชั่วโมง  ← NumberField (12–720)                 │
│                                                          │
│  กรณีโอนเงินไม่สำเร็จ (Transfer Failure)  (min: 6h)      │
│  [ 48  ] ชั่วโมง  ← NumberField (6–720)                  │
│                                                          │
│  กรณียกเลิกการบริจาค (Cancellation)  (min: 1h)           │
│  [ 24  ] ชั่วโมง  ← NumberField (1–720)                  │
│                                                          │
│  ℹ️ ค่าที่บันทึกมีผลกับคำร้องใหม่เท่านั้น                 │
│                                                          │
│  ── ส่วนที่ 3: ค่าใช้จ่ายแพลตฟอร์ม (Platform Fees) ───  │
│                                                          │
│  ℹ️ ยอดที่ผู้บริจาคเห็น = ยอดสุทธิหลังหักค่าใช้จ่าย     │
│                                                          │
│  🏦 บัญชีรับรายได้ของแพลตฟอร์ม (Sheserved Account)       │
│  [ dropdown เลือกบัญชีของ Sheserved ที่ลงทะเบียนไว้ ▼ ] │
│  ℹ️ ค่าใช้จ่ายทั้งหมดจะถูกโอนเข้าบัญชีนี้หลังจบภารกิจ     │
│                                                          │
│  รายการค่าใช้จ่าย                                        │
│  ┌─────────────────────────────────────────────────┐    │
│  │ #  ชื่อรายการ          ประเภท         จำนวน    │    │
│  │ 1  Sheserved Service   % of gross    [ 2.5 ] %  │    │
│  │ 2  Omise Gateway Fee   % per txn     [ 1.75] %  │    │
│  │ 3  Transfer Fee        Fixed ฿       [ 25  ] ฿  │    │
│  │                 [✏️ แก้ไข]  [🗑️ ลบ]  [↕️ เรียง]  │    │
│  └─────────────────────────────────────────────────┘    │
│  [+ เพิ่มรายการค่าใช้จ่าย]  ← ไม่จำกัดจำนวนรายการ       │
│                                                          │
│  📊 Live Preview (อ้างอิง Net Goal: 1,000 ฿)            │
│  🎯 Net Goal:                        1,000.00 ฿         │
│  ─────────────────────────────────────────────          │
│  + Sheserved Service 2.5%:          +   25.77 ฿         │
│  + Omise Gateway Fee 1.75%:         +   18.04 ฿         │
│  + Transfer Fee (Fixed):            +   25.00 ฿         │
│  ─────────────────────────────────────────────          │
│  🏦 Gross Target (ต้องเปิดรับ):      1,068.81 ฿         │
│                                                          │
│  ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──         │
│  [💾 บันทึกการตั้งค่าทั้งหมด]                             │
└──────────────────────────────────────────────────────────┘
```

**หมายเหตุ UI — ส่วนที่ 2 (Grace Period):**
- Min floor: Pause = **12h** / Transfer Failure = **6h** / Cancellation = **1h**
- Max: 720h (30 วัน) — validate ทั้ง Client และ Server
- แสดง label "(ค่าเริ่มต้นระบบ)" เมื่อยังไม่เคยตั้งค่า
- แสดง diff `72h → 96h` ก่อนบันทึกเสมอ
- Warning dialog ถ้าตั้งต่ำกว่า default เกิน 50%

**หมายเหตุ UI — ส่วนที่ 3 (Platform Fees):**
- ไม่จำกัด % สูงสุด — Admin เป็นผู้รับผิดชอบตามกฎหมายที่บังคับใช้
- Live Preview คำนวณ real-time: `Gross = Net ÷ (1 − Σ%fees) + Σfixed_fees`
- `fee_snapshot` ถูก save ลง `donation_requests` ณ เวลาสร้างคำร้อง — Admin เปลี่ยน fee ภายหลังไม่กระทบคำร้องที่มีอยู่
- ส่งออกรายงาน fee breakdown ต่อการ disburse ได้จาก Tab "รายงาน"

---

#### ส่วนที่ 3 ในการ์ด — 💰 รายละเอียด Fee Types (ขยายความ)

Admin สามารถ **เพิ่มรายการค่าใช้จ่ายได้ไม่จำกัด** ต่อหมวดหมู่ — ไม่มีการจำกัด % ล่วงหน้า

**ประเภทค่าใช้จ่ายที่รองรับ (เลือกได้ต่อรายการ):**

| `fee_type` | ความหมาย | วิธีคำนวณ |
|:---|:---|:---|
| `percent_of_gross` | % ของยอด escrow รวม | `rate × gross_amount` |
| `fixed_baht` | จำนวนเงินคงที่ (฿) | `amount` ต่อการ disburse 1 ครั้ง |
| `percent_per_transaction` | % ต่อ transaction ที่ชำระ | `rate × transaction_amount` |

**Wireframe ส่วน Fee ในการ์ดหมวดหมู่:**

```
┌──────────────────────────────────────────────────────────┐
│  ──────────────────────────────────────────────         │
│  💰  ค่าใช้จ่ายแพลตฟอร์ม (Platform Fees)                │
│  ℹ️ ยอดที่ผู้บริจาคเห็น = ยอดสุทธิหลังหักค่าใช้จ่าย    │
│                                                          │
│  รายการค่าใช้จ่าย                                        │
│  ┌─────────────────────────────────────────────────┐    │
│  │ #  ชื่อรายการ          ประเภท         จำนวน    │    │
│  │ 1  Sheserved Service   % of gross    [ 2.5 ] %  │    │
│  │ 2  Omise Gateway Fee   % per txn     [ 1.75] %  │    │
│  │ 3  Transfer Fee        Fixed ฿       [ 25  ] ฿  │    │
│  │ + เพิ่มรายการใหม่                               │    │
│  └─────────────────────────────────────────────────┘    │
│                                                          │
│  [+ เพิ่มรายการค่าใช้จ่าย]  ← ไม่จำกัดจำนวนรายการ      │
│                                                          │
│  ──────────────────────────────────────────────         │
│  📊 Live Preview (ยอดอ้างอิง: 1,000 ฿ net goal)         │
│                                                          │
│  🎯 ยอดที่ผู้รับต้องการ (Net Goal):    1,000.00 ฿       │
│  ─────────────────────────────────────────────          │
│  บวก Sheserved Service 2.5%:         +  25.77 ฿        │
│  บวก Omise Gateway Fee 1.75%:        +  18.04 ฿        │
│  บวก Transfer Fee (Fixed):           +  25.00 ฿        │
│  ─────────────────────────────────────────────          │
│  🏦 ยอดที่ต้องเปิดรับบริจาค (Gross):  1,068.81 ฿       │
│                                                          │
│  ℹ️ ผู้บริจาคจะเห็น Net Goal 1,000 ฿ บนหน้าจอ         │
│     ระบบเปิดรับจริง 1,068.81 ฿ (จ่ายครบ = Net ครบ)     │
│                                                          │
│  [💾 บันทึกรายการค่าใช้จ่าย]                             │
└──────────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> **ไม่มีการกำหนด % สูงสุดในระบบ** — Admin มีอำนาจกำหนดค่าใช้จ่ายตามความเหมาะสมและกฎหมายที่บังคับใช้ในขณะนั้น ทั้งนี้ Fee ทุกรายการต้องแสดงให้ผู้บริจาค **acknowledge ก่อนชำระเงินทุกครั้ง** เพื่อความโปร่งใสและป้องกันข้อพิพาท

---

### Net Goal / Gross Target UX Model (นโยบายการแสดงยอดบนหน้าจอ)

**หลักการ:** ยอดที่ผู้ใช้ทุกคน (ไทยมุง, Responder, Viewer) เห็นบนหน้า Emergency Live คือ **"ยอด Net"** ที่ปลายทางต้องการจริง — ระบบจะเปิดรับบริจาคให้ได้ **Gross = Net + ค่าใช้จ่ายทั้งหมด** โดยอัตโนมัติ

```
Reporter ตั้ง Net Goal: 1,000 ฿  ← "ฉันต้องการเงิน 1,000 ฿"
                ↓
ระบบคำนวณ Gross Target:
    Gross = Net ÷ (1 − total_percent_fees) − total_fixed_fees
    Gross ≈ 1,068.81 ฿  ← "ต้องเปิดรับเท่านี้จึงได้ Net ครบ"
                ↓
หน้าจอ Emergency แสดง:
    "ยอดที่ต้องการ: 1,000 ฿"  ← ทุกคนเห็น Net Goal
    Progress Bar: สะท้อน % ของ Gross ที่รับมาแล้ว
                ↓
ผู้บริจาคชำระเงิน → เงินสะสมใน Escrow (Gross)
                ↓
เมื่อ Gross ≥ 1,068.81 ฿ → ปิดรับ / Mission complete
                ↓
Disburse: Gross − Fees = 1,000 ฿ net → Reporter ✅
```

**ผลลัพธ์ต่อ UX:**
- ผู้บริจาครู้สึกว่า "บริจาคครบตามที่ปลายทางต้องการ" ทุกบาท
- ไม่มีความสับสนเรื่อง "บริจาคไปแล้ว แต่ผู้รับได้น้อยกว่า"
- Sheserved เก็บค่าใช้จ่ายจาก Gross ส่วนเกินโดยอัตโนมัติ

> [!NOTE]
> Reporter เห็น **ทั้ง Net Goal และ Gross Target** ในหน้า Create Donation Request เพื่อให้รู้ว่าต้องเปิดรับเท่าไหร่จึงได้เงินครบตามต้องการ — ผู้ชมเห็นเฉพาะ Net Goal เท่านั้น

---

### DB Schema — Flexible Fee System


[SQL Schema Implemented]


---

### Escrow Disburse Flow (Updated — พร้อม Fee Deduction)

```
1. Mission Complete + Consensus ผ่านทุกราย
      ↓
2. ดึง fee_snapshot จาก donation_requests (ไม่ใช้ category fee ปัจจุบัน)
      ↓
3. คำนวณยอดทุก confirmed transactions ใน escrow (gross_amount)
      ↓
4. คำนวณค่าใช้จ่ายแต่ละรายการตาม fee_snapshot:
     ├── percent_of_gross   → rate × gross_amount
     ├── percent_per_txn    → Σ (rate × each_transaction_amount)
     └── fixed_baht         → amount (คงที่ ครั้งเดียว)
      ↓
5. net_amount = gross_amount − Σ(all_fees)
      ↓
6. ตรวจสอบ min_net_amount:
     ถ้า net_amount < 0 → Error: ค่าใช้จ่ายเกินยอด → Alert Admin
      ↓
7. โอน net_amount ไปยัง Reporter (ผ่าน Beneficiary)
      ↓
8. บันทึก donation_disbursement_logs พร้อม fee_breakdown (JSONB)
      ↓
9. Emit 'donation-disbursed':
   { videoId, requestId, grossAmount, netAmount, totalFees, feeBreakdown }
      ↓
10. System Message ใน Live Chat:
    "[ระบบ] โอนเงินสำเร็จ — ยอดสุทธิ 1,000 ฿ ถึงผู้รับแล้ว
     (ยอดรวม 1,068.81 ฿ หักค่าใช้จ่าย 68.81 ฿)"
```

---

### Reporting System — ประวัติการโอนและค่าใช้จ่าย

**Tab ใหม่ในหน้าจัดการบริจาค: "รายงาน (Reports)"**

```
┌──────────────────────────────────────────────────────────┐
│  📋  รายงานการโอนเงินและค่าใช้จ่าย                       │
│  ──────────────────────────────────────────────         │
│  [ช่วงเวลา: เดือนนี้ ▼]  [หมวดหมู่: ทั้งหมด ▼]          │
│  [ส่งออก CSV]  [ส่งออก PDF]                              │
│                                                          │
│  สรุป                                                    │
│  ยอดรวม Gross:    45,230.00 ฿                            │
│  ยอดรวม Fees:      3,215.50 ฿  (7.11%)                  │
│  ยอดรวม Net:      42,014.50 ฿                            │
│                                                          │
│  รายการ (ล่าสุดก่อน)                                     │
│  ┌───────────────────────────────────────────────────┐  │
│  │ วันที่       │ คำร้อง    │ Gross  │ Fee   │ Net   │  │
│  │ 2026-04-08  │ [ลิงก์]   │ 1,069฿ │  69฿  │ 1,000฿│  │
│  │ 2026-04-07  │ [ลิงก์]   │   535฿ │  35฿  │   500฿│  │
│  └───────────────────────────────────────────────────┘  │
│  [ดูรายละเอียด Fee Breakdown] ← กดแต่ละแถว             │
└──────────────────────────────────────────────────────────┘
```

**Implementation Files เพิ่มเติม:**

| ไฟล์ | บทบาท |
|:---|:---|
| `supabase/migrations/XXXXXX_add_fee_system.sql` | `category_fee_items`, `donation_disbursement_logs`, alter `donation_requests` |
| `lib/features/donation/models/fee_item_model.dart` | `CategoryFeeItem`, `DisbursementLog`, `FeeBreakdown` |
| `lib/features/donation/services/fee_calculator_service.dart` | คำนวณ gross จาก net + snapshot fee |
| `lib/features/admin/pages/disbursement_report_page.dart` | Reporting UI + Export |
| `websocket-server/services/disbursement-service.js` | escrow release + fee deduction logic |





#### จุดที่ 2 — Tab ใหม่ในหน้าจัดการบริจาค (Donation Admin)
เพิ่ม Tab **"ผู้รับมรดก"** ที่แสดง:
- รายการ `beneficiary_organizations` ทั้งหมด (active/inactive)
- สถิติ: จำนวนครั้ง/ยอดเงินรวมที่โอนให้ Beneficiary แทนผู้ร้องขอเดิม
- ปุ่ม เพิ่ม / แก้ไข / ปิดใช้งาน Beneficiary
- Badge ⚠️ แสดง category ที่ยังไม่ได้กำหนด beneficiary

> [!IMPORTANT]
> เฉพาะ **Super Admin** เท่านั้นที่มีสิทธิ์เพิ่ม/แก้ไข beneficiary — ต้องบันทึก audit log ทุก update และ beneficiary ต้องผ่านขั้นตอน verify บัญชีธนาคารก่อน activate เสมอ

---

### 7. ปัญหาที่อาจเกิดขึ้น (Risk Analysis)

---

#### ความเสี่ยงที่ 1 — 🔐 Beneficiary Data ถูก Inject โอนเงินผิดบัญชี

**ปัญหา:** ผู้ไม่ประสงค์ดีเข้าถึง Admin UI แล้วแก้ไขข้อมูลบัญชีธนาคารของ Beneficiary ทำให้เงินโอนไปผิดปลายทาง

**แนวทางแก้ไข:**
- **Permission Guard**: เฉพาะ Role `super_admin` เท่านั้นที่แก้ไข `beneficiary_organizations` ได้ — บังคับด้วย Supabase RLS Policy
- **Verify ก่อน Activate**: บัญชีใหม่ที่เพิ่มเข้ามาต้องมีสถานะ `is_verified = FALSE` ก่อน และต้องผ่านขั้นตอน verify (เช่น Admin รายที่สองยืนยัน หรือแนบเอกสารหน้าบัญชี) ก่อน Activate
- **Immutable Audit Log**: ทุก INSERT/UPDATE ใน `beneficiary_organizations` ต้องบันทึก log พร้อม `changed_by`, `changed_at`, `old_value`, `new_value` ด้วย Supabase Trigger
- **Masked Display**: แสดงเลขบัญชีแบบ masked (`0XX-X-XXXXX-X`) ในหน้า Admin เสมอ — ต้องกด "เปิดเผยเลขเต็ม" พร้อม re-authenticate ก่อน


[SQL Schema Implemented]


---

#### ความเสี่ยงที่ 2 — ⏰ Race Condition ระหว่าง Refund กับ Beneficiary Transfer

**ปัญหา:** ผู้บริจาคกดขอ Refund ขณะที่ระบบ (Scheduled Job) กำลังโอนเงินให้ Beneficiary พร้อมกัน — อาจเกิดการ double-process หรือเงินเดินทาง 2 ทาง

**แนวทางแก้ไข:**
- **State Lock**: ก่อนดำเนินการโอนใดๆ ต้องอัปเดต `donation_transactions.status = 'processing_transfer'` ด้วย atomic query ก่อนเสมอ
- **Optimistic Locking**: ใช้ `WHERE status = 'confirmed'` ในเงื่อนไข UPDATE — ถ้า rows affected = 0 แสดงว่ามีคนอื่น Lock ไปก่อนแล้ว ให้ abort
- **DB Function Atomic**: ห่อทั้ง "lock + transfer" ไว้ใน DB Function เดียวด้วย Transaction เพื่อป้องกัน partial state


[SQL Schema Implemented]


---

#### ความเสี่ยงที่ 3 — 🏦 PromptPay/Omise ไม่รองรับ Auto-Refund ทุกกรณี

**ปัญหา:** PromptPay ไม่มี API สำหรับ Refund (โอนกลับ) — Omise รองรับ Refund เฉพาะ Card เท่านั้น ไม่รองรับ PromptPay QR ที่ชำระไปแล้ว

**แนวทางแก้ไข แบบ Phase:**

| Phase | การทำงาน | เงื่อนไข |
|:---|:---|:---|
| **Phase 1 (ปัจจุบัน)** | Admin รับ notification → โอนเงินคืนมือ → mark `status = 'refunded'` | ใช้ระหว่าง Dev/Staging |
| **Phase 2** | Omise Refund API สำหรับ Card payment | เมื่อเปิด Production + ใช้ Omise Card |
| **Phase 3** | PromptPay: แจ้งผู้บริจาคให้กรอกบัญชีรับคืน → โอนผ่าน SCB/KBank Open API | ระยะยาว |

**นโยบาย fallback ที่ต้องมีเสมอ:**
- ทุก Refund request ต้องส่ง FCM แจ้ง Admin ทันที
- มีหน้า Admin "รายการรอ Refund" เพื่อจัดการ manual โดยไม่ตกหล่น
- `donation_transactions.status = 'refund_pending'` สำหรับรอ Admin ดำเนินการ

---

#### ความเสี่ยงที่ 4 — 📢 ผู้บริจาคไม่รู้ว่าเงินถูกโอนไปยัง Beneficiary แทน

**ปัญหา:** ผู้บริจาคชำระเงินแล้วคาดหวังว่าเงินจะไปถึงผู้ร้องขอโดยตรง แต่ระบบโอนให้ Beneficiary แทน — หากไม่มีการแจ้งให้ทราบอาจเกิดข้อพิพาท

**แนวทางแก้ไข:**
- **Mandatory FCM**: ทุกกรณีที่ transfer ไปยัง Beneficiary ต้องส่ง Push Notification ถึงผู้บริจาคทันที พร้อมระบุ ชื่อหน่วยงาน + เหตุผล
- **In-app Timeline**: หน้าประวัติการบริจาคต้องแสดง final status ของแต่ละ transaction อย่างชัดเจน เช่น:
  - ✅ `โอนให้ผู้ร้องขอแล้ว`
  - 🔁 `โอนให้ [ชื่อหน่วยงาน] แทน — เหตุผล: คำร้องถูกระงับเกินระยะเวลา`
  - 💰 `คืนเงินแล้ว`
- **Pre-consent Disclosure**: ก่อนชำระเงิน ระบบต้องแสดง disclaimer ว่า *"ในกรณีที่คำร้องถูกระงับหรือยกเลิก ยอดเงินอาจถูกโอนให้หน่วยงาน [ชื่อ] แทน"* และให้ผู้บริจาค acknowledge ก่อน

---

#### ความเสี่ยงที่ 5 — 🏷️ Category ยังไม่มี Beneficiary ขณะที่ต้องโอนเงิน

**ปัญหา:** Admin ยังไม่ได้ตั้งค่า `beneficiary_org_id` ใน category นั้นๆ แต่เกิดเหตุการณ์ที่ต้องโอนให้ Beneficiary — ระบบจะโอนไปที่ไหน?

**แนวทางแก้ไข:**

```
ลำดับ Fallback ของ Beneficiary Lookup:
  1. donation_categories.beneficiary_org_id  ← ตั้งค่าต่อ category (อันดับแรก)
      ↓ ถ้า NULL
  2. beneficiary_organizations WHERE is_global_default = TRUE  ← กองกลางระบบ
      ↓ ถ้าไม่มี global default
  3. ระงับการโอน + แจ้ง Super Admin ทันที (email + FCM)
     บันทึก status = 'transfer_blocked_no_beneficiary'
     ← ห้ามปล่อยให้เงินค้างโดยไม่มีจุดหมาย
```

- **Admin Warning**: Category ที่ `beneficiary_org_id = NULL` ต้องมีป้าย ⚠️ สีส้มใน Category Admin ตลอดเวลา
- **Block Activation**: หาก Category ไม่มี beneficiary และไม่มี Global Default → ระบบ **ห้ามสร้างคำร้องบริจาค** ใน category นั้น (block ที่ UI และ API layer)

---

#### ความเสี่ยงที่ 6 — 🔄 Reporter ยกเลิกคำร้องขณะ Consensus ยังไม่ครบ

**ปัญหา:** Reporter กดยกเลิกคำร้อง แต่มี Responder บางรายที่กดโหวต consensus ไปแล้ว และมีเงินสะสมอยู่ในคำร้อง — สถานะจะ conflict กัน

**แนวทางแก้ไข:**
- **Status Priority Rule (Strict):** `closed > cancelled > paused > active`
  - เมื่อ `cancelled` → ระบบหยุดรับ consensus vote ทันที (ignore vote ที่มาทีหลัง)
  - เมื่อ `cancelled` → เริ่ม cancellation grace period ตาม `cancellation_grace_hours`
- **Notify All Responders**: ส่ง System Message ลง Live Chat ทันทีว่า:
  *"[ระบบ] Reporter ได้ยกเลิกคำร้องบริจาค [ชื่อ] — การโหวต Consensus ถูกยกเลิกโดยอัตโนมัติ"*
- **DB Guard**: ใช้ CHECK constraint หรือ trigger ป้องกันการ INSERT ลง `donation_closure_consensus` เมื่อ request ถูก cancel แล้ว


[SQL Schema Implemented]


---

#### ความเสี่ยงที่ 7 — ⚡ Grace Period ถูกตั้งค่าต่ำเกินไปจนผู้เสียหายไม่ทัน

**ปัญหา:** Admin อาจตั้ง `pause_grace_period_hours = 1` ทำให้ผู้ร้องขอ (Reporter) ไม่ทันรู้ตัวก่อนที่เงินจะถูกโอนให้ Beneficiary ไปแล้ว

**แนวทางแก้ไข:**
- **Minimum Floor**: กำหนด minimum ที่ **12 ชั่วโมง** ใน DB (`CHECK (pause_grace_period_hours >= 12)`) และใน UI (`min: 12`) สำหรับ Pause Deadline case
  - กรณี Transfer Failure: minimum **6 ชั่วโมง**
  - กรณี Cancellation: minimum **1 ชั่วโมง** (ยืดหยุ่นกว่า เพราะเจ้าของกด cancel เอง)
- **Warning Dialog**: ถ้า Admin ตั้งค่าต่ำกว่า default เกิน 50% ให้แสดง dialog เตือน เช่น:
  *"คุณกำลังตั้งระยะเวลาผ่อนผันต่ำกว่าค่าเริ่มต้น (24h → 12h) ซึ่งอาจทำให้ผู้ร้องขอไม่มีเวลาเพียงพอในการดำเนินการ ยืนยันหรือไม่?"*
- **Notification Trigger**: ระบบต้องส่งแจ้งเตือนล่วงหน้าให้ Reporter เมื่อเหลือเวลา **25% ของ grace period** เสมอ (เช่น grace = 48h → แจ้งเมื่อเหลือ 12h)

---

#### ความเสี่ยงที่ 8 — 🏚️ Beneficiary Account ถูกปิดหรือยกเลิกในภายหลัง

**ปัญหา:** Beneficiary organization ที่เคย active อยู่ ถูก `is_active = FALSE` หลังจากที่มีคำร้องที่รออยู่ — ระบบจะโอนไปยังบัญชีที่ปิดแล้ว

**แนวทางแก้ไข:**
- **Deactivation Check**: ก่อน deactivate beneficiary ระบบต้องตรวจสอบว่ามี `donation_requests` ที่ `is_paused = TRUE` และ `beneficiary_org_id` ชี้มาที่ org นี้หรือไม่ — ถ้ามีให้ **block การ deactivate** พร้อมแจ้งจำนวนคำร้องที่ affected
- **Cascading Reassign**: หากต้องการ deactivate จริง ต้อง reassign beneficiary ของทุก category ที่ใช้ org นี้ก่อน หรือกำหนด org ใหม่แทนผ่าน dialog
- **Runtime Check**: ทุกครั้งที่ระบบจะโอนเงิน ต้อง validate ว่า `beneficiary_organizations.is_active = TRUE` อีกครั้งก่อนส่ง — ถ้า FALSE ให้ escalate ไปยัง Global Default

```dart
// beneficiary_transfer_service.dart
Future<BeneficiaryOrg?> resolveBeneficiary(String categoryId) async {
  // 1. ลอง category-level beneficiary ก่อน
  final cat = await beneficiaryRepo.getCategoryBeneficiary(categoryId);
  if (cat != null && cat.isActive) return cat;

  // 2. Fallback: Global Default
  final global = await beneficiaryRepo.getGlobalDefault();
  if (global != null && global.isActive) return global;

  // 3. ไม่มี beneficiary ที่ใช้งานได้ → block + alert Admin
  await adminAlertService.notifyNoBeneficiary(categoryId);
  return null;
}
```

---

#### ความเสี่ยงที่ 9 — 💸 Partial Transfer (โอนสำเร็จบางส่วน บางส่วนล้มเหลว)

**ปัญหา:** คำร้องหนึ่งมีหลาย `donation_transactions` ที่ confirmed — ระบบโอนสำเร็จบาง transaction แต่บางอันล้มเหลวระหว่างทาง ยอดในระบบกับความจริงไม่ตรงกัน

**แนวทางแก้ไข:**
- **All-or-Nothing Policy**: ห่อการโอนทั้งหมดของคำร้องเดียวไว้ใน **DB Transaction เดียว** — ถ้า transaction ใดล้มเหลว ให้ rollback ทั้งหมด (ไม่ partial commit)
- **Batch Transfer**: รวมยอดทั้งหมดของคำร้องเป็น **การโอนครั้งเดียว** (single transfer) ไปยัง beneficiary แทนการโอนทีละ transaction — ลด overhead และ failure point
- **Idempotency Key**: สร้าง `idempotency_key` สำหรับแต่ละ beneficiary transfer เพื่อให้ retry ซ้ำได้โดยไม่โอนซ้ำ (ใช้ `request_id + reason` เป็น key)
- **Transfer Status Tracking**: อัปเดต `donation_transactions.status` ทั้งหมดเป็น `'transferred_to_beneficiary'` พร้อมกันใน transaction เดียวเท่านั้น

---

### 8. Implementation Files (Beneficiary + Fee + Escrow System)

#### 📦 Database Migrations

| ไฟล์ | บทบาท |
|:---|:---|
| `supabase/migrations/XXXXXX_add_beneficiary_system.sql` | `beneficiary_organizations`, `beneficiary_audit_logs`, `beneficiary_transfer_logs`, RLS + Triggers |
| `supabase/migrations/XXXXXX_add_escrow_columns.sql` | เพิ่ม `escrow_status`, `escrow_released_at`, `escrow_release_ref` ใน `donation_requests` |
| `supabase/migrations/XXXXXX_add_grace_period_columns.sql` | เพิ่ม `pause_grace_period_hours`, `transfer_failure_grace_hours`, `cancellation_grace_hours`, `beneficiary_org_id` ใน `donation_categories` |
| `supabase/migrations/XXXXXX_add_fee_system.sql` | `category_fee_items`, `donation_disbursement_logs`, เพิ่ม `goal_amount_net`, `goal_amount_gross`, `fee_snapshot` ใน `donation_requests` |

#### 🎯 Models (Dart)

| ไฟล์ | บทบาท |
|:---|:---|
| `lib/features/donation/models/beneficiary_model.dart` | `BeneficiaryOrganization`, `BeneficiaryAuditLog`, `BeneficiaryTransferLog` |
| `lib/features/donation/models/fee_item_model.dart` | `CategoryFeeItem`, `FeeBreakdown`, `DisbursementLog` |
| `lib/features/donation/models/donation_request_model.dart` | อัปเดต: เพิ่ม `goalAmountNet`, `goalAmountGross`, `feeSnapshot`, `escrowStatus` |

#### 🗄️ Repositories (Dart)

| ไฟล์ | บทบาท |
|:---|:---|
| `lib/features/donation/data/repositories/beneficiary_repository.dart` | CRUD `beneficiary_organizations` + fallback lookup chain |
| `lib/features/donation/data/repositories/fee_repository.dart` | CRUD `category_fee_items`, ดึง fee snapshot ตอนสร้าง request |
| `lib/features/donation/data/repositories/disbursement_repository.dart` | บันทึก/ดึง `donation_disbursement_logs` |

#### ⚙️ Services (Dart)

| ไฟล์ | บทบาท |
|:---|:---|
| `lib/features/donation/services/fee_calculator_service.dart` | คำนวณ Gross จาก Net Goal + fee snapshot, คำนวณ net ตอน disburse |
| `lib/features/donation/services/beneficiary_transfer_service.dart` | Beneficiary lookup (fallback chain), atomic lock + transfer |
| `lib/features/donation/services/escrow_release_service.dart` | Orchestrate: Fee deduction → Net calculation → Beneficiary release |

#### 🖥️ Admin UI Pages (Dart/Flutter)

| ไฟล์ | บทบาท |
|:---|:---|
| `lib/features/admin/pages/beneficiary_management_page.dart` | Tab "ผู้รับมรดก": รายการ orgs, สถิติ, verify workflow |
| `lib/features/admin/pages/disbursement_report_page.dart` | Tab "รายงาน": ประวัติโอน, fee breakdown, Export CSV/PDF |
| `lib/features/admin/widgets/category_card_widget.dart` | อัปเดต: เพิ่ม Beneficiary section + Grace Period section + Fee section |
| `lib/features/admin/widgets/fee_item_list_widget.dart` | Editable list ของ `category_fee_items` + Add/Edit/Delete |
| `lib/features/admin/widgets/fee_live_preview_widget.dart` | Live Preview: คำนวณ Gross จาก Net แบบ real-time |

#### 🌐 WebSocket Server (Node.js)

| ไฟล์ | บทบาท |
|:---|:---|
| `websocket-server/services/beneficiary-service.js` | Beneficiary lookup, atomic lock, transfer to Beneficiary escrow |
| `websocket-server/services/disbursement-service.js` | Escrow release + fee deduction + emit `donation-disbursed` |
| `websocket-server/jobs/escrow-deadline-checker.js` | Scheduled job: ตรวจ `pause_deadline` ที่เกินกำหนด → trigger transfer |

---

### 9. หมายเหตุสำคัญ — `current_amount` vs Net/Gross Model

> [!IMPORTANT]
> ตาราง `donation_requests.current_amount` ที่มีอยู่เดิมต้องถูก reinterpret ให้ชัดเจนว่าเก็บ **ยอด Gross ที่รับเข้ามาจริง** (เงินที่ผู้บริจาคชำระแล้ว) — ไม่ใช่ยอด Net
>
> **หน้า Emergency Live ต้องแปลงค่าก่อนแสดง:**
> ```
> displayed_amount = current_amount × (net_goal / gross_target)
>                 ≈ current_amount × net_ratio
> ```
> เพื่อให้ Progress Bar และตัวเลขบนจอสะท้อน "ยอด Net สะสม" ที่ผู้ชมเข้าใจง่าย

**สรุป field ที่เกี่ยวข้องใน `donation_requests`:**

| Field | ความหมาย | ใครเห็น |
|:---|:---|:---|
| `goal_amount_net` | ยอดที่ผู้รับต้องการจริง | **ทุกคน** (แสดงบนจอ) |
| `goal_amount_gross` | ยอดที่ต้องเปิดรับ (net + fees) | Reporter เท่านั้น |
| `current_amount` | ยอด Gross ที่รับเข้ามาจริงสะสม | ระบบ (แปลงเป็น net ก่อนแสดง) |
| `fee_snapshot` | JSONB รายการค่าใช้จ่าย ณ เวลาสร้าง | ระบบ (คำนวณ deduction ตอน disburse) |
| `escrow_status` | สถานะเงินใน escrow | Admin |

---

### 10. แผนงานในอนาคต (Future Implementations)

> [!TIP]
> ส่วนนี้เป็นการบันทึกแผนงานส่วนขยายที่ควรดำเนินการเมื่อพร้อมเปิดใช้งานระบบจริงจัง (Production) เพื่อลดภาระงานของทีม Admin และเพิ่มความปลอดภัยสูงสุด

#### 10.1 ระบบจัดการคิวคืนเงิน (Refund Queue)
จังหวะที่เงินเข้า Escrow ไปแล้ว และผู้บริจาคขอ Refund หรือ Admin สั่งปิดหมายด้วยสถานะ "ยกเลิก" ปัจจุบันฐานข้อมูลจะตีสถานะ Transaction จาก `in_escrow` เป็น `refund_pending` 

**แผนพัฒนาต่อยอด:**
- สร้าง Tab การจัดการ "รายการรอคืนเงิน" (Refund Queue) ใน Admin Dashboard
- **แบบ Manual:** Admin ดาวน์โหลดรายงานผู้ที่อยู่ในคิว `refund_pending` โอนเงินคืนผ่านแอปธนาคาร และกดปลดล็อคสถานะเป็น `refunded`
- **แบบ Automated:** เขียน Node.js Service เพื่อยิง API ของ Payment Gateway (เช่น Omise Reversal API) ในการ Void รหัส charge คืนเงินเข้าบัตรเครดิต โดยเมื่อ Payment Gateway ตอบรับว่าสำเร็จ ค่อยเปลี่ยนสถานะ Database อัตโนมัติ (หมายเหตุ: วิธีนี้อาจไม่รองรับ PromptPay)

#### 10.2 การตั้งค่าความปลอดภัยบน Production (Security Setup)
ห้ามให้ User ธรรมดามีสิทธิ์ดัดแปลงการโอนเงิน Escrow บน Database การทำงานส่วนนี้จึงถูกล็อคด้วย RLS ขีดสุด ดังนั้น Node.js ต้องถูกบังคับให้ใช้กุญแจผู้คุมระบบ

**ตัวอย่างวิธีการตั้งค่า `.env` ที่ถูกต้องบนเซิร์ฟเวอร์:**
```env
SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
# ห้ามใช้ ANON_KEY เด็ดขาด ให้ใช้ SERVICE_ROLE_KEY เท่านั้น สำหรับ Backend Services
SUPABASE_SERVICE_ROLE_KEY=<key จาก Supabase Dashboard → Settings → API → service_role>
```

> **หมายเหตุ (2026-05-26):** Supabase รองรับ key 2 format:
> - `eyJhbG...` (JWT format — โปรเจคเก่า)
> - `sb_secret_...` (Secret format — โปรเจคใหม่)
> ทั้งสองใช้ได้กับ `@supabase/supabase-js` และ Emergency Health Services — ตรวจสอบได้ด้วยคำสั่ง:
> ```bash
> node -e "const {createClient}=require('@supabase/supabase-js'); const c=createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY); c.from('videos').select('id').limit(1).then(({error})=>console.log(error?'❌ Key ไม่ถูกต้อง: '+error.message:'✅ Key ใช้ได้'))"
> ```

หากใช้ผิดกุญแจ (ตัวอย่างการนำ `anon_key` มาใส่) ลูปการโอนเงินคืน, Background Services และ Emergency Health Settings จะพังและถูกตีกลับด้วย Error `Supabase service client is not configured`

#### 10.3 ระบบลงทะเบียนรับมรดก (Partner Onboarding Portal / Self-Service Verification)
ในเวอร์ชันเปิดใช้งานจริง (Production) แพลตฟอร์มควรยกเลิกการให้ Admin เป็นผู้กรอกข้อมูลการเงินขององค์กรมูลนิธิด้วยตนเอง (Manual Data Entry) เพื่อเพิ่ม Scalability ตามหลัก Platform Economy
**แผนพัฒนาต่อยอด:**
- **Database (Supabase):** 
  - เพิ่มฟิลด์ `owner_user_id` ในตาราง `beneficiary_organizations` เพื่อผูกบัญชีมูลนิธิเข้ากับ User ของแอป
  - เพิ่มฟิลด์ `document_urls` (JSONB) เพื่อเก็บลิงก์รูปถ่ายสมุดบัญชีและไฟล์ MOU สัญญา
- **User App (Front-end): Concurrent Registration & Post-Registration UI** 
  - **ลงทะเบียนแบบคู่ขนาน (Concurrent Flow):** ในจังหวะที่ผู้ใช้ลงทะเบียนขอสิทธิ์วิชาชีพ (Profession Verification) ระบบสามารถเสนอหน้าต่างพ่วงให้แนบเอกสาร "ตัวแทนมูลนิธิ/รับมรดก" ไปพร้อมกันได้เลย โดยไม่ต้องรอวิชาชีพอนุมัติก่อน (แยกอิสระ) ข้อมูลจะส่งแยกกันไปเข้าคิว `Application Review` และ `Beneficiary Pending` พร้อมกัน
  - **แถบอนุมัติบริจาคในหน้า Profile (Post-Registration):** หากผู้ใช้ข้ามขั้นตอนไปก่อน ให้มีจุดเข้าถึง (Entry Point) เป็นเมนู "ลงทะเบียนองค์กรมูลนิธิ/MOU" ภายใต้แถบ "อนุมัติบริจาค (Donation/Escrow Settings)" ในหน้า Profile ส่วนตัว เพื่อให้สามารถยื่นเจตจำนงในภายหลังได้ด้วยตนเอง
- **Admin UI: Unified Admin Flow (ตรวจแบบไร้รอยต่อ)** 
  - เปลี่ยนบทบาทของ Admin ใน "แถบผู้รับมรดก" จากคนกรอกข้อมูล เป็น "คนตรวจ (Auditor)" 
  - เพิ่มแท็บย่อย **"รอตรวจสอบ (Pending Approval)"**
  - **Seamless Navigation:** ในหน้า "ตรวจสอบผู้สมัคร (Application Review)" หาก User คนที่แอดมินกำลังตรวจวิชาชีพอยู่ มีเอกสารมูลนิธิรอตรวจอยู่ด้วย ระบบจะขึ้น Badge/ปุ่มลัด สีสดใส เช่น `มีบัญชีมูลนิธิรอตรวจ` เมื่อแอดมินกดยืนยันวิชาชีพเสร็จ สามารถกดปุ่มนี้เพื่อ Route (`Navigator.push`) ข้ามไปยังหน้า "รอตรวจสอบ (Pending Approval)" ในแถบผู้รับมรดกได้อย่างต่อเนื่องโดยไม่ต้องกดถอยหลังกลับไปหาเมนูหลัก

---

## 11. Security & Implementation Safety (Updated 2026-04-16)

เพื่อปิดความเสี่ยงในการทำงานจริงบนระบบ Escrow & Notification ได้มีการอัปเดตแกนหลัก 4 ส่วนดังนี้:

### 11.1 ป้องกัน Race Condition ของระบบ Escrow (Pessimistic Locking)
- **Database RP**: ใช้ DB Function (`process_escrow_transfer`) ใน PostgreSQL ที่เรียกใช้ `SELECT ... FOR UPDATE NOWAIT` ในการล็อก Transaction อย่างเด็ดขาด ปิดช่องโหว่การใช้ Application-level Lock ที่อาจเกิดบั๊กเมื่อมีคำขอ Refund กับ Release โผล่มาพร้อมกัน

### 11.2 แยกสคริปต์ Dev Auto-Seeding อย่างเด็ดขาด
- **Strict Environment**: ป้องกันการให้สิทธิ์เจ้าหน้าที่กู้ภัยมั่วซั่วบน Production โดยลบโค้ด Auto-Seed ออกจาก `server.js` อย่างสมบูรณ์ 
- **ย้ายไปที่ Scripts**: รวมไว้ในไฟล์ `scripts/seeders/dev-seed.js` และให้ผู้พัฒนาสั่งรันด้วย `npm run seed:dev <userId>` ด้วยตนเองเท่านั้น (ทำงานได้แค่ในโหมด Development)

### 11.3 Webhook & Gateway Resiliency (BullMQ)
- **ระบบคิวแยก**: คิว Payment Transfer จะดูแลด้วย BullMQ 
- **Exponential Backoff**: โอนเงินล้มเหลวด้วยปัญหา Network จะถูกจัดคิววนกลับพร้อมระยะเวลา Backoff ที่ทวีคูณขึ้น
- **Circuit Breaker**: หาก Gateway พังเกิน Limit (เช่น 5 ครั้ง) จะเข้าสู่โหมดพัก (Open Circuit) และปรับสถานะ Transaction เป็น `transfer_failed` เพื่อส่งแจ้งเตือนให้ Admin Manual Retry ได้ทันท่วงที ป้องกันปัญหาเงินค้างท่อ

### 11.4 Local Sync State Management
- **Startup Reconciliation**: เพิ่ม `is_synced` ให้ฐานข้อมูลวิดีโอ 
- เครื่อง Server วิดีโอหลัก (Node.js) จะทำการรัน `reconcileLocalToCloud()` ทุกครั้งที่เปิดเครื่อง หากฐานข้อมูลในรถและบนคลาวด์ไม่ตรงกันเนื่องจากสภาวะอินเทอร์เน็ตหลุด มันจะ Upsert ข้อมูลการยอด Like/View คืนกลับเข้าสู่ Supabase ให้ทันทีเป็นสิ่งแรก

**กฎสำคัญ (อัปเดต 2026-05-26):**

- **Video Sync — Blacklist Local-only Columns**: ตาราง `videos` ในเครื่องหลักมี column พิเศษที่ไม่มีใน Cloud Schema (`address`, `alley`, `road`, `soi`, `village`, `cached_like_count`, `cached_view_count`, `category_id`, `is_synced`) — `sync-service.js` ใช้ `VIDEO_LOCAL_ONLY_COLUMNS` Set เพื่อกรอง column เหล่านี้ออกก่อน Upsert ทุกครั้ง หากเพิ่ม column ใหม่ที่ Local-only ต้องเพิ่มชื่อใน Set นี้ด้วย

- **Interaction Sync — Pre-filter Duplicates**: ก่อน Upsert interactions จะ Query Cloud เพื่อเช็ค tuple `(video_id, user_id, type)` ที่มีอยู่แล้ว — ถ้า Query ไม่ได้ (Network/Auth) จะ mark ทั้งหมดเป็น `is_synced = true` ใน Local เพื่อหยุด retry ซ้ำ

- **GPS Track Sync — FK Safety**: sync เฉพาะ tracks ที่ `video_id` ขึ้น Cloud แล้ว (`is_synced = true`) เพื่อป้องกัน FK constraint violation

### 11.5 Emergency Health Tables — FK ต้องชี้ไป `public.users` ไม่ใช่ `auth.users`

> **ปัญหาที่เกิดขึ้นจริง (2026-05-26):** ตาราง `emergency_health_data_settings`, `emergency_health_release_sessions`, `emergency_health_access_tokens`, `emergency_health_dead_man_checkins` ถูกสร้างด้วย `REFERENCES auth.users(id)` แต่โปรเจกต์นี้ **ไม่ได้ใช้ Supabase Auth** เลย (`auth.uid()` จะเป็น null เสมอ) ทำให้บันทึกข้อมูลไม่ได้และเกิด error:
> ```
> violates foreign key constraint "emergency_health_data_settings_user_id_fkey"
> ```

**กฎที่ต้องปฏิบัติสำหรับตาราง Emergency Health ทุกตาราง:**
- FK ที่อ้างถึง user ต้อง `REFERENCES users(id)` (public schema) เสมอ — **ห้ามใช้ `auth.users`**
- ปิด RLS (`DISABLE ROW LEVEL SECURITY`) เพราะ backend ใช้ service role key จัดการทั้งหมด
- ห้ามเขียน RLS policy ที่ใช้ `auth.uid()` ในตาราง emergency health

**Migration ที่ apply แล้ว:** `20260526144500_fix_emergency_health_fk_to_public_users.sql`

**หากสร้าง migration ใหม่สำหรับตาราง emergency health ให้ใช้ pattern นี้:**
```sql
-- ✅ ถูก
user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE

-- ❌ ผิด — auth.uid() เป็น null เสมอในโปรเจกต์นี้
user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
```

---

### 11.6 Unified Database & Race Condition Avoidance (Thai Mhung Gallery)
- **ปัญหาเดิม (Data Pollution)**: การใช้ Local API ก่อนหน้านี้ดึงภาพอ้างอิงตาทีละ `category_id` ทำให้เกิดปัญหา "ภาพปนกันข้ามเหตุการณ์"
- **การแก้ไข (Local API Fast-Path + URL Signature Filter)**: โค้ดใน Application เปลี่ยนวิธีค้นหาใหม่ โดยยังคงยิงหา Local PostgreSQL เพื่อให้ภาพโหลดขึ้นแกลลอรี่ไวที่สุดในหน่วยมิลลิวินาที (ไม่ต้องรอ Cloud Sync หรือหลบเลี่ยงปัญหา Table/RLS ใหม่) แต่เพิ่มกลไกคัดกรองขยะออก:
  - เรียก Local API แบบกวาดรูปไทยมุงทั้งหมดในเครื่อง
  - ฝั่งแอปจะทำการเช็ค Signature ของ Path URL (`.../[incidentId]/thaimhung/...`)
  - คัดเฉพาะรูปที่มี ID ตรงกับเหตุการณ์นี้มาแสดงเท่านั้น
- **ผลลัพธ์**: ขจัดการแสดงผลภาพมั่วซั่วให้เหลือเฉพาะภาพที่มาจากการ์ดเหตุการณ์เป๊ะๆ 100% พร้อมความเร็วแบบเรียลไทม์ผ่าน Local LAN

### 11.6 Thai Mhung Real-time Gallery Flow (WebSocket Implementation)
ได้มีการเปลี่ยนช่องทางหลักในการแจ้งเตือนภาพใหม่จากการพึ่งพา Supabase Realtime มาเป็น WebSocket-based เพื่อความเร็วและความแน่นอน (Low Latency) สูงสุดในสภาวะที่มีโหลดการใช้งานหนาแน่น:

```text
📱 User A อัปโหลดรูป
    │
    ▼
🖥️ Server (routes/video.js)
    ├── บันทึกลง DB + Supabase
    └── ✅ NEW: broadcastNewThaiMhungPhoto() → WebSocket Room "video-{incidentId}"
                    │
                    ▼
📱 User B (ฟังอยู่ใน Room เดียวกัน)
    ├── WebSocketService รับ event "new-thaimhung-photo"
    │       │
    │       ▼
    ├── thaiMhungPhotoStream → Gallery Widget
    │       ├── แทรกรูปที่ตำแหน่งบนสุด (Index 0)
    │       ├── เลื่อน scroll ไปโฟกัสรูปใหม่
    │       └── ส่ง onNewPhotoArrived → แสดงเอฟเฟกต์บนแผนที่
    │
    └── (Supabase Realtime ยังทำงานเป็น Backup ด้วย + มีการป้องกันซ้ำ)
```
- **ข้อดี**: 
  - ลดทราฟฟิกขาไปสู่ Supabase Cloud โดยใช้ Local WebSocket ทำงานแทน 
  - ผู้ใช้งานไม่ต้องรอการตรวจสอบ Transaction บน Cloud ทำให้เห็นภาพใหม่โผล่ขึ้นมาทันที (Instant Update)
  - ผูกเข้ากับระบบ Pan Map ช่วยให้อิริยาบถบนหน้าจอศูนย์สั่งการดูมีชีวิตชีวาและสะท้อนสถานการณ์จริงตลอดเวลา

### 11.7 Resilience & Fail-safe Mechanisms (Triple Redundancy)
เพื่อป้องกันปัญหา "ภาพไม่รีเฟรช" หรือ "การแจ้งเตือนไม่ขึ้น" เมื่อเกิดความขัดข้องในระดับเน็ตเวิร์คหรือฐานข้อมูล (เช่น Foreign Key Constraint ขวางการ INSERT บน Cloud) ระบบได้เพิ่มกลไก **Triple Redundancy** ดังนี้:

1.  **WebSocket Primary (Fastest)**: ใช้ `new-thaimhung-photo` event ยิงตรงจาก Server ไปยังทุก Client ในห้องวิดีโอทันทีหลังไฟล์เข้าสู่ระบบ ไม่ต้องรอผลลัพธ์จาก Database
2.  **Supabase Realtime (Backup Event)**: เฝ้าติดตามการเปลี่ยนแปลงที่ตาราง `thai_mhung_photos` โดยตรงผ่าน Cloud Channel เพื่อรองรับ Client ที่อาจมีปัญหาการเชื่อมต่อ WebSocket
3.  **Periodic Polling Fallback (Double Safety)**: กาเลอรี่จะทำ "Check-sum" มวลรวมของรูปภาพผ่าน Local API ทุกๆ 5 วินาที ด้วยตัวเอง (Self-check)
    - หากพบว่าจำนวนรูปภาพใน DB มากกว่าใน UI (โดยไม่ได้รับ Event จากข้อ 1 และ 2)
    - ระบบจะทำการดึงข้อมูลใหม่ (Fetch) และแทรกภาพลงบนสุด + เลื่อน Scroll + แสดงเอฟเฟกต์แผนที่ ให้โดยอัตโนมัติ
- **เป้าหมาย**: รับประกัน 100% ว่าเจ้าหน้าที่ศูนย์ควบคุมจะเห็นภาพล่าสุดจากพื้นที่ "ภายในไม่เกิน 5 วินาที" แม้ระบบคลาวด์จะล่มหรือเน็ตเวิร์คแกว่งก็ตาม
