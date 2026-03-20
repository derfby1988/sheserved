# คู่มือการตั้งค่า Database Server (เครื่องหลัก)

## ภาพรวม

คู่มือนี้สำหรับ **Database Server (เครื่องหลัก)** ที่จะให้เครื่องอื่นเชื่อมต่อมาใช้ database

**หมายเหตุ:** 
- ทำที่เครื่อง Database Server เท่านั้น (ทำครั้งเดียว)
- เครื่องนี้จะให้ Client Machines เชื่อมต่อมาใช้ database ร่วมกัน
- หลัง setup เสร็จ ต้องแจ้ง IP address, username, password ให้ Client machines

---

## Prerequisites

ก่อนเริ่มต้น ต้องมี:

1. **macOS** (เครื่องหลักเป็น macOS)
2. **Homebrew** ติดตั้งแล้ว
3. **External Drive** (optional - สำหรับเก็บ database)

---

## Phase 0: Setup Database Server

### 0.1 ติดตั้ง PostgreSQL

#### 0.1.1 ติดตั้ง PostgreSQL

```bash
# ติดตั้ง PostgreSQL
brew install postgresql@14
```

#### 0.1.2 ตั้งค่า Data Directory บน External Drive (Optional)

**สำหรับ macOS (Homebrew):**

```bash
# 1. หยุด PostgreSQL (ถ้ากำลังรันอยู่)
brew services stop postgresql@14

# 2. สร้าง data directory บน external drive
# ตัวอย่าง: external drive mount ที่ /Volumes/ExternalDrive
mkdir -p /Volumes/ExternalDrive/postgresql-data

# 3. ตั้งค่า ownership
sudo chown -R $(whoami) /Volumes/ExternalDrive/postgresql-data

# 4. Initialize database cluster บน external drive
/opt/homebrew/opt/postgresql@14/bin/initdb -D /Volumes/ExternalDrive/postgresql-data

# 5. แก้ไข postgresql.conf เพื่อชี้ไปที่ external drive
# ไฟล์: /Volumes/ExternalDrive/postgresql-data/postgresql.conf
```

**หมายเหตุ:** ตัวอย่างนี้สำหรับ macOS เท่านั้น

#### 0.1.3 ตั้งค่า Environment Variable (macOS)

```bash
# วิธีที่ 1: เพิ่มใน ~/.zshrc
echo 'export PGDATA=/Volumes/ExternalDrive/postgresql-data' >> ~/.zshrc
source ~/.zshrc

# วิธีที่ 2: ใช้ brew services พร้อม environment variable
brew services start postgresql@14 --env="PGDATA=/Volumes/ExternalDrive/postgresql-data"

# วิธีที่ 3: สร้าง plist file สำหรับ launchd (แนะนำสำหรับ production)
# สร้างไฟล์: ~/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist
# และเพิ่ม Environment variable ใน plist
```

#### 0.1.4 Start PostgreSQL

```bash
# Start PostgreSQL
brew services start postgresql@14
```

**ตรวจสอบ (macOS):**

```bash
psql --version
brew services list

# ตรวจสอบ data directory location
psql -U postgres -c "SHOW data_directory;"

# ตรวจสอบ external drive mount (ถ้าใช้)
df -h | grep ExternalDrive
```

**หมายเหตุสำคัญ:**

- External drive ต้อง mount อยู่เสมอ (PostgreSQL ต้องการ data directory)
- ใช้ external drive ที่เชื่อถือได้ (SSD ดีกว่า HDD)
- ตั้งค่า auto-mount external drive เมื่อ boot
- Backup ข้อมูลเป็นประจำ (external drive อาจเสียหายได้)
- Performance อาจช้ากว่า internal drive (ขึ้นอยู่กับ connection type: USB 3.0, Thunderbolt, etc.)

---

### 0.2 ตั้งค่า PostgreSQL ให้รับ Remote Connection

**หมายเหตุ:** ถ้าใช้ external drive, ไฟล์ config จะอยู่ใน data directory บน external drive

**แก้ไข `postgresql.conf` (macOS):**

```bash
# หาไฟล์ postgresql.conf
# Default: /opt/homebrew/var/postgresql@14/postgresql.conf
# External drive: /Volumes/ExternalDrive/postgresql-data/postgresql.conf

# แก้ไข:
listen_addresses = '*'  # หรือ '0.0.0.0'
port = 5432
```

**แก้ไข `pg_hba.conf` (macOS):**

