-- Migration: Add share analytics columns to fitness_groups
-- Created for Phase 20 (Share & Deep Link)

ALTER TABLE public.fitness_groups 
ADD COLUMN IF NOT EXISTS share_visit_count INT NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS share_join_count INT NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_shared_visit_at TIMESTAMPTZ;

-- RPC for recording a share visit
-- SECURITY DEFINER allows unauthenticated Guest users to increment the counter
CREATE OR REPLACE FUNCTION public.record_fitness_group_share_visit(p_group_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.fitness_groups
  SET 
    share_visit_count = share_visit_count + 1,
    last_shared_visit_at = NOW()
  WHERE id = p_group_id;
END;
$$;
