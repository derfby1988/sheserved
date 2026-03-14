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

```sql
-- หลักสำหรับเก็บข้อมูลวิดีโอ
CREATE TABLE videos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    type VARCHAR(20) DEFAULT 'normal', -- normal, emergency
    title VARCHAR(255) NOT NULL,
    description TEXT,
    bunny_video_id VARCHAR(255),
    bunny_url TEXT,
    thumbnail_url TEXT,
    duration INTEGER,
    file_size BIGINT,
    status VARCHAR(50) DEFAULT 'processing',
    progress INTEGER DEFAULT 0,
    address TEXT,
    road VARCHAR(255),
    soi VARCHAR(255),
    alley VARCHAR(255),
    village VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- สำหรับเก็บตำแหน่งพิกัดที่สัมพันธ์กับเวลาในวิดีโอ (สำหรับแสดงผลบน Map)
CREATE TABLE video_gps_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    timestamp_offset INTEGER NOT NULL, -- วินาทีที่เท่าไหร่ของวิดีโอ
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- สำหรับเก็บ Interaction (Likes, Views, Gifting)
CREATE TABLE video_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    type VARCHAR(20), -- like, gift, view
    value INTEGER DEFAULT 0, -- จำนวนเงินบริจาคหรือค่าอื่นๆ
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- สำหรับเก็บสถานะการตอบรับช่วยเหลือของอาชีพต่างๆ
-- ✅ อัปเดต 2026-03-14: ตรงกับ Supabase Production Schema จริง
CREATE TABLE incident_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    -- ✅ ชื่อ Field จริงใน DB คือ volunteer_id (ไม่ใช่ responder_id)
    -- FK ชื่อ: incident_responses_volunteer_id_fkey
    volunteer_id UUID NOT NULL REFERENCES consumer_profiles(id),
    status VARCHAR(20) DEFAULT 'en_route',
    -- Status ที่ใช้จริง: 'en_route' | 'accepted' | 'arrived' | 'resolved' | 'cancelled'
    accepted_at TIMESTAMP,                -- เวลาที่รับงาน
    arrived_at TIMESTAMP,                 -- เวลาที่ถึงที่เกิดเหตุ
    resolved_at TIMESTAMP,                -- เวลาที่ปิดงาน (resolved/cancelled)
    volunteer_start_lat DOUBLE PRECISION, -- ละติจูดจุดออกตัวของ volunteer
    volunteer_start_lng DOUBLE PRECISION, -- ลองจิจูดจุดออกตัวของ volunteer
    notes TEXT,                           -- หมายเหตุเพิ่มเติม
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- ป้องกัน volunteer เดิมรับงานเดิมซ้ำ
    UNIQUE (video_id, volunteer_id)
);

-- ⚠️ หมายเหตุสำคัญสำหรับทีม:
-- ห้ามใช้ชื่อ responder_id ในโค้ดใหม่ใดๆ ทั้งสิ้น
-- FK constraint ที่ใช้ Join ใน Supabase query:
--   consumer_profiles!incident_responses_volunteer_id_fkey(full_name)
--   user_group_roles!incident_responses_volunteer_id_fkey(...)



## Technology Stack

### Backend (Node.js)
- **express** & **multer** - API และ Upload
- **pg** - PostgreSQL
- **fluent-ffmpeg** - Transcoding
- **axios** - Bunny.net API
- **bullmq** - สำหรับจัดการ **Priority Queue**
- **socket.io** - สำหรับ Progress และ Real-time Interactions

### Flutter / Frontend
- **Supabase SDK** - สำหรับดึงข้อมูลวิดีโอและ GPS
- **DonationRepository** - เชื่อมโยงปุ่ม "บริจาค" เพื่อเรียกใช้ฟังก์ชัน `getRequests()` และการชำระเงินเดิม
- **video_player** / **chewie** - สำหรับเล่นวิดีโอ HLS

### CDN/Storage
- **Bunny.net** - HLS streaming & Storage (Thailand PoP)

### Video Processing & Management
- **FFmpeg**: Transcoding เป็น HLS
- **Priority Queue**: กำหนดให้ Emergency tasks รันก่อน
- **Auto Cleanup**: ลบไฟล์หลังประมวลผลเสร็จสิ้น

## UI/UX Implementation Tips (Standard for Figma Design)

- **Map Integration**: ใช้ `video_gps_tracks` เพื่อขยับ Marker บนแผนที่ตาม `currentPosition` ของวิดีโอ
- **Donation Integration**:
  - เมื่อคลิกปุ่ม "บริจาค" ในหน้าวิดีโอ ให้ตรวจสอบ `donation_request_id` จากวิดีโอนั้น
  - เรียกใช้ `DonationRepository.getRequests()` เพื่อดึงข้อมูลปลายทาง และเริ่ม Flow การโอนเงิน/บริจาคเดิมที่มีอยู่
  - หลังการบริจาคสำเร็จ ให้ส่ง Event ผ่าน **Socket.io** เพื่อให้ระบบ Real-time Interactions แสดงข้อความขอบคุณหรือยอดรวมอัปเดตทันที
- **Glassmorphism Overlay**: ใช้ `BackdropFilter` ใน Flutter ซ้อนทับหน้าจอวิดีโอเพื่อให้ได้ลุคตาม Figma
- **Emergency Priority**: ในหน้า Dashboard ของเจ้าหน้าที่ วิดีโอประเภท `emergency` ต้องแสดงผลโดดเด่นและเข้าถึงง่ายที่สุด

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

# Bunny.net
BUNNY_API_KEY=<your_api_key>
BUNNY_STORAGE_ZONE=<your_storage_zone>
BUNNY_CDN_URL=<your_cdn_url>

# Config
MAX_CONCURRENT_TRANSCODES=2
TEMP_FILE_PATH=./temp/videos
REDIS_URL=redis://localhost:6379
```

