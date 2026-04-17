# Fix Plan - Sheserved Navigation & UI Issues

![Error Screenshot](file:///Users/dave_macmini/sheserved/docs/error_screenshot.jpg)
*บันทึกภาพ ERROR: พบ Assertion Failure ใน painting.dart และอาการ Right Overflow*

## Priority: URGENT & CRITICAL

### 1. Navigation Bar Switching Issue
- **Observation**: User reports persistent issues when switching pages via the navigation bar.
- **Potential Causes**:
    - `IndexedStack` not updating correctly or `setState` delay in `MainAppLayout`.
    - Tab indices mismatch or `onIndexChanged` callback logic.
    - `onWillPop` logic interfering with navigation state.
- **Actions**:
    - [x] Verify indices in `MainAppLayout` and `TlzBottomNavigationBar`.
    - [x] Ensure `onIndexChanged` prevents redundant `setState` calls.
    - [x] Consider adding a small delay or transition animation between tabs if jank is observed.
    - [x] Debug the `IndexedStack` behavior during rapid switching.

### 2. UI Rendering - Red Screen (Text Shadow)
- **Observation**: เกิด Error สีแดง "dart:ui/painting.dart: Failed assertion: line 804 pos 15: blurRadius >= 0"
- **Visual Analysis**: 
    - จากภาพประกอบ พบว่านอกจากการแจ้งเตือนเรื่อง `blurRadius` แล้ว ยังพบอาการ **Right Overflowed by 99474 pixels** ซึ่งเป็นค่าที่สูงมากผิดปกติ
    - ปัญหานี้มักเกิดจากการที่ Widget ในกลุ่ม `Row` หรือ `Stack` พยายามขยายตัวในพื้นที่ที่เป็น Unbounded width (เช่น ภายใน Horizontal ListView หรือช่วงที่ Animation ยังคำนวณค่าไม่เสร็จ)
- **Actions**:
    - [x] ลบ `shadows` ออกจาก `TrendingDonationCard` เพราะเป็นจุดเดียวที่ใช้ `Shadow` (ไม่ใช่ BoxShadow) และมีโอกาสเกิดค่าลบตอนทำ Animation
    - [x] ตรวจสอบ `TlzBottomNavigationBar` ส่วนของการไล่เฉดสี (ShaderMask) และ `_GlassEdgePainter` ว่ามีการคำนวณขนาดที่อาจเป็น NaN หรือ Infinity หรือไม่
    - [x] ตรวจสอบ `Row` ในเมนูบาร์ว่ามีจุดไหนที่อาจเกิด Overflow เมื่อมีการขยายขนาดไอคอน (AnimatedScale) หรือไม่

### 3. Navigation Bar Aesthetics & Animation
- **Observation**: Icons not scaling uniformly or prominently enough.
- **Actions**:
    - [x] Implemented `AnimatedScale` and `AnimatedSlide` for all icons.
    - [x] Increased scale from 1.15 to 1.25 for better visibility.
    - [x] Synchronized `Home` (Pill) and other (Bubble) icons' animation curves.

### 4. Startup & Auth Flow
- **Observation**: App redirects to Login page unexpectedly on startup.
- **Actions**:
    - [x] Removed forced `Navigator.pushNamed('/login')` from `ProfilePage.initState`.
    - [x] Implemented login placeholder in `ProfilePage`.
    - [x] Verified `MainAppLayout` as the default home route.
