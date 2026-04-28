# Sheserved UI Rendering Standards (iOS & Android Parity)

เอกสารนี้รวบรวมเทคนิคและกฎเกณฑ์ในการจัดการ UI เพื่อให้การแสดงผลบน iOS (Impeller) และ Android (Skia) มีความสม่ำเสมอ โดยเฉพาะในหน้าที่มีการใช้ Native Platform Views เช่น Google Maps

## 1. การจัดการ Layer (Z-Order) กับ Platform View
บน iOS, Native Platform View (เช่น Google Maps) มักจะเรนเดอร์ทับ Flutter Widgets เสมอ

*   **กฎเหล็ก:** หากต้องการให้ Flutter Widgets (เช่น Header, Buttons) อยู่เหนือแผนที่บน iOS ต้องใช้เทคนิค **Compositing Layer Force**
*   **วิธีปฏิบัติ:** ครอบ Widget ที่ต้องการให้อยู่ด้านบนด้วย `Opacity(opacity: 0.999)` (ห้ามใช้ 1.0 เพราะ Flutter จะทำลาย layer ทิ้ง) วิธีนี้จะบังคับให้เกิด `saveLayer` และอยู่เหนือ Native View ได้อย่างถูกต้อง
*   **การตัดขอบ:** ใช้ `ClipRect` ครอบพื้นที่แผนที่เสมอเพื่อไม่ให้ Native View เรนเดอร์ล้นออกมานอกขอบเขตที่กำหนด โดยตั้งค่า `clipBehavior: Clip.hardEdge`

## 2. มาตรฐานการทำ Gradient (iOS Impeller Compatibility)
iOS Impeller มีพฤติกรรมการคำนวณ Alpha ที่ต่างจาก Android

*   **ห้ามใช้:** `Colors.transparent` หรือ `Color(0x00000000)` (Transparent Black) ใน Gradient เพราะจะทำให้เกิด "เส้นตัดสีดำ" (Hard Edge) บน iOS
*   **วิธีปฏิบัติ:** ให้ใช้สีพื้นฐานเดียวกัน (Same Base Color) แล้วปรับ Alpha เป็น 0 แทน เช่น `Color(0x006DD5B1)`
*   **ความเนียน:** เพื่อให้การไล่ระดับความใส (Transparency) สม่ำเสมอทั้งสองแพลตฟอร์ม ให้ใช้ **7 stops** แทนการใช้แค่ 2-3 stops เพื่อช่วยเครื่องมือเรนเดอร์ของ iOS

## 3. โครงสร้างความสูงหน้า Home (Dynamic Layout)
เนื่องจากบน iOS แผนที่ต้องเริ่มที่ตำแหน่งต่างจาก Android เพื่อหลบเลี่ยงปัญหา Z-Order

*   **Map Start Offset:**
    *   Android: เริ่มที่ `_headerSectionHeight / 2`
    *   iOS: เริ่มที่ `_headerSectionHeight` (เพื่อไม่ให้แผนที่ Native เข้าไปทับพื้นที่ Header Gradient)
*   **การคำนวณ Map Height:** ความสูงของแผนที่ต้องคำนวณแบบ Dynamic เสมอเพื่อให้จุดสิ้นสุดอยู่ที่กึ่งกลาง Pharmacy Card เท่ากันทุกแพลตฟอร์ม

## 4. ระบบ Anti-Overscroll
เพื่อให้รอยต่อระหว่าง Header และ แผนที่ดูเนียนตาเมื่อผู้ใช้ดึงหน้าจอ (Bounce/Overscroll)

*   **วิธีปฏิบัติ:** ใช้ `Positioned` สีเขียวมินต์ (`AppColors.primary`) วางไว้ที่ Layer ล่างสุดของ Stack เสมอ เพื่อเป็นสีรองพื้นเมื่อมีการยืดหน้าจอ
*   **Scroll Physics:** ใช้ `AlwaysScrollableScrollPhysics` เพื่อรักษาความรู้สึกลื่นไหลของ iOS แต่ต้องมั่นใจว่าระบบ Offset และ Map Height คำนวณถูกต้องเพื่อไม่ให้เห็นช่องว่างพื้นหลังสีขาว

---
*บันทึกครั้งล่าสุด: 28 เมษายน 2026*
