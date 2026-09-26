SELECT jsonb_build_object(
  'columns', (SELECT jsonb_agg(jsonb_build_object('column', column_name, 'type', data_type, 'nullable', is_nullable)) FROM information_schema.columns WHERE table_schema='public' AND table_name='file_attachments'),
  'rls', (SELECT relrowsecurity FROM pg_class WHERE oid='public.file_attachments'::regclass),
  'privileges', jsonb_build_object('select', has_table_privilege('authenticated','public.file_attachments','SELECT'), 'insert', has_table_privilege('authenticated','public.file_attachments','INSERT'), 'update_table', has_table_privilege('authenticated','public.file_attachments','UPDATE'), 'rename', has_column_privilege('authenticated','public.file_attachments','original_filename','UPDATE'), 'delete_mark', has_column_privilege('authenticated','public.file_attachments','deleted_at','UPDATE'), 'storage_path_update', has_column_privilege('authenticated','public.file_attachments','storage_path','UPDATE')),
  'storage_policies', (SELECT jsonb_agg(jsonb_build_object('name',policyname,'using',qual,'check',with_check)) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'ch_storage_%'),
  'file_counts', (SELECT jsonb_build_object('chat',count(*) FILTER (WHERE conversation_id IS NOT NULL),'standalone',count(*) FILTER (WHERE conversation_id IS NULL)) FROM public.file_attachments WHERE deleted_at IS NULL)
) AS file_catalog;
