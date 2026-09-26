SELECT jsonb_agg(jsonb_build_object(
  'account', CASE a.email
    WHEN 'user@connecthub.local' THEN 'member demo'
    WHEN 'admin@connecthub.local' THEN 'admin demo' END,
  'profile_exists', p.id IS NOT NULL,
  'target_email_conflict', EXISTS (
    SELECT 1 FROM public.users other
    WHERE lower(other.email) = lower(a.email) AND other.id <> a.id
  ),
  'conflicting_profile_has_auth', EXISTS (
    SELECT 1 FROM public.users other JOIN auth.users owner ON owner.id = other.id
    WHERE lower(other.email) = lower(a.email) AND other.id <> a.id
  ),
  'member_role_candidates', (
    SELECT count(*) FROM public.roles r
    WHERE r.code IN ('member','user') AND r.is_active
      AND (r.organization_id = p.organization_id OR r.organization_id IS NULL)
  ),
  'admin_role_candidates', (
    SELECT count(*) FROM public.roles r
    WHERE r.code = 'admin' AND r.is_active
      AND (r.organization_id = p.organization_id OR r.organization_id IS NULL)
  )
) ORDER BY a.email) AS preflight
FROM auth.users a LEFT JOIN public.users p ON p.id = a.id
WHERE a.email IN ('user@connecthub.local', 'admin@connecthub.local');