```bash
# หาไฟล์ pg_hba.conf (อยู่ใน data directory เดียวกับ postgresql.conf)
# Default: /opt/homebrew/var/postgresql@14/pg_hba.conf
# External drive: /Volumes/ExternalDrive/postgresql-data/pg_hba.conf

# เพิ่มบรรทัด (เลือกแบบที่เหมาะสม):
# แบบที่ 1: อนุญาตทุก IP (ไม่แนะนำสำหรับ production)
host    all             all             0.0.0.0/0               md5

# แบบที่ 2: อนุญาตเฉพาะ network ของคุณ (แนะนำ)
host    all             all             192.168.1.0/24          md5
```

**Restart PostgreSQL (macOS):**

```bash
brew services restart postgresql@14
```

---

### 0.3 สร้าง Database และ User

```bash
# เข้าสู่ PostgreSQL
psql -U postgres

# สร้าง user สำหรับ remote access
CREATE USER sheserved WITH PASSWORD 'your_secure_password';

# สร้าง database
CREATE DATABASE sheserved OWNER sheserved;

# ให้สิทธิ์
GRANT ALL PRIVILEGES ON DATABASE sheserved TO sheserved;

# ออกจาก psql
\q
```

**บันทึกข้อมูลนี้ไว้:**
- Username: `sheserved`
- Password: `your_secure_password` (ที่ตั้งไว้)
- Database: `sheserved`

---

### 0.4 Setup Database Schema

```bash
# Clone repository (ถ้ายังไม่มี)
git clone <repository-url>
cd tree_law_zoo/websocket-server

# รัน schema
psql -U sheserved -d sheserved -f database.sql
```

---

### 0.5 หา IP Address ของ Database Server (macOS)

```bash
# วิธีที่ 1: ใช้ ifconfig
ifconfig | grep "inet " | grep -v 127.0.0.1

# วิธีที่ 2: ใช้ ipconfig (เฉพาะ interface en0 - Ethernet/WiFi)
ipconfig getifaddr en0

# วิธีที่ 3: ใช้ networksetup
networksetup -getinfo "Wi-Fi" | grep "IP address"
```

**บันทึก IP address นี้ไว้** - เครื่อง Client จะใช้เชื่อมต่อ

**ตัวอย่าง:** `192.168.1.100`

**แจ้งข้อมูลต่อไปนี้ให้ Client Machines:**
- IP Address: `192.168.1.100` (ตัวอย่าง)
- Database Name: `sheserved`
- Username: `sheserved`
- Password: `your_secure_password`
- Port: `5432`

---

### 0.6 ตั้งค่า Firewall (macOS)

**วิธีที่ 1: ใช้ System Preferences (แนะนำ)**

1. เปิด System Preferences > Security & Privacy > Firewall
2. คลิก "Firewall Options..."
3. ตรวจสอบว่า "Block all incoming connections" ไม่ได้ถูกเลือก
4. เพิ่ม PostgreSQL (ถ้าจำเป็น) ในรายการ allowed apps

**วิธีที่ 2: ใช้ pfctl (Advanced)**

```bash
# ดู firewall rules ปัจจุบัน
sudo pfctl -s rules

# เพิ่ม rule สำหรับ PostgreSQL (ถ้าจำเป็น)
# แก้ไขไฟล์: /etc/pf.conf
```

**หมายเหตุ:** macOS Firewall มักจะอนุญาต outgoing connections โดยอัตโนมัติ ดังนั้น Client machines ควรเชื่อมต่อไปที่ Database Server ได้

---

### 0.7 ทดสอบ Remote Connection

**ทดสอบจากเครื่อง Client:**

```bash
# จากเครื่อง Client ทดสอบ:
psql -h <DB_SERVER_IP> -U sheserved -d sheserved
# ใส่ password ที่ตั้งไว้

# หรือใช้ telnet/nc เพื่อทดสอบ port
nc -zv <DB_SERVER_IP> 5432
```

---

## Checklist สำหรับ Database Server

### Prerequisites

- [ ] macOS ติดตั้งแล้ว
- [ ] Homebrew ติดตั้งแล้ว
- [ ] External Drive (optional) พร้อมใช้งาน

### PostgreSQL Installation

- [ ] PostgreSQL ติดตั้งแล้ว (`brew install postgresql@14`)
- [ ] External Drive setup (optional) - data directory บน external drive
- [ ] Environment variable ตั้งค่าแล้ว (ถ้าใช้ external drive)
- [ ] PostgreSQL start สำเร็จ (`brew services start postgresql@14`)

### Remote Access Configuration

- [ ] ตั้งค่า `postgresql.conf` ให้รับ remote connection (`listen_addresses = '*'`)
- [ ] ตั้งค่า `pg_hba.conf` ให้อนุญาต remote access
- [ ] Restart PostgreSQL สำเร็จ

### Database Setup

- [ ] สร้าง user `sheserved` สำเร็จ
- [ ] สร้าง database `sheserved` สำเร็จ
- [ ] Setup database schema สำเร็จ (`database.sql`)
- [ ] ทดสอบ local connection สำเร็จ

