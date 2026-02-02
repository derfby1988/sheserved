# ✅ Database Server Setup เสร็จสมบูรณ์!

## Phase 0: Setup Database Server - เสร็จแล้ว 100%

### สรุปสิ่งที่ทำเสร็จแล้ว

1. ✅ **ติดตั้ง PostgreSQL@14**
   - ติดตั้ง Homebrew
   - ติดตั้ง PostgreSQL@14
   - Format External Drive เป็น APFS (`/Volumes/PostgreSQL`)
   - Initialize Database Cluster บน External Drive
   - Start PostgreSQL Service

2. ✅ **ตั้งค่า Remote Connection**
   - แก้ไข `postgresql.conf` (listen_addresses = '*')
   - แก้ไข `pg_hba.conf` (remote access rule)
   - PostgreSQL ทำงานอยู่แล้ว

3. ✅ **สร้าง Database และ User**
   - Database: `sheserved`
   - User: `sheserved`
   - สิทธิ์: ALL PRIVILEGES

4. ✅ **Setup Database Schema**
   - Tables: `users`, `locations`
   - Schema ถูก setup เรียบร้อย

5. ✅ **หา IP Address**
   - IP Address ของ Database Server: `<IP_ADDRESS>`
   - Port: 5432

6. ✅ **ตั้งค่า Firewall**
   - Firewall ตั้งค่าเรียบร้อย
   - Port 5432 เปิดอยู่

7. ✅ **ทดสอบ Remote Connection**
   - ทดสอบ port สำเร็จ
   - ทดสอบ connection สำเร็จ

---

## 📋 ข้อมูล Database Server

### Connection Information

```
DB_HOST=<IP_ADDRESS>
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=<password ที่ตั้งไว้>
DB_PORT=5432
```

### Database Structure

- **Database:** `tree_law_zoo`
- **Tables:**
  - `users` - ข้อมูลผู้ใช้
  - `locations` - ข้อมูลตำแหน่ง

### Server Information

- **Data Directory:** `/Volumes/PostgreSQL/postgresql-data`
- **Filesystem:** APFS
- **PostgreSQL Version:** 14.20
- **Port:** 5432
- **Status:** ✅ ทำงานอยู่

---

## 🎯 ขั้นตอนถัดไป

### สำหรับเครื่อง Client (เครื่องอื่น)

ตอนนี้ Database Server พร้อมใช้งานแล้ว เครื่อง Client สามารถ:

1. **Setup Client Machine** (Phase 1-4)
   - ติดตั้ง Prerequisites (Flutter, Node.js, Java 17)
   - Clone repository
   - Setup Flutter App
   - Setup WebSocket Server

2. **ตั้งค่า .env ใน websocket-server/**
   ```env
   DB_HOST=<IP_ADDRESS>
   DB_NAME=sheserved
   DB_USER=sheserved
   DB_PASSWORD=<password>
   DB_PORT=5432
   ```

3. **ทดสอบ Connection จาก Client**
   ```bash
   psql -h <IP_ADDRESS> -U sheserved -d sheserved
   ```

---

## ⚠️ หมายเหตุสำคัญ

1. **External Drive ต้อง mount อยู่เสมอ**
   - PostgreSQL ต้องการ data directory
   - ตั้งค่า auto-mount ใน System Preferences > Users & Groups > Login Items

2. **Backup ข้อมูลเป็นประจำ**
   - External drive อาจเสียหายได้
   - ใช้ `pg_dump` เพื่อ backup database

3. **Security**
   - ใช้ strong password
   - พิจารณาใช้ VPN หรือ SSH tunnel สำหรับ production
   - จำกัด IP addresses ใน `pg_hba.conf` (ถ้าจำเป็น)

---

## 🎉 สรุป

**Database Server Setup เสร็จสมบูรณ์แล้ว!**

เครื่องนี้พร้อมให้เครื่อง Client เชื่อมต่อมาใช้ database แล้ว

ขั้นตอนถัดไป: Setup Client Machine (Phase 1-4)
