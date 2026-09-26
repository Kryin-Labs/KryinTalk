# KryinTalk Account Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver personal signup, email confirmation, consent-gated login, pending access, admin approval, member access codes, and reliable server audit records.

**Architecture:** Keep Supabase Auth as the only identity provider. Store approval and consent in the existing profile, enforce both in database policies/RPCs, and use a restricted Flutter auth layout until access is approved. Reuse existing roles, audit logs, theme, legal content, and admin routes; add one invite table.

**Tech Stack:** Flutter/Dart, Riverpod, GoRouter, Supabase Flutter, PostgreSQL functions/RLS, Supabase CLI and its local pgTAP test support; no new application dependencies.

**Spec:** [Account and access design](../specs/2026-09-26-kryintalk-account-access-design.md). Read the complete spec before implementation; its button tables and copy are acceptance requirements.

This is a planning artifact. App changes and live database writes have not begun. Implement in this session after design review; do not automatically spawn workers.

## Global Constraints

- Signup creates a personal account; no workspace, company, organization, server, or group creation fields.
- Production authentication, access decisions, storage, and admin actions use Supabase; no FastAPI fallback.
- Retain Flutter, Riverpod, GoRouter, existing icons, existing fonts, and AppTheme; add no UI framework dependency.
- Keep existing Terms and Privacy content; do not invent legal clauses.
- Never grant access or roles from client metadata, preferences, query strings, or JWT claims alone.
- Never log passwords, tokens, confirmation URLs, raw invite codes, hashes, or SMTP credentials; reveal an invite code only in its creator's one-time dialog.
- Preserve existing message ownership, reply navigation, HTML/code rendering, and Markdown attachment fixes.
- Public signup requires email confirmation before sign-in; approval never substitutes for confirmation.
- Every explicit password login requires an unchecked-by-default agreement checkbox; Enter follows the same rule.
- First release app codes are email-bound, single-use, valid for 7 days, and grant member access only.
- All protected data operations require the current database approval state, including storage and privileged RPCs.

## Review Focus

1. A confirmation email opened in another tab/browser must confirm once and lead to sign-in without granting access or logging out other devices. Task 6 tests callback/reused-link behavior and verifies both browser contexts.
2. Account switching or suspension while a request/subscription is in flight must not expose cached data from the previous identity. Task 4 tests stale completions and provider disposal.
3. Two people redeeming the same code concurrently must produce one success; failed-attempt logging must survive safe rejection. Task 3 tests transactions, reuse, and rate limits.
4. Unknown/missing profile fields, forged role metadata, and conflicting legacy identity must fail closed while a valid pending profile remains readable. Tasks 1, 2, and 4 exercise these cases.
5. Keyboard submission, 360px layout, large text, dark mode, and policy-modal dismissal must preserve disabled/consent semantics. Tasks 5 and 7 exercise these interactions.

---

## Files and responsibilities

