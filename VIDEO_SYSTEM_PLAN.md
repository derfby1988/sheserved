# Video Upload and Streaming System Plan

## Overview

แผนระบบวิดีโอสำหรับ Tree Law Zoo โดยใช้ Bunny.net + PostgreSQL + FFmpeg ทั้งหมดรันที่เครื่องหลัก (เครื่องเดียว)

## Architecture

### ทางเลือกที่เลือก: Bunny.net + PostgreSQL + FFmpeg (Self-hosted)

**Flow การทำงาน:**
1. Upload → 2. Insert to PostgreSQL → 3. Transcode (FFmpeg) → 4. Upload to Bunny.net → 5. Update PostgreSQL → 6. Return video info

### สถาปัตยกรรม

```
┌─────────────────────────────────────────────────┐
│  Main Machine (เครื่องหลัก)                      │
│                                                 │
│  ┌─────────────┐    ┌──────────────┐          │
│  │  Flutter    │    │  WebSocket   │          │
│  │  App        │───▶│  Server      │          │
│  └─────────────┘    │  (Node.js)   │          │
│                     └──────┬───────┘          │
│                            │                   │
│                     ┌──────▼───────┐          │
│                     │  PostgreSQL  │          │
│                     │  (Database) │          │
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
CREATE TABLE videos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    bunny_video_id VARCHAR(255),
    bunny_url TEXT,
    thumbnail_url TEXT,
    duration INTEGER, -- seconds
    file_size BIGINT, -- bytes
    status VARCHAR(50) DEFAULT 'processing', -- processing, ready, error
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Technology Stack

### Backend (Node.js)
- **express** - Web server
- **multer** - File upload handling
- **pg** - PostgreSQL client
- **fluent-ffmpeg** - FFmpeg wrapper
- **axios** - HTTP client for Bunny.net API

### CDN/Storage
- **Bunny.net** - CDN และ Storage สำหรับวิดีโอ
  - มี PoP (Point of Presence) ในประเทศไทย
  - ราคาถูก ($0.01/GB storage, $0.005/GB bandwidth)
  - รองรับ HLS streaming

### Video Processing
- **FFmpeg** - Transcoding วิดีโอเป็น HLS format

## Environment Variables

```env
# Database
DB_HOST=localhost
DB_NAME=tree_law_zoo
DB_USER=tree_law_zoo_user
DB_PASSWORD=<password>
DB_PORT=5432

# Server
PORT=3000

# Bunny.net
BUNNY_API_KEY=<your_api_key>
BUNNY_STORAGE_ZONE=<your_storage_zone>
BUNNY_CDN_URL=<your_cdn_url>
```

## Cost Estimation

### Bunny.net (สำหรับประเทศไทย)
- **Storage**: $0.01/GB/เดือน
- **Bandwidth**: $0.005/GB
- **ตัวอย่าง**: 100GB storage + 1TB bandwidth/เดือน = $1 + $5 = **$6/เดือน**

### Self-hosted (FFmpeg, PostgreSQL)
- **ค่าใช้จ่าย**: $0 (รันบนเครื่องหลัก)

## Development Setup

### เครื่องหลัก (Main Machine)
- ✅ Flutter SDK
- ✅ Node.js
- ✅ PostgreSQL
- ✅ FFmpeg
- ✅ หน้าจอ
- ✅ GitHub sync

### ไม่ต้อง
- ❌ เครื่องที่ 2 (Client Machine) ไม่ต้องเปิดระหว่างพัฒนา
- ❌ SSH หรือ remote connection ไม่จำเป็น

## Implementation Files

### Backend
- `websocket-server/routes/video.js` - Video upload routes
- `websocket-server/services/video-service.js` - Video processing service

### Flutter
- `lib/services/video_service.dart` - Video API client

## Notes

- ระบบทั้งหมดรันที่เครื่องหลักเครื่องเดียว
- ใช้ GitHub สำหรับ sync code ระหว่างเครื่อง
- Bunny.net มี PoP ในประเทศไทย ทำให้ latency ต่ำ
- FFmpeg แปลงวิดีโอเป็น HLS format สำหรับ adaptive streaming
