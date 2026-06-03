-- 2023-06-01: Tax schema for ERP accounting system
-- ตารางหลักและตารางย่อยสำหรับฟอร์มภาษีของกรมสรรพากร
-- คอลัมน์ทั้งหมดมีคำอธิบายเป็นภาษาไทยเพื่อความชัดเจน

-- -------------------------------------------------------------------
-- Base table: tax_record (ข้อมูลพื้นฐานของทุกฟอร์มภาษี)
-- -------------------------------------------------------------------
CREATE TABLE tax_record (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id  UUID NOT NULL REFERENCES organizations(id),
    profession_id    UUID NOT NULL REFERENCES professions(id),
    tax_year         INT                     , -- ปีภาษี (เช่น 2026)
    tax_period       VARCHAR(7)              , -- ช่วงเวลา เช่น 2026-04 หรือ 2026-Q2
    filing_date      DATE                    , -- วันที่ยื่นหรือกำหนดส่ง
    source_form      VARCHAR(10) NOT NULL   , -- รหัสฟอร์ม (ภ.ง.ด.1, 3, 5, …)
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON COLUMN tax_record.organization_id IS 'รหัสองค์กร (tenant) ที่ใช้บันทึกข้อมูลภาษี';
COMMENT ON COLUMN tax_record.profession_id   IS 'รหัสอาชีพ/โปรไฟล์ของผู้ใช้ (profession_id) เพื่อแยกข้อมูล Multi‑tenant';
COMMENT ON COLUMN tax_record.tax_year        IS 'ปีภาษี (เช่น 2569)';
COMMENT ON COLUMN tax_record.tax_period      IS 'ช่วงเวลาแบบเดือนหรือไตรมาส (เช่น 2026-04 หรือ 2026-Q2)';
COMMENT ON COLUMN tax_record.filing_date     IS 'วันที่ส่งแบบเต็ม (วัน/เดือน/ปี)';
COMMENT ON COLUMN tax_record.source_form      IS 'รหัสฟอร์มภาษีที่อ้างอิง (เช่น ภ.ง.ด.1)';

-- -------------------------------------------------------------------
-- Personal Income Tax (ภ.ง.ด.1)
-- -------------------------------------------------------------------
CREATE TABLE personal_income_tax (
    id               UUID PRIMARY KEY REFERENCES tax_record(id),
    taxpayer_id      VARCHAR(20) NOT NULL,               -- เลขประจำตัวผู้เสียภาษี (เลขบัตรประชาชนหรือเลขประจำตัวผู้เสียภาษี)
    total_income     NUMERIC(15,2) NOT NULL,             -- รายได้รวมทั้งหมดก่อนหักค่าใช้จ่าย
    deductions       NUMERIC(15,2) DEFAULT 0,          -- ค่าลดหย่อนภาษี (ค่าใช้จ่ายที่หักได้)
    tax_rate         NUMERIC(5,2) NOT NULL,             -- อัตราภาษี (เปอร์เซ็นต์)
    tax_amount       NUMERIC(15,2) GENERATED ALWAYS AS ((total_income - deductions) * tax_rate/100) STORED,
    filing_date      DATE NOT NULL
);
COMMENT ON COLUMN personal_income_tax.taxpayer_id IS 'เลขประจำตัวผู้เสียภาษี (เช่น เลขบัตรประชาชน)';
COMMENT ON COLUMN personal_income_tax.total_income IS 'ยอดรวมของรายได้ทั้งหมดที่ต้องคำนวณภาษี';
COMMENT ON COLUMN personal_income_tax.deductions IS 'ยอดค่าลดหย่อนที่ผู้เสียภาษีสามารถลดได้';
COMMENT ON COLUMN personal_income_tax.tax_rate IS 'อัตราภาษีที่ต้องนำมาคูณกับฐานภาษี (เช่น 5, 10, 20 %)';
COMMENT ON COLUMN personal_income_tax.tax_amount IS 'จำนวนภาษีที่ต้องชำระ (ฐานภาษี * อัตราภาษี)';

-- -------------------------------------------------------------------
-- Withholding Tax (ภ.ง.ด.3)
-- -------------------------------------------------------------------
CREATE TABLE withholding_tax (
    id               UUID PRIMARY KEY REFERENCES tax_record(id),
    payer_id         VARCHAR(20) NOT NULL,   -- ผู้หักภาษี (เจ้าของธุรกิจหรือผู้จ่ายเงิน)
    payee_id         VARCHAR(20) NOT NULL,   -- ผู้รับเงินที่ถูกหักภาษี
    document_no      VARCHAR(30),            -- เลขที่เอกสารหรือใบสำคัญจ่าย
    tax_base         NUMERIC(15,2) NOT NULL, -- ฐานภาษี (จำนวนเงินที่คำนวณภาษีจาก)
    tax_rate         NUMERIC(5,2) NOT NULL,   -- อัตราภาษีหัก ณ ที่จ่าย (เปอร์เซ็นต์)
    tax_amount       NUMERIC(15,2) GENERATED ALWAYS AS (tax_base * tax_rate/100) STORED,
    date_paid        DATE NOT NULL
);
COMMENT ON COLUMN withholding_tax.payer_id IS 'รหัสผู้หักภาษี (เช่น ผู้จ่ายเงินหรือบริษัท)';
COMMENT ON COLUMN withholding_tax.payee_id IS 'รหัสผู้รับเงินที่ต้องหักภาษี (เช่น ผู้รับบริการ)';
COMMENT ON COLUMN withholding_tax.document_no IS 'หมายเลขเอกสารที่ใช้บันทึกการจ่ายเงิน (ใบสำคัญจ่าย)';
COMMENT ON COLUMN withholding_tax.tax_base IS 'ฐานภาษีที่คำนวนจากยอดจ่ายจริง';
COMMENT ON COLUMN withholding_tax.tax_rate IS 'อัตราการหักภาษี ณ ที่จ่าย (เช่น 1%, 3%)';
COMMENT ON COLUMN withholding_tax.tax_amount IS 'จำนวนภาษีที่ได้หัก ณ ที่จ่าย';
COMMENT ON COLUMN withholding_tax.date_paid IS 'วันที่จ่ายเงินและทำการหักภาษี';

-- -------------------------------------------------------------------
-- VAT Report (ภ.ง.ด.53)
-- -------------------------------------------------------------------
CREATE TABLE vat_report (
    id               UUID PRIMARY KEY REFERENCES tax_record(id),
    taxable_sales    NUMERIC(15,2) NOT NULL,   -- ยอดขายที่ต้องคำนวณภาษีมูลค่าเพิ่ม
    vat_rate         NUMERIC(5,2) DEFAULT 7,  -- อัตราภาษีมูลค่าเพิ่ม (ปกติ 7%)
    vat_output       NUMERIC(15,2) GENERATED ALWAYS AS (taxable_sales * vat_rate/100) STORED,
    vat_input        NUMERIC(15,2) DEFAULT 0, -- ภาษีที่รับจากการซื้อ (VAT Input)
    vat_payable      NUMERIC(15,2) GENERATED ALWAYS AS (vat_output - vat_input) STORED,
    filing_date      DATE NOT NULL
);
COMMENT ON COLUMN vat_report.taxable_sales IS 'ยอดขายรวมที่ต้องเสีย VAT (ไม่รวม VAT)';
COMMENT ON COLUMN vat_report.vat_rate IS 'อัตรา VAT (ส่วนใหญ่ 7%)';
COMMENT ON COLUMN vat_report.vat_output IS 'VAT ที่ต้องชำระต่อกรมสรรพากร (VAT Output)';
COMMENT ON COLUMN vat_report.vat_input IS 'VAT ที่ได้รับคืนจากการซื้อ (VAT Input)';
COMMENT ON COLUMN vat_report.vat_payable IS 'ยอด VAT ที่ต้องชำระสุทธิ (Output - Input)';

-- -------------------------------------------------------------------
-- Tax Invoice (ภ.ง.ด.5)
-- -------------------------------------------------------------------
CREATE TABLE tax_invoice (
    id               UUID PRIMARY KEY REFERENCES tax_record(id),
    invoice_no       VARCHAR(30) NOT NULL,          -- เลขที่ใบกำกับภาษี (Tax Invoice No.)
    invoice_date     DATE NOT NULL,                 -- วันที่ใบกำกับภาษี
    customer_id      VARCHAR(20),                  -- รหัสลูกค้า/ผู้ซื้อ
    item_desc        TEXT,                         -- รายละเอียดสินค้า/บริการ
    quantity         INT,                          -- จำนวนหน่วย
    unit_price       NUMERIC(15,2),                -- ราคาต่อหน่วย (มิได้รวม VAT)
    tax_rate         NUMERIC(5,2) DEFAULT 7,       -- อัตรา VAT ของรายการนี้
    tax_amount       NUMERIC(15,2) GENERATED ALWAYS AS (quantity * unit_price * tax_rate/100) STORED,
    total_amount     NUMERIC(15,2) GENERATED ALWAYS AS (quantity * unit_price + tax_amount) STORED,
    currency         VARCHAR(3) DEFAULT 'THB'    -- สกุลเงิน (THB, USD, …)
);
COMMENT ON COLUMN tax_invoice.invoice_no IS 'เลขใบกำกับภาษีตามระบบ POS หรือระบบบิล';
COMMENT ON COLUMN tax_invoice.invoice_date IS 'วันที่ออกใบกำกับภาษี';
COMMENT ON COLUMN tax_invoice.customer_id IS 'รหัสหรือหมายเลขประจำตัวลูกค้า (ถ้ามี)';
COMMENT ON COLUMN tax_invoice.item_desc IS 'คำอธิบายสินค้า/บริการที่ขาย';
COMMENT ON COLUMN tax_invoice.quantity IS 'จำนวนหน่วยที่ขาย';
COMMENT ON COLUMN tax_invoice.unit_price IS 'ราคาต่อหน่วยก่อน VAT';
COMMENT ON COLUMN tax_invoice.tax_rate IS 'อัตรา VAT ของรายการ (โดยทั่วไป 7%)';
COMMENT ON COLUMN tax_invoice.tax_amount IS 'ภาษี VAT ที่คำนวณจากจำนวนและอัตรา';
COMMENT ON COLUMN tax_invoice.total_amount IS 'มูลค่ารวม (รวม VAT) ของใบกำกับภาษี';
COMMENT ON COLUMN tax_invoice.currency IS 'สกุลเงินที่ใช้ในใบกำกับภาษี';

-- -------------------------------------------------------------------
-- Annual Tax Return (ภ.ง.ด.30)
-- -------------------------------------------------------------------
CREATE TABLE annual_tax_return (
    id                UUID PRIMARY KEY REFERENCES tax_record(id),
    total_income      NUMERIC(15,2) NOT NULL,   -- รายได้รวมทั้งหมดของปี
    total_deductions  NUMERIC(15,2) DEFAULT 0, -- ค่าใช้จ่ายที่หักได้ทั้งหมด
    taxable_income    NUMERIC(15,2) GENERATED ALWAYS AS (total_income - total_deductions) STORED,
    total_tax_due     NUMERIC(15,2) NOT NULL,   -- ภาษีที่ต้องชำระทั้งหมดของปี
    total_tax_paid    NUMERIC(15,2) DEFAULT 0, -- ภาษีที่ได้ชำระแล้ว
    balance           NUMERIC(15,2) GENERATED ALWAYS AS (total_tax_due - total_tax_paid) STORED,
    filing_date       DATE NOT NULL
);
COMMENT ON COLUMN annual_tax_return.total_income IS 'ยอดรายได้รวมของปี ภาษีเงินได้ทั้งหมด';
COMMENT ON COLUMN annual_tax_return.total_deductions IS 'ยอดค่าใช้จ่ายทั้งหมดที่สามารถหักได้ (ค่าใช้จ่ายส่วนบุคคล)';
COMMENT ON COLUMN annual_tax_return.taxable_income IS 'ฐานภาษีที่ต้องคำนวณ (รายได้ - ค่าใช้จ่าย)';
COMMENT ON COLUMN annual_tax_return.total_tax_due IS 'ภาษีที่ต้องชำระตามกฎหมาย';
COMMENT ON COLUMN annual_tax_return.total_tax_paid IS 'ภาษีที่ได้ชำระไปแล้วในปีนั้น';
COMMENT ON COLUMN annual_tax_return.balance IS 'ยอดค้างชำระ (หรือส่วนคืน)';

-- -------------------------------------------------------------------
-- Estimated Income Tax (ภ.ง.ด.2)
-- -------------------------------------------------------------------
CREATE TABLE estimated_income_tax (
    id                UUID PRIMARY KEY REFERENCES tax_record(id),
    period            VARCHAR(5) NOT NULL,      -- ไตรมาสหรือครึ่งปี (เช่น H1, H2, Q1)  
    estimated_income  NUMERIC(15,2) NOT NULL,   -- รายได้ประมาณการในช่วงนั้น
    estimated_tax     NUMERIC(15,2) NOT NULL,   -- ภาษีที่คาดว่าจะต้องชำระ
    payment_due_date  DATE NOT NULL              -- วันกำหนดชำระภาษีประมาณการ
);
COMMENT ON COLUMN estimated_income_tax.period IS 'ระยะเวลาประมาณการ (เช่น H1, H2, Q1, Q2)';
COMMENT ON COLUMN estimated_income_tax.estimated_income IS 'ยอดรายได้ที่คาดว่าจะได้รับในช่วงนั้น';
COMMENT ON COLUMN estimated_income_tax.estimated_tax IS 'จำนวนภาษีที่คาดว่าจะต้องจ่าย';
COMMENT ON COLUMN estimated_income_tax.payment_due_date IS 'กำหนดส่งเงินภาษีตามประมาณการ';

-- -------------------------------------------------------------------
-- VAT Statistics (ภ.ง.ด.53 สถิติ)
-- -------------------------------------------------------------------
CREATE TABLE vat_statistics (
    id                UUID PRIMARY KEY REFERENCES tax_record(id),
    total_output_vat  NUMERIC(15,2) NOT NULL,   -- VAT ยอดขายรวม (VAT Output)
    total_input_vat   NUMERIC(15,2) NOT NULL,   -- VAT ยอดซื้อรวม (VAT Input)
    net_vat           NUMERIC(15,2) GENERATED ALWAYS AS (total_output_vat - total_input_vat) STORED,
    filing_date       DATE NOT NULL
);
COMMENT ON COLUMN vat_statistics.total_output_vat IS 'ยอด VAT ที่ต้องจ่าย (ออกจากการขาย)';
COMMENT ON COLUMN vat_statistics.total_input_vat IS 'ยอด VAT ที่ได้รับคืน (จากการซื้อ)';
COMMENT ON COLUMN vat_statistics.net_vat IS 'ยอด VAT สุทธิที่ต้องชำระต่อกรมสรรพากร';

-- -------------------------------------------------------------------
-- Customs Tax (ภ.ง.ด.6)
-- -------------------------------------------------------------------
CREATE TABLE customs_tax (
    id                UUID PRIMARY KEY REFERENCES tax_record(id),
    import_declaration_no VARCHAR(30),        -- เลขที่เอกสารนำเข้าสินค้า
    export_declaration_no VARCHAR(30),        -- เลขที่เอกสารส่งออกสินค้า
    customs_duty      NUMERIC(15,2) NOT NULL, -- ภาษีศุลกากรที่ต้องจ่าย
    vat_on_import     NUMERIC(15,2) NOT NULL, -- VAT ที่อยู่ในสินค้านำเข้า
    taxable_value    NUMERIC(15,2) NOT NULL,   -- มูลค่าที่ต้องเสียภาษี (CIF)
    date             DATE NOT NULL
);
COMMENT ON COLUMN customs_tax.import_declaration_no IS 'เลขที่เอกสารการนำเข้าสินค้าจากกรมศุลกากร';
COMMENT ON COLUMN customs_tax.export_declaration_no IS 'เลขที่เอกสารการส่งออกของศุลกากร';
COMMENT ON COLUMN customs_tax.customs_duty IS 'ภาษีศุลกากรที่ต้องชำระ (ตามอัตราภาษีศุลกากร)';
COMMENT ON COLUMN customs_tax.vat_on_import IS 'VAT ที่ต้องคำนวนจากมูลค่าสินค้านำเข้า';
COMMENT ON COLUMN customs_tax.taxable_value IS 'มูลค่าที่ต้องเสียภาษี (มูลค่าสินค้า + ค่าขนส่ง + ประกัน)';

-- End of migration
