-- Labels and booleans only. Do not return IDs or personal profile data.
SELECT jsonb_agg(jsonb_build_object(
  'label', split_part(a.email, '@', 1),
  'profile_matches_auth', p.email = a.email,
  'roles', (SELECT coalesce(jsonb_agg(r.code ORDER BY r.code), '[]'::jsonb)
    FROM public.user_roles ur JOIN public.roles r
      ON replace(ur.role_id, '-', '') = replace(r.id::text, '-', '')
    WHERE replace(ur.user_id, '-', '') = replace(a.id::text, '-', ''))
) ORDER BY split_part(a.email, '@', 1)) AS account_alignment
FROM auth.users a LEFT JOIN public.users p ON p.id = a.id;
