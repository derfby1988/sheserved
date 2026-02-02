# Setup Guide - WebSocket Server & Database

คู่มือการ setup WebSocket Server และ Database สำหรับ Real-time Location Tracking

## Prerequisites

ก่อนเริ่มต้น ต้องมี:
1. **Node.js** (v14 หรือสูงกว่า) - [Download](https://nodejs.org/)
2. **PostgreSQL** (v12 หรือสูงกว่า) - [Download](https://www.postgresql.org/download/)
3. **npm** (มาพร้อมกับ Node.js)

## ขั้นตอนที่ 1: Setup Database

### วิธีที่ 1: ใช้ Script (แนะนำ)

```bash
cd websocket-server
./setup-database.sh
```

Script จะถาม:
- PostgreSQL password
- Database name (default: sheserved)
- Database user (default: sheserved)

### วิธีที่ 2: Manual Setup

1. เข้าสู่ PostgreSQL:
```bash
psql -U postgres
```

2. สร้าง database:
```sql
CREATE DATABASE sheserved;
```

3. ออกจาก psql และรัน schema:
```bash
psql -U sheserved -d sheserved -f database.sql
```

## ขั้นตอนที่ 2: Setup WebSocket Server

### 1. ติดตั้ง Dependencies

```bash
cd websocket-server
npm install
```

### 2. สร้างไฟล์ .env

สร้างไฟล์ `.env` ในโฟลเดอร์ `websocket-server`:

```env
# Database Configuration
DB_HOST=localhost
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=your_password
DB_PORT=5432

# Server Configuration
PORT=3000
```

**⚠️ เปลี่ยน `DB_PASSWORD` และค่าอื่นๆ ตามที่คุณตั้งค่า**

### 3. ใช้ Setup Script (แนะนำ)

```bash
./setup.sh
```

Script จะ:
- ติดตั้ง dependencies
- สร้างไฟล์ .env (ถ้ายังไม่มี)
- Setup database

### 4. Start Server

#### Development mode (with auto-reload):
```bash
npm run dev
```

#### Production mode:
```bash
npm start
```

หรือใช้ script:
```bash
./start.sh
```

## ตรวจสอบการทำงาน

### 1. ตรวจสอบ Server

เปิด browser ไปที่: `http://localhost:3000/health`

ควรเห็น:
```json
{
  "status": "ok",
  "connectedUsers": 0
}
```

### 2. ตรวจสอบ Database

```bash
psql -U sheserved -d sheserved -c "SELECT COUNT(*) FROM locations;"
```

## Troubleshooting

### ปัญหา: Cannot connect to PostgreSQL

**แก้ไข:**
1. ตรวจสอบว่า PostgreSQL กำลังรันอยู่:
   ```bash
   # macOS
   brew services list
   
   # Linux
   sudo systemctl status postgresql
   ```

2. ตรวจสอบ connection:
   ```bash
   psql -U postgres -h localhost
   ```

### ปัญหา: Port 3000 already in use

**แก้ไข:**
1. เปลี่ยน PORT ในไฟล์ .env:
   ```env
   PORT=3001
   ```

2. หรือ kill process ที่ใช้ port 3000:
   ```bash
   # macOS/Linux
   lsof -ti:3000 | xargs kill -9
   ```

### ปัญหา: Database connection error

**แก้ไข:**
1. ตรวจสอบ credentials ในไฟล์ .env
2. ตรวจสอบว่า database ถูกสร้างแล้ว:
   ```bash
   psql -U postgres -l
   ```

### ปัญหา: Permission denied when running scripts

**แก้ไข:**
```bash
chmod +x setup.sh setup-database.sh start.sh
```

## Production Deployment

### 1. ใช้ PM2 (Process Manager)

```bash
# ติดตั้ง PM2
npm install -g pm2

# Start server
pm2 start server.js --name websocket-server

# Auto-start on reboot
pm2 startup
pm2 save

# Monitor
pm2 monit
```

### 2. ใช้ Nginx เป็น Reverse Proxy

สร้างไฟล์ `/etc/nginx/sites-available/websocket`:

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location /socket.io/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 3. SSL Certificate (Let's Encrypt)

```bash
sudo certbot --nginx -d your-domain.com
```

## Security Checklist

- [ ] เปลี่ยน CORS origin ใน production
- [ ] เพิ่ม authentication/authorization
- [ ] ใช้ HTTPS/WSS
- [ ] ตั้งค่า rate limiting
- [ ] Validate input data
- [ ] ใช้ environment variables สำหรับ sensitive data
- [ ] Setup firewall rules
- [ ] Regular backups

## Next Steps

หลังจาก setup เสร็จแล้ว:

1. **ทดสอบ WebSocket connection** จาก Flutter app
2. **ตั้งค่า server URL** ใน `WebSocketService`
3. **ทดสอบ location tracking**

ดูตัวอย่างการใช้งานใน `lib/services/README.md`
