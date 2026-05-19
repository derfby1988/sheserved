# แผนการพัฒนาระบบซิงค์ข้อมูลสุขภาพหลังบ้าน (Health Data Auto-Sync Plan)

เอกสารฉบับนี้ร่างขึ้นเพื่อตอบโจทย์การ **ดึงข้อมูลให้ละเอียดที่สุด** จากอุปกรณ์สวมใส่ (Smartwatches) และ **ซิงค์กลับไปยังฐานข้อมูล (Supabase) อัตโนมัติ** เพื่อให้สามารถนำข้อมูลไปใช้ประโยชน์ขั้นสูงได้ในอนาคต (เช่น สร้างกราฟสุขภาพส่วนบุคคล, แจ้งเตือนความผิดปกติ, หรือรวมเข้ากับระบบคะแนนสะสม)

---

## 1. ข้อมูลที่จะทำการดึง (Data Types to Fetch)

เราจะขยายขอบเขตการดึงข้อมูลจาก `health` package ให้ครอบคลุมทุกมิติสุขภาพที่สำคัญ:

*   **หมวดการเคลื่อนไหว (Activity):**
    *   จำนวนก้าว (Steps)
    *   ระยะทางเดิน/วิ่ง (Distance Walking/Running)
    *   พลังงานที่เผาผลาญ (Active Energy Burned / Calories)
    *   ระยะเวลาออกกำลังกาย (Exercise Time / Workouts)
*   **หมวดสัญญาณชีพ (Vitals):**
    *   อัตราการเต้นของหัวใจ (Heart Rate) - เก็บค่าต่ำสุด สูงสุด และค่าเฉลี่ย
    *   ความแปรปรวนของอัตราการเต้นหัวใจ (Heart Rate Variability - HRV) (ถ้ามี)
    *   ออกซิเจนในเลือด (Blood Oxygen - SpO2)
    *   ความดันโลหิต (Blood Pressure) (ถ้ามี)
*   **หมวดการนอนหลับ (Sleep):**
    *   เวลานอนรวม (Total Sleep Duration)
    *   คุณภาพการนอน (Awake, Asleep, Deep Sleep - ถ้า OS รองรับ)
*   **หมวดสัดส่วนร่างกาย (Body - ถ้าตาชั่งหรือแอปส่งข้อมูลมา):**
    *   น้ำหนัก (Weight), มวลไขมัน (Body Fat Percentage)

---

## 2. โครงสร้างตารางฐานข้อมูลใหม่ (Database Schema)

เพื่อรองรับข้อมูลแบบ Time-Series ที่มีความถี่สูง เราจะไม่เก็บในตาราง `consumer_profiles` โดยตรง แต่จะสร้างตารางใหม่:

**ตาราง: `device_health_metrics`**
*   `id` (UUID, Primary Key)
*   `user_id` (UUID, Foreign Key ชี้ไปที่ `users`)
*   `metric_type` (String) เช่น 'steps', 'heart_rate', 'sleep_duration', 'active_calories'
*   `value` (Numeric/JSONB) เก็บค่าตัวเลข หรือ JSON หากเป็นข้อมูลซับซ้อน (เช่น ข้อมูล Sleep Stage)
*   `unit` (String) เช่น 'count', 'bpm', 'minutes', 'kcal'
*   `measured_at` (Timestamptz) เวลาที่เกิดข้อมูลนั้นจริงจากนาฬิกา
*   `source_name` (String) เช่น 'Apple Health', 'Garmin', 'Health Connect'
*   `synced_at` (Timestamptz) เวลาที่ซิงค์เข้า Server (Default: now())

---

## 3. สถาปัตยกรรมการซิงค์ (Sync Architecture)

เราจะแบ่งการทำงานเป็น 2 ส่วนหลัก:

### ส่วนที่ 1: Foreground Sync (ซิงค์เมื่อเปิดแอป)
*   **เมื่อใด:** ทุกครั้งที่ผู้ใช้เปิดแอปและเข้าหน้าจอ Home หรือหน้า Health (และสิทธิ์ถูกอนุญาตแล้ว)
*   **กระบวนการ:**
    1. ตรวจสอบว่ามีการซิงค์ล่าสุดเมื่อใด (Last Sync Time)
    2. หากเกินเวลาที่กำหนด (เช่น 1 ชั่วโมง) ให้ดึงข้อมูลก้อนใหม่จาก OS API โดยใช้ช่วงเวลาตั้งแต่ Last Sync Time จนถึง ปัจจุบัน (Delta Sync)
    3. ส่งข้อมูล (Batch Insert) เข้าตาราง `device_health_metrics`

### ส่วนที่ 2: Background Sync (การซิงค์เบื้องหลัง - อนาคต)
*   ใช้เครื่องมืออย่าง `workmanager` หรือ `flutter_background_service` (Android) และ Background Fetch (iOS)
*   **ข้อจำกัดที่ต้องระวัง:** Apple HealthKit จะไม่อนุญาตให้อ่านข้อมูลบางอย่างตอนที่หน้าจอ iPhone ล็อกอยู่ (เพื่อความเป็นส่วนตัว) ดังนั้น Background Sync บน iOS อาจทำงานได้จำกัด ต้องอาศัย Foreground Sync เป็นหลัก

---

## 4. แผนการดำเนินงาน (Implementation Steps)

1.  **[Database]** รัน SQL Script สร้างตาราง `device_health_metrics` และกำหนด RLS (Row Level Security) ใน Supabase
2.  **[Repository]** เพิ่มเมธอด `syncDeviceMetrics(List<HealthMetric> metrics)` ใน `HealthRepository`
3.  **[Data Source]** แก้ไข `AppleHealthSource` และ `HealthConnectSource` ให้ดึงข้อมูล Data Types อื่นๆ ตามข้อ 1
4.  **[Provider]** แก้ไข `HealthNotifier` ให้ทำหน้าที่ดึงข้อมูลมัดรวม (Batch) และส่งให้ Repository บันทึกลงฐานข้อมูลโดยอัตโนมัติเมื่อสถานะเป็น Connected
5.  **[UI]** อัปเดต UI ให้แสดงข้อมูลที่ดึงมาใหม่ (เช่น โชว์แคลอรี่, โชว์กราฟย้อนหลังดึงจากตารางใหม่ แทนที่จะดึงจาก OS สดๆ อย่างเดียว)
