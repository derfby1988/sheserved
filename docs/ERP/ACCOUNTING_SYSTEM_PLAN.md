# Accounting / Finance (ระบบบัญชีและการเงิน)

## ภาพรวม (Overview)
ระบบหลังบ้านสำหรับบันทึกเส้นทางการเงินของคลินิก เพื่อให้เห็นภาพรวมของรายได้ ค่าใช้จ่าย และผลกำไรขาดทุน
ทุกองค์กรที่มีสิทธิ์ใช้งาน POS (`uses_pos_system = true`) จะได้รับระบบ Accounting ของตนเองโดยแยกตาม `profession_id` เพื่อให้ข้อมูลการเงินเป็นเอกเทศจากองค์กรอื่น.
## ฟีเจอร์หลักเบื้องต้น (Core Features)
- **Chart of Accounts (ผังบัญชีมาตรฐานไทย):** รองรับการแยกหมวดหมู่บัญชี 5 หมวด (สินทรัพย์, หนี้สิน, ทุน, รายได้, ค่าใช้จ่าย) ตามมาตรฐานบัญชีไทยและอ้างอิงข้อกำหนดของ **กรมสรรพากร**
- **General Ledger (บัญชีแยกประเภท/สมุดรายวันทั่วไป):** บันทึกทุก Transaction ทางการเงินแบบ Double-Entry (Debit/Credit) ที่สอดคล้องกับผังบัญชีมาตรฐาน
- **Accounts Receivable (AR) / ลูกหนี้การค้า:** ติดตามยอดค้างชำระ (เช่น กรณีลูกค้าองค์กรวางบิล)
- **Accounts Payable (AP) / เจ้าหนี้การค้า:** ติดตามยอดค้างจ่ายแก่ Supplier
- **Tax Management & Reporting (ระบบจัดการภาษี):** จัดทำรายงานภาษีขาย (Sales Tax), ภาษีซื้อ (Purchase Tax), และภาษีหัก ณ ที่จ่าย (Withholding Tax) รายเดือน/รายปี เพื่อนำส่งกรมสรรพากร (ภ.พ.30, ภ.ง.ด.3, ภ.ง.ด.53) ตามกฎหมายไทย

