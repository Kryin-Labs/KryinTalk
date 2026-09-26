-- The seeded regular Auth account inherited an unrelated super_admin role.
-- Revoke that role at its exact Auth ID. No profile or message row is moved.
BEGIN;
DO $$
DECLARE
  account_id uuid;
  member_role_id text;
BEGIN
  SELECT a.id INTO STRICT account_id
  FROM auth.users a JOIN public.users u ON u.id = a.id
  WHERE a.email = 'user@connecthub.local' AND lower(u.email) <> lower(a.email);
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur JOIN public.roles r
      ON replace(ur.role_id, '-', '') = replace(r.id::text, '-', '')
    WHERE replace(ur.user_id, '-', '') = replace(account_id::text, '-', '')
      AND r.code = 'super_admin'
  ) THEN
    RAISE EXCEPTION 'Expected inherited super_admin role was not found';
  END IF;
  SELECT r.id::text INTO STRICT member_role_id
  FROM public.roles r JOIN public.users u
    ON replace(r.organization_id, '-', '') = replace(u.organization_id, '-', '')
       OR r.organization_id IS NULL
  WHERE u.id = account_id AND r.code IN ('member', 'user') AND r.is_active;

  DELETE FROM public.user_roles
  WHERE replace(user_id, '-', '') = replace(account_id::text, '-', '');
  INSERT INTO public.user_roles (user_id, role_id)
  VALUES (account_id::text, member_role_id);
END $$;
COMMIT;
