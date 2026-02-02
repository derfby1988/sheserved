# คู่มือการตั้งค่าเครื่องใหม่ (Setup Guide for New Machine)

## ภาพรวม

คู่มือนี้ครอบคลุมการตั้งค่าทั้งหมดที่ต้องทำหลังจาก clone repository จาก GitHub เพื่อให้เครื่องใหม่สามารถรัน Flutter app และ WebSocket server ได้

**หมายเหตุ:** คู่มือนี้แบ่งเป็น 2 ส่วน:

1. **Setup Database Server** - ทำที่เครื่องหลัก (เครื่องที่มี Database)
2. **Setup Client Machine** - ทำที่เครื่องอื่น (เครื่องที่ clone repository)

## สิ่งที่ต้อง Setup

### สำหรับ Database Server (เครื่องหลัก - ทำครั้งเดียว)

1. PostgreSQL installation และ configuration
2. Database schema setup
3. Network configuration (ให้เครื่องอื่นเชื่อมต่อได้)
4. Firewall/Security settings
5. สร้าง database user สำหรับ remote access

### สำหรับ Client Machine (เครื่องอื่น - ทำทุกเครื่อง)

1. Flutter App (Frontend)

   - Flutter SDK
   - Dependencies (pubspec.yaml)
   - Platform-specific setup (Android/iOS/macOS)
   - Java 17 สำหรับ Android build (macOS)

2. WebSocket Server (Backend)

   - Node.js และ npm
   - Dependencies (package.json)
   - Environment variables (.env) - ชี้ไปที่ Remote Database
   - **ไม่ต้องติดตั้ง PostgreSQL** (เชื่อมต่อไปที่ Remote Database)

3. Remote Database Connection

   - ตั้งค่า `.env` ให้ชี้ไปที่ Database Server IP
   - ทดสอบ connection

---

## ขั้นตอนการ Setup

> **สำคัญ:** เลือกส่วนที่เหมาะสมกับเครื่องของคุณ

> - ถ้าเป็น **Database Server** → ทำ Phase 0 เท่านั้น

> - ถ้าเป็น **Client Machine** → ข้าม Phase 0 ไปทำ Phase 1-4

---

## Phase 0: Setup Database Server (เครื่องหลัก - ทำครั้งเดียว)

> **ทำที่เครื่อง Database Server เท่านั้น** - เครื่องนี้จะให้เครื่องอื่นเชื่อมต่อมาใช้ database

### 0.1 ติดตั้ง PostgreSQL

#### 0.1.1 ติดตั้ง PostgreSQL

```bash
# macOS
brew install postgresql@14

# Linux (Ubuntu/Debian)
sudo apt-get install postgresql postgresql-contrib

# Windows
# Download installer from https://www.postgresql.org/download/windows/
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
# หรือใช้ symbolic link
```

**หมายเหตุ:** ตัวอย่างนี้สำหรับ macOS เท่านั้น (เครื่องหลักเป็น macOS)

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
# macOS
brew services start postgresql@14

# Linux
sudo systemctl start postgresql
sudo systemctl enable postgresql  # Auto-start on boot
```

**ตรวจสอบ (macOS):**

```bash
psql --version
brew services list

# ตรวจสอบ data directory location
psql -U postgres -c "SHOW data_directory;"

# ตรวจสอบ external drive mount
df -h | grep ExternalDrive
```

**หมายเหตุสำคัญ:**

- External drive ต้อง mount อยู่เสมอ (PostgreSQL ต้องการ data directory)
- ใช้ external drive ที่เชื่อถือได้ (SSD ดีกว่า HDD)
- ตั้งค่า auto-mount external drive เมื่อ boot
- Backup ข้อมูลเป็นประจำ (external drive อาจเสียหายได้)
- Performance อาจช้ากว่า internal drive (ขึ้นอยู่กับ connection type: USB 3.0, Thunderbolt, etc.)

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

### 0.4 Setup Database Schema

```bash
# Clone repository (ถ้ายังไม่มี)
git clone <repository-url>
cd tree_law_zoo/websocket-server

# รัน schema
psql -U sheserved -d sheserved -f database.sql
```

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

### 0.7 ทดสอบ Remote Connection (จากเครื่อง Client - macOS)

```bash
# จากเครื่อง Client ทดสอบ:
psql -h <DB_SERVER_IP> -U sheserved -d sheserved
# ใส่ password ที่ตั้งไว้

