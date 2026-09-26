-- Legacy SQL seeds omitted these GoTrue string fields. NULL makes /token
-- fail with "Database error querying schema" before checking the password.
-- Preserve every account, password hash, identity, and non-null token.
BEGIN;
UPDATE auth.users SET
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, '')
WHERE confirmation_token IS NULL OR recovery_token IS NULL
   OR email_change IS NULL OR email_change_token_new IS NULL;
COMMIT;
