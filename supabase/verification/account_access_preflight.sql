SELECT jsonb_build_object(
 'columns', (SELECT jsonb_agg(to_jsonb(c)) FROM information_schema.columns c WHERE table_schema='public'),
 'policies', (SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE schemaname IN ('public','storage','realtime')),
 'functions', (SELECT jsonb_agg(jsonb_build_object('name',p.proname,'definition',pg_get_functiondef(p.oid),
   'args',pg_get_function_identity_arguments(p.oid),'definer',p.prosecdef,
   'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
   'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f'),
 'column_grants', (SELECT jsonb_agg(to_jsonb(g)) FROM information_schema.column_privileges g WHERE table_schema='public' AND grantee IN ('anon','authenticated')),
 'triggers', (SELECT jsonb_agg(pg_get_triggerdef(t.oid)) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('auth','public')),
 'buckets', (SELECT jsonb_agg(jsonb_build_object('id',id,'public',public)) FROM storage.buckets),
 'alignment', (SELECT jsonb_build_object('matching_confirmed',count(*) FILTER (WHERE lower(trim(a.email))=lower(trim(u.email)) AND a.email_confirmed_at IS NOT NULL),
   'mismatched',count(*) FILTER (WHERE a.id IS NOT NULL AND lower(trim(a.email)) IS DISTINCT FROM lower(trim(u.email))),
   'orphan_profiles',count(*) FILTER (WHERE a.id IS NULL)) FROM public.users u LEFT JOIN auth.users a ON a.id=u.id)
) AS audit;
