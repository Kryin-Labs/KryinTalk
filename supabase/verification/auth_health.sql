-- Aggregate checks only. Do not return passwords, tokens, or account details.
SELECT jsonb_build_object('auth', (SELECT to_jsonb(checks) FROM (SELECT count(*) AS auth_users,
  count(*) FILTER (WHERE confirmation_token IS NULL) AS null_confirmation_token,
  count(*) FILTER (WHERE recovery_token IS NULL) AS null_recovery_token,
  count(*) FILTER (WHERE email_change IS NULL) AS null_email_change,
  count(*) FILTER (WHERE email_change_token_new IS NULL) AS null_email_change_token_new,
  count(*) FILTER (WHERE email_change_token_current IS NULL) AS null_email_change_token_current,
  count(*) FILTER (WHERE reauthentication_token IS NULL) AS null_reauthentication_token
FROM auth.users) checks),
'migrations', (SELECT jsonb_agg(version ORDER BY version)
FROM supabase_migrations.schema_migrations));
