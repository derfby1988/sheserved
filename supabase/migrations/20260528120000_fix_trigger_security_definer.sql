-- Fix: init_consultation_room_experts trigger function needs SECURITY DEFINER
-- สาเหตุ: trigger รันด้วย privileges ของผู้ใช้ที่ INSERT (patient) ซึ่งอาจถูก RLS บล็อก
-- ไม่ให้อ่าน expert_groups จาก consultation_packages → ไม่มีแถวถูกสร้างใน consultation_room_experts
-- ผลกระทบ: ExpertStatusBanner ไม่แสดง expert ใดๆ (joined=0), _mergeWithPackageGroups ใส่แต่ waiting groups

-- 1. แก้ไข function ให้รันด้วย privileges ของ owner (postgres)
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Ensure RLS policies allow reading consultation_room_experts for consultation participants
-- (ถ้ายังไม่มี policy นี้)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'consultation_room_experts'
      AND policyname = 'allow_consultation_participants_select'
  ) THEN
    CREATE POLICY allow_consultation_participants_select
      ON public.consultation_room_experts
      FOR SELECT
      TO authenticated
      USING (
        consultation_id IN (
          SELECT id FROM public.consultation_requests
          WHERE user_id = auth.uid()
             OR provider_id = auth.uid()
        )
      );
  END IF;
END $$;