# หรือใช้ telnet/nc เพื่อทดสอบ port
nc -zv <DB_SERVER_IP> 5432
```

---

## Phase 1: Prerequisites Installation (Client Machine)

#### 1.1 Flutter SDK (macOS)

```bash
# ติดตั้ง Flutter
brew install flutter

# หรือ download จาก https://docs.flutter.dev/get-started/install/macos
# Extract และเพิ่ม PATH ใน ~/.zshrc:
# export PATH="$PATH:/path/to/flutter/bin"
```

**ตรวจสอบ:**

```bash
flutter doctor
flutter doctor --android-licenses  # ถ้าต้องการ build Android
```

#### 1.2 Node.js และ npm (macOS)

```bash
# ติดตั้ง Node.js
brew install node
```

**ตรวจสอบ:**

```bash
node --version  # ควรเป็น v14 หรือสูงกว่า
npm --version
```

#### 1.3 PostgreSQL Client (Optional - สำหรับ Client)

**สำหรับ Client Machine:**

- **ไม่ต้องติดตั้ง PostgreSQL Server** (เชื่อมต่อไปที่ Remote Database)
- **ติดตั้ง `psql` client เท่านั้น** (ถ้าต้องการทดสอบ connection)
```bash
# macOS - ติดตั้ง PostgreSQL client only
brew install libpq
brew link --force libpq

# Linux - ติดตั้ง client only
sudo apt-get install postgresql-client

# Windows
# Download และติดตั้ง PostgreSQL (เลือกเฉพาะ client tools)
```


**ตรวจสอบ:**

```bash
psql --version
```

**หมายเหตุ:** ถ้าไม่ต้องการใช้ `psql` command line ก็ไม่ต้องติดตั้ง - WebSocket server จะเชื่อมต่อผ่าน Node.js library

#### 1.4 Java 17 (สำหรับ Android build - macOS)

```bash
# ติดตั้ง Java 17
brew install openjdk@17

# ตรวจสอบ path (จะใช้ใน gradle.properties)
ls -la /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

---

### Phase 2: Repository Setup

#### 2.1 Clone Repository

```bash
git clone <repository-url>
cd tree_law_zoo
```

#### 2.2 ตรวจสอบ Branch

```bash
git branch
git checkout main  # หรือ branch ที่ต้องการ
```

---

### Phase 3: Flutter App Setup

#### 3.1 Install Flutter Dependencies

```bash
cd /path/to/tree_law_zoo
flutter pub get
```

#### 3.2 Android Setup (macOS)

```bash
# ตั้งค่า Java 17 ใน gradle.properties
# ไฟล์: android/gradle.properties
# เพิ่มบรรทัด:
org.gradle.java.home=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

**ตรวจสอบ:**

```bash
flutter doctor --android-licenses
```

#### 3.3 iOS Setup (macOS เท่านั้น)

```bash
cd ios
pod install
cd ..
```

#### 3.4 macOS Setup (macOS เท่านั้น)

```bash
cd macos
pod install
cd ..
```

#### 3.5 Test Flutter App (macOS)

```bash
# Web
flutter run -d chrome

# Android (ต้องมี emulator หรือ device)
flutter run -d android

# iOS
flutter run -d ios

# macOS
flutter run -d macos
```

---

### Phase 4: WebSocket Server Setup

#### 4.1 Install Node.js Dependencies

```bash
cd websocket-server
npm install
```

#### 4.2 สร้างไฟล์ .env

```bash
# สร้างไฟล์ .env จาก template
cp .env.example .env  # ถ้ามี
# หรือสร้างใหม่
```

**เนื้อหาไฟล์ `.env` (Client Machine):**

```env
# Database Configuration - ชี้ไปที่ Remote Database Server
# ⚠️ เปลี่ยนค่าเหล่านี้ให้ตรงกับ Database Server
DB_HOST=192.168.1.100  # IP address ของเครื่อง Database Server (จาก Phase 0.5)
DB_NAME=sheserved
DB_USER=sheserved  # User ที่สร้างที่ Database Server (จาก Phase 0.3)
DB_PASSWORD=your_secure_password  # Password ที่ตั้งไว้ที่ Database Server
DB_PORT=5432

