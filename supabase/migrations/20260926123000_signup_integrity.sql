BEGIN;
-- Ensure every active internal partition has the two assignable roles.
-- Creating definitions does not grant an account any role or access.
INSERT INTO public.roles(organization_id,code,name,is_active,created_at)
SELECT o.id::text,c.code,c.name,true,now() FROM public.organizations o
CROSS JOIN (VALUES ('member','Member'),('admin','Admin')) c(code,name)
WHERE o.is_active AND o.deleted_at IS NULL AND NOT EXISTS(
 SELECT 1 FROM public.roles r WHERE r.code=c.code AND r.is_active
 AND (r.organization_id IS NULL OR public.same_kryintalk_key(r.organization_id,o.id::text)));
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
 -- ponytail: serialize only equal normalized usernames, preserving legacy accounts.
 PERFORM pg_advisory_xact_lock(hashtextextended(v_username,26123026));
 IF EXISTS(SELECT 1 FROM public.users WHERE lower(username)=v_username) THEN
  RAISE EXCEPTION 'Username unavailable' USING ERRCODE='23505'; END IF;
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

COMMIT;
