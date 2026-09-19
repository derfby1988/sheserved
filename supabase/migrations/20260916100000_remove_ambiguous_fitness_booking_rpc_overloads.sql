DROP FUNCTION IF EXISTS public.book_fitness_session(UUID, UUID);
DROP FUNCTION IF EXISTS public.book_fitness_session(UUID, UUID, UUID);

CREATE OR REPLACE FUNCTION public.book_fitness_session(
  p_session_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN public.book_fitness_session(
    p_session_id,
    app.require_current_user_id(),
    NULL::UUID,
    NULL::VARCHAR
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.book_fitness_session(UUID, UUID, UUID, VARCHAR)
  TO anon, authenticated, sheserved_app;
GRANT EXECUTE ON FUNCTION public.book_fitness_session(UUID)
  TO anon, authenticated, sheserved_app;

NOTIFY pgrst, 'reload schema';