# Server Configuration
PORT=3000

# JWT (สำหรับอนาคต)
JWT_SECRET=your_super_secret_key_change_this_in_production
JWT_EXPIRES_IN=7d

# Social Login (สำหรับอนาคต)
GOOGLE_CLIENT_ID=your_google_client_id
FACEBOOK_APP_ID=your_facebook_app_id
FACEBOOK_APP_SECRET=your_facebook_app_secret
```

**สำคัญ:**

- `DB_HOST` = IP address ของ Database Server (ถามจากคนที่ setup Database Server)
- `DB_USER` และ `DB_PASSWORD` = ข้อมูลจาก Database Server (Phase 0.3)

#### 4.3 ทดสอบ Remote Database Connection

**ไม่ต้อง setup database ที่เครื่อง Client** - Database อยู่ที่ Database Server แล้ว

**ทดสอบ connection:**

```bash
# ถ้าติดตั้ง psql client
psql -h <DB_SERVER_IP> -U sheserved -d sheserved

# หรือทดสอบผ่าน Node.js
cd websocket-server
node -e "const {Pool}=require('pg');const p=new Pool({host:process.env.DB_HOST,user:process.env.DB_USER,password:process.env.DB_PASSWORD,database:process.env.DB_NAME,port:process.env.DB_PORT});p.query('SELECT NOW()').then(r=>{console.log('✅ Connected:',r.rows[0]);p.end()}).catch(e=>{console.error('❌ Error:',e.message);process.exit(1)})"
```

**หมายเหตุ:** Database setup ทำที่ Database Server เท่านั้น (Phase 0.4)

**สำหรับเครื่อง Database Server:**

**ขั้นตอนที่ 1: ตั้งค่า PostgreSQL ให้รับ Remote Connection**

**macOS/Linux - แก้ไข `postgresql.conf`:**

```bash
# หาไฟล์ postgresql.conf
# macOS: /opt/homebrew/var/postgresql@14/postgresql.conf
# Linux: /etc/postgresql/14/main/postgresql.conf

# แก้ไข:
listen_addresses = '*'  # หรือ '0.0.0.0'
port = 5432
```

**macOS/Linux - แก้ไข `pg_hba.conf`:**

```bash
# หาไฟล์ pg_hba.conf
# macOS: /opt/homebrew/var/postgresql@14/pg_hba.conf
# Linux: /etc/postgresql/14/main/pg_hba.conf

# เพิ่มบรรทัด:
host    all             all             0.0.0.0/0               md5
# หรือเฉพาะ network ของคุณ:
host    all             all             192.168.1.0/24          md5
```

**Restart PostgreSQL:**

```bash
# macOS
brew services restart postgresql@14

# Linux
sudo systemctl restart postgresql
```

**ขั้นตอนที่ 2: สร้าง Database และ User**

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

**ขั้นตอนที่ 3: Setup Schema**

```bash
# รัน schema
psql -U sheserved -d sheserved -f websocket-server/database.sql
```

**ขั้นตอนที่ 4: ตั้งค่า Firewall (ถ้าจำเป็น)**

**macOS:**

```bash
# เปิด port 5432
sudo pfctl -f /etc/pf.conf
# หรือใช้ System Preferences > Security & Privacy > Firewall
```

**Linux (UFW):**

```bash
sudo ufw allow 5432/tcp
sudo ufw reload
```

**Linux (firewalld):**

```bash
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
```

**สำหรับเครื่องอื่น (Client):**

- **ไม่ต้อง setup database** - แค่ตั้งค่า `.env` ให้ชี้ไปที่ remote database
- **ทดสอบ connection:**
```bash
psql -h <DB_SERVER_IP> -U sheserved -d sheserved
```


#### 4.4 Test WebSocket Server

```bash
# Start server
npm start

# หรือใช้ script
chmod +x start.sh
./start.sh

