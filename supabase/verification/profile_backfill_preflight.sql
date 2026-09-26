SELECT jsonb_build_object(
  'public_profiles', (SELECT count(*) FROM public.users),
  'active_workspaces', (SELECT count(*) FROM public.organizations
    WHERE is_active AND deleted_at IS NULL),
  'accounts', (SELECT jsonb_agg(jsonb_build_object(
    'label', split_part(a.email, '@', 1) || CASE WHEN a.email LIKE '%.local'
      THEN '-local' ELSE '-external' END,
    'profile_exists', p.id IS NOT NULL,
    'email_conflict', EXISTS(SELECT 1 FROM public.users other
      WHERE lower(other.email) = lower(a.email) AND other.id <> a.id),
    'username_hint', a.raw_user_meta_data ->> 'username',
    'org_hint_valid', EXISTS(SELECT 1 FROM public.organizations o
      WHERE o.id::text = a.raw_user_meta_data ->> 'organization_id'
        AND o.is_active AND o.deleted_at IS NULL)
  ) ORDER BY a.email) FROM auth.users a
    LEFT JOIN public.users p ON p.id = a.id)
) AS preflight;
