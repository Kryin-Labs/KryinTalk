SELECT jsonb_build_object(
  'file_policies', (SELECT jsonb_agg(jsonb_build_object('name', policyname,
    'command', cmd, 'roles', roles, 'using', qual, 'check', with_check))
    FROM pg_policies WHERE schemaname = 'public' AND tablename = 'file_attachments'),
  'file_grants', (SELECT jsonb_agg(jsonb_build_object('privilege', privilege_type,
    'grantee', grantee)) FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'file_attachments'
      AND grantee IN ('authenticated', 'anon')),
  'storage_policies', (SELECT jsonb_agg(jsonb_build_object('name', policyname,
    'command', cmd, 'roles', roles)) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects')
) AS attachment_access;
