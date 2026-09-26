SELECT jsonb_build_object(
  'guest_auth_count', (SELECT count(*) FROM auth.users WHERE email = 'guestuser@connecthub.local'),
  'guest_auth_has_profile', (SELECT EXISTS (
    SELECT 1 FROM auth.users a JOIN public.users u ON u.id = a.id
    WHERE a.email = 'guestuser@connecthub.local')),
  'legacy_guest_profile_count', (SELECT count(*) FROM public.users
    WHERE email = 'guestuser@connecthub.local'),
  'legacy_guest_org_active', (SELECT bool_and(o.is_active AND o.deleted_at IS NULL)
    FROM public.users u JOIN public.organizations o
      ON replace(o.id::text, '-', '') = replace(u.organization_id, '-', '')
    WHERE u.email = 'guestuser@connecthub.local'),
  'guest_role_count', (SELECT count(*) FROM public.roles WHERE code = 'guest' AND is_active)
) AS guest_backfill;
