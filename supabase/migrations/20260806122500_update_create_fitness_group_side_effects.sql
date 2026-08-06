-- Update trigger function to avoid type mismatch and ensure deterministic chat_room id
-- Date: 2026-08-06

CREATE OR REPLACE FUNCTION public.create_fitness_group_side_effects()
RETURNS TRIGGER AS $$
DECLARE
  v_room_id TEXT;
BEGIN
  -- Create a chat room for this fitness group (id is TEXT; prefix with 'group_')
  v_room_id := 'group_' || NEW.id::text;

  INSERT INTO public.chat_rooms (id, participant_ids, last_message, room_type, room_ref_id)
    VALUES (v_room_id, ARRAY[]::UUID[], NULL, 'fitness_group', NEW.id)
  ON CONFLICT (id) DO NOTHING;

  -- Ensure creator becomes admin member
  IF NEW.created_by IS NOT NULL THEN
    INSERT INTO public.fitness_group_members (group_id, user_id, role, is_active, joined_at)
      VALUES (NEW.id, NEW.created_by, 'admin', true, now())
    ON CONFLICT (group_id, user_id) DO UPDATE SET role='admin', is_active=true;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger to ensure it points to the updated function
DROP TRIGGER IF EXISTS trg_create_fitness_group_side_effects ON public.fitness_groups;
CREATE TRIGGER trg_create_fitness_group_side_effects
AFTER INSERT ON public.fitness_groups
FOR EACH ROW EXECUTE FUNCTION public.create_fitness_group_side_effects();

NOTIFY pgrst, 'reload schema';
