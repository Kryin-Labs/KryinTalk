-- Catalog data only: no tokens, passwords, messages, filenames or user PII.
SELECT jsonb_build_object(
  'columns', (SELECT jsonb_agg(jsonb_build_object('table', table_name, 'column', column_name,
    'type', data_type, 'default', column_default) ORDER BY table_name, ordinal_position)
    FROM information_schema.columns WHERE table_schema = 'public'),
  'rls', (SELECT jsonb_agg(jsonb_build_object('table', c.relname, 'enabled', c.relrowsecurity))
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'),
  'policies', (SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p
    WHERE schemaname IN ('public', 'storage')),
  'functions', (SELECT jsonb_agg(jsonb_build_object('name', p.proname,
    'args', pg_get_function_identity_arguments(p.oid), 'definer', p.prosecdef,
    'settings', p.proconfig, 'anon_execute', has_function_privilege('anon', p.oid, 'EXECUTE'),
    'authenticated_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE')))
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
    AND p.prosecdef),
  'triggers', (SELECT jsonb_agg(jsonb_build_object('table', c.relname, 'name', t.tgname,
    'definition', pg_get_triggerdef(t.oid))) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('public', 'auth')),
  'attachments_bucket', (SELECT jsonb_agg(jsonb_build_object('id', id, 'public', public,
    'file_size_limit', file_size_limit)) FROM storage.buckets WHERE id = 'attachments'),
  'realtime', (SELECT jsonb_agg(tablename) FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public')
) AS audit;
