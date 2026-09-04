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
    - ใช้ **WebSocket** กระจายอีเวนต์ `like-toggled`, `yield-way-updated`, `donation-progress-updated` และ `donation-closed` เพื่อให้แถบกราฟขยับแบบแอนิเมชันบนหน้าจอของผู้ใช้ทุกคนทันที
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
  - เรียกใช้ `DonationRepository.getRequestsByVideoId(videoId, activeOnly: true)` เพื่อดึงเฉพาะคำร้องที่ `approval_status = 'active'` — คำร้องที่ปิดรับแล้ว (`completed`) จะไม่แสดง
  - หลังการบริจาคสำเร็จ ให้ส่ง Event `donation-progress-updated` ผ่าน **Socket.io** เพื่อให้ระบบ Real-time Interactions แสดงยอดรวมอัปเดตทันที
  - รองรับ Event `donation-closed` จาก Server — เมื่อผู้ร้องขอปิดรับบริจาค ให้อัปเดต UI ซ่อนปุ่มบริจาคของคำร้องนั้นและแสดงข้อความแจ้งเตือนผู้ดูไลฟ์
  - **Request Mutation Policy**: เมื่อคำร้องเข้าสถานะ `active` แล้ว UI ฝั่งผู้ใช้ต้องแสดงผลแบบ read-only; ปุ่มแก้ไขจะมีเฉพาะ `pending_local` เท่านั้น ส่วนการจบคำร้องให้ใช้ `closeRequest()` หรือ `cancelRequest()` ตามเงื่อนไข และ `deleteRequest()` ต้องจำกัดเฉพาะ admin/maintenance ไม่ให้แสดงใน UI ฝั่งผู้ใช้
  - **Locked-state Hint**: หากผู้ใช้เปิดคำร้องที่ `active` หรือ `completed` ให้แสดงข้อความช่วยอธิบายว่า “เริ่มเปิดรับแล้ว ระบบล็อกการแก้ไขเพื่อความโปร่งใสต่อผู้บริจาค” เพื่อป้องกันความสับสน
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

### Redis Coordination

Phase 2 BullMQ (video transcode + thumbnail queue) และ Phase 1 middleware (rate limiter, idempotency, cache-aside) ใช้ `REDIS_URL` เดียวกันผ่าน `websocket-server/middleware/redis-client.js` เพื่อให้:

* Rate limiter/duplicate-check ก่อนเข้าคิวได้ผลทันที
* `idempotencyMiddleware` อ่าน `x-idempotency-key` header จากทุก API รวมถึง escrow transfer endpoints ที่สร้าง `idempotency_key`
* BullMQ jobs สามารถตรวจสอบ key state (เช่น `idem:` prefix) ได้ในการ retry และ auto-clean เดิม

ควรตรวจสอบให้แน่ใจว่า escrow transfer route ผ่าน middleware เดียวกับ `/api` หลัก (ติดตั้ง `defaultRateLimiter` + `idempotencyMiddleware`) เพื่อให้ `x-idempotency-key` ยังทำงานครบถ้วนก่อนส่งงานเข้า BullMQ queue.

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

#### ขั้นตอนที่ 3 — อัปเดต Server Environment (สำคัญมาก)
```bash
# websocket-server/.env
LOCAL_API_URL=http://192.168.X.X:8080  # ← เปลี่ยนตรงนี้
```
> **⚠️ ทำไมต้องทำ**: Backend ใช้ `LOCAL_API_URL` นี้ generate URL ในทุก field (`thumbnail_url`, `bunny_url`, `photo_urls`) ตอน upload/save ลง DB — ถ้าไม่เปลี่ยน backend จะยังใส่ IP เก่าใน DB ถึงแม้ Flutter จะแก้ `mainMachineIp` แล้วก็ตาม

#### ขั้นตอนที่ 4 — Restart Node.js Server (เพื่อโหลด `.env` ใหม่) + Start Caddy
```bash
cd websocket-server
# ต้อง restart เพื่อให้ Node.js อ่าน LOCAL_API_URL ใหม่
npm run dev

# terminal อีกอันสำหรับ reverse proxy
./start-caddy.sh
```
> ตรวจสอบ log ให้แน่ใจว่า Node.js รันที่ `:3000` และ Caddy รันที่ `:8080`
> **หมายเหตุ**: แค่แก้ `.env` ไม่พอ — ต้อง **restart Node.js** เพื่อโหลดค่าใหม่เข้า process

#### ขั้นตอนที่ 5 — ทดสอบ (Mandatory)
```bash
# จาก device อื่นในวง
curl http://192.168.X.X:8080/api/videos/emergency/list | python3 -m json.tool
```
> **ต้องตรวจสอบ**: ใน JSON response ทุก `thumbnail_url`, `bunny_url`, `photo_urls` ต้องขึ้นต้นด้วย `http://192.168.X.X:8080/` ไม่ใช่ IP เก่า (`192.168.1.xxx`, `172.20.xxx` ฯลฯ)
> 
> ถ้าเจอ IP เก่า → แสดงว่า Backend ยังใช้ `LOCAL_API_URL` เดิม → กลับไปทำขั้นตอนที่ 3-4 ใหม่

---

### 📋 ไฟล์ทั้งหมดที่ต้องแก้เมื่อเปลี่ยน IP

| ไฟล์ | ค่าที่ต้องแก้ | หมายเหตุ |
|------|--------------|----------|
| `lib/config/app_config.dart` | `mainMachineIp` | Flutter auto-normalize URL เก่าใน DB ให้ชี้ไป Caddy (`:8080`) |
| `websocket-server/.env` | `LOCAL_API_URL` | URL ที่ Server ใช้ generate thumbnail URL ผ่าน Caddy |
| `websocket-server/start-caddy.sh` | Caddy startup script | ใช้ `Caddyfile.dev` สำหรับ Phase 1 (`:8080`) |
| `websocket-server/Caddyfile.dev` | Caddy dev config | bind port `8080` โดยไม่ต้อง sudo |

> **ไม่ต้องแก้**: DB records เก่า — `_normalizeLocalUrl()` ใน Flutter จัดการแก้ URL ที่ดึงมาจาก DB ให้ชี้ไป IP ปัจจุบันได้
> 
> **แต่**: `_normalizeLocalUrl()` เป็น **fallback ชั่วคราว** สำหรับข้อมูลเก่าเท่านั้น — ถ้า backend ยัง generate URL ใหม่ด้วย IP เก่า (เพราะ `LOCAL_API_URL` ผิด) ข้อมูลใหม่ที่ upload จะมี URL ผิดถาวร

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

### 🛠️ Backend Dependency Recovery — `Cannot find module` (Updated 2026-09-03)

> **อาการ**: รัน `npm start` ใน `websocket-server` แล้ว Node.js crash ทันทีพร้อมข้อความ `Error: Cannot find module '<package>'` ทั้งที่ `package.json` ระบุแพ็กเกจนั้นอยู่ — พบจริงกับ `pino` และ `uuid`

#### สาเหตุ

1. **`node_modules/` และ `package-lock.json` ไม่ตรงกับ `package.json`** — เกิดจากการลบ `node_modules` ด้วยตนเอง, `flutter clean` ที่ลบทับ, หรือการ restore จาก backup ที่ไม่ครบ
2. **แพ็กเกจอยู่ใน `overrides` เท่านั้น ไม่ได้อยู่ใน `dependencies`** — `overrides` บังคับเวอร์ชันเฉพาะเมื่อแพ็กเกจนั้นถูกติดตั้งเป็น transitive dependency เท่านั้น ไม่ได้ติดตั้งแพ็กเกจโดยตรง ทำให้ `require('uuid')` ใน source code ล้มเหลว
3. **`npm install` รายงาน `up to date` ทั้งที่ขาดแพ็กเกจ** — เพราะ `package-lock.json` เก่ายังค้างอยู่และ npm คิดว่า tree สมบูรณ์แล้ว

#### วิธีแก้ไข (ตามลำดับ)

**กรณีที่ 1 — แพ็กเกจอยู่ใน `dependencies` แล้ว แต่ `node_modules` หาย**

```bash
cd websocket-server
rm -rf node_modules package-lock.json
npm install
```

> ลบ `package-lock.json` ด้วยเพื่อบังคับให้ npm สร้าง tree ใหม่จาก `package.json` ปัจจุบัน ไม่ใช่ lock เก่า

**กรณีที่ 2 — แพ็กเกจอยู่ใน `overrides` เท่านั้น ไม่มีใน `dependencies`**

ย้ายแพ็กเกจจาก `overrides` ไป `dependencies` ด้วย ดังตัวอย่าง `uuid`:

```diff
  "dependencies": {
    ...
-   "socket.io": "^4.8.3"
+   "socket.io": "^4.8.3",
+   "uuid": "^11.1.1"
  },
  "overrides": {
    "brace-expansion": "^5.0.8",
    "ws": "^8.21.0",
    "uuid": "^11.1.1",
    "engine.io": "^6.6.8"
  }
```

> `overrides` ควรเก็บไว้เพื่อบังคับเวอร์ชัน transitive dependencies แต่ต้องเพิ่มแพ็กเกจเดียวกันใน `dependencies` ด้วยถ้า source code `require()` มันโดยตรง

จากนั้นรัน:

```bash
npm install
npm start
```

#### การตรวจสอบก่อนเริ่มเซิร์ฟเวอร์ (Pre-flight Check)

ก่อนรัน `npm start` ทุกครั้งหลังเปลี่ยนเครื่อง/restore repo ให้ตรวจสอบ:

```bash
cd websocket-server
# ตรวจว่าแพ็กเกจหลักที่ source code เรียกใช้มีอยู่จริง
ls node_modules/pino node_modules/uuid node_modules/express node_modules/socket.io 2>&1
# ถ้ามี "No such file or directory" ให้รัน rm -rf node_modules package-lock.json && npm install
```

#### แพ็กเกจที่เคยเจอปัญหา (Watchlist)

| แพ็กเกจ | สาเหตุ | วันที่เจอ |
|---------|--------|----------|
| `pino` | `node_modules` หายหลัง restore/clean | 2026-09-03 |
| `uuid` | อยู่ใน `overrides` เท่านั้น ไม่มีใน `dependencies` | 2026-09-03 |

> หากเพิ่ม dependency ใหม่ในอนาคต ให้ตรวจสอบว่าอยู่ใน `dependencies` (ไม่ใช่แค่ `overrides`) และทดสอบ `npm start` หลัง `rm -rf node_modules && npm install` ทุกครั้ง

---

### 🕒 Trending Card Timestamp Display Policy (Updated 2026-09-01)

> **ไฟล์ที่เกี่ยวข้อง:** `lib/features/video/presentation/pages/widgets/trending_panel_widget.dart`, `websocket-server/routes/video.js`

การ์ดเหตุการณ์ใน Trending Panel ต้องแสดงเวลาตามกฎต่อไปนี้ — **ทุกกรณีต้องใช้ `video.createdAt` ของผู้สร้างสื่อเท่านั้น** ห้ามใช้ `updated_at`, เวลาเซิร์ฟเวอร์ปัจจุบัน, เวลาประมวลผล, หรือเวลา generate thumbnail แทน

#### รูปแบบการแสดงผล

| อายุสื่อ | ข้อความที่แสดง | ตัวอย่าง |
|---------|---------------|---------|
| < 1 นาที | `เมื่อครู่นี้` | `เมื่อครู่นี้` |
| 1–59 นาที | `N นาทีที่แล้ว` | `15 นาทีที่แล้ว` |
| ≥ 1 ชั่วโมง | วันที่และเวลาแบบไทย (24 ชม.) | `25 พ.ค.69 12.22 น.` |

#### Logic ฝั่ง Flutter

```dart
final createdAt = AppConfig.toThailand(video.createdAt);
final now = AppConfig.thailandNow;
final diff = now.difference(createdAt);

final dateStr =
    diff.inMinutes >= 0 && diff.inMinutes < 60
      ? diff.inMinutes == 0
          ? 'เมื่อครู่นี้'
          : '${diff.inMinutes} นาทีที่แล้ว'
      : _formatThaiDate(createdAt);
```

`_formatThaiDate()` ใช้:
- เดือนย่อภาษาไทย (พ.ค., มิ.ย., ...)
- ปี พ.ศ. (ค.ศ. + 543) แสดงเป็นเลข 2 หลักท้าย (`69` สำหรับ 2569)
- เวลา 24 ชั่วโมง คั่นด้วยจุด
- คำลงท้าย `น.`

#### ฝั่ง Backend (Mandatory)

- Query `/api/videos/emergency/list` ต้อง SELECT `v.created_at` ออกมาด้วยเสมอ
- Cache key ของ emergency list ต้องถูก version เพื่อป้องกัน client ได้ response เก่าที่ไม่มี `created_at`
- หาก `created_at` หายไป Flutter จะ fall back ไปใช้ `DateTime.now()` ซึ่งผิด — ต้องไม่เกิดกรณีนี้

#### ข้อควรระวัง

- ข้อความ relative (`เมื่อครู่นี้`, `N นาทีที่แล้ว`) เปลี่ยนได้ตามเวลาที่ผ่านไป แต่ต้องคำนวณจาก `created_at` ที่คงที่เท่านั้น
- รูปแบบ absolute (`25 พ.ค.69 12.22 น.`) ต้องคงที่ ไม่เปลี่ยนตามเวลา
- ใช้พฤติกรรมเดียวกันทั้งการ์ดวิดีโอและการ์ดภาพ emergency

---

### 👁️ Cumulative Viewer Count Badge (Updated 2026-09-01)

> **ไฟล์ที่เกี่ยวข้อง:** `lib/features/video/presentation/pages/widgets/trending_panel_widget.dart`, `lib/services/websocket_service.dart`, `websocket-server/server.js`, `websocket-server/routes/video.js`

การ์ดใน Trending Panel แสดง **จำนวนผู้เข้าชมสะสม (Cumulative Viewer Count)** ที่มุมขวาบนของการ์ด — ไม่ใช่จำนวนผู้ชมพร้อมกันในห้อง (Concurrent Viewers)

#### คำจำกัดความ (แยกจากกันชัดเจน)

| แนวคิด | ความหมาย | ฟิลด์/Event |
|--------|---------|-------------|
| **Cumulative Viewer Count** | ยอดรวมผู้เคยเปิดดูวิดีโอตั้งแต่สร้าง | `cached_view_count` → `viewer_count` (API), `_viewerCount` (Flutter), event `cumulative-viewer-count` |
| **Concurrent Viewers** | จำนวนผู้ชมที่อยู่ในห้องวิดีโอ ณ ขณะนั้น | event `viewer-count` |

#### Data Flow

1. ผู้ใช้เปิด/เลือกการ์ดวิดีโอ → Flutter ส่ง `record-view` ผ่าน WebSocket
2. Server insert row `view` ลง `video_interactions`
3. Database trigger `trg_update_interaction_counts` อัปเดต `cached_view_count` ในตาราง `videos` อัตโนมัติ
4. Server อ่าน `cached_view_count` ล่าสุดจาก PostgreSQL แล้ว broadcast `cumulative-viewer-count` ให้ทุก client
5. Trending Panel รับ event และอัปเดต badge ทันที

#### กัน Double Count

- ห้ามเพิ่ม `cached_view_count` ในโค้ดฝั่ง server ด้วยมือ — ให้ trigger เป็นคนเพิ่มอย่างเดียว
- `TrendingPanelWidget` มี guard กันบันทึกซ้ำเมื่อเลือกการ์ดเดิมซ้ำ หรือระหว่าง card transition
- หนึ่งการเลือกการ์ด = หนึ่งการนับ view

#### ฝั่ง Backend

- Query `/api/videos/emergency/list` ต้อง SELECT `v.cached_view_count AS viewer_count`
- ฟอร์แมตตัวเลขแบบ compact ฝั่ง Flutter: `999`, `1.2K`, `1.5M`

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

### 🐛 Phase 2 Queue Integration Bug — `retryJob is not defined`

> วันที่พบ: 2026-06-09 | สถานะ: ✅ แก้ไขแล้ว | ไฟล์: `websocket-server/queues/index.js`

#### อาการ
- `npm run dev` หรือ `node server.js` crash ทันทีตอน startup
- Error: `ReferenceError: retryJob is not defined` ที่ `queues/index.js:233`
- ผลกระทบ: Node.js ไม่รัน → Caddy ตอบ `502 Bad Gateway` → Flutter ไม่โหลดการ์ด/รูปภาพ

#### สาเหตุ
`retryJob()` ถูกวางอยู่ **กลาง function `shutdownAll()`** (nested scope) แทนที่จะเป็น top-level function → ตอน `module.exports` หา reference ไม่เจอ

#### วิธีตรวจสอบก่อน deploy
```bash
# 1. ตรวจสอบว่าฟังก์ชันที่ export อยู่ระดับ top-level
grep -n "async function retryJob" websocket-server/queues/index.js
# ต้องแสดงบรรทัดที่อยู่ **นอก** function อื่น (ไม่ใช่ nested)

# 2. ลองรัน Node.js ดูว่า startup ผ่านหรือไม่
cd websocket-server && node -c server.js
# หรือรัน health check หลัง start
curl http://localhost:3000/health
```

#### วิธีแก้ไข
ย้าย `retryJob()` ออกมาอยู่ **ระดับ top-level** (นอก `shutdownAll()`) ก่อน `module.exports`:

```javascript
// websocket-server/queues/index.js

// ── Retry Job ─────────────────────────────────────────────
async function retryJob(queueName, jobId) {
  const entry = registry.find((e) => e.name === queueName);
  if (!entry || !entry.queue) {
    throw new Error(`Queue "${queueName}" not found in registry`);
  }
  const job = await entry.queue.getJob(jobId);
  if (!job) {
    throw new Error(`Job ${jobId} not found in queue ${queueName}`);
  }
  await job.retry();
  return { jobId, queueName };
}

// ── Exports ────────────────────────────────────────────────
module.exports = {
  registry,
  shutdownAll,
  getHealthSnapshot,
  getFailedJobs,
  retryJob,  // ← ต้องอยู่ใน exports
  // ...
};
```

#### ป้องกัน
- หลังแก้ไฟล์ `queues/index.js` ให้รัน `node -c server.js` เพื่อ syntax check ก่อน commit
- ตรวจสอบว่าฟังก์ชันใหม่ไม่ถูกวาง nested ใน `shutdownAll()`, `getHealthSnapshot()` หรือ function อื่น
- ใช้ `eslint` หรือตรวจสอบ indentation ว่า `async function` อยู่ระดับเดียวกับ `module.exports`

---

### 🐛 Video Player `bunnyUrl` IP Normalization Bug (Fixed 2026-09-01)

> **วันที่พบ:** 2026-09-01 | **สถานะ:** ✅ แก้ไขแล้ว | **ไฟล์:** `lib/features/video/data/repositories/video_repository.dart`, `lib/features/video/presentation/pages/parts/emergency_navigation_logic.dart`

#### อาการ
หลังเปลี่ยน IP เครื่องหลัก (เช่นจาก `172.20.10.13` เป็น `192.168.1.129`) แล้วอัปเดต `AppConfig.mainMachineIp` กับ `LOCAL_API_URL` ทั้งหมด:
- Thumbnail บน Trending Card โหลดได้ (Flutter `_normalizeLocalUrl()` ทำงาน)
- API / WebSocket ต่อได้
- แต่ **Video Player (ExoPlayer/Android)** ไม่สามารถเล่นวิดีโอได้ และ logcat แสดง:
  ```
  java.net.SocketTimeoutException: failed to connect to /172.20.10.13 (port 8080) from /192.168.1.126 (port ...) after 8000ms
  ```

#### สาเหตุ
1. `bunnyUrl` ที่ได้จาก DB ยังเก็บ URL เก่า `http://172.20.10.13:8080/temp/videos/.../index.m3u8`
2. `emergency_navigation_logic.dart` ส่ง `video.bunnyUrl!` เข้า `_initializePlayer(...)` โดยตรง โดยไม่ผ่าน normalization
3. `_ensureFullUrl()` ใน `video_repository.dart` แก้เฉพาะ `localhost:3000` และ `http://...:3000` ไม่ได้จัดการ `http://...:8080` (Caddy Phase 1) ทำให้ URL HLS ยังชี้ไป IP เก่า

#### วิธีแก้ไข
**1. ปรับ `_ensureFullUrl()` ให้ normalize ทุก local IP/hostname** (`lib/features/video/data/repositories/video_repository.dart`):
```dart
String _ensureFullUrl(String url) {
  if (url.isEmpty) return '';
  final baseUrl = AppConfig.localApiUrl;

  // ✅ CDN (https) ไม่ต้องแตะต้อง
  if (url.startsWith('https://')) return url;

  // ✅ Normalize ทุก local URL ที่ชี้ไป backend เก่า
  // Phase 1 ใช้ Caddy ผ่าน AppConfig.localApiUrl (เช่น http://192.168.1.129:8080)
  if (url.startsWith('http://')) {
    // กรณี localhost ทุก port
    if (url.startsWith('http://localhost')) {
      return url.replaceFirst(
        RegExp(r'^http://localhost(:\d+)?'),
        baseUrl,
      );
    }

    // กรณี http://172.20.10.13:8080/... หรือ http://192.168.0.116:3000/...
    // แทนที IPv4:port เก่าด้วย Caddy endpoint ปัจจุบัน
    return url.replaceFirst(
      RegExp(r'http://\d+\.\d+\.\d+\.\d+(:\d+)?'),
      baseUrl,
    );
  }

  // ✅ Relative path → เติม baseUrl
  String fullUrl;
  if (url.startsWith('/')) {
    fullUrl = '$baseUrl$url';
  } else {
    fullUrl = '$baseUrl/$url';
  }

  return fullUrl;
}
```

**2. ส่ง `bunnyUrl` ผ่าน `ensureFullUrl()` ก่อนเข้า video player** (`lib/features/video/presentation/pages/parts/emergency_navigation_logic.dart`):
```dart
} else if (video.bunnyUrl != null && video.bunnyUrl!.isNotEmpty) {
  _initializePlayer(
    ServiceLocator.instance.videoRepository.ensureFullUrl(video.bunnyUrl!),
    isLocal: false,
  );
}
```

#### ป้องกัน
- เมื่อแก้ IP ตาม Runbook ต้องทดสอบไม่ใช่แค่ thumbnail/API แต่ต้อง **ทดสอบเล่นวิดีโอจริง** (ExoPlayer)
- ค้นหา `\.bunnyUrl` หรือ `_initializePlayer\(.*video\.bunnyUrl` ทั้งหมดใน project ให้ผ่าน `ensureFullUrl()` หรือ `_normalizeLocalUrl()` เสมอ
- รักษา `AppConfig.localApiUrl` ให้ชี้ไป Caddy endpoint (`:8080`) ไม่ใช่ Node.js port `:3000` ตรง ๆ

---

## Phase — Responder Route Color by Profession

> Planned: 2026-09-03
> Status: Pending implementation

### 1. Objective
เปลี่ยนเส้นประ (dashed polyline) ของจิตอาสาใน `EmergencyLivePage` จากสีฟ้าคงที (`Colors.blue`) ให้ใช้สีตาม `professionColor` ของแต่ละคน (`professions.color_hex`)

### 2. Background
`MapBackgroundWidget` วาดเส้นทางของแต่ละจิตอาสาด้วยสีฟ้าคงที:

```dart
color: Colors.blue.withOpacity(0.6),
```

ปัจจุบัน `GET /api/videos/:id/responders` ส่ง `profession_color` กลับมาแล้ว และ `VideoRepository.getIncidentResponders` map เป็น `professionColor` นอกจากนี้ `MapBackgroundWidget` ยังใช้ `professionColor` กำหนดสีของ marker อยู่แล้ว ดังนั้นการนำไปใช้กับ `Polyline` จึงทำได้โดยไม่ต้องเพิ่ม API ใหม่

### 3. Implementation Steps

#### 3.1 Flutter — `lib/features/video/presentation/pages/widgets/map_background_widget.dart`
- ในส่วนสร้าง `Polyline` ของ responder ให้ parse `r['professionColor']` ก่อนกำหนด `color`
- แปลง hex string เป็น `Color` ด้วย pattern เดียวกับ marker
- คงค่า `.withOpacity(0.6)` และ `dash pattern` ไว้
- Fallback ไป `Colors.blue` เมื่อไม่มีสีหรือ parse ไม่ผ่าน

#### 3.2 Backend — `websocket-server/routes/video.js`
- ตรวจสอบ `GET /:id/responders` ว่า `SELECT p.color_hex` ครบทุก responder
- ตรวจสอบ Supabase fallback ใน `video_repository.dart` ว่าดึง `professions.color_hex` ด้วย
- (Optional) เพิ่ม `p.category` หากต้องการรองรับ "สีกลุ่มอาชีพ" ในอนาคต

### 4. Edge Cases

| สถานการณ์ | การจัดการ |
|---|---|
| `professionColor` เป็น `null` | ใช้ `Colors.blue` |
| hex ไม่ถูกต้อง | ใช้ default และ log warning |
| จิตอาสาหลายคนอาชีพเดียวกัน | เส้นซ้อนทับสีเดียวกัน แก้ด้วย dash pattern ที่มีอยู่ |
| Web platform | Google Maps web รองรับ `Polyline` สี custom ปกติ |