# Updated tax reporting requirements with frequency categories
### รายงานภาษีที่ต้องจัดเก็บ (Tax Reporting Requirements)
- รายการขายและใบกำกับภาษี (Tax Invoice) พร้อมข้อมูลสินค้า/บริการ, จำนวน, ราคาต่อหน่วย, อัตราภาษี, มูลค่าภาษี **(รายเดือน)**
- รายการซื้อจัดซื้อและใบกำกับภาษีขาเข้า (Purchase Tax Invoice) พร้อมอัตราภาษีและมูลค่าภาษี **(รายเดือน)**
- รายการหัก ณ ที่จ่ายต่อผู้ให้บริการ (Withholding Tax) พร้อมฐานภาษีและอัตราที่หัก **(รายเดือน / รายไตรมาส)**
- สรุปภาษีมูลค่าเพิ่ม (VAT) รายเดือนรวมถึง VAT ค้างรับ/ค้างจ่าย **(รายเดือน)**
- การจัดทำไฟล์ CSV/Excel สำหรับส่งต่อกรมสรรพากร (ภ.30, ภ.ง.ด.3, ภ.ง.ด.53) พร้อมลายเซ็นดิจิทัล **(รายเดือน / รายปี)**
- บันทึก Audit Trail ของการเปลี่ยนแปลงข้อมูลภาษี (ผู้แก้ไข, เวลา, เหตุผล) เพื่อการตรวจสอบ **(ต่อเนื่อง)**
- รองรับการส่งออกแบบ XML/JSON ตามมาตรฐาน e‑Filing ของกรมสรรพากร **(รายไตรมาส / รายปี)**
- เก็บสำเนาใบกำกับภาษีอิเล็กทรอนิกส์ (e‑Invoice) ตามข้อกำหนด **(ต่อเนื่อง)**
- รองรับหลายสกุลเงินและอัตราแปลงสกุลเงินในกรณีองค์กรที่ทำธุรกรรมต่างประเทศ **(ต่อเนื่อง)**
- รายการขายและใบกำกับภาษี (Tax Invoice) พร้อมข้อมูลสินค้า/บริการ, จำนวน, ราคาต่อหน่วย, อัตราภาษี, มูลค่าภาษี
- รายการซื้อจัดซื้อและใบกำกับภาษีขาเข้า (Purchase Tax Invoice) พร้อมอัตราภาษีและมูลค่าภาษี
- รายการหัก ณ ที่จ่ายต่อผู้ให้บริการ (Withholding Tax) พร้อมฐานภาษีและอัตราที่หัก
- สรุปภาษีมูลค่าเพิ่ม (VAT) รายเดือนรวมถึง VAT ค้างรับ/ค้างจ่าย
- การจัดทำไฟล์ CSV/Excel สำหรับส่งต่อกรมสรรพากร (ภ.30, ภ.ง.ด.3, ภ.ง.ด.53) พร้อมลายเซ็นดิจิทัล
- บันทึก Audit Trail ของการเปลี่ยนแปลงข้อมูลภาษี (ผู้แก้ไข, เวลา, เหตุผล) เพื่อการตรวจสอบ
- รองรับการส่งออกแบบ XML/JSON ตามมาตรฐาน e‑Filing ของกรมสรรพากร
- เก็บสำเนาใบกำกับภาษีอิเล็กทรอนิกส์ (e‑Invoice) ตามข้อกำหนด
- รองรับหลายสกุลเงินและอัตราแปลงสกุลเงินในกรณีองค์กรที่ทำธุรกรรมต่างประเทศ
- **Financial Reports:** สรุปงบกำไรขาดทุน (P&L), งบทดลอง

## ฟอร์มภาษีของกรมสรรพากร (Revenue Department Tax Forms)

| ฟอร์ม | ชื่อเต็ม | รายงานที่เกี่ยวข้อง | ความถี่ |
|------|----------|-------------------|--------|
| **ภ.ง.ด.1** | ภาษีเงินได้บุคคลธรรมดา (Personal Income Tax) | รายได้จากการขาย, ค่าตัดบัญชีเงินเดือน | รายปี |
| **ภ.ง.ด.3** | ภาษีหัก ณ ที่จ่าย (Withholding Tax) | รายการหัก ณ ที่จ่าย | รายเดือน / ไตรมาส |
| **ภ.ง.ด.53** | ภาษีมูลค่าเพิ่ม (VAT) | สรุป VAT รายเดือน | รายเดือน |
| **ภ.ง.ด.5** | ใบกำกับภาษี (Tax Invoice) | รายการขาย, ใบกำกับภาษี | รายเดือน |
| **ภ.ง.ด.30** | รายการส่งภาษี (Tax Return) | สรุปภาษีรวม | รายปี |
| **ภ.ง.ด.2** | ภาษีเงินได้ประเมิน (Estimated Income Tax) | การคำนวนภาษีก่อนปีใหม่ | รายครึ่งปี |
| **ภ.ง.ด.53 (สถิติ)** | รายงานสถิติ VAT | รายสถิติการเสีย VAT | รายไตรมาส |
| **ภ.ง.ด.6** | รายงานภาษีศุลกากร (Customs Tax) | หากมีการนำเข้า/ส่งออก | รายปี |

### โครงสร้างฐานข้อมูล (Database Schema)

> **หมายเหตุ:** ตารางภาษีในระบบปัจจุบันใช้ `tax_forms` + `tax_form_lines` (see ER Diagram) สำหรับเก็บข้อมูลฟอร์มภาษีทั่วไป ตารางย่อยเฉพาะทาง (`tax_record`, `personal_income_tax`, `withholding_tax`) เป็น **แผนอนาคต** สำหรับ e-Filing ขั้นสูง ยังไม่มี migration ในระบบปัจจุบัน



