# คู่มือ Setup Database Server บน External Drive - ทีละขั้นตอน

## External Drive ที่พบ
- ✅ `/Volumes/Dave_1T` (931GB, เหลือ 582GB) - **แนะนำ**
- ⚠️ `/Volumes/Dave_240G` (เต็มแล้ว 100%)
- ❌ `/Volumes/DAVE_4G` (3.7GB - พื้นที่ไม่พอ)

---

## ขั้นตอนที่ 1: ติดตั้ง Homebrew

**รันคำสั่งนี้ใน Terminal:**

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**หลังจากติดตั้งเสร็จ (สำหรับ Apple Silicon):**

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**ตรวจสอบ:**
```bash
brew --version
```

---

## ขั้นตอนที่ 2: ติดตั้ง PostgreSQL@14

```bash
brew install postgresql@14
```

**เพิ่ม PostgreSQL ไปยัง PATH:**

```bash
echo 'export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"' >> ~/.zshrc
export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
```

**ตรวจสอบ:**
```bash
psql --version
```

---

## ขั้นตอนที่ 3: ตั้งค่า Data Directory บน External Drive

**เลือก External Drive:**
- แนะนำ: `/Volumes/Dave_1T` (มีพื้นที่เหลือ 582GB)

**3.1 หยุด PostgreSQL (ถ้ากำลังรันอยู่):**

```bash
brew services stop postgresql@14
```

**3.2 สร้าง data directory บน external drive:**

```bash
# ใช้ Dave_1T (แนะนำ)
EXTERNAL_DRIVE="/Volumes/Dave_1T"
mkdir -p "$EXTERNAL_DRIVE/postgresql-data"
```

**3.3 ตั้งค่า ownership:**

```bash
sudo chown -R $(whoami) "$EXTERNAL_DRIVE/postgresql-data"
```

**3.4 Initialize database cluster บน external drive:**

```bash
/opt/homebrew/opt/postgresql@14/bin/initdb -D "$EXTERNAL_DRIVE/postgresql-data"
```

**3.5 ตั้งค่า Environment Variable:**

```bash
# เพิ่มใน ~/.zshrc
echo "export PGDATA=$EXTERNAL_DRIVE/postgresql-data" >> ~/.zshrc
source ~/.zshrc
```

**ตรวจสอบ:**
```bash
echo $PGDATA
# ควรแสดง: /Volumes/Dave_1T/postgresql-data
```

---

## ขั้นตอนที่ 4: ตั้งค่า PostgreSQL ให้รับ Remote Connection

**4.1 แก้ไข postgresql.conf:**

```bash
nano "$PGDATA/postgresql.conf"
```

**แก้ไข:**
```conf
listen_addresses = '*'  # หรือ '0.0.0.0'
port = 5432
```

**4.2 แก้ไข pg_hba.conf:**

```bash
nano "$PGDATA/pg_hba.conf"
```

**เพิ่มบรรทัด (เลือกแบบที่เหมาะสม):**

```conf
# แบบที่ 1: อนุญาตทุก IP (ไม่แนะนำสำหรับ production)
host    all             all             0.0.0.0/0               md5

# แบบที่ 2: อนุญาตเฉพาะ network ของคุณ (แนะนำ)
host    all             all             192.168.1.0/24          md5
```

**4.3 Start PostgreSQL:**

```bash
# วิธีที่ 1: ใช้ brew services พร้อม environment variable
brew services start postgresql@14

# วิธีที่ 2: ใช้ pg_ctl โดยตรง
/opt/homebrew/opt/postgresql@14/bin/pg_ctl -D "$PGDATA" -l "$PGDATA/server.log" start
```

**ตรวจสอบ:**
```bash
brew services list
psql -U postgres -c "SHOW data_directory;"
```

---

## ขั้นตอนที่ 5: สร้าง Database และ User

```bash
psql -U postgres
```

**ใน psql prompt:**

