-- Migration: Add procurement aggregate types to outbox_events CHECK constraint
-- Date: 2026-07-02
-- Prerequisites: 20260609180000_create_accounting_core_schema.sql (outbox_events)

-- The original CHECK constraint on outbox_events.aggregate_type only allows:
-- 'pos_sale','procurement_gr','hr_payroll','telemedicine','logistics','manual'
-- We need to add procurement_po, procurement_pr, back_order for procurement outbox events.

ALTER TABLE public.outbox_events DROP CONSTRAINT IF EXISTS outbox_events_aggregate_type_check;

ALTER TABLE public.outbox_events ADD CONSTRAINT outbox_events_aggregate_type_check
    CHECK (aggregate_type IN ('pos_sale','procurement_gr','procurement_po','procurement_pr','back_order','hr_payroll','telemedicine','logistics','manual','accounting'));