## การเชื่อมโยงกับระบบอื่น (Integrations)
- **[POS System](../plans/implementation_plan.md):** รายรับจากการขายหน้าร้านจะถูกลงบัญชีเป็น 'รายได้' และ 'เงินสด/เงินฝาก'
- **[Procurement System](PROCUREMENT_SYSTEM_PLAN.md):** ใบ PO ที่รับของแล้วจะถูกตั้งเป็น 'เจ้าหนี้การค้า (AP)' และบันทึกเป็น 'ต้นทุนสินค้า'
- **[HR System](HR_SYSTEM_PLAN.md):** การจ่ายเงินเดือนและค่าคอมมิชชั่นจะถูกบันทึกเป็น 'ค่าใช้จ่าย'

## การเชื่อมโยงสินค้าและผังบัญชี (Product-Account Mapping)
- **Tenant-Specific Mapping:** แต่ละองค์กร (Tenant) สามารถตั้งค่าผูก (Map) รายการสินค้า/บริการ/แพ็กเกจของตนเอง เข้ากับรหัสบัญชีที่ต้องการได้อย่างอิสระ
- **Smart Recommendation:** เมื่อองค์กรสร้างสินค้าหรือบริการใหม่ ระบบจะทำการวิเคราะห์จาก "หมวดหมู่สินค้า (Category)" และ "ประเภทสินค้า (Type)" เพื่อ **แนะนำผังบัญชีที่ควรจะเป็น** ให้อัตโนมัติ (เช่น ถ้าสร้างหมวด "ยา" ระบบจะแนะนำให้ผูกฝั่งรายรับกับ `4100 รายได้จากการขาย` และฝั่งต้นทุนกับ `5100 ต้นทุนขาย`) เพื่อความสะดวกและลดข้อผิดพลาด

## ข้อมูลตั้งต้นสำหรับผังบัญชีมาตรฐาน (Master Chart of Accounts)
ระบบจะเก็บผังบัญชีมาตรฐานไทยไว้ในตาราง master แยกต่างหาก (`standard_chart_of_accounts`) และเมื่อองค์กร/profession ใหม่ถูกสร้าง ระบบจะคัดลอกข้อมูลจาก master table ไปยัง `chart_of_accounts` ของ profession นั้นโดยอัตโนมัติ (trigger `trg_seed_chart_of_accounts_on_profession_insert`) จากนั้นองค์กรสามารถปรับแก้ เพิ่มเติม หรือแตกบัญชีย่อยได้เอง โดย **ห้ามแก้ไข master table ของ Sheserved**

### สถาปัตยกรรม Master → Profession Copy
- **`standard_chart_of_accounts`** — ผังบัญชีมาตรฐานไทย (read-only, 40 บัญชี)
- **`chart_of_accounts`** — ผังบัญชีของแต่ละ profession (seeded from master + editable)
  - `standard_account_id` — FK อ้างอิงถึง master row (traceability)
  - `is_custom` — `false` = จาก master, `true` = สร้าง/แก้ไขโดยผู้ใช้
- **RPC `seed_profession_chart_of_accounts(p_profession_id)`** — คัดลอก master → profession chart (idempotent)
- **RPC `reset_chart_of_account_to_standard(p_account_id)`** — คืนค่าบัญชีที่แก้ไขกลับไปตาม master (per-item)
- **RPC `get_chart_of_account_dependencies(p_account_id)`** — ตรวจสอบความสัมพันธ์ก่อนลบ (GL, journal, parent, products)
- **RPC `delete_chart_of_account(p_account_id)`** — ลบบัญชีที่ไม่มี dependency (safe delete)

> **หมายเหตุ:** `account_type` ใน database เก็บเป็น `smallint` (1=asset, 2=liability, 3=equity, 4=revenue, 5=expense) แต่ Flutter model (`ChartOfAccount.fromJson`) แปลงเป็น `String` ('asset', 'liability', 'equity', 'revenue', 'expense') เสมอ ทำให้ UI ไม่ต้องสนใจ schema mode

