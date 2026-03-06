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

### Self-hosted (FFmpeg, PostgreSQL, Queue)
- **ค่าใช้จ่าย**: $0 (รันบนเครื่องหลัก)

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

## Notes

- ระบบทั้งหมดรันที่เครื่องหลักเครื่องเดียว
- **Queue**: สำคัญมากเพื่อคุม CPU ไม่ให้รัน FFmpeg มากเกินไปจนเครื่องค้าง
- **Cleanup**: ต้องมั่นใจว่าไฟล์ถูกลบหลัง success/error เพื่อประหยัดพื้นที่ Disk
- **Progress**: ใช้ WebSocket เป็นหลักเพื่อความลื่นไหลของ UI และ Polling เป็นแผนสำรอง
- Bunny.net มี PoP ในประเทศไทย ทำให้ latency ต่ำ
- FFmpeg แปลงวิดีโอเป็น HLS format สำหรับ adaptive streaming
