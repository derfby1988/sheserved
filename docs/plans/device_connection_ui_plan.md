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

---

## 6. การจัดการข้อมูลชนกันและขยายระบบในอนาคต (Data Deduplication & Future Scalability)

เพื่อเตรียมรองรับการเชื่อมต่ออุปกรณ์และ Cloud APIs จำนวนมากในอนาคต (เช่น การต่อ Garmin/Fitbit Cloud ตรงควบคู่กับ Apple Health/Google Health Connect) ระบบใช้กลยุทธ์ป้องกันข้อมูลชนกันและการนับซ้ำ (Data Deduplication) ดังนี้:

### ก. การจัดการข้อมูลทับซ้อนที่ระดับ OS (OS-Level Deduplication)
*   **การรวมศูนย์:** อุปกรณ์ทั้งหมดที่เชื่อมต่อผ่านระบบปฏิบัติการ (iOS/Android) จะถูกเกลี่ยและลดความซ้ำซ้อนโดยอัตโนมัติผ่านลำดับความสำคัญ (Data Source Prioritization) ในแอป Health (iOS) หรือแอป Health Connect (Android)
*   **แนวทางปฏิบัติ:** แอป SHEserved จะเรียกใช้ข้อมูลที่ผ่านการ Aggregated จากระดับ OS เป็นหลักผ่าน `AppleHealthSource` และ `HealthConnectSource` ซึ่งจะทำให้ได้ตัวเลขรวมที่ถูกต้องเสร็จสรรพโดยไม่ต้องคำนวณแยกเอง

### ข. การจัดการข้อมูลชนกันที่ระดับฐานข้อมูล (Cloud API Sync Layer)
ในอนาคตเมื่อต่อเชื่อม Cloud API โดยตรง ข้อมูลประเภทเดียวกันที่ถูกบันทึกลงตาราง `device_health_metrics` ในช่วงเวลาทับซ้อนกัน จะต้องถูกขจัดข้อมูลซ้ำซ้อนผ่าน Logic คิวรีสุขภาพดังนี้:
1.  **Source Prioritization Hierarchy:** จัดลำดับความน่าเชื่อถือของแหล่งข้อมูลหลัก (เช่น หากมีข้อมูลก้าวเดินในวันนั้นจาก `Apple Health` ให้ใช้ค่านั้นเป็นอันดับแรก และเพิกเฉยข้อมูลประเภทเดียวกันจาก `Garmin Cloud API` ในวันเดียวกัน)
2.  **Single Active Source Policy:** ในหน้าการจัดการอุปกรณ์ อนุญาตให้ผู้ใช้กำหนดสถานะ "ใช้งานหลัก (Primary Tracking Source)" ได้ทีละหนึ่งอุปกรณ์สำหรับข้อมูลแต่ละประเภท (เช่น สิทธิ์นับก้าวเป็นของนาฬิกาหลักเท่านั้น)
3.  **Time-Bucket Filtering:** สำหรับข้อมูลแบบ Spot Metrics (เช่น อัตราชีพจร) หากส่งมาจากหลายแหล่งพร้อมกัน ให้ใช้วิธีกรองหาค่าเฉลี่ยรายชั่วโมง หรือยึดค่าจากอุปกรณ์ที่มีลำดับความสำคัญสูงที่สุด เพื่อนำไปประเมินคะแนนหัวใจ (Cardio Score) อย่างถูกต้องและโปร่งใส

---

## 7. สูตรคำนวณคะแนนสุขภาพ Dynamic 4 มิติ (4-Dimensional Dynamic Scoring Formula)

ระบบใช้สูตรประเมินคะแนนสุขภาพรวมเต็ม **100 คะแนน** โดยถ่วงน้ำหนักแบ่งออกเป็น **4 มิติหลัก** จากข้อมูลจริงที่วัดได้จริงจากร่างกายและอุปกรณ์สวมใส่ ดังมีรายละเอียดตามเกณฑ์ดังนี้:

```
คะแนนสุขภาพรวม (100 คะแนน)
 ├── 1. สัดส่วนร่างกาย (30 คะแนน) -> อิงดัชนีมวลกาย (BMI)
 ├── 2. การเคลื่อนไหว (30 คะแนน) -> อิงจำนวนก้าว (15) + แคลอรี่ที่เผาผลาญ (15)
 ├── 3. ความแข็งแรงหัวใจ (20 คะแนน) -> อิงชีพจรขณะพัก (10) + ค่า HRV (10)
 └── 4. การนอนพักผ่อน (20 คะแนน) -> อิงชั่วโมงการนอนหลับ
```