### รายการบัญชีมาตรฐาน (40 บัญชี จาก `standard_chart_of_accounts`)
1. **หมวด 1: สินทรัพย์ (Assets) [รหัส 1XXX]**
   - `1111` เงินสดในมือ (Cash on Hand)
   - `1112` เงินฝากธนาคารออมทรัพย์ (Savings Accounts)
   - `1113` เงินฝากธนาคารกระแสรายวัน (Current Accounts)
   - `1121` ลูกหนี้การค้า (Accounts Receivable)
   - `1122` ค่าเผื่อหนี้สงสัยจะสูญ (Allowance for Doubtful Accounts)
   - `1131` สินค้าคงเหลือ - ยาและเวชภัณฑ์ (Inventory - Medicines & Medical Supplies)
   - `1132` สินค้าคงเหลือ - เครื่องสำอางและสินค้าอื่นๆ (Inventory - Cosmetics & Others)
   - `1141` ภาษีซื้อรอนำส่ง / ภาษีถูกหัก ณ ที่จ่าย (Withholding Tax Receivable)
   - `1151` ค่าใช้จ่ายจ่ายล่วงหน้า (Prepaid Expenses)
   - `1211` อุปกรณ์ทางการแพทย์และเครื่องมือ (Medical Equipment)
   - `1212` ค่าเสื่อมราคาสะสม - อุปกรณ์ทางการแพทย์ (Accumulated Depreciation - Medical Equipment)
   - `1221` เครื่องตกแต่งและเครื่องใช้สำนักงาน (Furniture & Office Equipment)
   - `1222` ค่าเสื่อมราคาสะสม - เครื่องตกแต่งและเครื่องใช้สำนักงาน (Accumulated Depreciation - Furniture & Office)
2. **หมวด 2: หนี้สิน (Liabilities) [รหัส 2XXX]**
   - `2111` เจ้าหนี้การค้า (Accounts Payable)
   - `2121` ค่าใช้จ่ายค้างจ่าย (Accrued Expenses)
   - `2131` ภาษีเงินได้หัก ณ ที่จ่าย รอนำส่ง (Withholding Tax Payable)
   - `2132` ภาษีมูลค่าเพิ่มรอนำส่ง (VAT Payable)
   - `2133` ประกันสังคมรอนำส่ง (Social Security Payable)
   - `2141` รายได้รับล่วงหน้า / เงินมัดจำรับ (Unearned Revenue / Customer Deposits) - *สำคัญสำหรับการขายคอร์ส*
   - `2211` เงินกู้ยืมระยะยาว (Long-term Loans)
3. **หมวด 3: ส่วนของเจ้าของ / ทุน (Equity) [รหัส 3XXX]**
   - `3111` ทุนจดทะเบียน (Registered Capital)
   - `3112` ทุนที่เรียกชำระแล้ว (Paid-in Capital)
   - `3211` กำไร(ขาดทุน)สะสม - ยังไม่ได้จัดสรร (Retained Earnings - Unappropriated)
   - `3212` ถอนใช้ส่วนตัว / เงินปันผลจ่าย (Drawings / Dividends)
4. **หมวด 4: รายได้ (Revenues) [รหัส 4XXX]**
   - `4111` รายได้จากการขายยาและเวชภัณฑ์ (Revenue from Medicines)
   - `4112` รายได้จากการขายผลิตภัณฑ์อื่นๆ (Revenue from Other Products)
   - `4211` รายได้จากการตรวจรักษาพยาบาล (Revenue from Medical Services)
   - `4212` รายได้จากการทำหัตถการ/ศัลยกรรม (Revenue from Procedures/Surgery)
   - `4311` รายได้ดอกเบี้ยรับ / รายได้อื่นๆ (Interest / Other Income)
