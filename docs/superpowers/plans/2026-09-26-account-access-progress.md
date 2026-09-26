# Account access execution ledger

User authorized implementation in the existing D:\conhub checkout, preserving dirty work and without agents/tasks. Later authorized private GitHub upload to Kryin-Labs. Original git checkout/index/history remain intact; upload uses a clean separate snapshot.

- Exported actual live public schema, storage policies and auth trigger read-only; local reports remain ignored. No live service-role key retrieved.
- Four precise migrations tested locally and applied live: account_access, access_administration, app_access_invites, signup_integrity. Previously rejected pending_identity_guard.sql remains untouched.
- 78 database assertions passed against exported schema: identity/confirmation, pending direct data and storage/RPC denial, private-message membership, forbidden privilege writes, consent, admin role bounds, atomic audit rollback, invite restrictions and normalized username collision prevention.
- Concurrent local REST redemption allowed exactly one member approval; parallel bad attempts reached the server rate limit; local logout completed.
- Local signup, Mailpit delivery, exact confirmation callback, reused-link recovery, explicit login, pending own-profile and direct users/messages/files/notification denials all passed. No mail links or tokens printed.
- 31 Flutter checks passed: form guards, Enter/busy, unchecked agreements, policy dialogs, light/dark 360/768/1440px at 200% text, access/recovery/resend, stale-response isolation, reply navigation, literal HTML, Markdown and fresh attachment signing.
- Release web build passed. Analyzer had no errors; 227 warning/info findings remain. Final checks repeat after safe admin error handling changed.
- Stdlib preview check passed: callback document served, missing asset and traversal return 404. Browser verified signup/login/policy close and invalid callback recovery. Preview stays at http://127.0.0.1:8080/#/register.
- Live Site URL is https://kryintalks.vercel.app, with exact production/local callback allowlist, confirmation required, password minimum 8. SMTP remains unset, so production delivery is not claimed.
- Existing matching confirmed profiles retain approval, with explicit consent required. No identity/message ownership was remapped.
- Existing confirmed @superadmin has an old role scoped to another internal partition. Exact role repair SQL is prepared locally. Automatic approval review rejected that role grant for lack of explicit authorization; no workaround/retry occurred. User approval is required to complete bootstrap. Account, credentials, history and consent unchanged.
- Private GitHub repository created at https://github.com/Kryin-Labs/KryinTalk. Upload snapshot excludes credentials, local reports, vendor binaries, backups, retired holding-area scripts and generated APKs.
- Vercel config builds Flutter 3.44.9 using the official checksum-verified Linux archive; preserves 404 for missing assets and serves the callback document. User will import repo; Vercel execution is unverified until import. Deployment instructions are in docs/DEPLOYMENT.md.