# ตรวจสอบ health
curl http://localhost:3000/health
```

---

### Phase 5: Configuration Files ที่ต้องสร้าง/แก้ไข

#### 5.1 Flutter App

- **ไม่ต้องสร้างไฟล์ใหม่** - ทุกอย่างอยู่ใน repo แล้ว
- **ตรวจสอบ:** `lib/main.dart` ใช้ route `/login` ถูกต้อง

#### 5.2 WebSocket Server

- **ต้องสร้าง:** `websocket-server/.env` (ไม่ควร commit)
- **ตรวจสอบ:** `websocket-server/server.js` มี logic ที่ถูกต้อง

#### 5.3 Android Build

- **ต้องแก้ไข:** `android/gradle.properties` (เพิ่ม Java 17 path)
- **ตรวจสอบ:** Java version ตรงกับที่ตั้งค่า

---

## Checklist สำหรับเครื่องใหม่

### Prerequisites (Client Machine)

- [ ] Flutter SDK ติดตั้งแล้ว (`flutter doctor`)
- [ ] Node.js และ npm ติดตั้งแล้ว
- [ ] PostgreSQL client ติดตั้งแล้ว (optional - สำหรับทดสอบ)
- [ ] Java 17 ติดตั้งแล้ว (สำหรับ Android build)
- [ ] มีข้อมูล Database Server (IP address, username, password)

### Repository

- [ ] Clone repository สำเร็จ
- [ ] อยู่ใน branch ที่ถูกต้อง

### Flutter App

- [ ] `flutter pub get` สำเร็จ
- [ ] Android: ตั้งค่า Java 17 ใน `gradle.properties`
- [ ] iOS: `pod install` สำเร็จ
- [ ] macOS: `pod install` สำเร็จ
- [ ] Test run สำเร็จ (`flutter run -d chrome`)

### WebSocket Server (Client Machine)

- [ ] `npm install` สำเร็จ
- [ ] สร้างไฟล์ `.env` พร้อมค่าที่ถูกต้อง (ชี้ไปที่ Remote DB Server)
- [ ] ทดสอบ connection ไปยัง Remote Database สำเร็จ
- [ ] Server start สำเร็จ (`npm start`)
- [ ] Health check ผ่าน (`curl http://localhost:3000/health`)

### Remote Database Server (เครื่องหลัก)

- [ ] PostgreSQL ติดตั้งและรันอยู่
- [ ] ตั้งค่า `postgresql.conf` ให้รับ remote connection
- [ ] ตั้งค่า `pg_hba.conf` ให้อนุญาต remote access
- [ ] สร้าง database และ user สำหรับ remote access
- [ ] Setup database schema สำเร็จ
- [ ] Firewall เปิด port 5432 (ถ้าจำเป็น)
- [ ] ทดสอบ remote connection จากเครื่องอื่นสำเร็จ

---

## Troubleshooting

### Flutter Issues

**ปัญหา: Flutter doctor แสดง errors**

```bash
flutter doctor -v  # ดูรายละเอียด
flutter doctor --android-licenses  # สำหรับ Android
```

**ปัญหา: Android build fails - Java version**

- ตรวจสอบ `android/gradle.properties` มี Java 17 path
- ตรวจสอบ Java version: `java -version`

**ปัญหา: iOS build fails (macOS)**

```bash
cd ios
pod deintegrate
pod install
cd ..
```

**ปัญหา: macOS build fails**

```bash
cd macos
pod deintegrate
pod install
cd ..
```

### WebSocket Server Issues

**ปัญหา: Cannot connect to remote database**

**สำหรับเครื่อง Client:**

- ตรวจสอบ `DB_HOST` ใน `.env` ถูกต้อง (IP address ของ Database Server)
- ตรวจสอบ network connectivity: `ping <DB_SERVER_IP>`
- ตรวจสอบ credentials ใน `.env`
- ทดสอบ connection: `psql -h <DB_SERVER_IP> -U <DB_USER> -d <DB_NAME>`

**สำหรับเครื่อง Database Server:**

- ตรวจสอบ PostgreSQL กำลังรัน: `brew services list` (macOS) หรือ `sudo systemctl status postgresql` (Linux)
- ตรวจสอบ `postgresql.conf`: `listen_addresses = '*'`
- ตรวจสอบ `pg_hba.conf`: มี rule สำหรับ remote access
- ตรวจสอบ firewall: port 5432 เปิดอยู่
- ตรวจสอบ database และ user มีอยู่: `psql -U postgres -c "\du"` และ `psql -U postgres -l`

