-- Resolve the signed-in user's role from the normalized role relation.
-- The production export stores relation keys as text; profile rows do not
-- contain an authority column.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_current_user_profile()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH role_codes AS (
    SELECT r.code
    FROM public.user_roles AS ur
    JOIN public.roles AS r ON public.same_kryintalk_key(r.id::text, ur.role_id)
    WHERE public.same_kryintalk_key(ur.user_id, auth.uid()::text)
      AND r.is_active
  ), ranked_role AS (
    SELECT code
    FROM role_codes
    ORDER BY CASE code
      WHEN 'super_admin' THEN 1
      WHEN 'admin' THEN 2
      WHEN 'manager' THEN 3
      WHEN 'user' THEN 4
      WHEN 'member' THEN 5
      WHEN 'guest' THEN 6
      ELSE 99
    END
    LIMIT 1
  )
  SELECT to_jsonb(u) || jsonb_build_object(
    'role', coalesce((SELECT code FROM ranked_role), 'member'),
    'roles', coalesce((SELECT jsonb_agg(code ORDER BY code) FROM role_codes), '[]'::jsonb),
    'is_super_admin', exists (SELECT 1 FROM role_codes WHERE code = 'super_admin')
  )
  FROM public.users AS u
  WHERE u.id = auth.uid()
    AND u.is_active
    AND NOT u.is_suspended
    AND u.deleted_at IS NULL
$$;

REVOKE ALL ON FUNCTION public.get_current_user_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_current_user_profile() TO authenticated;

COMMIT;
