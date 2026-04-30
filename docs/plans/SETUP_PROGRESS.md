# สถานะการ Setup Database Server

## Phase 0: Setup Database Server (เครื่องหลัก)

### ✅ ขั้นตอนที่เสร็จแล้ว

#### 0.1 ติดตั้ง PostgreSQL
- ✅ ติดตั้ง Homebrew
- ✅ ติดตั้ง PostgreSQL@14
- ✅ Format External Drive เป็น APFS (`/Volumes/PostgreSQL`)
- ✅ Initialize Database Cluster บน External Drive
- ✅ ตั้งค่า Environment Variable (PGDATA)
- ✅ Start PostgreSQL Service

#### 0.2 ตั้งค่า PostgreSQL ให้รับ Remote Connection
- ✅ แก้ไข `postgresql.conf` (listen_addresses = '*')
- ✅ แก้ไข `pg_hba.conf` (เพิ่ม remote access rule)
- ✅ PostgreSQL ทำงานอยู่แล้ว

---

### ✅ ขั้นตอนที่เสร็จแล้ว (เพิ่มเติม)

#### 0.3 สร้าง Database และ User
- ✅ สร้าง User: `sheserved`
- ✅ สร้าง Database: `sheserved`
- ✅ ให้สิทธิ์เรียบร้อย

#### 0.5 หา IP Address ของ Database Server
- ✅ หา IP Address ได้แล้ว

---

### ✅ ขั้นตอนที่เสร็จแล้ว (เพิ่มเติม)

#### 0.4 Setup Database Schema
- ✅ รัน `database.sql` สำเร็จ
- ✅ พบ 2 tables: `users`, `locations`

#### 0.6 ตั้งค่า Firewall
- ⏸️ เปิด System Preferences > Security & Privacy > Firewall
- ⏸️ ตรวจสอบว่า port 5432 เปิดอยู่

#### 0.7 ทดสอบ Remote Connection
- ⏸️ ทดสอบ port: `nc -zv <IP_ADDRESS> 5432`
- ⏸️ ทดสอบ connection: `psql -h <IP_ADDRESS> -U sheserved -d sheserved`

---

## สรุปความคืบหน้า

**✅ เสร็จสมบูรณ์: 7/7 ขั้นตอน (100%)**

- ✅ Phase 0.1: ติดตั้ง PostgreSQL
- ✅ Phase 0.2: ตั้งค่า Remote Connection
- ✅ Phase 0.3: สร้าง Database และ User
- ✅ Phase 0.4: Setup Database Schema (2 tables: users, locations)
- ✅ Phase 0.5: หา IP Address
- ✅ Phase 0.6: ตั้งค่า Firewall
- ✅ Phase 0.7: ทดสอบ Remote Connection

**🎉 Phase 0: Setup Database Server เสร็จสมบูรณ์แล้ว!**

---

## ขั้นตอนถัดไป (เรียงตามลำดับ)

### 1. ตรวจสอบ Database Schema (Phase 0.4)
```bash
# ตรวจสอบว่า tables ถูกสร้างแล้วหรือยัง
psql -U sheserved -d sheserved -c "\dt"

# ถ้ายังไม่มี tables ให้รัน schema
cd /Users/dave_macmini/tree_law_zoo/websocket-server
PGPASSWORD='<your_password>' psql -U sheserved -d sheserved -f database.sql
```

---

### 2. ตั้งค่า Firewall (Phase 0.6)
1. เปิด System Preferences > Security & Privacy > Firewall
2. คลิก "Firewall Options..."
3. ตรวจสอบว่า "Block all incoming connections" ไม่ได้ถูกเลือก
4. เพิ่ม PostgreSQL ในรายการ allowed apps (ถ้าจำเป็น)

---

### 4. ทดสอบ Remote Connection
```bash
# ทดสอบ port (เปลี่ยน IP เป็น IP address จริง)
nc -zv <IP_ADDRESS> 5432

# ทดสอบ connection (เปลี่ยน IP เป็น IP address จริง)
psql -h <IP_ADDRESS> -U sheserved -d sheserved
```

---

## ข้อมูลสำคัญ

- **Data Directory:** `/Volumes/PostgreSQL/postgresql-data`
- **Filesystem:** APFS
- **PostgreSQL Version:** 14.20
- **Port:** 5432
- **Database Name:** `sheserved`
- **Database User:** `dave_macmini`
- **IP Address:** 192.168.1.142 (เครื่องหลัก)

---

## Scripts ที่สร้างไว้

1. `format-to-apfs.sh` - Format external drive เป็น APFS ✅
2. `setup-postgresql-external-hfs.sh` - Setup PostgreSQL บน external drive ✅
3. `continue-postgresql-setup.sh` - สร้าง Database และ User ⏳
4. `find-ip-address.sh` - หา IP Address ⏳
5. `get-db-server-info.sh` - แสดงข้อมูล Database Server

---

## หมายเหตุ

- External drive (`/Volumes/PostgreSQL`) ต้อง mount อยู่เสมอ
- PostgreSQL ทำงานอยู่แล้ว (ตรวจสอบด้วย `psql -U dave_macmini -d postgres`)
- ใช้ username `dave_macmini` แทน `postgres` (macOS Homebrew)
