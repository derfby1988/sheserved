---
description: แนวทางการจัดการการนำทาง (Navigation) ไปยังหน้า Login และการย้อนกลับ
---

# แนวทางการจัดการการนำทางไปยังหน้า Login

เมื่อมีการร้องขอให้ผู้ใช้เข้าสู่ระบบ (Login) จากหน้าจออื่นๆ (เช่น หน้า Health, หน้าบทความ หรือหน้าการจองบริการ) เพื่อป้องกันปัญหาปุ่มย้อนกลับใช้งานไม่ได้หรือประวัติการนำทาง (Navigation Stack) ผิดพลาด ให้ปฏิบัติตามแนวทางดังนี้:

## 1. การนำทางไปยังหน้า Login (Direct Navigation)
หลีกเลี่ยงการเปิดหน้าปลายทางที่ต้องใช้การตรวจสอบสิทธิ์ (Authenticated Page) ทิ้งไว้แล้วค่อยสั่งเปลี่ยนหน้าไป Login ในภายหลัง เพราะจะทำให้หน้าเดิมค้างอยู่ในสถานะ Loading หรือเกิดหน้าซ้อนกัน

**✅ แนวทางที่ถูกต้อง:** ตรวจสอบสถานะการเข้าสู่ระบบที่หน้าต้นทาง (Source Page) ทันที:
```dart
onTap: () {
  if (AuthService.instance.isLoggedIn) {
    Navigator.pushNamed(context, '/target-page');
  } else {
    // ส่งเป้าหมายไปเป็น argument เพื่อให้นำทางต่อหลัง login สำเร็จ
    Navigator.pushNamed(
      context, 
      '/login',
      arguments: '/target-page',
    );
  }
},
```

## 2. การจัดการปุ่มย้อนกลับในหน้า Login
เพื่อให้ปุ่มย้อนกลับทำงานได้เสถียรที่สุดในทุกกรณี (ทั้งกรณีเปิดทับหน้าเดิม หรือเปิดขึ้นมาใหม่เลย):
- ใช้ `Stack` เพื่อวางปุ่มย้อนกลับไว้บนสุดเสมอ
- ใช้ `GestureDetector` พร้อม `HitTestBehavior.opaque` และขยาย `Padding` เพื่อให้กดได้ง่าย
- ใช้กลไกการย้อนกลับที่ตรวจสอบประวัติการนำทาง:

```dart
onTap: () {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    // กรณีไม่มีประวัติการนำทาง (เช่น เข้าแอปมาที่หน้า Login เลย) ให้กลับไปหน้าหลัก
    Navigator.pushReplacementNamed(context, '/');
  }
},
```

## 3. การจัดการหน้าปลายทาง (Target Page)
ในหน้าปลายทางที่ต้องการข้อมูลผู้ใช้ (เช่น `HealthDataEntryPage`) ควรมีการตรวจสอบซ้ำใน `initState` และใช้ `pushReplacementNamed` เพื่อเปลี่ยนหน้าเป็น Login แทนการ `pushNamed` ปกติ เพื่อป้องกันการเกิด Navigation Stack ซ้อน (Redundant Stack) ซึ่งเป็นสาเหตุหลักที่ทำให้ปุ่มย้อนกลับพาไปหน้าเดิมที่ค้างอยู่
