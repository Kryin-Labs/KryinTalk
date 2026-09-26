-- Only known repository demo accounts; no IDs, hashes, or credentials returned.
SELECT jsonb_agg(jsonb_build_object(
  'account', CASE a.email
    WHEN 'user@connecthub.local' THEN 'member demo'
    WHEN 'admin@connecthub.local' THEN 'admin demo'
    WHEN 'superadmin@connecthub.local' THEN 'superadmin demo'
  END,
  'profile_email_matches_auth', p.email = a.email,
  'assigned_roles', (
    SELECT coalesce(jsonb_agg(r.code ORDER BY r.code), '[]'::jsonb)
    FROM public.user_roles ur JOIN public.roles r
      ON replace(ur.role_id, '-', '') = replace(r.id::text, '-', '')
    WHERE replace(ur.user_id, '-', '') = replace(a.id::text, '-', '')
  )
) ORDER BY a.email) AS demo_roles
FROM auth.users a LEFT JOIN public.users p ON p.id = a.id
WHERE a.email IN ('user@connecthub.local',
  'admin@connecthub.local', 'superadmin@connecthub.local');
