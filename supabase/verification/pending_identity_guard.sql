-- Legacy demo seeds reused Auth IDs for different public users. An Auth token
-- must never inherit that other profile's organization, messages, or role.
BEGIN;
CREATE OR REPLACE FUNCTION public.auth_profile_matches()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users a
    JOIN public.users u ON u.id = a.id
    WHERE a.id = auth.uid()
      AND lower(u.email) = lower(a.email)
      AND u.is_active AND NOT u.is_suspended AND u.deleted_at IS NULL
  )
$$;
REVOKE ALL ON FUNCTION public.auth_profile_matches() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auth_profile_matches() TO authenticated;

-- Restrictive policies cover direct REST access, including old JWTs and RPCs
-- that do not pass through the Flutter profile check.
DO $$
DECLARE target record;
BEGIN
  FOR target IN
    SELECT n.nspname, c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND c.relrowsecurity
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS kt_aligned_auth ON %I.%I', target.nspname, target.relname);
    EXECUTE format(
      'CREATE POLICY kt_aligned_auth ON %I.%I AS RESTRICTIVE FOR ALL TO authenticated USING (public.auth_profile_matches()) WITH CHECK (public.auth_profile_matches())',
      target.nspname, target.relname
    );
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.current_user_org_id()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT o.id::text
  FROM public.users u
  JOIN public.organizations o ON public.same_kryintalk_key(o.id::text, u.organization_id)
  WHERE u.id = auth.uid() AND public.auth_profile_matches()
    AND o.is_active AND o.deleted_at IS NULL
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_org_admin(p_org_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.auth_profile_matches() AND p_org_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON public.same_kryintalk_key(r.id::text, ur.role_id)
    WHERE public.same_kryintalk_key(ur.user_id, auth.uid()::text)
      AND r.is_active AND r.code IN ('super_admin', 'admin', 'manager')
      AND (r.organization_id IS NULL OR public.same_kryintalk_key(r.organization_id, p_org_id))
  )
$$;

CREATE OR REPLACE FUNCTION public.get_current_user_profile()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH role_codes AS (
    SELECT r.code FROM public.user_roles ur
    JOIN public.roles r ON public.same_kryintalk_key(r.id::text, ur.role_id)
    WHERE public.same_kryintalk_key(ur.user_id, auth.uid()::text) AND r.is_active
  ), ranked_role AS (
    SELECT code FROM role_codes ORDER BY CASE code
      WHEN 'super_admin' THEN 1 WHEN 'admin' THEN 2 WHEN 'manager' THEN 3
      WHEN 'user' THEN 4 WHEN 'member' THEN 5 WHEN 'guest' THEN 6 ELSE 99 END
    LIMIT 1
  )
  SELECT (to_jsonb(u) - 'password_hash') || jsonb_build_object(
    'role', coalesce((SELECT code FROM ranked_role), 'member'),
    'roles', coalesce((SELECT jsonb_agg(code ORDER BY code) FROM role_codes), '[]'::jsonb),
    'is_super_admin', exists (SELECT 1 FROM role_codes WHERE code = 'super_admin')
  )
  FROM public.users u WHERE u.id = auth.uid() AND public.auth_profile_matches()
$$;
COMMIT;