### 1) มิติสัดส่วนร่างกาย (Body Composition) — น้ำหนัก 30% (เต็ม 30 คะแนน)
คำนวณจากดัชนีมวลกาย (BMI) ของผู้ใช้งานปัจจุบัน โดยประเมินหาเกณฑ์หักคะแนนหากอยู่นอกช่วงสุขภาพดี:
*   **ค่า BMI ในอุดมคติ:** $18.5 \le \text{BMI} < 23.0$ $\rightarrow$ **ได้ 30 คะแนนเต็ม**
*   **กรณีน้ำหนักน้อยเกินไป (Underweight):** หาก $\text{BMI} < 18.5$
    $$\text{คะแนน} = 30.0 - (18.5 - \text{BMI}) \times 3$$
*   **กรณีน้ำหนักเกิน / ท้วม (Overweight):** หาก $23.0 \le \text{BMI} < 30.0$
    $$\text{คะแนน} = 30.0 - (\text{BMI} - 22.9) \times 2$$
*   **กรณีอ้วน (Obese):** หาก $\text{BMI} \ge 30.0$
    $$\text{คะแนน} = 30.0 - (\text{BMI} - 22.9) \times 4$$
*   *หมายเหตุ: คะแนนจำกัดช่วงให้อยู่ระหว่าง $0.0 \le \text{คะแนน} \le 30.0$*

### 2) มิติการเคลื่อนไหว (Daily Activity) — น้ำหนัก 30% (เต็ม 30 คะแนน)
สะท้อนความกระฉับกระเฉงตลอดทั้งวัน โดยแบ่งเป็น 2 ส่วนย่อย:
1.  **จำนวนก้าวเดินรายวัน (Steps):** เป้าหมายที่ **8,000 ก้าว** (สัดส่วน 15 คะแนน)
    $$\text{คะแนนส่วนก้าวเดิน} = \left( \frac{\text{ก้าวเดินจริง}}{8000} \right) \times 15.0$$ (Clamped สูงสุด 15.0 คะแนน, Fallback เมื่อไม่มีข้อมูล = 8,000 ก้าว)
2.  **การเผาผลาญแคลอรี่ (Active Calories):** เป้าหมายที่ **300 kcal** (สัดส่วน 15 คะแนน)
    $$\text{คะแนนส่วนเผาผลาญ} = \left( \frac{\text{แคลอรี่จริง}}{300.0} \right) \times 15.0$$ (Clamped สูงสุด 15.0 คะแนน, Fallback เมื่อไม่มีข้อมูล = 300.0 kcal)

### 3) มิติด้านคาร์ดิโอและหัวใจ (Cardio Health) — น้ำหนัก 20% (เต็ม 20 คะแนน)
สะท้อนความฟิตของหัวใจและการฟื้นตัวของระบบประสาทอัตโนมัติ โดยแบ่งเป็น 2 ส่วนย่อย:
1.  **อัตราชีพจรขณะพัก (Resting Heart Rate):** ช่วงสุขภาพดีคือ **60 - 80 bpm** (สัดส่วน 10 คะแนน)
    *   หากอยู่ในช่วง $60 \le \text{HR} \le 80$ $\rightarrow$ **ได้ 10 คะแนนเต็ม**
    *   หากชีพจรช้าเกินไป ($\text{HR} < 60$): $\text{หักคะแนน} = (60 - \text{HR}) \times 0.5$
    *   หากชีพจรเร็วเกินไป ($\text{HR} > 80$): $\text{หักคะแนน} = (\text{HR} - 80) \times 0.5$
    *   *หมายเหตุ: คะแนนของชีพจรถูกจำกัดไว้ที่ช่วง $0.0 \le \text{คะแนน} \le 10.0$*
2.  **ความแปรปรวนของหัวใจ (Heart Rate Variability - HRV):** ค่ามาตรฐานเพื่อสุขภาพที่ดีเป้าหมายคือ **40 ms** (สัดส่วน 10 คะแนน)
    $$\text{คะแนนส่วน HRV} = \left( \frac{\text{HRV จริง}}{40.0} \right) \times 10.0$$ (Clamped สูงสุด 10.0 คะแนน, Fallback เมื่อไม่มีข้อมูล = 40.0 ms)

### 4) มิติการนอนและการพักผ่อน (Sleep & Recovery) — น้ำหนัก 20% (เต็ม 20 คะแนน)
ประเมินความเพียงพอในการนอนหลับเพื่อพักฟื้นกล้ามเนื้อและการทำงานของสมอง:
*   **เป้าหมายการนอนหลับ:** **7 ชั่วโมง (420 นาที)** ต่อคืน (สัดส่วน 20 คะแนน)
    $$\text{คะแนนส่วนการนอน} = \left( \frac{\text{นาทีที่หลับจริง}}{420.0} \right) \times 20.0$$
*   *หมายเหตุ: คะแนนถูก Clamped สูงสุด 20.0 คะแนน, Fallback เมื่อไม่มีข้อมูล = 420 นาที*