5. **หมวด 5: ค่าใช้จ่าย (Expenses) [รหัส 5XXX]**
   - `5111` ต้นทุนยาและเวชภัณฑ์ที่ใช้ไป (Cost of Medicines Used)
   - `5112` ต้นทุนผลิตภัณฑ์อื่นๆที่ขาย (Cost of Other Products Sold)
   - `5121` ค่าธรรมเนียมแพทย์ / ค่ามือแพทย์ (Doctor Fees/Commissions)
   - `5211` เงินเดือนและค่าจ้างพนักงาน (Salaries & Wages)
   - `5212` ค่าล่วงเวลา / โอที (Overtime)
   - `5213` เงินสมทบกองทุนประกันสังคม (Social Security Contributions)
   - `5221` ค่าเช่าสถานที่และบริการ (Rent & Services)
   - `5222` ค่าน้ำประปา ไฟฟ้า โทรศัพท์ และอินเทอร์เน็ต (Utilities & Communication)
   - `5223` ค่าโฆษณาและส่งเสริมการขาย (Advertising & Marketing)
   - `5231` ค่าเสื่อมราคา - อุปกรณ์และเครื่องใช้ (Depreciation Expense)
   - `5241` ค่าธรรมเนียมธนาคาร / ค่าธรรมเนียม Payment Gateway (Bank / Gateway Fees)

## แผนการพัฒนา (Implementation Plan)

### 1. ไฟล์ที่สร้างแล้ว (Completed Artifacts)

| ไฟล์ | ที่อยู่ | รายละเอียด |
|------|--------|-----------|
| **SQL Migration** | `supabase/migrations/20260609180000_create_accounting_core_schema.sql` | Schema หลัก: ตาราง 11 ตาราง + โครงสร้างผังบัญชี |
| **SQL Migration** | `supabase/migrations/20260613170000_standard_chart_of_accounts_template.sql` | Master chart table (`standard_chart_of_accounts`) + RPC `seed_profession_chart_of_accounts` + RPC `reset_chart_of_account_to_standard` + RPC `get_chart_of_account_dependencies` + RPC `delete_chart_of_account` + `is_custom` flag + `standard_account_id` FK + auto-seed trigger |
| **ER Diagram** | `docs/ERP/ACCOUNTING_ER_DIAGRAM.md` | Mermaid ER Diagram + รายละเอียดคอลัมน์ทุกตาราง |
| **Outbox Spec** | `docs/ERP/ACCOUNTING_OUTBOX_SPEC.md` | ตัวอย่าง payload POS→Accounting, Procurement→Accounting, HR→Accounting |
| **Flutter Model** | `lib/features/erp/data/models/chart_of_account.dart` | `ChartOfAccount` model — รองรับ `smallint`→`String` account_type mapping, `is_custom`, `standard_account_id` |
| **Flutter Repository** | `lib/features/erp/data/repositories/phase_three_repository.dart` | `PhaseThreeRepository` — CRUD + seed + reset + dependency check + delete + `getChartOfAccountsAccountTypeMode()` |
| **Flutter Provider** | `lib/features/erp/presentation/providers/phase_three_provider.dart` | `PhaseThreeNotifier` — load/create/update/reset/checkDelete/delete COA + load GL/AR/AP/Employees/Shifts |
| **Flutter UI** | `lib/features/erp/presentation/pages/chart_of_accounts_page.dart` | `ChartOfAccountsPage` — grouped sliver list, search, filter chips, custom visual, reset/delete dialogs |

### 2. ตารางหลักใน Database (12 ตาราง)

- **`organization_branches`** — สาขาขององค์กร (multi-branch support)
- **`outbox_events`** — Outbox Pattern (event ต้นทางจาก POS/Procurement/HR)
- **`idempotency_keys`** — กันซ้ำสำหรับ write operation
- **`exchange_rates`** — อัตราแลกเปลี่ยนสกุลเงิน
- **`accounting_periods`** — งวดบัญชี (open/closed/locked)
- **`standard_chart_of_accounts`** — master template ผังบัญชีมาตรฐาน (read-only, 40 บัญชี)
- **`chart_of_accounts`** — ผังบัญชีของแต่ละ profession (copied from master + custom additions)
  - `standard_account_id` (UUID, FK) — อ้างอิง master row
  - `is_custom` (BOOLEAN) — `false`=seeded from master, `true`=user-created/modified
