-- Review/deploy with the matching Flutter build. Does not remap any identity.
BEGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC,anon,authenticated;
ALTER TABLE public.users
  ADD COLUMN access_status text NOT NULL DEFAULT 'pending' CHECK (access_status IN ('pending','approved','rejected','revoked')),
  ADD COLUMN access_reviewed_at timestamptz,
  ADD COLUMN access_reviewed_by uuid REFERENCES public.users(id),
  ADD COLUMN access_reason text CHECK (length(access_reason)<=500),
  ADD COLUMN policy_version text,
  ADD COLUMN policy_accepted_at timestamptz;
ALTER TABLE public.users ALTER COLUMN role DROP DEFAULT, ALTER COLUMN role DROP NOT NULL;

-- Existing legitimate accounts keep access; consent is required on next load.
UPDATE public.users u SET access_status='approved'
FROM auth.users a WHERE a.id=u.id AND a.email_confirmed_at IS NOT NULL
 AND lower(trim(a.email))=lower(trim(u.email))
 AND u.is_active AND NOT u.is_suspended AND u.deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.has_verified_kryintalk_identity()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.users u JOIN auth.users a ON a.id=u.id
 WHERE a.id=auth.uid() AND a.email_confirmed_at IS NOT NULL
 AND lower(trim(a.email))=lower(trim(u.email)) AND u.deleted_at IS NULL)
$$;
CREATE OR REPLACE FUNCTION public.has_app_access()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.has_verified_kryintalk_identity() AND EXISTS(SELECT 1 FROM public.users u
 JOIN public.organizations o ON public.same_kryintalk_key(o.id::text,u.organization_id)
 WHERE u.id=auth.uid() AND u.is_active AND NOT u.is_suspended AND u.deleted_at IS NULL
 AND u.access_status='approved' AND u.policy_version='2026-09-26'
 AND o.is_active AND o.deleted_at IS NULL)
