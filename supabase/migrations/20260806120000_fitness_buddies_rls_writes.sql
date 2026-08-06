-- Fitness Buddies RLS write policies (Phase 1: app layer enforces authorization)
-- Fixes 42501 on INSERT/UPDATE/DELETE for fitness_buddies tables
-- Date: 2026-08-06

-- Ensure RLS enabled where needed (idempotent)
ALTER TABLE IF EXISTS public.sports ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fitness_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fitness_group_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fitness_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fitness_group_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fitness_group_blocklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chat_rooms ENABLE ROW LEVEL SECURITY;

-- sports (proposals, admin edits)
DROP POLICY IF EXISTS sports_modify_all ON public.sports;
CREATE POLICY sports_modify_all ON public.sports FOR ALL USING (true) WITH CHECK (true);

-- fitness_groups
DROP POLICY IF EXISTS fitness_groups_modify_all ON public.fitness_groups;
CREATE POLICY fitness_groups_modify_all ON public.fitness_groups FOR ALL USING (true) WITH CHECK (true);

-- fitness_group_sessions
DROP POLICY IF EXISTS fitness_group_sessions_modify_all ON public.fitness_group_sessions;
CREATE POLICY fitness_group_sessions_modify_all ON public.fitness_group_sessions FOR ALL USING (true) WITH CHECK (true);

-- fitness_group_members
DROP POLICY IF EXISTS fitness_group_members_modify_all ON public.fitness_group_members;
CREATE POLICY fitness_group_members_modify_all ON public.fitness_group_members FOR ALL USING (true) WITH CHECK (true);

-- fitness_group_bookings
DROP POLICY IF EXISTS fitness_group_bookings_modify_all ON public.fitness_group_bookings;
CREATE POLICY fitness_group_bookings_modify_all ON public.fitness_group_bookings FOR ALL USING (true) WITH CHECK (true);

-- fitness_group_blocklist
DROP POLICY IF EXISTS fitness_group_blocklist_modify_all ON public.fitness_group_blocklist;
CREATE POLICY fitness_group_blocklist_modify_all ON public.fitness_group_blocklist FOR ALL USING (true) WITH CHECK (true);

-- chat_rooms (trigger from fitness_groups writes here)
DROP POLICY IF EXISTS chat_rooms_modify_all ON public.chat_rooms;
CREATE POLICY chat_rooms_modify_all ON public.chat_rooms FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
