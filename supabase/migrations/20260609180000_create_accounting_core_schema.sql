-- Migration: Accounting Core Schema (Condensed Phase 1)
-- Tables: chart_of_accounts, journal_entries, journal_entry_lines, vat_records, tax_forms, tax_form_lines
-- Plus: outbox_events, idempotency_keys, organization_branches, exchange_rates, accounting_periods, general_ledger view
-- Seed: Thai Chart of Accounts for Clinic/Center (profession_id 00000000-0000-0000-0000-000000000003)

-- 1. ORGANIZATION BRANCHES
CREATE TABLE IF NOT EXISTS public.organization_branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_code TEXT NOT NULL,
    branch_name TEXT NOT NULL,
    tax_id TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(profession_id, branch_code)
);
COMMENT ON COLUMN public.organization_branches.tax_id IS 'เลขประจำตัวผู้เสียภาษีของสาขา (ถ้าแยก)';

-- 2. RELIABILITY CORE
CREATE TABLE IF NOT EXISTS public.outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    aggregate_type TEXT NOT NULL CHECK (aggregate_type IN ('pos_sale','procurement_gr','hr_payroll','telemedicine','logistics','manual')),
    aggregate_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','published','failed','processing')),
    retry_count INT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    published_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_outbox_status ON public.outbox_events(status, created_at);
CREATE INDEX IF NOT EXISTS idx_outbox_aggregate ON public.outbox_events(aggregate_type, aggregate_id);

CREATE TABLE IF NOT EXISTS public.idempotency_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key TEXT NOT NULL,
    scope TEXT NOT NULL DEFAULT 'accounting',
    request_method TEXT,
    request_path TEXT,
    request_body_hash TEXT,
    response_status INT,
    response_body JSONB,
    profession_id UUID REFERENCES public.professions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),
    UNIQUE(idempotency_key, scope)
);
CREATE INDEX IF NOT EXISTS idx_idempotency_key ON public.idempotency_keys(idempotency_key, scope);

-- 3. EXCHANGE RATES & ACCOUNTING PERIODS
CREATE TABLE IF NOT EXISTS public.exchange_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    from_currency VARCHAR(3) NOT NULL,
    to_currency VARCHAR(3) NOT NULL,
    rate NUMERIC(15,6) NOT NULL,
    effective_date DATE NOT NULL,
    source TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(profession_id, from_currency, to_currency, effective_date)
);

CREATE TABLE IF NOT EXISTS public.accounting_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    period_name VARCHAR(20) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','locked')),
    closed_by UUID,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(profession_id, branch_id, period_name)
);

-- 4. CHART OF ACCOUNTS
CREATE TABLE IF NOT EXISTS public.chart_of_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    account_code VARCHAR(20) NOT NULL,
    account_name VARCHAR(255) NOT NULL,
    account_name_en VARCHAR(255),
    account_type SMALLINT NOT NULL CHECK (account_type IN (1,2,3,4,5)),
    parent_id UUID REFERENCES public.chart_of_accounts(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT true,
    is_default BOOLEAN DEFAULT false,
    bank_account_no VARCHAR(50),
    display_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(profession_id, account_code)
);
COMMENT ON COLUMN public.chart_of_accounts.account_type IS '1=สินทรัพย์ 2=หนี้สิน 3=ทุน 4=รายได้ 5=ค่าใช้จ่าย';

-- 5. PRODUCT-ACCOUNT MAPPING
CREATE TABLE IF NOT EXISTS public.product_account_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    product_id UUID NOT NULL,
    product_type VARCHAR(20) NOT NULL CHECK (product_type IN ('inventory_item','service','package','medicine')),
    category_hint TEXT,
    revenue_account_id UUID REFERENCES public.chart_of_accounts(id),
    cogs_account_id UUID REFERENCES public.chart_of_accounts(id),
    inventory_account_id UUID REFERENCES public.chart_of_accounts(id),
    adjustment_account_id UUID REFERENCES public.chart_of_accounts(id),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(profession_id, product_id, product_type)
);