- **`product_account_mappings`** — ผูกสินค้ากับบัญชี (smart recommendation base)
- **`journal_entries`** — รายการบัญชี (header)
- **`journal_entry_lines`** — บรรทัดรายการ (debit/credit double-entry)
- **`vat_records`** — รายการ VAT (output=input)
- **`tax_forms`** + **`tax_form_lines`** — ฟอร์มภาษีกรมสรรพากร

`general_ledger` เป็น **View** ที่รวม `journal_entries` + `journal_entry_lines` + `chart_of_accounts` สำหรับบัญชีแยกประเภท

### 3. Outbox Integration (ระบบเชื่อมโยง)

ทุก write operation ที่มีผลต่อเงินหรือสต๊อกต้องผ่าน `outbox_events` ก่อน commit:

| Event | Source | Accounting Impact |
|-------|--------|-------------------|
| `pos.sale.completed` | POS System | บันทึกรายได้ + ต้นทุน + VAT ขาย |
| `procurement.goods_received` | Procurement System | บันทึกสินค้าเข้า + เจ้าหนี้ + VAT ซื้อ |
| `hr.payroll.processed` | HR System | บันทึนค่าใช้จ่ายเงินเดือน + หัก ณ ที่จ่าย |
| `accounting.journal.created` | Manual Entry | บันทึกรายการปรับปรุง/ค่าเสื่อม |

Accounting Worker จะ poll `outbox_events` ทุก 5 วินาที → parse payload → สร้าง `journal_entries` (draft → posted) → สร้าง `vat_records` (ถ้ามี) → อัปเดต outbox เป็น `published`

### 4. Flutter Architecture Outline

#### โครงสร้างโฟลเดอร์ (Actual — ERP Phase 3)
```
lib/features/erp/
├── data/
│   ├── models/ (ChartOfAccount, GlEntry, AccountsReceivable, AccountsPayable, Employee, Shift, DashboardSnapshot)
│   └── repositories/ (PhaseThreeRepository)
└── presentation/
    ├── pages/
    │   ├── chart_of_accounts_page.dart — ผังบัญชี 5 หมวด (grouped list + search + filter)
    │   ├── gl_entries_page.dart — รายการบัญชีแยกประเภท
    │   ├── accounts_receivable_page.dart — ลูกหนี้การค้า
    │   ├── accounts_payable_page.dart — เจ้าหนี้การค้า
    │   ├── employee_list_page.dart — พนักงาน
    │   └── shift_management_page.dart — ตารางเวร
    ├── widgets/
    │   └── glass_card.dart
    └── providers/
        └── phase_three_provider.dart
```

**Chart of Accounts UI (`chart_of_accounts_page.dart`)**
- **Grouped by Type:** แสดงบัญชีจัดกลุ่มตาม 5 หมวด (สินทรัพย์ → หนี้สิน → ทุน → รายได้ → ค่าใช้จ่าย) พร้อม Section Header แสดงจำนวนบัญชีในแต่ละหมวด
- **Search:** ช่องค้นหารหัสบัญชีหรือชื่อบัญชีแบบ real-time
- **Type Filter:** ChoiceChips กรองแสดงเฉพาะหมวดที่เลือก (ทั้งหมด / สินทรัพย์ / หนี้สิน / ทุน / รายได้ / ค่าใช้จ่าย)
- **Custom-only Filter:** FilterChip "เฉพาะที่สร้าง/แก้ไขเอง" — กรองแสดงเฉพาะ `is_custom = true`
- **Color Coding:** แต่ละหมวดมีสีประจำตัว (สินทรัพย์=เขียว, หนี้สิน=แดง, ทุน=น้ำเงิน, รายได้=ฟ้า, ค่าใช้จ่าย=ส้ม)
- **Custom Account Visual:** บัญชีที่สร้าง/แก้ไขเอง (`is_custom = true`) แสดง:
  - แถบซ้ายสี `amber` (แทนสีหมวดปกติ)
  - ชื่อบัญชีสี `amber.700`
  - Badge "Custom" พร้อมพื้นหลัง amber จาง