### 5. Testing Checklist
- [ ] Responder 1 คน มีสีตามอาชีพ
- [ ] Responder หลายคนหลายอาชีพ เส้นเป็นคนละสี
- [ ] `professionColor` เป็น null/invalid ไม่ crash
- [ ] สีเข้มไม่บดบังแผนที่ (opacity 0.6)
- [ ] iOS / Android / Web render ตรงกัน

### 6. Acceptance Criteria
- `MapBackgroundWidget` วาดเส้นทางจิตอาสาด้วยสี `professionColor`
- Fallback default ทำงานได้โดยไม่ crash
- Dash pattern และ width คงเดิม
- ไม่กระทบ marker hue ที่ใช้ `professionColor` อยู่แล้ว

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
    - **Mission Lock (ล็อกการรับงานซ้อนระหว่างภารกิจ — ปรับปรุง 2026-09-04)**:
        - **หลักการ**: จิตอาสามีภารกิจ active ได้**เพียง 1 งาน** (`incident_responses` status `accepted`/`arrived`/`en_route`) — ดูเหตุการณ์อื่นได้ แต่**ห้ามรับงานซ้อน** ต้องจบภารกิจก่อน (`resolved`/`cancelled`)
        - **Mission Auto-Select**: เข้าหน้า EmergencyLivePage แบบไม่ระบุเหตุการณ์ (เช่น จากเมนู/แท็บ) → `_restoreActiveMissionIfNeeded()` ใช้ `getActiveRescues()` (Local-first) เปิดเหตุการณ์ของภารกิจให้อัตโนมัติ จิตอาสาไม่ต้องกดค้นหาเอง
        - **เข้าดูเหตุการณ์อื่นได้ (Trending Filter)**: กดเปิดเหตุการณ์ใหม่ (เช่น "วิเคราะห์เหตุนี้" จาก Home) → ดูได้ แต่กล่องยอดนิยมแสดงเฉพาะ **(1) การ์ดเหตุการณ์ที่ภารกิจตนเองค้าง (2) การ์ดที่กำลังดูอยู่ (3) การ์ดที่ได้รับการแจ้งเตือนหรือมีสิทธิเข้าร่วมเป็นจิตอาสา** — เกณฑ์ "มีสิทธิ" ใช้ Rule 3-5 เดียวกับ `_isEligibleResponder()`: ไม่ใช่เหตุการณ์ตัวเอง + อาชีพตรงกับ `volunteerProfessionIds` ของหมวดหมู่ + ยังไม่มีคนอาชีพเดียวกันรับ (`_computeMissionTrendingFilter()` → `_eligibleTrendingVideoIds`) — ไม่มีภารกิจค้าง → แสดงทุกการ์ดตามปกติ — **Fullscreen ต้องใช้ลิสต์ที่กรองแล้วเช่นกัน** (กันปัดเลี่ยงตัวกรอง)
        - **บล็อกที่ปุ่มรับงาน**: กด "รับภารกิจ" ที่เหตุการณ์ใหม่ขณะมีภารกิจค้าง → `_acceptRescue()` ตรวจ `getActiveRescues()` ก่อน dialog ยืนยัน → แสดง SnackBar "คุณมีภารกิจค้างอยู่ — ต้องกด "จบภารกิจ" ให้เสร็จก่อนจึงจะรับเหตุการณ์ใหม่ได้" แล้วเด้งกลับไปเหตุการณ์ภารกิจอัตโนมัติ
        - **ขณะอยู่ในภารกิจของตัวเอง** (`_currentResponseId != null`) ปิดความสามารถเปลี่ยนเหตุการณ์ทุกช่องทาง ป้องกันเผลอกดเปลี่ยน:
            - แตะการ์ดอื่นใน Trending Panel → ถูกบล็อก (แผงแสดงเฉพาะการ์ดภารกิจ)
            - ปัดขึ้น/ลงบน Video Player หน้าปกติ → ถูกบล็อก พร้อม SnackBar "อยู่ระหว่างภารกิจ — ไม่สามารถเปลี่ยนเหตุการณ์ได้"
            - ปัดขึ้น/ลงใน Fullscreen Video Viewer → ถูกบล็อก พร้อม SnackBar เดียวกัน
        - เมื่อจบภารกิจ (`_currentResponseId` กลับเป็น null หลังสถานะ `resolved`/`cancelled`) → คืนความสามารถเปลี่ยนเหตุการณ์และรับงานใหม่ตามปกติ
        - **เหตุผล**: หากผู้ช่วยเหลือเปลี่ยนเหตุการณ์กลางคัน จะสูญเสียการติดตามเส้นทาง GPS, สถานะ responder, แผนที่ และข้อมูลแชทของเหตุการณ์เดิมที่ยังค้างภารกิจ
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

### 3.1 Fullscreen Video Viewer และการเปลี่ยนเหตุการณ์ด้วยการปัด (แผนงาน — ยังไม่ Implement)

#### เป้าหมายและขอบเขต
- เมื่อยังไม่มีรูปภาพจาก Ruler Gallery ที่ถูกเลือกอยู่ และผู้ใช้แตะพื้นที่ Video Player ให้เปิด **Fullscreen Video Viewer** ผ่าน route แยกเต็มหน้าจอ ไม่ใช้ `Positioned.fill` ทับ `LiveViewWidget` เดิม
- Fullscreen ต้องเปิดได้เฉพาะเมื่อมี `_currentVideoId` และมี Video Player ที่พร้อมใช้งานเท่านั้น หากยังไม่มีการ์ดเหตุการณ์ที่เลือก ให้คงสถานะซ่อน Video Player และไม่เปิด fullscreen จากพื้นที่ว่าง
- การเปิด fullscreen ต้องไม่เปลี่ยนสถานะการเลือกของ Ruler Gallery และไม่ทำลาย/สร้างซ้ำ controller ของวิดีโอโดยไม่จำเป็น

#### Interaction ใน Fullscreen (Gesture Map)
| ท่าทาง (Gesture) | ผลลัพธ์ |
|---|---|
| **ปัดขึ้น** | ไปการ์ดเหตุการณ์ถัดไปในรายการ Trending ตามลำดับที่โหลดอยู่ |
| **ปัดลง** | ไปการ์ดเหตุการณ์ก่อนหน้าในรายการ Trending |
| **Single tap** | สลับ **เล่น/หยุดวิดีโอ** (play/pause) ของการ์ดปัจจุบัน |
| **Double tap** | กด **Like** แบบ toggle (unique/toggle logic เดิม) อัปเดตจำนวน Like แบบ real-time ไม่เปิด/ปิด fullscreen |
| **ปัดขวา (ลากตามนิ้ว)** | **Drag-to-dismiss** ปิด fullscreen — วิดีโอเลื่อนตามนิ้ว และปล่อยเพื่อปิด หากปล่อยก่อนถึงเกณฑ์ให้ spring กลับมา |
| **ปุ่มปิด (X)** | ปิด fullscreen ทันที (ทางเลือกเดียวกับปัดขวา) |

- **การเปลี่ยนการ์ด (ปัดขึ้น/ลง)**: ใช้ flow เดียวกับการเลือกการ์ดปกติ (เปลี่ยน `_currentVideoId`, โหลดข้อมูลเหตุการณ์, เปลี่ยน video source, อัปเดตแผนที่/แกลลอรี่/สถิติ) พร้อม loading/error state ระหว่างเปลี่ยน และมี transition animation แบบเลื่อนแนวตั้ง (vertical fling) ต่อการ์ด
- หากปัดถึงต้นหรือท้ายรายการ ให้โหลดหน้าถัดไปเมื่อมีข้อมูลเพิ่มเติม หรือแสดงสถานะว่าไม่มีการ์ดเพิ่มเติม โดยไม่วนกลับไปการ์ดเดิมโดยไม่แจ้งผู้ใช้
- **การนับการดูสะสม**: ทุกครั้งที่ปัดเปลี่ยนการ์ดใน fullscreen ให้ส่ง view event (`recordVideoView` + join/leave video room) **ทุกครั้งที่การ์ดเปลี่ยน** เหมือนแตะการ์ดในแผงยอดนิยม และให้ DB trigger / unique constraint เป็นตัวตัดยอดซ้ำของผู้ใช้คนเดียวกัน
- **การแสดงข้อมูลบนวิดีโอ (Fullscreen Overlay)**:
  - ปุ่มปิด (X) มุมซ้าย/ขวาบน มองเห็นตลอดหรือแสดงซ้อนเมื่อ single tap
  - **ชื่อเหตุการณ์/การ์ด** (title)
  - **จำนวนผู้ชมปัจจุบัน** (viewer count) แบบ real-time
  - **ยอดไลค์** (like count) อัปเดตแบบ real-time
- ต้องป้องกัน gesture conflict:
  - vertical swipe → เฉพาะเปลี่ยนการ์ด
  - double tap → เฉพาะ Like
  - single tap → เฉพาะ play/pause (ไม่ชน double tap ด้วย `GestureDetector` ดีเลย์แยก)
  - horizontal drag → เฉพาะ drag-to-dismiss
  - ขณะวิดีโอกำลังโหลด/error state ให้บล็อก gesture ที่ต้องใช้วิดีโอ และแสดง loading/error UI ตามปกติ

#### การคงการ์ดเมื่อปิด Fullscreen
- เมื่อปิด fullscreen ให้ส่ง `currentVideoId` ล่าสุดกลับมายัง `EmergencyLivePage` และคงการ์ดเหตุการณ์ล่าสุดเป็นการ์ดที่เลือกอยู่
- หลังกลับจาก fullscreen ต้องคง video source, แผนที่, จำนวนผู้ชม, Like state และข้อมูลเหตุการณ์ของการ์ดล่าสุด ไม่ย้อนกลับไปการ์ดเดิมที่เปิด fullscreen
- Ruler Gallery ต้อง sync ไปยังเหตุการณ์ล่าสุดเท่านั้นเมื่อกลับหน้าเดิม และห้ามเปิด Lightbox/Overlay ของรูปโดยอัตโนมัติ

#### การแยกความรับผิดชอบกับ Ruler Gallery
- Fullscreen ใช้ route/widget แยกจาก Ruler Gallery เพื่อไม่ให้ fullscreen รับ gesture ของ Ruler และไม่บังหรือ reset `FixedExtentScrollController`
- ขณะ fullscreen เปิด Ruler Gallery ด้านหลังไม่รับ gesture และไม่โหลด/เปลี่ยนรูปจากการแตะที่ตำแหน่งเดิม
- เมื่อ fullscreen ปิด ให้คืนการควบคุม gesture ให้ Ruler Gallery และรักษา index/การ์ดล่าสุดให้ตรงกับ `_currentVideoId`

#### Acceptance Criteria
1. แตะ Video Player ขณะไม่มีรูปใน Ruler ที่ถูกเลือก → เปิด fullscreen ได้เมื่อมีการ์ดเหตุการณ์ปัจจุบัน
2. ปัดขึ้น/ลง → เปลี่ยนการ์ดและวิดีโอได้โดยไม่ทำให้ Ruler Gallery เล่น/เลื่อนผิดพฤติกรรม
3. Single tap → สลับ play/pause ของการ์ดปัจจุบัน และไม่ชนกับการแตะสองครั้ง
4. Double-tap → Like แบบ toggle และจำนวน Like ตรงกับระบบปกติ
5. เปิดหรือเปลี่ยนการ์ดหลายครั้ง → ยอดดูสะสมเพิ่มตามการ์ดที่เปลี่ยนจริง และ DB ตัดยอดซ้ำของผู้ใช้คนเดียวกัน
6. ปัดขวาแบบ drag-to-dismiss: วิดีโอเลื่อนตามนิ้ว ปล่อยถึงเกณฑ์ → ปิด, ปล่อยไม่ถึงเกณฑ์ → spring กลับ
7. กดปุ่มปิด (X) → ปิด fullscreen ทันที
8. หลังปิด → ค้างที่การ์ดเหตุการณ์ล่าสุดที่ดูใน fullscreen
9. Fullscreen overlay แสดง ชื่อเหตุการณ์, จำนวนผู้ชม, ยอดไลค์ และปุ่มปิด
10. ยังไม่มีการ์ดเหตุการณ์ → ไม่มี video player และไม่เปิด fullscreen จากพื้นที่ว่าง

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

### Bug Fix #7 — Responder Marker/เส้นทางไม่แสดงฝั่งผู้แจ้งเหตุ (Local-first Data Flow)
**วันที่:** 2026-09-03
**ไฟล์ที่เกี่ยวข้อง:** `lib/features/video/data/repositories/video_repository.dart`, `websocket-server/routes/video.js`, `lib/features/video/presentation/pages/parts/emergency_navigation_logic.dart`, `lib/features/video/presentation/pages/parts/emergency_websocket_logic.dart`, `lib/features/video/presentation/pages/widgets/action_buttons_widget.dart`

**อาการ:** ฝั่งผู้แจ้งเหตุได้รับ SnackBar "กู้ภัยกำลังเดินทางมาหาคุณ..." แต่ไม่แสดง marker ผู้ช่วยเหลือ จำนวนผู้ช่วยเหลือ และเส้นทางบนแผนที่ + Error แดง `Invalid argument(s): 0` หลังรับภารกิจ

**สาเหตุ (Root Causes — 6 จุดซ้อนกัน):**
1. **Auth Header ขาดใน `/accept`**: `acceptIncident()` เรียก `POST /api/videos/:id/accept` โดยไม่ส่ง header `x-user-id` ขณะที่ route ใช้ `requireAuth` → Local API ตอบ 401 → fallback ไปบันทึก Supabase แทน ทำให้ **Local Postgres ไม่มีแถว responder**
2. **อ่านคนละฐานข้อมูลกับที่เขียน**: `acceptIncident`/`rescue-status-update` เขียนลง **Local Postgres เป็น source of truth** (dual-write ไป Supabase เป็น non-critical และอาจล้มเหลวเงียบๆ จาก FK violation เมื่อวิดีโอยังไม่ถูก sync) แต่ `getIncidentResponders()` อ่านจาก **Supabase โดยตรง** → ไม่เจอข้อมูลที่เพิ่งบันทึก
3. **PostgREST Relationship Cache**: query แบบ nested `users:volunteer_id(...)` ล้มทั้งชุดด้วย `PGRST200` แม้ FK จะมีอยู่จริงใน PostgreSQL (schema cache ไม่รู้จัก) — query ล้ม = รายการ responder ว่างทั้งหมด
4. **Status Filter ไม่ครบ**: server บันทึกสถานะเริ่มต้นเป็น `en_route` แต่ query กรองเฉพาะ `accepted, arrived` → responder ที่กำลังเดินทางไม่ถูกโหลด
5. **Location Key Mismatch**: listener `location-updated` ค้นหาด้วย `userId` และเขียน `latitude/longitude` แต่ map ใช้ `volunteerId` + `currentLat/currentLng` → ตำแหน่ง real-time ไม่เคยอัปเดตบนแผนที่
6. **Zero-area LatLngBounds**: เมื่อ responder กับจุดเกิดเหตุพิกัดใกล้/เท่ากัน `CameraUpdate.newLatLngBounds` throw `Invalid argument(s): 0` (และ `animateCamera` เป็น async ที่เดิมไม่ `await` จึงจับ error ไม่ได้) + `ActionButtonsWidget` เรียก `clamp(0, -1)` บน list คำร้องที่ว่างหลังผู้ใช้กลายเป็น Responder

**กฎที่ต้องปฏิบัติ:**
- **Local-first สำหรับข้อมูลภารกิจ**: ข้อมูล `incident_responses` ต้องอ่านจาก Local API (`GET /api/videos/:id/responders`) ก่อนเสมอ — Supabase เป็น fallback เท่านั้น เพราะ accept/status-update เขียนลง Local Postgres เท่านั้น
- **`x-user-id` ทุก request ที่ backend ใช้ `requireAuth`**: ลืม header นี้ = 401 เงียบๆ ที่ fallback ไป cloud แล้วข้อมูลแยกกันระหว่าง Local/Cloud (เคยเกิดกับ `toggleLike` และ `acceptIncident`)
- **ห้ามพึ่ง nested PostgREST relationship** (`users:volunteer_id(...)`) สำหรับตารางที่ FK อาจไม่อยู่ใน schema cache — ให้ query ตารางหลักก่อนแล้วดึงข้อมูลเสริมแยก โดยความล้มเหลวของข้อมูลเสริมต้องไม่ซ่อนข้อมูลหลัก (พิกัด/สถานะ)
- **Field naming ต้องตรงกันตลอดสาย**: DB (`volunteer_id`) → repository (`volunteerId`) → map widget (`currentLat/currentLng`) — การเปลี่ยนชื่อ key ต้องตรวจทั้งสายทั้ง producer และ consumer
- **Location listener ต้องกรองตาม incident**: `location-updated` เป็น broadcast รวมทุก user — ห้ามเพิ่ม user ภายนอกเข้า `_responders` ของเหตุการณ์ปัจจุบัน ให้ update เฉพาะ responder ที่โหลดไว้แล้ว
- **Async race guard**: ทุก async load ที่ผูกกับ `_currentVideoId` ต้อง capture videoId ก่อน await และตรวจว่ายังตรงกับเหตุการณ์ปัจจุบันก่อน `setState`
- **กัน ArgumentError จาก list ว่าง**: ห้าม `list[index.clamp(0, list.length - 1)]` เมื่อ list อาจว่าง (clamp กับ upperLimit -1 → `ArgumentError`) และ `GoogleMap.animateCamera` ต้อง `await` + ใช้ `newLatLngZoom` แทนเมื่อ bounds มีพื้นที่เป็นศูนย์

**ผลลัพธ์ที่ต้องยืนยันเสมอหลังแก้:**
- `GET /api/videos/:id/responders` คืนแถวของเหตุการณ์นั้นจาก Local DB
- หน้า reporter เห็น marker responder + เส้นประนำทาง + snackbar แจ้งสถานะ
- ไม่มี `PGRST200` ใน log ของ flow นี้

---

### Bug Fix #8 — กดรับภารกิจไปแล้ว กลับเข้าหน้าเดิมต้องกดรับใหม่ (Mission State Restore)
**วันที่:** 2026-09-04
**ไฟล์ที่เกี่ยวข้อง:** `websocket-server/routes/video.js`, `lib/features/video/data/repositories/video_repository.dart`, `lib/features/video/presentation/pages/parts/emergency_navigation_logic.dart`

**อาการ:** จิตอาสากด "รับช่วยเหลือ" สำเร็จ (แถวถูกบันทึกลง `incident_responses` ใน Local Postgres จริง, status `accepted`) แต่เมื่อออกจากหน้าแล้วกลับเข้ามาเหตุการณ์เดิม ระบบแสดงการ์ด "รับภารกิจช่วยเหลือ" ใหม่ราวกับยังไม่เคยรับ

**สาเหตุ (Root Causes — 3 จุด):**
1. **Home Page dedup อ่าน Supabase ที่ว่างเปล่า**: `getTakenIncidentVideoIdsByProfession()` อ่าน `incident_responses` จาก Supabase เท่านั้น — แต่ตารางนี้ใน Supabase **ว่างทั้งตาราง** (dual-write จาก Local ล้มเหลวเงียบๆ เพราะ video ไม่ exist ใน cloud / FK violation) และยังใช้ nested relationship `users:volunteer_id(user_group_roles(profession_id))` ที่ล้มด้วย `PGRST200` → `catch` คืน `Set()` เปล่าเงียบๆ → Profession De-duplication ใช้งานไม่ได้เลย → การ์ดแดงโผล่ซ้ำให้คนที่รับไปแล้ว
2. **`getActiveRescues()` (RescuePage) อ่าน Supabase เท่านั้น** → ได้ `[]` → restore ภารกิจที่ค้างอยู่ไม่ได้ และ status filter ขาด `en_route` (สถานะเริ่มต้นหลังกดรับ)
3. **Restore ใน Live Page ไม่เริ่ม tracking ซ้ำ**: `_loadResponders()` restore `_currentResponseId` ได้ แต่ `initState` เรียก `_startResponderTracking()`/`_initCompass()` ก่อน restore เสร็จ แล้วทั้งคู่ early-return เพราะ `_currentResponseId == null` ในตอนนั้น → หลัง restore สำเร็จ GPS tracking และเข็มเข็มทิศไม่เคยเริ่มทำงาน

