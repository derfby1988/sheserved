-- Migration: Create tax schema with Thai column comments

-- Base table for shared tax record fields
CREATE TABLE tax_record (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL,
    tax_year INT NOT NULL,
    period VARCHAR(10),
    filing_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON COLUMN tax_record.organization_id IS 'รหัสองค์กร';
COMMENT ON COLUMN tax_record.tax_year IS 'ปีภาษี';
COMMENT ON COLUMN tax_record.period IS 'รอบระยะเวลาการยื่น (เดือน/ไตรมาส)';
COMMENT ON COLUMN tax_record.filing_date IS 'วันที่ยื่นแบบ';
COMMENT ON COLUMN tax_record.created_at IS 'สร้างเมื่อ';
COMMENT ON COLUMN tax_record.updated_at IS 'อัปเดตเมื่อ';

-- Table for ภ.ง.ด.1 (Personal Income Tax Return)
CREATE TABLE tax_form_1 (
    id SERIAL PRIMARY KEY,
    tax_record_id INTEGER REFERENCES tax_record(id),
    taxpayer_id VARCHAR(13),
    full_name VARCHAR(100),
    address TEXT,
    taxable_income DECIMAL(15,2),
    tax_payable DECIMAL(15,2)
);

COMMENT ON COLUMN tax_form_1.tax_record_id IS 'เชื่อมโยงกับ tax_record';
COMMENT ON COLUMN tax_form_1.taxpayer_id IS 'เลขประจำตัวผู้เสียภาษี (TIN)';
COMMENT ON COLUMN tax_form_1.full_name IS 'ชื่อ-นามสกุล';
COMMENT ON COLUMN tax_form_1.address IS 'ที่อยู่';
COMMENT ON COLUMN tax_form_1.taxable_income IS 'รายได้ที่ต้องเสียภาษี';
COMMENT ON COLUMN tax_form_1.tax_payable IS 'ภาษีที่ต้องจ่าย';

-- Table for ภ.ง.ด.3 (Withholding Tax Certificate)
CREATE TABLE tax_form_3 (
    id SERIAL PRIMARY KEY,
    tax_record_id INTEGER REFERENCES tax_record(id),
    payer_id VARCHAR(13),
    payee_id VARCHAR(13),
    income_type VARCHAR(50),
    amount DECIMAL(15,2),
    tax_withheld DECIMAL(15,2)
);

COMMENT ON COLUMN tax_form_3.tax_record_id IS 'เชื่อมโยงกับ tax_record';
COMMENT ON COLUMN tax_form_3.payer_id IS 'ผู้จ่ายภาษี (ผู้หัก)';
COMMENT ON COLUMN tax_form_3.payee_id IS 'ผู้รับเงิน (ผู้ถูกหัก)';
COMMENT ON COLUMN tax_form_3.income_type IS 'ประเภทรายได้';
COMMENT ON COLUMN tax_form_3.amount IS 'จำนวนเงิน';
COMMENT ON COLUMN tax_form_3.tax_withheld IS 'ภาษีที่หักไว้';

-- Table for ภ.ง.ด.5 (VAT Return)
CREATE TABLE tax_form_5 (
    id SERIAL PRIMARY KEY,
    tax_record_id INTEGER REFERENCES tax_record(id),
    period_month VARCHAR(7),
    total_sales DECIMAL(15,2),
    vat_output DECIMAL(15,2),
    vat_input DECIMAL(15,2),
    net_vat DECIMAL(15,2)
);

COMMENT ON COLUMN tax_form_5.tax_record_id IS 'เชื่อมโยงกับ tax_record';
COMMENT ON COLUMN tax_form_5.period_month IS 'เดือนที่รายงาน (YYYY-MM)';
COMMENT ON COLUMN tax_form_5.total_sales IS 'ยอดขายรวม';
COMMENT ON COLUMN tax_form_5.vat_output IS 'VAT ภาษีออก';
COMMENT ON COLUMN tax_form_5.vat_input IS 'VAT ภาษีเข้า';
COMMENT ON COLUMN tax_form_5.net_vat IS 'VAT สุทธิ';

-- Table for ภ.ง.ด.30 (Corporate Income Tax Return)
CREATE TABLE tax_form_30 (
    id SERIAL PRIMARY KEY,
    tax_record_id INTEGER REFERENCES tax_record(id),
    corporation_name VARCHAR(100),
    tax_id VARCHAR(13),
    total_revenue DECIMAL(15,2),
    taxable_income DECIMAL(15,2),
    tax_payable DECIMAL(15,2)
);

COMMENT ON COLUMN tax_form_30.tax_record_id IS 'เชื่อมโยงกับ tax_record';
COMMENT ON COLUMN tax_form_30.corporation_name IS 'ชื่อบริษัท';
COMMENT ON COLUMN tax_form_30.tax_id IS 'เลขประจำตัวผู้เสียภาษีของบริษัท';
COMMENT ON COLUMN tax_form_30.total_revenue IS 'รายได้รวม';
COMMENT ON COLUMN tax_form_30.taxable_income IS 'กำไรที่ต้องเสียภาษี';
COMMENT ON COLUMN tax_form_30.tax_payable IS 'ภาษีที่ต้องจ่าย';

-- Table for ภ.ง.ด.6 (Customs Tax)
CREATE TABLE tax_form_6 (
    id SERIAL PRIMARY KEY,
    tax_record_id INTEGER REFERENCES tax_record(id),
    import_declaration_no VARCHAR(30),
    export_declaration_no VARCHAR(30),
    customs_duty DECIMAL(15,2),
    vat DECIMAL(15,2),
    total_tax DECIMAL(15,2)
);

COMMENT ON COLUMN tax_form_6.tax_record_id IS 'เชื่อมโยงกับ tax_record';
COMMENT ON COLUMN tax_form_6.import_declaration_no IS 'เลขที่หนังสือแจ้งศุลกากรนำเข้า';
COMMENT ON COLUMN tax_form_6.export_declaration_no IS 'เลขที่หนังสือแจ้งศุลกากรส่งออก';
COMMENT ON COLUMN tax_form_6.customs_duty IS 'ภาษีศุลกากร';
COMMENT ON COLUMN tax_form_6.vat IS 'VAT';
COMMENT ON COLUMN tax_form_6.total_tax IS 'ภาษีรวม';
