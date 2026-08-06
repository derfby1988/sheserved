-- Fix chat_rooms: ensure room_ref_id exists for fitness_group integration
-- Date: 2026-08-06

-- Ensure prerequisite columns
ALTER TABLE IF EXISTS public.chat_rooms
  ADD COLUMN IF NOT EXISTS room_type TEXT DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS room_ref_id UUID;

-- Helpful index for lookups by (room_type, room_ref_id)
CREATE INDEX IF NOT EXISTS idx_chat_rooms_roomtype_ref ON public.chat_rooms(room_type, room_ref_id);

NOTIFY pgrst, 'reload schema';
