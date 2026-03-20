# คู่มือการตั้งค่าเครื่องใหม่ (Client Machine)

## ภาพรวม

คู่มือนี้สำหรับ **Client Machine (เครื่องที่ 2)** ที่ต้องการ clone repository และเชื่อมต่อไปที่ Remote Database Server

**หมายเหตุ:** 
- เครื่องนี้เป็น **Client Machine** - ไม่ต้องติดตั้ง PostgreSQL Server
- Database อยู่ที่ **Remote Database Server (เครื่องหลัก)**
- ต้องมีข้อมูล Database Server: IP address, username, password

---

## Prerequisites

ก่อนเริ่มต้น ต้องมี:

1. **Flutter SDK** (v3.10.0 หรือสูงกว่า)
2. **Node.js** (v14 หรือสูงกว่า) และ npm
3. **Java 17** (สำหรับ Android build - macOS)
4. **PostgreSQL Client** (optional - สำหรับทดสอบ connection)
5. **ข้อมูล Database Server:**
   - IP address ของ Database Server
   - Database username (`sheserved`)
   - Database password
   - Database name (`tree_law_zoo`)

---

## Phase 1: Prerequisites Installation (macOS)

### 1.1 Flutter SDK

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

### 1.2 Node.js และ npm

```bash
# ติดตั้ง Node.js
brew install node
```

**ตรวจสอบ:**

```bash
node --version  # ควรเป็น v14 หรือสูงกว่า
npm --version
```

### 1.3 PostgreSQL Client (Optional)

**สำหรับ Client Machine:**

- **ไม่ต้องติดตั้ง PostgreSQL Server** (เชื่อมต่อไปที่ Remote Database)
- **ติดตั้ง `psql` client เท่านั้น** (ถ้าต้องการทดสอบ connection)

```bash
# ติดตั้ง PostgreSQL client only
brew install libpq
brew link --force libpq
```

**ตรวจสอบ:**

```bash
psql --version
```

**หมายเหตุ:** ถ้าไม่ต้องการใช้ `psql` command line ก็ไม่ต้องติดตั้ง - WebSocket server จะเชื่อมต่อผ่าน Node.js library

### 1.4 Java 17 (สำหรับ Android build)

```bash
# ติดตั้ง Java 17
brew install openjdk@17

# ตรวจสอบ path (จะใช้ใน gradle.properties)
ls -la /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

---

## Phase 2: Repository Setup

### 2.1 Clone Repository

```bash
git clone <repository-url>
cd tree_law_zoo
```

### 2.2 ตรวจสอบ Branch

```bash
git branch
git checkout main  # หรือ branch ที่ต้องการ
```

---

## Phase 3: Flutter App Setup

### 3.1 Install Flutter Dependencies

```bash
cd /path/to/tree_law_zoo
flutter pub get
```

### 3.2 Android Setup (macOS)

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

### 3.3 iOS Setup (macOS)

```bash
cd ios
pod install
cd ..
```

### 3.4 macOS Setup (macOS)

```bash
cd macos
pod install
cd ..
```

### 3.5 Test Flutter App

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

## Phase 4: WebSocket Server Setup

### 4.1 Install Node.js Dependencies

```bash
cd websocket-server
npm install
```

### 4.2 สร้างไฟล์ .env

```bash
# สร้างไฟล์ .env จาก template
cp .env.example .env
```

**เนื้อหาไฟล์ `.env` (Client Machine):**

```env
# Database Configuration - ชี้ไปที่ Remote Database Server
# ⚠️ เปลี่ยนค่าเหล่านี้ให้ตรงกับ Database Server
DB_HOST=192.168.1.100  # IP address ของเครื่อง Database Server
DB_NAME=sheserved
DB_USER=sheserved  # User ที่สร้างที่ Database Server
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
- `DB_USER` และ `DB_PASSWORD` = ข้อมูลจาก Database Server
- ไฟล์ `.env` ไม่ควร commit (ถูก ignore ใน `.gitignore`)

### 4.3 ทดสอบ Remote Database Connection

**ไม่ต้อง setup database ที่เครื่อง Client** - Database อยู่ที่ Database Server แล้ว

**ทดสอบ connection:**

```bash
# วิธีที่ 1: ใช้ psql client (ถ้าติดตั้งแล้ว)
psql -h <DB_SERVER_IP> -U sheserved -d sheserved
# ใส่ password ที่ตั้งไว้

# วิธีที่ 2: ทดสอบผ่าน Node.js
cd websocket-server
node -e "require('dotenv').config();const {Pool}=require('pg');const p=new Pool({host:process.env.DB_HOST,user:process.env.DB_USER,password:process.env.DB_PASSWORD,database:process.env.DB_NAME,port:process.env.DB_PORT});p.query('SELECT NOW()').then(r=>{console.log('✅ Connected:',r.rows[0]);p.end()}).catch(e=>{console.error('❌ Error:',e.message);process.exit(1)})"

# วิธีที่ 3: ใช้ test script
./test-remote-db.sh
```

