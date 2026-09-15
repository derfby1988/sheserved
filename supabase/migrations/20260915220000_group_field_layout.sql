-- Migration: 20260915220000_group_field_layout.sql
-- Description: Allow fitness_groups to have custom field_layout (single/double) and safety validation RPC

-- 1. Add field_layout column to fitness_groups if not exists
ALTER TABLE public.fitness_groups
  ADD COLUMN IF NOT EXISTS field_layout VARCHAR(10) NULL
  CHECK (field_layout IN ('none', 'single', 'double'));

COMMENT ON COLUMN public.fitness_groups.field_layout IS 'Custom field layout for this group (none, single, double). If NULL, fall back to sport.field_layout.';

-- 2. Function to check if a group can safely reduce field_layout from 'double' to 'single'
-- Returns:
--   can_reduce: BOOLEAN
--   reason: TEXT (NULL if safe, or explanation why reduction is blocked)
CREATE OR REPLACE FUNCTION public.can_reduce_group_field_layout(p_group_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_has_active_right_positions BOOLEAN;
  v_has_upcoming_bookings BOOLEAN;
  v_upcoming_count INT;
BEGIN
  -- 1. Check if there are active positions on the right side (side = 1)
  SELECT EXISTS (
    SELECT 1
    FROM public.fitness_group_positions
    WHERE group_id = p_group_id
      AND is_active = true
      AND side = 1
  ) INTO v_has_active_right_positions;

  IF v_has_active_right_positions THEN
    -- Check if any of these right-side positions have bookings in upcoming sessions
    SELECT COUNT(*)
    INTO v_upcoming_count
    FROM public.fitness_group_bookings b
    JOIN public.fitness_group_sessions s ON b.session_id = s.id
    JOIN public.fitness_group_positions p ON b.position_id = p.id
    WHERE s.group_id = p_group_id
      AND p.side = 1
      AND s.start_time >= now()
      AND b.status IN ('confirmed', 'pending');

    IF v_upcoming_count > 0 THEN
      RETURN jsonb_build_object(
        'can_reduce', false,
        'reason', 'มีรอบนัดในอนาคตที่สมาชิกจองตำแหน่งในฝั่งขวาไว้แล้ว (' || v_upcoming_count || ' รายการ) กรุณารอให้รอบนัดเสร็จสิ้นหรือแจ้งผู้ใช้ย้ายตำแหน่งก่อน'
      );
    END IF;

    -- If no upcoming bookings, still warn that right-side positions will need to be adjusted
    RETURN jsonb_build_object(
      'can_reduce', true,
      'has_right_positions', true,
      'reason', 'มีหมุดตำแหน่งฝั่งขวาอยู่ หมุดเหล่านี้จะถูกปิดการใช้งานเมื่อเปลี่ยนเป็น 1 ฝั่ง'
    );
  END IF;

  RETURN jsonb_build_object(
    'can_reduce', true,
    'has_right_positions', false,
    'reason', NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_reduce_group_field_layout(UUID) TO anon, authenticated, sheserved_app;
