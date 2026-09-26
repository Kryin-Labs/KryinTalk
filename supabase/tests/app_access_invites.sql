BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path=public,extensions;
SELECT no_plan();
\ir fixtures/account_access.inc
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT throws_ok($$SELECT public.create_app_access_invite('actor1@example.test')$$,'42501',NULL,'member cannot issue access codes');
SELECT set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
SELECT throws_ok($$SELECT public.create_app_access_invite('invalid')$$,'22023',NULL,'invalid recipient rejected');
SELECT public.create_app_access_invite(' ACTOR2@example.test ') AS wrong \gset
SELECT public.create_app_access_invite('actor1@example.test') AS valid \gset
SELECT public.create_app_access_invite('actor1@example.test') AS spare \gset
SELECT public.create_app_access_invite('actor1@example.test') AS expired \gset
SELECT public.create_app_access_invite('actor1@example.test') AS revoked \gset
SELECT public.create_app_access_invite('actor2@example.test') AS unconfirmed \gset
SELECT ok(NOT (public.list_app_access_invites()->'items'->0 ? 'code_digest'),'invite lists hide digest');
SELECT ok(NOT (public.list_app_access_invites()->'items'->0 ? 'code'),'invite lists hide raw code');
SELECT public.revoke_app_access_invite((:'revoked'::jsonb->>'id')::uuid);
RESET ROLE;
UPDATE public.app_access_invites SET created_at=now()-interval '8 days',expires_at=now()-interval '1 day' WHERE id=(:'expired'::jsonb->>'id')::uuid;
SELECT ok((SELECT octet_length(code_digest)=32 FROM public.app_access_invites WHERE id=(:'valid'::jsonb->>'id')::uuid),'only SHA256 digest persisted');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
SELECT is(public.redeem_app_access_invite(:'unconfirmed'::jsonb->>'code')->>'error_code','invalid_code','unconfirmed cannot redeem');
SELECT set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT throws_ok($$SELECT code_digest FROM public.app_access_invites$$,'42501',NULL,'pending cannot read invite digest');
SELECT throws_ok($$INSERT INTO public.app_access_invites(recipient_email) VALUES('actor1@example.test')$$,'42501',NULL,'pending cannot insert invites');
SELECT is(public.redeem_app_access_invite(:'wrong'::jsonb->>'code')->>'error_code','invalid_code','wrong email denied');
SELECT is(public.redeem_app_access_invite(:'expired'::jsonb->>'code')->>'error_code','invalid_code','expired code denied');
SELECT is(public.redeem_app_access_invite(:'revoked'::jsonb->>'code')->>'error_code','invalid_code','revoked code denied');
SELECT is(public.redeem_app_access_invite('invalid-code')->>'error_code','invalid_code','invalid code denied');
SELECT is(public.redeem_app_access_invite('another-invalid-code')->>'error_code','invalid_code','fifth invalid attempt recorded');
SELECT is(public.redeem_app_access_invite(:'valid'::jsonb->>'code')->>'error_code','rate_limited','server five-attempt limit blocks valid code');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.audit_logs WHERE user_id='a1000000-0000-4000-8000-000000000001' AND action='invite.redeem_failed'),5::bigint,'failed attempts commit audit records');
SELECT ok(NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE details::text LIKE '%'||(:'valid'::jsonb->>'code')||'%'),'raw code absent from audit');
DELETE FROM public.audit_logs WHERE action='invite.redeem_failed';
SELECT set_config('kryintalk.account_write','trusted',true);
UPDATE public.users SET policy_version='old' WHERE id='a1000000-0000-4000-8000-000000000001';
SELECT set_config('kryintalk.account_write','',true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is(public.redeem_app_access_invite(:'valid'::jsonb->>'code')->>'error_code','invalid_code','missing current consent denied');
SELECT public.record_account_consent('2026-09-26');
SELECT is(public.redeem_app_access_invite(:'valid'::jsonb->>'code')->>'ok','true','valid code approves member atomically');
SELECT ok(public.has_app_access(),'member access active after redemption');
SELECT is(public.get_current_user_profile()->>'role','member','invite grants only member');
SELECT is(public.redeem_app_access_invite(:'valid'::jsonb->>'code')->>'error_code','invalid_code','used code never works twice');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.app_access_invites WHERE id=(:'valid'::jsonb->>'id')::uuid AND redeemed_by='a1000000-0000-4000-8000-000000000001'),1::bigint,'one consumption recorded');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE action='invite.redeemed'),1::bigint,'one redemption audited');
SELECT ok(EXISTS(SELECT 1 FROM public.audit_logs WHERE action='access.approved'),'code approval audited');
-- An unused code must not bypass rejection, revocation, suspension, inactivity or identity mismatch.
SELECT set_config('kryintalk.account_write','trusted',true);
UPDATE public.users SET access_status='rejected' WHERE id='a1000000-0000-4000-8000-000000000001';
SELECT set_config('kryintalk.account_write','',true);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT is(public.redeem_app_access_invite(:'spare'::jsonb->>'code')->>'error_code','invalid_code','rejected cannot bypass review');
RESET ROLE;
SELECT set_config('kryintalk.account_write','trusted',true);
UPDATE public.users SET access_status='revoked' WHERE id='a1000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT is(public.redeem_app_access_invite(:'spare'::jsonb->>'code')->>'error_code','invalid_code','revoked cannot bypass review');
RESET ROLE;
UPDATE public.users SET access_status='pending',is_suspended=true WHERE id='a1000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT is(public.redeem_app_access_invite(:'spare'::jsonb->>'code')->>'error_code','invalid_code','suspended cannot bypass review');
RESET ROLE;
UPDATE public.users SET is_suspended=false,is_active=false WHERE id='a1000000-0000-4000-8000-000000000001';
DELETE FROM public.audit_logs WHERE action='invite.redeem_failed';
SET LOCAL ROLE authenticated;
SELECT is(public.redeem_app_access_invite(:'spare'::jsonb->>'code')->>'error_code','invalid_code','inactive cannot bypass review');
RESET ROLE;
SELECT ok((SELECT redeemed_at IS NULL FROM public.app_access_invites WHERE id=(:'spare'::jsonb->>'id')::uuid),'restricted attempts do not consume code');
SELECT * FROM finish();
ROLLBACK;

