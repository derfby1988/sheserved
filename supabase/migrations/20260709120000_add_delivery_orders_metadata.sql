-- Migration: Add metadata column to delivery_orders (P6 — Drug Risk Override Plan)
-- Date: 2026-07-09
-- Purpose: Embed drug_risk_flags (has_override, override_scope, requires_id_verification,
-- no_safe_box_allowed) so riders/warehouse staff know special handling requirements
-- for controlled substances at pickup/delivery time.

ALTER TABLE public.delivery_orders
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_delivery_orders_metadata_gin
  ON public.delivery_orders USING gin (metadata);

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