-- 6. JOURNAL ENTRIES & LINES
CREATE TABLE IF NOT EXISTS public.journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    entry_number VARCHAR(50) NOT NULL,
    entry_date DATE NOT NULL,
    reference_type VARCHAR(50) NOT NULL CHECK (reference_type IN ('pos_sale','procurement_gr','hr_payroll','telemedicine','logistics','manual','adjustment','opening_balance')),
    reference_id UUID,
    source_event_id UUID REFERENCES public.outbox_events(id) ON DELETE SET NULL,
    memo TEXT,
    currency_code VARCHAR(3) NOT NULL DEFAULT 'THB',
    exchange_rate NUMERIC(15,6) NOT NULL DEFAULT 1.000000,
    base_currency_code VARCHAR(3) NOT NULL DEFAULT 'THB',
    total_debit NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_credit NUMERIC(15,2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','reversed')),
    posted_at TIMESTAMPTZ,
    reversed_by UUID,
    reversed_at TIMESTAMPTZ,
    reversal_reason TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(profession_id, entry_number)
);
CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON public.journal_entries(entry_date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_ref ON public.journal_entries(reference_type, reference_id);

CREATE TABLE IF NOT EXISTS public.journal_entry_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_entry_id UUID NOT NULL REFERENCES public.journal_entries(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES public.chart_of_accounts(id),
    branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    debit_amount NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (debit_amount >= 0),
    credit_amount NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (credit_amount >= 0),
    base_debit_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    base_credit_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    description TEXT,
    cost_center VARCHAR(50),
    line_order INT DEFAULT 0,
    CHECK ((debit_amount > 0 AND credit_amount = 0) OR (credit_amount > 0 AND debit_amount = 0) OR (debit_amount = 0 AND credit_amount = 0))
);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON public.journal_entry_lines(account_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON public.journal_entry_lines(journal_entry_id);

-- 7. GENERAL LEDGER (View)
CREATE OR REPLACE VIEW public.general_ledger AS
SELECT
    je.id AS journal_entry_id, je.profession_id, je.branch_id, je.entry_number, je.entry_date,
    je.reference_type, je.reference_id, je.memo, je.currency_code, je.exchange_rate, je.status,
    jel.id AS line_id, jel.account_id, jel.branch_id AS line_branch_id,
    jel.debit_amount, jel.credit_amount, jel.base_debit_amount, jel.base_credit_amount,
    jel.description AS line_description, jel.cost_center,
    coa.account_code, coa.account_name, coa.account_type, je.posted_at, je.created_at
FROM public.journal_entry_lines jel
JOIN public.journal_entries je ON jel.journal_entry_id = je.id
JOIN public.chart_of_accounts coa ON jel.account_id = coa.id
WHERE je.status = 'posted';

-- 8. VAT RECORDS
CREATE TABLE IF NOT EXISTS public.vat_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    journal_entry_id UUID REFERENCES public.journal_entries(id) ON DELETE SET NULL,
    journal_entry_line_id UUID REFERENCES public.journal_entry_lines(id) ON DELETE SET NULL,
    document_type VARCHAR(20) NOT NULL CHECK (document_type IN ('tax_invoice','purchase_invoice','receipt','credit_note','debit_note')),
    document_number VARCHAR(50) NOT NULL,
    document_date DATE NOT NULL,
    counterparty_name VARCHAR(255),
    counterparty_tax_id VARCHAR(20),
    vat_type VARCHAR(10) NOT NULL CHECK (vat_type IN ('output','input')),
    vat_rate NUMERIC(5,2) NOT NULL DEFAULT 7.00,
    vat_base_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    vat_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    currency_code VARCHAR(3) DEFAULT 'THB',
    reporting_period VARCHAR(7) NOT NULL,
    filed_at TIMESTAMPTZ,
    e_invoice_ref VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(profession_id, document_number, document_type)
);
CREATE INDEX IF NOT EXISTS idx_vat_period ON public.vat_records(profession_id, reporting_period, vat_type);

-- 9. TAX FORMS
CREATE TABLE IF NOT EXISTS public.tax_forms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profession_id UUID NOT NULL REFERENCES public.professions(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL,
    form_type VARCHAR(10) NOT NULL CHECK (form_type IN ('ภ.ง.ด.1','ภ.ง.ด.3','ภ.ง.ด.53','ภ.ง.ด.30','ภ.พ.30')),
    tax_year INT NOT NULL,
    tax_period VARCHAR(7),
    filing_date DATE,
    due_date DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','filed','amended','cancelled')),
    total_tax_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_income_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    digital_signature TEXT,
    xml_payload TEXT,
    json_payload JSONB,
    filed_by UUID,
    filed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tax_form_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_form_id UUID NOT NULL REFERENCES public.tax_forms(id) ON DELETE CASCADE,
    line_type VARCHAR(20) NOT NULL CHECK (line_type IN ('summary','detail','attachment')),
    sequence_no INT NOT NULL DEFAULT 0,
    description TEXT,
    amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    quantity INT DEFAULT 1,
    tax_rate NUMERIC(5,2),
    tax_amount NUMERIC(15,2),
    reference_table VARCHAR(50),
    reference_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tax_forms_period ON public.tax_forms(profession_id, tax_year, tax_period);

-- 10. SEED DATA: Thai Chart of Accounts for Clinic/Center
-- หมวด 1: สินทรัพย์
INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order) VALUES
('00000000-0000-0000-0000-000000000003', '1111', 'เงินสดในมือ', 'Cash on Hand', 1, true, 100),
('00000000-0000-0000-0000-000000000003', '1112', 'เงินฝากธนาคารออมทรัพย์', 'Savings Accounts', 1, true, 101),
('00000000-0000-0000-0000-000000000003', '1113', 'เงินฝากธนาคารกระแสรายวัน', 'Current Accounts', 1, true, 102),
('00000000-0000-0000-0000-000000000003', '1121', 'ลูกหนี้การค้า', 'Accounts Receivable', 1, true, 103),
('00000000-0000-0000-0000-000000000003', '1122', 'ค่าเผื่อหนี้สงสัยจะสูญ', 'Allowance for Doubtful Accounts', 1, true, 104),
('00000000-0000-0000-0000-000000000003', '1131', 'สินค้าคงเหลือ - ยาและเวชภัณฑ์', 'Inventory - Medicines', 1, true, 105),
('00000000-0000-0000-0000-000000000003', '1132', 'สินค้าคงเหลือ - เครื่องสำอางและอื่นๆ', 'Inventory - Cosmetics & Others', 1, true, 106),
('00000000-0000-0000-0000-000000000003', '1141', 'ภาษีซื้อรอนำส่ง / ภาษีถูกหัก ณ ที่จ่ายรับ', 'Input VAT / WHT Receivable', 1, true, 107),
('00000000-0000-0000-0000-000000000003', '1151', 'ค่าใช้จ่ายจ่ายล่วงหน้า', 'Prepaid Expenses', 1, true, 108),
('00000000-0000-0000-0000-000000000003', '1211', 'อุปกรณ์ทางการแพทย์และเครื่องมือ', 'Medical Equipment', 1, true, 109),
('00000000-0000-0000-0000-000000000003', '1212', 'ค่าเสื่อมราคาสะสม - อุปกรณ์ทางการแพทย์', 'Accum. Depreciation - Medical Equipment', 1, true, 110),
('00000000-0000-0000-0000-000000000003', '1221', 'เครื่องตกแต่งและเครื่องใช้สำนักงาน', 'Furniture & Office Equipment', 1, true, 111),
('00000000-0000-0000-0000-000000000003', '1222', 'ค่าเสื่อมราคาสะสม - เครื่องตกแต่ง', 'Accum. Depreciation - Furniture', 1, true, 112)
ON CONFLICT (profession_id, account_code) DO NOTHING;

-- หมวด 2: หนี้สิน
INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order) VALUES
('00000000-0000-0000-0000-000000000003', '2111', 'เจ้าหนี้การค้า', 'Accounts Payable', 2, true, 200),
('00000000-0000-0000-0000-000000000003', '2121', 'ค่าใช้จ่ายค้างจ่าย', 'Accrued Expenses', 2, true, 201),
('00000000-0000-0000-0000-000000000003', '2131', 'ภาษีเงินได้หัก ณ ที่จ่าย รอนำส่ง', 'Withholding Tax Payable', 2, true, 202),
('00000000-0000-0000-0000-000000000003', '2132', 'ภาษีมูลค่าเพิ่มรอนำส่ง', 'VAT Payable', 2, true, 203),
('00000000-0000-0000-0000-000000000003', '2133', 'ประกันสังคมรอนำส่ง', 'Social Security Payable', 2, true, 204),
('00000000-0000-0000-0000-000000000003', '2141', 'รายได้รับล่วงหน้า / เงินมัดจำรับ', 'Unearned Revenue / Deposits', 2, true, 205),
('00000000-0000-0000-0000-000000000003', '2211', 'เงินกู้ยืมระยะยาว', 'Long-term Loans', 2, true, 206)
ON CONFLICT (profession_id, account_code) DO NOTHING;

