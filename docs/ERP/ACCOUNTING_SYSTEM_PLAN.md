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
| **SQL Migration** | `supabase/migrations/20260613100000_add_gfmis_document_types.sql` | GFMIS lookup table (40 types) + journal_entries GFMIS fields + gl_entries link fields + updated `general_ledger` view + RPC `resolve_gfmis_document_type` + RPC `create_journal_entry_gfmis` |
| **ER Diagram** | `docs/ERP/ACCOUNTING_ER_DIAGRAM.md` | Mermaid ER Diagram + รายละเอียดคอลัมน์ทุกตาราง |
| **Outbox Spec** | `docs/ERP/ACCOUNTING_OUTBOX_SPEC.md` | ตัวอย่าง payload POS→Accounting, Procurement→Accounting, HR→Accounting |
| **Flutter Model** | `lib/features/erp/data/models/chart_of_account.dart` | `ChartOfAccount` model — รองรับ `smallint`→`String` account_type mapping, `is_custom`, `standard_account_id` |
| **Flutter Model** | `lib/features/erp/data/models/gfmis_document_type.dart` | `GfmisDocumentType` model — lookup 40 GFMIS document types |
| **Flutter Model** | `lib/features/erp/data/models/gl_entry.dart` | `GlEntry` model — เพิ่ม `journalEntryId`, `documentType`, `sapTransactionCode`, `formNumber` |
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

### 2.5 GFMIS Document Types (New GFMIS Thai Integration)

ระบบรองรับ **40 ประเภทเอกสาร** จากมาตรฐาน GFMIS ส่วนราชการ (New GFMIS Thai) ผ่านตาราง lookup `gfmis_document_types`:

| หมวดหมู่ | รหัส | SAP T-Code | แบบฟอร์ม | รายละเอียด |
|---|---|---|---|---|
| **Bank Book** | ZBANK | ZBANK | บช.61 | สร้าง/เปลี่ยนแปลงข้อมูลธนาคาร |
| **General Ledger** | JM | ZGL_JM | บช.01 | บันทึกรับปรุงบัญชีสัดส่วน |
| **General Ledger** | JR | ZGL_JR | บช.01 | บันทึกรายการบัญชีเงินสด/เทียบเท่า |
| **General Ledger** | JV | ZGL_JV | บช.01 | บันทึกรายการบัญชีทั่วไป |
| **General Ledger** | N3 | ZGL_N3 | บช.01 | บันทึกหักล้างส่งเงินฝากเป็นรายได้ |
| **General Ledger** | PP | Zf_02_PP | บช.01 | บันทึกจ่ายเงินฝากธนาคาร |
| **General Ledger** | RE | ZRP_RE | บช.01 | บันทึกรับเงินฝากธนาคาร |
| **Adjustment** | SW | ZFBS1 | บช.02 | บันทึกปรับปรุงค่ารับ/ค่าจ่าย |
| **Internal Transfer** | N1 | ZGL_N1 | บช.04 | ลูกหนี้ตั้งสต็อกเงินระหว่างกำหนด |
| **Internal Transfer** | RI-RN, RO, SQ | ZRP_RI..ZFV50_SQ | บช.04 | โอนภายในระหว่างหน่วยงาน |
| **Special Funds** | N9, JU, G2, G5, G6, G3 | ZPA_FB50_N9..ZF_51_G3 | บช.53-63 | เงินเบิกเหล่าทหาร/TR2W/O |
| **Revenue/Expense** | JA, JF, J6, J7 | ZDB_JA1..ZGL_J7 | บช.12-57 | รับ/จ่ายเงินยืม ปรับปรุงหมวดรายจ่าย |
| **Revenue/Payable** | NK, N4-N8, NC | ZGL_NK_TKK..ZGL_NC | บช.50-66 | ผลักดันเงิน/บัญชีผิด |
| **Stock/Inventory** | JX, JY, JXS, JXM | ZGL_JX, ZGL_JY | บช.05-11 | เอกสารนำเข้างานสต็อก |
| **Organization** | JP, JO, JXO | ZGL_JP..ZGL_JX | บช.49-60 | ปรับปรุงประเภท/ขยายบัญชี |
| **Year-end** | J9C1, J9C2 | ZJ9_C01, ZJ9_C02 | บช.67-68 | ปรับบัญชีจากปีเก่า |

#### Schema Integration

