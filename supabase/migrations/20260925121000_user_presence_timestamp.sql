-- Keep activity timestamps separate from the actual login timestamp.
BEGIN;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_active_at timestamptz;
UPDATE public.users SET last_active_at = last_login_at
WHERE last_active_at IS NULL AND last_login_at IS NOT NULL;
GRANT SELECT (last_active_at) ON public.users TO authenticated;
COMMIT;
