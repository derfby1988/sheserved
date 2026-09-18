-- Prevent active/upcoming sessions in the same group from overlapping.
--
-- The previous owner-overlap trigger only rejected overlaps when
-- owner_auto_join=true. Session time conflicts are a group invariant, so
-- enforce it for every session entry point (direct inserts, repository calls,
-- admin tooling, and updates) at the database boundary.
--
-- Existing historical overlaps are left untouched. Only a new or edited
-- session that has not ended is checked.

CREATE OR REPLACE FUNCTION public.guard_fitness_session_owner_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Serialize writes for the same group so two concurrent inserts cannot
  -- both pass the overlap check before either row becomes visible.
  PERFORM pg_advisory_xact_lock(hashtext(NEW.group_id::text));

  IF NEW.ends_at >= now()
     AND EXISTS (
       SELECT 1
       FROM public.fitness_group_sessions s
       WHERE s.group_id = NEW.group_id
         AND s.id <> NEW.id
         AND s.ends_at >= now()
         AND (s.starts_at, s.ends_at) OVERLAPS (NEW.starts_at, NEW.ends_at)
     ) THEN
    RAISE EXCEPTION 'GROUP_SESSION_OVERLAP'
      USING ERRCODE = 'P0001',
            DETAIL = 'A group session overlaps another active or upcoming session';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_fitness_session_owner_overlap
  ON public.fitness_group_sessions;

CREATE TRIGGER trg_guard_fitness_session_owner_overlap
BEFORE INSERT OR UPDATE OF group_id, starts_at, ends_at
ON public.fitness_group_sessions
FOR EACH ROW EXECUTE FUNCTION public.guard_fitness_session_owner_overlap();