| File | Responsibility |
| --- | --- |
| `supabase/migrations/20260926120000_account_access.sql` | Profile columns, pending signup trigger, consent, safe profile, identity/access helpers, policy/RPC audit |
| `supabase/migrations/20260926121000_access_administration.sql` | Server-approved account listing, review actions, role changes, immutable audit authorization |
| `supabase/migrations/20260926122000_app_access_invites.sql` | One invite table, issue/list/revoke/redeem operations and rate limit |
| `supabase/verification/account_access_preflight.sql` | Read-only aggregate/catalog verification; no raw credentials or personal messages |
| `supabase/tests/account_access.sql` | Transactional identity, pending, consent, RLS/storage, role, and audit assertions |
| `supabase/tests/app_access_invites.sql` | Transactional invite and failed-attempt assertions |
| `scripts/account_access_concurrency.mjs` | One local-only concurrency check using native fetch/assert |
| `clients/web/lib/core/supabase/supabase_service.dart` | SDK signup/resend/callback, safe profile and onboarding RPC calls |
| `clients/web/lib/core/auth/auth_service.dart` | Explicit registration result, consent validation, sanitized auth errors |
| `clients/web/lib/core/auth/auth_provider.dart` | Session vs approved-access state; session events and refresh |
| `clients/web/lib/core/router/app_router.dart` | Loading/public/onboarding/protected route boundaries |
| `clients/web/lib/core/api/api_client.dart` | Keep Supabase bridge; authorization denial refresh without treating pending as invalid credentials |
| `clients/web/lib/core/presence/presence_provider.dart` | Only approved, current-policy identity starts presence |
| `clients/web/lib/core/notifications/notification_provider.dart` | Stop/clear/restart notifications with approved access and identity changes |
| `clients/web/lib/core/notifications/web_notification_service.dart` | Browser notification lifecycle obeys the same access boundary |
| `clients/web/lib/shared/widgets/app_scaffold.dart` | Protected shell only; unread counts require approved access |
| `clients/web/lib/features/auth/auth_widgets.dart` | Small common auth layout, policy links/modal, and matching input/button styles |
| `clients/web/lib/features/auth/register_screen.dart` | Personal form, confirmation password, live requirements, disabled agreement CTA |
| `clients/web/lib/features/auth/login_screen.dart` | Matching login UI, email-only label, disabled agreement CTA; remove inert keep-signed-in control |
| `clients/web/lib/features/auth/confirmation_screen.dart` | Check-email/resend and callback loading/success/error screens |
| `clients/web/lib/features/auth/access_screen.dart` | Restricted pending/restricted dashboard and restored-session consent screen |
| `clients/web/lib/features/admin/user_management_screen.dart` | Requests/Members/Invites tabs and working RPC-backed dialogs |
| `clients/web/lib/features/admin/audit_log_screen.dart` | Safe access-event filters/detail presentation |
| `clients/web/lib/features/groups/group_invite_screen.dart` | Group links cannot bypass pending/restricted access |
| `clients/web/lib/features/messaging/chat_screen.dart` | Fresh authorized URL on attachment download/retry after shorter URL expiry |
| `clients/web/lib/features/files/file_list_screen.dart` | Fresh authorized file download rather than a stale cached URL |
| `clients/web/lib/main.dart` | Callback-aware startup before protected routing/providers |
| `clients/web/test/auth_service_test.dart` | Extend existing auth regression checks |
| `clients/web/test/account_access_test.dart` | State/redirect/session transition checks |
| `clients/web/test/auth_forms_test.dart` | Button/validation/modal/responsive widget checks |
| `.env.example` | Non-secret callback origin and optional admin contact settings |
| `scripts/serve_web_preview.py` | Minimal SPA fallback for the actual callback path |

Keep types with the existing auth files; do not introduce repositories, factories, or another global state layer. Query/admin pagination maps can remain JSON maps in the existing style.

## Task 1: Pending signup and authoritative data gates

**Files:** Create account-access migration, preflight, and `supabase/tests/account_access.sql`; modify the existing helpers by replacing their definitions in the new migration, never editing already-applied migrations.

**Interfaces:** `has_verified_kryintalk_identity() RETURNS boolean`; `has_app_access() RETURNS boolean`; `get_current_user_profile() RETURNS jsonb`; `record_account_consent(p_version text) RETURNS jsonb`; `is_signup_username_available(p_username text) RETURNS boolean`. The safe profile has `access_status`, `email_confirmed`, `policy_version`, and `is_active/is_suspended` booleans; pending profile role is null and roles is an empty array.

- [ ] Capture current policies, functions, column grants, storage privacy, and aggregate Auth/profile alignment using the existing read-only verification mechanism. Include `pg_policies`, `pg_proc.prosecdef`, function EXECUTE grants, buckets' public flags, and mismatch counts in `account_access_preflight.sql`.
- [ ] Create a disposable local Supabase environment under ignored `tools/account-access-test`. Initialize it with the installed CLI; export only the current public schema as its base migration, add local fixture data, copy the proposed migrations/tests there, and start it. Do not use the old full seed as a production repair. Require a working local container runtime before database-test claims.

```powershell
tools\supabase\supabase.exe --workdir tools/account-access-test init
tools\supabase\supabase.exe db dump --linked --schema public --file tools/account-access-test/supabase/migrations/20260926000000_base.sql
tools\supabase\supabase.exe --workdir tools/account-access-test start
tools\supabase\supabase.exe --workdir tools/account-access-test db reset
tools\supabase\supabase.exe --workdir tools/account-access-test test db
```

