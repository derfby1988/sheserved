# สรุป Setup Plan - Tree Law Zoo

## ภาพรวม

คู่มือนี้ครอบคลุมการตั้งค่าทั้งหมดที่ต้องทำหลังจาก clone repository จาก GitHub เพื่อให้เครื่องใหม่สามารถรัน Flutter app และ WebSocket server ได้

**แบ่งเป็น 2 ส่วน:**
1. **Setup Database Server** - ทำที่เครื่องหลัก (เครื่องที่มี Database) ✅ **เสร็จแล้ว**
2. **Setup Client Machine** - ทำที่เครื่องอื่น (เครื่องที่ clone repository)

---

## Phase 0: Setup Database Server (เครื่องหลัก) ✅ เสร็จแล้ว

### สถานะ: ✅ เสร็จสมบูรณ์ 100%

**สิ่งที่ทำเสร็จแล้ว:**
- ✅ ติดตั้ง PostgreSQL@14
- ✅ Format External Drive เป็น APFS (`/Volumes/PostgreSQL`)
- ✅ Initialize Database Cluster บน External Drive
- ✅ ตั้งค่า Remote Connection (postgresql.conf, pg_hba.conf)
- ✅ สร้าง Database (`tree_law_zoo`) และ User (`sheserved`)
- ✅ Setup Database Schema (2 tables: users, locations)
- ✅ หา IP Address
- ✅ ตั้งค่า Firewall
- ✅ ทดสอบ Remote Connection

**ข้อมูล Database Server:**
- Data Directory: `/Volumes/PostgreSQL/postgresql-data`
- Filesystem: APFS
- Database: `sheserved`
- User: `sheserved`
- Port: 5432
- Tables: `users`, `locations`

---

## Phase 1-4: Setup Client Machine (เครื่องอื่น)

### Phase 1: Prerequisites Installation

#### 1.1 Flutter SDK (macOS)
```bash
brew install flutter
flutter doctor
flutter doctor --android-licenses  # สำหรับ Android
```

#### 1.2 Node.js และ npm (macOS)
```bash
brew install node
node --version  # ควรเป็น v14 หรือสูงกว่า
npm --version
```

#### 1.3 PostgreSQL Client (Optional)
```bash
# macOS - ติดตั้ง client only
brew install libpq
brew link --force libpq
```

#### 1.4 Java 17 (สำหรับ Android build - macOS)
```bash
brew install openjdk@17
# ตรวจสอบ path (จะใช้ใน gradle.properties)
ls -la /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

---

### Phase 2: Repository Setup

```bash
git clone https://github.com/derfby1988/tree_law_zoo.git
cd tree_law_zoo
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

#### 3.5 Test Flutter App
```bash
# Web
flutter run -d chrome

# Android
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

**สำคัญ:** ตั้งค่าให้ชี้ไปที่ Remote Database Server

```env
# Database Configuration - ชี้ไปที่ Remote Database Server
# ⚠️ เปลี่ยนค่าเหล่านี้ให้ตรงกับ Database Server
DB_HOST=<IP_ADDRESS>  # IP address ของเครื่อง Database Server
DB_NAME=sheserved
DB_USER=sheserved  # User ที่สร้างที่ Database Server
DB_PASSWORD=<password>  # Password ที่ตั้งไว้ที่ Database Server
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

#### 4.3 ทดสอบ Remote Database Connection

```bash
# ถ้าติดตั้ง psql client
psql -h <DB_SERVER_IP> -U sheserved -d sheserved

# หรือทดสอบผ่าน Node.js
cd websocket-server
node -e "const {Pool}=require('pg');const p=new Pool({host:process.env.DB_HOST,user:process.env.DB_USER,password:process.env.DB_PASSWORD,database:process.env.DB_NAME,port:process.env.DB_PORT});p.query('SELECT NOW()').then(r=>{console.log('✅ Connected:',r.rows[0]);p.end()}).catch(e=>{console.error('❌ Error:',e.message);process.exit(1)})"
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

## Checklist สำหรับเครื่อง Client

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

## สถาปัตยกรรม Remote Database

```
┌─────────────────────┐         ┌──────────────────────┐
│  เครื่อง Client     │         │  เครื่อง Database     │
│  (เครื่องอื่น)       │         │  Server              │
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

### WebSocket Server Issues

**ปัญหา: Cannot connect to remote database**

**สำหรับเครื่อง Client:**
- ตรวจสอบ `DB_HOST` ใน `.env` ถูกต้อง (IP address ของ Database Server)
- ตรวจสอบ network connectivity: `ping <DB_SERVER_IP>`
- ตรวจสอบ credentials ใน `.env`
- ทดสอบ connection: `psql -h <DB_SERVER_IP> -U <DB_USER> -d <DB_NAME>`

**สำหรับเครื่อง Database Server:**
- ตรวจสอบ PostgreSQL กำลังรัน: `brew services list` (macOS)
- ตรวจสอบ `postgresql.conf`: `listen_addresses = '*'`
- ตรวจสอบ `pg_hba.conf`: มี rule สำหรับ remote access
- ตรวจสอบ firewall: port 5432 เปิดอยู่

---

## สรุป

**ความยาก:** ⭐⭐⭐ (ปานกลาง-ยาก)

**เวลาที่ใช้:**
- Database Server: 30-45 นาที ✅ **เสร็จแล้ว**
- Client Machine: 20-30 นาที

**สิ่งที่ต้องทำเอง:**

**เครื่อง Database Server (ทำครั้งเดียว):** ✅ **เสร็จแล้ว**
1. ✅ ติดตั้ง PostgreSQL
2. ✅ ตั้งค่า remote access
3. ✅ สร้าง database และ user
4. ✅ Setup database schema
5. ✅ ตั้งค่า firewall

**เครื่องอื่น (Client):**
1. ติดตั้ง Prerequisites (Flutter, Node.js, Java 17)
2. Clone repository
3. สร้างไฟล์ `.env` ชี้ไปที่ Remote Database Server
4. ทดสอบ connection

---

## ข้อมูลสำคัญ

**Database Server (เครื่องหลัก):**
- IP Address: `<IP_ADDRESS>` (บันทึกไว้)
- Database: `sheserved`
- User: `sheserved`
- Password: `<password>` (บันทึกไว้)
- Port: 5432

**สำหรับเครื่อง Client:**
- ใช้ข้อมูลข้างต้นในการตั้งค่า `.env`
- ไม่ต้องติดตั้ง PostgreSQL Server
- แค่ตั้งค่า `.env` ให้ชี้ไปที่ Remote Database Server
