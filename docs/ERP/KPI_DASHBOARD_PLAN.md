# KPI Dashboard Plan — Sheserved ERP

## ภาพรวม (Overview)

**KPI Dashboard** คือศูนย์กลางการแสดงผลสรุปเมตริกและเป้าหมายขององค์กร (Executive View) ซึ่งออกแบบมาเพื่อให้เจ้าของกิจการ (Owner) หรือผู้จัดการ (Manager) สามารถติดตามความคืบหน้าของยอดขาย กำไร และประสิทธิภาพของพนักงาน เปรียบเทียบกับเป้าหมายที่ตั้งไว้ (Actual vs Target) ได้แบบ Real-time

### การบูรณาการร่วมกับ ERP Dashboard
- **แยกหน้าต่าง/แถบ (Separate Tab or Page):** KPI Dashboard จะใช้ UI ร่วมกับ `ErpDashboardPage` หลัก แต่จะถูกออกแบบเป็น **Tab แยกลำพัง** หรือปุ่มเข้าสู่หน้า **Executive Dashboard** เฉพาะ เพื่อป้องกันความสับสนกับหน้าการทำงานประจำวัน (Operation Dashboard) ของพนักงานทั่วไป

---

## 1. การตั้งเป้าหมายและการดึงข้อมูล (Metrics & Integrations)

ข้อมูลบน KPI Dashboard จะเกิดจากการบูรณาการข้อมูลจาก 3 โมดูลหลัก ได้แก่:

### A. เป้าหมายระดับองค์กรและการเงิน (อิงจาก Accounting / Finance)
- **ตั้งเป้าหมายยอดขาย/กำไร:** กำหนดเป้า (Target) เป็น รายวัน, รายสัปดาห์, รายไตรมาส, และรายปี
- **Actual Data:** ระบบจะดึงยอดรวมที่เกิดขึ้นจริงแบบเรียลไทม์จากระบบ **POS (ยอดขาย)** และ **Accounting (กำไรสุทธิ - Net Profit)** มาเปรียบเทียบในรูปแบบกราฟ (เช่น Bar Chart / Gauge Chart)

### B. เป้าหมายรายบุคคลและการประเมิน (อิงจาก HR System)
- **ตั้งเป้าหมายพนักงาน (Individual Quota):** ตั้งยอดเป้าหมายการขายต่อคน เช่น ทันตแพทย์ A, เภสัชกร B
- **Actual Data:** ดึงข้อมูลจากระบบ POS โดยอ้างอิงฟิลด์ `served_by` เพื่อดูประสิทธิภาพ (Performance) ของพนักงาน
- **นำไปใช้:** ตัวเลขนี้จะถูกส่งกลับไปที่ **HR System** เพื่อคำนวณโบนัสและค่าคอมมิชชั่นเมื่อสิ้นสุดรอบประเมิน

---

## 2. สิทธิการเข้าถึงข้อมูล (Permissions & Access Control)

ระบบ KPI Dashboard ถูกควบคุมความปลอดภัยโดยตรงจากแผนงานหน้าจัดการสิทธิพนักงานในไฟล์ `HR_SYSTEM_PLAN.md` โดยใช้ระบบ `employee_roles` และ `role_module_permissions`:

1. **ระดับเจ้าขององค์กร (Owner / Executive Role):**
   - **Permission Level:** `Full Access`
   - **Scope:** เข้าถึงแถบ KPI Dashboard ได้ 100% สามารถกำหนดตัวเลขเป้าหมายรวม (Target) และดูตัวเลขยอดขาย/กำไร ของ **"ทุกสาขา (All Branches)"** และดูเป้าหมายของพนักงานทุกคนได้
2. **ระดับผู้จัดการ (Branch Manager Role):**
   - **Permission Level:** `View` หรือ `Edit (เฉพาะตั้งเป้าพนักงาน)`
   - **Scope:** สามารถเข้าถึง KPI Dashboard ได้ แต่เห็นตัวเลขเป้าหมายและยอดขายเฉพาะของ **"สาขาที่ตนเองดูแลเท่านั้น"**
3. **ระดับพนักงานทั่วไป (Staff / Employee Role):**
   - **Permission Level:** `No Access` สำหรับ KPI รวมของบริษัท
   - **Scope:** หากองค์กรตั้งให้พนักงานเห็นเป้าตัวเองได้ พนักงานจะเห็นเฉพาะหน้า Dashboard ของตัวเองเท่านั้น (Individual Performance) ว่าตนเองทำยอดไปเท่าไหร่และขาดอีกเท่าไหร่

*หมายเหตุ: สิทธิ์การเข้าถึง KPI Dashboard ไม่ได้ถูกผูกมัดกับ Role ของพนักงานอย่างตายตัว ในหน้าต่าง "จัดการสิทธิพนักงาน" (HR Dashboard) จะมี **Toggle Switch ควบคุมสิทธิ์โมดูล KPI Dashboard แยกต่างหาก** ทำให้ Owner/Admin สามารถเปิดหรือปิดการเข้าถึงให้กับพนักงานคนใดก็ได้ตามต้องการอย่างยืดหยุ่น (บันทึกสิทธิ์ลงใน `role_module_permissions`)*

---

## 3. Database Schema (ร่าง)

เพื่อเก็บข้อมูลเป้าหมาย (Target) จำเป็นต้องมีตารางบันทึกการตั้งค่าแยกออกมา (ส่วนยอด Actual ดึง Query จากระบบอื่น):

```sql
CREATE TABLE kpi_targets (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profession_id     UUID NOT NULL REFERENCES professions(id) ON DELETE CASCADE,
  branch_id         UUID REFERENCES organization_branches(id), -- NULL = เป้าหมายรวมทุกสาขา
  employee_id       UUID REFERENCES employees(id),             -- NULL = เป้าหมายระดับองค์กร/สาขา
  
  target_type       TEXT NOT NULL,                             -- เช่น 'revenue', 'net_profit', 'appointments'
  target_amount     DECIMAL(15,2) NOT NULL,                    -- ตัวเลขเป้าหมาย
  period_type       TEXT NOT NULL,                             -- เช่น 'daily', 'weekly', 'monthly', 'quarterly', 'yearly'
  
  start_date        DATE NOT NULL,
  end_date          DATE NOT NULL,
  
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);
```

---

## 4. แผนการพัฒนา UI (Implementation Phases)
- **Phase A:** พัฒนาหน้า Tab `KPIDashboardView` และฝังลงในหน้าจอ `ErpDashboardPage`
- **Phase B:** สร้างหน้า Modal เพื่อให้ Owner/Manager สามารถกรอกฟอร์มเพื่อบันทึกตัวเลขลงตาราง `kpi_targets`
- **Phase C:** สร้าง Chart Widgets (ใช้ไลบรารีเช่น `fl_chart`) เพื่อดึงข้อมูล Actual จาก POS/Accounting มาเทียบกับ Target ตาม `period_type`
