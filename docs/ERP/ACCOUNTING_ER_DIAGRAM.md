# Accounting System ER Diagram

```mermaid
erDiagram
    professions ||--o{ organization_branches : has
    professions ||--o{ outbox_events : emits
    professions ||--o{ chart_of_accounts : owns
    professions ||--o{ journal_entries : records
    professions ||--o{ vat_records : reports
    professions ||--o{ tax_forms : files
    professions ||--o{ exchange_rates : sets
    professions ||--o{ accounting_periods : defines
    professions ||--o{ product_account_mappings : configures

    organization_branches ||--o{ journal_entries : at_branch
    organization_branches ||--o{ journal_entry_lines : at_branch
    organization_branches ||--o{ vat_records : at_branch
    organization_branches ||--o{ tax_forms : at_branch

    chart_of_accounts ||--o{ journal_entry_lines : debited_or_credited
    chart_of_accounts ||--o{ product_account_mappings : mapped_to
    chart_of_accounts ||--o{ chart_of_accounts : parent_of

    journal_entries ||--o{ journal_entry_lines : contains
    journal_entries ||--o{ vat_records : linked_to
    journal_entries ||--|| outbox_events : sourced_from

    tax_forms ||--o{ tax_form_lines : contains
    tax_forms ||--o{ vat_records : aggregates

    journal_entry_lines ||--o{ vat_records : generates
```

## รายละเอียดตาราง (Table Details)

### `organization_branches`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัสสาขา |
| profession_id | UUID | FK → professions | องค์กรเจ้าของ |
| branch_code | TEXT | UQ | รหัสสาขา (HQ, B01) |
| branch_name | TEXT | | ชื่อสาขา |
| tax_id | TEXT | | เลขผู้เสียภาษี (ถ้าแยก) |

### `outbox_events`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัส event |
| profession_id | UUID | FK → professions | องค์กร |
| aggregate_type | TEXT | | pos_sale, procurement_gr, hr_payroll, manual |
| aggregate_id | UUID | | รหัส aggregate |
| event_type | TEXT | | เช่น pos.sale.completed |
| payload | JSONB | | ข้อมูล event |
| status | TEXT | | pending, published, failed, processing |
| retry_count | INT | | จำนวน retry |

### `chart_of_accounts`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัสบัญชี |
| profession_id | UUID | FK → professions | องค์กร |
| branch_id | UUID | FK → organization_branches | สาขา (nullable) |
| account_code | VARCHAR(20) | UQ | รหัสบัญชี (1111, 4111) |
| account_name | VARCHAR(255) | | ชื่อบัญชี |
| account_type | SMALLINT | | 1=Asset 2=Liability 3=Equity 4=Revenue 5=Expense |
| parent_id | UUID | FK → chart_of_accounts | บัญชีแม่ |
| is_default | BOOLEAN | | บัญชีเริ่มต้น |

### `journal_entries`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัสรายการ |
| profession_id | UUID | FK → professions | องค์กร |
| branch_id | UUID | FK → organization_branches | สาขา |
| entry_number | VARCHAR(50) | UQ | เลขที่รายการ |
| entry_date | DATE | | วันที่บันทึก |
| reference_type | VARCHAR(50) | | pos_sale, procurement_gr, manual |
| reference_id | UUID | | รหัสอ้างอิง |
| source_event_id | UUID | FK → outbox_events | event ต้นทาง |
| memo | TEXT | | คำอธิบาย |
| currency_code | VARCHAR(3) | | สกุลเงิน |
| exchange_rate | NUMERIC | | อัตราแลกเปลี่ยน |
| status | VARCHAR(20) | | draft, posted, reversed |

### `journal_entry_lines`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัสบรรทัด |
| journal_entry_id | UUID | FK → journal_entries | รายการแม่ |
| account_id | UUID | FK → chart_of_accounts | บัญชี |
| branch_id | UUID | FK → organization_branches | สาขา |
| debit_amount | NUMERIC | | ยอดเดบิต |
| credit_amount | NUMERIC | | ยอดเครดิต |
| base_debit_amount | NUMERIC | | ยอดเดบิตสกุลหลัก |
| base_credit_amount | NUMERIC | | ยอดเครดิตสกุลหลัก |
| description | TEXT | | รายละเอียด |

### `vat_records`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัส VAT |
| profession_id | UUID | FK → professions | องค์กร |
| journal_entry_id | UUID | FK → journal_entries | รายการบัญชี |
| document_type | VARCHAR(20) | | tax_invoice, purchase_invoice |
| document_number | VARCHAR(50) | UQ | เลขที่เอกสาร |
| vat_type | VARCHAR(10) | | output (ขาย), input (ซื้อ) |
| vat_rate | NUMERIC | | อัตรา VAT |
| vat_base_amount | NUMERIC | | ฐานภาษี |
| vat_amount | NUMERIC | | ภาษี |
| reporting_period | VARCHAR(7) | | YYYY-MM |

### `tax_forms`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัสฟอร์ม |
| profession_id | UUID | FK → professions | องค์กร |
| form_type | VARCHAR(10) | | ภ.ง.ด.1/3/53/30, ภ.พ.30 |
| tax_year | INT | | ปีภาษี |
| tax_period | VARCHAR(7) | | YYYY-MM หรือ YYYY-QN |
| status | VARCHAR(20) | | draft, filed, amended |
| total_tax_amount | NUMERIC | | ยอดภาษีรวม |
| xml_payload | TEXT | | XML e-Filing |
| json_payload | JSONB | | ข้อมูล JSON |

### `tax_form_lines`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัสบรรทัด |
| tax_form_id | UUID | FK → tax_forms | ฟอร์มแม่ |
| line_type | VARCHAR(20) | | summary, detail, attachment |
| amount | NUMERIC | | ยอดเงิน |
| tax_amount | NUMERIC | | ภาษี |

### `product_account_mappings`
| Column | Type | Key | Description |
|--------|------|-----|-------------|
| id | UUID | PK | รหัส mapping |
| profession_id | UUID | FK → professions | องค์กร |
| product_id | UUID | | รหัสสินค้า |
| product_type | VARCHAR(20) | | inventory_item, service, package |
| revenue_account_id | UUID | FK → chart_of_accounts | บัญชีรายได้ |
| cogs_account_id | UUID | FK → chart_of_accounts | บัญชีต้นทุน |
| inventory_account_id | UUID | FK → chart_of_accounts | บัญชีสินค้า |
