-- Patch: แก้ไข get_available_users_for_invite ให้ค้นหาด้วย username ได้เสมอ
-- Date: 2026-07-13
--
-- ปัญหา: RPC เดิมใช้ COALESCE(NULLIF(TRIM(first_name || ' ' || last_name), ''), u.username)
-- ทำให้ถ้าผู้ใช้มี first_name/last_name อยู่แล้ว การค้นหาด้วย username จะไม่ทำงาน
-- เช่น ค้นหา "firm" ไม่เจอถ้า user นั้นมีชื่อ-นามสกุลอยู่แล้ว
--
-- วิธีแก้: แยกเงื่อนไขค้นหาออกเป็น name OR username OR email OR phone แยกกัน

CREATE OR REPLACE FUNCTION public.get_available_users_for_invite(
  p_profession_id UUID,
  p_search TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(jsonb_build_object(
      'id', u.id,
      'full_name', COALESCE(NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''), u.username, u.email),
      'email', u.email,
      'phone', u.phone,
      'role', u.role
    ))
    FROM public.users u
    WHERE u.is_active = true
      AND NOT EXISTS (
        SELECT 1 FROM public.employees e
        WHERE e.profession_id = p_profession_id AND e.user_id = u.id
      )
      AND (
        p_search IS NULL OR
        COALESCE(NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''), '') ILIKE '%' || p_search || '%' OR
        u.username ILIKE '%' || p_search || '%' OR
        u.email ILIKE '%' || p_search || '%' OR
        u.phone ILIKE '%' || p_search || '%'
      )
  );
END;
$$;
