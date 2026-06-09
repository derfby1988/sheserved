# Accounting Outbox Payload Specification

## Overview
ทุก write operation ที่มีผลต่อเงินหรือสต๊อกต้องผ่าน `outbox_events` ก่อน commit แล้ว consumer จะอ่าน event นี้เพื่อสร้าง `journal_entries` ใน Accounting module

---

## 1. POS Sale → Accounting (Revenue)

### Event Type
`pos.sale.completed`

### Aggregate
- `aggregate_type`: `pos_sale`
- `aggregate_id`: `order_id` (UUID)

### Payload Schema
```json
{
  "event_version": "1.0",
  "source": "pos_system",
  "profession_id": "00000000-0000-0000-0000-000000000003",
  "branch_id": "uuid-or-null",
  "order_id": "order-uuid",
  "order_number": "SO-2026-0001",
  "sale_date": "2026-06-09",
  "customer_id": "customer-uuid",
  "customer_type": "patient",
  "payment_method": "cash",
  "currency_code": "THB",
  "exchange_rate": 1.0,
  "lines": [
    {
      "line_id": "line-uuid-1",
      "product_id": "product-uuid",
      "product_type": "medicine",
      "product_name": "Paracetamol 500mg",
      "quantity": 2,
      "unit_price": 150.00,
      "total_price": 300.00,
      "discount_amount": 0.00,
      "vat_rate": 7.00,
      "vat_amount": 21.00,
      "revenue_account_code": "4111",
      "cogs_account_code": "5111",
      "inventory_account_code": "1131"
    },
    {
      "line_id": "line-uuid-2",
      "product_type": "service",
      "product_name": "ค่าตรวจรักษา",
      "quantity": 1,
      "unit_price": 500.00,
      "total_price": 500.00,
      "vat_rate": 7.00,
      "vat_amount": 35.00,
      "revenue_account_code": "4211",
      "cogs_account_code": null,
      "inventory_account_code": null
    }
  ],
  "summary": {
    "subtotal": 800.00,
    "total_discount": 0.00,
    "total_vat": 56.00,
    "grand_total": 856.00,
    "total_cogs": 180.00
  },
  "payments": [
    {
      "method": "cash",
      "amount": 856.00,
      "reference": "",
      "bank_account_code": "1111"
    }
  ]
}
```

### Generated Journal Entry (Double-Entry)
| Account Code | Account Name | Debit (THB) | Credit (THB) |
|-------------|-------------|------------|-------------|
| 1111 | เงินสดในมือ | 856.00 | |
| 4111 | รายได้จากการขายยา | | 300.00 |
| 4211 | รายได้จากการตรวจรักษา | | 500.00 |
| 2132 | ภาษีมูลค่าเพิ่มรอนำส่ง | | 56.00 |
| 5111 | ต้นทุนยาและเวชภัณฑ์ | 180.00 | |
| 1131 | สินค้าคงเหลือ - ยา | | 180.00 |

### VAT Record Generated
- `document_type`: `tax_invoice`
- `vat_type`: `output`
- `vat_base_amount`: 800.00
- `vat_amount`: 56.00
- `reporting_period`: `2026-06`

---

## 2. Procurement GR → Accounting (AP + Inventory)

### Event Type
`procurement.goods_received`

### Aggregate
- `aggregate_type`: `procurement_gr`
- `aggregate_id`: `gr_id` (UUID)

### Payload Schema
```json
{
  "event_version": "1.0",
  "source": "procurement_system",
  "profession_id": "00000000-0000-0000-0000-000000000003",
  "branch_id": "uuid-or-null",
  "gr_id": "gr-uuid",
  "gr_number": "GR-2026-0042",
  "po_id": "po-uuid",
  "po_number": "PO-2026-0015",
  "supplier_id": "supplier-uuid",
  "supplier_name": "บริษัท เมดิคัล ซัพพลาย จำกัด",
  "supplier_tax_id": "0123456789012",
  "gr_date": "2026-06-09",
  "currency_code": "THB",
  "exchange_rate": 1.0,
  "lines": [
    {
      "line_id": "line-uuid-1",
      "product_id": "product-uuid",
      "product_name": "หน้ากากอนามัย N95",
      "quantity_received": 100,
      "unit_cost": 25.00,
      "total_cost": 2500.00,
      "vat_rate": 7.00,
      "vat_amount": 175.00,
      "inventory_account_code": "1131",
      "ap_account_code": "2111"
    }
  ],
  "summary": {
    "subtotal": 2500.00,
    "total_vat": 175.00,
    "grand_total": 2675.00
  }
}
```

