-- Aggregate references at the three mismatched demo Auth IDs. No row data or IDs.
SELECT jsonb_build_object(
  'foreign_keys', (SELECT jsonb_agg(jsonb_build_object(
    'table', conrelid::regclass::text, 'column', a.attname,
    'definition', pg_get_constraintdef(c.oid)))
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND c.confrelid = 'public.users'::regclass
      AND array_length(c.conkey, 1) = 1),
  'demo_references', (SELECT jsonb_agg(jsonb_build_object(
    'account', split_part(a.email, '@', 1),
    'messages_sent', (SELECT count(*) FROM public.messages m WHERE m.sender_id = a.id),
    'conversations', (SELECT count(*) FROM public.conversation_participants cp WHERE cp.user_id = a.id),
    'notifications', (SELECT count(*) FROM public.notification_items n WHERE n.user_id = a.id),
    'group_memberships', (SELECT count(*) FROM public.group_members gm WHERE replace(gm.user_id::text, '-', '') = replace(a.id::text, '-', '')),
    'role_assignments', (SELECT count(*) FROM public.user_roles ur WHERE replace(ur.user_id::text, '-', '') = replace(a.id::text, '-', ''))
  ) ORDER BY a.email) FROM auth.users a
    WHERE a.email IN ('admin@connecthub.local', 'user@connecthub.local', 'manager@connecthub.local'))
) AS references;