- [ ] Write transactional pgTAP fixtures with six isolated test Auth/profile identities: pending, unconfirmed, approved member, approved admin, approved superadmin, mismatched email. Use UUIDs `a1000000-0000-4000-8000-000000000001` through `a1000000-0000-4000-8000-000000000006`; seed one active internal organization/roles locally and empty non-null Auth token strings. Approved fixtures have current consent and correct roles; pending fixture has consent but no role. Seed nonempty messages in two separate private conversations, notification/file rows, and private storage objects. Copy current relevant storage policies into the disposable baseline from the read-only catalog, so denial is tested against actual readable fixtures; an approved participant must pass positive controls. Each test starts BEGIN and ends ROLLBACK, with a pgTAP plan/finish. Set JWT subject/claims and role explicitly for the actor under test.
- [ ] Add these failing assertions for pending actor `a1000000-0000-4000-8000-000000000001`:

```sql
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SELECT ok(public.has_verified_kryintalk_identity(), 'pending identity is valid');
SELECT ok(NOT public.has_app_access(), 'pending is not approved');
SELECT is(public.get_current_user_profile()->>'access_status', 'pending', 'own status readable');
SELECT is(public.get_current_user_profile()->'roles', '[]'::jsonb, 'pending has no roles');
SELECT ok(NOT (public.get_current_user_profile() ? 'password_hash'), 'hash is private');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.messages), 'pending cannot read messages');
SELECT ok(NOT EXISTS (SELECT 1 FROM storage.objects), 'pending cannot read stored objects');
```

- [ ] Add matching checks for unconfirmed/mismatched/inactive/deleted profiles, forged metadata `role=super_admin`, direct protected-column updates, and old-policy-version approved profiles. Add an approved actor check proving private-conversation membership still matters. Run the local tests and observe failures before migration.
- [ ] Add new columns with defaults/constraints. Backfill only matching confirmed active existing identities as approved; keep their policy version null so restored sessions must record consent. New Auth inserts produce pending profiles and no role assignment. Ignore metadata organization/role/access fields; validate only display name, normalized username, and consent input.

```sql
ALTER TABLE public.users
  ADD COLUMN access_status text NOT NULL DEFAULT 'pending'
    CHECK (access_status IN ('pending','approved','rejected','revoked')),
  ADD COLUMN access_reviewed_at timestamptz,
  ADD COLUMN access_reviewed_by uuid REFERENCES public.users(id),
  ADD COLUMN access_reason text CHECK (length(access_reason) <= 500),
  ADD COLUMN policy_version text,
  ADD COLUMN policy_accepted_at timestamptz;
```

- [ ] Replace the signup trigger so the internal organization is server-selected for legacy partition compatibility and never constitutes membership. Insert profile once; do not ON CONFLICT overwrite an unrelated identity. Copy consent only when submitted agreement is true and version exactly `2026-09-26`; the timestamp is server-generated. Add scalar username availability checked on submission, retaining the unique constraint for races.
- [ ] Implement fixed-search-path identity/access helpers and whitelisted own-profile/consent RPCs. Gate all existing protected central helpers plus direct self policies and every exposed bypassing SECURITY DEFINER RPC. Explicitly audit `is_org_admin`, group invite functions, roles, files, notifications, friends, audit records, storage, and Realtime channels.

```sql
-- Core predicate inside has_app_access(); use trusted Auth row joined to u.
a.id = auth.uid()
AND a.email_confirmed_at IS NOT NULL
AND lower(trim(a.email)) = lower(trim(u.email))
AND u.is_active AND NOT u.is_suspended AND u.deleted_at IS NULL
AND u.access_status = 'approved'
AND u.policy_version = '2026-09-26'
```

- [ ] Revoke direct writes to protected profile/role/consent columns and forged audit events. Retain necessary presentation-field writes. Preserve the legacy security trigger while ensuring trusted consent RPC writes are not accidentally reset. Revoke PUBLIC/anon execution for privileged routines; onboarding routines require authenticated identity. Prevent RLS recursion by keeping the core helpers independent of gated helpers.
- [ ] Run local SQL tests again. Require real read/write/storage/RPC denial, not only migration-text checks. Inspect grants and explain any remaining intentional public endpoint. Deliverable: a verified pending account can read its own status but has no protected app access.

## Task 2: Server-authorized admin review and role management