```sql
-- สร้าง user สำหรับ remote access
CREATE USER sheserved WITH PASSWORD 'your_secure_password';

-- สร้าง database
CREATE DATABASE sheserved OWNER sheserved;

-- ให้สิทธิ์
GRANT ALL PRIVILEGES ON DATABASE sheserved TO sheserved;

-- ออกจาก psql
\q
```

---

## ขั้นตอนที่ 6: Setup Database Schema

```bash
cd /Users/dave_macmini/tree_law_zoo/websocket-server
psql -U sheserved -d sheserved -f database.sql
```

---

## ขั้นตอนที่ 7: หา IP Address

```bash
# วิธีที่ 1: ใช้ ipconfig (เฉพาะ interface en0 - Ethernet/WiFi)
ipconfig getifaddr en0

# วิธีที่ 2: ใช้ ifconfig
ifconfig | grep "inet " | grep -v 127.0.0.1

# วิธีที่ 3: ใช้ networksetup
networksetup -getinfo "Wi-Fi" | grep "IP address"
```

**บันทึก IP address นี้ไว้** - เครื่อง Client จะใช้เชื่อมต่อ

---

## ขั้นตอนที่ 8: ตั้งค่า Firewall

**วิธีที่ 1: ใช้ System Preferences (แนะนำ)**

1. เปิด System Preferences > Security & Privacy > Firewall
2. คลิก "Firewall Options..."
3. ตรวจสอบว่า "Block all incoming connections" ไม่ได้ถูกเลือก
4. เพิ่ม PostgreSQL (ถ้าจำเป็น) ในรายการ allowed apps

**วิธีที่ 2: ใช้ pfctl (Advanced)**

```bash
# ดู firewall rules ปัจจุบัน
sudo pfctl -s rules
```

---

## ขั้นตอนที่ 9: ทดสอบ Remote Connection

**จากเครื่อง Client (หรือเครื่องเดียวกัน):**

```bash
# ทดสอบ connection
psql -h <DB_SERVER_IP> -U sheserved -d sheserved

# หรือใช้ telnet/nc เพื่อทดสอบ port
nc -zv <DB_SERVER_IP> 5432
```

---

## ⚠️ หมายเหตุสำคัญสำหรับ External Drive

1. **External drive ต้อง mount อยู่เสมอ** - PostgreSQL จะไม่ start ถ้า data directory ไม่มี
2. **ตั้งค่า auto-mount external drive เมื่อ boot:**
   - System Preferences > Users & Groups > Login Items
   - เพิ่ม external drive ใน Login Items
3. **ใช้ external drive ที่เชื่อถือได้** - SSD ดีกว่า HDD
4. **Backup ข้อมูลเป็นประจำ** - external drive อาจเสียหายหรือหลุดได้
5. **ตรวจสอบ disk space** - ใช้ `df -h` เป็นประจำ
6. **Performance** - อาจช้ากว่า internal drive (ขึ้นอยู่กับ connection type)

---

## 📋 Checklist

- [ ] ขั้นตอนที่ 1: ติดตั้ง Homebrew
- [ ] ขั้นตอนที่ 2: ติดตั้ง PostgreSQL@14
- [ ] ขั้นตอนที่ 3: ตั้งค่า Data Directory บน External Drive
- [ ] ขั้นตอนที่ 4: ตั้งค่า Remote Connection
- [ ] ขั้นตอนที่ 5: สร้าง Database และ User
- [ ] ขั้นตอนที่ 6: Setup Database Schema
- [ ] ขั้นตอนที่ 7: หา IP Address
- [ ] ขั้นตอนที่ 8: ตั้งค่า Firewall
- [ ] ขั้นตอนที่ 9: ทดสอบ Remote Connection

---

## 📝 สรุปข้อมูลสำหรับเครื่อง Client

หลังจาก setup เสร็จ ให้บันทึกข้อมูลนี้ไว้:

```
DB_HOST=<IP_ADDRESS>
DB_NAME=sheserved
DB_USER=sheserved
DB_PASSWORD=<password ที่ตั้งไว้>
DB_PORT=5432
```