-- หมวด 3: ทุน
INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order) VALUES
('00000000-0000-0000-0000-000000000003', '3111', 'ทุนจดทะเบียน', 'Registered Capital', 3, true, 300),
('00000000-0000-0000-0000-000000000003', '3112', 'ทุนที่เรียกชำระแล้ว', 'Paid-in Capital', 3, true, 301),
('00000000-0000-0000-0000-000000000003', '3211', 'กำไร(ขาดทุน)สะสม - ยังไม่จัดสรร', 'Retained Earnings', 3, true, 302),
('00000000-0000-0000-0000-000000000003', '3212', 'ถอนใช้ส่วนตัว / เงินปันผลจ่าย', 'Drawings / Dividends', 3, true, 303)
ON CONFLICT (profession_id, account_code) DO NOTHING;

-- หมวด 4: รายได้
INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order) VALUES
('00000000-0000-0000-0000-000000000003', '4111', 'รายได้จากการขายยาและเวชภัณฑ์', 'Revenue from Medicines', 4, true, 400),
('00000000-0000-0000-0000-000000000003', '4112', 'รายได้จากการขายผลิตภัณฑ์อื่นๆ', 'Revenue from Other Products', 4, true, 401),
('00000000-0000-0000-0000-000000000003', '4211', 'รายได้จากการตรวจรักษาพยาบาล', 'Revenue from Medical Services', 4, true, 402),
('00000000-0000-0000-0000-000000000003', '4212', 'รายได้จากการทำหัตถการ/ศัลยกรรม', 'Revenue from Procedures/Surgery', 4, true, 403),
('00000000-0000-0000-0000-000000000003', '4311', 'รายได้ดอกเบี้ยรับ / รายได้อื่นๆ', 'Interest / Other Income', 4, true, 404)
ON CONFLICT (profession_id, account_code) DO NOTHING;

