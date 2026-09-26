# KryinTalk deployment

Import the private Kryin-Labs/KryinTalk repository into Vercel. Use repository root `/`, framework preset **Other**, and project name `kryintalks` if available. The committed `vercel.json` builds the Flutter client using the checksum-verified Flutter 3.44.9 SDK and publishes `clients/web/build/web`. It rewrites the confirmation callback document while leaving missing assets as 404s. Vercel build execution itself remains to be verified after import.

Production origin: https://kryintalks.vercel.app. The build uses this by default. If Vercel assigns a different domain, set `AUTH_CALLBACK_ORIGIN` in Vercel, add its exact `/auth/callback` URL in Supabase Authentication URL Configuration, and rebuild. Optional `KRYINTALK_ADMIN_CONTACT_EMAIL` changes the contact dialog. Neither value is a secret. Never put a Supabase service-role or management token in the client or Vercel build.

The live Supabase project has the access migrations applied, confirmation required, minimum password length 8, and the production callback allowlisted. Production SMTP is not configured: add a verified sender and provider credentials in Supabase Authentication SMTP Settings, then test delivery to a real mailbox. The built-in sender is unsuitable for unrestricted public signup. No sender credentials are committed.

An existing confirmed fake account had a superadmin role scoped to a different internal partition. Repairing that relational role was rejected by automatic approval review and remains pending explicit user approval. Its identity, credentials, messages, and consent were preserved. No arbitrary new signup receives admin access. Admins use Users → Requests to approve email-confirmed pending accounts, or issue recipient-bound, member-only, single-use access codes under Invites.

Local preview: `flutter build web --release --dart-define=AUTH_CALLBACK_ORIGIN=http://127.0.0.1:8080` from `clients/web`, then `python scripts/serve_web_preview.py` from the repository root. Open http://127.0.0.1:8080/#/register. Local callbacks are allowlisted. The production build script supplies the production origin instead.

Verification: `flutter test`; `flutter analyze` (existing lint warnings remain); local Supabase `test db`; `node scripts/account_access_concurrency.mjs` against disposable local fixtures; `python scripts/test_web_preview.py`. Concurrency tests refuse production hosts. Signed attachment links last at most 60 seconds; download and image retry request a fresh authorized link.

This private upload is a clean snapshot of the current source, including the previously modified application work. Existing local git history and working-tree edits were left intact. Credentials, local database reports, vendor binaries, backups, old holding-area scripts, and built APKs are excluded.
