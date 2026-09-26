BEGIN;
CREATE OR REPLACE FUNCTION kryintalk_private.account_roles(p_id uuid)
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT coalesce(array_agg(DISTINCT r.code),'{}'::text[]) FROM public.user_roles ur
 JOIN public.roles r ON public.same_kryintalk_key(r.id::text,ur.role_id)
 JOIN public.users u ON u.id=p_id WHERE public.same_kryintalk_key(ur.user_id,p_id::text)
 AND r.is_active AND (r.organization_id IS NULL OR public.same_kryintalk_key(r.organization_id,u.organization_id))
$$;
CREATE OR REPLACE FUNCTION kryintalk_private.require_account_admin(p_target uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_actor public.users; v_target public.users; v_super boolean;
BEGIN
 SELECT * INTO v_actor FROM public.users WHERE id=auth.uid();
 v_super:='super_admin'=ANY(kryintalk_private.account_roles(auth.uid()));
 IF NOT public.has_app_access() OR NOT (v_super OR 'admin'=ANY(kryintalk_private.account_roles(auth.uid()))) THEN
  RAISE EXCEPTION 'Administrator access required' USING ERRCODE='42501';
 END IF;
 IF p_target IS NOT NULL THEN
  SELECT * INTO v_target FROM public.users WHERE id=p_target AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Account unavailable' USING ERRCODE='P0002'; END IF;
  IF p_target=auth.uid() OR (NOT v_super AND
   (NOT public.same_kryintalk_key(v_actor.organization_id,v_target.organization_id)
    OR kryintalk_private.account_roles(p_target) && ARRAY['admin','super_admin','manager'])) THEN
   RAISE EXCEPTION 'You cannot manage this account' USING ERRCODE='42501';
  END IF;
 END IF;
END $$;
CREATE OR REPLACE FUNCTION kryintalk_private.safe_account(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT jsonb_build_object('id',u.id,'display_name',u.display_name,'username',u.username,'email',u.email,
 'created_at',u.created_at,'email_confirmed',a.email_confirmed_at IS NOT NULL AND lower(trim(a.email))=lower(trim(u.email)),
 'access_status',u.access_status,'is_active',u.is_active,'is_suspended',u.is_suspended,
 'access_reason',u.access_reason,'access_reviewed_at',u.access_reviewed_at,'access_reviewed_by',u.access_reviewed_by,
 'roles',to_jsonb(kryintalk_private.account_roles(u.id)),
 'role',CASE WHEN 'super_admin'=ANY(kryintalk_private.account_roles(u.id)) THEN 'super_admin'
 WHEN 'admin'=ANY(kryintalk_private.account_roles(u.id)) THEN 'admin'
 WHEN 'manager'=ANY(kryintalk_private.account_roles(u.id)) THEN 'manager'
 WHEN u.access_status='approved' THEN 'member' END)
 FROM public.users u LEFT JOIN auth.users a ON a.id=u.id WHERE u.id=p_id
$$;
CREATE OR REPLACE FUNCTION kryintalk_private.assign_account_role(p_id uuid,p_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_role uuid; v_org text;
BEGIN
 SELECT organization_id INTO v_org FROM public.users WHERE id=p_id;
 SELECT id INTO v_role FROM public.roles WHERE code=p_role AND is_active
 AND (organization_id IS NULL OR public.same_kryintalk_key(organization_id,v_org))
 ORDER BY organization_id NULLS LAST,id LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Account role unavailable'; END IF;
 DELETE FROM public.user_roles WHERE public.same_kryintalk_key(user_id,p_id::text);
 INSERT INTO public.user_roles(user_id,role_id,granted_by,created_at)
 VALUES(p_id::text,v_role::text,auth.uid()::text,now());
END $$;
CREATE OR REPLACE FUNCTION kryintalk_private.protect_last_superadmin(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF 'super_admin'=ANY(kryintalk_private.account_roles(p_id)) AND NOT EXISTS(
 SELECT 1 FROM public.users u JOIN auth.users a ON a.id=u.id WHERE u.id<>p_id
 AND u.is_active AND NOT u.is_suspended AND u.deleted_at IS NULL AND u.access_status='approved'
 AND a.email_confirmed_at IS NOT NULL AND lower(trim(a.email))=lower(trim(u.email))
 AND 'super_admin'=ANY(kryintalk_private.account_roles(u.id))) THEN
  RAISE EXCEPTION 'The last active superadmin must be preserved' USING ERRCODE='42501';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.list_app_accounts(p_status text DEFAULT 'pending',p_search text DEFAULT '',p_limit int DEFAULT 25,p_offset int DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_result jsonb;
BEGIN
 PERFORM kryintalk_private.require_account_admin();
 IF p_limit IS NULL OR p_offset IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_offset<0 OR length(p_search)>100
 OR p_status IS NULL OR p_status NOT IN ('pending','rejected','approved','suspended','revoked','all') THEN
  RAISE EXCEPTION 'Invalid account filter' USING ERRCODE='22023';
 END IF;
 WITH filtered AS (SELECT u.id,u.created_at FROM public.users u WHERE u.deleted_at IS NULL
 AND ('super_admin'=ANY(kryintalk_private.account_roles(auth.uid())) OR public.same_kryintalk_key(u.organization_id,public.current_user_org_id()))
 AND (p_status='all' OR (p_status='suspended' AND u.is_suspended) OR (u.access_status=p_status AND NOT u.is_suspended))
 AND (p_search='' OR strpos(lower(u.email||' '||u.username||' '||u.display_name),lower(p_search))>0)),
 page AS (SELECT * FROM filtered ORDER BY created_at DESC NULLS LAST,id LIMIT p_limit OFFSET p_offset)
 SELECT jsonb_build_object('items',coalesce((SELECT jsonb_agg(kryintalk_private.safe_account(id) ORDER BY created_at DESC NULLS LAST,id) FROM page),'[]'::jsonb),
 'total',(SELECT count(*) FROM filtered)) INTO v_result;
 RETURN v_result;
END $$;
CREATE OR REPLACE FUNCTION public.get_app_account_review(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM kryintalk_private.require_account_admin();
 IF NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=p_user_id AND u.deleted_at IS NULL
 AND ('super_admin'=ANY(kryintalk_private.account_roles(auth.uid())) OR public.same_kryintalk_key(u.organization_id,public.current_user_org_id()))) THEN
  RAISE EXCEPTION 'Account unavailable' USING ERRCODE='42501'; END IF;
 RETURN kryintalk_private.safe_account(p_user_id)||jsonb_build_object('history',coalesce((SELECT jsonb_agg(to_jsonb(e)) FROM
 (SELECT id,action,created_at,user_id,details FROM public.audit_logs WHERE resource_id=p_user_id::text
 AND (action LIKE 'access.%' OR action LIKE 'role.%' OR action LIKE 'account.%') ORDER BY created_at DESC LIMIT 50) e),'[]'::jsonb));
END $$;
CREATE OR REPLACE FUNCTION public.review_app_access(p_user_id uuid,p_action text,p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_user public.users; v_old jsonb; v_event text; v_reason text:=nullif(trim(p_reason),'');
BEGIN
 -- ponytail: serialize admin mutations; per-target locks if admin throughput matters.
 PERFORM pg_advisory_xact_lock(26120926);
 SELECT * INTO v_user FROM public.users WHERE id=p_user_id FOR UPDATE;
 PERFORM kryintalk_private.require_account_admin(p_user_id);
 IF p_action IS NULL OR p_action NOT IN ('approve','decline','reopen','suspend','restore','revoke')
 OR (p_action IN ('decline','reopen','suspend','revoke') AND v_reason IS NULL) OR length(v_reason)>500 THEN
  RAISE EXCEPTION 'Provide a reason of 1–500 characters' USING ERRCODE='22023';
 END IF;
 v_old:=kryintalk_private.safe_account(p_user_id);
 IF p_action IN ('suspend','revoke') THEN PERFORM kryintalk_private.protect_last_superadmin(p_user_id); END IF;
 IF p_action='approve' THEN
  IF v_user.access_status<>'pending' OR v_user.is_suspended OR NOT v_user.is_active OR NOT EXISTS(
   SELECT 1 FROM auth.users a WHERE a.id=p_user_id AND a.email_confirmed_at IS NOT NULL
   AND lower(trim(a.email))=lower(trim(v_user.email))) THEN
   RAISE EXCEPTION 'Only a verified pending account can be approved' USING ERRCODE='22023';
  END IF;
  PERFORM kryintalk_private.assign_account_role(p_user_id,'member'); v_event:='access.approved';
 ELSIF p_action='decline' AND v_user.access_status='pending' THEN v_event:='access.declined';
 ELSIF p_action='reopen' AND v_user.access_status IN ('rejected','revoked') AND NOT v_user.is_suspended THEN v_event:='access.reopened';
 ELSIF p_action='suspend' AND v_user.access_status='approved' AND NOT v_user.is_suspended THEN v_event:='access.suspended';
 ELSIF p_action='restore' AND v_user.access_status='approved' AND v_user.is_suspended AND v_user.is_active THEN v_event:='access.restored';
 ELSIF p_action='revoke' AND v_user.access_status IN ('pending','approved','rejected') THEN v_event:='access.revoked';
 ELSE RAISE EXCEPTION 'Account state changed; refresh and review again' USING ERRCODE='22023'; END IF;
 IF p_action IN ('revoke','decline','reopen') THEN DELETE FROM public.user_roles WHERE public.same_kryintalk_key(user_id,p_user_id::text); END IF;
 PERFORM set_config('kryintalk.account_write','trusted',true);
 UPDATE public.users SET access_status=CASE p_action WHEN 'approve' THEN 'approved' WHEN 'decline' THEN 'rejected'
 WHEN 'reopen' THEN 'pending' WHEN 'revoke' THEN 'revoked' ELSE access_status END,
 is_suspended=CASE p_action WHEN 'suspend' THEN true WHEN 'restore' THEN false ELSE is_suspended END,
 role=CASE WHEN p_action='approve' THEN 'member' WHEN p_action IN ('revoke','decline','reopen') THEN NULL ELSE role END,
 access_reviewed_at=now(),access_reviewed_by=auth.uid(),access_reason=v_reason,updated_at=now()
 WHERE id=p_user_id;
 PERFORM set_config('kryintalk.account_write','',true);
 PERFORM public.write_kryintalk_audit(v_event,'user',p_user_id::text,jsonb_build_object('old',v_old->'access_status',
 'new',(SELECT access_status FROM public.users WHERE id=p_user_id),'reason',v_reason,'action',p_action));
 RETURN kryintalk_private.safe_account(p_user_id);
END $$;
CREATE OR REPLACE FUNCTION public.set_app_account_role(p_user_id uuid,p_role text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_user public.users; v_old text[];
BEGIN
 PERFORM pg_advisory_xact_lock(26120926);
 SELECT * INTO v_user FROM public.users WHERE id=p_user_id FOR UPDATE;
 PERFORM kryintalk_private.require_account_admin(p_user_id);
 IF NOT ('super_admin'=ANY(kryintalk_private.account_roles(auth.uid()))) THEN
  RAISE EXCEPTION 'Only superadmin can change application roles' USING ERRCODE='42501'; END IF;
 IF p_role IS NULL OR p_role NOT IN ('member','admin') OR v_user.access_status<>'approved' OR v_user.is_suspended
 OR NOT v_user.is_active OR NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=p_user_id
 AND a.email_confirmed_at IS NOT NULL AND lower(trim(a.email))=lower(trim(v_user.email))) THEN
  RAISE EXCEPTION 'An approved verified account and member/admin role are required' USING ERRCODE='22023'; END IF;
 PERFORM kryintalk_private.protect_last_superadmin(p_user_id);
 v_old:=kryintalk_private.account_roles(p_user_id);
 PERFORM kryintalk_private.assign_account_role(p_user_id,p_role);
 PERFORM set_config('kryintalk.account_write','trusted',true);
 UPDATE public.users SET role=p_role,updated_at=now() WHERE id=p_user_id;
 PERFORM set_config('kryintalk.account_write','',true);
 PERFORM public.write_kryintalk_audit('role.changed','user',p_user_id::text,jsonb_build_object('old',v_old,'new',p_role));
 RETURN kryintalk_private.safe_account(p_user_id);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA kryintalk_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.list_app_accounts(text,text,int,int),public.get_app_account_review(uuid),
 public.review_app_access(uuid,text,text),public.set_app_account_role(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_app_accounts(text,text,int,int),public.get_app_account_review(uuid),
 public.review_app_access(uuid,text,text),public.set_app_account_role(uuid,text) TO authenticated;
COMMIT;
