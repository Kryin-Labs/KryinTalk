BEGIN;
CREATE TABLE public.app_access_invites(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code_digest bytea NOT NULL UNIQUE CHECK(octet_length(code_digest)=32),
 recipient_email text NOT NULL CHECK(recipient_email=lower(trim(recipient_email)) AND length(recipient_email)<=254),
 organization_id text NOT NULL,
 created_by uuid NOT NULL REFERENCES public.users(id),created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '7 days' CHECK(expires_at>created_at),
 redeemed_by uuid REFERENCES public.users(id),redeemed_at timestamptz,revoked_at timestamptz,
 CHECK((redeemed_by IS NULL)=(redeemed_at IS NULL))
);
CREATE INDEX ON public.app_access_invites(recipient_email,expires_at);
CREATE INDEX ON public.audit_logs(user_id,created_at) WHERE action='invite.redeem_failed';
ALTER TABLE public.app_access_invites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_access_invites FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.create_app_access_invite(p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE v_email text:=lower(trim(p_email)); v_code text; v_invite public.app_access_invites;
BEGIN
 PERFORM kryintalk_private.require_account_admin();
 IF v_email IS NULL OR length(v_email)>254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
  RAISE EXCEPTION 'A valid recipient email is required' USING ERRCODE='22023'; END IF;
 v_code:=encode(gen_random_bytes(24),'hex');
 INSERT INTO public.app_access_invites(code_digest,recipient_email,organization_id,created_by)
 VALUES(digest(v_code,'sha256'),v_email,public.current_user_org_id(),auth.uid()) RETURNING * INTO v_invite;
 PERFORM public.write_kryintalk_audit('invite.created','app_access_invite',v_invite.id::text,jsonb_build_object('expires_at',v_invite.expires_at,'role','member'));
 RETURN jsonb_build_object('id',v_invite.id,'code',v_code,'expires_at',v_invite.expires_at);
END $$;
CREATE FUNCTION public.list_app_access_invites(p_limit int DEFAULT 25,p_offset int DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM kryintalk_private.require_account_admin();
 IF p_limit IS NULL OR p_offset IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_offset<0 THEN
  RAISE EXCEPTION 'Invalid pagination' USING ERRCODE='22023'; END IF;
 RETURN (WITH scoped AS(SELECT id,recipient_email,created_by,created_at,expires_at,redeemed_at,revoked_at
 FROM public.app_access_invites WHERE public.same_kryintalk_key(organization_id,public.current_user_org_id())
 OR 'super_admin'=ANY(kryintalk_private.account_roles(auth.uid()))),
 page AS(SELECT * FROM scoped ORDER BY created_at DESC,id LIMIT p_limit OFFSET p_offset)
 SELECT jsonb_build_object('items',coalesce((SELECT jsonb_agg(to_jsonb(page) ORDER BY created_at DESC,id) FROM page),'[]'::jsonb),
 'total',(SELECT count(*) FROM scoped)));
END $$;
CREATE FUNCTION public.revoke_app_access_invite(p_invite_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_invite public.app_access_invites;
BEGIN
 PERFORM kryintalk_private.require_account_admin();
 SELECT * INTO v_invite FROM public.app_access_invites WHERE id=p_invite_id FOR UPDATE;
 IF NOT FOUND OR NOT(public.same_kryintalk_key(v_invite.organization_id,public.current_user_org_id())
 OR 'super_admin'=ANY(kryintalk_private.account_roles(auth.uid()))) THEN
  RAISE EXCEPTION 'Invite unavailable' USING ERRCODE='42501'; END IF;
 IF v_invite.redeemed_at IS NOT NULL OR v_invite.revoked_at IS NOT NULL OR v_invite.expires_at<=now() THEN
  RAISE EXCEPTION 'Invite state changed; refresh' USING ERRCODE='22023'; END IF;
 UPDATE public.app_access_invites SET revoked_at=now() WHERE id=p_invite_id;
 PERFORM public.write_kryintalk_audit('invite.revoked','app_access_invite',p_invite_id::text);
 RETURN jsonb_build_object('id',p_invite_id,'revoked_at',now());
END $$;
CREATE FUNCTION public.redeem_app_access_invite(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE v_invite public.app_access_invites; v_user public.users; v_code text:=trim(p_code);
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 -- Serialize attempts per account, then lock invite -> profile consistently.
 PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text,26122026));
 IF (SELECT count(*) FROM public.audit_logs WHERE action='invite.redeem_failed'
 AND user_id=auth.uid()::text AND created_at>now()-interval '15 minutes')>=5 THEN
  RETURN jsonb_build_object('ok',false,'error_code','rate_limited'); END IF;
 IF v_code IS NOT NULL AND length(v_code) BETWEEN 1 AND 128 THEN
  SELECT * INTO v_invite FROM public.app_access_invites WHERE code_digest=digest(v_code,'sha256') FOR UPDATE;
 END IF;
 SELECT * INTO v_user FROM public.users WHERE id=auth.uid() FOR UPDATE;
 IF v_invite.id IS NULL OR v_invite.redeemed_at IS NOT NULL OR v_invite.revoked_at IS NOT NULL
 OR v_invite.expires_at<=now() OR v_user.id IS NULL OR v_user.access_status<>'pending'
 OR NOT v_user.is_active OR v_user.is_suspended OR v_user.deleted_at IS NOT NULL
 OR v_user.policy_version IS DISTINCT FROM '2026-09-26' OR NOT public.has_verified_kryintalk_identity()
 OR lower(trim(v_user.email))<>v_invite.recipient_email
 OR NOT public.same_kryintalk_key(v_user.organization_id,v_invite.organization_id) THEN
  PERFORM public.write_kryintalk_audit('invite.redeem_failed','user',auth.uid()::text,jsonb_build_object('outcome','invalid'));
  RETURN jsonb_build_object('ok',false,'error_code','invalid_code'); END IF;
 PERFORM kryintalk_private.assign_account_role(auth.uid(),'member');
 PERFORM set_config('kryintalk.account_write','trusted',true);
 UPDATE public.users SET access_status='approved',role='member',access_reviewed_at=now(),
 access_reviewed_by=v_invite.created_by,access_reason=NULL,updated_at=now() WHERE id=auth.uid();
 PERFORM set_config('kryintalk.account_write','',true);
 UPDATE public.app_access_invites SET redeemed_at=now(),redeemed_by=auth.uid() WHERE id=v_invite.id;
 PERFORM public.write_kryintalk_audit('access.approved','user',auth.uid()::text,jsonb_build_object('source','invite','invite_id',v_invite.id));
 PERFORM public.write_kryintalk_audit('invite.redeemed','app_access_invite',v_invite.id::text,jsonb_build_object('outcome','approved'));
 RETURN jsonb_build_object('ok',true,'profile',public.get_current_user_profile());
END $$;
REVOKE ALL ON FUNCTION public.create_app_access_invite(text),public.list_app_access_invites(int,int),
 public.revoke_app_access_invite(uuid),public.redeem_app_access_invite(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_app_access_invite(text),public.list_app_access_invites(int,int),
 public.revoke_app_access_invite(uuid),public.redeem_app_access_invite(text) TO authenticated;
COMMIT;
