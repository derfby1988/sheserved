# Procurement / Purchasing (ระบบจัดซื้อจัดจ้าง)

## ภาพรวม (Overview)
ระบบสำหรับการจัดซื้อสินค้า ยา และอุปกรณ์ทางการแพทย์เข้ามาเติมในคลัง ช่วยควบคุมต้นทุนและการอนุมัติสั่งซื้อให้เป็นระบบ

## ฟีเจอร์หลักเบื้องต้น (Core Features)
- **Supplier Management:** จัดการฐานข้อมูลผู้จัดจำหน่าย (Vendors/Suppliers)
- **Purchase Requisition (PR):** การทำใบขอซื้อจากแผนกต่างๆ (เช่น ห้องยาขอซื้อยาเพิ่ม)
- **Purchase Order (PO):** การออกใบสั่งซื้ออย่างเป็นทางการเพื่อส่งให้ Supplier
- **Approval Workflow:** ระบบอนุมัติใบขอซื้อและใบสั่งซื้อตามระดับสิทธิ์ (Role-based Approval)
- **Goods Receipt:** การบันทึกรับสินค้าเข้าคลังเมื่อ Supplier มาส่งของ

## การเชื่อมโยงกับระบบอื่น (Integrations)
- **[Inventory System](INVENTORY_SYSTEM_PLAN.md):** การกดรับของ (Goods Receipt) จะทำการเพิ่มจำนวนสินค้าลงใน Stock โดยอัตโนมัติ
- **[Accounting System](ACCOUNTING_SYSTEM_PLAN.md):** เมื่อรับของแล้ว จะเกิดรายการตั้งหนี้ (Accounts Payable) ไปที่ระบบบัญชี

## แผนการพัฒนา (Implementation Plan Placeholder)
*(พื้นที่สำหรับเขียน DB Schema, Flutter UI, และ Business Logic ในอนาคต)*

### 1. Database Schema
- `suppliers`
- `purchase_orders`
- `purchase_order_items`

### 2. Flutter UI
- `PoManagementPage`
- `SupplierDirectoryPage`