**Files:** Create `20260926121000_access_administration.sql`; extend `supabase/tests/account_access.sql`.

**Interfaces:** Exact RPC signatures/JSON are defined in spec section 7. Lists return `{items:[],total:int}`. Mutations return the updated safe target profile/status. Normal admins can affect ordinary members in their permitted partition; superadmins can affect admins. Managers never gain app-review authority.

- [ ] Add failing tests for member/manager calling review RPCs, admin changing an admin/superadmin, self-role changes, cross-partition targets, unverified approval, and removing the last active superadmin. Use `throws_ok(...,'42501',...)` for permission failures and controlled invalid-state codes for stale transitions.
- [ ] Implement bounded list/search and review RPCs. Actor is always `auth.uid()` with current approved access. Lock the target row; recheck current state, verified identity, role rank, and partition inside the transaction. Allow these transitions only:

```text
approve: pending -> approved + member role
decline: pending -> rejected
reopen: rejected/revoked -> pending, no role granted
suspend: approved -> is_suspended true
restore: approved + suspended -> is_suspended false
revoke: pending/approved/rejected -> revoked, remove application role assignments
```

- [ ] Validate reasons as trimmed 1-500 characters for decline/reopen/suspend/revoke, optional for approve/restore. Keep denial reasons public only where UI explicitly tells the reviewer they will be shown. Admin cannot approve a suspended target or grant an admin role as part of approval.
- [ ] Implement `set_app_account_role(p_user_id uuid,p_role text)` for member/admin choices; trusted bootstrap handles superadmin separately. Serialize privileged-role changes with one transaction-scoped advisory lock so concurrent revocations cannot remove all superadmins. Use the same lock for review actions affecting privileged targets. Count matching verified, approved, active, non-suspended/non-deleted superadmins independently of policy version, so publishing new terms does not permit deleting their protected role.
- [ ] Reuse internal `write_kryintalk_audit` with client execution revoked. Record old/new values, actor/target and reason in the same transaction. Enforce append-only client grants. Confirm an injected audit failure rolls back the access change.

```sql
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000005","role":"authenticated"}', true);
SELECT public.review_app_access(
  'a1000000-0000-4000-8000-000000000001', 'approve', NULL);
SELECT is((SELECT access_status FROM public.users
  WHERE id='a1000000-0000-4000-8000-000000000001'), 'approved', 'approved atomically');
SELECT ok(EXISTS (SELECT 1 FROM public.audit_logs
  WHERE action='access.approved'
    AND resource_id='a1000000-0000-4000-8000-000000000001'), 'approval audited');
```

- [ ] Run local SQL tests for approved member usability and target limits. Deliverable: admin actions work through Supabase and cannot elevate the caller or bypass server state.

## Task 3: App access codes

**Files:** Create invite migration, `supabase/tests/app_access_invites.sql`, and one concurrency script.

**Interfaces:** `create_app_access_invite(email)` returns `{id,code,expires_at}` once; list returns `{items,total}` without code/digest; revoke returns safe metadata; redeem returns `{ok:boolean,error_code?:string,profile?:json}`. Failed code validation returns JSON, not an exception that rolls back the failed-attempt event.

- [ ] Write failing SQL tests for wrong email, unverified/rejected/suspended/revoked user, invalid code, expiry, revocation, reuse, failed-attempt audit, 5-attempt/15-minute limit, and missing policy consent. Verify no direct read of a code digest or pending account table insert.
- [ ] Add the invite table from spec section 7 with unique digest, single-use fields, FK/expiry constraints, and indexes on recipient/status and failed-attempt audit actor/time. Generate 24 random bytes server-side, encode hex, return once, and store only SHA-256 digest. Trim/normalize recipient email; role and partition come only from the approved creator.
- [ ] Implement issue/list/revoke server functions, with pagination and current admin authorization. Raw codes are visible only in the immediate successful issue response; no persisted clipboard cache.
- [ ] Implement redeem with consistent lock order: invite row, then recipient profile. Recheck current email/identity, pending status, consent, expiration and revocation; enforce failed-attempt rate limit server-side. Invalid attempts commit only redacted audit events. Success grants member, consumes invite, and records approval/redemption atomically. Distinct network/database errors cannot consume the code.
- [ ] Add a concurrency script that refuses non-local Supabase URLs. Read local test URL/key/tokens/code only from environment; print result counts, never values. Use native fetch and assert:

```javascript
import assert from 'node:assert/strict';
const base = process.env.KRYINTALK_LOCAL_SUPABASE_URL;
assert(base && ['localhost','127.0.0.1'].includes(new URL(base).hostname));
const body = JSON.stringify({p_code: process.env.KRYINTALK_TEST_INVITE_CODE});
const tokens = [process.env.KRYINTALK_TEST_TOKEN_A, process.env.KRYINTALK_TEST_TOKEN_B];
assert(tokens.every(Boolean));
const results = await Promise.all(tokens.map(async token => {
  const response = await fetch(`${base}/rest/v1/rpc/redeem_app_access_invite`, {
    method: 'POST', headers: {apikey: process.env.KRYINTALK_LOCAL_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'}, body,
  });
  return response.ok ? response.json() : {ok: false};
}));
assert.equal(results.filter(result => result.ok).length, 1);
console.log('Concurrent single-use redemption: PASS');
```

Use two independently issued sessions for the same recipient in the single-use race; separately test a second account with a different email cannot redeem. Repeat the race for last-superadmin mutations using the same assertion style.
- [ ] Run SQL and local concurrency checks. Deliverable: a verified pending account can gain member access once through an assigned code; no group invite or elevated role is involved.

## Task 4: Auth outcomes, route state, and provider lifecycle

**Files:** Modify auth service/provider, Supabase service, router, API bridge, presence, notifications, browser notification service, AppScaffold, main; extend auth tests and create `account_access_test.dart`.

**Interfaces:** Keep existing `LoginResult`. Define registration types in `auth_service.dart`:

```dart
enum RegistrationOutcome { confirmationRequired, failed }

class RegistrationResult {
  final RegistrationOutcome outcome;
  final String? error;
  const RegistrationResult.confirmationRequired()
      : outcome = RegistrationOutcome.confirmationRequired, error = null;
  const RegistrationResult.failed(this.error)
      : outcome = RegistrationOutcome.failed;
}
```

`AuthService.register(...)` and `AuthNotifier.register(...)` return `Future<RegistrationResult>` with required existing fields plus `required bool agreedToPolicies`. `login(email,password,{required bool agreedToPolicies})` retains its existing service/notifier return type. `refreshProfile()` remains available. `SupabaseService.signUp(...)` returns the SDK `AuthResponse`; send display name, username, agreement and current policy version, never role/org. `SupabaseService.resendSignupConfirmation(String email)` uses signup resend with the configured callback URL. Add `recordConsent(String version)` and `redeemAccessCode(String code)` methods invoking the exact RPCs above.

- [ ] Search all login/register/signIn/signUp callers and all `isAuthenticated` consumers; update every production caller and existing test affected by signature changes. Keep authentication state distinct from authorization.
- [ ] Add failing state checks for pending, approved/current-consent, outdated consent, suspension, missing flags, and malicious cached role. Use this getter contract in AuthState:

```dart
static const currentPolicyVersion = '2026-09-26';
bool get hasAppAccess => isAuthenticated &&
    user?['email_confirmed'] == true && user?['is_active'] == true &&
    user?['is_suspended'] == false && user?['access_status'] == 'approved' &&
    user?['policy_version'] == currentPolicyVersion;
bool get needsPolicyAcceptance => isAuthenticated && user != null &&
    user?['policy_version'] != currentPolicyVersion;
```

Reuse one imported policy constant from auth_service in provider/widgets instead of duplicating the client value. Admin/superadmin getters additionally require `hasAppAccess`; no role fallback grants pending membership.

```dart
test('missing approval cannot be supplied by a cached admin role', () {
  const state = AuthState(isAuthenticated: true, isLoading: false,
      user: {'role':'admin', 'is_super_admin':true});
  expect(state.hasAppAccess, isFalse);
  expect(state.isAdmin, isFalse);
});
test('a valid pending identity is signed in but cannot enter chats', () {
  const state = AuthState(isAuthenticated: true, isLoading: false, user: {
    'email_confirmed':true, 'is_active':true, 'is_suspended':false,
    'access_status':'pending', 'policy_version':'2026-09-26',
  });
  expect(state.isAuthenticated, isTrue);
  expect(state.hasAppAccess, isFalse);
});
```