### Network Configuration

- [ ] หา IP address ของ Database Server
- [ ] ตั้งค่า firewall (ถ้าจำเป็น)
- [ ] ทดสอบ remote connection จากเครื่อง Client สำเร็จ

### Information Sharing

- [ ] แจ้ง IP address ให้ Client machines
- [ ] แจ้ง username และ password ให้ Client machines
- [ ] แจ้ง database name และ port ให้ Client machines

---

## Troubleshooting

### PostgreSQL Issues

**ปัญหา: PostgreSQL ไม่ start**

- ตรวจสอบ service: `brew services list`
- ตรวจสอบ log: `brew services info postgresql@14`
- ตรวจสอบ external drive mount (ถ้าใช้): `df -h | grep ExternalDrive`
- ตรวจสอบ permissions: `ls -la /path/to/data/directory`

**ปัญหา: PostgreSQL ไม่ start (External Drive)**

- ตรวจสอบ external drive mount อยู่: `df -h`
- ตรวจสอบ data directory มีอยู่และ accessible
- ตรวจสอบ permissions: `ls -la /path/to/data/directory`
- ตรวจสอบ PostgreSQL log สำหรับ error messages
- macOS: ตรวจสอบ external drive mount:
  - System Preferences > Disk Utility
  - หรือ `diskutil list`
  - หรือ `df -h | grep ExternalDrive`
- ตั้งค่า auto-mount external drive:
  - System Preferences > Users & Groups > Login Items
  - เพิ่ม external drive ใน Login Items

### Remote Connection Issues

**ปัญหา: Client machines ไม่สามารถเชื่อมต่อได้**

- ตรวจสอบ PostgreSQL กำลังรัน: `brew services list`
- ตรวจสอบ `postgresql.conf`: `listen_addresses = '*'`
- ตรวจสอบ `pg_hba.conf`: มี rule สำหรับ remote access
- ตรวจสอบ firewall: System Preferences > Security & Privacy > Firewall
- ตรวจสอบ IP address ถูกต้อง
- ทดสอบ local connection: `psql -U sheserved -d sheserved`

**ปัญหา: Connection timeout**

- ตรวจสอบ network connectivity
- ตรวจสอบ firewall rules
- ตรวจสอบ PostgreSQL log: `tail -f /opt/homebrew/var/postgresql@14/server.log`
- หรือถ้าใช้ external drive: `tail -f /Volumes/ExternalDrive/postgresql-data/server.log`

### Database Issues

**ปัญหา: Database not found**

```bash
# สร้าง database ใหม่
psql -U postgres
CREATE DATABASE sheserved;
\q
```

**ปัญหา: User not found**

```bash
# สร้าง user ใหม่
psql -U postgres
CREATE USER sheserved WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE sheserved TO sheserved;
\q
```

---

## Security Considerations

### สำหรับ Production:

1. **ใช้ Strong Password:**
   - ใช้ password ที่ซับซ้อนสำหรับ database user
   - เปลี่ยน default password

2. **Network Security:**
   - ใช้ VPN หรือ SSH tunnel สำหรับ remote access
   - จำกัด IP addresses ที่อนุญาตใน `pg_hba.conf`
   - ใช้ SSL/TLS connection

3. **Firewall:**
   - เปิดเฉพาะ port ที่จำเป็น
   - ใช้ firewall rules ที่จำกัดเฉพาะ network ที่ต้องการ

4. **Database User:**
   - สร้าง user เฉพาะสำหรับ application (ไม่ใช้ postgres user)
   - ให้สิทธิ์เฉพาะที่จำเป็น (principle of least privilege)

---

## สรุป

**ความยาก:** ⭐⭐⭐ (ปานกลาง-ยาก)

**เวลาที่ใช้:** ประมาณ 30-45 นาที

**สิ่งที่ต้องทำ:**

1. ติดตั้ง PostgreSQL
2. ตั้งค่า remote access (postgresql.conf, pg_hba.conf)
3. สร้าง database และ user
4. Setup database schema
5. ตั้งค่า firewall
6. หา IP address และแจ้งให้ Client machines

**สิ่งที่ต้องแจ้งให้ Client Machines:**

- IP Address ของ Database Server
- Database Name: `sheserved`
- Username: `sheserved`
- Password: (ที่ตั้งไว้)
- Port: `5432`

---

## ดูเพิ่มเติม

- [SETUP_NEW_MACHINE.md](SETUP_NEW_MACHINE.md) - คู่มือสำหรับ Client Machine
- [websocket-server/README.md](websocket-server/README.md) - WebSocket Server documentation
- [websocket-server/database.sql](websocket-server/database.sql) - Database schema