- **CRUD Dialog:** แตะที่บัญชีเพื่อแก้ไข หรือกด FAB เพื่อเพิ่มบัญชีใหม่
  - สร้างใหม่ → `is_custom = true`
  - แก้ไข → `is_custom = true` (แม้เดิมมาจาก master)
- **Reset to Standard:** ไอคอน `restore` บน card ของบัญชีที่แก้ไขจาก master (`is_custom = true && standard_account_id != null`) → คืนค่า code/name/type ตาม master → `is_custom = false`
- **Delete Custom Account:** ไอคอน `delete_outline` (สีแดง) บน card ของบัญชีที่ **สร้างใหม่เองเท่านั้น** (`is_custom = true && standard_account_id == null`) — ไม่แสดงบนบัญชีที่แก้ไขจากมาตรฐาน (มี `standard_account_id`) → ตรวจสอบ dependency (GL entries, journal lines, parent accounts, linked products) → ถ้ามี blocking items แจ้งรายการที่ขัดขวาง → ถ้าสะอาด → ยืนยัน → ลบ
- **Auto-seed:** โหลดครั้งแรกจะเรียก RPC `seed_profession_chart_of_accounts` เพื่อคัดลอกจาก `standard_chart_of_accounts` อัตโนมัติ

#### State Management (Riverpod — PhaseThreeProvider)
- **PhaseThreeNotifier** — รวม state ทุก subdomain ของ Phase 3:
  - `loadChartOfAccounts()` / `createChartOfAccount()` / `updateChartOfAccount()` / `resetChartOfAccount()` / `checkDeleteChartOfAccount()` / `deleteChartOfAccount()` — ผังบัญชี
  - `loadGlEntries()` / `createGlEntry()` / `createGlFromOrder()` — รายการบัญชี
  - `loadAccountsReceivable()` / `updateArStatus()` — ลูกหนี้
  - `loadAccountsPayable()` / `updateApStatus()` — เจ้าหนี้
  - `loadEmployees()` / `createEmployee()` / `updateEmployee()` — พนักงาน
  - `loadShifts()` / `createShift()` / `updateShift()` — ตารางเวร
  - `loadSnapshots()` / `upsertSnapshot()` — Dashboard analytics

#### Routes (ERP Dashboard → Phase 3 Modules)
```
/erp/chart-of-accounts          → ChartOfAccountsPage
/erp/gl-entries                 → GlEntriesPage
/erp/accounts-receivable        → AccountsReceivablePage
/erp/accounts-payable          → AccountsPayablePage
/erp/employees                 → EmployeeListPage
/erp/shifts                    → ShiftManagementPage
```

### 5. Phase ต่อไป (Future Work)

- **AR/AP UI Polish:** เพิ่มฟีเจอร์ payment matching, aging report, statement export
- **AR/AP Accounting Flow (Deferred):** สร้าง AR จาก order ที่ยังไม่ชำระเต็ม และสร้าง AP จาก procurement/PO/received invoice ที่ยังไม่จ่าย โดยให้ Flutter เป็น client layer และให้ server-side/RPC เป็นผู้ตัดสินใจทางบัญชีหลัก
- **AR/AP Data Source Integration (Deferred):** ผูก flow เข้ากับ `orders`, `unified_payments`, `purchase_orders`, `goods_receipts`, และ supplier invoice เมื่อพร้อมทำงานต่อ
- **Withholding Tax (Phase 2):** ตาราง `withholding_tax_records` + ฟอร์ม ภ.ง.ด.3/53
- **e-Filing Export (Phase 2):** สร้าง XML/JSON payload ตามมาตรฐานกรมสรรพากร
- **Audit Trail (Phase 3):** ตาราง `transaction_audit_log` บันทึกทุกการแก้ไข
- **Integration Tests:** End-to-end POS Sale → Outbox → Journal Entry → VAT Record