```sql
-- journal_entries เพิ่มฟิลด์ GFMIS
ALTER TABLE journal_entries
  ADD COLUMN document_type VARCHAR(10) REFERENCES gfmis_document_types(code),
  ADD COLUMN sap_transaction_code VARCHAR(20),
  ADD COLUMN form_number VARCHAR(10),
  ADD COLUMN gfmis_batch_id VARCHAR(50),
  ADD COLUMN gfmis_posted BOOLEAN DEFAULT false;

-- gl_entries เชื่อมโยงกับ journal_entries
ALTER TABLE gl_entries
  ADD COLUMN journal_entry_id UUID REFERENCES journal_entries(id),
  ADD COLUMN journal_entry_line_id UUID REFERENCES journal_entry_lines(id),
  ADD COLUMN document_type VARCHAR(10),
  ADD COLUMN sap_transaction_code VARCHAR(20),
  ADD COLUMN form_number VARCHAR(10);
```

#### RPC Functions

- **`resolve_gfmis_document_type(sap_code)`** — แปลง SAP T-Code → GFMIS document type code
- **`create_journal_entry_gfmis(...)`** — สร้าง journal entry พร้อม auto-resolve SAP code และ form number จาก document type

#### Flutter Models

| ไฟล์ | รายละเอียด |
|---|---|
| `lib/features/erp/data/models/gfmis_document_type.dart` | `GfmisDocumentType` — lookup model รองรับ 40 รหัส |
| `lib/features/erp/data/models/gl_entry.dart` | เพิ่ม `journalEntryId`, `journalEntryLineId`, `documentType`, `sapTransactionCode`, `formNumber` |

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

### 2.6 GFMIS Reports — 88 รายการ (New GFMIS Thai)

ระบบรองรับรายงานมาตรฐาน GFMIS ส่วนราชการทั้งหมด **88 รายการ** แบ่งเป็น 5 กลุ่ม:

#### A. รายงานพื้นฐาน (15 รายการ — พร้อมใช้ทันที)

| ลำดับ | รายงาน GFMIS | แหล่งข้อมูลในระบบ | สถานะ |
|---|---|---|---|
| 1 | ผังบัญชี (NGL_COA) | `chart_of_accounts` | ✅ Ready |
| 2 | รายงานบัญชีเงินฝากกระทรวงการคลัง (NGL_LST001) | `treasury_deposits` | ⚠️ Phase 2 |
| 3 | รายชื่อบัญชีเงินฝากธนาคารพาณิชย์ของส่วนราชการ (NGL_LST002) | `treasury_deposits` | ⚠️ Phase 2 |
| 4 | รายชื่อบัญชีซื้อข้อมูลตามวัตถุประสงค์ (NGL_LST003) | `chart_of_accounts` + mapping | ⚠️ Phase 3 |
| 5 | รายชื่อบัญชีเงินฝากกระทรวงการคลังแยกตามรหัสหน่วยงาน (NGL_LST004) | `treasury_deposits` | ⚠️ Phase 2 |
| 6 | รายชื่อกองทุนหมุนเวียน (NGL_LST005) | `special_funds` | ⚠️ Phase 3 |
| 7 | รายงานแสดงบรรทัดรายการบัญชีแยกประเภททั่วไป-ระดับหน่วยเบิกจ่าย (NGL_Display) | `journal_entries` + `journal_entry_lines` | ✅ Ready |
| 8 | แสดงเอกสาร (NFI_DISPLAY) | `journal_entries` | ✅ Ready |
| 9 | แสดงบัญชี (NFI_DISPLAY_L) | `general_ledger` view | ✅ Ready |
| 10 | แสดงเอกสารทางบัญชี(เอกสารพัก) (NFI_DISPLAY_P) | `journal_entries` (status='draft') | ✅ Ready |
| 11 | บัญชีแยกประเภททั่วไปยอดคงเหลือ (NFI_FS10N) | `general_ledger` view | ✅ Ready |
| 12 | รายงานแสดงเอกสารจาก Automatic Post. (NFI_RPT004) | `journal_entries` (source='auto') | ✅ Ready |
| 13 | รายงานแสดงรหัสระหว่างหน่วยงาน (NFI_RPT005) | `journal_entries` (inter-unit) | ⚠️ Phase 2 |
| 14 | รายงานแสดงเอกสารพักก่อนผ่านรายการบัญชี (NFI_RPT006) | `journal_entries` (status='draft') | ✅ Ready |
| 15 | ZFI_GET_DATA (NFI_GET_DATA) | Export RPC | ⚠️ Phase 3 |

#### B. เงินยืม/สภาพคล่อง/บัญชีแผน (21 รายการ)

