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

```sql
-- ตารางพื้นฐานสำหรับเก็บข้อมูลฟอร์มภาษีทั้งหมด
CREATE TABLE tax_record (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id  UUID NOT NULL REFERENCES organizations(id),
    profession_id    UUID NOT NULL REFERENCES professions(id),
    tax_year         INT,                         -- ปีภาษี (สำหรับภ.ง.ด.1, 30, …)
    tax_period       VARCHAR(7),                  -- YYYY-MM หรือ YYYY-QN (สำหรับภ.ง.ด.3, 5, 53)
    filing_date      DATE,                        -- วันที่ยื่นฟอร์ม
    source_form      VARCHAR(10) NOT NULL,        -- ชื่อฟอร์ม (ภ.ง.ด.1, 3, 5, …)
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ฟิลด์อธิบาย (COMMENT) ภาษาไทย
COMMENT ON COLUMN tax_record.organization_id IS 'รหัสองค์กร (tenant)';
COMMENT ON COLUMN tax_record.profession_id IS 'รหัสอาชีพ – แยกข้อมูล multi‑tenant';
COMMENT ON COLUMN tax_record.tax_year IS 'ปีภาษี (ใช้กับฟอร์มที่อิงปี)';
COMMENT ON COLUMN tax_record.tax_period IS 'ช่วงเวลาภาษี (เดือนหรือไตรมาส)';
COMMENT ON COLUMN tax_record.filing_date IS 'วันที่ยื่นฟอร์มต่อกรมสรรพากร';
COMMENT ON COLUMN tax_record.source_form IS 'รหัสฟอร์มภาษีที่ระบุ (เช่น ภ.ง.ด.1)';

-- ตัวอย่างตารางย่อย (ฟอร์มภ.ง.ด.1 – ภาษีเงินได้บุคคลธรรมดา)
CREATE TABLE personal_income_tax (
    id               UUID PRIMARY KEY REFERENCES tax_record(id),
    taxpayer_id      VARCHAR(20) NOT NULL,                -- เลขประจำตัวผู้เสียภาษี
    total_income     NUMERIC(15,2) NOT NULL,              -- รายได้รวมก่อนหักค่าใช้จ่าย
    deductions       NUMERIC(15,2) DEFAULT 0,            -- รายการหักลบ
    tax_rate         NUMERIC(5,2) NOT NULL,              -- อัตราภาษี (%)
    tax_amount       NUMERIC(15,2) GENERATED ALWAYS AS ( (total_income - deductions) * tax_rate/100 ) STORED,
    CHECK (source_form = 'ภ.ง.ด.1')
);
COMMENT ON COLUMN personal_income_tax.taxpayer_id IS 'เลขประจำตัวผู้เสียภาษี (เช่น เลขบัตรประชาชน)';
COMMENT ON COLUMN personal_income_tax.total_income IS 'รวมรายได้ทั้งหมดของปีนั้น';
COMMENT ON COLUMN personal_income_tax.deductions IS 'รวมค่าใช้จ่ายที่อนุญาตให้หัก';
COMMENT ON COLUMN personal_income_tax.tax_rate IS 'อัตราภาษีที่ใช้คำนวณ (เปอร์เซ็น)';

-- ตัวอย่างตารางย่อย (ภ.ง.ด.3 – ภาษีหัก ณ ที่จ่าย)
CREATE TABLE withholding_tax (
    id               UUID PRIMARY KEY REFERENCES tax_record(id),
    payer_id         VARCHAR(20) NOT NULL,                -- ผู้หักภาษี
    payee_id         VARCHAR(20) NOT NULL,                -- ผู้รับเงินที่ถูกหัก
    document_no      VARCHAR(30),                         -- เลขที่เอกสาร/ใบเสร็จ
    tax_base         NUMERIC(15,2) NOT NULL,              -- ฐานภาษีที่คำนวณ
    tax_rate         NUMERIC(5,2) NOT NULL,               -- อัตราภาษี (%)
    tax_amount       NUMERIC(15,2) GENERATED ALWAYS AS ( tax_base * tax_rate/100 ) STORED,
    date_paid        DATE,
    CHECK (source_form = 'ภ.ง.ด.3')
);
COMMENT ON COLUMN withholding_tax.payer_id IS 'ผู้หักภาษี (เช่น บริษัท)';
COMMENT ON COLUMN withholding_tax.payee_id IS 'ผู้รับเงินที่ถูกหัก (เช่น พนักงาน)';
COMMENT ON COLUMN withholding_tax.tax_base IS 'ฐานภาษีที่ต้องหัก';
COMMENT ON COLUMN withholding_tax.tax_rate IS 'อัตราภาษีที่กำหนด';

-- ตารางย่อยอื่น ๆ (VAT, Tax Invoice, Customs Tax, ฯลฯ) จะมีโครงสร้างคล้ายกันและใช้ CHECK(source_form = '…')
```



## การเชื่อมโยงกับระบบอื่น (Integrations)
- **[POS System](../plans/implementation_plan.md):** รายรับจากการขายหน้าร้านจะถูกลงบัญชีเป็น 'รายได้' และ 'เงินสด/เงินฝาก'
- **[Procurement System](PROCUREMENT_SYSTEM_PLAN.md):** ใบ PO ที่รับของแล้วจะถูกตั้งเป็น 'เจ้าหนี้การค้า (AP)' และบันทึกเป็น 'ต้นทุนสินค้า'
- **[HR System](HR_SYSTEM_PLAN.md):** การจ่ายเงินเดือนและค่าคอมมิชชั่นจะถูกบันทึกเป็น 'ค่าใช้จ่าย'

## การเชื่อมโยงสินค้าและผังบัญชี (Product-Account Mapping)
- **Tenant-Specific Mapping:** แต่ละองค์กร (Tenant) สามารถตั้งค่าผูก (Map) รายการสินค้า/บริการ/แพ็กเกจของตนเอง เข้ากับรหัสบัญชีที่ต้องการได้อย่างอิสระ
- **Smart Recommendation:** เมื่อองค์กรสร้างสินค้าหรือบริการใหม่ ระบบจะทำการวิเคราะห์จาก "หมวดหมู่สินค้า (Category)" และ "ประเภทสินค้า (Type)" เพื่อ **แนะนำผังบัญชีที่ควรจะเป็น** ให้อัตโนมัติ (เช่น ถ้าสร้างหมวด "ยา" ระบบจะแนะนำให้ผูกฝั่งรายรับกับ `4100 รายได้จากการขาย` และฝั่งต้นทุนกับ `5100 ต้นทุนขาย`) เพื่อความสะดวกและลดข้อผิดพลาด

## ข้อมูลตั้งต้นสำหรับผังบัญชีมาตรฐาน (Seed Data - Thai Chart of Accounts)
เมื่อองค์กรใหม่เปิดใช้งานระบบ จะมีการคัดลอก (Seed) ผังบัญชี 5 หมวดหลักมาตรฐานไทยไปให้เป็นข้อมูลตั้งต้น ซึ่งองค์กรสามารถนำไปใช้ หรือแตกบัญชีย่อยเพิ่มได้เอง:
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

## แผนการพัฒนา (Implementation Plan Placeholder)
*(พื้นที่สำหรับเขียน DB Schema, Flutter UI, และ Business Logic ในอนาคต)*

### 1. Database Schema
- `chart_of_accounts`
- `general_ledgers`
- `journal_entries`

### 2. Flutter UI
- `AccountingDashboardPage`
- `ProfitAndLossReportPage`
