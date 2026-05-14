-- Migration: Trigger to init consultation_room_experts
CREATE OR REPLACE FUNCTION public.init_consultation_room_experts()
RETURNS TRIGGER AS $$
DECLARE
  v_expert_groups JSONB;
  v_group JSONB;
BEGIN
  -- ดึง expert_groups จากแพ็คเกจ
  SELECT expert_groups INTO v_expert_groups
  FROM public.consultation_packages
  WHERE id = NEW.package_id;

  IF v_expert_groups IS NOT NULL AND jsonb_typeof(v_expert_groups) = 'array' THEN
    FOR v_group IN SELECT * FROM jsonb_array_elements(v_expert_groups)
    LOOP
      INSERT INTO public.consultation_room_experts (
        consultation_id, room_id, expert_group_id, expert_group_name,
        expert_group_role, max_experts, is_required, status
      ) VALUES (
        NEW.id, NEW.room_id,
        v_group->>'id',
        v_group->>'name',
        v_group->>'role',
        COALESCE((v_group->>'maxExperts')::INT, 1),
        COALESCE((v_group->>'isRequired')::BOOLEAN, false),
        'waiting'
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_consultation_request_created ON public.consultation_requests;
CREATE TRIGGER on_consultation_request_created
  AFTER INSERT ON public.consultation_requests
  FOR EACH ROW EXECUTE FUNCTION public.init_consultation_room_experts();