| ลำดับ | รายงาน | ตารางที่ต้องสร้าง | Phase |
|---|---|---|---|
| 16 | บัญชีแผนการเบิกจ่ายงบประมาณเหลือ (NGLF_08) | `liquidity_plans` | 2 |
| 17 | รายงานบัญชีแผนประเภทบุรณาการระบบ (NFI_DOC_ALL) | `liquidity_plans` | 2 |
| 18-20 | รายงานเคลื่อนไหวเงินยืม (Y_DEV, ZGL_MVT_MONTH) | `cash_advances` | 2 |
| 21 | สมุดของระบบงานเบิกจ่าย (NGL_TB_PMT_Load) | `cash_advances` | 2 |
| 22-23 | รายงานเอกสารยอดเงินฝากคลัง (NFI_LG_AMOUNT) | `treasury_deposits` | 2 |
| 24 | รายงานเคลื่อนไหวเงินฝากคลัง (NFI_LG_TB) | `treasury_deposits` | 2 |
| 25-26 | รายงานสถานะเงินหลังประมาณ (NFI_LG_WTH_2GR/3GR) | `budget_status` | 3 |
| 27-29 | รายงานเสียดอกต่ำกว่าอัตราดอกเบี้ย/สูงกว่า (NGL_RPT501-503) | `deposit_interest_analysis` | 3 |
| 30-32 | รายงานแผนจัดสรรเงินหมุนเวียน (ZFI_RPT0029-31) | `liquidity_plans` | 2 |
| 33-36 | รายงานการเคลื่อนไหวเงินฝากคลัง (ZGL_RPT012-018) | `treasury_deposits` | 2 |

#### C. เงินฝากคลัง/ภาษี/เงินสด (24 รายการ)

| ลำดับ | รายงาน | ตารางที่ต้องสร้าง | Phase |
|---|---|---|---|
| 37-44 | รายงานเงินฝากคลังตามประเภท/ธนาคาร (ZGL_RPT072, ZGL_05_01, ZGL_05..ZGL_11) | `treasury_deposits` | 2 |
| 45-48 | รายงานเงินฝากคลังและการรับ-จ่าย/เคลื่อนไหว (ZGL_06..ZGL_14_LG) | `treasury_deposits` + `treasury_transactions` | 2 |
| 49 | รายงานภาษีมูลค่าเพิ่ม (NGL_RPT015) | `vat_records` | ✅ Ready |
| 50 | รายงานเงินคงเหลือของบัญชีเงินฝากคลัง (ZGL_14_LG) | `treasury_deposits` | 2 |
| 51-52 | รายงานการรับ/จ่ายเงินสด (ZGL_R03_108, ZGL_R03_111) | `cash_book` | 2 |
| 53 | รายงานแสดงสรุปความเคลื่อนไหวของสำหรับส่วนราชการ (ZGL_R01) | `treasury_deposits` | 2 |
| 54-60 | รายงานแสดงรายการคำนวณภาษี/ยอดคงเหลือ (ZGL_R04..ZGL_R10) | `tax_calculations` | 3 |

#### D. รายงานทั่วไป/Gen File/สรุป (22 รายการ)

| ลำดับ | รายงาน | ตาราง/View | Phase |
|---|---|---|---|
| 61-68 | Gen File ต่าง ๆ (ZGL_R11..ZGL_R18) | `gfmis_document_types` + `journal_entries` | 2 |
| 69 | รายงานความเคลื่อนไหวของบัญชีตามบุคคล (NGL_RPT91) | `journal_entries` + `users` | 2 |
| 70 | รายงานสรุปรายรับ/จ่าย (NGL_RPT001) | `general_ledger` view | ✅ Ready |
| 71 | รายงานบัญชีลูกหนี้ (NGL_RPT003) | `accounts_receivable` | ✅ Ready |
| 72-74 | สมุดเงินสด/รับ/จ่าย (NGL_RPT007-011) | `cash_book` | 2 |
| 75 | รายงานยุทธิปีงบประมาณ (NFI_RPT0040) | `budget_plans` | 3 |
| 76 | รายงานแสดงรายละเอียดยอดคงเหลือแยกตามงบประมาณ (NGL_R02) | `budget_status` | 3 |
| 77 | รายงานสรุปเงินหมุนเวียนประจำวัน (NFI_CASHBAL_CCTR) | `liquidity_plans` | 2 |
| 78-80 | รายงานแสดงรายได้/ค่าใช้จ่าย (ZRP_R04, ZTMRS0913, ZGL_MVT_MONTH_EX2) | `general_ledger` view | ✅ Ready |
| 81-82 | งบเผยแพร่ความรู้และระบบราชการ (Z_ALR, ZGL_RPTB01) | `kpi_reports` | 3 |

