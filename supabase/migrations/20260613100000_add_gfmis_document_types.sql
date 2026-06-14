-- Migration: Add GFMIS Document Types & Align with New GFMIS Thai
-- Date: 2026-06-13
-- Prerequisites: 20260609180000_create_accounting_core_schema.sql
--                 20260611180000_erp_phase_3_finance_operations.sql

-- ============================================================
-- 1. GFMIS DOCUMENT TYPES (Lookup)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.gfmis_document_types (
    code            VARCHAR(10) PRIMARY KEY,
    name_th         TEXT NOT NULL,
    name_en         TEXT,
    sap_transaction_code VARCHAR(20) NOT NULL,
    form_number     VARCHAR(10),
    category        VARCHAR(50) NOT NULL CHECK (category IN (
        'general_ledger', 'adjustment', 'accounts_receivable', 'accounts_payable',
        'internal_transfer', 'special_funds', 'revenue', 'expense', 'other'
    )),
    description     TEXT,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Seed GFMIS Document Types from "คู่มือระบบบัญชีแยกประเภท GL ส่วนราชการ"
INSERT INTO public.gfmis_document_types (code, name_th, sap_transaction_code, form_number, category, description) VALUES
-- 1. Bank Book
('ZBANK', 'สร้าง/เปลี่ยนแปลงข้อมูลซื้อข้อมูลธนาคาร (Bank Book)', 'ZBANK', 'บช.61', 'other', 'สร้าง/เปลี่ยนแปลงข้อมูลซื้อข้อมูลธนาคาร'),

-- 2. General Ledger Documents
('JM', 'บันทึกรับปรุงบัญชีสัดส่วน', 'ZGL_JM', 'บช.01', 'general_ledger', 'ประเภทเอกสาร JM: บันทึกรับปรุงบัญชีสัดส่วน'),
('JR', 'บันทึกรายการบัญชีเงินสดและเทียบเท่าเงินสด', 'ZGL_JR', 'บช.01', 'general_ledger', 'ประเภทเอกสาร JR: บันทึกรายการบัญชีเงินสดและเทียบเท่าเงินสด'),
('JV', 'บันทึกรายการบัญชีทั่วไปไม่เกี่ยวกับเงินสดและเทียบเท่าเงินสด', 'ZGL_JV', 'บช.01', 'general_ledger', 'ประเภทเอกสาร JV: บันทึกรายการบัญชีทั่วไปไม่เกี่ยวกับเงินสดและเทียบเท่าเงินสด'),
('N3', 'บันทึกบันทึกหักล้างส่งเงินฝากกลังเป็นเงินรายได้แผ่นดิน', 'ZGL_N3', 'บช.01', 'general_ledger', 'ประเภทเอกสาร N3: บันทึกบันทึกหักล้างส่งเงินฝากกลังเป็นเงินรายได้แผ่นดิน'),
('PP', 'บันทึกจ่ายเงินฝากธนาคารพาณิชย์', 'Zf_02_PP', 'บช.01', 'general_ledger', 'ประเภทเอกสาร PP: บันทึกจ่ายเงินฝากธนาคารพาณิชย์'),
('RE', 'บันทึกรับเงินฝากธนาคารพาณิชย์', 'ZRP_RE', 'บช.01', 'general_ledger', 'ประเภทเอกสาร RE: บันทึกรับเงินฝากธนาคารพาณิชย์'),

-- 3. Adjustment
('SW', 'บันทึกปรับปรุงรายการบัญชีค่ารับ/ค่าจ่าย', 'ZFBS1', 'บช.02', 'adjustment', 'ประเภทเอกสาร SW: บันทึกปรับปรุงรายการบัญชีค่ารับ/ค่าจ่าย'),

-- 4. AR/AP (Internal Transfers)
('JR2', 'บันทึกรายการบัญชีเงินสดและเทียบเท่าเงินสด (เพิ่มเติม)', 'ZGL_JR', 'บช.01-2', 'accounts_receivable', 'ประเภทเอกสาร JR รูปแบบ 2'),
('JV2', 'บันทึกรายการบัญชีทั่วไปไม่เกี่ยวกับเงินสดและเทียบเท่าเงินสด (เพิ่มเติม)', 'ZGL_JV', 'บช.01-2', 'accounts_payable', 'ประเภทเอกสาร JV รูปแบบ 2'),
('N1', 'ลูกหนี้ตั้งสต็อกเงินระหว่างกำหนดระยะเวลาให้ชำระหมู่คู่ฝ่าย', 'ZGL_N1', 'บช.04', 'accounts_receivable', 'ประเภทเอกสาร N1'),
('RI', 'โอนภายในระหว่างหน่วยงานเดียวกัน (รายได้)', 'ZRP_RI', 'บช.04', 'internal_transfer', 'ประเภทเอกสาร RI'),
('RU', 'โอนภายในระหว่างหน่วยงาน (รายได้)', 'ZRP_RU', 'บช.04', 'internal_transfer', 'ประเภทเอกสาร RU'),
('RK', 'โอนภายในระหว่างหน่วยงานเดียวกัน (พลิกคืน)', 'ZRP_RK', 'บช.04', 'internal_transfer', 'ประเภทเอกสาร RK'),
('RL', 'โอนภายในต่างหน่วยงาน (พลิกคืน)', 'ZRP_RL', 'บช.04', 'internal_transfer', 'ประเภทเอกสาร RL'),
('RM', 'โอนภายในระหว่างหน่วยงานในส่วนราชการให้ผู้ปฏิบัติงาน', 'ZRP_RM', 'บช.04', 'internal_transfer', 'ประเภทเอกสาร RM'),
('RN', 'โอนภายในระหว่างหน่วยงานในส่วนราชการให้ผู้ปฏิบัติงาน', 'ZRP_RN', 'บช.04', 'internal_transfer', 'ประเภทเอกสาร RN'),
('RO', 'โอนภายในระหว่างหน่วยงานในส่วนราชการให้ผู้ปฏิบัติงานเป็นรายได้', 'ZRP_RO', 'บช.04', 'internal_transfer', 'ประเภทเอกสาร RO'),
('SQ', 'บันทึกปรับปรุงรายได้สินค้าและบริการส่งสต็อก', 'ZFV50_SQ', 'บช.04', 'adjustment', 'ประเภทเอกสาร SQ'),

-- 5. Special Funds
('N9', 'ตั้งสต็อกเงิน TR2W/O', 'ZPA_FB50_N9', 'บช.62', 'special_funds', 'ประเภทเอกสาร N9: ตั้งสต็อกเงิน TR2W/O'),
('JU', 'การโอนเงินจาก CCD', 'ZGL_JU', 'บช.63', 'special_funds', 'ประเภทเอกสาร JU: การโอนเงินจาก CCD'),
('G2', 'ตั้งสูตรเงินเบิกเหล่าทหาร', 'ZFB65_G2', 'บช.53', 'special_funds', 'ประเภทเอกสาร G2: ตั้งสูตรเงินเบิกเหล่าทหาร'),
('G5', 'บันทึกแปลงสะสมเงินเหล่าทหาร (กรม)', 'ZGL_G5', 'บช.56', 'special_funds', 'ประเภทเอกสาร G5: บันทึกแปลงสะสมเงินเหล่าทหาร (กรม)'),
('G6', 'บันทึกแปลงสะสมเงินเหล่าทหาร (กองร้อย)', 'ZGL_G6', 'บช.56', 'special_funds', 'ประเภทเอกสาร G6: บันทึกแปลงสะสมเงินเหล่าทหาร (กองร้อย)'),
('G3', 'ลักษณะ/คู่สมุดเงินเหล่าทหาร', 'ZF_51_G3', 'บช.57', 'special_funds', 'ประเภทเอกสาร G3: ลักษณะ/คู่สมุดเงินเหล่าทหาร'),

-- 6. Revenue/Expense Transfers
('JA', 'บันทึกปรับปรุงเงินเหล่าทหาร/โครงการในปีปัจจุบัน', 'ZDB_JA1', 'บช.57-1', 'revenue', 'ประเภทเอกสาร JA: บันทึกปรับปรุงเงินเหล่าทหาร/โครงการในปีปัจจุบัน'),
('JA2', 'บันทึกปรับปรุงเงินเหล่าทหาร/โครงการในปีปัจจุบัน (รูปแบบ 2)', 'ZDB_JA2', 'บช.57-1', 'revenue', 'ประเภทเอกสาร JA2'),
('JF', 'รับเงินยืม', 'ZGL_JF5', 'บช.12', 'expense', 'ประเภทเอกสาร JF: รับเงินยืม'),
('J6', 'จ่ายเงินยืม', 'ZGL_JF6', 'บช.13', 'expense', 'ประเภทเอกสาร J6: จ่ายเงินยืม'),
('J7', 'บันทึกปรับปรุงหมวดรายจ่าย', 'ZGL_J7', 'บช.44', 'expense', 'ประเภทเอกสาร J7: บันทึกปรับปรุงหมวดรายจ่าย'),
('J7CC', 'บันทึกปรับปรุงหมวดรายจ่าย (ต่างหน่วยงาน)', 'ZGL_J7_CC', 'บช.45', 'expense', 'ประเภทเอกสาร J7CC: บันทึกปรับปรุงหมวดรายจ่าย (ต่างหน่วยงาน)'),

-- 7. Revenue/Payable Adjustments
('NK', 'ผลักดันไปรับคืนเงิน', 'ZGL_NK_TKK', 'บช.66', 'accounts_receivable', 'ประเภทเอกสาร NK: ผลักดันไปรับคืนเงิน'),
('N4', 'ผลักดันเงินงบประมาณเป็นรายได้แผ่นดิน', 'ZGL_N4', 'บช.50', 'revenue', 'ประเภทเอกสาร N4: ผลักดันเงินงบประมาณเป็นรายได้แผ่นดิน'),
('N5', 'ผลักดันเงินงบประมาณเป็นรายได้แผ่นดินปีก่อน', 'ZGL_N5', 'บช.51', 'revenue', 'ประเภทเอกสาร N5: ผลักดันเงินงบประมาณเป็นรายได้แผ่นดินปีก่อน'),
('N5B', 'ผลักดันเงินงบประมาณเป็นรายได้แผ่นดินปีก่อน (เบิกก่อน)', 'ZGL_N5', 'บช.52', 'revenue', 'ประเภทเอกสาร N5B: ผลักดันเงินงบประมาณเป็นรายได้แผ่นดินปีก่อน (เบิกก่อน)'),
('N6', 'บันทึกบัญชีเงินฝากในงบประมาณเป็นขั้นตอนสุดท้าย', 'ZGL_N6', 'บช.54', 'revenue', 'ประเภทเอกสาร N6: บันทึกบัญชีเงินฝากในงบประมาณเป็นขั้นตอนสุดท้าย'),
('N7', 'บันทึกบัญชีเงินฝากในงบประมาณเป็นขั้นตอนสุดท้าย (เบิกเต็ม)', 'ZGL_N7', 'บช.54', 'revenue', 'ประเภทเอกสาร N7: บันทึกบัญชีเงินฝากในงบประมาณเป็นขั้นตอนสุดท้าย (เบิกเต็ม)'),
('N8', 'ผลักดันเงินรายได้แผ่นดินคืนสต็อก', 'ZGL_N8', 'บช.55', 'revenue', 'ประเภทเอกสาร N8: ผลักดันเงินรายได้แผ่นดินคืนสต็อก'),
('NC', 'บันทึกบัญชีผิด', 'ZGL_NC', 'บช.65', 'adjustment', 'ประเภทเอกสาร NC: บันทึกบัญชีผิด'),

-- 8. Stock/Inventory Documents
('JX', 'เอกสารนำเข้างานสต็อก', 'ZGL_JX', 'บช.05', 'other', 'ประเภทเอกสาร JX: เอกสารนำเข้างานสต็อก'),
('JY', 'เอกสารนำเข้างานสต็อก (ต่างประเทศ)', 'ZGL_JY', 'บช.08', 'other', 'ประเภทเอกสาร JY: เอกสารนำเข้างานสต็อก (ต่างประเทศ)'),
('JXS', 'เอกสารนำเข้างานสต็อก (โรงพยาบาลสั่งซื้อ)', 'ZGL_JX', 'บช.10', 'other', 'ประเภทเอกสาร JXS: เอกสารนำเข้างานสต็อก (โรงพยาบาลสั่งซื้อ)'),
('JXM', 'เอกสารนำเข้างานสต็อก (เงินหมวดยืมนักษัตร)', 'ZGL_JY', 'บช.11', 'other', 'ประเภทเอกสาร JXM: เอกสารนำเข้างานสต็อก (เงินหมวดยืมนักษัตร)'),

-- 9. Organization/Reorganization
('JP', 'ปรับปรุงประเภท/กรม', 'ZGL_JP', 'บช.49', 'adjustment', 'ประเภทเอกสาร JP: ปรับปรุงประเภท/กรม'),
('JP1', 'ปรับปรุงประเภท/กรม (รูปแบบ 1)', 'ZGL_JP_1', 'บช.49-1', 'adjustment', 'ประเภทเอกสาร JP1: ปรับปรุงประเภท/กรม (รูปแบบ 1)'),
('JO', 'เอกสารขยาย/ปิดบัญชีที่สัดส่วน', 'ZGL_JO', 'บช.59', 'adjustment', 'ประเภทเอกสาร JO: เอกสารขยาย/ปิดบัญชีที่สัดส่วน'),
('JXO', 'เอกสารขยายออก', 'ZGL_JX', 'บช.60', 'adjustment', 'ประเภทเอกสาร JXO: เอกสารขยายออก'),

-- 10. Year-end Closing
('J9C1', 'ปรับบัญชีจากปีเก่า (คงค้าง)', 'ZJ9_C01', 'บช.67', 'adjustment', 'ประเภทเอกสาร J9C1: ปรับบัญชีจากปีเก่า (คงค้าง)'),
('J9C2', 'ปรับบัญชีจากปีเก่า (ยอดมหาศ)', 'ZJ9_C02', 'บช.68', 'adjustment', 'ประเภทเอกสาร J9C2: ปรับบัญชีจากปีเก่า (ยอดมหาศ)')

ON CONFLICT (code) DO UPDATE SET
    name_th = EXCLUDED.name_th,
    sap_transaction_code = EXCLUDED.sap_transaction_code,
    form_number = EXCLUDED.form_number,
    category = EXCLUDED.category,
    description = EXCLUDED.description;

CREATE INDEX IF NOT EXISTS idx_gfmis_doc_types_category ON public.gfmis_document_types(category);

-- ============================================================
-- 2. ADD GFMIS FIELDS TO JOURNAL ENTRIES
-- ============================================================

ALTER TABLE public.journal_entries
    ADD COLUMN IF NOT EXISTS document_type VARCHAR(10) REFERENCES public.gfmis_document_types(code),
    ADD COLUMN IF NOT EXISTS sap_transaction_code VARCHAR(20),
    ADD COLUMN IF NOT EXISTS form_number VARCHAR(10),
    ADD COLUMN IF NOT EXISTS gfmis_batch_id VARCHAR(50),
    ADD COLUMN IF NOT EXISTS gfmis_posted BOOLEAN DEFAULT false;

-- Expand reference_type to support GFMIS source types
ALTER TABLE public.journal_entries
    DROP CONSTRAINT IF EXISTS journal_entries_reference_type_check;

ALTER TABLE public.journal_entries
    ADD CONSTRAINT journal_entries_reference_type_check
    CHECK (reference_type IN (
        'pos_sale','procurement_gr','hr_payroll','telemedicine','logistics',
        'manual','adjustment','opening_balance','gfmis_import'
    ));

CREATE INDEX IF NOT EXISTS idx_journal_entries_doc_type ON public.journal_entries(document_type);
CREATE INDEX IF NOT EXISTS idx_journal_entries_sap_code ON public.journal_entries(sap_transaction_code);
CREATE INDEX IF NOT EXISTS idx_journal_entries_gfmis_batch ON public.journal_entries(gfmis_batch_id);

-- ============================================================
-- 3. LINK GL ENTRIES TO JOURNAL ENTRIES
-- ============================================================

ALTER TABLE public.gl_entries
    ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES public.journal_entries(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS journal_entry_line_id UUID REFERENCES public.journal_entry_lines(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS document_type VARCHAR(10) REFERENCES public.gfmis_document_types(code),
    ADD COLUMN IF NOT EXISTS sap_transaction_code VARCHAR(20),
    ADD COLUMN IF NOT EXISTS form_number VARCHAR(10);

CREATE INDEX IF NOT EXISTS idx_gl_entries_journal_entry ON public.gl_entries(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_gl_entries_doc_type ON public.gl_entries(document_type);

-- ============================================================
-- 4. UPDATE GENERAL LEDGER VIEW
-- ============================================================

DROP VIEW IF EXISTS public.general_ledger;

CREATE OR REPLACE VIEW public.general_ledger AS
SELECT
    je.id AS journal_entry_id,
    je.profession_id,
    je.branch_id,
    je.entry_number,
    je.entry_date,
    je.document_type,
    je.sap_transaction_code,
    je.form_number,
    je.reference_type,
    je.reference_id,
    je.memo,
    je.currency_code,
    je.exchange_rate,
    je.status,
    jel.id AS line_id,
    jel.account_id,
    jel.branch_id AS line_branch_id,
    jel.debit_amount,
    jel.credit_amount,
    jel.base_debit_amount,
    jel.base_credit_amount,
    jel.description AS line_description,
    jel.cost_center,
    coa.account_code,
    coa.account_name,
    coa.account_type,
    gdt.name_th AS document_type_name,
    gdt.category AS document_category,
    je.posted_at,
    je.created_at
FROM public.journal_entry_lines jel
JOIN public.journal_entries je ON jel.journal_entry_id = je.id
JOIN public.chart_of_accounts coa ON jel.account_id = coa.id
LEFT JOIN public.gfmis_document_types gdt ON je.document_type = gdt.code
WHERE je.status = 'posted';

-- ============================================================
-- 5. RPC: MAP DOCUMENT TYPE FROM SAP CODE
-- ============================================================

CREATE OR REPLACE FUNCTION public.resolve_gfmis_document_type(p_sap_code VARCHAR)
RETURNS VARCHAR AS $$
DECLARE
    v_doc_type VARCHAR(10);
BEGIN
    SELECT code INTO v_doc_type
    FROM public.gfmis_document_types
    WHERE sap_transaction_code = p_sap_code
      AND is_active = true
    ORDER BY code
    LIMIT 1;
    
    RETURN v_doc_type;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 6. RPC: CREATE JOURNAL ENTRY WITH GFMIS TYPE
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_journal_entry_gfmis(
    p_profession_id UUID,
    p_branch_id UUID,
    p_document_type VARCHAR(10),
    p_entry_date DATE,
    p_reference_type VARCHAR(50),
    p_reference_id UUID,
    p_memo TEXT,
    p_lines JSONB,  -- [{"account_id": "...", "debit": 0, "credit": 100, "description": "...", "cost_center": "..."}]
    p_created_by UUID
) RETURNS UUID AS $$
DECLARE
    v_entry_id UUID;
    v_entry_number VARCHAR(50);
    v_sap_code VARCHAR(20);
    v_form_num VARCHAR(10);
    v_line JSONB;
    v_total_debit NUMERIC(15,2) := 0;
    v_total_credit NUMERIC(15,2) := 0;
    v_line_debit NUMERIC(15,2);
    v_line_credit NUMERIC(15,2);
BEGIN
    -- Get SAP code and form number from document type
    SELECT sap_transaction_code, form_number
    INTO v_sap_code, v_form_num
    FROM public.gfmis_document_types
    WHERE code = p_document_type;
    
    -- Generate entry number: DOC-YYYYMMDD-XXXX
    v_entry_number := p_document_type || '-' || TO_CHAR(p_entry_date, 'YYYYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 9999)::TEXT, 4, '0');
    
    -- Validate lines balance
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_line_debit := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_line_credit := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_total_debit := v_total_debit + v_line_debit;
        v_total_credit := v_total_credit + v_line_credit;
    END LOOP;
    
    IF v_total_debit != v_total_credit THEN
        RAISE EXCEPTION 'Journal entry must balance: debit % != credit %', v_total_debit, v_total_credit;
    END IF;
    
    -- Create journal entry
    INSERT INTO public.journal_entries (
        profession_id, branch_id, entry_number, entry_date,
        document_type, sap_transaction_code, form_number,
        reference_type, reference_id, memo,
        total_debit, total_credit, status, created_by
    ) VALUES (
        p_profession_id, p_branch_id, v_entry_number, p_entry_date,
        p_document_type, v_sap_code, v_form_num,
        p_reference_type, p_reference_id, p_memo,
        v_total_debit, v_total_credit, 'draft', p_created_by
    ) RETURNING id INTO v_entry_id;
    
    -- Create journal entry lines
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        INSERT INTO public.journal_entry_lines (
            journal_entry_id, account_id, branch_id,
            debit_amount, credit_amount,
            description, cost_center, line_order
        ) VALUES (
            v_entry_id,
            (v_line->>'account_id')::UUID,
            COALESCE((v_line->>'branch_id')::UUID, p_branch_id),
            COALESCE((v_line->>'debit')::NUMERIC, 0),
            COALESCE((v_line->>'credit')::NUMERIC, 0),
            v_line->>'description',
            v_line->>'cost_center',
            COALESCE((v_line->>'line_order')::INT, 0)
        );
    END LOOP;
    
    RETURN v_entry_id;
END;
$$ LANGUAGE plpgsql;