- [ ] Make signup-without-session a successful confirmation-required result. Remove profile fabrication and cached-role authority. Validate agreement at the service boundary before an SDK login/signup request. Record successful password-login consent server-side before protected routing; if recording fails, keep a valid session restricted and offer retry.
- [ ] Handle Auth sign-in, sign-out, token refresh, and startup/callback events without duplicate profile races. Track a monotonically increasing request epoch/account ID; discard old completions after logout/account switch. Pending login must not write online presence. A missing profile yields restricted setup error/retry; a confirmed identity mismatch signs out locally and shows setup failure.
- [ ] Add one small pure redirect helper in the existing router, `String? accountRedirect(AuthState auth, Uri uri)`, and test route decisions directly. Keep the GoRouter instance stable while auth changes; refresh redirects through a listener rather than constructing a new router and resetting callback/deep-link state on each profile update. Route loading to `/loading` outside the protected shell. Always permit legal/callback paths. Signed-out protected route → `/login`; valid session with missing profile → `/access` setup error; stale consent → `/consent`; pending/restricted → `/access`; approved login/onboarding route → `/dashboard`. Preserve `/join/:token` solely as group landing; pending users cannot join via it. No open redirects from arbitrary query strings.
- [ ] Change protected provider eligibility from `isAuthenticated` to `hasAppAccess`; compare account ID and approval state; stop timers/channels and clear unread/cache items on either change. Authorization denial refreshes status rather than logging out a valid pending session. Prevent a transient loading state from mounting AppScaffold or starting protected providers.
- [ ] Reduce protected `createSignedUrl` lifetime from the current 3600 seconds to 60 seconds. Update chat/file download and media retry handlers to call the existing signer with the stored path on explicit action; no periodic URL refresh loop. Add a regression check proving a stale message URL is replaced on download and a signer failure produces a visible error instead of launching the old URL.
- [ ] Add tests with a delayed profile fetch: logout/switch actor before resolving, then verify stale completion does not repopulate state. Override the existing provider in tests with a fake AuthNotifier; do not introduce a new repository abstraction for testing.
- [ ] Run `D:\flutter\bin\flutter.bat test test/auth_service_test.dart test/account_access_test.dart` from `clients/web`. Deliverable: session, consent, approval, and protected provider lifecycles agree.

## Task 5: Branded forms and policy interactions

**Files:** Create `auth_widgets.dart`; modify signup/login; create `auth_forms_test.dart`.

**Interfaces:** `AuthLayout({required Widget child, required String title, required String subtitle})` provides branding/responsiveness without fetching app data. `showAccountPolicyDialog(BuildContext context,{required bool privacy})` reuses existing legal content. Screen CTAs calculate `canSubmit = valid && agreed && !busy`; handlers recheck the same condition. Give inputs/CTAs stable ValueKeys for tests.

- [ ] Add failing widget cases: empty/invalid form disabled, valid form + unchecked agreement disabled, first/second fresh login unchecked, checked valid form enabled, uncheck returns gray, Enter while unchecked invokes no auth request, repeated Enter while busy invokes one request, modal close never ticks consent.
- [ ] Implement the spec's exact fields, limits, copy, password requirements, normalized handle, visibility toggles, proper autofill, inline errors, and responsive form shell. Use existing theme/font/icon packages. Do not add a component library or change global theme tokens just for these screens.

```dart
final canSubmit = formIsValid && agreedToPolicies && !busy;
FilledButton(
  key: const ValueKey('register-submit'),
  onPressed: canSubmit ? submit : null,
  child: Text(busy ? 'Creating account…' : 'Create account'),
);
// submit() and onFieldSubmitted use the same canSubmit guard.
```

- [ ] Implement accessible policy dialogs: close/Escape, focus trap/restore, scrollable body, separately focusable links, no persistent recognizers created on every build. Reuse existing legal screen content rather than duplicating legal text. Remove inert keep-signed-in UI and misleading username-login label.
- [ ] In widget tests, fill the real fields, inspect button callbacks/disabled semantics, and use a fake provider counting requests. Keep helpers local to the test file. Example assertion after entering valid values but before ticking:

