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
CREATE TABLE incident_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID REFERENCES videos(id) ON DELETE CASCADE,
    responder_id UUID NOT NULL, -- user_id ของอาชีพที่เข้าช่วยเหลือ
    status VARCHAR(20) DEFAULT 'en_route', -- en_route, arrived, completed, cancelled
    estimated_arrival TIMESTAMP,
    arrived_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

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
    - **Proximity Filter**: ผู้ใช้ต้องอยู่ในระยะห่างจากจุดเกิดเหตุ **ไม่เกิน 500 เมตร** 
    - **Distance Alert**: หากโหมดไทยมุงถูกเรียกใช้งานแต่ระยะห่างเกิน 500 เมตร ระบบจะแจ้งเตือนให้ผู้ใช้ทราบว่า "คุณอยู่ไกลจากจุดเกิดเหตุเกินไปสำหรับการทำหน้าที่ไทยมุง"
- **Community Alert (Notification Channels)**: 
    - **Push Notification (FCM)**: ใช้ Firebase Cloud Messaging สำหรับส่งแจ้งเตือนหาผู้ใช้ที่อยู่รอบพิกัดเหตุการณ์ 500 เมตร แม้จะปิดแอปอยู่ เพื่อเชิญชวนให้มาทำหน้าที่ "ไทยมุง"
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