## Cost Estimation

### Bunny.net (สำหรับประเทศไทย)
- **Storage**: $0.01/GB/เดือน
- **Bandwidth**: $0.005/GB
- **ตัวอย่าง**: 100GB storage + 1TB bandwidth/เดือน = $1 + $5 = **$6/เดือน**

### Google Maps (Mobile Only)
- **Maps SDK for Android & iOS**: ฟรีไม่จำกัดจำนวนครั้ง (Unlimited)
- **Maps JavaScript API (Web)**: ป้องกันไม่ให้เปิดใช้งานเพื่อหลีกเลี่ยงค่าใช้จ่าย ($7/1,000 loads)
- **ค่าใช้จ่ายรายเดือน**: **$0** (ภายใต้การจำกัดการใช้งานเฉพาะแอปมือถือ)

### Self-hosted (FFmpeg, PostgreSQL, Queue)
- **ค่าใช้จ่าย**: $0 (รันบนเครื่องหลัก)

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
- **Community Alert (Notification Channels)**: 
    - **Push Notification (FCM)**: ใช้ Firebase Cloud Messaging สำหรับส่งแจ้งเตือนหาผู้ใช้ที่อยู่รอบพิกัดเหตุการณ์ **ตามรัศมี (alertRadius)** ที่ผู้ใช้แต่ละคนกำหนดไว้ แม้จะปิดแอปอยู่ เพื่อเชิญชวนให้มาทำหน้าที่ "ไทยมุง"
    - **In-app Entry (HomeHeaderSection)**: ใช้พื้นที่ด้านขวาของ `HomeHeaderSection` ในหน้า Home เพื่อแสดง Badge แจ้งเตือนเหตุการณ์ใกล้ตัวแบบ Real-time (WebSocket) พร้อมข้อความเชิญชวน
    - **One-Click Navigation**: เมื่อกดที่การแจ้งเตือนใน `HomeHeaderSection` ระบบจะต้องนำทางผู้ใช้ไปยังหน้า `EmergencyLivePage` ของเหตุการณ์นั้นทันที
- **Crowd Support Display**: แสดงจุดหรือจำนวน "ไทยมุง" บนแผนที่รอบจุดเกิดเหตุ เพื่อให้เจ้าหน้าที่เห็นความหนาแน่นของพยานและผู้ช่วยในพื้นที่

### 2. Community Reporting (Thai Mhung Mode)
เมื่อผู้ใช้อยู่ในโหมด "ไทยมุง" และกดเมนูนี้ จะปรากฏ UI คล้ายกับ `IncidentReportWidget` แต่ปรับเปลี่ยนดังนี้:
- **Photo Only**: ปิดความสามารถในการถ่ายคลิปวิดีโอ ให้เหลือเพียงการถ่ายภาพนิ่งเท่านั้น
- **Quota Limit**: จำกัดการส่งภาพได้สูงสุด **3 ภาพ ต่อ 1 เหตุการณ์ ต่อคน**
- **Countdown Display**: มี UI แสดงตัวนับจำนวนภาพที่เหลืออยู่ (เช่น "เหลือโควตาถ่ายภาพ 2/3")