**ปัญหา: Port 3000 already in use**

```bash
# macOS/Linux
lsof -ti:3000 | xargs kill -9

# หรือใช้ script
cd websocket-server
./kill-server.sh
```

**ปัญหา: npm install fails**

```bash
rm -rf node_modules package-lock.json
npm install
```

### Database Issues

**ปัญหา: Permission denied**

- ตรวจสอบ PostgreSQL user และ password
- macOS: อาจไม่ต้องใช้ password (ใช้ system user)

**ปัญหา: Database not found**

```bash
# สร้าง database ใหม่ (ที่เครื่อง Database Server)
psql -U postgres
CREATE DATABASE sheserved;
\q

# รัน schema
psql -U sheserved -d sheserved -f websocket-server/database.sql
```

**ปัญหา: Connection timeout / Connection refused**

- ตรวจสอบ Database Server กำลังรันอยู่
- ตรวจสอบ IP address ถูกต้อง
- ตรวจสอบ firewall บน Database Server
- ตรวจสอบ network (LAN/WAN) connectivity
- ตรวจสอบ PostgreSQL log (macOS): 
  - `brew services info postgresql@14`
  - หรือดู log ใน data directory: `tail -f /opt/homebrew/var/postgresql@14/server.log`
  - หรือถ้าใช้ external drive: `tail -f /Volumes/ExternalDrive/postgresql-data/server.log`

**ปัญหา: PostgreSQL ไม่ start (External Drive)**

- ตรวจสอบ external drive mount อยู่: `df -h` (macOS/Linux)
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
  - หรือใช้ `defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true`

---

## Remote Database Server Setup (เครื่องหลัก)

### Phase 0: Setup Database Server (ทำครั้งเดียวที่เครื่องหลัก)

#### 0.1 ติดตั้ง PostgreSQL

```bash
# macOS
brew install postgresql@14
brew services start postgresql@14

# Linux
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql
```

#### 0.2 ตั้งค่า Remote Access

**แก้ไข postgresql.conf:**

```bash
# macOS
nano /opt/homebrew/var/postgresql@14/postgresql.conf

# Linux
sudo nano /etc/postgresql/14/main/postgresql.conf

# เปลี่ยน:
listen_addresses = '*'
```

**แก้ไข pg_hba.conf:**

```bash
# macOS
nano /opt/homebrew/var/postgresql@14/pg_hba.conf

# Linux
sudo nano /etc/postgresql/14/main/pg_hba.conf

# เพิ่มบรรทัด:
host    all             all             0.0.0.0/0               md5
```

**Restart PostgreSQL:**

```bash
# macOS
brew services restart postgresql@14

# Linux
sudo systemctl restart postgresql
```

#### 0.3 สร้าง Database และ User

```bash
psql -U postgres

CREATE USER sheserved WITH PASSWORD 'your_secure_password';
CREATE DATABASE sheserved OWNER sheserved;
GRANT ALL PRIVILEGES ON DATABASE sheserved TO sheserved;
\q
```

#### 0.4 Setup Schema

```bash
cd websocket-server
psql -U sheserved -d sheserved -f database.sql
```

#### 0.5 หา IP Address

```bash
# macOS/Linux
ifconfig | grep "inet " | grep -v 127.0.0.1

# หรือ
hostname -I  # Linux
ipconfig getifaddr en0  # macOS
```

**บันทึก IP address นี้ไว้** - เครื่องอื่นจะใช้เชื่อมต่อ

#### 0.6 ตั้งค่า Firewall (ถ้าจำเป็น)

```bash
# macOS - ใช้ System Preferences
# Linux (UFW)
sudo ufw allow 5432/tcp
sudo ufw reload
```

---

## Quick Start Script (สำหรับ macOS - Client Machine)

สร้างไฟล์ `setup-new-machine.sh`:

```bash
#!/bin/bash

echo "🚀 Starting setup for new machine..."

# 1. Flutter dependencies
echo "📦 Installing Flutter dependencies..."
flutter pub get

# 2. iOS pods (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Installing iOS pods..."
    cd ios && pod install && cd ..
fi

# 3. macOS pods (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "💻 Installing macOS pods..."
    cd macos && pod install && cd ..
fi

# 4. WebSocket server dependencies
echo "🔌 Installing WebSocket server dependencies..."
cd websocket-server
npm install

# 5. Setup database
echo "🗄️  Setting up database..."
chmod +x setup-database-simple.sh
./setup-database-simple.sh

# 6. Create .env if not exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file..."
    echo "⚠️  Please enter Remote Database Server information:"
    read -p "DB Server IP (from Database Server admin): " db_host
    read -p "DB User (default: sheserved): " db_user
    read -sp "DB Password: " db_password
    echo ""
    
    cat > .env << EOF
DB_HOST=${db_host:-localhost}
DB_NAME=sheserved
DB_USER=${db_user:-sheserved}
DB_PASSWORD=${db_password}
DB_PORT=5432
PORT=3000
JWT_SECRET=change_this_in_production
JWT_EXPIRES_IN=7d
EOF
    echo "✅ Created .env file. Please verify the values."
fi

cd ..

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Verify websocket-server/.env points to Remote Database Server"
echo "2. Test database connection:"
echo "   psql -h <DB_SERVER_IP> -U sheserved -d sheserved"
echo "3. Start WebSocket server: cd websocket-server && npm start"
echo "4. Run Flutter app: flutter run -d chrome"
echo ""
echo "⚠️  Make sure Database Server is running and accessible!"
```

---

## สถาปัตยกรรม Remote Database

```
┌─────────────────────┐         ┌──────────────────────┐
│  เครื่องที่ 1        │         │  เครื่อง Database     │
│  (Client)           │         │  Server              │
│                     │         │                      │
│  Flutter App        │         │  PostgreSQL          │
│  WebSocket Server   │────────▶│  Port: 5432          │
│                     │ Network │  Database: tree_law_ │
│  .env:              │         │  User: tree_law_zoo_ │
│  DB_HOST=192.168... │         │  zoo_user            │
└─────────────────────┘         └──────────────────────┘
         │                                │
         │                                │
         └────────────────────────────────┘
              Shared Database
              (เห็นข้อมูลร่วมกัน)
```

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

## สรุป

**ความยาก:** ⭐⭐⭐ (ปานกลาง-ยาก)

**เวลาที่ใช้:**

- Database Server: 30-45 นาที
- Client Machine: 20-30 นาที

**สิ่งที่ต้องทำเอง:**

**เครื่อง Database Server (ทำครั้งเดียว):**

1. ติดตั้ง PostgreSQL
2. ตั้งค่า remote access (postgresql.conf, pg_hba.conf)
3. สร้าง database และ user
4. Setup database schema
5. ตั้งค่า firewall

**เครื่องอื่น (Client):**

1. ติดตั้ง Prerequisites (Flutter, Node.js, Java 17)
2. Clone repository
3. สร้างไฟล์ `.env` ชี้ไปที่ Remote Database Server
4. ทดสอบ connection

**สิ่งที่ script ช่วยได้:**

- Install dependencies
- Quick start script (สำหรับ client)
- Database setup script (สำหรับ server)

**สิ่งที่ต้องระวัง:**

**ทั่วไป:**

- ไฟล์ `.env` ไม่ควร commit (ควรมี `.gitignore`)
- Java 17 path แตกต่างกันตาม OS
- Database Server IP address ต้องถูกต้อง
- Network connectivity ระหว่างเครื่อง
- Security: ใช้ strong password และพิจารณาใช้ VPN/SSH tunnel สำหรับ production
- Firewall rules ต้องอนุญาต port 5432

**สำหรับ External Drive:**

- External drive ต้อง mount อยู่เสมอ (PostgreSQL จะไม่ start ถ้า data directory ไม่มี)
- ตั้งค่า auto-mount external drive เมื่อ boot
- ใช้ external drive ที่เชื่อถือได้ (SSD ดีกว่า HDD, USB 3.0+ หรือ Thunderbolt)
- Performance อาจช้ากว่า internal drive (ขึ้นอยู่กับ connection type)
- Backup ข้อมูลเป็นประจำ (external drive อาจเสียหายหรือหลุดได้)
- ตรวจสอบ disk space บน external drive เป็นประจำ
- ใช้ journaling filesystem (HFS+, ext4, NTFS) ไม่ใช่ FAT32