**กฎที่ต้องปฏิบัติ:**
- **Local-first ครบทุก read ของ `incident_responses`** (ต่อยอด Bug Fix #7): ทั้ง `getIncidentResponders`, `getTakenIncidentVideoIdsByProfession` และ `getActiveRescues` ต้องเรียก Local API ก่อน — Supabase เป็น fallback เท่านั้น
- **Endpoints ที่ต้องมีใน Local API**:
  - `GET /api/videos/taken-by-profession/:professionId` → video_ids ที่ถูกรับแล้วตามอาชีพ (status `accepted/arrived/en_route`)
  - `GET /api/videos/volunteer/:volunteerId/active-rescues` → ภารกิจ active ของ volunteer พร้อม `videos` object ฝังอยู่ (รูปแบบเดียวกับ `*, videos(*)` ของ PostgREST)
- **ห้ามใช้ nested PostgREST relationship** — ให้ query ตารางหลัก (`incident_responses`) แล้ว join `user_group_roles` ฝั่ง server หรือ query แยกแบบ flat
- **Silent catch = ฟีเจอร์เงียบหาย**: `catch (e) { return {}; }` ทำให้ dedup พังโดยไม่มีใครรู้ — ต้อง `debugPrint` ทุกจุดที่ fallback
- **Restore ต้องกู้ side-effect คืนด้วย**: หลัง restore `_currentResponseId` สำเร็จ ต้องเรียก `_startResponderTracking()` + `_initCompass()` + `_checkPrivacyPermissions()` ซ้ำ เพราะ initState เรียกไปแล้วตอนที่ state ยังเป็น null
- **Status filter ต้องครบ 3 สถานะเสมอ**: `accepted`, `arrived`, `en_route`

**ผลลัพธ์ที่ต้องยืนยันเสมอหลังแก้:**
- `GET /api/videos/taken-by-profession/:professionId` คืน video_id ของเหตุการณ์ที่รับไปแล้วจาก Local DB → การ์ดแดงบน Home ไม่โผล่ซ้ำสำหรับภารกิจที่รับอยู่
- `GET /api/videos/volunteer/:volunteerId/active-rescues` คืนภารกิจ active พร้อม `videos.id/type/user_id`
- กลับเข้าเหตุการณ์เดิมตอนภารกิจยังไม่จบ → เห็น Rescue Control Panel ("กำลังปฏิบัติภารกิจ") ไม่ใช่ปุ่มรับภารกิจใหม่ และ GPS tracking ทำงานต่อทันที

**เพิ่มเติม (2026-09-04) — Mission Auto-Select:**
- จิตอาสาที่มีภารกิจค้างเข้าหน้า Live **แบบไม่ระบุเหตุการณ์** (เมนู/แท็บ) → `_loadInitialData()` เรียก `_restoreActiveMissionIfNeeded()` ใช้ `getActiveRescues()` (Local-first) หาภารกิจ active แล้ว `_switchVideo()` ไปยังเหตุการณ์นั้นทันที — จิตอาสาไม่ต้องกดค้นหาเหตุการณ์เอง (ถ้าระบุเหตุการณ์มาเอง → ดูได้ตาม Mission Lock Hint ด้านล่าง)
- ถ้า `_switchVideo` ถูกเรียกจาก auto-select ผู้เรียกต้อง `return` ทันที (ป้องกัน double-load) เพราะ `_switchVideo` เรียก `_loadInitialData()` ใหม่ให้เอง
- Safety net: ถ้าการ์ดภารกิจไม่อยู่ในหน้าแรกของ trending (เกิน 20 อันดับ) ให้ฝัง `_currentVideo` เข้าไปในลิสต์ที่ส่งให้ `TrendingPanelWidget` ขณะล็อก เพื่อไม่ให้แผงแสดงข้อความว่างแทนการ์ดภารกิจ
- **Mission Lock Hint (ปรับปรุง 2026-09-04)**: นโยบายที่ตกลงกัน — **คง Mission Lock ตามแผน ไม่เปิดรับงานซ้อน** แต่แบ่งพฤติกรรมเป็น 2 ชั้น:
  - **เข้าดูได้ (กรองกล่องยอดนิยม)**: จิตอาสาที่มีภารกิจค้างกดเปิดเหตุการณ์ใหม่ (เช่น "วิเคราะห์เหตุนี้" จาก Home) → ดูได้ แต่กล่องยอดนิยมแสดงเฉพาะ **(1) การ์ดเหตุการณ์ที่ภารกิจตนเองค้าง (2) การ์ดที่กำลังดูอยู่ (3) การ์ดที่ได้รับการแจ้งเตือนหรือมีสิทธิเข้าร่วมเป็นจิตอาสา** — เกณฑ์ "มีสิทธิ" ใช้ Rule 3-5 เดียวกับ `_isEligibleResponder()`: ไม่ใช่เหตุการณ์ตัวเอง + อาชีพตรงกับ `volunteerProfessionIds` ของหมวดหมู่ + ยังไม่มีคนอาชีพเดียวกันรับ (คำนวณใน `_computeMissionTrendingFilter()` แล้วเก็บใน `_eligibleTrendingVideoIds`) — ไม่มีภารกิจค้าง → แสดงทุกการ์ดตามปกติ และ fullscreen ต้องใช้ลิสต์ที่กรองแล้วเช่นกัน (กันปัดเลี่ยงตัวกรอง)
  - **บล็อกที่ปุ่มรับงาน**: เมื่อกด "รับภารกิจ" ที่เหตุการณ์ใหม่ → `_acceptRescue()` ตรวจ `getActiveRescues()` (Local-first) ก่อน dialog ยืนยัน → ถ้ามีภารกิจค้างที่เหตุการณ์อื่น แสดง SnackBar "คุณมีภารกิจค้างอยู่ — ต้องกด จบภารกิจ ให้เสร็จก่อนจึงจะรับเหตุการณ์ใหม่ได้" แล้ว `_switchVideo()` เด้งกลับไปเหตุการณ์ภารกิจอัตโนมัติ
  - auto-select คงไว้เฉพาะกรณีเข้าหน้า Live แบบไม่ระบุเหตุการณ์ (restore convenience)

---

### Bug Fix #9 — ป้องกันการกด 'จบภารกิจ' แล้ว Socket หลุด (HTTP Status Endpoint + Idempotent Update + 24h Stale Filter)
**วันที่:** 2026-09-04
**ไฟล์ที่เกี่ยวข้อง:** `websocket-server/routes/video.js`, `websocket-server/server.js`, `lib/features/video/data/repositories/video_repository.dart`, `lib/features/video/presentation/pages/parts/emergency_navigation_logic.dart`, `lib/features/video/presentation/pages/rescue_page.dart`

**ปัญหาเดิม:**
1. การกด "จบภารกิจ" หรือเปลี่ยนสถานะ (`arrived`, `resolved`, `cancelled`) พึ่งพาเฉพาะ `socket.emit('rescue-status-update')` แบบ fire-and-forget โดยไม่มี HTTP fallback และไม่มี acknowledgement — หาก WebSocket หลุด หรือสัญญาณเครือข่ายกระตุกชั่วขณะ สถานะจะไม่ถูกบันทึกลง Local PostgreSQL แต่หน้าจอจะ pop ออกทันที ทำให้ภารกิจค้างอยู่ในสถานะ `accepted` ตลอดไป
2. ภารกิจเก่าที่ค้างจากอดีต (เช่น หลายเดือนก่อน) ยังมีสถานะ `accepted` ทำให้ `getActiveRescues()` ดึงขึ้นมาทริกเกอร์ Mission Lock และ Auto-select อยู่ตลอดเวลา

**วิธีแก้ไขและป้องกัน (Implemented):**
1. **Primary HTTP Status Endpoint**: เพิ่ม `POST /api/videos/:id/status` (ใช้ `requireAuth`, `strictRateLimiter`, รับ `x-user-id`)
   - อัปเดตตาราง `incident_responses` โดยตรงใน Local PostgreSQL (source of truth)
   - อัปเดตแบบ Idempotent (`CASE WHEN status = ... AND arrived_at/resolved_at IS NULL THEN CURRENT_TIMESTAMP ELSE ... END`)
   - ทำ Real-time Notification ส่งให้ผู้ประสบเหตุ (`rescue-incoming`) และส่งเข้าห้องวิดีโอ (`rescue-status-updated`) ผ่าน Socket Service ในคำขอเดียว
   - ล้างและ Archive ข้อความแชทอัตโนมัติเมื่อสถานะเป็น `resolved` หรือ `cancelled`
2. **Repository & UI Await Guard**:
   - `VideoRepository.updateRescueStatus()` เรียก Local HTTP endpoint ก่อน แล้ว Dual-Write/Fallback ไป Supabase
   - `_updateRescueStatus()` ใน Flutter ทำการ `await` คำสั่งของ repository ก่อนแสดงผล:
     - หากสำเร็จ: ปลดล็อกภารกิจ (`_currentResponseId = null`, `_pendingMissionVideoId = null`), ยกเลิกเข็มทิศ, แสดง SnackBar สำเร็จสีเขียว และรอ 600ms ค่อย `Navigator.pop()`
     - หากล้มเหลว: แสดง SnackBar สีแดงแจ้งเตือน "ไม่สามารถบันทึกสถานะได้ กรุณาลองใหม่อีกครั้ง" และ**ห้าม pop ออก** เพื่อให้ผู้ใช้กดซ้ำได้
3. **Socket Acknowledgement**: ปรับ `socket.on('rescue-status-update')` ใน `server.js` ให้รองรับ callback acknowledgement
4. **24-Hour Active Mission Threshold**: ใน `GET /volunteer/:volunteerId/active-rescues` เพิ่มเงื่อนไข `AND ir.accepted_at > CURRENT_TIMESTAMP - INTERVAL '24 hours'` เพื่อตัดภารกิจค้างเก่าเก็บในอดีต (Zombie Missions) ไม่ให้เข้ามารบกวนการใช้งานปัจจุบัน

---

### Bug Fix #10 — กล่องยอดนิยมไม่กรองตามสิทธิจิตอาสา + เห็นเหตุการณ์ที่จบภารกิจแล้ว (Eligibility-based Filter)
**วันที่:** 2026-09-04
**ไฟล์ที่เกี่ยวข้อง:** `websocket-server/routes/video.js`, `lib/features/video/presentation/pages/parts/emergency_navigation_logic.dart`, `lib/features/video/presentation/pages/emergency_live_page.dart`

**อาการ:** จิตอาสากดเข้าจากการ์ดแจ้งเตือนหน้า Home แล้วกล่องยอดนิยมแสดงวิดีโอทุกใบ รวมถึง (1) เหตุการณ์ที่จิตอาสาผู้นี้ไม่มีสิทธิ (2) เหตุการณ์ที่จบภารกิจไปแล้ว

**สาเหตุ (Root Causes — 4 จุด):**
1. **Filter ถูก gate ที่ "มีภารกิจค้าง"**: `_computeMissionTrendingFilter()` และ `_filteredTrendingVideos()` เดิม early-return เมื่อ `_pendingMissionVideoId == null` — จิตอาสาที่เพิ่งจบภารกิจ (หรือไม่เคยมี) จึงเห็นทุกการ์ด ตรงที่สุดกับกรณีทดสอบ: จบภารกิจ 11:12 แล้วเข้าจากการ์ดแจ้งเตือน 11:36 → filter ถูกข้ามทั้งหมด
2. **resolved ไม่ถูกนับเป็น "หมดสิทธิ"**: `taken-by-profession` กรองเฉพาะ `accepted/arrived/en_route` — เหตุการณ์ที่จบภารกิจแล้วยังผ่านเกณฑ์ → แสดงในกล่องยอดนิยม + **บั๊กแฝง**: หน้า Home จะแจ้งเตือนซ้ำเหตุการณ์ที่จบภารกิจไปแล้ว
3. **Rule 5 มองไม่เห็น resolved**: `GET /:id/responders` คืนเฉพาะ active responders → ปุ่ม "ฉันพร้อมช่วยเหลือ" ยังแสดงบนเหตุการณ์ที่จบแล้ว และกดรับซ้ำจะฟื้นภารกิจ (upsert รีเซ็ตเป็น `en_route`)
4. **วิดีโอไม่มี category = ไม่มีสิทธิให้ใครรับ** (Rule 4 ล้ม) แต่ยังแสดงในกล่องยอดนิยมของจิตอาสา

**นโยบายที่ตกลงกัน (2026-09-04):**
- **Filter ใช้กับจิตอาสาเท่านั้น** — จิตอาสา = ผู้ใช้ที่อาชีพตรงกับ `volunteerProfessionIds` ของ category ใดๆ (`_isVolunteerCapable`) ผู้ชมทั่วไป/reporter ที่ไม่มีอาชีพตรงเห็นทุกการ์ดตามปกติ (คง feed สาธารณะ)
- **Resolved บล็อกต่ออาชีพ** — เหตุการณ์หายจากชุดมีสิทธิเมื่อจิตอาสา**อาชีพเดียวกัน**จบภารกิจไปแล้ว อาชีพอื่นที่ยังไม่มีใครรับยังเห็นได้ (สอดคล้องโครงสร้างหลายอาชีพต่อเหตุการณ์)

**วิธีแก้ไข (Implemented):**
1. **Eligibility-based Filter (always-on สำหรับจิตอาสา)**: `_computeMissionTrendingFilter()` คำนวณเสมอเมื่อผู้ใช้เป็นจิตอาสา (ไม่ gate ที่ภารกิจค้าง) — เกณฑ์: ไม่ใช่เหตุการณ์ตัวเอง (Rule 3) + มี category และอาชีพตรง (Rule 4) + ไม่มีคนอาชีพเดียวกันรับอยู่หรือจบไปแล้ว (Rule 5 + resolved) — `_filteredTrendingVideos()` gate ที่ `_isVolunteerCapable` แทน `_pendingMissionVideoId`
2. **ขยาย `taken-by-profession` รวม `resolved`**: `status IN ('accepted','arrived','en_route','resolved')` — แก้พร้อมกันทั้งกล่องยอดนิยม (live page) และการแจ้งเตือนซ้ำบน Home (ใช้ endpoint เดียวกันผ่าน `getTakenIncidentVideoIdsByProfession`)
3. **Accept Guard (defense in depth)**: `POST /:id/accept` ตรวจว่ามี resolved response โดยจิตอาสาอาชีพเดียวกันหรือไม่ → ตอบ `409 { code: 'MISSION_ALREADY_RESOLVED' }` — กันการฟื้นภารกิจที่จบแล้วแม้ UI พลาดทุกเส้นทาง

**ผลลัพธ์ที่ต้องยืนยันเสมอหลังแก้:**
- จิตอาสาเข้าจากการ์ดแจ้งเตือน → กล่องยอดนิยมเหลือเฉพาะ: การ์ดที่ดูอยู่ + ภารกิจค้าง + เหตุการณ์ที่มีสิทธิ (ตรงอาชีพ ไม่มีใครรับ/จบ)
- เหตุการณ์ที่จบภารกิจแล้ว (resolved โดยอาชีพเดียวกัน) ไม่แสดงในกล่องยอดนิยมของจิตอาสาอาชีพนั้น และไม่แจ้งเตือนซ้ำบน Home
- กดรับเหตุการณ์ที่จบแล้วโดยตรง (API) → `409 MISSION_ALREADY_RESOLVED`
- ผู้ชมทั่วไป (ไม่มีอาชีพตรง) → กล่องยอดนิยมแสดงครบตามปกติ

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

### WebSocket Events — การปิดรับบริจาค (Implemented มิ.ย. 2569)

| Event | ทิศทาง | Payload | ผลลัพธ์ใน Flutter |
|:------|:-------|:--------|:----------------|
| `donation-closed` | Flutter → Server → Room | `{ videoId, requestId, title, currentAmount, reason }` | ผู้ร้องขอปิดรับ → Server Broadcast ไปยัง `room-video-{videoId}` |
| `donation-progress-updated` | Server → Room | `{ videoId, requestId, donationTitle, currentAmount, targetAmount }` | มีการบริจาค gift → อัปเดตยอด current_amount แบบ Real-time |
| `donation-request-status-updated` | Server → User Room | `{ userId, requestId, title, status }` | สถานะคำร้องเปลี่ยน (เช่น อนุมัติแล้ว) → แจ้งเจ้าของคำร้อง |

**ความสำคัญของ `activeOnly: true`:**
- `DonationRepository.getRequestsByVideoId(videoId, activeOnly: true)` จะกรองเฉพาะ `approval_status = 'active'`
- คำร้องที่ถูกปิด (`completed`) จะไม่ปรากฏในหน้าไลฟ์โดยอัตโนมัติ ป้องกันการบริจาคเข้าเคสที่ปิดแล้ว
- ผู้ดูไลฟ์ที่เปิดอยู่จะได้รับ Event `donation-closed` เพื่อให้ UI อัปเดตยอดรวมและซ่อนปุ่มบริจาคของเคสนั้นทันที
- `deleteRequest()` ไม่ใช่ action สำหรับผู้ใช้ฝั่ง live/donation sheet; หากต้องมีการลบถาวรให้เป็น flow ของ admin/maintenance เท่านั้น และไม่ควรถูกเรียกจาก UI ผู้ใช้ที่ผูกกับวิดีโอ

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

---

### 🔄 Phase 6.12: Async Thai Mhung Face Blur + Gallery Blocking (✅ เสร็จสมบูรณ์)

> **สถานะ**: ✅ เสร็จสมบูรณ์บนเครื่องหลัก
> *Last Updated: 2026-06-20*

#### 1. ปัญหาปัจจุบัน (แก้ไขแล้ว)
- ✅ ผู้ส่งภาพไทยมุงต้องรอ dialog loading จนกว่า Python `deface` จะเบลอใบหน้าเสร็จ (Sync Processing) → **แก้ไข: Backend ตอบกลับทันที**
- ✅ หากรอนาน ผู้ใช้อาจเข้าใจผิดว่าภาพยังไม่ถูกส่ง → กดส่งซ้ำ → **แก้ไข: เปลี่ยน loading text และ success message**
- ✅ ภาพใหม่ไม่ปรากฏใน Gallery จนกว่า backend จะประมวลผลเสร็จทั้งหมด → **แก้ไข: Immediate placeholder insertion + cache invalidation**

#### 1.1 สาเหตุหลักที่พบระหว่างการทำ (Root Cause Analysis)

**ปัญหา:** Gallery ส่งคืน 0 รูปแม้ว่า insert สำเร็จ

**สาเหตุ:**
- Insert `thai_mhung_photos` ใช้ `videoId` (UUID ของ video record ใหม่)
- Gallery query ใช้ `incidentId` (UUID ของ incident หลัก)
- ทั้งสองค่าไม่ตรงกัน → WHERE clause ไม่เจอข้อมูล → ส่งคืน 0 รูป

**วิธีแก้ไข:**
- เปลี่ยน insert ให้ใช้ `incidentId` แทน `videoId` ใน `websocket-server/routes/video.js:359`
- เพิ่ม logs เพื่อตรวจสอบค่าที่ใช้ insert และ query

#### 2. เป้าหมาย
- Backend ตอบกลับทันทีหลังอัปโหลด (ไม่รอ blur)
- Gallery แสดงภาพพร้อม badge "กำลังปกป้องสิทธิ์ส่วนบุคคล..."
- บล็อกการเปิดภาพเต็ม (lightbox) ขณะกำลังเบลอ → แสดง SnackBar แจ้งเตือน
- ป้องกัน PDPA: ไม่มีใบหน้าที่ไม่เบลอปรากฏบน UI เด็ดขาด

#### 3. สถาปัตย์ (Architecture)

```
ผู้ใช้กดส่ง → อัปโหลดรูปต้นฉบับ
         ↓
Backend: รับรูป → บันทึก DB (photo_url = null หรือ status = 'blurring')
         ↓
Backend: ตอบกลับทันที "ได้รับแล้ว" → Flutter ปิด dialog
         ↓
Gallery: แสดง placeholder + badge "กำลังเบลอ..."
         ↓
Backend: ส่งให้ Python deface (background/async) → เสร็จแล้วอัปเดต DB
         ↓
Backend: broadcast 'photo-blur-complete' (WebSocket/Realtime)
         ↓
Gallery: รับ event → แสดงรูปจริง + badge "ปกป้องสิทธิ์แล้ว"
```

#### 4. ขั้นตอน Backend (ทำบนเครื่องหลัก)

**4.1 แก้ไข `websocket-server/routes/video.js`**

```javascript
// ใน endpoint upload-photos (ประมาณบรรทัด 210)
// เปลี่ยนจาก:
const blurResult = await faceBlurService.blurFacesInImage(newPath, anonPath);

// เป็น:
// 1. ตอบกลับ client ทันที
res.json({ success: true, photoId, status: 'blurring' });

// 2. สั่ง blur แบบ background
faceBlurService.blurFacesInImage(newPath, anonPath)
  .then(result => {
    if (result.success) {
      // อัปเดต DB: photo_url = anonPath, blur_status = 'completed'
      pool.query('UPDATE thai_mhung_photos SET photo_url = $1, blur_status = $2 WHERE id = $3', [anonPath, 'completed', photoId]);
      // Broadcast
      socketService.emit('photo-blur-complete', { photoId, url: anonPath });
    }
  })
  .catch(err => {
    console.error('[Blur] Background error:', err);
  });
```

**4.2 เพิ่ม column ใน DB**

```sql
ALTER TABLE thai_mhung_photos ADD COLUMN blur_status VARCHAR(20) DEFAULT 'blurring';
-- ค่าที่เป็นไปได้: 'blurring' | 'completed' | 'failed'
```

**4.3 แก้ไข `websocket-server/services/face-blur-service.js`**

- ตรวจสอบว่า function `blurFacesInImage` รองรับการเรียกแบบ fire-and-forget ได้
- เพิ่ม error logging เมื่อ blur ล้มเหลว

**4.4 Restart Backend**

```bash
cd websocket-server
npm run dev
```

#### 5. ขั้นตอน Flutter Gallery (ทำบนเครื่องหลัก)

**5.1 เพิ่ม field ใน `ThaiMhungPhoto` model**

```dart
// lib/features/video/presentation/pages/widgets/thai_mhung_gallery_widget.dart
class ThaiMhungPhoto {
  final String id;
  final String? photoUrl;
  final DateTime createdAt;
  final String? userId;
  final String blurStatus; // 'blurring' | 'completed' | 'failed'
  
  ThaiMhungPhoto({
    required this.id,
    this.photoUrl,
    required this.createdAt,
    this.userId,
    this.blurStatus = 'completed',
  });
}
```

**5.2 แก้ `thai_mhung_gallery_widget.dart`**

```dart
// ใน itemBuilder
GestureDetector(
  onTap: () {
    if (photo.blurStatus == 'blurring') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ภาพกำลังถูกปกป้องสิทธิ์ส่วนบุคคล กรุณารอสักครู่'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _openLightbox(photo);
  },
  child: Stack(
    children: [
      photo.blurStatus == 'blurring'
        ? Container(
            color: Colors.grey[300],
            child: const Center(child: Icon(Icons.face_retouching_off, color: Colors.grey)),
          )
        : CachedNetworkImage(imageUrl: photo.photoUrl!),
      if (photo.blurStatus == 'blurring')
        Positioned(
          top: 4, left: 4,
          child: Chip(
            label: const Text('กำลังปกป้อง...', style: TextStyle(fontSize: 10)),
            backgroundColor: Colors.orange.withOpacity(0.9),
          ),
        ),
    ],
  ),
)
```

**5.3 แก้ `thai_mhung_ruler_gallery_widget.dart`** (หากใช้)

ทำเช่นเดียวกับข้อ 5.2 — บล็อก tap + แสดง badge

**5.4 รับ WebSocket Event**

```dart
// ใน initState หรือตรงจุด subscribe WebSocket
WebSocketService().on('photo-blur-complete', (data) {
  setState(() {
    final photo = _thaiMhungPhotos.firstWhere((p) => p.id == data['photoId']);
    photo.blurStatus = 'completed';
    photo.photoUrl = data['url'];
  });
});
```

#### 6. ขั้นตอน Flutter Sender (✅ เสร็จแล้วบนเครื่องลอง)

ส่วนนี้ทำแล้ว — ไม่ต้องแก้เพิ่ม:
- `_isSendingThaiMhungPhotos` state + guard clause + SnackBlock
- Dialog text: *"กำลังอัปโหลดและปกป้องสิทธิ์ส่วนบุคคล... (เบลอใบหน้า อาจใช้เวลาสักครู่)"*
- ปิดปุ่มถ่าย/ส่งขณะกำลังส่ง

#### 7. การทดสอบบนเครื่องหลัก

1. **Backend**: อัปโหลดรูปไทยมุง → ตรวจสอบ log ว่าตอบกลับทันที + Python ทำงาน background
2. **DB**: `SELECT blur_status FROM thai_mhung_photos ORDER BY created_at DESC LIMIT 1;`
3. **Flutter**: รูปขึ้นใน gallery พร้อม badge สีส้ม → รอ ~5-15 วินาที → badge เปลี่ยนเป็นรูปจริง
4. **PDPA Test**: กดที่รูปที่ยังมี badge "กำลังปกป้อง..." → ต้องเห็น SnackBar สีส้ม ไม่เปิด lightbox

#### 8. ความปลอดภัยทางกฎหมาย (PDPA)

| สถานะ | ที่เก็บ | แสดงบน UI | กดดูได้ |
|-------|--------|-----------|---------|
| ต้นฉบับ (original) | Server disk | ❌ ไม่แสดง | ❌ |
| กำลังเบลอ (blurring) | Server disk | ✅ placeholder | ❌ บล็อก |
| เบลอแล้ว (completed) | Server disk / DB | ✅ แสดงรูป | ✅ |

> **หลักการ**: รูปต้นฉบับที่มีใบหน้าชัดเจนต้องอยู่บน Server เท่านั้น ไม่มีวิธีใดที่ Client จะเข้าถึงได้โดยตรง

---

## 🔄 Local-to-Cloud Sync: บทเรียนและการแก้ไข (Added 2026-07-29)

> เกิดจากปัญหาจริง: Sync service ล้มเหลวทุกครั้งตอน server startup เนื่องจาก schema mismatch และ RLS policy

### สาเหตุและวิธีแก้ไข

| ปัญหา | สาเหตุ | วิธีแก้ | ไฟล์ |
|-------|--------|--------|------|
| `Video Cloud Sync failed: Could not find the 'incident_id' column` | Local DB มี `incident_id` แต่ Cloud ไม่มี — sync ส่ง column นี้ไป upsert โดยไม่ strip | เพิ่ม `'incident_id'` ใน `VIDEO_LOCAL_ONLY_COLUMNS` | `services/sync-service.js` |
| `Video Cloud Sync failed: Could not find the 'peak_viewers' column` | เหตุผลเดียวกัน — local-only column ไม่ได้ strip | เพิ่ม `'peak_viewers'` ใน `VIDEO_LOCAL_ONLY_COLUMNS` | ข้างต้น |
| `Video Cloud Sync failed: Could not find the 'peak_viewers_at' column` | เหตุผลเดียวกัน | เพิ่ม `'peak_viewers_at'` ใน `VIDEO_LOCAL_ONLY_COLUMNS` | ข้างต้น |
| `Video Cloud Sync failed: Could not find the 'photo_urls' column` | เหตุผลเดียวกัน | เพิ่ม `'photo_urls'` ใน `VIDEO_LOCAL_ONLY_COLUMNS` | ข้างต้น |
| `Interaction Cloud Sync failed: new row violates row-level security policy` | Sync ใช้ anon key ซึ่งถูก RLS บล็อก | สร้าง service-role Supabase client (`supabaseForSync`) แยกจาก anon client แล้วส่งเข้า `syncQueueService.init()` | `server.js` |
| `Interaction Cloud Sync failed: duplicate key value violates unique constraint` | `upsert` ใช้ `onConflict: 'id'` แต่ Cloud มี partial unique index `(video_id, user_id, type) WHERE type='like'` ไม่รองรับ onConflict | เปลี่ยนจาก `upsert` เป็น `insert` ธรรมดา (pre-filter กรองซ้ำแล้ว) + catch duplicate key error แบบ graceful | `services/sync-service.js` |

### รายการ Local-Only Columns ที่ต้อง strip ก่อน sync ไป Cloud

```js
const VIDEO_LOCAL_ONLY_COLUMNS = new Set([
    'is_synced',
    'address', 'alley', 'road', 'soi', 'village',
    'cached_like_count', 'cached_view_count',
    'category_id',
    'incident_id',
    'peak_viewers',
    'peak_viewers_at',
    'photo_urls',
]);
```

> **⚠️ ป้องกันการเกิดซ้ำ:** ทุกครั้งที่เพิ่ม column ใหม่ใน local `videos` table ต้องตรวจสอบว่า Cloud schema มี column นั้นหรือไม่ ถ้าไม่มี ต้องเพิ่มใน `VIDEO_LOCAL_ONLY_COLUMNS` ทันที มิฉะนั้น sync จะล้มเหลว

### จุดเสี่ยงด้านความปลอดภัย (อ้างอิง docs/secure/)

- **การใช้ service_role key สำหรับ sync** ทำให้ bypass RLS ทั้งหมด — ขัดกับหลัก Least Privilege (แผน 12) และเพิ่มความเสี่ยงถ้า sync logic มีบั๊ก (แผน 01 section 9.3)
- **ระยะสั้น:** ใช้ได้เพราะ sync เป็น server-side job ที่ไม่รับ input จากผู้ใช้
- **ระยะยาว:** ควรสร้าง DB role เฉพาะสำหรับ sync ที่มีสิทธิ์ insert/update บน `videos` และ `video_interactions` เท่านั้น แทนการใช้ service_role key เต็มสิทธิ์

---

## 12. ระบบคัดแยกระดับภาวะคุกคามต่อชีวิต (Triage System) — 📋 แผน (ยังไม่ implement)

> **สถานะ**: 📋 ออกแบบเสร็จ รอเริ่ม implement
> *Created: 2026-08-09*
> **ที่มา**: ทีมอาสาที่เข้าร่วมช่วยเหลือต้องประเมินผู้ป่วยเพื่อจัดกลุ่มตามความวิกฤต ตามหลัก START Triage สากล

### 12.0 สรุปข้อกำหนดที่ยืนยันแล้ว (Confirmed Requirements)

| # | หัวข้อ | ข้อสรุป |
|:--|:---|:---|
| 1 | Entry Point | **แทนที่** `RelationshipViewWidget` เดิมด้วย Triage Bottom Sheet ครึ่งจอ (กดจากปุ่ม "เกี่ยวดอง") — **ผู้ใช้ทุกคนเห็นปุ่มและเปิด Sheet ได้** ส่วนสิทธิ์การกระทำภายใน (ระบุสี/ลบ/dispute) ควบคุมโดย Backend ตาม Permission Matrix (12.4) |
| 2 | Cardinality | 1 incident : N victims — **ทุกคนแจ้งชื่อได้** |
| 3 | สิทธิลบ/ปฏิเสธความถูกต้อง | **เฉพาะทีมจิตอาสาที่เข้าช่วยเหลือ** เท่านั้น |
| 4 | ชื่อย่อ | `prefix + พยัญชนะตัวแรก` (ไทย: `นาย ก` / อังกฤษ: `Mr. J`) — mask ที่ **Backend** |
| 5 | ที่เก็บ | Local PostgreSQL + **Sync ขึ้น Supabase Cloud** |
| 6 | ผู้เห็นชื่อเต็ม | ทีมอาสา (`status IN ('accepted','en_route','arrived')`) + Admin/Super Admin + **ผู้กรอกเฉพาะ record ที่ตนเองกรอก** ✅ยืนยัน |
| 7 | ผู้ให้สี | **เฉพาะจิตอาสาที่เข้าช่วยเหลือ** (ยกเว้นสีดำ — ดูข้อ 13) |
| 8 | Conflict Resolution | **Last-write-wins** + เก็บ history ทุกครั้ง |
| 9 | Map Badge | แสดง `⚫1 🔴2 🟡1 🟢3` เหนือหมุดเหตุการณ์ |
| 10 | Real-time | WebSocket `victim-triage-updated` → room `video-{incidentId}` |
| 11 | Health Data Link | เชื่อมได้เมื่อ **(ก)** ผู้ประสบเหตุตั้งค่าอนุญาตล่วงหน้า **และ (ข)** ถูกระบุสีโดยจิตอาสาแล้ว |
| 12 | Edit Lock | ผู้กรอก**แก้ไขไม่ได้**หลังถูกระบุสีแล้ว — จิตอาสาแก้ได้เสมอ |
| 13 | **สีดำ (Deceased)** | **มี 4 ระดับ** — ผู้ระบุสีดำต้องเป็น **จิตอาสาในเหตุการณ์ AND อาชีพอยู่ในหมวด `provider`** (ผู้ให้บริการสุขภาพ) |
| 14 | Reporter ผู้ถ่ายวิดีโอ | **ไม่เห็นชื่อเต็ม** (นอกจากเป็นจิตอาสาในเหตุการณ์นั้นด้วย) ✅ยืนยัน |

---

### 12.1 ระดับการคัดแยก (Triage Levels)

| ระดับ | สี | ชื่อไทย | ความหมาย | Enum Value | Sort Order | ผู้มีสิทธิระบุ |
|:---|:---|:---|:---|:---|:---|:---|
| 1 | ⚫ **ดำ** | **เคสดำ / เสียชีวิต** | เสียชีวิตแล้ว หรือบาดเจ็บรุนแรงเกินศักยภาพ/ทรัพยากรที่จะช่วยชีวิตไว้ได้ | `deceased` | 1 | **จิตอาสา + อาชีพหมวด `provider`** 🔒 |
| 2 | 🔴 แดง | ผู้ป่วยวิกฤต | ต้องช่วยเหลือทันที มีภาวะคุกคามต่อชีวิต | `critical` | 2 | จิตอาสาในเหตุการณ์ |
| 3 | 🟡 เหลือง | ผู้ป่วยรีบด่วน | ต้องช่วยเหลือเร็ว แต่รอได้ระยะสั้น | `urgent` | 3 | จิตอาสาในเหตุการณ์ |
| 4 | 🟢 เขียว | ผู้ป่วยไม่รีบด่วน | อาการเล็กน้อย รอได้ | `non_urgent` | 4 | จิตอาสาในเหตุการณ์ |
| 5 | ⚪ **ขาว** | **ผู้ป่วยทั่วไป / ยังไม่ประเมิน** | ป่วยทั่วไป เช่น เป็นหวัด มีไข้ ไอ — และรวมกรณีที่ยังไม่ถูกจิตอาสาประเมิน | `white` | 5 | **(ค่าเริ่มต้น)** — จิตอาสาเปลี่ยนได้ |

> **⚪ ขาว = ค่า Default เดียวของระบบ** ✅ยืนยัน — ไม่มีสถานะ "เทา/unassessed" แยกอีกต่อไป
> ทุก record ที่ถูกแจ้งชื่อเริ่มที่ `white` และแยกกรณี "ยังไม่ประเมิน" กับ "ประเมินแล้วว่าเป็นผู้ป่วยทั่วไป" ด้วยฟิลด์ `triaged_at`:
>
> | เงื่อนไข | ความหมาย | แสดงบน UI |
> |:---|:---|:---|
> | `triage_level='white'` AND `triaged_at IS NULL` | ยังไม่ถูกประเมิน | `⚪ ยังไม่ประเมิน` |
> | `triage_level='white'` AND `triaged_at IS NOT NULL` | ประเมินแล้ว = ผู้ป่วยทั่วไป | `⚪ ผู้ป่วยทั่วไป` |

> **⚠️ หมายเหตุ**: ⚫ ดำ ถูกจัด **Sort Order = 1** เพื่อให้ทีมอาสาเห็นภาพรวมทรัพยากรก่อน (หลัก START Triage — เคสดำไม่ต้องใช้ทรัพยากรช่วยชีวิตแล้ว) หากต้องการให้ 🔴 แดงขึ้นบนสุดเพราะเป็นเคสที่ต้องรีบที่สุด ให้สลับเป็น `critical=1, deceased=2` แล้วแก้ `TRIAGE_SORT_ORDER` ที่จุดเดียว

#### 12.1.1 เงื่อนไขพิเศษของเคสดำ (Black Tag Authorization)

> **หลักการ**: การชี้ว่าบุคคลเสียชีวิตเป็นข้อมูลที่มีผลทางกฎหมายและกระทบครอบครัวโดยตรง — เงื่อนไขต้อง**รัดกุมกว่าสีอื่นทั้งหมด**

```text
┌──────────────────────────────────────────────────────────────┐
│  สิทธิระบุเคสดำ = ต้องผ่านทั้ง 2 เงื่อนไขพร้อมกัน (AND)        │
├──────────────────────────────────────────────────────────────┤
│ ① เป็นจิตอาสาที่เข้าร่วมช่วยเหลือในเหตุการณ์นั้น              │
│    incident_responses.status IN ('accepted','en_route','arrived') │
│                            AND                               │
│ ② อาชีพอยู่ในหมวดหมู่ผู้ให้บริการสุขภาพ                       │
│    professions.category = 'provider'                         │
│    (FK → user_categories.id — ยืนยันแล้วว่ามีค่านี้จริง)       │
└──────────────────────────────┬───────────────────────────────┘
                               ▼
            canTriageBlack = true  → ปุ่ม ⚫ เปิดใช้งาน
            canTriageBlack = false → ปุ่ม ⚫ แสดงแบบ disabled
                                      + ข้อความอธิบายเหตุผล
```

**ข้อกำหนดเพิ่มเติมของเคสดำ:**

| ข้อ | ข้อกำหนด | เหตุผล |
|:--|:---|:---|
| 1 | **บังคับกรอก `triage_note`** (อย่างน้อย 10 อักขระ) | ต้องมีเหตุผลทางคลินิกบันทึกไว้ |
| 2 | **Double Confirm** — พิมพ์คำว่า `ยืนยัน` ก่อนบันทึก | ป้องกันกดพลาด |
| 3 | **บันทึก snapshot อาชีพ + หมวดหมู่** ณ เวลาที่ระบุ | ตรวจย้อนหลังได้ว่าผู้ระบุมีสิทธิจริง |
| 4 | **ห้าม auto-unlock ข้อมูลสุขภาพ** สำหรับเคสดำ | ผู้เสียชีวิตไม่ได้ให้ความยินยอมเพื่อการนี้ (ดู 12.10) |
| 5 | **ไม่แสดงจำนวนเคสดำต่อผู้ชมทั่วไป** — ซ่อนทั้ง list และ Map Badge | ป้องกันข่าวลือ/ความตื่นตระหนก ก่อนแจ้งญาติอย่างเป็นทางการ |
| 6 | **เปลี่ยนออกจากดำได้** แต่ต้องเป็น `provider` เช่นกัน + บังคับเหตุผล | กรณีประเมินผิด (เช่น พบว่ายังมีชีพจร) |
| 7 | **System Message ใน Live Chat** — แจ้งเฉพาะทีมอาสา ไม่ broadcast ทั้งห้อง | PDPA + ความอ่อนไหว |

> **⚠️ ข้อจำกัดที่ต้องยอมรับ**: หมวด `provider` ในระบบนี้ครอบคลุมกว้าง — รวม `ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า` และ `คลินิก/ศูนย์` ด้วย ไม่ใช่แค่แพทย์/พยาบาล
> หากต้องการรัดกุมกว่านี้ ให้เปลี่ยนเงื่อนไข ② เป็นการเช็ค `professions.profession_code IN ('doctor_gp','doctor_family','doctor_specialist','nurse',...)` แทน — **ดูข้อ 12.15 #1**

---

### 12.2 PDPA — การปกปิดชื่อ (Name Masking Architecture)

> **⚠️ หลักการเด็ดขาด**: การ mask ต้องทำที่ **Backend** เท่านั้น
> ห้ามส่งชื่อเต็มลง Client แล้วซ่อนใน UI เพราะผู้ใช้สามารถดักจับ Network Response ได้ = ข้อมูลรั่วไหลตาม PDPA มาตรา 37

```text
┌─────────────────────────────────────────────────────────┐
│ Client ขอรายชื่อ: GET /api/incidents/{id}/victims       │
│         Header: Authorization + X-User-Id               │
└───────────────────────┬─────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────┐
│ Backend: canViewFullName(userId, incidentId, victimRow)? │
│   ├── เป็น Responder ใน incident_responses              │
│   │   status IN ('accepted','en_route','arrived')  → ✅  │
│   ├── เป็น Admin / Super Admin                     → ✅  │
│   ├── เป็นผู้กรอก record นั้นเอง (reported_by)      → ✅* │
│   └── อื่นๆ ทั้งหมด (รวม Reporter ผู้ถ่ายวิดีโอ)     → ❌  │
└───────────────────────┬─────────────────────────────────┘
                        ▼
        ┌───────────────┴────────────────┐
        ▼ ✅ มีสิทธิ                      ▼ ❌ ไม่มีสิทธิ
┌──────────────────────┐      ┌────────────────────────────┐
│ { prefix: "นาย",     │      │ { prefix: "นาย",           │
│   firstName: "สมชาย",│      │   firstName: null,   ← ตัดทิ้ง│
│   lastName: "ใจดี",  │      │   lastName: null,    ← ตัดทิ้ง│
│   displayName:       │      │   displayName: "นาย ก",     │
│     "นาย สมชาย ใจดี",│      │   isMasked: true }          │
│   isMasked: false }  │      └────────────────────────────┘
└──────────────────────┘
```

> **✅\* = เห็นเฉพาะ record ที่ตนเองกรอกเท่านั้น** — เป็นการตรวจ **รายแถว (per-row)** ไม่ใช่ต่อ 1 request
> ในชุดข้อมูลเดียวกัน ผู้กรอกอาจเห็นชื่อเต็มบางแถว และเห็นชื่อย่อในแถวที่คนอื่นกรอก

**อัลกอริทึมย่อชื่อ (`maskVictimName`):**

```javascript
// websocket-server/utils/victim-name-mask.js
const THAI_PREFIX_MAP = {
  'นาย': 'นาย', 'นาง': 'นาง', 'นางสาว': 'นางสาว',
  'ด.ช.': 'ด.ช.', 'ด.ญ.': 'ด.ญ.', 'ไม่ระบุ': 'บุคคล',
};
const EN_PREFIX_MAP = {
  'นาย': 'Mr.', 'นาง': 'Mrs.', 'นางสาว': 'Ms.',
  'ด.ช.': 'Master', 'ด.ญ.': 'Miss', 'ไม่ระบุ': 'Person',
};

function isThaiText(s) { return /[\u0E00-\u0E7F]/.test(s || ''); }

function maskVictimName(prefix, firstName) {
  const name = (firstName || '').trim();
  if (!name) return `${THAI_PREFIX_MAP[prefix] || 'บุคคล'} (ไม่ทราบชื่อ)`;

  if (isThaiText(name)) {
    // ไทย: พยัญชนะตัวแรก — ต้องข้ามสระนำหน้า (เ แ โ ไ ใ) เช่น "เอกชัย" → "อ"
    const LEADING_VOWELS = ['เ', 'แ', 'โ', 'ไ', 'ใ'];
    let ch = name[0];
    if (LEADING_VOWELS.includes(ch) && name.length > 1) ch = name[1];
    return `${THAI_PREFIX_MAP[prefix] || 'บุคคล'} ${ch}`;
  }
  // อังกฤษ: ตัวอักษรแรกพิมพ์ใหญ่ → "Mr. J"
  return `${EN_PREFIX_MAP[prefix] || 'Person'} ${name[0].toUpperCase()}`;
}
```

> **⚠️ กับดักภาษาไทย**: ชื่อ "เอกชัย" ถ้าใช้ `name[0]` ตรงๆ จะได้ "เ" ซึ่งเป็นสระ ไม่ใช่พยัญชนะ — ต้องข้ามสระนำหน้า (เ แ โ ไ ใ) เสมอ

**ป้องกันการเดาชื่อซ้ำ (De-anonymization Risk):**
หากในเหตุการณ์เดียวมี "นาย ก" หลายคน ให้เติมลำดับต่อท้าย: `นาย ก (1)`, `นาย ก (2)` — คำนวณที่ Backend จาก sort order ของ `created_at`

**การ mask แบบรายแถว (Row-level Masking):**

```javascript
// websocket-server/services/victim-permission-service.js
function serializeVictim(row, ctx) {
  // ctx = { isResponder, isAdmin, userId, canTriageBlack }
  const canSeeFull = ctx.isResponder || ctx.isAdmin || row.reported_by === ctx.userId;

  // ⚫ เคสดำ: ห้ามส่งออกต่อผู้ที่ไม่ใช่ทีมอาสา/Admin (12.1.1 ข้อ 5)
  const hideBlack = row.triage_level === 'deceased' && !(ctx.isResponder || ctx.isAdmin);
  if (hideBlack) return null; // กรองออกจากผลลัพธ์ทั้งแถว

  return {
    id: row.id,
    prefix: row.prefix,
    firstName: canSeeFull ? row.first_name : null,
    lastName:  canSeeFull ? row.last_name  : null,
    displayName: canSeeFull
      ? `${row.prefix} ${row.first_name} ${row.last_name}`.trim()
      : row.masked_name,
    isMasked: !canSeeFull,
    triageLevel: row.triage_level,
    // triage_note เห็นเฉพาะทีมอาสา/Admin เท่านั้น — ผู้กรอกก็ไม่เห็น
    triageNote: (ctx.isResponder || ctx.isAdmin) ? row.triage_note : null,
  };
}
```

> **⚠️ สิทธิผู้กรอกไม่เท่ากับจิตอาสา**: ผู้กรอกเห็นแค่**ชื่อเต็มที่ตนเองกรอก** — ไม่เห็น `triage_note` และไม่เห็นเคสดำ

---

### 12.3 Database Schema

#### 12.3.1 ตารางหลัก `incident_victims`

```sql
-- migration: 20260809xxxxxx_create_incident_victims.sql
-- ⚠️ FK ต้องชี้ public.users ไม่ใช่ auth.users (ดู Section 11.5)

-- ⚫ ดำ เพิ่มเข้าเป็นค่าที่ 1 เพื่อให้ ORDER BY triage_level เรียงตามลำดับที่ต้องการโดยตรง
CREATE TYPE triage_level AS ENUM ('deceased', 'critical', 'urgent', 'non_urgent', 'white');
CREATE TYPE victim_verify_status AS ENUM ('unverified', 'confirmed', 'disputed');

CREATE TABLE incident_victims (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id       UUID NOT NULL,          -- อ้างถึง videos.id (incident หลัก)

    -- ── ข้อมูลบุคคล (PDPA Sensitive) ──
    prefix            VARCHAR(20) NOT NULL DEFAULT 'ไม่ระบุ',
    first_name        VARCHAR(100),
    last_name         VARCHAR(100),
    masked_name       VARCHAR(120) NOT NULL,  -- pre-computed ตอน insert เพื่อไม่ต้องคำนวณทุก request
    linked_user_id    UUID REFERENCES users(id) ON DELETE SET NULL, -- ถ้าเป็นผู้ใช้ในระบบ

    -- ── การคัดแยก ──
    triage_level      triage_level NOT NULL DEFAULT 'white',   -- ⚪ ขาว = ผู้ป่วยทั่วไป/ยังไม่ประเมิน
    triaged_by        UUID REFERENCES users(id) ON DELETE SET NULL,
    triaged_at        TIMESTAMPTZ,
    triage_note       TEXT,                   -- อาการที่พบ (เห็นเฉพาะทีมอาสา)
    triaged_by_profession_id       UUID REFERENCES professions(id) ON DELETE SET NULL, -- snapshot
    triaged_by_profession_category VARCHAR(50),  -- snapshot: 'provider' / 'consumer' / ...

    -- ── ⚫ เคสดำ (Deceased) — ต้องรัดกุมกว่าสีอื่น ──
    deceased_confirmed_by     UUID REFERENCES users(id) ON DELETE SET NULL,
    deceased_confirmed_at     TIMESTAMPTZ,
    deceased_reason           TEXT,           -- บังคับกรอก ≥ 10 อักขระ

    -- ── การยืนยัน / ปฏิเสธ ──
    verify_status     victim_verify_status NOT NULL DEFAULT 'unverified',
    disputed_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    disputed_reason   TEXT,
    disputed_at       TIMESTAMPTZ,

    -- ── ที่มา ──
    reported_by       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_deleted        BOOLEAN NOT NULL DEFAULT FALSE,  -- Soft delete เท่านั้น (audit)
    deleted_by        UUID REFERENCES users(id) ON DELETE SET NULL,
    deleted_at        TIMESTAMPTZ,
    deleted_reason    TEXT,

    -- ── Health Data Link ──
    health_data_consent_verified BOOLEAN NOT NULL DEFAULT FALSE,
    health_data_unlocked_at      TIMESTAMPTZ,

    -- ── Retention Countdown (ปิดข้อ 12.13 #12 — ข้อมูลค้างในระบบ) ──
    -- เริ่มนับเมื่อเหตุการณ์จบ ไม่ใช่ตอนสร้าง record เพื่อไม่ให้ตัดข้อมูลระหว่างเหตุการณ์ยังดำเนินอยู่
    -- ครอบคลุมทั้ง record ที่ยังไม่ถูกประเมิน (white/triaged_at IS NULL — รวมชื่อที่ถูกแจ้งมั่ว) และที่ถูกประเมินแล้ว
    retention_countdown_started_at TIMESTAMPTZ,

    is_synced         BOOLEAN NOT NULL DEFAULT FALSE,  -- สำหรับ Cloud Sync
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_victims_incident      ON incident_victims(incident_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_victims_triage        ON incident_victims(incident_id, triage_level) WHERE is_deleted = FALSE;
CREATE INDEX idx_victims_deceased      ON incident_victims(incident_id)
    WHERE is_deleted = FALSE AND triage_level = 'deceased';
CREATE INDEX idx_victims_sync          ON incident_victims(is_synced) WHERE is_synced = FALSE;
CREATE INDEX idx_victims_linked_user   ON incident_victims(linked_user_id) WHERE linked_user_id IS NOT NULL;
-- ใช้โดย anonymize cron job (12.16) เพื่อหา record ที่ครบกำหนดลบ
CREATE INDEX idx_victims_retention     ON incident_victims(retention_countdown_started_at)
    WHERE is_deleted = FALSE AND retention_countdown_started_at IS NOT NULL;

-- ป้องกันแจ้งชื่อซ้ำในเหตุการณ์เดียวกัน (เฉพาะที่กรอกชื่อจริง)
CREATE UNIQUE INDEX idx_victims_no_dup
    ON incident_victims(incident_id, lower(first_name), lower(last_name))
    WHERE is_deleted = FALSE AND first_name IS NOT NULL AND last_name IS NOT NULL;

-- บังคับที่ระดับ DB: เคสดำต้องมีคนยืนยัน + เหตุผลเสมอ
ALTER TABLE incident_victims ADD CONSTRAINT chk_deceased_requires_confirmation
    CHECK (
        triage_level <> 'deceased'
        OR (deceased_confirmed_by IS NOT NULL
            AND deceased_confirmed_at IS NOT NULL
            AND char_length(coalesce(deceased_reason, '')) >= 10)
    );

-- เคสดำห้ามปลดล็อกข้อมูลสุขภาพ (12.1.1 ข้อ 4)
ALTER TABLE incident_victims ADD CONSTRAINT chk_deceased_no_health_unlock
    CHECK (NOT (triage_level = 'deceased' AND health_data_consent_verified = TRUE));

ALTER TABLE incident_victims DISABLE ROW LEVEL SECURITY; -- backend ใช้ service role
```

> **⚠️ ทำไมต้องบังคับที่ระดับ DB ด้วย**: การตรวจที่ Backend อย่างเดียวอาจพลาดได้หากมี code path ใหม่ — เคสดำมีผลทางกฎหมาย จึงต้องมี defense-in-depth

#### 12.3.2 ตาราง History `incident_victim_triage_logs`

```sql
CREATE TABLE incident_victim_triage_logs (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    victim_id      UUID NOT NULL REFERENCES incident_victims(id) ON DELETE CASCADE,
    incident_id    UUID NOT NULL,
    from_level     triage_level,
    to_level       triage_level NOT NULL,
    changed_by     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    changed_by_role VARCHAR(100),      -- snapshot ชื่ออาชีพ ณ เวลานั้น
    changed_by_profession_id       UUID REFERENCES professions(id) ON DELETE SET NULL,
    changed_by_profession_category VARCHAR(50),  -- สำคัญสำหรับ audit เคสดำ
    note           TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_triage_logs_victim ON incident_victim_triage_logs(victim_id, created_at DESC);
-- ดึงประวัติการระบุเคสดำทั้งหมดเพื่อการตรวจสอบ
CREATE INDEX idx_triage_logs_deceased ON incident_victim_triage_logs(incident_id, created_at DESC)
    WHERE to_level = 'deceased';
ALTER TABLE incident_victim_triage_logs DISABLE ROW LEVEL SECURITY;
```

> **Last-write-wins + History**: ทุกครั้งที่เปลี่ยนสี ระบบ `INSERT` log ใหม่เสมอ ไม่ทับของเดิม → ตรวจสอบย้อนหลังได้ว่าใครเปลี่ยนอะไรเมื่อไร (สำคัญมากหากเกิดข้อพิพาททางกฎหมาย)

#### 12.3.4 ตาราง Audit Logs

```sql
-- บันทึก consent ตอนแจ้งชื่อ (PDPA)
CREATE TABLE victim_report_consent_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    victim_id       UUID NOT NULL REFERENCES incident_victims(id) ON DELETE CASCADE,
    reported_by     UUID NOT NULL REFERENCES users(id),
    consented       BOOLEAN NOT NULL DEFAULT TRUE,
    ip_address      INET,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_victim_consent_victim ON victim_report_consent_logs(victim_id, created_at DESC);
ALTER TABLE victim_report_consent_logs DISABLE ROW LEVEL SECURITY;

-- บันทึกทุกครั้งทีเปิดดูข้อมูลสุขภาพ (12.10)
CREATE TABLE health_data_access_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    victim_id       UUID NOT NULL REFERENCES incident_victims(id) ON DELETE CASCADE,
    accessed_by     UUID NOT NULL REFERENCES users(id),
    session_id      UUID,  -- emergency_health_release_sessions.id (ถ้ามี)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_health_access_victim ON health_data_access_logs(victim_id, created_at DESC);
CREATE INDEX idx_health_access_user   ON health_data_access_logs(accessed_by, created_at DESC);
ALTER TABLE health_data_access_logs DISABLE ROW LEVEL SECURITY;
```

#### 12.3.3 Cloud Sync Schema

> **⚠️ บทเรียนจาก Section 11 (Local-to-Cloud Sync)**: ต้องกำหนด local-only columns ตั้งแต่แรก มิฉะนั้น sync จะพัง

```javascript
// websocket-server/services/sync-service.js
const VICTIM_LOCAL_ONLY_COLUMNS = new Set([
    'is_synced',
]);
```

**Cloud table `incident_victims` ต้องมี column เหมือน Local ทุกตัว ยกเว้น `is_synced`**

**ประเด็นความปลอดภัยของการ Sync ชื่อจริงขึ้น Cloud:**

| ทางเลือก | ข้อดี | ข้อเสีย | คำแนะนำ |
|:---|:---|:---|:---|
| **A. Sync ชื่อเต็ม plaintext** | ง่าย query ได้ | ชื่อจริงผู้บาดเจ็บอยู่บน Cloud แบบอ่านได้ | ❌ ไม่แนะนำ |
| **B. Sync เฉพาะ `masked_name`** | ปลอดภัยสูงสุด | ทีมอาสาดูย้อนหลังจาก Cloud ไม่ได้ | ⚠️ ถ้าไม่ต้องดูย้อนหลัง |
| **C. เข้ารหัสชื่อด้วย `pgcrypto`** | ปลอดภัย + ยังกู้คืนได้ | ต้องจัดการ key | ✅ **แนะนำ** |

```sql
-- ทางเลือก C: เข้ารหัสก่อน sync
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Cloud เก็บเป็น BYTEA แทน VARCHAR
first_name_enc  BYTEA,   -- pgp_sym_encrypt(first_name, $2) เมื่อ sync; $2 มาจาก process.env.VICTIM_NAME_ENC_KEY
last_name_enc   BYTEA,
masked_name     VARCHAR(120) NOT NULL,  -- ตัวนี้ plaintext ได้ ไม่ระบุตัวตน
```

---

### 12.4 Permission Matrix (ตารางสิทธิ์)

| การกระทำ | ผู้ชมทั่วไป / ไทยมุง | ผู้กรอกข้อมูล (Reporter of victim) | Reporter เหตุการณ์ | ทีมอาสา (accepted/en_route/arrived) | Admin |
|:---|:---:|:---:|:---:|:---:|:---:|
| ดูรายชื่อ (ชื่อย่อ) | ✅ | ✅ | ✅ | ✅ | ✅ |
| ดูชื่อเต็ม | ❌ | ✅* เฉพาะที่ตนกรอก | ❌ | ✅ ทั้งหมด | ✅ ทั้งหมด |
| ดูสีคัดแยก | ✅ | ✅ | ✅ | ✅ | ✅ |
| ดู `triage_note` (อาการ) | ❌ | ❌ | ❌ | ✅ | ✅ |
| เพิ่มรายชื่อ | ✅ | ✅ | ✅ | ✅ | ✅ |
| แก้ไขชื่อ (ก่อนระบุสี) | ❌ | ✅ เฉพาะของตน | ❌ | ✅ | ✅ |
| แก้ไขชื่อ (หลังระบุสีแล้ว) | ❌ | ❌ **ล็อก** | ❌ | ✅ | ✅ |
| **กำหนด/เปลี่ยนสีคัดแยก** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **ลบรายชื่อ** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **ปฏิเสธความถูกต้อง (Dispute)** | ❌ | ❌ | ❌ | ✅ | ✅ |
| ดู History การเปลี่ยนสี | ❌ | ❌ | ❌ | ✅ | ✅ |
| ดูข้อมูลสุขภาพที่ปลดล็อก | ❌ | ❌ | ❌ | ✅ (ตามเงื่อนไข 12.7) | ✅ |

> **✅ ยืนยันแล้ว (\*)**: **ผู้กรอกเห็นชื่อเต็มเฉพาะ record ที่ตนเองกรอกเท่านั้น** (per-row ไม่ใช่ per-request)
> เหตุผล: เป็นข้อมูลที่ตนพิมพ์เข้าไปเอง การ mask กลับไม่มีความหมายเชิงความปลอดภัย
> **บังคับที่ Backend**: ตรวจ `victim.reported_by === userId` ทีละแถวก่อนตัดสินใจ mask — `canViewFull` ระดับ request **ยังเป็น `false`** สำหรับผู้กรอก

**ฟังก์ชันตรวจสิทธิ์ฝั่ง Backend:**

> **⚠️ แก้ไข 2026-08-09 — ปิด conflict กับ `01_broken_object_level_authorization.md` (O1: เชื่อ userId จาก request โดยไม่ verify)**
> ห้ามส่ง `userId` ที่มาจาก `req.query`/`req.body`/header ดิบเข้าฟังก์ชันนี้โดยตรง — ต้องผ่าน middleware `verifyToken` + `requireAuth` (มีอยู่แล้วใน `websocket-server/middleware/auth.js`) ก่อนเสมอ ซึ่งจะ verify `x-user-id` กับตาราง `users` จริง (เช็ค `is_active`) แล้วเซ็ต `req.userId` ที่เชื่อถือได้ — **รูปแบบเดียวกับที่ `video.js` ใช้อยู่แล้ว** (`const userId = req.userId` ไม่ใช่จาก `req.body`)
> Flutter ฝั่ง client ส่ง `x-user-id` จาก `ServiceLocator.instance.currentUser?.id` ตาม `auth_data_guidelines.md` อยู่แล้ว (ดูตัวอย่างใน `watermark_repository.dart`) — chain นี้จึงสอดคล้องกับ interim pattern ที่ทั้งระบบใช้ ไม่ใช่การเชื่อ header แบบ raw

```javascript
// websocket-server/routes/victims.js
// ทุก route ต้องผ่าน requireAuth ก่อนเข้าถึง handler:
// router.get('/api/incidents/:incidentId/victims', requireAuth, async (req, res) => { ... })
// router.patch('/api/victims/:victimId/triage', requireAuth, strictRateLimiter, async (req, res) => { ... })

// websocket-server/services/victim-permission-service.js
async function getVictimPermissions(userId, incidentId) {
  // userId ต้องเป็น req.userId ที่ผ่าน verifyToken แล้วเท่านั้น — ไม่ใช่ req.query.userId/req.body.userId
  if (!userId) return { canViewFull: false, isResponder: false, isAdmin: false };

  const [responderRes, adminRes] = await Promise.all([
    pool.query(
      `SELECT 1 FROM incident_responses
        WHERE video_id = $1 AND volunteer_id = $2
          AND status IN ('accepted','en_route','arrived') LIMIT 1`,
      [incidentId, userId]
    ),
    pool.query(
      `SELECT 1 FROM users
        WHERE id = $1 AND role = 'admin' AND is_active = TRUE LIMIT 1`,
      [userId]
    ),
  ]);

  const isResponder = responderRes.rowCount > 0;
  const isAdmin = adminRes.rowCount > 0;
  return {
    isResponder,
    isAdmin,
    canViewFull:  isResponder || isAdmin,  // ผู้กรอกตรวจแยกรายแถว
    canTriage:    isResponder || isAdmin,
    canDelete:    isResponder || isAdmin,
    canDispute:   isResponder || isAdmin,
    canViewNote:  isResponder || isAdmin,
  };
}
```

> **⚠️ ต้องตรวจสอบก่อน implement**: ชื่อ table/column จริงของ `incident_responses` และ flag admin ใน `users` — แผนนี้อ้างอิงจากเอกสาร Section 5 แต่ยังไม่ได้ verify กับ schema จริง

---

### 12.5 State Machine & Edit Lock

```text
┌──────────────────────────────────────────────────────────────┐
│                    วงจรชีวิตของ Victim Record                 │
└──────────────────────────────────────────────────────────────┘

   [ใครก็ได้กรอกชื่อ]
          │
          ▼
   ┌─────────────────────┐
   │  ⚪ white            │  ← ผู้กรอก แก้ไข/ลบชื่อตนเองได้
   │  triaged_at: NULL   │     (ยังไม่ล็อก)
   └──────────┬──────────┘
              │ จิตอาสาระบุสี  (canTriage = true)
              ▼
   ┌─────────────────────────────────────────┐
   │  🔴 critical / 🟡 urgent / 🟢 non_urgent │  🔒 ผู้กรอกล็อก
   │  verify: confirmed                      │     แก้/ลบไม่ได้อีก
   └──────────┬──────────────────────────────┘
              │
     ┌────────┴─────────┬──────────────────┐
     ▼                  ▼                  ▼
 [เปลี่ยนสีซ้ำ]     [Dispute]          [ลบ]
 Last-write-wins   verify: disputed   is_deleted = TRUE
 + INSERT log      + เหตุผลบังคับ     + เหตุผลบังคับ
 (จิตอาสาเท่านั้น)  (จิตอาสาเท่านั้น)   (จิตอาสาเท่านั้น)
```

**เงื่อนไข Edit Lock (บังคับที่ Backend ไม่ใช่แค่ซ่อนปุ่ม):**

```javascript
function canEditVictim(victim, perms, userId) {
  if (victim.is_deleted) return false;
  if (perms.isResponder || perms.isAdmin) return true;       // จิตอาสาแก้ได้เสมอ
  if (victim.reported_by !== userId) return false;           // ไม่ใช่ของตน
  return victim.triaged_at === null;                          // 🔒 ล็อกหลังจิตอาสาประเมิน
}
```

---

### 12.6 API Endpoints (Node.js — `websocket-server/routes/victims.js`)

| Method | Path | Middleware | สิทธิ์ | คำอธิบาย |
|:---|:---|:---|:---|:---|
| `GET` | `/api/incidents/:incidentId/victims` | `verifyToken` (identity ไม่บังคับ) | ทุกคน | รายชื่อ (masked ตามสิทธิ) + สรุปนับแต่ละสี — ไม่ login ก็ดูชื่อย่อได้ |
| `POST` | `/api/incidents/:incidentId/victims` | `requireAuth` | ทุกคน (login แล้ว) | เพิ่มรายชื่อผู้อยู่ในเหตุการณ์ |
| `PATCH` | `/api/victims/:victimId` | `requireAuth` | ผู้กรอก (ก่อนระบุสี) / จิตอาสา | แก้ไขชื่อ-สกุล |
| `PATCH` | `/api/victims/:victimId/triage` | `requireAuth` + `strictRateLimiter` | **จิตอาสาเท่านั้น** | กำหนด/เปลี่ยนสีคัดแยก |
| `POST` | `/api/victims/:victimId/dispute` | `requireAuth` | **จิตอาสาเท่านั้น** | ปฏิเสธความถูกต้องของชื่อ |
| `DELETE` | `/api/victims/:victimId` | `requireAuth` | **จิตอาสาเท่านั้น** | Soft delete (ต้องระบุเหตุผล) |
| `GET` | `/api/victims/:victimId/history` | `requireAuth` | จิตอาสา / Admin | ประวัติการเปลี่ยนสี |
| `GET` | `/api/incidents/:incidentId/triage-summary` | ไม่บังคับ login | ทุกคน | สรุปนับสำหรับ Map Badge (เบา ไม่มีชื่อเลย) |

> **⚠️ ทุก route ที่ต้อง login ต้องใส่ `requireAuth` (จาก `middleware/auth.js`) — ห้ามอ่าน `userId` เองจาก `req.body`/`req.query` แล้วส่งเข้า service function ตรงๆ (ปิด O1 ตาม `01_broken_object_level_authorization.md`)**

#### 12.6.1 DB Functions (Atomic Mutation)

ทุก mutation จับคู่กับ API endpoints ด้านบน โดย route handler เรียก DB function เพื่อความ atomic และ audit:

```sql
-- 1. insert_victim(...) — เรียกจาก POST /api/incidents/:id/victims
-- คำนวณ masked_name + บันทึก consent log ในธุรกรรมเดียว
CREATE OR REPLACE FUNCTION insert_victim(
    p_incident_id UUID,
    p_prefix      VARCHAR(20),
    p_first_name  VARCHAR(100),
    p_last_name   VARCHAR(100),
    p_masked_name VARCHAR(120),  -- คำนวณโดย utils/victim-name-mask.js ก่อนเรียก
    p_reported_by UUID,
    p_consent     BOOLEAN
) RETURNS incident_victims AS $$
DECLARE
    v_limit   INT;
    v_count   INT;
    v_victim  incident_victims;
BEGIN
    -- ตรวจ Rate Limit (per incident / per reporter)
    SELECT (value->>'victimReportRateLimitPerIncident')::INT INTO v_limit
    FROM app_settings WHERE key = 'video_system_config';
    v_limit := COALESCE(v_limit, 0);

    IF v_limit > 0 THEN
        SELECT COUNT(*) INTO v_count
        FROM incident_victims
        WHERE incident_id = p_incident_id
          AND reported_by = p_reported_by
          AND is_deleted = FALSE;

        IF v_count >= v_limit THEN
            RAISE EXCEPTION 'VICTIM_REPORT_RATE_LIMIT_EXCEEDED';
        END IF;
    END IF;

    INSERT INTO incident_victims (
        incident_id, prefix, first_name, last_name, masked_name,
        reported_by, verify_status
    ) VALUES (
        p_incident_id, p_prefix, p_first_name, p_last_name, p_masked_name,
        p_reported_by, 'unverified'
    ) RETURNING * INTO v_victim;

    -- บันทึก consent log
    INSERT INTO victim_report_consent_logs (victim_id, reported_by, consented)
    VALUES (v_victim.id, p_reported_by, p_consent);

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;
```

```sql
-- 2. dispute_victim(...) — เรียกจาก POST /api/victims/:id/dispute
CREATE OR REPLACE FUNCTION dispute_victim(
    p_victim_id UUID,
    p_disputed_by UUID,
    p_reason TEXT
) RETURNS incident_victims AS $$
DECLARE
    v_victim incident_victims;
BEGIN
    SELECT * INTO v_victim FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    IF v_victim.verify_status = 'disputed' THEN
        RAISE EXCEPTION 'ALREADY_DISPUTED';
    END IF;

    IF p_reason IS NULL OR char_length(p_reason) < 10 THEN
        RAISE EXCEPTION 'DISPUTE_REASON_TOO_SHORT';
    END IF;

    UPDATE incident_victims SET
        verify_status   = 'disputed',
        disputed_by     = p_disputed_by,
        disputed_reason = p_reason,
        disputed_at     = NOW(),
        is_synced       = FALSE,
        updated_at      = NOW()
     WHERE id = p_victim_id
    RETURNING * INTO v_victim;

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;
```

```sql
-- 3. edit_victim_name(...) — เรียกจาก PATCH /api/victims/:id
-- จิตอาสาแก้ชื่อหลัง dispute → เปลี่ยน verify_status กลับเป็น 'confirmed' อัตโนมัติ
CREATE OR REPLACE FUNCTION edit_victim_name(
    p_victim_id UUID,
    p_editor_id UUID,
    p_prefix     VARCHAR(20),
    p_first_name VARCHAR(100),
    p_last_name  VARCHAR(100),
    p_masked_name VARCHAR(120)  -- คำนวณโดย utils/victim-name-mask.js ก่อนเรียก
) RETURNS incident_victims AS $$
DECLARE
    v_victim incident_victims;
BEGIN
    SELECT * INTO v_victim FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    UPDATE incident_victims SET
        prefix        = p_prefix,
        first_name    = p_first_name,
        last_name     = p_last_name,
        masked_name   = p_masked_name,
        verify_status = 'confirmed',
        is_synced     = FALSE,
        updated_at    = NOW()
     WHERE id = p_victim_id
    RETURNING * INTO v_victim;

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;
```

```sql
-- 4. soft_delete_victim(...) — เรียกจาก DELETE /api/victims/:id
CREATE OR REPLACE FUNCTION soft_delete_victim(
    p_victim_id UUID,
    p_deleted_by UUID,
    p_reason TEXT
) RETURNS incident_victims AS $$
DECLARE
    v_victim incident_victims;
BEGIN
    SELECT * INTO v_victim FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    IF p_reason IS NULL OR char_length(p_reason) < 10 THEN
        RAISE EXCEPTION 'DELETE_REASON_TOO_SHORT';
    END IF;

    UPDATE incident_victims SET
        is_deleted     = TRUE,
        deleted_by     = p_deleted_by,
        deleted_at     = NOW(),
        deleted_reason = p_reason,
        is_synced      = FALSE,
        updated_at     = NOW()
     WHERE id = p_victim_id
    RETURNING * INTO v_victim;

    RETURN v_victim;
END;
$$ LANGUAGE plpgsql;
```

```sql
-- 5. ตัวอย่าง helper SQL สำหรับ permission service
CREATE OR REPLACE FUNCTION is_victim_responder(p_user_id UUID, p_incident_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM incident_responses
         WHERE video_id = p_incident_id
           AND volunteer_id = p_user_id
           AND status IN ('accepted','en_route','arrived')
    );
END;
$$ LANGUAGE plpgsql;
```

**ตัวอย่าง Response — `GET /api/incidents/:id/victims` (ผู้ชมทั่วไป):**

```json
{
  "success": true,
  "summary": { "critical": 2, "urgent": 1, "non_urgent": 3, "white": 1, "total": 7 },
  "viewerPermissions": { "canTriage": false, "canDelete": false, "canViewFull": false },
  "victims": [
    {
      "id": "uuid-1",
      "displayName": "นาย ก",
      "isMasked": true,
      "firstName": null,
      "lastName": null,
      "triageLevel": "critical",
      "triagedAt": "2026-08-09T14:32:00+07:00",
      "triagedByName": "พยาบาลวิชาชีพ",
      "verifyStatus": "confirmed",
      "canEdit": false,
      "hasHealthData": false
    }
  ]
}
```

**ตัวอย่าง Response — ผู้ใช้ที่เป็นจิตอาสาในเหตุการณ์นั้น:**

```json
{
  "viewerPermissions": { "canTriage": true, "canDelete": true, "canViewFull": true },
  "victims": [
    {
      "id": "uuid-1",
      "displayName": "นาย สมชาย ใจดี",
      "isMasked": false,
      "firstName": "สมชาย",
      "lastName": "ใจดี",
      "triageLevel": "critical",
      "triageNote": "หมดสติ ชีพจรเบา",
      "verifyStatus": "confirmed",
      "canEdit": true,
      "hasHealthData": true,
      "healthDataSessionId": "uuid-session"
    }
  ]
}
```

**Atomic Triage Update (ป้องกัน Race Condition):**

```sql
-- DB Function: update_victim_triage(victim_id, new_level, user_id, note)
-- ใช้ SELECT ... FOR UPDATE ตามหลักเดียวกับ Escrow (Section 11.1)
CREATE OR REPLACE FUNCTION update_victim_triage(
    p_victim_id UUID, p_new_level triage_level,
    p_user_id UUID, p_note TEXT
) RETURNS incident_victims AS $$
DECLARE
    v_old        incident_victims;
    v_role       VARCHAR(100);
    v_prof_id    UUID;
    v_prof_cat   VARCHAR(50);
BEGIN
    SELECT * INTO v_old FROM incident_victims
     WHERE id = p_victim_id AND is_deleted = FALSE
     FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'VICTIM_NOT_FOUND'; END IF;

    SELECT p.name, p.id, p.category
      INTO v_role, v_prof_id, v_prof_cat
      FROM users u
      LEFT JOIN professions p ON p.id = u.profession_id
     WHERE u.id = p_user_id;

    -- ⚫ เคสดำ: ต้องเป็น profession category = 'provider' + บังคับเหตุผล ≥ 10 ตัวอักษร
    IF p_new_level = 'deceased' THEN
        IF v_prof_cat IS NULL OR v_prof_cat <> 'provider' THEN
            RAISE EXCEPTION 'DECEASED_REQUIRES_PROVIDER_PROFESSION';
        END IF;
        IF COALESCE(p_note, '') = '' OR char_length(p_note) < 10 THEN
            RAISE EXCEPTION 'DECEASED_REASON_TOO_SHORT';
        END IF;
    END IF;

    -- Last-write-wins: ทับค่าเดิมเสมอ
    UPDATE incident_victims SET
        triage_level                   = p_new_level,
        triaged_by                     = p_user_id,
        triaged_at                     = NOW(),
        triage_note                    = COALESCE(p_note, triage_note),
        triaged_by_profession_id       = v_prof_id,
        triaged_by_profession_category = v_prof_cat,
        verify_status                  = 'confirmed',
        is_synced                      = FALSE,
        updated_at                     = NOW(),
        -- เคสดำ: บันทึกคนยืนยันพร้อมกัน (trigger DB constraint ตรวจอีกชั้น)
        deceased_confirmed_by          = CASE WHEN p_new_level = 'deceased' THEN p_user_id ELSE deceased_confirmed_by END,
        deceased_confirmed_at          = CASE WHEN p_new_level = 'deceased' THEN NOW()        ELSE deceased_confirmed_at END,
        deceased_reason                = CASE WHEN p_new_level = 'deceased' THEN p_note         ELSE deceased_reason END
     WHERE id = p_victim_id;

    -- History: INSERT ใหม่เสมอ ไม่ทับ
    INSERT INTO incident_victim_triage_logs
        (victim_id, incident_id, from_level, to_level, changed_by, changed_by_role,
         changed_by_profession_id, changed_by_profession_category, note)
    VALUES
        (p_victim_id, v_old.incident_id, v_old.triage_level, p_new_level, p_user_id, v_role,
         v_prof_id, v_prof_cat, p_note);

    RETURN (SELECT * FROM incident_victims WHERE id = p_victim_id);
END;
$$ LANGUAGE plpgsql;
```

---

### 12.7 WebSocket Events (Real-time)

Broadcast เข้า room `video-{incidentId}` เหมือน Thai Mhung (Section 11.6)

| Event | ทิศทาง | Payload | ผู้รับ |
|:---|:---|:---|:---|
| `victim-added` | S→C | `{ victimId, displayName, triageLevel, summary }` | ทุกคนในห้อง (ชื่อย่อเสมอ) |
| `victim-triage-updated` | S→C | `{ victimId, fromLevel, toLevel, triagedByName, summary }` | ทุกคนในห้อง |
| `victim-name-updated` | S→C | `{ victimId, displayName }` | ทุกคนในห้อง (ชื่อย่อเสมอ) |
| `victim-deleted` | S→C | `{ victimId, summary }` | ทุกคนในห้อง |
| `victim-disputed` | S→C | `{ victimId, disputedByName, summary }` | ทุกคนในห้อง |
| `victim-health-unlocked` | S→C | `{ victimId, sessionId }` | **เฉพาะ socket ของจิตอาสา** |

> **⚠️ กฎ PDPA สำหรับ WebSocket**: Broadcast **ต้องส่งชื่อย่อเสมอ** ห้ามส่งชื่อเต็มผ่าน broadcast เด็ดขาด เพราะทุกคนในห้องรับได้
> ผู้ที่มีสิทธิ์เห็นชื่อเต็ม ให้ **re-fetch ผ่าน REST API** ที่ตรวจสิทธิ์รายคน หรือใช้ `io.to(socketId).emit()` ยิงตรงเฉพาะ socket ที่ยืนยันสิทธิแล้ว

```javascript
// websocket-server/services/victim-broadcast-service.js
function broadcastTriageUpdate(io, incidentId, payload, summary) {
  // 1. ทุกคน — ชื่อย่อเท่านั้น
  io.to(`video-${incidentId}`).emit('victim-triage-updated', {
    victimId: payload.victimId,
    displayName: payload.maskedName,   // ← masked เสมอ
    fromLevel: payload.fromLevel,
    toLevel: payload.toLevel,
    triagedByName: payload.triagedByName,
    summary,
  });
  // 2. จิตอาสา — ยิงตรงพร้อมชื่อเต็ม
  for (const socketId of getResponderSocketIds(incidentId)) {
    io.to(socketId).emit('victim-triage-updated:full', {
      ...payload, fullName: payload.fullName, triageNote: payload.triageNote,
    });
  }
}
```

---

### 12.8 UI Specification

#### 12.8.1 Entry Point — แก้ไข `bottom_tabs_widget.dart`

> **✅ แก้ไขแล้ว (2026-08-10)**: ปุ่ม "เกี่ยวดอง" มองเห็นได้โดย **ผู้ใช้ทุกคน** (ไม่กรองด้วย `isEligibleResponder`) และเปิด Triage Bottom Sheet แทนที่จะสลับแท็บเต็มจอ ปุ่ม "คัดแยก" แยกต่างหากถูกลบออก เพราะ "เกี่ยวดอง" ทำหน้าที่เป็น entry point เดียว ส่วนสิทธิ์การกระทำ (ระบุสี/ลบ/dispute) ถูกควบคุมในระดับ Backend ตาม Permission Matrix (12.4) ไม่ใช่ควบคุมที่การมองเห็นปุ่ม

```dart
// ✅ แก้ไขแล้ว — ตัด !isEligibleResponder ออกจากทุกปุ่ม
// ทุกคนเห็น ไทยมุง / เกี่ยวดอง / แจ้งเหตุ
if (showThaiMhung && !(selectedTab == 2 || isThaiMhungReporting))

// เกี่ยวดอง เปิด Triage Sheet แทนสลับแท็บ
onTap: onTriageTabSelected ?? () => onTabSelected(1)

// ปุ่ม "คัดแยก" แยกต่างหาก — ลบออกแล้ว (รวมเข้ากับเกี่ยวดอง)
```

**เปลี่ยนพฤติกรรมจาก Tab เป็น Bottom Sheet:**

```dart
// เดิม: onTap: () => onTabSelected(1)  → เปลี่ยน _selectedTab = 1 (เต็มจอ)
// ใหม่: onTap: onTriageTap             → เปิด showModalBottomSheet ครึ่งจอ

// ใน emergency_live_page.dart
void _showTriageSheet() {
  if (_currentVideoId == null) return;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.5,   // ครึ่งจอตามที่ต้องการ
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => TriageSheetWidget(
        incidentId: _currentVideoId!,
        scrollController: scrollController,
      ),
    ),
  );
}
```

> **การจัดการ `_selectedTab == 1`**: หลังเปลี่ยนเป็น Bottom Sheet แล้ว case นี้ใน `_buildMainContent()` (บรรทัด ~812) จะไม่ถูกเรียกอีก → **ลบ `RelationshipViewWidget` และ import ทิ้ง** พร้อมลบไฟล์ `relationship_view_widget.dart`

> **ซ่อน Top Bar ขณะเปิด Triage Sheet**: เนื่องจาก tab เกี่ยวดองแสดงเนื้อหาเป็น `SizedBox.shrink()` แล้วเปิด `TriageSheetWidget` ครึ่งจอด้านหน้า ปุ่ม **Back (`FloatingBackButton`)** และ **ปุ่มควบคุมวิดีโอ (`GlassmorphismVideoControls`)** บน `emergency_live_page.dart` ต้องถูกซ่อนขณะ `_selectedTab == 1` เพื่อไม่ให้ผู้ใช้กดผิดขณะ focus กับรายการผู้ป่วย และเพื่อหลีกเลี่ยงปุ่มควบคุมวิดีโอลอยทับหน้า Triage Sheet โดยไม่จำเป็น
>
> ```dart
> // emergency_live_page.dart — Layer 3 (Top Bar)
> FloatingBackButton(
>   visible: _isUiVisible && _selectedTab != 2 && _selectedTab != 1 && !_isThaiMhungReporting,
>   onTap: () => Navigator.of(context).pop(),
> ),
> if (_isUiVisible && _selectedTab != 2 && _selectedTab != 1 && !_isThaiMhungReporting && _chewieController != null && !_isOverlayVisible) ...[
>   GlassmorphismVideoControls(
>     controller: _chewieController!.videoPlayerController,
>   ),
> ]
> ```

> **ซ่อน Floating "ข้อมูลสุขภาพ" ขณะเปิด Triage Sheet**: ในเหตุการณ์ที่มีผู้ป่วยฉุกเฉินหลายคน ปุ่ม Floating "ข้อมูลสุขภาพ" ระดับหน้าเหตุการณ์ (`FloatingActionButton.extended` ใน `emergency_live_page.dart` Layer 5) จะไม่ชัดว่าเปิดข้อมูลของผู้ป่วยคนใด จึงต้อง **ซ่อนขณะ `_selectedTab == 1`** และให้ผู้ใช้เข้าถึงข้อมูลสุขภาพรายบุคคลผ่าน **ปุ่ม "ดูข้อมูลสุขภาพ" ในแต่ละการ์ดผู้ป่วยใน `TriageSheetWidget`** แทน (ซึ่งมีอยู่แล้วใน `TriageVictimCard` ตามเงื่อนไข `victim.hasHealthData && (canTriage || canViewFull)`)
>
> ```dart
> // emergency_live_page.dart — Layer 5 (Floating Health Data Button)
> // เดิม: if (_isUiVisible && _currentResponseId != null && _isEmergencyHealthDataAvailable)
> // ใหม่: เพิ่ม _selectedTab != 1 เพื่อซ่อนขณะอยู่ในโหมดเกี่ยวดอง
> if (_isUiVisible && _currentResponseId != null && _isEmergencyHealthDataAvailable && _selectedTab != 1)
> ```

> **ซ่อน Dead Man Check-in chip ขณะเปิด Triage Sheet**: Dead Man Check-in chip เป็นกลไก Dead Man's Switch สำหรับ **ข้อมูลสุขภาพของตัวผู้ใช้เอง** (โหลดจาก `fetchCheckin(userId)`) ไม่เกี่ยวข้องกับผู้ป่วยในเหตุการณ์ จึงไม่จำเป็นต้องแสดงในโหมดเกี่ยวดองที่ผู้ใช้กำลังจัดการผู้ป่วยคนอื่น ต้อง **ซ่อนขณะ `_selectedTab == 1`**
>
> ```dart
> // emergency_live_page.dart — Dead Man Check-in chip
> // เดิม: if (_isUiVisible && _deadManCheckin?.isEnabled == true)
> // ใหม่: เพิ่ม _selectedTab != 1
> if (_isUiVisible && _deadManCheckin?.isEnabled == true && _selectedTab != 1)
> ```

> **ซ่อน Emergency Health Panic Overlay ขณะเปิด Triage Sheet**: Panic Overlay เป็นหน้าจอเต็มที่เตือน **เจ้าของข้อมูลสุขภาพ** ว่าข้อมูลของตัวเองกำลังจะถูกปลดล็อกอัตโนมัติ (counting → released) ไม่เกี่ยวข้องกับผู้ป่วยในเหตุการณ์ จึงไม่จำเป็นต้องแสดงในโหมดเกี่ยวดอง ต้อง **ซ่อนขณะ `_selectedTab == 1`**
>
> ```dart
> // emergency_live_page.dart — Emergency Health Panic Overlay
> // เดิม: if (_isEmergencyHealthPanicVisible && _emergencyHealthSession != null)
> // ใหม่: เพิ่ม _selectedTab != 1
> if (_isEmergencyHealthPanicVisible && _emergencyHealthSession != null && _selectedTab != 1)
> ```

**ป้ายเตือนบนปุ่ม**: หากมีผู้ประสบเหตุกลุ่มสีแดง ให้แสดง badge แดงกระพริบมุมขวาบนของปุ่ม "เกี่ยวดอง"

#### 12.8.2 Layout — `triage_sheet_widget.dart`

```text
╔═══════════════════════════════════════════════╗
║              ──── handle bar ────             ║  ← ลากปรับความสูงได้
║                                               ║
║  ผู้อยู่ในเหตุการณ์                    7 คน   ║
║  ┌─────┬─────┬─────┬─────┐                    ║
║  │🔴 2 │🟡 1 │🟢 3 │⚪ 1 │  ← กดกรองได้       ║
║  └─────┴─────┴─────┴─────┘                    ║
╠═══════════════════════════════════════════════╣
║  แบ่งกลุ่มตามความวิกฤต (แดง → เขียว)         ║
║  และเรียงภายในแต่ละกลุ่มตามเวลาแจ้งล่าสุด    ║
║  (ล่าสุดอยู่ด้านบนสุด)                         ║
║                                               ║
║  🔴 วิกฤต 2 คน                                 ║
║ ┌───────────────────────────────────────────┐ ║
║ │ 🔴 │ นาย สมชาย ใจดี              [เปลี่ยน]│ ║ ← จิตอาสา: ชื่อเต็ม
║ │    │ วิกฤต · หมดสติ ชีพจรเบา              │ ║   + note
║ │    │ ประเมินโดย พยาบาลวิชาชีพ · 14:32     │ ║
║ │    │ 💊 มีข้อมูลสุขภาพ  [ดู]              │ ║ ← ปลดล็อกแล้ว
║ └───────────────────────────────────────────┘ ║
║                                               ║
║  🟡 รีบด่วน 1 คน                               ║
║ ┌───────────────────────────────────────────┐ ║
║ │ 🟡 │ นางสาว ข                             │ ║ ← Viewer: ชื่อย่อ
║ │    │ รีบด่วน · ประเมินแล้ว 14:35          │ ║
║ └───────────────────────────────────────────┘ ║
║                                               ║
║  🟢 ไม่รีบด่วน 3 คน                            ║
║ ┌───────────────────────────────────────────┐ ║
║ │ 🟢 │ ด.ช. ง            ⚠️ ข้อมูลถูกโต้แย้ง│ ║ ← disputed
║ └───────────────────────────────────────────┘ ║
║                                               ║
║  ⚪ ยังไม่ประเมิน 1 คน                         ║
║ ┌───────────────────────────────────────────┐ ║
║ │ ⚪ │ นาย ค                                   ║ ← ค่าเริ่มต้น = ขาว
║ │    │ ยังไม่ประเมิน · แจ้งโดย ผู้ใช้ทั่วไป  │ ║
║ │    │ [⚫ ดำ] [🔴 แดง] [🟡 เหลือง] [🟢 เขียว]│ ║ ← เฉพาะผู้มีสิทธิ
║ └───────────────────────────────────────────┘ ║
╠═══════════════════════════════════════════════╣
║      [ ➕ แจ้งชื่อผู้อยู่ในเหตุการณ์ ]         ║ ← ทุกคนกดได้
╚═══════════════════════════════════════════════╝
```

**การแสดงผล**: แบ่งเป็นกลุ่มตามความวิกฤต (`critical` → `urgent` → `non_urgent` → `white`) และแสดงจำนวนสรุปของแต่ละกลุ่ม

**การจัดเรียงภายในกลุ่ม**: เรียงตามเวลาแจ้งรายชื่อ/อัปเดตล่าสุดแบบ `DESC` (รายการล่าสุดอยู่ด้านบนสุด)

**สถานะยังไม่ประเมิน**: ถ้า `triage_level='white'` และ `triaged_at IS NULL` ให้แสดงเป็น `⚪ ยังไม่ประเมิน` พร้อมชุดปุ่มเปลี่ยนระดับ 4 ปุ่มสำหรับผู้มีสิทธิ (`⚫ ดำ`, `🔴 แดง`, `🟡 เหลือง`, `🟢 เขียว`)

**Swipe Actions (เฉพาะจิตอาสา)**: ปัดซ้ายบนการ์ด → `[โต้แย้ง]` `[ลบ]`

#### 12.8.3 Dialog เพิ่มรายชื่อ

```text
┌─────────────────────────────────────┐
│  แจ้งชื่อผู้อยู่ในเหตุการณ์          │
├─────────────────────────────────────┤
│  คำนำหน้า  [ นาย        ▼]          │  ← dropdown: นาย/นาง/นางสาว/
│  ชื่อ       [_________________]      │     ด.ช./ด.ญ./ไม่ระบุ
│  นามสกุล    [_________________]      │
│                                     │
│  ℹ️ ผู้ชมทั่วไปจะเห็นเป็น "นาย ก"    │  ← preview แบบ real-time
│     เฉพาะทีมอาสาที่เข้าช่วยเหลือ     │
│     เท่านั้นที่เห็นชื่อเต็ม           │
│                                     │
│  ☑️ ข้าพเจ้ายืนยันว่าข้อมูลถูกต้อง   │  ← บังคับติ๊กก่อนส่ง (PDPA)
│     และยินยอมให้ใช้เพื่อการช่วยเหลือ │
│                                     │
│        [ยกเลิก]      [บันทึก]        │
└─────────────────────────────────────┘
```

> **PDPA Consent**: ต้องมี checkbox ยินยอมทุกครั้ง และบันทึกลง log ว่าใครเป็นผู้แจ้ง เวลาใด — เพราะเป็นการเปิดเผยข้อมูลส่วนบุคคลของ**บุคคลที่สาม**

#### 12.8.4 Inline Triage Action + Dialog เฉพาะเคสดำ (เฉพาะจิตอาสา)

**หลักการ UI**: การเปลี่ยน triage level ปกติให้ทำได้ **ทันทีจาก bottom sheet** โดยกดปุ่มสีของการ์ดนั้นเลย ไม่ต้องเปิด dialog เพิ่ม

**การบันทึก audit trail**: ทุกครั้งที่กดเปลี่ยนสี ระบบต้องบันทึก `triaged_by`, `triaged_at` และค่าเดิม/ค่าใหม่ลงตารางจริงเหมือนเดิม

**เคสดำ (`deceased`)**: ให้เปิด **dialog เฉพาะกรณีที่กด [เพิ่มหมายเหตุ]** เท่านั้น เพื่อบังคับให้ผู้ใช้ยืนยันเหตุผล/หมายเหตุเพิ่มเติมก่อนบันทึก

```text
┌──────────────────────────────────────────────┐
│  รายการเปลี่ยนระดับความวิกฤต                │
│  นาย สมชาย ใจดี                              │
├──────────────────────────────────────────────┤
│  [⚫ ดำ]   [🔴 แดง]   [🟡 เหลือง]   [🟢 เขียว] │  ← กดเปลี่ยนได้ทันที
│                                              │
│  ถ้าเลือก ⚫ ดำ → แสดงเฉพาะปุ่ม [เพิ่มหมายเหตุ] │
│  แล้วค่อยเปิด dialog สำหรับกรอกหมายเหตุ      │
│                                              │
│  [เพิ่มหมายเหตุ]                              │
└──────────────────────────────────────────────┘
```

**กรณีเปลี่ยนสีที่คนอื่นเคยประเมินไว้** → แสดงเตือนสั้นๆ ก่อนบันทึก:
> *"นาย ก ถูกประเมินเป็น 🔴 วิกฤต โดย พยาบาลวิชาชีพ เมื่อ 14:32 — การเปลี่ยนของคุณจะแทนที่ค่าเดิม"*

#### 12.8.5 Dialog โต้แย้งความถูกต้องของชื่อ (เฉพาะจิตอาสา)

> **Trigger**: ปัดซ้ายบนการ์ด → กด `[โต้แย้ง]` หรือกดที่ ⚠️ badge บนการ์ดที่ disputed แล้ว (เพื่อโต้แย้งเพิ่ม/แก้ไขเหตุผล)
> **สิทธิ์**: เฉพาะจิตอาสาที่ `status IN ('accepted','en_route','arrived')` ในเหตุการณ์นั้น

```text
┌─────────────────────────────────────────┐
│  ⚠️ โต้แย้งความถูกต้องของชื่อ             │
├─────────────────────────────────────────┤
│  ชื่อที่แจ้ง:  นาย สมชาย ใจดี            │  ← แสดงชื่อเต็ม (จิตอาสาเห็น)
│  แจ้งโดย:    ผู้ใช้ทั่วไป · 14:28       │
├─────────────────────────────────────────┤
│  เหตุผลที่โต้แย้ง (บังคับ ≥ 10 อักขระ)    │
│  ┌─────────────────────────────────┐    │
│  │ ชื่อ-สกุล ไม่ตรงกับบัตรประชาชน     │    │
│  │ ของผู้ประสบเหตุ ตัวจริงชื่อ...    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ℹ️ การโต้แย้งจะ:                        │
│     • ทำเครื่องหมาย ⚠️ บนการ์ด         │
│     • แจ้งเตือนทุกคนในห้อง              │
│     • ชื่อยังคงแสดง แต่มีสถานะ disputed │
│     • จิตอาสาสามารถแก้ไขชื่อได้หลัง     │
│       โต้แย้ง (แก้ไข → verify: confirmed)│
│                                         │
│        [ยกเลิก]      [โต้แย้ง]           │
└─────────────────────────────────────────┘
```

**หลังโต้แย้งแล้ว (Post-Dispute Flow):**

```text
โต้แย้ง (verify_status = 'disputed')
     │
     ├── จิตอาสาคนเดิม/คนอื่น → กด [แก้ไขชื่อ]
     │   → PATCH /api/victims/:id (first_name, last_name)
     │   → verify_status กลับเป็น 'confirmed' (อัตโนมัติ)
     │   → WebSocket: victim-name-updated + victim-disputed(resolved)
     │
     ├── จิตอาสา → กด [ลบ] (ถ้าชื่อเป็นคนละคน/ไม่เกี่ยวข้อง)
     │   → DELETE /api/victims/:id (soft delete + reason)
     │
     └── ไม่มีใครแก้ → ค้างเป็น disputed
         → ไม่ถูกลบโดย retention anonymizer (ยกเว้นเคสดำ)
         → รอจิตอาสาตัดสินใจ
```

> **สำคัญ**: เมื่อจิตอาสาแก้ไขชื่อหลังโต้แย้ง → `verify_status` เปลี่ยนกลับเป็น `confirmed` อัตโนมัติ (เพราะจิตอาสายืนยันว่าชื่อใหม่ถูกต้องแล้ว) ไม่ต้องมีปุ่มยืนยันแยก

---

### 12.9 Map Badge — สรุปสถานะเหนือหมุดเหตุการณ์

```text
                ┌─────────────────┐
                │ 🔴2  🟡1  🟢3   │  ← Custom Marker Widget
                └────────┬────────┘
                         ▼
                        📍  (หมุดเหตุการณ์เดิม)
```

**การ implement**: Google Maps ไม่รองรับ Widget เป็น Marker โดยตรง ต้องแปลงเป็น Bitmap

```dart
// lib/features/video/presentation/pages/utils/triage_badge_marker.dart
Future<BitmapDescriptor> buildTriageBadgeMarker(TriageSummary s) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // วาดกล่องพื้นหลัง + จุดสี + ตัวเลข
  // ...
  final img = await recorder.endRecording().toImage(width, height);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
}
```

**กฎการแสดงผล:**
- ซ่อน badge ทั้งหมดเมื่อ `total == 0`
- ซ่อนสีที่มีค่า `0` (เช่น มีแค่แดง 2 → แสดง `🔴2` อย่างเดียว)
- ไม่แสดง `white` บน map (ลด noise)
- **Cache Bitmap** ตาม key `"${c}-${u}-${n}"` เพื่อไม่ต้องวาดใหม่ทุก frame — สำคัญมากด้าน performance
- อัปเดตเมื่อได้รับ WebSocket `victim-triage-updated` เท่านั้น ไม่ poll

---

### 12.10 การเชื่อมกับ Emergency Health Data (Section 9)

> **เงื่อนไขปลดล็อก — ต้องครบ 3 ข้อพร้อมกัน:**

```text
┌──────────────────────────────────────────────────────────┐
│ ① ผู้ประสบเหตุเป็นผู้ใช้ในระบบ                            │
│    victim.linked_user_id IS NOT NULL                     │
│                          AND                             │
│ ② เจ้าตัวเปิด Auto-Release ไว้ล่วงหน้า + session released │
│    emergency_health_release_sessions.status = 'released'  │
│    AND user_id = victim.linked_user_id                   │
│    AND incident_id = victim.incident_id                  │
│                          AND                             │
│ ③ ถูกระบุสีโดยจิตอาสาแล้ว (ยืนยันตัวตนภาคสนาม)            │
│    victim.triaged_at IS NOT NULL                         │
│    AND victim.verify_status = 'confirmed'                │
└────────────────────────┬─────────────────────────────────┘
                         ▼
      health_data_consent_verified = TRUE
      health_data_unlocked_at = NOW()
                         ▼
      emit 'victim-health-unlocked' → เฉพาะ socket จิตอาสา
                         ▼
      แสดงปุ่ม [💊 ดูข้อมูลสุขภาพ] บนการ์ดผู้ประสบเหตุ
      → เปิด EmergencyHealthDataDialog เดิม (Section 9)
      → บันทึก health_data_access_logs ทุกครั้งที่เปิด
```

**การจับคู่ `linked_user_id`:**

| วิธี | ความแม่นยำ | หมายเหตุ |
|:---|:---|:---|
| จับคู่จากชื่อ-สกุลตรงกับ `users` | ⚠️ ต่ำ | ชื่อซ้ำได้ **ห้ามใช้เป็นวิธีเดียว** |
| จับคู่จาก `emergency_health_release_sessions` ที่ active ใน incident เดียวกัน | ✅ สูง | **แนะนำ** — เพราะ session ผูกกับ incident อยู่แล้ว |
| จิตอาสายืนยันด้วยตนเอง (เลือกจาก dropdown session ที่ released) | ✅ สูงสุด | เพิ่มขั้นตอน แต่ปลอดภัยสุด |

> **⚠️ ความเสี่ยงร้ายแรง**: หากจับคู่ผิดคน = **เปิดเผยข้อมูลสุขภาพของคนที่ไม่เกี่ยวข้อง**
> **แนะนำใช้วิธีที่ 2 + 3 ร่วมกัน** — ระบบเสนอรายชื่อ session ที่ released ใน incident นั้น แล้วให้จิตอาสากดยืนยันว่าเป็นคนเดียวกัน

---

### 12.11 Implementation Files

#### Database Migrations
```
supabase/migrations/
├── 20260809xxxxxx_create_incident_victims.sql          (ตารางหลัก + enum + index + retention_countdown_started_at)
├── 20260809xxxxxx_create_victim_triage_logs.sql        (history)
├── 20260809xxxxxx_create_update_victim_triage_fn.sql   (DB function + FOR UPDATE)
├── 20260809xxxxxx_create_victim_mutation_fns.sql       [ใหม่] insert/dispute/edit/delete functions
├── 20260809xxxxxx_create_victim_audit_tables.sql       [ใหม่] consent log + health data access log
└── 20260809xxxxxx_cloud_victims_encrypted.sql          (Cloud schema + pgcrypto)
```
> ต้องรัน migration เดียวกันทั้ง **Local PostgreSQL** และ **Supabase Cloud**

#### Backend (Node.js)
```
websocket-server/
├── routes/victims.js                          [ใหม่] REST endpoints ทั้ง 8 ตัว — ทุก route ที่ต้อง login ใช้ requireAuth (12.6)
├── services/victim-permission-service.js      [ใหม่] getVictimPermissions() — รับเฉพาะ req.userId ที่ verify แล้ว
├── services/victim-broadcast-service.js       [ใหม่] WebSocket broadcast + masking
├── services/victim-health-link-service.js     [ใหม่] ตรวจ 3 เงื่อนไขปลดล็อก
├── utils/victim-name-mask.js                  [ใหม่] maskVictimName()
├── jobs/victim-retention-countdown-starter.js [ใหม่] cron รายชั่วโมง — รัน SQL 3 ชั้นเพื่อเซ็ต `retention_countdown_started_at` (12.16.1)
├── jobs/victim-retention-anonymizer.js        [ใหม่] cron รายวัน — อ่าน victimRetentionDays แล้วลบ record ที่ครบกำหนด (12.16.1)
├── services/sync-service.js                   [แก้]  + syncVictimsToCloud()
└── server.js                                  [แก้]  + app.use('/api', victimsRouter) + start ทั้ง 2 victim cron jobs พร้อม graceful shutdown
```

#### Flutter
```
lib/features/video/
├── models/triage_models.dart                                    [ใหม่] IncidentVictim, TriageLevel, TriageSummary
├── data/repositories/victim_repository.dart                     [ใหม่] เรียก Local API
├── presentation/pages/widgets/triage_sheet_widget.dart          [ใหม่] Bottom Sheet ครึ่งจอ
├── presentation/pages/widgets/triage_victim_card.dart           [ใหม่] การ์ดรายคน + inline triage actions + swipe actions
├── presentation/pages/widgets/add_victim_dialog.dart            [ใหม่] ฟอร์มแจ้งชื่อ + consent
├── presentation/pages/utils/triage_badge_marker.dart            [ใหม่] วาด Bitmap สำหรับ Map
├── presentation/pages/widgets/bottom_tabs_widget.dart           [แก้]  ตัด !isEligibleResponder + badge
├── presentation/pages/emergency_live_page.dart                  [แก้]  _showTriageSheet() + subscribe events
├── presentation/pages/widgets/relationship_view_widget.dart     [ลบ]   แทนที่ด้วย Triage Sheet
└── services/websocket_service.dart                              [แก้]  + victimTriageStream
```

---

### 12.11.1 ⚠️ Pre-Implementation Checklist (ต้องทำก่อนเริ่ม Phase 1)

| # | รายการ | รายละเอียด | เหตุผล |
|:--|:---|:---|:---|
| 1 | **Seed `app_settings.video_system_config`** | ต้องมี row `key = 'video_system_config'` พร้อม default JSON `{"victimRetentionDays":0,"victimReportRateLimitPerIncident":0,"incidentRetentionMaxWaitHours":72}` ก่อน deploy migration ที่มี DB function อ่านค่านี้ (`insert_victim`, cron jobs) | ถ้าไม่มี row จะได้ `NULL` และ query `(value->>'x')::INT` อาจ error หรือ fallback ผิดพลาด |
| 2 | **Implement `utils/victim-name-mask.js` ก่อน DB functions** | ต้องมีฟังก์ชัน `maskVictimName(prefix, firstName, lastName)` ตาม algorithm ใน 12.2 (รองรับชื่อไทย/อังกฤษ + เติมลำดับเมื่อชื่อย่อซ้ำ) เพราะ `insert_victim()`/`edit_victim_name()` รับ `p_masked_name` เป็น parameter จาก Node ไม่ได้คำนวณเองใน SQL | DB function ไม่ได้ implement masking logic เอง — ต้องคำนวณฝั่ง Node ก่อนเรียก |
| 3 | **เติม Cloud Sync migration ฉบับเต็มก่อน Phase 8** | `12.3.3` มีแค่ตัวอย่าง column (`first_name_enc`, `last_name_enc`) ยังไม่มี `CREATE TABLE` เต็มสำหรับ Cloud — ต้องเขียน migration แยกที่มีคอลัมน์ครบเหมือน Local ยกเว้น `is_synced` (ตาม `VICTIM_LOCAL_ONLY_COLUMNS`) ก่อนรัน `syncVictimsToCloud()` | ถ้าข้าม Phase 8 ในรอบแรกสามารถเลื่อนข้อนี้ไปทำทีหลังได้ |

> **หมายเหตุ**: ถ้ายังไม่ implement Cloud Sync (Phase 8) ในรอบแรก สามารถข้ามข้อ 3 ไปก่อนได้ แต่ข้อ 1-2 **ต้องทำก่อน Phase 1** เพราะ DB function ใน migration แรกพึ่งพาโดยตรง

---

### 12.12 Implementation Phases (จัดเรียงตามลำดับความสำคัญ)

> **หลักการจัดลำดับ**: ระบบนี้เกี่ยวข้องกับความปลอดภัยชีวิต (life-safety) — จึงให้ความสำคัญกับ **แกนหลักที่ใช้งานได้จริงในภาคสนาม (P0)** ก่อน ตามด้วย **การประสานงานแบบ real-time (P1)** จากนั้นจึงเป็น **ส่วนเสริม/compliance (P2)** และปิดท้ายด้วย **การทดสอบยืนยัน (P3)**

#### 🔴 P0 — Critical Path (แกนหลักที่ต้องทำงานได้ก่อนใช้จริงในภาคสนาม)

| Phase | ขอบเขต | ผลลัพธ์ที่ตรวจสอบได้ |
|:---|:---|:---|
| **1. Database** | Migration ทั้งหมด (ตาราง + enum + DB functions + audit tables) | `\d incident_victims` แสดงครบ, เรียก `update_victim_triage()`/`insert_victim()` ได้ |
| **2. Backend Core** | `victim-name-mask.js` + `victim-permission-service.js` + `routes/victims.js` | `curl` ด้วย user 3 แบบ (viewer/responder/admin) ได้ผลต่างกันถูกต้อง — ปิด PDPA + BOLA |
| **3. Flutter Models + Repo** | `triage_models.dart` + `victim_repository.dart` | Unit test parse JSON ทั้ง masked/unmasked |
| **4. Flutter UI — อ่าน** | `triage_sheet_widget.dart` + `triage_victim_card.dart` + แก้ `bottom_tabs_widget.dart` | กดปุ่มเกี่ยวดอง → Sheet ขึ้นครึ่งจอ แสดงรายชื่อถูกต้อง |
| **5. Flutter UI — เขียน** | `add_victim_dialog.dart` + `triage_victim_card.dart` | Viewer เพิ่มชื่อได้, Responder เปลี่ยนระดับจาก bottom sheet ได้, Viewer ไม่เห็นปุ่มเปลี่ยนระดับ |

> เมื่อครบ P0 ระบบใช้งานได้จริงในภาคสนามแล้ว (เพิ่มชื่อ/คัดแยกสี/ดูรายชื่อ) แม้ยังไม่มี real-time sync — ผู้ใช้ต้อง refresh เองเพื่อดูข้อมูลล่าสุด

#### 🟠 P1 — Real-time & Field Coordination (สำคัญรองลงมา — ทีมภาคสนามต้องเห็นข้อมูลพร้อมกัน)

| Phase | ขอบเขต | ผลลัพธ์ที่ตรวจสอบได้ |
|:---|:---|:---|
| **6. Backend Realtime** | `victim-broadcast-service.js` + register events | เปิด 2 client ทดสอบ — ทั้งคู่เห็นสีเปลี่ยนพร้อมกัน และ viewer เห็นชื่อย่อ |
| **7. Map Badge** | `triage_badge_marker.dart` + integration | Badge ขึ้นเหนือหมุด + อัปเดต real-time + ไม่ค้าง frame |

#### 🟡 P2 — Compliance & Extended Integration (ทำได้หลัง core ใช้งานได้แล้ว)

| Phase | ขอบเขต | ผลลัพธ์ที่ตรวจสอบได้ |
|:---|:---|:---|
| **8. Cloud Sync** | `syncVictimsToCloud()` + pgcrypto | ปิดเน็ต → เพิ่มชื่อ → เปิดเน็ต → ข้อมูลขึ้น Cloud แบบเข้ารหัส |
| **9. Health Data Link** | `victim-health-link-service.js` + UI ปุ่มดูข้อมูล | ครบ 3 เงื่อนไข → ปุ่มขึ้น, ขาดข้อใดข้อหนึ่ง → ปุ่มไม่ขึ้น |

> ทั้งสอง Phase นี้ไม่บล็อกการใช้งานคัดแยกหลัก — เลื่อนไปทำหลัง P0/P1 เสร็จสมบูรณ์ได้โดยไม่กระทบภาคสนาม

#### 🟢 P3 — Validation (ทำคู่ขนานตลอด แต่เป็น gate สุดท้ายก่อน Production)

| Phase | ขอบเขต | ผลลัพธ์ที่ตรวจสอบได้ |
|:---|:---|:---|
| **10. E2E Test** | Maestro flow + PDPA Checklist | ดู 12.14 — ต้องผ่านครบก่อนเปิดใช้งานจริง |

---

### 12.13 Risk Analysis

| # | ความเสี่ยง | ผลกระทบ | แนวทางป้องกัน |
|:--|:---|:---|:---|
| 1 | **ชื่อเต็มรั่วผ่าน WebSocket broadcast** | 🔴 ละเมิด PDPA | Broadcast ส่ง masked เสมอ, ชื่อเต็มยิงตรงเฉพาะ socket ที่ตรวจสิทธิแล้ว (12.7) |
| 2 | **จับคู่ Health Data ผิดคน** | 🔴 เปิดเผยข้อมูลสุขภาพผู้อื่น | ใช้ session-based matching + จิตอาสายืนยันด้วยตนเอง (12.10) |
| 3 | **แจ้งชื่อมั่ว / กลั่นแกล้ง** | 🟡 ข้อมูลปลอมในระบบ | จิตอาสา Dispute/ลบได้, บันทึก `reported_by` ทุก record, Rate Limit **อ่านจากตารางจริง** (`app_settings.video_system_config.victimReportRateLimitPerIncident`) — default `0` = ยังไม่กำหนด (ดู 12.16) |
| 4 | **Last-write-wins ทำให้สีวิกฤตถูกลดโดยพลการ** | 🟠 ผู้ป่วยวิกฤตถูกมองข้าม | เก็บ history 100% + แสดง dialog เตือนก่อนเปลี่ยน + System Message ใน Live Chat เมื่อลดระดับจากแดง |
| 5 | **De-anonymization จากชื่อย่อ** | 🟡 เดาตัวตนได้ | เติมลำดับเมื่อชื่อย่อซ้ำ (12.2) + ไม่แสดงนามสกุลย่อเลย |
| 6 | **Race condition — 2 จิตอาสาระบุสีพร้อมกัน** | 🟡 log ไม่ครบ | `SELECT ... FOR UPDATE` ใน DB function (12.6) |
| 7 | **Cloud Sync พังเพราะ schema mismatch** | 🟠 ข้อมูลไม่ขึ้น Cloud | กำหนด `VICTIM_LOCAL_ONLY_COLUMNS` ตั้งแต่แรก + ตรวจก่อนเพิ่ม column ใหม่ (บทเรียน Section 11) |
| 8 | **จิตอาสาออกจากเหตุการณ์แต่ยังเห็นชื่อเต็ม** | 🟡 สิทธิค้าง | ตรวจสิทธิ**ทุก request** ไม่ cache ฝั่ง Client — เมื่อ status เปลี่ยนเป็น `completed`/`cancelled` ให้ตัดสิทธิทันที |
| 9 | **Map Badge วาด Bitmap ทุก frame** | 🟡 แอปกระตุก | Cache BitmapDescriptor ตาม summary key (12.9) |
| 10 | **FK ชี้ `auth.users`** | 🔴 บันทึกไม่ได้เลย | ใช้ `REFERENCES users(id)` เสมอ (กฎ Section 11.5) |
| 11 | **ผู้กรอกลบชื่อตัวเองหลังจิตอาสาประเมินแล้ว** | 🟠 ข้อมูลภาคสนามหาย | Edit Lock บังคับที่ Backend ไม่ใช่แค่ซ่อนปุ่ม (12.5) |
| 12 | **ข้อมูลผู้ป่วยค้างในระบบหลังเหตุการณ์จบ (รวมชื่อที่ถูกแจ้งมั่ว/ไม่มีจิตอาสาระบุสี)** | 🟠 เก็บข้อมูลเกินจำเป็น (PDPA) | Retention Countdown เริ่มนับเมื่อ**เหตุการณ์จบ** (ไม่ใช่ตอนสร้าง record) โดยไม่สนว่าถูกประเมินสีแล้วหรือไม่ — อ่านจำนวนวันจากตารางจริง (`app_settings.video_system_config.victimRetentionDays`) แล้วลบทิ้งอัตโนมัติเมื่อครบกำหนด (ดู 12.16) |

---

### 12.14 Testing Plan

**Backend (curl / integration):**
> **หมายเหตุ**: `X-User-Id` ใน curl ด้านล่างต้องเป็น ID ของ user ที่ **มีอยู่จริงและ `is_active = TRUE`** ในตาราง `users` เท่านั้น — เพราะ `verifyToken` middleware จะ query DB จริงเพื่อยืนยันก่อนเซ็ต `req.userId` (เหมือน endpoint อื่นในระบบ) การส่ง ID ปลอมที่ไม่มีในตารางจะได้ `401 Unauthorized` ทันที ไม่ใช่การ "เชื่อ header" ตรงๆ แบบที่ `01_broken_object_level_authorization.md` เตือน
```bash
# 0. ทดสอบว่า verifyToken ปฏิเสธ ID ที่ไม่มีในตาราง users จริง
curl -H "X-User-Id: 00000000-0000-0000-0000-000000000000" \
  http://localhost:3000/api/incidents/$INCIDENT_ID/victims
# คาดหวัง: 401 Unauthorized (ไม่ใช่การเชื่อ header เปล่าๆ)

# 1. Viewer ทั่วไป — ต้องได้ชื่อย่อเท่านั้น
curl -H "X-User-Id: $VIEWER_ID" \
  http://localhost:3000/api/incidents/$INCIDENT_ID/victims | jq '.victims[0]'
# คาดหวัง: firstName = null, isMasked = true, displayName = "นาย ก"

# 2. Responder — ต้องได้ชื่อเต็ม
curl -H "X-User-Id: $RESPONDER_ID" \
  http://localhost:3000/api/incidents/$INCIDENT_ID/victims | jq '.victims[0]'
# คาดหวัง: firstName = "สมชาย", isMasked = false

# 3. Viewer พยายามระบุสี — ต้องถูกปฏิเสธ
curl -X PATCH -H "X-User-Id: $VIEWER_ID" -H "Content-Type: application/json" \
  -d '{"triageLevel":"critical"}' \
  http://localhost:3000/api/victims/$VICTIM_ID/triage
# คาดหวัง: 403 Forbidden

# 4. Object-level check (BOLA) — พยายามส่ง userId อื่นทาง body เพื่อสวมรอย ต้องไม่มีผล
curl -X PATCH -H "X-User-Id: $VIEWER_ID" -H "Content-Type: application/json" \
  -d '{"userId":"'$ADMIN_ID'","triageLevel":"critical"}' \
  http://localhost:3000/api/victims/$VICTIM_ID/triage
# คาดหวัง: 403 Forbidden เหมือนเดิม — พิสูจน์ว่า route ใช้ req.userId ไม่ใช่ req.body.userId

# 5. ตรวจ history หลังเปลี่ยนสี 2 ครั้ง
psql -c "SELECT from_level, to_level, changed_by_role FROM incident_victim_triage_logs
         WHERE victim_id = '$VICTIM_ID' ORDER BY created_at;"
# คาดหวัง: 2 แถว
```

**Maestro E2E** — `tests/maestro/scenario_triage.yaml`
1. Login เป็น Viewer → เปิดเหตุการณ์ → กด "เกี่ยวดอง" → Sheet ขึ้นครึ่งจอ
2. กด "แจ้งชื่อ" → กรอก `นาย/สมชาย/ใจดี` → ติ๊ก consent → บันทึก
3. `assertVisible: "นาย ก"` และ `assertNotVisible: "สมชาย"` ← **ทดสอบ PDPA**
4. `assertNotVisible: "ระบุกลุ่ม"` ← Viewer ไม่มีสิทธิระบุสี
5. Login เป็น Responder ที่ accepted → เปิดเหตุการณ์เดียวกัน → กด "เกี่ยวดอง"
6. `assertVisible: "นาย สมชาย ใจดี"` ← เห็นชื่อเต็ม
7. กด "ระบุกลุ่ม" → เลือก 🔴 วิกฤต → ยืนยัน
8. `assertVisible: "วิกฤต"` + กลับไปที่จอ Viewer → `assertVisible: "🔴 1"` ← real-time

**PDPA Checklist (ต้องผ่านครบก่อน Production):**
- [ ] ดัก Network Response ด้วย Charles/mitmproxy ในฐานะ Viewer → **ต้องไม่พบชื่อเต็มใน payload ใดๆ**
- [ ] ดัก WebSocket frame ในฐานะ Viewer → **ต้องไม่พบชื่อเต็ม**
- [ ] มี consent checkbox ก่อนบันทึกทุกครั้ง
- [ ] มี audit log ครบทุกการเข้าถึงข้อมูลสุขภาพ
- [ ] ตั้งค่า `victimRetentionDays` > 0 ที่หน้า Video System Admin (ดู 12.16) และ anonymize job ทำงานจริง
- [ ] ตั้งค่า `victimReportRateLimitPerIncident` > 0 ที่หน้า Video System Admin (ดู 12.16)

---

### 12.15 ประเด็นที่ยืนยันแล้ว (Resolved — 2026-08-09)

| # | ประเด็น | ข้อสรุปที่ยืนยัน |
|:--|:---|:---|
| 1 | ผู้กรอกเห็นชื่อเต็มหรือไม่ | ✅ **เห็นชื่อเต็มเฉพาะ record ที่ตนเองกรอก** (per-row check ที่ Backend — 12.4) |
| 2 | Reporter ผู้ถ่ายวิดีโอไม่เห็นชื่อเต็ม | ✅ **ถูกต้อง** — เว้นเมื่อเขาเป็นจิตอาสาในเหตุการณ์นั้นด้วย |
| 3 | ทางเลือก Cloud Sync | ✅ **เลือก C (pgcrypto)** — ยืนยันแล้วว่าไม่มีค่าใช้จ่ายเพิ่ม และไม่ขัดกับ `docs/secure` (ดู 12.15.1) |
| 4 | Retention Policy | ✅ **default ยังไม่กำหนดวัน** (`victimRetentionDays = 0` = ปิด) — Admin กำหนดเองที่ Video System Admin, **ดึงค่าจากตารางจริง** `app_settings` (12.16) |
| 5 | Rate Limit การแจ้งชื่อ | ✅ **default ยังไม่กำหนด** (`victimReportRateLimitPerIncident = 0` = ไม่จำกัด) — Admin กำหนดเอง, **ดึงค่าจากตารางจริง** `app_settings` (12.16) |
| 6 | Schema จริงของ `incident_responses` / admin flag | ⏳ ยังต้อง verify ก่อนเขียนโค้ด (หมายเหตุใน 12.4) |
| 7 | Default Triage Level | ✅ **⚪ ขาว (`white`)** — ผู้ป่วยทั่วไป/ยังไม่ประเมิน — ยกเลิกสีเทา/`unassessed` (12.1) |

#### 12.15.1 การตรวจทางเลือก C (pgcrypto) — ค่าใช้จ่าย + ความสอดคล้องกับ `docs/secure`

| หัวข้อตรวจ | ผล |
|:---|:---|
| **ค่าใช้จ่ายเพิ่ม** | ✅ **ไม่มี** — `pgcrypto` เป็น extension มาตรฐานที่มากับ PostgreSQL/Supabase อยู่แล้ว ไม่ต้องชื้อ KMS/HSM ภายนอก |
| **ขัดกับ `07_secret_management.md`?** | ✅ **ไม่ขัด — แต่เพิ่มหน้าที่** ตาม K4/K6: key ต้องอยู่ใน `.env` ของ `websocket-server` เท่านั้น + เพิ่มใน `.env.example` + เพิ่มใน `secret_rotation_runbook.md` |
| **ขัดกับ `12_least_privilege.md`?** | ✅ ไม่ขัด — การถอดรหัสทำที่ server เท่านั้น Client (Flutter) **ไม่เคยมี key** |
| **ข้อห้ามเด็ดขาด** | ❌ ห้าม hardcode key ใน SQL/migration, ห้ามส่ง key มาที่ Client, ห้าม log ค่าที่ decrypt แล้ว (ตาม `05_logging_audit_monitoring.md`) |

**งานที่เพิ่มจากการเลือก C:**
- เพิ่ม `VICTIM_NAME_ENC_KEY` ใน `websocket-server/.env` + `.env.example`
- Sync service เข้ารหัสก่อนส่งขึ้น Cloud (`pgp_sym_encrypt`) — Cloud เก็บ `BYTEA`
- เพิ่มขั้นตอน rotation ของ key นี้ใน `docs/secure/secret_rotation_runbook.md`

#### 12.15.2 Identity Chain — ความสอดคล้องกับ `auth_data_guidelines.md` (ปิด conflict ทางอ้อม)

> **ปัญหาเดิม**: แผนนี้ระบุแค่ "ตรวจ `userId`" โดยไม่ได้บอกว่า `userId` มาจากไหน ทำให้ดูเหมือนตัดตอนจาก custom AuthService ไปเชื่อ header ตรงๆ ซึ่งขัดกับหลักการของ `auth_data_guidelines.md` (ห้ามใช้ `Supabase.instance.client.auth.currentUser`, ต้องใช้ session จาก custom AuthService เท่านั้น)

**Chain ที่ถูกต้อง (สอดคล้องกับรูปแบบที่ `watermark_repository.dart`/`consultation_repository.dart` ใช้อยู่แล้ว):**

```text
1. Flutter: ServiceLocator.instance.currentUser?.id
   (มาจาก custom AuthService session — ไม่ใช่ Supabase.instance.client.auth.currentUser)
                         ▼
2. Flutter: ส่ง header 'x-user-id': userId ไปกับทุก request ของ victim_repository.dart
                         ▼
3. Backend: verifyToken(pool) middleware — query ตาราง users จริง
   ตรวจ id มีอยู่จริง + is_active = TRUE → เซ็ต req.userId (เชื่อถือได้)
                         ▼
4. Route handler: ใช้ req.userId เท่านั้น (ไม่ใช่ req.body.userId/req.query.userId)
   → ส่งเข้า getVictimPermissions(req.userId, incidentId)
```

> **สรุป**: เมื่อ implement ตามข้อ 12.4/12.6 ที่แก้ไขแล้ว (ใช้ `requireAuth` + `req.userId`) แผนนี้จะสอดคล้องกับ `auth_data_guidelines.md` ทันที เพราะ identity ที่ backend เห็นย้อนกลับไปหา custom AuthService session ได้เสมอ ไม่มีจุดใดที่ client ควบคุม `userId` ที่ใช้ authorization ได้โดยตรง

---

### 12.16 Admin Configuration — Retention & Rate Limit (ตารางจริง)

> **หน้าจอ**: `Video System Admin` — `lib/features/admin/presentation/pages/video_admin_page.dart`
> **ที่เก็บ**: `app_settings` (key = `video_system_config`, JSONB) — ตารางจริงที่มีอยู่แล้ว
> **ตัวอ่านค่า**: `SyncConfig.loadFromSupabase()` ใน `main()` → ใช้ค่าจากตารางเสมอ ไม่ hardcode

| Field (JSONB) | หน้าจอ Admin | Default | ความหมายของ `0` |
|:---|:---|:---:|:---|
| `victimRetentionDays` | ระยะเก็บชื่อผู้ประสบเหตุหลังเริ่มนับถอยหลัง (วัน) | `0` | **ยังไม่กำหนด** — ไม่รัน anonymize job |
| `victimReportRateLimitPerIncident` | จำกัดจำนวนการแจ้งชื่อ/คน/เหตุการณ์ | `0` | **ไม่จำกัด** — ข้ามการตรวจ rate limit |
| `incidentRetentionMaxWaitHours` | รอสูงสุดกี่ชม. ก่อนเริ่มนับถอยหลัง (แม้จิตอาสาไม่ครบ) | `72` | **ไม่จำกัดเวลารอ** — รอจนกว่าจิตอาสาจะครบตามอาชีพที่กำหนด |

```text
┌─ Victim & PDPA Controls ──────────────────────────────┐
│ ระยะเก็บชื่อผู้ประสบเหตุหลังเริ่มนับถอยหลัง (วัน)        │
│ [ 0                                              ]      │
│ 0 = ยังไม่กำหนด (ไม่ลบ/anonymize อัตโนมัติ)              │
├──────────────────────────────────────────────────────┤
│ จำกัดการแจ้งชื่อ/คน/เหตุการณ์                          │
│ [ 0                                              ]      │
│ 0 = ไม่จำกัด                                          │
├──────────────────────────────────────────────────────┤
│ รอสูงสุดกี่ชม. ก่อนเริ่มนับถอยหลัง (แม้จิตอาสาไม่ครบ)    │
│ [ 72                                             ]      │
│ 0 = รอจนกว่าจิตอาสาจะครบตามอาชีพที่กำหนด                │
└──────────────────────────────────────────────────────┘
           [ บันทึกการตั้งค่า (Apply Now) ]
```

#### 12.16.1 กลไก Retention Countdown — รวมชื่อที่ถูกแจ้งมั่ว/ไม่มีจิตอาสาระบุสี

> **เป้าหมาย**: แม้มีคนแจ้งชื่อมั่วๆ (ไม่ผ่าน rate limit เพราะยังตั้งเป็น `0`, หรือแจ้งจริงแต่ไม่มีจิตอาสาเข้ามาระบุสีให้เลย) ข้อมูลนั้นต้อง**ไม่ค้างอยู่ในระบบตลอดไป** — ต้องเริ่มนับถอยหลังทันทีที่เหตุการณ์พร้อมปิด ไม่ว่าจะถูกประเมินสีหรือไม่

> **แนวทางที่เลือก: ใช้ `donation_categories.volunteer_profession_ids` + `incident_responses` (ใช้ตารางจริงที่มีอยู่แล้ว)**
> ผู้ใช้สร้าง UI และตารางสำหรับระบุอาชีพที่เข้าร่วมเหตุการณ์แต่ละประเภทไว้แล้ว (`donation_categories.volunteer_profession_ids` — แก้ไขได้ที่หน้า Donation Admin) จึงไม่ต้องเพิ่ม column ใหม่บน `videos`
> โครงสร้างที่ใช้:
> - `videos.category_id` → `donation_categories.id` (หมวดหมู่เหตุการณ์)
> - `donation_categories.volunteer_profession_ids` (TEXT[]) — อาชีพที่กำหนดให้เหตุการณ์ประเภทนี้
> - `incident_responses.volunteer_id` + `status` IN ('accepted','en_route','arrived') — จิตอาสาที่รับงาน
> - `user_group_roles.user_id` → `profession_id` — อาชีพของจิตอาสาแต่ละคน

**3 ชั้นการเริ่มนับ (เรียงตามลำดับการทำงาน):**

```text
┌─────────────────────────────────────────────────────────────┐
│ ชั้นที่ 1 (หลัก): จิตอาสาครบตามอาชีพที่กำหนด                  │
│ เมื่อ: ทุก profession_id ใน volunteer_profession_ids          │
│       มี ≥1 responder ที่ status IN ('accepted','en_route',  │
│       'arrived') ใน incident_responses                       │
│ → SET retention_countdown_started_at = NOW()                │
├─────────────────────────────────────────────────────────────┤
│ ชั้นที่ 2 (สำรอง): หมวดหมู่ไม่กำหนดอาชีพ                      │
│ เมื่อ: volunteer_profession_ids = '{}' (ว่าง)                 │
│ → เริ่มนับทันทีเมื่อมี responder แรก accept (≥1 คน)            │
├─────────────────────────────────────────────────────────────┤
│ ชั้นที่ 3 (สำรองสูงสุด): รอเกิน 72 ชั่วโมง                    │
│ เมื่อ: NOW() - videos.created_at >= 72 ชม.                   │
│ → เริ่มนับไม่ว่าจิตอาสาจะครบหรือไม่ (กันข้อมูลค้างตลอดไป)       │
│ → ค่า 72 ชม. อ่านจาก app_settings.video_system_config       │
│    .incidentRetentionMaxWaitHours (default 72)              │
└─────────────────────────────────────────────────────────────┘
                         ▼
   Cron job (ทุกชั่วโมง) ตรวจเงื่อนไขข้างต้น:
   ถ้า retention_countdown_started_at IS NULL และเข้าเงื่อนไข → SET NOW()
                         ▼
   Cron job (ทุกวัน) อ่าน victimRetentionDays จาก app_settings:
      ถ้า victimRetentionDays = 0  → skip (ยังไม่กำหนด)
      ถ้า victimRetentionDays > 0  →
        anonymize record ที่ครบกำหนด (null-out PII): SET first_name=NULL, last_name=NULL,
          masked_name='(ไม่ระบุตัวตน)', disputed_reason=NULL, deleted_reason=NULL
          WHERE retention_countdown_started_at <= NOW() - (victimRetentionDays || ' days')::interval
            AND is_deleted = FALSE
            AND triage_level <> 'deceased'
            AND verify_status <> 'disputed'
```

```sql
-- websocket-server/migrations: ไม่ต้องเพิ่ม column ใหม่บน videos — ใช้ category_id ที่มีอยู่
-- ต้องเพิ่มเฉพาะ retention_countdown_started_at บน incident_victims (อยู่ใน 12.3.1 แล้ว)

-- Cron job ตรวจเงื่อนไขการเริ่มนับ (รันทุกชั่วโมง):
-- websocket-server/jobs/victim-retention-countdown-starter.js

-- ตัวอย่าง SQL ที่ cron job รัน:
-- ชั้นที่ 1: ครบตามอาชีพ
UPDATE incident_victims v
SET retention_countdown_started_at = NOW()
WHERE v.is_deleted = FALSE
  AND v.retention_countdown_started_at IS NULL
  AND EXISTS (
    -- ทุก profession_id ใน volunteer_profession_ids มี ≥1 responder รับแล้ว
    SELECT 1 FROM videos vid
    JOIN donation_categories dc ON dc.id::text = vid.category_id::text
    WHERE vid.id = v.incident_id
      AND dc.volunteer_profession_ids <> '{}'
      AND NOT EXISTS (
        SELECT 1 FROM unnest(dc.volunteer_profession_ids) AS required_pid
        WHERE NOT EXISTS (
          SELECT 1 FROM incident_responses ir
          JOIN user_group_roles ugr ON ugr.user_id = ir.volunteer_id
          WHERE ir.video_id = vid.id
            AND ir.status IN ('accepted','en_route','arrived')
            AND ugr.profession_id::text = required_pid
        )
      )
  );

-- ชั้นที่ 2: หมวดหมู่ไม่กำหนดอาชีพ → มี ≥1 responder รับ
UPDATE incident_victims v
SET retention_countdown_started_at = NOW()
WHERE v.is_deleted = FALSE
  AND v.retention_countdown_started_at IS NULL
  AND EXISTS (
    SELECT 1 FROM videos vid
    JOIN donation_categories dc ON dc.id::text = vid.category_id::text
    WHERE vid.id = v.incident_id
      AND (dc.volunteer_profession_ids = '{}' OR dc.volunteer_profession_ids IS NULL)
      AND EXISTS (
        SELECT 1 FROM incident_responses ir
        WHERE ir.video_id = vid.id
          AND ir.status IN ('accepted','en_route','arrived')
      )
  );

-- ชั้นที่ 3: รอเกิน max wait hours (ค่าจาก app_settings — default 72)
-- ถ้า incidentRetentionMaxWaitHours = 0 → ข้ามชั้นนี้ทั้งหมด (รอจนกว่าจิตอาสาจะครบ)
-- ตัวอย่าง: maxWaitHours = 72
UPDATE incident_victims v
SET retention_countdown_started_at = NOW()
WHERE v.is_deleted = FALSE
  AND v.retention_countdown_started_at IS NULL
  AND EXISTS (
    SELECT 1 FROM videos vid
    WHERE vid.id = v.incident_id
      AND vid.created_at <= NOW() - make_interval(hours => $1)  -- $1 = maxWaitHours (72)
  );
```

> **⚠️ กรณีเคสดำ (deceased)**: ไม่ลบตาม retention ปกติ — ต้องเก็บถาวรเพื่อการตรวจสอบทางกฎหมาย (ยกเว้นจาก anonymize job เสมอ ไม่ว่า `victimRetentionDays` จะเป็นเท่าไร)
> **กรณี Dispute ค้าง**: record ที่ `verify_status = 'disputed'` ให้เก็บไว้จนกว่าจิตอาสาจะตัดสินใจ — ไม่ถูกลบทั้งที่มีข้อพิพาทค้าง

**งานที่ต้องเพิ่ม (ต่อยอดของเดิม):**

| ไฟล์ | สิ่งที่เพิ่ม |
|:---|:---|
| `lib/config/sync_config.dart` | 3 static fields: `victimRetentionDays`, `victimReportRateLimitPerIncident`, `incidentRetentionMaxWaitHours` (default 72) + อ่าน/เขียนใน `loadFromSupabase()` / `saveToSupabase()` |
| `lib/features/admin/presentation/pages/video_admin_page.dart` | เพิ่ม section "Victim & PDPA Controls" 3 ช่อง (เพิ่ม max wait hours) |
| `websocket-server` (victim report endpoint) | อ่าน `victimReportRateLimitPerIncident` จาก `app_settings` → ข้ามตรวจ rate limit เมื่อค่าเป็น `0` |
| `websocket-server/jobs/victim-retention-countdown-starter.js` | [ใหม่] cron รายชั่วโมง — รัน SQL 3 ชั้นเพื่อเซ็ต `retention_countdown_started_at` |
| `websocket-server/jobs/victim-retention-anonymizer.js` | [ใหม่] cron รายวัน — อ่าน `victimRetentionDays` แล้ว **anonymize** record ที่ครบกำหนด (null-out PII) ยกเว้น `triage_level = 'deceased'` และ `verify_status = 'disputed'` |
| `websocket-server/server.js` | [แก้] start ทั้ง 2 cron jobs พร้อม graceful shutdown |
| `supabase/migrations/` | เพิ่ม `retention_countdown_started_at` column + index บน `incident_victims` (อยู่ใน 12.3.1 แล้ว) — **ไม่ต้องเพิ่ม column บน `videos`** |

```sql
-- SQL ตัวอย่างที cron job รัน (anonymization)
UPDATE incident_victims
SET first_name      = NULL,
    last_name       = NULL,
    masked_name     = '(ไม่ระบุตัวตน)',
    disputed_reason = NULL,
    deleted_reason  = NULL,
    is_synced       = FALSE,
    updated_at      = NOW()
WHERE is_deleted = FALSE
  AND triage_level <> 'deceased'
  AND verify_status <> 'disputed'
  AND retention_countdown_started_at <= NOW() - (victimRetentionDays || ' days')::interval;
```

> **หมายเหตุ**: ล้าง `disputed_reason`/`deleted_reason` ด้วยเพราะอาจมีชื่อเต็มในข้อความอิสระ (PDPA)

---

#### 12.16.2 กลไก Rate Limit — การแจ้งชื่อ/คน/เหตุการณ์

หลักการที่เลือก: **SQL COUNT แบบ per-incident + per-reporter** (ทางเลือก A) — ไม่ใช้ Redis time-window เพราะ quota นี้คือ "จำนวนครั้งทั้งหมดต่อเหตุการณ์" ไม่รีเซ็ต

```sql
-- ตรวจก่อน insert ใน `insert_victim()`
SELECT COUNT(*) INTO v_count
FROM incident_victims
WHERE incident_id = p_incident_id
  AND reported_by = p_reported_by
  AND is_deleted = FALSE;

IF v_limit > 0 AND v_count >= v_limit THEN
    RAISE EXCEPTION 'VICTIM_REPORT_RATE_LIMIT_EXCEEDED';
END IF;
```

Flow ใน `POST /api/incidents/:incidentId/victims`:
1. อ่าน `victimReportRateLimitPerIncident` จาก `app_settings.video_system_config` (default `0`)
2. ถ้าค่า = `0` → ข้ามตรวจ
3. ถ้าค่า > `0` → query count ตาม SQL ข้างบน
4. ถ้าเกิา → ตอบ `429 Too Many Requests`

> **⚠️ ก่อน Production**: ค่า `0` ทั้งสองตัว**ขัดกับ**แผน `03_rate_limiting_resource_exhaustion.md` และ PDPA data minimization
> → ต้องตั้งค่าจริงที่หน้า Admin ก่อนเปิดใช้จริง (ค่าที่แนะนำเป็นจุดตั้งต้น: retention 90 วัน, rate limit 5 ชื่อ, max wait 72 ชม.)
> **แต่** cron job เริ่มนับถอยหลังทำงานเสมอไม่ว่าตั้งค่า Admin หรือยัง — เพียงแค่ยังไม่มีการ anonymize จริงจนกว่า `victimRetentionDays > 0`

---

## 13. Runbook: การ์ดวีดีโอไม่โหลดบนอุปกรณ์ Android

### 13.1 สาเหตุ

เมื่อ Flutter app พยายามดึงรายการวิดีโอฉุกเฉิน (`VideoRepository.getEmergencyVideos`) จะลองเรียก Local API (`AppConfig.localApiUrl`) ก่อน แล้วค่อย fallback ไป Supabase ถ้า Local API timeout หรือ error

ในกรณีทีพบปัญหา ค่า `mainMachineIp` ของ Flutter (`lib/config/app_config.dart`) ชี้ไปที่ `172.20.10.13:8080` ซึ่งผ่าน **Caddy reverse proxy** บน port 8080 ไปยัง **websocket-server** บน `localhost:3000` แต่ websocket-server ดังกล่าวไม่ได้รันอยู่ ทำให้ Caddy ตอบ **502 Bad Gateway** แอปจึง timeout แล้ว fallback ไป Supabase แต่ข้อมูล emergency video ไม่ปรากฏในรูปแบบทีต้องการ

### 13.2 อาการ

- หน้าเหตุการณ์/การ์ดวีดีโอไม่โหลด/ไม่แสดงบน Android
- Logcat แสดง `VideoRepository: Local emergency list failed - TimeoutException after 0:00:10.000000`
- `curl http://<mainMachineIp>:8080/api/videos` หรือ `/api/videos/emergency/list` ตอบ `HTTP 502 Bad Gateway`

### 13.3 วิธีแก้ไข

1. ตรวจสอบว่า `websocket-server` รันอยู่บน `localhost:3000`:
   ```bash
   lsof -nP -iTCP:3000 -sTCP:LISTEN
   ```
2. ถ้าไม่มี process ฟัง port 3000 ให้รันใหม่:
   ```bash
   cd /Users/dave_macmini/sheserved/websocket-server
   node server.js
   ```
3. ตรวจสอบ Caddy รันอยู่บน port 8080 และ reverse proxy ไป `localhost:3000`:
   ```bash
   lsof -nP -iTCP:8080 -sTCP:LISTEN
   ```
4. ตรวจสอบ `AppConfig.mainMachineIp` ใน `lib/config/app_config.dart` ให้ตรงกับ IP ที `websocket-server` แจ้งตอน start เช่น `172.20.10.13:8080`
5. ทดสอบ endpoint ผ่าน Caddy:
   ```bash
   curl "http://172.20.10.13:8080/api/videos/emergency/list?page=1&limit=20"
   ```
6. ถ้า API ตอบ 200 พร้อมข้อมูล ให้ hot-restart หรือ pull-to-refresh แอป Android เพื่อให้ `VideoRepository` ดึงข้อมูลจาก Local API ใหม่อีกครั้ง

### 13.4 บทเรียน

- Local API เป้น fast-path หลักสำหรับ Video System; ถ้า backend ล้ม การ์ดวีดีโอจะไม่แสดงแม้ Supabase ยังทำงาน
- ควรตรวจสอบ `lsof` ทั้ง `localhost:3000` และ `:8080` ก่อนรัน Maestro หรือ demo video system
- หาก IP ของเครื่องหลักเปลี่ยน (e.g. เปลี่ยน Wi-Fi) ต้องอัปเดต `mainMachineIp` ใน `lib/config/app_config.dart` ให้ตรง

## 14. Runbook: ไม่สามารถเพิ่มอาชีพใหม่ (Admin → เพิ่มอาชีพใหม่)

### 14.1 สาเหตุ

ตาราง `public.professions` เปิดใช้ **Row Level Security (RLS)** และนโยบายเริ่มต้น (`INSERT WITH CHECK (true)`) ถูกปรับคุ้มครองให้เข้มงวดขึ้นบนโปรเจคจริง ทำให้การ `INSERT` ผ่าน `SupabaseClient` จาก Flutter — แม้ผู้ใช้จะ authenticated แล้ว — ถูกปฏิเสธด้วย `42501`

นอกจากนี้ ฟิลด์ `approval_required_license_types` ในตาราง `professions` เป็น `text[]` แต่ข้อมูลส่งจาก Dart มาในรูปแบบ JSON array ผ่าน `JSONB` ทำให้เกิดข้อผิดพลาด `42804: column "approval_required_license_types" is of type text[] but expression is of type jsonb`

### 14.2 อาการ

- กด `เพิ่ม` ในหน้าจอ `เพิ่มอาชีพใหม่` แล้วไม่สำเร็จ
- Log แสดง:
  - `RPC create failed: PostgrestException ... column "approval_required_license_types" is of type text[] but expression is of type jsonb, code: 42804`
  - `Error saving profession: PostgrestException ... new row violates row-level security policy for table "professions", code: 42501`
- แป้นพิมพ์บังข้อความ error ด้านล่างจอ

### 14.3 วิธีแก้ไข

1. **ฝั่งฐานข้อมูล:** สร้างหรืออัปเดต RPC function `create_profession_bypass_rls` แบบ `SECURITY DEFINER` เพื่อข้าม RLS และแปลง `approval_required_license_types` จาก JSONB เป็น `text[]`
   - ไฟล์ migration: `supabase/migrations/20260810100000_create_profession_bypass_rls.sql`
   - หลักการ: เหมือนกับ RPC `update_profession_bypass_rls` ที่มีอยู่แล้วสำหรับ update
2. **ฝั่ง Flutter:** `ProfessionRepository.createProfession` เรียก RPC ก่อน ถ้าล้มเหลวจึง fallback ไป `INSERT` ตรง (เพื่อ local dev ที่ยังไม่มี RLS จำกัด)
   - ไฟล์: `lib/features/admin/data/repositories/profession_repository.dart`
3. **ฝั่ง UI:** ครอบเนื้อหา dialog ด้วย `GestureDetector` พร้อม `FocusScope.of(context).unfocus()` เมื่อแตะพื้นที่นอกช่อง input แป้นพิมพ์จะหายและมองเห็นข้อความ error
   - ไฟล์: `lib/features/admin/presentation/pages/profession_admin_page.dart`

### 14.4 วิธี deploy

```bash
cd /Users/apisekpanyakong/ProjectFlutter/sheserved
supabase db push
```

หรือเปิด **Supabase Dashboard → SQL Editor** แล้วรันเนื้อหาใน `supabase/migrations/20260810100000_create_profession_bypass_rls.sql`

### 14.5 บทเรียน

- ห้ามอัปเดต RLS ของ `professions` บน Supabase dashboard โดยไม่มี migration สำรอง — มิฉะนั้นเครื่อง dev หรือ teammate จะไม่ทราบว่า policy เปลี่ยนไป
- ทุกครั้งที่ต้องส่ง `List<String>` จาก Flutter ไป Postgres RPC ให้ตรวจสอบว่า column เป้าหมายเป็น `text[]` หรือ `jsonb` — ถ้าเป็น `text[]` ให้แปลงด้วย `jsonb_array_elements_text` หรือ cast ก่อน insert
- ถ้ามี RPC บายพาสสำหรับ `UPDATE` แล้ว ต้องสร้าง RPC คู่ขนานสำหรับ `INSERT` เสมอ เมื่อ RLS บังคับใช้
- Flutter ไม่ควรพึ่ง service role key เพื่อข้าม RLS บน client — ต้องข้ามที่ RPC ฝั่ง Supabase เท่านั้น

## 15. Emergency Chat Overlay Layout (Updated 2026-09-03)

> **ไฟล์ที่เกี่ยวข้อง:** `lib/features/video/presentation/pages/emergency_live_page.dart`, `lib/features/video/presentation/pages/widgets/emergency_chat_widget.dart`, `lib/features/video/presentation/pages/widgets/bottom_tabs_widget.dart`

หน้า `EmergencyLivePage` มี overlay แชททฉุกเฉินลอยบนแผนที่ ต้องปฏิบัติตามข้อกำหนดตำแหน่งและความสูงดังต่อไปนี้ เพื่อป้องกันบดบังปุ่ม **ไทยมุง / เกี่ยวดอง / แจ้งเหต��ัน�ุุฉุกเฉิน** และป�้องก้องกันฟองข้อความ + ช่องกรอกลอยสูงเกิดไป

### 15.1 ข้อกำหนดตำแหน่ง

1. **เมื่อไม่มีแป้นพิมพ์ (keyboard closed)**
   - ด้านล่างของ `EmergencyChatWidget` ต้องอยู่ **เหนือ row ของปุ่ม `BottomTabsWidget` เท่านั้น**
   - ไม่อนุญาตให้ overlay ทับปุ่ม `ไทยมุง`, `เกี่ยวดอง`, หรือ `ัน�น�แจ้งเหตุแจ้งเหตุฉุกเฉิน`
   - `BottomTabsWidget` ใช้ `maxButtonSize = screenHeight * 0.1` และ `GlassTabButton` สัดส่วน 1:1
   - ระยะ bottom offset ของ chat overlay:
     ```
     bottom = padding.bottom + 12 + maxButtonSize
     ```
     โดย `12` คือ `SizedBox` ระหว่าง `BottomTabsWidget` กับขอบล่างของ SafeArea

2. **เมื่อมีแป้นพิมพ์ (keyboard open)**
   - `Scaffold` ใช้ `resizeToAvoidBottomInset` (default `true`) — body/Stack ถูกย่อให้สูงเพียงเหนือแป้นพิมพ์แล้ว
   - ⚠️ **Scaffold จะลบ `viewInsets.bottom` ออกจาก MediaQuery ที่ children ใน body เห็น** — วิดเจ็ตข้างใน body (เช่น `EmergencyUiOverlay`) เช็ค `MediaQuery.viewInsets.bottom` ตรง ๆ จะได้ `0` เสมอ
   - **แถวปุ่ม `BottomTabsWidget` ต้องถูกซ่อน** เมื่อแป้นพิมพ์เปิด โดยส่ง `isKeyboardVisible` เป็น parameter จาก `emergency_live_page.dart` (context เหนือ Scaffold อ่าน `viewInsets` ได้จริง) ลงใน `EmergencyUiOverlay`
   - **ห้ามบวก `viewInsets.bottom` ซ้ำ** ใน `Positioned.bottom` — จะทำให้แชทลอยขึ้นไปสุดจอ (double-counting)
   - แชทต้องชิดขอบล่างของพื้นที่ที่เหลือ (ขอบบนแป้นพิมพ์) 8pt

3. **รวมเงื่อนไข:**
   ```dart
   final mq = MediaQuery.of(context);
   final viewInsets = mq.viewInsets.bottom;
   final actionRowHeight = mq.size.height * 0.1;
   final chatBottom = viewInsets > 0
       ? 8.0  // keyboard เปิด: ปุ่มถูกซ่อน → ชิดขอบบนแป้นพิมพ์
       : mq.padding.bottom + 12 + actionRowHeight;  // keyboard ปิด: เหนือแถวปุ่ม
   ```
   - keyboard ปิด: `padding.bottom = 34` (home indicator) → แชทอยู่เหนือแถวปุ่ม
   - keyboard เปิด: แถวปุ่มซ่อน, ขอบล่าง Stack = ขอบบนแป้นพิมพ์ → แชทชิดขอบบนแป้นพิมพ์ 8pt

### 15.2 ข้อกำหนดความสูง

- ความสูงสูงสุดของ `EmergencyChatWidget`:
  - ถ้า **keyboard เปิด** หรือ **ยังไม่ได้วัดขอบล่าง Trending Panel** → จำกัด **25% ของความสูงหน้าจอ**
  - ถ้า **keyboard ปิด และวัด `trendingPanelBottom` ได้แล้ว** → ความสูงสูงสุด = พื้นที่ว่างระหว่าง `trendingPanelBottom + 12` ถึง `chatBottom` (overlay ชิดขอบล่างของกล่องยอดนิยม)
- เมื่อมี Trending Panel ให้คำนวณจากพื้นที่ว่างระหว่าง `trendingPanelBottom` กับ `chatBottom`
- ช่องกรอกข้อความ (Input) ต้องอยู่ **ชิดล่างสุด** ของ overlay ด้วยการใช้ `Column.mainAxisAlignment = MainAxisAlignment.end`
- ฟองข้อความต้องอยู่ **เหนือ input โดยตรง** ไม่ลอยสูงเกินกว่าความสูง overlay
- ไม่มี `inputSpacer` หรือตัวยก input ให้ลอยขึ้นไป

### 15.3 ตัวอย่างโครงสร้าง widget

```dart
// emergency_chat_widget.dart
Column(
  mainAxisSize: MainAxisSize.max,
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    // ปิด / filter ด้านบน
    Row(...),
    const SizedBox(height: 4),
    // รายการข้อความขยายตัวจากล่างขา�า�ึ้ึ้นบน
    Flexible(child: _buildMessageList()),
    // ช่องกรอกชิดล่าง
    _buildInputArea(inputHeight),
  ],
)
```

### 15.4 สิ่งห้าม

- ห้ามใช้ `Column.mainAxisSize = MainAxisSize.min` แล้วใส่ `Align` ชั่วคราว — ทำให้ overlay ลอยไม่สม่ำเสมอ
- ห้ามเพิ่ม `SizedBox` ยก input ให้สูงกว่า bottom ของ overlay
- ห้ามให้ `ListView` ลอยสูงกว่าพื้นที่ที overlay กำหนด


---

## Phase — Responder Route Polyline (Development → Production)

> Planned: 2026-09-03
> Status: Pending implementation

แผนแยกการ implement การวาดเส้นทางละเอียดของจิตอาสาบนแผนที่ออกเป็น 2 ระยะ ช่วงพัฒนาเน้น render polyline ให้ถูกต้องโดยใช้ test data สำเร็จรูป ช่วง production ค่อยเชื่อมกับ routing provider ของจริง

### 1. Phase 1 — Development: วาดเส้นจาก `encodedPolyline` ที่มีอยู่

**Objective:** รองรับการวาด `Polyline` ละเอียดบนแผนที่โดยไม่ต้องเรียก routing API ในช่วง dev/test

- สร้างตัวอย่าง `encodedPolyline` สำหรับ dev/test (hardcoded ใน `MapBackgroundWidget` หรือ mock data)
- ใช้ `flutter_polyline_points` decode แล้วสร้าง `Polyline` บน `EmergencyLivePage`
- ปรับ `_adjustMapBounds()` ให้ include ทุกจุดของ `encodedPolyline` (ไม่ใช่แค่ start/end) เพื่อไม่ให้เส้นทางโค้งหลุดหน้าจอ
- รองรับสีตามอาชีพ (เชื่อมกับ Phase — Responder Route Color by Profession)
- รองรับ dash pattern / width / opacity
- ทดสอบ performance กับเส้นทาง 100+ points

### 2. Phase 2 — Production: สร้าง `encodedPolyline` จากเส้นทางถนนจริง

**Objective:** เชื่อมกับ routing provider เพื่อสร้าง `encodedPolyline` ของเส้นทางถนนจริงที่จิตอาสาต้องใช้

#### 2.1 Routing Provider ตัวเลือก

| Provider | ค่าใช้จ่าย | ข้อดี | ข้อควรระวัง |
|---|---|---|---|
| Google Maps Directions API | มีค่าใช้จ่าย (ภายใน free tier ของ Google Maps Platform) | แม่นยำ ครอบคลุมไทย | ต้องบริหาร quota/credit; ห้ามเปิด `Maps JavaScript API` ตามแผนเดิม |
| OSRM (`router.project-osrm.org`) | ฟรี demo | ไม่เสียเงิน | limit ต่ำ, ข้อมูลถนนไทยไม่สมบูรณ์, ไม่เหมาะ production |
| Self-host OSRM/Valhalla | ค่าเซิร์ฟเวอร์ | ฟรี license, ควบคุมเอง | ต้องเตรียมข้อมูลถนนและ maintain |
| OpenRouteService | มี free tier | API key ฟรี | rate limit, ข้อมูลถนนไทย varies |

#### 2.2 Implementation Steps

- แก้ `_drawRouteToEmergency` ใน `rescue_page.dart` ให้เลือก provider ได้ (default OSRM สำหรับ dev, Google สำหรับ production ถ้า budget อนุญาต)
- ส่ง `encodedPolyline` ผ่าน `WebSocketService.sendVolunteerRoute` (มีแล้ว) เมื่อ route พร้อม
- เก็บ `route_polyline` ลง `incident_responses` (มีแล้ว)
- `MapBackgroundWidget` ใช้ `route_polyline` แทนเส้นตรงถ้ามี ถ้าไม่มี fallback ไปเส้นตรง
- อัปเดต `VIDEO_SYSTEM_PLAN.md` เรื่อง Cost Prevention เพิ่มเตือน Directions API
- (Optional) อัปเดต `encodedPolyline` แบบ real-time เมื่อจิตอาสาออกนอก route

### 3. Fallback & Edge Cases

| สถานการณ์ | การจัดการ |
|---|---|
| routing API ล้ม | fallback เส้นตรงจาก `currentLat/Lng` ไปจุดเกิดเหตุ |
| ไม่มี `encodedPolyline` | ใช้เส้นตรงเหมือนเดิม |
| dev/test | ใช้ mock `encodedPolyline` โดยไม่ต้องเรียก API |
| ผู้ใช้ปิดการใช้งาน routing provider | ใช้เส้นตรง |

### 4. Testing Checklist

**Phase 1:**
- [ ] Decode `encodedPolyline` ได้ถูกต้อง
- [ ] `Polyline` วาดบน `EmergencyLivePage` ได้
- [ ] `_adjustMapBounds` include ทุกจุดของ polyline
- [ ] สี/width/opacity ถูกต้อง

**Phase 2:**
- [ ] เรียก routing provider ได้ใน production mode
- [ ] ส่ง `encodedPolyline` ขึ้น server ได้
- [ ] `MapBackgroundWidget` แสดงเส้นทางจริงเมื่อมี `route_polyline`
- [ ] fallback เส้นตรงทำงานเมื่อ route หาย
- [ ] ไม่มีค่าใช้จ่ายแฝงใน dev mode