$$;
CREATE OR REPLACE FUNCTION public.current_user_org_id()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT organization_id FROM public.users WHERE id=auth.uid() AND public.has_app_access()
$$;
CREATE OR REPLACE FUNCTION public.is_org_admin(p_org_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.has_app_access() AND EXISTS(SELECT 1 FROM public.user_roles ur
 JOIN public.roles r ON public.same_kryintalk_key(r.id::text,ur.role_id)
 WHERE public.same_kryintalk_key(ur.user_id,auth.uid()::text) AND r.is_active
 AND (r.code='super_admin' OR (r.code='admin'
 AND public.same_kryintalk_key(public.current_user_org_id(),p_org_id)
 AND (r.organization_id IS NULL OR public.same_kryintalk_key(r.organization_id,p_org_id)))))
$$;

-- Retire legacy column authority and the superadmin private-chat shortcut.
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.has_app_access() AND EXISTS(SELECT 1 FROM public.user_roles ur JOIN public.roles r
 ON public.same_kryintalk_key(r.id::text,ur.role_id) JOIN public.users u ON u.id=auth.uid()
 WHERE public.same_kryintalk_key(ur.user_id,u.id::text) AND r.code='super_admin' AND r.is_active
 AND (r.organization_id IS NULL OR public.same_kryintalk_key(r.organization_id,u.organization_id)))
$$;
CREATE OR REPLACE FUNCTION public.can_access_conversation_text(p_conversation_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.can_access_conversation(p_conversation_id)
$$;

-- Own onboarding data is a whitelisted RPC, never an exception to table RLS.
CREATE OR REPLACE FUNCTION public.get_current_user_profile()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 WITH codes AS (SELECT DISTINCT r.code FROM public.user_roles ur JOIN public.roles r
 ON public.same_kryintalk_key(r.id::text,ur.role_id) JOIN public.users u ON u.id=auth.uid()
 WHERE public.same_kryintalk_key(ur.user_id,u.id::text) AND r.is_active
 AND u.access_status='approved' AND (r.organization_id IS NULL OR public.same_kryintalk_key(r.organization_id,u.organization_id)))
 SELECT jsonb_build_object('id',u.id,'email',u.email,'username',u.username,'display_name',u.display_name,
 'avatar_url',u.avatar_url,'hide_from_dm',u.hide_from_dm,'organization_id',u.organization_id,
 'is_active',u.is_active,'is_suspended',u.is_suspended,'access_status',u.access_status,
 'access_reason',CASE WHEN u.access_status='rejected' THEN u.access_reason END,
 'policy_version',u.policy_version,'policy_accepted_at',u.policy_accepted_at,'email_confirmed',a.email_confirmed_at IS NOT NULL,
 'role',(SELECT code FROM codes ORDER BY CASE code WHEN 'super_admin' THEN 0 WHEN 'admin' THEN 1 WHEN 'manager' THEN 2 ELSE 3 END LIMIT 1),
 'roles',coalesce((SELECT jsonb_agg(code ORDER BY code) FROM codes),'[]'::jsonb),
 'app_access',public.has_app_access(),'is_super_admin',EXISTS(SELECT 1 FROM codes WHERE code='super_admin'))
 FROM public.users u JOIN auth.users a ON a.id=u.id
 WHERE u.id=auth.uid() AND a.email_confirmed_at IS NOT NULL AND lower(trim(a.email))=lower(trim(u.email)) AND u.deleted_at IS NULL
$$;

-- Column grants prevent client security writes; retain both legacy triggers.
-- Trigger current_user is its owner, so do not use it to identify direct writes.
CREATE OR REPLACE FUNCTION public.kryintalk_preserve_profile_security_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF current_setting('kryintalk.account_write',true) IS DISTINCT FROM 'trusted' THEN
  new.organization_id:=old.organization_id; new.password_hash:=old.password_hash;
  new.role:=old.role; new.is_active:=old.is_active; new.is_suspended:=old.is_suspended;
  new.deleted_at:=old.deleted_at; new.access_status:=old.access_status;
  new.access_reviewed_at:=old.access_reviewed_at; new.access_reviewed_by:=old.access_reviewed_by;
  new.access_reason:=old.access_reason; new.policy_version:=old.policy_version;
  new.policy_accepted_at:=old.policy_accepted_at;
 END IF;
 RETURN new;
END $$;
CREATE OR REPLACE FUNCTION public.protect_user_security_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF current_setting('kryintalk.account_write',true) IS DISTINCT FROM 'trusted' THEN
  new.organization_id:=old.organization_id; new.password_hash:=old.password_hash;
  new.role:=old.role; new.is_active:=old.is_active; new.is_suspended:=old.is_suspended; new.deleted_at:=old.deleted_at;
 END IF;
 RETURN new;
END $$;
CREATE OR REPLACE FUNCTION public.record_account_consent(p_version text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF p_version IS DISTINCT FROM '2026-09-26' OR NOT public.has_verified_kryintalk_identity() THEN
  RAISE EXCEPTION 'Confirmed account and current policy are required' USING ERRCODE='42501';
 END IF;
 PERFORM set_config('kryintalk.account_write','trusted',true);
 UPDATE public.users SET policy_version=p_version,policy_accepted_at=now(),updated_at=now() WHERE id=auth.uid();
 PERFORM set_config('kryintalk.account_write','',true);
 PERFORM public.write_kryintalk_audit('account.consent_recorded','user',auth.uid()::text,jsonb_build_object('policy_version',p_version));
 RETURN public.get_current_user_profile();
END $$;
CREATE OR REPLACE FUNCTION public.is_signup_username_available(p_username text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT lower(trim(p_username)) ~ '^[a-z0-9_]{3,100}$'
 AND NOT EXISTS(SELECT 1 FROM public.users WHERE lower(username)=lower(trim(p_username)))
$$;
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_org uuid; v_username text; v_name text; v_consent boolean;
BEGIN
 SELECT id INTO v_org FROM public.organizations WHERE is_active AND deleted_at IS NULL ORDER BY created_at,id LIMIT 1;
 IF v_org IS NULL THEN RAISE EXCEPTION 'Account provisioning unavailable'; END IF;
 v_username:=lower(trim(regexp_replace(coalesce(new.raw_user_meta_data->>'username',''),'^@','')));
 v_name:=trim(coalesce(new.raw_user_meta_data->>'display_name',''));
 IF v_username !~ '^[a-z0-9_]{3,100}$' OR length(v_name) NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'Invalid account profile' USING ERRCODE='22023';
 END IF;
 v_consent:=new.raw_user_meta_data->>'agreement'='true' AND new.raw_user_meta_data->>'policy_version'='2026-09-26';
 INSERT INTO public.users(id,organization_id,email,username,display_name,password_hash,role,is_active,is_suspended,
 access_status,policy_version,policy_accepted_at,presence_status,created_at,updated_at)
 VALUES(new.id,v_org::text,new.email,v_username,v_name,'managed-by-supabase-auth',NULL,true,false,'pending',
 CASE WHEN v_consent THEN '2026-09-26' END,CASE WHEN v_consent THEN now() END,'offline',now(),now());
 INSERT INTO public.audit_logs(user_id,action,resource_type,resource_id,details)
 VALUES(new.id::text,'account.pending_created','user',new.id::text,jsonb_build_object('outcome','pending'));
 IF v_consent THEN
  INSERT INTO public.audit_logs(user_id,action,resource_type,resource_id,details)
  VALUES(new.id::text,'account.consent_recorded','user',new.id::text,jsonb_build_object('policy_version','2026-09-26','source','signup'));
 END IF;
 RETURN new;
END $$;

REVOKE INSERT,UPDATE,DELETE ON public.users FROM anon,authenticated;
-- Remove any pre-existing column grants as well as the table-level grant.
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT column_name,table_name FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('users','roles','user_roles','audit_logs') LOOP
  EXECUTE format('REVOKE INSERT (%I), UPDATE (%I) ON public.%I FROM anon,authenticated',c.column_name,c.column_name,c.table_name);
 END LOOP;
END $$;
GRANT UPDATE(display_name,username,avatar_url,hide_from_dm,presence_status,presence_text,last_active_at,last_login_at,settings,updated_at) ON public.users TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.roles,public.user_roles,public.audit_logs FROM anon,authenticated;

-- Restrictive policies AND with existing row/membership policies. No private
-- conversation grants are widened; all direct self-policy bypasses are closed.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['organizations','users','roles','user_roles','groups','group_roles','group_members','group_invites',
 'group_user_invitations','conversations','conversation_participants','conversation_preferences','messages','message_reactions',
 'file_attachments','friendships','notification_items','audit_logs'] LOOP
  EXECUTE format('REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.%I FROM anon,authenticated',t);
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY kt_account_access ON public.%I AS RESTRICTIVE FOR ALL TO public USING (public.has_app_access()) WITH CHECK (public.has_app_access())',t);
 END LOOP;
END $$;
CREATE POLICY kt_account_access ON storage.objects AS RESTRICTIVE FOR ALL TO public
 USING(public.has_app_access()) WITH CHECK(public.has_app_access());
UPDATE storage.buckets SET public=false WHERE id='attachments';

-- Exact legacy RPC inventory: preserve the existing implementations/row checks
-- in an unexposed schema; add the approval predicate at every public entry point.
CREATE SCHEMA IF NOT EXISTS kryintalk_private;
REVOKE ALL ON SCHEMA kryintalk_private FROM PUBLIC,anon,authenticated;
DO $$ DECLARE f record; v_args text; v_call text; BEGIN
 FOR f IN SELECT p.*,pg_get_function_arguments(p.oid) args,pg_get_function_result(p.oid) result,
 pg_get_function_identity_arguments(p.oid) identity_args
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
 AND p.proname=ANY(ARRAY['is_super_admin','can_access_file','can_access_conversation_text',
 'is_group_moderator','kryintalk_can_message_action','create_direct_conversation','send_conversation_message',
 'mark_conversation_read','get_conversation_state','request_friendship','respond_to_friendship','remove_friendship','block_user',
 'create_kryintalk_group','list_kryintalk_groups','update_kryintalk_group','kryintalk_group_summary',
 'get_kryintalk_group_roles','create_kryintalk_group_role','update_kryintalk_group_role','delete_kryintalk_group_role',
 'get_kryintalk_group_members','add_kryintalk_group_members','assign_kryintalk_group_member_role','remove_kryintalk_group_member',
 'find_or_create_kryintalk_group_conversation','delete_kryintalk_group','create_kryintalk_group_invite',
 'accept_kryintalk_group_invite','invite_kryintalk_group_user','respond_kryintalk_group_invitation','update_kryintalk_profile']) LOOP
  SELECT coalesce(string_agg(quote_ident(x),',' ORDER BY ord),'') INTO v_args
  FROM unnest(f.proargnames) WITH ORDINALITY names(x,ord) WHERE ord<=f.pronargs;
  -- Copy, rather than move: existing policies must keep their public function OIDs.
  EXECUTE replace(pg_get_functiondef(f.oid),format('FUNCTION public.%I(',f.proname),format('FUNCTION kryintalk_private.%I(',f.proname));
  EXECUTE format('REVOKE ALL ON FUNCTION kryintalk_private.%I(%s) FROM PUBLIC,anon,authenticated',f.proname,f.identity_args);
  v_call:=CASE WHEN f.proretset THEN format('RETURN QUERY SELECT * FROM kryintalk_private.%I(%s); RETURN;',f.proname,v_args)
    WHEN f.prorettype='void'::regtype THEN format('PERFORM kryintalk_private.%I(%s); RETURN;',f.proname,v_args)
    ELSE format('RETURN kryintalk_private.%I(%s);',f.proname,v_args) END;
  EXECUTE format('CREATE OR REPLACE FUNCTION public.%I(%s) RETURNS %s LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $gate$ BEGIN IF NOT public.has_app_access() THEN %s END IF; %s END $gate$',f.proname,f.args,f.result,
    CASE WHEN f.prorettype='boolean'::regtype THEN 'RETURN false;' ELSE 'RAISE EXCEPTION ''App access required'' USING ERRCODE=''42501'';' END,v_call);
  EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC,anon',f.proname,f.identity_args);
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated',f.proname,f.identity_args);
 END LOOP;
END $$;

-- Group landing links expose no directory, membership counts, or inviter identity.
DO $$ BEGIN
 EXECUTE replace(pg_get_functiondef('public.get_kryintalk_group_invite(text)'::regprocedure),
 'FUNCTION public.get_kryintalk_group_invite(', 'FUNCTION kryintalk_private.get_kryintalk_group_invite(');
END $$;
REVOKE ALL ON FUNCTION kryintalk_private.get_kryintalk_group_invite(text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.get_kryintalk_group_invite(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF public.has_app_access() THEN RETURN kryintalk_private.get_kryintalk_group_invite(p_token); END IF;
 RETURN jsonb_build_object('group_name','KryinTalk group','is_expired',NOT EXISTS(SELECT 1 FROM public.group_invites
 WHERE token=p_token AND NOT coalesce(is_revoked,'false')::boolean AND expires_at>now() AND uses_count<max_uses));
END $$;
REVOKE ALL ON FUNCTION public.get_kryintalk_group_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_kryintalk_group_invite(text) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.handle_new_auth_user(),public.protect_user_security_fields(),
 public.kryintalk_preserve_profile_security_fields(),public.write_kryintalk_audit(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
-- Channels were retired; this legacy function references a dropped table.
REVOKE ALL ON FUNCTION public.can_access_channel(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.has_app_access(),public.has_verified_kryintalk_identity(),public.record_account_consent(text),
 public.get_current_user_profile(),public.is_signup_username_available(text) FROM PUBLIC,anon;
-- anon can evaluate the restrictive policy as false, and check a scalar handle.
GRANT EXECUTE ON FUNCTION public.has_app_access(),public.has_verified_kryintalk_identity(),public.is_signup_username_available(text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_user_profile(),public.record_account_consent(text) TO authenticated;
COMMIT;
