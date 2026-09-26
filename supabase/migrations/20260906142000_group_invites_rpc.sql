-- Expiring group-link invites and direct, notification-backed group invitations.

CREATE TABLE IF NOT EXISTS public.group_user_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invited_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  invited_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role_id uuid REFERENCES public.group_roles(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, invited_user_id)
);

ALTER TABLE public.group_user_invitations ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.kryintalk_require_group_inviter(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_group public.groups%ROWTYPE; v_actor jsonb := public.kryintalk_group_actor(p_group_id);
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'add_members');
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Group not found.' USING ERRCODE = 'P0002'; END IF;
  IF coalesce(v_group.only_admin_invites, 'true')::boolean
    AND NOT coalesce((v_actor ->> 'is_owner')::boolean, false)
    AND coalesce((v_actor ->> 'rank')::bigint, 10000) > 10 THEN
    RAISE EXCEPTION 'Only group owners and administrators can create invites.' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_kryintalk_group_invite(
  p_group_id uuid,
  p_expires_hours integer DEFAULT 24,
  p_max_uses integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_invite public.group_invites%ROWTYPE; v_group public.groups%ROWTYPE; v_creator public.users%ROWTYPE;
BEGIN
  IF p_expires_hours NOT BETWEEN 1 AND 720 OR p_max_uses NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'Invite expiry must be 1–720 hours and use limit must be 1–10,000.' USING ERRCODE = '22023';
  END IF;
  PERFORM public.kryintalk_require_group_inviter(p_group_id);
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id;
  INSERT INTO public.group_invites (group_id, token, created_by, max_uses, uses_count, expires_at, is_revoked)
  VALUES (p_group_id::text, replace(gen_random_uuid()::text, '-', ''), auth.uid()::text, p_max_uses, 0,
    now() + make_interval(hours => p_expires_hours), 'false')
  RETURNING * INTO v_invite;
  SELECT * INTO v_creator FROM public.users WHERE id = auth.uid();
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, 'group.invite.created', 'group_invite', v_invite.id::text,
    jsonb_build_object('group_id', p_group_id, 'max_uses', p_max_uses, 'expires_hours', p_expires_hours));
  RETURN jsonb_build_object(
    'id', v_invite.id, 'group_id', p_group_id, 'group_name', v_group.name,
    'token', v_invite.token, 'created_by', auth.uid(),
    'created_by_name', coalesce(v_creator.display_name, v_creator.username),
    'created_by_username', v_creator.username,
    'max_uses', v_invite.max_uses, 'uses_count', v_invite.uses_count,
    'expires_at', v_invite.expires_at, 'created_at', v_invite.created_at,
    'is_expired', false, 'is_used', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_kryintalk_group_invite(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_invite public.group_invites%ROWTYPE; v_group public.groups%ROWTYPE; v_creator public.users%ROWTYPE;
BEGIN
  SELECT * INTO v_invite FROM public.group_invites WHERE token = p_token;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invite link is invalid.' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_group FROM public.groups WHERE id::text = v_invite.group_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invite link is invalid.' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_creator FROM public.users WHERE id::text = v_invite.created_by;
  RETURN jsonb_build_object(
    'id', v_invite.id, 'group_id', v_group.id, 'group_name', v_group.name,
    'group_description', v_group.description, 'group_icon', v_group.icon,
    'token', v_invite.token, 'created_by', v_invite.created_by,
    'created_by_name', coalesce(v_creator.display_name, v_creator.username, 'A group member'),
    'created_by_username', v_creator.username,
    'max_uses', v_invite.max_uses, 'uses_count', v_invite.uses_count,
    'expires_at', v_invite.expires_at, 'created_at', v_invite.created_at,
    'member_count', (SELECT count(*) FROM public.group_members WHERE group_id = v_group.id::text),
    'is_expired', coalesce(v_invite.is_revoked, 'false')::boolean OR v_invite.expires_at <= now() OR v_invite.uses_count >= v_invite.max_uses,
    'is_used', v_invite.uses_count >= v_invite.max_uses
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_kryintalk_group_invite(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_invite public.group_invites%ROWTYPE; v_group public.groups%ROWTYPE;
  v_role_id uuid; v_conversation_id uuid; v_was_member boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_invite FROM public.group_invites WHERE token = p_token FOR UPDATE;
  IF NOT FOUND OR coalesce(v_invite.is_revoked, 'false')::boolean OR v_invite.expires_at <= now() OR v_invite.uses_count >= v_invite.max_uses THEN
    RAISE EXCEPTION 'This invite link has expired or reached its use limit.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_group FROM public.groups WHERE id::text = v_invite.group_id AND deleted_at IS NULL;
  IF NOT FOUND OR v_group.organization_id IS DISTINCT FROM public.current_user_org_id() THEN
    RAISE EXCEPTION 'You cannot join this group.' USING ERRCODE = '42501';
  END IF;
  SELECT EXISTS(SELECT 1 FROM public.group_members WHERE group_id = v_group.id::text AND user_id = auth.uid()::text) INTO v_was_member;
  IF NOT v_was_member THEN
    SELECT id INTO v_role_id FROM public.group_roles WHERE group_id = v_group.id::text AND coalesce(is_default, 'false')::boolean LIMIT 1;
    INSERT INTO public.group_members (group_id, user_id, role_id, added_by)
    VALUES (v_group.id::text, auth.uid()::text, v_role_id::text, v_invite.created_by)
    ON CONFLICT (group_id, user_id) DO NOTHING;
    UPDATE public.group_invites SET uses_count = uses_count + 1, updated_at = now()
    WHERE id = v_invite.id AND uses_count < max_uses;
  END IF;
  SELECT id INTO v_conversation_id FROM public.conversations
  WHERE organization_id = v_group.organization_id AND conversation_type = 'group' AND target_id = v_group.id::text LIMIT 1;
  IF v_conversation_id IS NULL THEN
    INSERT INTO public.conversations (organization_id, conversation_type, target_id)
    VALUES (v_group.organization_id, 'group', v_group.id::text) RETURNING id INTO v_conversation_id;
  END IF;
  INSERT INTO public.conversation_participants (conversation_id, user_id)
  VALUES (v_conversation_id, auth.uid()) ON CONFLICT (conversation_id, user_id) DO NOTHING;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, 'group.invite.accepted', 'group', v_group.id::text, jsonb_build_object('invite_id', v_invite.id));
  RETURN jsonb_build_object('message', CASE WHEN v_was_member THEN 'You are already a member of this group.' ELSE 'You joined the group.' END,
    'group_id', v_group.id, 'group_name', v_group.name, 'conversation_id', v_conversation_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.invite_kryintalk_group_user(
  p_group_id uuid, p_user_id uuid, p_role_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group public.groups%ROWTYPE; v_role_id uuid := p_role_id; v_role_rank bigint;
  v_invitation public.group_user_invitations%ROWTYPE; v_inviter public.users%ROWTYPE;
BEGIN
  PERFORM public.kryintalk_require_group_inviter(p_group_id);
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id AND organization_id = v_group.organization_id AND deleted_at IS NULL AND is_active) THEN RAISE EXCEPTION 'User not found in this organization.' USING ERRCODE = 'P0002'; END IF;
  IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id = p_group_id::text AND user_id = p_user_id::text) THEN RAISE EXCEPTION 'This user is already a group member.' USING ERRCODE = '23505'; END IF;
  IF v_role_id IS NULL THEN SELECT id INTO v_role_id FROM public.group_roles WHERE group_id = p_group_id::text AND coalesce(is_default, 'false')::boolean LIMIT 1; ELSE SELECT hierarchy_rank INTO v_role_rank FROM public.group_roles WHERE id = v_role_id AND group_id = p_group_id::text; IF v_role_rank IS NULL THEN RAISE EXCEPTION 'Role not found.' USING ERRCODE = 'P0002'; END IF; END IF;
  INSERT INTO public.group_user_invitations (group_id, invited_user_id, invited_by, role_id, status)
  VALUES (p_group_id, p_user_id, auth.uid(), v_role_id, 'pending')
  ON CONFLICT (group_id, invited_user_id) DO UPDATE SET invited_by = EXCLUDED.invited_by, role_id = EXCLUDED.role_id, status = 'pending', updated_at = now()
  RETURNING * INTO v_invitation;
  SELECT * INTO v_inviter FROM public.users WHERE id = auth.uid();
  INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read)
  VALUES (p_user_id, 'invitation', 'Group Invitation: ' || v_group.name,
    coalesce(v_inviter.display_name, v_inviter.username, 'A group member') || ' invited you to join ' || v_group.name || '.',
    'group_invite', p_group_id::text, NULL, false);
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, 'group.member.invited', 'group', p_group_id::text, jsonb_build_object('user_id', p_user_id, 'role_id', v_role_id));
  RETURN jsonb_build_object('message', 'Invitation sent.', 'invitation_id', v_invitation.id, 'group_id', p_group_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_kryintalk_group_invitation(
  p_group_id uuid, p_action text, p_notification_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_invitation public.group_user_invitations%ROWTYPE; v_group public.groups%ROWTYPE; v_role_id uuid; v_conversation_id uuid;
BEGIN
  IF p_action NOT IN ('accept', 'reject') THEN RAISE EXCEPTION 'Invitation action is invalid.' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_invitation FROM public.group_user_invitations WHERE group_id = p_group_id AND invited_user_id = auth.uid() AND status = 'pending' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitation not found.' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Group not found.' USING ERRCODE = 'P0002'; END IF;
  IF p_action = 'reject' THEN
    UPDATE public.group_user_invitations SET status = 'rejected', updated_at = now() WHERE id = v_invitation.id;
    IF p_notification_id IS NOT NULL THEN UPDATE public.notification_items SET is_read = true, updated_at = now() WHERE id = p_notification_id AND user_id = auth.uid(); END IF;
    RETURN jsonb_build_object('message', 'Invitation declined.', 'group_id', p_group_id);
  END IF;
  v_role_id := coalesce(v_invitation.role_id, (SELECT id FROM public.group_roles WHERE group_id = p_group_id::text AND coalesce(is_default, 'false')::boolean LIMIT 1));
  INSERT INTO public.group_members (group_id, user_id, role_id, added_by)
  VALUES (p_group_id::text, auth.uid()::text, v_role_id::text, v_invitation.invited_by::text)
  ON CONFLICT (group_id, user_id) DO NOTHING;
  UPDATE public.group_user_invitations SET status = 'accepted', updated_at = now() WHERE id = v_invitation.id;
  SELECT id INTO v_conversation_id FROM public.conversations WHERE organization_id = v_group.organization_id AND conversation_type = 'group' AND target_id = p_group_id::text LIMIT 1;
  IF v_conversation_id IS NULL THEN INSERT INTO public.conversations (organization_id, conversation_type, target_id) VALUES (v_group.organization_id, 'group', p_group_id::text) RETURNING id INTO v_conversation_id; END IF;
  INSERT INTO public.conversation_participants (conversation_id, user_id) VALUES (v_conversation_id, auth.uid()) ON CONFLICT (conversation_id, user_id) DO NOTHING;
  IF p_notification_id IS NOT NULL THEN UPDATE public.notification_items SET is_read = true, updated_at = now() WHERE id = p_notification_id AND user_id = auth.uid(); END IF;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details) VALUES (auth.uid()::text, 'group.invitation.accepted', 'group', p_group_id::text, jsonb_build_object('invitation_id', v_invitation.id));
  RETURN jsonb_build_object('message', 'You joined the group.', 'group_id', p_group_id, 'group_name', v_group.name, 'conversation_id', v_conversation_id);
END;
$$;

REVOKE ALL ON FUNCTION public.kryintalk_require_group_inviter(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_kryintalk_group_invite(uuid, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_kryintalk_group_invite(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_kryintalk_group_invite(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.invite_kryintalk_group_user(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.respond_kryintalk_group_invitation(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_kryintalk_group_invite(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_kryintalk_group_invite(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_kryintalk_group_invite(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.invite_kryintalk_group_user(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_kryintalk_group_invitation(uuid, text, uuid) TO authenticated;
