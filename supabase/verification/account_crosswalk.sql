SELECT jsonb_build_object(
  'alignment', (SELECT jsonb_agg(jsonb_build_object(
    'auth_account', split_part(a.email, '@', 1) || CASE WHEN a.email LIKE '%.local'
      THEN '-local' ELSE '-external' END,
    'profile_at_auth_id', (SELECT split_part(owner.email, '@', 1) || CASE
      WHEN owner.email LIKE '%.local' THEN '-local' ELSE '-external' END
      FROM auth.users owner WHERE owner.email = by_id.email),
    'profile_at_auth_id_exists', by_id.id IS NOT NULL,
    'profile_by_email_has_auth', EXISTS (SELECT 1 FROM auth.users other
      JOIN public.users by_email ON by_email.id = other.id
      WHERE by_email.email = a.email)
  ) ORDER BY a.email) FROM auth.users a
    LEFT JOIN public.users by_id ON by_id.id = a.id),
  'user_constraints', (SELECT jsonb_agg(jsonb_build_object('name', conname,
    'definition', pg_get_constraintdef(oid))) FROM pg_constraint
    WHERE conrelid = 'public.users'::regclass),
  'user_indexes', (SELECT jsonb_agg(indexname) FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'users')
) AS crosswalk;
