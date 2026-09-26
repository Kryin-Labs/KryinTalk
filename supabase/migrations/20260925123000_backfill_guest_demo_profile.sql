-- Give the seeded guest Auth account its own empty profile. Leave the legacy
-- profile and its conversation history at the original ID.
BEGIN;
DO $$
DECLARE
  guest_auth_id uuid;
  guest_org_id text;
  guest_role_id text;
BEGIN
  SELECT id INTO STRICT guest_auth_id FROM auth.users
  WHERE email = 'guestuser@connecthub.local';
  IF EXISTS (SELECT 1 FROM public.users WHERE id = guest_auth_id) THEN
    RAISE EXCEPTION 'Guest Auth account already has a profile';
  END IF;
  SELECT u.organization_id INTO STRICT guest_org_id FROM public.users u
  JOIN public.organizations o
    ON replace(o.id::text, '-', '') = replace(u.organization_id, '-', '')
  WHERE u.email = 'guestuser@connecthub.local'
    AND o.is_active AND o.deleted_at IS NULL;
  SELECT r.id::text INTO STRICT guest_role_id FROM public.roles r
  WHERE r.code = 'guest' AND r.is_active
    AND (r.organization_id IS NULL OR
      replace(r.organization_id, '-', '') = replace(guest_org_id, '-', ''));

  INSERT INTO public.users (
    id, organization_id, email, username, display_name, password_hash,
    is_active, is_suspended, role
  ) VALUES (
    guest_auth_id, guest_org_id, 'guestuser@connecthub.local',
    'guestuser_demo', 'Guest User', 'managed-by-supabase-auth',
    true, false, 'guest'
  );
  INSERT INTO public.user_roles (user_id, role_id)
  VALUES (guest_auth_id::text, guest_role_id);
END $$;
COMMIT;