-- หมวด 5: ค่าใช้จ่าย
INSERT INTO public.chart_of_accounts (profession_id, account_code, account_name, account_name_en, account_type, is_default, display_order) VALUES
('00000000-0000-0000-0000-000000000003', '5111', 'ต้นทุนยาและเวชภัณฑ์ที่ใช้ไป', 'Cost of Medicines Used', 5, true, 500),
('00000000-0000-0000-0000-000000000003', '5112', 'ต้นทุนผลิตภัณฑ์อื่นๆที่ขาย', 'Cost of Other Products Sold', 5, true, 501),
('00000000-0000-0000-0000-000000000003', '5121', 'ค่าธรรมเนียมแพทย์ / ค่ามือแพทย์', 'Doctor Fees/Commissions', 5, true, 502),
('00000000-0000-0000-0000-000000000003', '5211', 'เงินเดือนและค่าจ้างพนักงาน', 'Salaries & Wages', 5, true, 503),
('00000000-0000-0000-0000-000000000003', '5212', 'ค่าล่วงเวลา / โอที', 'Overtime', 5, true, 504),
('00000000-0000-0000-0000-000000000003', '5213', 'เงินสมทบกองทุนประกันสังคม', 'Social Security Contributions', 5, true, 505),
('00000000-0000-0000-0000-000000000003', '5221', 'ค่าเช่าสถานที่และบริการ', 'Rent & Services', 5, true, 506),
('00000000-0000-0000-0000-000000000003', '5222', 'ค่าน้ำประปา ไฟฟ้า โทรศัพท์ และอินเทอร์เน็ต', 'Utilities & Communication', 5, true, 507),
('00000000-0000-0000-0000-000000000003', '5223', 'ค่าโฆษณาและส่งเสริมการขาย', 'Advertising & Marketing', 5, true, 508),
('00000000-0000-0000-0000-000000000003', '5231', 'ค่าเสื่อมราคา - อุปกรณ์และเครื่องใช้', 'Depreciation Expense', 5, true, 509),
('00000000-0000-0000-0000-000000000003', '5241', 'ค่าธรรมเนียมธนาคาร / ค่าธรรมเนียม Payment Gateway', 'Bank / Gateway Fees', 5, true, 510)
ON CONFLICT (profession_id, account_code) DO NOTHING;

