BEGIN;
-- Use the same partition-valid relational authority as the account review RPCs.
CREATE OR REPLACE FUNCTION public.is_org_admin(p_org_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.has_app_access() AND (public.is_super_admin() OR
 (public.is_org_member(p_org_id) AND 'admin'=ANY(kryintalk_private.account_roles(auth.uid()))))
$$;
COMMIT;