```dart
expect(tester.widget<FilledButton>(find.byKey(
    const ValueKey('register-submit'))).onPressed, isNull);
await tester.testTextInput.receiveAction(TextInputAction.done);
expect(fakeAuth.registerCalls, 0);
```

- [ ] Verify 360px/768px/1440px, dark/light and 200% text scale with `tester.view.physicalSize`/`textScaleFactor` and `takeException() == null`; test scrolling to agreement/CTA on the smallest layout. Restore test view properties at teardown.
- [ ] Run form tests, then view signup/login in the live browser. Do not accept real account policies through computer-use unless action-time consent is provided; widget tests use isolated fake accounts. Deliverable: both forms meet every button/validation/modal contract in spec section 5.

## Task 6: Confirmation, consent, and access dashboard

**Files:** Create confirmation/access screens and preview host; modify router/main/Supabase service and `.env.example`.

**Interfaces:** `CheckEmailScreen({String? email})`, `AuthCallbackScreen()`, `AccessScreen()`, and `AccountConsentScreen()` remain outside AppScaffold. Confirmation callback uses the installed SDK API and current Supabase Flutter version; no manual token decoding. The access screen consumes only the safe profile and onboarding RPCs. Add nonsecret `AUTH_CALLBACK_ORIGIN` and optional `KRYINTALK_ADMIN_CONTACT_EMAIL` environment documentation using the project's existing configuration pattern.

- [ ] Add failing tests for confirmation-required navigation, resend countdown/server rate-limit, refresh without email, callback success/invalid/reused link, consent save failure, approved refresh, invalid invite code, restricted invite disabled, and missing contact email.
- [ ] Implement all copy/buttons/states from spec section 5. Preserve transient email in route extras/current screen state only. Clear passwords when leaving signup. Capture the initial callback path before SDK initialization consumes link parameters, then initialize routing at the callback screen instead of the current default dashboard. Keep existing hash-route links compatible. Callback cleans history tokens and signs out the newly established session locally, not globally; finish with explicit **Sign in**. Consent Continue never starts protected providers before RPC success/profile refresh.
- [ ] Implement pending dashboard code redemption and status refresh. Contact-admin modal copies safe request details on an explicit button click; it never sends email. Retry states preserve input and never show a false success. Focus refresh is debounced; Check status has 10-second cooldown; unsubscribe lifecycle observers on disposal.
- [ ] Add a minimal local preview server with SPA fallback only for app document routes; asset paths must return real 404s. Reject traversal. Use stdlib `http.server`, bind `127.0.0.1`, serve only `clients/web/build/web`, and return `index.html` for `/auth/callback`. Add one stdlib check that callback is served while a missing `.js` asset remains 404.
- [ ] Add nonsecret callback/contact `String.fromEnvironment` values alongside existing SupabaseConfig in `supabase_service.dart`; `.env.example` only documents them and is not automatically read by Flutter. Pass `--dart-define=AUTH_CALLBACK_ORIGIN=http://127.0.0.1:8080` for the local build. Configure exact allowed local callbacks and project password minimum 8; retain confirmation enabled. Production Site URL must be the real deployed app origin, obtained from existing deployment configuration or user at rollout, never guessed. SMTP sender credentials/DNS are a public-release prerequisite; configure secrets only through project settings, never Flutter/env committed files.
- [ ] Build and open the preview, test confirmation delivery with a controlled real mailbox, then open the same link in a second browser context and verify safe recovery. Existing sessions on another device remain valid; no callback can grant approval. If SMTP/deployed origin is unavailable, report that release dependency without claiming email delivery is fixed.

```powershell
# From clients/web
D:\flutter\bin\flutter.bat build web --release --dart-define=AUTH_CALLBACK_ORIGIN=http://127.0.0.1:8080
# From repository root; start hidden if launched in the background.
python scripts/serve_web_preview.py
```

- [ ] Run auth/form checks. Deliverable: create → email → confirm → login → pending dashboard works in the actual preview with correct redirects.

## Task 7: Admin buttons, invitations, and readable audit UI

**Files:** Modify admin users/audit screens and group invite screen; extend form/router tests where needed.

**Interfaces:** Call the exact RPCs from Tasks 2/3 directly through the existing Supabase service/client pattern; no unsupported POST/PUT admin bridge calls. Requests/Members/Invites tabs reuse the current page shell. Server remains the authority even when UI hides a button.

