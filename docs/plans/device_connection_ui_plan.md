# แผนการปรับปรุง UI/UX สำหรับการเชื่อมต่อสมาร์ทวอทช์ (Cross-Platform & Future-Proof)

เอกสารนี้รวบรวมแผนการปรับปรุง UI สำหรับการเชื่อมต่อสมาร์ทวอทช์และอุปกรณ์สุขภาพ โดยครอบคลุมทั้ง **Apple Watch (iOS)**, **Android Wear / Smartwatch อื่นๆ (Android)** และวางโครงสร้างเผื่อไว้สำหรับ **Cloud API (เช่น Garmin, Fitbit, Strava)** ในอนาคต ด้วยการใช้โครงสร้างพื้นฐานระดับ OS / API และหลีกเลี่ยงการใช้ข้อมูล Mock อย่างเด็ดขาด

กลยุทธ์หลักของเราคือการแบ่งระดับการเชื่อมต่อเป็น:
*   **ระดับที่ 1 (ปัจจุบัน):** OS Health Hubs (Apple HealthKit สำหรับ iOS, Google Health Connect สำหรับ Android)
*   **ระดับที่ 2 (อนาคต):** Cloud-to-Cloud APIs (เช่น Garmin Connect API, Fitbit Web API)

---

## ✅ สิ่งที่ดำเนินการเสร็จแล้ว

| รายการ | ไฟล์ | สถานะ |
|---|---|---|
| Abstract Interface | `lib/features/health/data/sources/health_data_source.dart` | ✅ เสร็จ |
| Apple HealthKit Source | `lib/features/health/data/sources/apple_health_source.dart` | ✅ เสร็จ |
| Health Connect Source | `lib/features/health/data/sources/health_connect_source.dart` | ✅ เสร็จ |
| Garmin Stub (อนาคต) | `lib/features/health/data/sources/garmin_api_source.dart` | ✅ เสร็จ |
| Riverpod State Manager | `lib/features/health/presentation/providers/health_provider.dart` | ✅ เสร็จ |
| Flutter package `health` | `pubspec.yaml` | ✅ ติดตั้งแล้ว |

---

## ⚠️ สิ่งที่ต้องดำเนินการก่อนทดสอบ (Prerequisites)

### ก. แก้ไขไฟล์ Native Config (บังคับ)

ไม่มีสิ่งนี้ แอปจะ Crash หรือถูก Apple Reject ทันทีเมื่อกดขอสิทธิ์

**iOS — แก้ไข `ios/Runner/Info.plist`:**
เพิ่มบรรทัดด้านล่างก่อนปิด `</dict>` สุดท้าย:
```xml
<key>NSHealthShareUsageDescription</key>
<string>เราต้องการดึงจำนวนก้าวเดินเพื่อแสดงผลสุขภาพของคุณ</string>
<key>NSHealthUpdateUsageDescription</key>
<string>เราต้องการบันทึกข้อมูลเพื่อคำนวณคะแนนสุขภาพ</string>
```

**Android — แก้ไข `android/app/src/main/AndroidManifest.xml`:**
```xml
<uses-permission android:name="android.permission.health.READ_STEPS"/>
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
<uses-permission android:name="android.permission.health.READ_SLEEP"/>
```

### ข. แก้ไข Bug ที่พบในโค้ดปัจจุบัน (บังคับ)

**1. `health_provider.dart` — copyWith ไม่ได้ล้าง errorMessage:**
เมื่อสถานะเปลี่ยนจาก error เป็น connected, ตัวแปร `errorMessage` เก่าจะยังค้างอยู่ ทำให้ UI อาจแสดงข้อความ Error ค้างโดยไม่รู้ตัว ต้องแก้ไข `copyWith` ให้ล้าง error เมื่อสถานะเปลี่ยน

**2. `health_page.dart` — ส่วน Device Card ยังเป็น Static:**
ปุ่ม "เพิ่ม" ใน `_buildConnectedDevicesSection` ยังเป็น `onPressed: () {}` (ไม่ได้ผูกกับ `healthProvider`)
Card "นาฬิกา" (`_buildDeviceItem(Icons.watch, 'นาฬิกา')`) ยังไม่ตอบสนองต่อสถานะจริง

### ค. เคลียร์พื้นที่ฮาร์ดดิสก์ของเครื่อง Mac
ขณะนี้เครื่อง Mac เต็มทำให้ build ไม่ผ่าน ต้องเคลียร์พื้นที่ให้ว่างอย่างน้อย **5-10 GB** ก่อน:
```bash
# ลบ Simulator ที่ไม่ได้ใช้
xcrun simctl delete unavailable
# ลบ Xcode cache (ถ้าจำเป็น)
rm -rf ~/Library/Developer/Xcode/DerivedData
```

---

## 1. สถาปัตยกรรมคลาสจัดการข้อมูล (Data Architecture)

เพื่อให้โค้ด UI สะอาดและรองรับการขยายตัวในอนาคต ระบบใช้โครงสร้างแบบ **Abstract Class `HealthDataSource`** ซึ่งได้ถูกสร้างไว้แล้วใน `lib/features/health/data/sources/`:
*   `AppleHealthSource`: ดึงข้อมูลผ่าน iOS HealthKit (เขียนโค้ดเสร็จแล้ว)
*   `HealthConnectSource`: ดึงข้อมูลผ่าน Android Health Connect (เขียนโค้ดเสร็จแล้ว)
*   `GarminApiSource`: (ตัวอย่างในอนาคต) ดึงข้อมูลผ่าน OAuth2 ของ Garmin

