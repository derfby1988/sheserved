# Quick Start Guide

## ปัญหา: ERR_CONNECTION_REFUSED

ถ้าเห็น error นี้ แสดงว่า WebSocket Server ยังไม่ได้รัน

## วิธีแก้ไข (3 ขั้นตอน):

### ขั้นตอนที่ 1: ติดตั้ง Dependencies

```bash
cd websocket-server
npm install
```

### ขั้นตอนที่ 2: Setup Database (ถ้ายังไม่ได้ทำ)

```bash
# สร้าง database
createdb sheserved

# หรือใช้ PostgreSQL client
psql -U sheserved
CREATE DATABASE sheserved;
\q

# รัน schema
psql -U sheserved -d sheserved -f database.sql
```

### ขั้นตอนที่ 3: แก้ไขไฟล์ .env

แก้ไขไฟล์ `.env` ในโฟลเดอร์ `websocket-server`:

```env
DB_HOST=localhost
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=your_actual_password  # ← เปลี่ยนเป็น password จริงของคุณ
DB_PORT=5432
PORT=3000
```

### ขั้นตอนที่ 4: Start Server

```bash
# Development mode (recommended)
npm run dev

# หรือ Production mode
npm start
```

## ตรวจสอบว่า Server รันอยู่:

เปิด browser ไปที่: `http://localhost:3000/health`

ควรเห็น:
```json
{
  "status": "ok",
  "connectedUsers": 0
}
```

## ถ้ายังไม่ได้:

1. **ตรวจสอบว่า Node.js ติดตั้งแล้ว:**
   ```bash
   node --version
   npm --version
   ```

2. **ตรวจสอบว่า PostgreSQL รันอยู่:**
   ```bash
   # macOS
   brew services list | grep postgresql
   
   # หรือ
   psql -U postgres -c "SELECT 1;"
   ```

3. **ตรวจสอบ port 3000:**
   ```bash
   lsof -ti:3000
   # ถ้ามี output แสดงว่ามี process ใช้ port 3000 อยู่แล้ว
   ```

4. **ลองเปลี่ยน port:**
   แก้ไขไฟล์ `.env`:
   ```env
   PORT=3001
   ```
   แล้วเข้าถึง `http://localhost:3001/health`
