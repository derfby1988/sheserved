# Sheserved UI Architecture & Rendering Standards (Home Page)

เอกสารนี้รวบรวมเทคนิค กฎเกณฑ์ และตรรกะ (Logic) ทั้งหมดที่ใช้ในหน้า Home เพื่อรักษาความสม่ำเสมอของ UI/UX ระหว่าง iOS และ Android

## 1. การจัดการ Rendering & Layer (Z-Order)
ใช้จัดการปัญหา Native Platform View (Google Maps) บดบัง Flutter UI บน iOS

*   **Compositing Force:** ครอบ Foreground UI ด้วย `Opacity(opacity: 0.999)` เพื่อบังคับให้ iOS สร้าง Compositing Layer แยกจากแผนที่
*   **Map Clipping:** ใช้ `ClipRect` พร้อม `clipBehavior: Clip.hardEdge` ครอบแผนที่เพื่อป้องกัน Native View เรนเดอร์ล้นขอบเขต
*   **Impeller Gradients:** ห้ามใช้ `Colors.transparent` (Black-based) ให้ใช้สีพื้นฐานที่มี Alpha 0 แทน และใช้ **7 stops** เพื่อความเนียนบน iOS

## 2. Dynamic Layout & Platform Offsets
การจัดวางตำแหน่งที่ปรับตามแพลตฟอร์มเพื่อให้ได้ Visual Parity

*   **Map Start Position:**
    *   **Android:** เริ่มที่ `_headerSectionHeight / 2` (เพื่อให้แผนที่ลอดใต้ Header ที่โปร่งใส)
    *   **iOS:** เริ่มที่ `_headerSectionHeight` (เพื่อหลีกเลี่ยงการเรนเดอร์ทับซ้อนของ Platform View ในส่วน Header)
*   **Dynamic Height:** `_mapHeight` ต้องคำนวณจาก `TargetBottom (กึ่งกลาง Pharmacy Card) - MapStartOffset` เสมอ

## 3. UX Logic: Snap-to-Corner Interaction
ระบบการจัดการ "วงกลมปรึกษา" (Consultation Widget)

*   **Long-press to Drag:** ผู้ใช้สามารถกดค้างเพื่อเปลี่ยนเป็นโหมด Mini และลากไปวางตามมุมต่างๆ
*   **Snap Points:** มี 9 จุดยึด (8 มุม/ขอบ + 1 กึ่งกลาง) โดยระบบจะคำนวณจุดที่ใกล้ที่สุดเมื่อปล่อยนิ้ว
*   **Persistence:** ตำแหน่งที่เลือกจะถูกบันทึกใน `user_preferences` บน Supabase (Key: `home_consultation_position`) เพื่อให้คงอยู่เมื่อเปิดแอปใหม่

## 4. UI Flow: Emergency Response System
การทำงานร่วมกันระหว่างระบบแจ้งเหตุและ UI หลัก

*   **Auto-Miniaturization:** เมื่อมีเหตุฉุกเฉินระดับ **Professional** เข้ามา วงกลมปรึกษาจะย่อขนาดอัตโนมัติและหลบไปที่ `leftCenter` เพื่อเปิดพื้นที่ให้การ์ดแจ้งเหตุ (Stacked Cards)
*   **Exclusion Logic:** 
    *   ผู้แจ้งเหตุ (Reporter) จะไม่เห็นการ์ดแจ้งเหตุของตัวเอง
    *   Professional จะเห็นการ์ดเมื่ออยู่ในรัศมี (Alert Radius) และยังไม่มีคนในอาชีพเดียวกันรับงาน
    *   Thai Mhung จะเห็นเป็น Badge แจ้งเตือนที่ Header เท่านั้น (ไม่รบกวนหน้าจอหลัก)

## 5. Visual UX & Transitions
*   **Scroll-Driven UI:** เมื่อ Scroll ลง แถบค้นหาจะเปลี่ยน Border Radius จากมนกลมเป็นเหลี่ยมมนเพื่อประหยัดพื้นที่
*   **Anti-Overscroll:** ใช้ `Positioned` สีเขียวมินต์เป็นพื้นหลังชั้นล่างสุดเพื่อรองรับแรงดึง (Bounce) ของ iOS ไม่ให้เห็นช่องว่างสีขาว
*   **Map Overlay:** ใช้ Gradient Overlay ทับด้านบนแผนที่ (Top 20%) เพื่อสร้าง Transition ที่นุ่มนวลระหว่าง Header และ แผนที่

---
*บันทึกครั้งล่าสุด: 28 เมษายน 2026*