### 3. Thai Mhung Gallery (Map Overlay)
แสดงรูปภาพที่ถูกบันทึกโดย "ไทยมุง" ไว้ที่ส่วนล่างตรงกลางของแผนที่:
- **Single Row View**: แสดงผลแบบแถวนอนบรรทัดเดียว ไม่กว้างเกินขนาดแผนที่
- **Focus Effect**: ภาพตรงกลางจะมีขนาดใหญ่กว่าภาพที่ขนาบข้าง (ซ้าย-ขวา)
- **Interactive Carousel**: 
    - ผู้ใช้สามารถเลื่อน (Scroll/Swipe) ซ้าย-ขวา เพื่อเปลี่ยนรูปที่ต้องการดู
    - เมื่อรูปใดมาอยู่ตรงกลาง รูปนั้นจะขยายใหญ่ขึ้นโดยอัตโนมัติ
    - สามารถกดที่รูปตรงกลางเพื่อขยายภาพแบบ Popup (Lightbox view) และสามารถปิดได้
- **Display Limit**: แสดงรูปตัวอย่างข้างซ้ายสูงสุด 2 รูป และข้างขวาสูงสุด 2 รูป
- **Ellipsis Indicator**: หากทิศทางใดมีรูปภาพมากกว่าที่แสดงอยู่ ให้แสดงสัญลักษณ์ ".." เพื่อแจ้งให้ผู้ใช้ทราบว่าสามารถเลื่อนดูต่อได้

### 4. Yield Way Feedback System
- ระบบให้ "ไทยมุง" กดปุ่ม "ให้ทาง" (Yield Way)
- ข้อมูลจะถูกประมวลผลเป็นเปอร์เซ็นต์ (Yield Way Percentage) และส่งข้อมูลไปยังรถฉุกเฉินหรือศูนย์สั่งการแบบ Real-time

---

## Strict Alert Policy & Rejected Enhancements (Updated 2026-03-13)

เพื่อให้ระบบมีความชัดเจนและไม่สร้างความสับสนให้กับผู้ใช้ (โดยเฉพาะกลุ่มวิชาชีพ) ได้มีการกำหนดนโยบายการแจ้งเตือนดังนี้:

### 1. No Professional Fallback (ยกเลิกการให้สิทธิอัตโนมัติ)
- **นโยบาย**: ระบบจะไม่ทำการ Fallback หรือให้สิทธิ "รับแจ้งเหตุ" แก่กลุ่มวิชาชีพ (Professional Responder) โดยอัตโนมัติ หากหมวดหมู่เหตุการณ์นั้นไม่ได้มีการระบุสิทธิของอาชีพนั้นๆ ไว้อย่างชัดเจนในฐานข้อมูล
- **เหตุผล**: เพื่อป้องกันไม่ให้ผู้ใช้สับสนเกี่ยวกับขอบเขตหน้าที่ (Scope of Duty) ของตนเอง และลดความถี่ของการแจ้งเตือนที่ไม่ตรงกับความเชี่ยวชาญ

### 2. Manual Distance Control (ควบคุมระยะทางด้วยตนเอง)
- **นโยบาย**: ระบบจะไม่ทำการขยายรัศมี (Distance expansion/buffer) หรือเพิ่มตัวคูณความแม่นยำใดๆ เหนือกว่าค่า `alertRadius` ที่ผู้ใช้กำหนดเองในหน้า Profile
- **เหตุผล**: เพื่อให้ผู้ใช้สามารถควบคุม "พื้นที่รับผิดชอบ" ได้อย่างแม่นยำตามความต้องการจริง และป้องกันการแจ้งเตือนที่ถี่เกินไปในเขตที่อยู่อาศัยหนาแน่น

### 3. Explicit Mapping First
- ทุกการแจ้งเตือนในหน้า Home จะต้องผ่านการตรวจสอบความตรวจสอบความสัมพันธ์ (Relevance Check) ระหว่าง `categoryId` และ `professionId` ในตาราง `incident_categories` เท่านั้น หากไม่มีการจับคู่กัน ระบบจะถือว่าไม่เกี่ยวข้องและไม่แสดงผลการแจ้งเตือน (ยกเว้นโหมดไทยมุงที่มีเงื่อนไขเฉพาะ)

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

### Bug Fix #3 — Thai Mhung Distance ต้องใช้ `user.alertRadius` ไม่ใช่ Hardcoded
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