-- 11. ROW LEVEL SECURITY
ALTER TABLE public.organization_branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounting_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chart_of_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_account_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entry_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vat_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tax_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tax_form_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "org_branches_select" ON public.organization_branches;
CREATE POLICY "org_branches_select" ON public.organization_branches FOR SELECT USING (true);
DROP POLICY IF EXISTS "org_branches_modify" ON public.organization_branches;
CREATE POLICY "org_branches_modify" ON public.organization_branches FOR ALL USING (true);

DROP POLICY IF EXISTS "outbox_select" ON public.outbox_events;
CREATE POLICY "outbox_select" ON public.outbox_events FOR SELECT USING (true);
DROP POLICY IF EXISTS "outbox_modify" ON public.outbox_events;
CREATE POLICY "outbox_modify" ON public.outbox_events FOR ALL USING (true);

DROP POLICY IF EXISTS "idempotency_select" ON public.idempotency_keys;
CREATE POLICY "idempotency_select" ON public.idempotency_keys FOR SELECT USING (true);
DROP POLICY IF EXISTS "idempotency_modify" ON public.idempotency_keys;
CREATE POLICY "idempotency_modify" ON public.idempotency_keys FOR ALL USING (true);

DROP POLICY IF EXISTS "accounting_select" ON public.accounting_periods;
CREATE POLICY "accounting_select" ON public.accounting_periods FOR SELECT USING (true);
DROP POLICY IF EXISTS "accounting_modify" ON public.accounting_periods;
CREATE POLICY "accounting_modify" ON public.accounting_periods FOR ALL USING (true);

DROP POLICY IF EXISTS "coa_select" ON public.chart_of_accounts;
CREATE POLICY "coa_select" ON public.chart_of_accounts FOR SELECT USING (true);
DROP POLICY IF EXISTS "coa_modify" ON public.chart_of_accounts;
CREATE POLICY "coa_modify" ON public.chart_of_accounts FOR ALL USING (true);

DROP POLICY IF EXISTS "mapping_select" ON public.product_account_mappings;
CREATE POLICY "mapping_select" ON public.product_account_mappings FOR SELECT USING (true);
DROP POLICY IF EXISTS "mapping_modify" ON public.product_account_mappings;
CREATE POLICY "mapping_modify" ON public.product_account_mappings FOR ALL USING (true);

DROP POLICY IF EXISTS "je_select" ON public.journal_entries;
CREATE POLICY "je_select" ON public.journal_entries FOR SELECT USING (true);
DROP POLICY IF EXISTS "je_modify" ON public.journal_entries;
CREATE POLICY "je_modify" ON public.journal_entries FOR ALL USING (true);

DROP POLICY IF EXISTS "jel_select" ON public.journal_entry_lines;
CREATE POLICY "jel_select" ON public.journal_entry_lines FOR SELECT USING (true);
DROP POLICY IF EXISTS "jel_modify" ON public.journal_entry_lines;
CREATE POLICY "jel_modify" ON public.journal_entry_lines FOR ALL USING (true);

DROP POLICY IF EXISTS "vat_select" ON public.vat_records;
CREATE POLICY "vat_select" ON public.vat_records FOR SELECT USING (true);
DROP POLICY IF EXISTS "vat_modify" ON public.vat_records;
CREATE POLICY "vat_modify" ON public.vat_records FOR ALL USING (true);

DROP POLICY IF EXISTS "tax_select" ON public.tax_forms;
CREATE POLICY "tax_select" ON public.tax_forms FOR SELECT USING (true);
DROP POLICY IF EXISTS "tax_modify" ON public.tax_forms;
CREATE POLICY "tax_modify" ON public.tax_forms FOR ALL USING (true);

DROP POLICY IF EXISTS "tax_line_select" ON public.tax_form_lines;
CREATE POLICY "tax_line_select" ON public.tax_form_lines FOR SELECT USING (true);
DROP POLICY IF EXISTS "tax_line_modify" ON public.tax_form_lines;
CREATE POLICY "tax_line_modify" ON public.tax_form_lines FOR ALL USING (true);