**State Management:** ใช้ Riverpod `StateNotifierProvider` ผ่าน `healthProvider` ใน `health_provider.dart` ซึ่งมี Logic ครบทั้ง: ตรวจสอบสิทธิ์, ขอสิทธิ์, ยกเลิก, และดึงข้อมูลสด

```
UI (health_page.dart)
    └── ref.watch(healthProvider)
           └── HealthNotifier
                  └── HealthDataSource (AppleHealthSource / HealthConnectSource)
                         └── OS HealthKit / Health Connect API
```

---

## 2. สถานะอุปกรณ์ (Device Status UI)

Card อุปกรณ์ "นาฬิกา" ต้องแสดงสถานะตาม `connectionState` จาก `healthProvider`:

| สถานะ | HealthConnectionState | UI |
|---|---|---|
| ยังไม่เชื่อมต่อ | `disconnected` | ไอคอนสีเทา + ข้อความ "แตะเพื่อเชื่อมต่อ" |
| กำลังเชื่อมต่อ | `checking` | Loading Spinner บน Card |
| เชื่อมต่อแล้ว | `connected` | ไอคอนสีแบรนด์ + "ซิงค์ล่าสุด: วันนี้ 08:30" |
| เกิดข้อผิดพลาด | `error` | ไอคอนสีแดง + ข้อความ errorMessage |

**Real Data Logic:**
- สถานะเริ่มต้นอิงจากผลลัพธ์จริงของ `source.hasPermissions()`
- เวลา "ซิงค์ล่าสุด" ดึงจาก timestamp ของข้อมูล HealthKit จริง ไม่ใช้เวลาจำลอง

---

## 3. Flow การเพิ่มอุปกรณ์ (Add Device Flow)

เมื่อผู้ใช้กดปุ่ม **"เพิ่ม"** หรือกดที่ Card นาฬิกาที่ยังไม่เชื่อมต่อ:

*   **Dynamic Bottom Sheet:** UI จะแสดงหน้าต่างเลือก Source ที่เหมาะสม:
    *   **iOS:** "เชื่อมต่อกับ Apple Health" + โลโก้ Apple Health
    *   **Android:** "เชื่อมต่อกับ Health Connect" + โลโก้ Health Connect
    *   *(อนาคต: เพิ่มปุ่ม "เชื่อมต่อ Garmin", "เชื่อมต่อ Fitbit" โดยไม่ต้องแก้โครงสร้าง UI หลัก)*
*   **การขอสิทธิ์:** เรียก `ref.read(healthProvider.notifier).requestAccess()` ซึ่งจะ:
    1. เปลี่ยนสถานะเป็น `checking`
    2. เรียก OS Permission Dialog / OAuth Webview ขึ้นมาให้ผู้ใช้กดอนุญาต
    3. เมื่อผู้ใช้กดยืนยัน → ดึงข้อมูลสดทันทีผ่าน `fetchLiveHealthData()`

---

## 4. หน้าต่างจัดการอุปกรณ์ (Device Management)

เมื่อผู้ใช้แตะที่ Card อุปกรณ์ที่อยู่ในสถานะ "เชื่อมต่อแล้ว":

*   **เปิดหน้าจอใหม่ (Device Details Page):**
    *   **ส่วนหัว:** ระบุแหล่งที่มาจาก `state.activeSource?.sourceName` เช่น "Linked via Apple Health"
    *   **Live Data View:** แสดงผลข้อมูลจากตัวแปร `state.todaySteps` และ `state.latestHeartRate` ที่ถูกดึงมาจาก API จริง
    *   **Disconnect:** เรียก `ref.read(healthProvider.notifier).disconnect()` เพื่อล้างแคชและหยุดซิงค์
    *   พร้อมแนะนำผู้ใช้ให้ไปปิดสิทธิ์ที่: Settings > Health > Data Access (iOS) หรือ Health Connect App (Android)

---

## 5. สรุปแนวทางการเขียนโค้ด (Implementation Note)

1.  **ใช้ DataSource Pattern:** UI ทำงานผ่าน `healthProvider` โดยไม่ต้องรู้ว่า Source คืออะไร
2.  **ห้าม Hardcode สถานะ:** `_buildDeviceItem` ต้องรับ `HealthConnectionState` มาเพื่อตัดสินใจแสดงสี/ไอคอน
3.  **Graceful Degradation:** ถ้า `state.todaySteps == 0` หรือ `state.latestHeartRate == null` ให้แสดง "ไม่มีข้อมูล" ไม่ใช่ตัวเลขหลอก
4.  **HealthPage ใช้ StatefulWidget:** แต่ `healthProvider` เป็น Riverpod ดังนั้นหน้า `HealthPage` จะต้อง `extends ConsumerStatefulWidget` จึงจะเรียก `ref.watch(healthProvider)` ได้ (ต้องแก้ไขจาก `StatefulWidget` ปัจจุบัน)
