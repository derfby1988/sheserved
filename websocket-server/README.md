# WebSocket Server for Real-time Location Tracking

Self-hosted WebSocket Server สำหรับ Real-time Location Tracking

## Features

- Real-time location updates via WebSocket
- PostgreSQL database สำหรับเก็บข้อมูลตำแหน่ง
- Room-based tracking สำหรับกลุ่ม
- REST API สำหรับ query ข้อมูลตำแหน่ง

## Prerequisites

- Node.js (v14 หรือสูงกว่า)
- PostgreSQL (v12 หรือสูงกว่า)
- npm หรือ yarn

## Installation

1. ติดตั้ง dependencies:
```bash
npm install
```

2. สร้าง database:
```bash
psql -U postgres -f database.sql
```

3. ตั้งค่า environment variables (สร้างไฟล์ `.env`):
```env
DB_HOST=localhost
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=your_password
DB_PORT=5432
PORT=3000
```

## Running

### Development mode (with auto-reload):
```bash
npm run dev
```

### Production mode:
```bash
npm start
```

## API Endpoints

### WebSocket Events

#### Client → Server:
- `user-connected` - แจ้งว่า user เชื่อมต่อแล้ว
- `location-update` - ส่งตำแหน่งใหม่
- `subscribe-user` - Subscribe ตำแหน่งของ user อื่น
- `unsubscribe-user` - Unsubscribe ตำแหน่งของ user อื่น
- `join-room` - เข้าร่วม room (สำหรับ group tracking)
- `leave-room` - ออกจาก room

#### Server → Client:
- `location-updated` - รับตำแหน่งที่อัพเดท
- `user-online` - แจ้งว่า user อื่นออนไลน์
- `user-offline` - แจ้งว่า user อื่นออฟไลน์
- `error` - แจ้ง error

### REST API

- `GET /health` - Health check
- `GET /api/locations/:userId?limit=100` - ดึงตำแหน่งล่าสุดของ user

## Security Considerations

1. **Authentication**: เพิ่ม authentication middleware
2. **CORS**: เปลี่ยน CORS origin ใน production
3. **Rate Limiting**: เพิ่ม rate limiting เพื่อป้องกัน abuse
4. **SSL/TLS**: ใช้ HTTPS/WSS ใน production
5. **Input Validation**: Validate ข้อมูลที่รับจาก client

## Production Deployment

1. ใช้ PM2 สำหรับ process management:
```bash
npm install -g pm2
pm2 start server.js --name websocket-server
```

2. ใช้ Nginx เป็น reverse proxy:
```nginx
location /socket.io/ {
    proxy_pass http://localhost:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

3. ตั้งค่า SSL certificate (Let's Encrypt)

## Monitoring

- ใช้ PM2 monitoring: `pm2 monit`
- ใช้ health check endpoint: `GET /health`

## Troubleshooting

- **Connection refused**: ตรวจสอบว่า server กำลังรันอยู่
- **Database connection error**: ตรวจสอบ database credentials
- **Port already in use**: เปลี่ยน PORT ใน environment variables