- [ ] Add failing tests for member/admin/superadmin visible actions; verified/unverified Approve disabled state; required decline reason; last-superadmin/self protection errors; expired/revoked invite actions; one-time code dialog; list error vs empty list.
- [ ] Replace password-based Create User controls with the three tabs and spec dialogs. Keep page size 25; reset pagination on search/filter changes. Use server search/scope; loading requests cannot overwrite a newer filter result. Confirm destructive access actions using the exact target name/role; keep action disabled while busy and show server stale-state errors.
- [ ] Implement issue/copy/revoke code actions; reveal raw code only in immediate issue dialog and clear it on close/dispose. Code lists never display hashes or reconstruct links. Admin email input is required; fixed member/single-use/7-day settings are explanatory text, not fake dropdowns.
- [ ] Add access-event filters to existing audit screen and safe detail dialog. Translate action codes to readable labels. List actor/target/timestamp/event ID and safe reason; retain append-only behavior. Read failures are visible, not swallowed as empty logs.
- [ ] Update group-invite UI: a pending/restricted user goes to access dashboard and cannot join; approved user still obeys group membership/invite rules. Do not label group links as signup/app access links.
- [ ] Verify all tabs/dialogs with keyboard, mobile width, empty lists, network error, and a stale target changed by another admin. Deliverable: every presented admin button has a working authorized Supabase operation and audit record.

## Task 8: Review, live rollout, and final regression

**Files:** Existing read-only scripts plus the new verification/tests; no broad repository cleanup.

- [ ] Self-review against every spec button/state and RPC signature. Run SQL tests and concurrency checks in local environment; run the Flutter test suite and analyzer once after the final changes. Compare analyzer baseline rather than masking pre-existing warnings.

```powershell
# From clients/web
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat build web --release
```

- [ ] Prepare exact migration/backup and bootstrap identity report. Bootstrap one correctly matched confirmed fake test account through trusted operator SQL; label/audit it and prove login. Preserve old message ownership. Do not mass-delete/reset accounts to hide identity errors.
- [ ] Present concrete SQL/app changes for any required live review. The previous broad `pending_identity_guard.sql` rejection remains in force; do not re-run it, retrieve privileged service keys, or bypass review. Apply only reviewed, authorized migrations through the existing CLI/management workflow. Never disable security to unblock deployment.
- [ ] Release SQL and compatible app in a controlled window; configure SMTP/callback settings, test real delivery and login. Keep secrets out of console/artifacts. If deployment origin or SMTP credentials are missing, finish the local implementation and clearly identify the remaining external configuration.
- [ ] Verify with separate fake pending/member/admin/superadmin accounts: pending cannot directly request directory/messages/files/notifications; admin approves a verified member; pending refresh becomes approved; invite redemption is one-use and email-bound; member cannot call admin RPC; admin cannot elevate self; superadmin boundary and audit events work.
- [ ] Test live reply navigation to exact message, literal `<h1>` rendering, Markdown/code formatting and .md download/upload. Do not re-run unrelated tests without a new failure/change.
- [ ] Verify sign-out/account switch clears old unread/chat data; approval revocation blocks new operations; document the 60-second signed-URL ceiling. Confirm there is no FastAPI request in the browser network log.
- [ ] Keep the completed preview at `http://127.0.0.1:8080/#/register`, open it in Codex, and report actual verification results plus any SMTP/deployment dependency. Stage/commit only this work's hunks if a commit is requested; preserve the many pre-existing working-tree edits.

## Plan self-review

Spec coverage: personal signup and branding (Task 5); confirmation/password consistency (Tasks 1/6); login/consent (Tasks 4/5/6); pending/status/contact/code dashboard (Task 6); admin/superadmin boundaries and actions (Tasks 2/7); invite security/races (Task 3); database/storage/realtime enforcement (Tasks 1/4); logs (Tasks 1/2/3/7); migration and full preview/regression (Task 8).

The initial release deliberately uses app access codes rather than a new invite-link signup flow. It preserves existing group links, internal chat partition fields, and the single Supabase identity system. Password recovery, OAuth buttons, automated admin emails, and organization setup are not introduced as inactive UI controls.