**หมายเหตุ:** Database setup ทำที่ Database Server เท่านั้น - ดู [SETUP_DATABASE_SERVER.md](SETUP_DATABASE_SERVER.md)

### 4.4 Test WebSocket Server

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

## Phase 5: Configuration Files ที่ต้องสร้าง/แก้ไข

### 5.1 Flutter App

- **ไม่ต้องสร้างไฟล์ใหม่** - ทุกอย่างอยู่ใน repo แล้ว
- **ตรวจสอบ:** `lib/main.dart` ใช้ route `/login` ถูกต้อง

### 5.2 WebSocket Server

- **ต้องสร้าง:** `websocket-server/.env` (ไม่ควร commit)
- **ตรวจสอบ:** `websocket-server/server.js` มี logic ที่ถูกต้อง

### 5.3 Android Build

- **ต้องแก้ไข:** `android/gradle.properties` (เพิ่ม Java 17 path)
- **ตรวจสอบ:** Java version ตรงกับที่ตั้งค่า

---

## Checklist สำหรับเครื่องใหม่

### Prerequisites

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

### WebSocket Server

- [ ] `npm install` สำเร็จ
- [ ] สร้างไฟล์ `.env` พร้อมค่าที่ถูกต้อง (ชี้ไปที่ Remote DB Server)
- [ ] ทดสอบ connection ไปยัง Remote Database สำเร็จ
- [ ] Server start สำเร็จ (`npm start`)
- [ ] Health check ผ่าน (`curl http://localhost:3000/health`)

---

## Quick Start

ใช้ script สำหรับ automation:

```bash
chmod +x setup-new-machine.sh
./setup-new-machine.sh
```

Script จะ:
- Install Flutter dependencies
- Install iOS/macOS pods
- Install WebSocket server dependencies
- สร้างไฟล์ `.env` แบบ interactive

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

- ตรวจสอบ `DB_HOST` ใน `.env` ถูกต้อง (IP address ของ Database Server)
- ตรวจสอบ network connectivity: `ping <DB_SERVER_IP>`
- ตรวจสอบ credentials ใน `.env`
- ทดสอบ connection: `psql -h <DB_SERVER_IP> -U <DB_USER> -d <DB_NAME>`
- ตรวจสอบว่า Database Server กำลังรันอยู่

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

### Database Connection Issues

**ปัญหา: Connection timeout / Connection refused**

- ตรวจสอบ Database Server กำลังรันอยู่
- ตรวจสอบ IP address ถูกต้อง
- ตรวจสอบ firewall บน Database Server
- ตรวจสอบ network (LAN/WAN) connectivity
- ทดสอบ port: `nc -zv <DB_SERVER_IP> 5432`

**ปัญหา: Authentication failed**

- ตรวจสอบ username และ password ใน `.env`
- ตรวจสอบว่า user `sheserved` มีอยู่ที่ Database Server
- ตรวจสอบว่า database `tree_law_zoo` มีอยู่

---

## สถาปัตยกรรม

```
┌─────────────────────┐         ┌──────────────────────┐
│  เครื่องนี้          │         │  เครื่อง Database     │
│  (Client)           │         │  Server              │
│                     │         │                      │
│  Flutter App        │         │  PostgreSQL          │
│  WebSocket Server   │────────▶│  Port: 5432          │
│                     │ Network │  Database: tree_law_ │
│  .env:              │         │  User: tree_law_zoo_  │
│  DB_HOST=192.168... │         │  zoo_user            │
└─────────────────────┘         └──────────────────────┘
         │                                │
         │                                │
         └────────────────────────────────┘
              Shared Database
              (เห็นข้อมูลร่วมกัน)
```

---

## Next Steps

หลังจาก setup เสร็จแล้ว:

1. **ทดสอบ Flutter App:** `flutter run -d chrome`
2. **ทดสอบ WebSocket Server:** `cd websocket-server && npm start`
3. **ทดสอบ Database Connection:** ใช้ `test-remote-db.sh`
4. **เริ่มพัฒนา:** ดู [README.md](README.md) สำหรับข้อมูลเพิ่มเติม

---

## ดูเพิ่มเติม

- [SETUP_DATABASE_SERVER.md](SETUP_DATABASE_SERVER.md) - คู่มือสำหรับ Database Server
- [websocket-server/README.md](websocket-server/README.md) - WebSocket Server documentation
- [websocket-server/.env.example](websocket-server/.env.example) - Environment variables template