### Generated Journal Entry
| Account Code | Account Name | Debit (THB) | Credit (THB) |
|-------------|-------------|------------|-------------|
| 1131 | สินค้าคงเหลือ - ยา | 2,500.00 | |
| 1141 | ภาษีซื้อรอนำส่ง | 175.00 | |
| 2111 | เจ้าหนี้การค้า | | 2,675.00 |

### VAT Record Generated
- `document_type`: `purchase_invoice`
- `vat_type`: `input`
- `vat_base_amount`: 2500.00
- `vat_amount`: 175.00

---

## 3. HR Payroll → Accounting (Expense)

### Event Type
`hr.payroll.processed`

### Payload Schema
```json
{
  "event_version": "1.0",
  "source": "hr_system",
  "profession_id": "00000000-0000-0000-0000-000000000003",
  "branch_id": "uuid-or-null",
  "payroll_id": "payroll-uuid",
  "payroll_period": "2026-06",
  "payroll_date": "2026-06-30",
  "employees": [
    {
      "employee_id": "emp-uuid-1",
      "employee_name": "สมชาย ใจดี",
      "salary": 35000.00,
      "overtime": 2500.00,
      "social_security_employee": 750.00,
      "social_security_employer": 750.00,
      "withholding_tax": 1500.00,
      "net_pay": 35250.00
    }
  ],
  "summary": {
    "total_salary": 35000.00,
    "total_overtime": 2500.00,
    "total_ss_employer": 750.00,
    "total_withholding_tax": 1500.00,
    "total_net_pay": 35250.00
  }
}
```

### Generated Journal Entry
| Account Code | Account Name | Debit (THB) | Credit (THB) |
|-------------|-------------|------------|-------------|
| 5211 | เงินเดือนและค่าจ้าง | 35,000.00 | |
| 5212 | ค่าล่วงเวลา / โอที | 2,500.00 | |
| 5213 | เงินสมทบประกันสังคม | 750.00 | |
| 2131 | ภาษีหัก ณ ที่จ่าย รอนำส่ง | | 1,500.00 |
| 2133 | ประกันสังคมรอนำส่ง | | 750.00 |
| 1112 / 1113 | เงินฝากธนาคาร | | 36,000.00 |

---

## 4. Manual Journal Entry

### Event Type
`accounting.journal.created`

### Payload Schema
```json
{
  "event_version": "1.0",
  "source": "accounting_manual",
  "profession_id": "00000000-0000-0000-0000-000000000003",
  "branch_id": "uuid-or-null",
  "entry_number": "JV-2026-0100",
  "entry_date": "2026-06-09",
  "memo": "ปรับปรุงค่าเสื่อมราคาเดือนมิถุนายน",
  "currency_code": "THB",
  "lines": [
    {
      "account_code": "5231",
      "debit_amount": 5000.00,
      "credit_amount": 0.00,
      "description": "ค่าเสื่อมราคาเครื่องมือแพทย์"
    },
    {
      "account_code": "1212",
      "debit_amount": 0.00,
      "credit_amount": 5000.00,
      "description": "ค่าเสื่อมราคาสะสม"
    }
  ]
}
```

---

## Consumer Flow (Accounting Worker)

```
outbox_events (status=pending)
    ↓
Accounting Worker polls every 5s
    ↓
Parse payload → Validate accounts exist
    ↓
Create journal_entries (status=draft)
    ↓
Create journal_entry_lines (debit=credit)
    ↓
If valid: POST journal_entries → status=posted
    ↓
Create vat_records (if applicable)
    ↓
Update outbox_events → status=published
    ↓
If fail: retry_count++ → status=failed (after max retries)
```