#### E. Master Data/Consolidation (6 รายการ)

| ลำดับ | รายงาน | ตารางที่ต้องสร้าง | Phase |
|---|---|---|---|
| 83 | งบแสดงการเปลี่ยนแปลงสินทรัพย์ส่วนราชการ (NGL_RPTB02) | `asset_register` | 3 |
| 84-85 | รายงานข้อมูลจัดทำตามการเงินรวม (NGL_FILE_DATA) | `consolidation_data` | 3 |
| 86 | ตาราง Mapping GL กับ ITEM (NGL_MAP_GL_VS_ITEM) | `gfmis_item_mappings` | 3 |
| 87 | ตาราง Maintain ITEM กับ BP Code (NGL_MAINTAIN_ITEM) | `gfmis_item_mappings` | 3 |
| 88 | รายงานแสดงข้อมูลเชื่อมโยงทางการเงินรวมสำหรับกระทรวง (NGL_CONSO_MINISTRY) | `consolidation_rules` | 3 |

### 2.7 Implementation Roadmap for GFMIS Reports

```
Phase 1 (Ready Now) — 15 รายงาน
├── ผังบัญชี, บัญชีแยกประเภท, แสดงเอกสาร/บัญชี
├── ยอดคงเหลือ, เอกสารพัก, VAT
└── ใช้ข้อมูลจาก: chart_of_accounts, journal_entries, journal_entry_lines, vat_records, general_ledger view

Phase 2 (ต้องสร้าง Module) — 52 รายงาน
├── เงินยืม/สภาพคล่อง: cash_advances, liquidity_plans
├── เงินฝากคลัง: treasury_deposits, treasury_transactions
├── เงินสด: cash_book
├── Gen File/สรุป: ต้องเพิ่มฟิลด์ใน journal_entries
└── ลูกหนี้: ใช้ accounts_receivable ที่มีอยู่ + aging logic

Phase 3 (Advanced/Consolidation) — 21 รายงาน
├── งบประมาณ/ยุทธิปี: budget_plans, budget_status
├── ภาษีขั้นสูง: tax_calculations
├── ทรัพย์สิน: asset_register
├── Master/Consolidation: gfmis_item_mappings, consolidation_rules, consolidation_data
└── งบเผยแพร่: kpi_reports
```

### 5. Phase ต่อไป (Future Work)

- **Phase 2A — Treasury Module:** สร้างตาราง `treasury_deposits`, `cash_advances`, `liquidity_plans`, `cash_book` + RPC สำหรับรายงานกลุ่ม B+C (45 รายการ)
- **Phase 2B — GFMIS Gen File Reports:** สร้าง RPC/View สำหรับรายงาน Gen File (ZGL_R11-R18) และสรุปรายวัน (7 รายการ)
- **Phase 3A — Budget & Asset Module:** สร้าง `budget_plans`, `budget_status`, `asset_register` สำหรับรายงานงบประมาณ/ยุทธิปี/ทรัพย์สิน (11 รายการ)
- **Phase 3B — Consolidation Module:** สร้าง `gfmis_item_mappings`, `consolidation_rules`, `consolidation_data` สำหรับ Master/Consolidation ระดับกระทรวง (6 รายการ)
- **AR/AP UI Polish:** เพิ่มฟีเจอร์ payment matching, aging report, statement export
- **AR/AP Accounting Flow (Deferred):** สร้าง AR จาก order ที่ยังไม่ชำระเต็ม และสร้าง AP จาก procurement/PO/received invoice ที่ยังไม่จ่าย โดยให้ Flutter เป็น client layer และให้ server-side/RPC เป็นผู้ตัดสินใจทางบัญชีหลัก
- **AR/AP Data Source Integration (Deferred):** ผูก flow เข้ากับ `orders`, `unified_payments`, `purchase_orders`, `goods_receipts`, และ supplier invoice เมื่อพร้อมทำงานต่อ
- **Withholding Tax (Phase 2):** ตาราง `withholding_tax_records` + ฟอร์ม ภ.ง.ด.3/53
- **e-Filing Export (Phase 2):** สร้าง XML/JSON payload ตามมาตรฐานกรมสรรพากร
- **Audit Trail (Phase 3):** ตาราง `transaction_audit_log` บันทึกทุกการแก้ไข
- **Integration Tests:** End-to-end POS Sale → Outbox → Journal Entry → VAT Record
