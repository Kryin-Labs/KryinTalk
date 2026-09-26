-- KryinTalk's Supabase-only data boundary.
-- Production uses UUID primary keys with legacy text relationship columns.
-- RPCs always derive the actor from auth.uid() and compare those keys safely.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS public.conversation_preferences (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  is_muted boolean NOT NULL DEFAULT false,
  is_archived boolean NOT NULL DEFAULT false,
  notifications_enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS conversation_preferences_user_id_idx
  ON public.conversation_preferences (user_id, is_archived);

-- The production export did not include this table, although the app already
-- exposes friend requests. Keep the relation normalized and let the RPCs own
-- all mutations.
CREATE TABLE IF NOT EXISTS public.friendships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  addressee_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'blocked')),
  blocked_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (requester_id <> addressee_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS friendships_pair_unique_idx
  ON public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

-- Earlier exports omitted fields used by the live notification and reaction
-- records. Make those records compatible before the RPCs below write them.
ALTER TABLE public.notification_items
  ADD COLUMN IF NOT EXISTS resource_type text,
  ADD COLUMN IF NOT EXISTS conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'message_reactions' AND column_name = 'reaction'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'message_reactions' AND column_name = 'emoji'
  ) THEN
    ALTER TABLE public.message_reactions RENAME COLUMN reaction TO emoji;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.same_kryintalk_key(p_left text, p_right text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT p_left IS NOT NULL
    AND p_right IS NOT NULL
    AND lower(replace(p_left, '-', '')) = lower(replace(p_right, '-', ''))
$$;

CREATE OR REPLACE FUNCTION public.current_user_org_id()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT o.id::text
  FROM public.users AS u
  JOIN public.organizations AS o ON public.same_kryintalk_key(o.id::text, u.organization_id)
  WHERE u.id = auth.uid()
    AND u.is_active
    AND NOT u.is_suspended
    AND u.deleted_at IS NULL
    AND o.is_active
    AND o.deleted_at IS NULL
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_org_member(p_org_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT auth.uid() IS NOT NULL
    AND p_org_id IS NOT NULL
    AND public.same_kryintalk_key(public.current_user_org_id()::text, p_org_id)
$$;

CREATE OR REPLACE FUNCTION public.is_org_member(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.is_org_member(p_org_id::text)
$$;

CREATE OR REPLACE FUNCTION public.is_org_admin(p_org_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.user_roles AS ur
      JOIN public.roles AS r ON public.same_kryintalk_key(r.id::text, ur.role_id)
      WHERE public.same_kryintalk_key(ur.user_id, auth.uid()::text)
        AND r.is_active
        AND r.code IN ('super_admin', 'admin', 'manager')
        AND (r.organization_id IS NULL OR public.same_kryintalk_key(r.organization_id, p_org_id))
    )
$$;

CREATE OR REPLACE FUNCTION public.is_org_admin(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.is_org_admin(p_org_id::text)
$$;

CREATE OR REPLACE FUNCTION public.can_access_group(p_group_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.groups AS g
    WHERE public.same_kryintalk_key(g.id::text, p_group_id)
      AND g.deleted_at IS NULL
      AND public.is_org_member(g.organization_id)
      AND (
        NOT g.is_private
        OR public.same_kryintalk_key(g.created_by, auth.uid()::text)
        OR public.is_org_admin(g.organization_id)
        OR EXISTS (
          SELECT 1 FROM public.group_members AS gm
          WHERE public.same_kryintalk_key(gm.group_id, g.id::text)
            AND public.same_kryintalk_key(gm.user_id, auth.uid()::text)
        )
      )
  )
$$;

CREATE OR REPLACE FUNCTION public.can_access_group(p_group_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.can_access_group(p_group_id::text)
$$;

CREATE OR REPLACE FUNCTION public.can_access_conversation(p_conversation_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.conversations AS c
    WHERE public.same_kryintalk_key(c.id::text, p_conversation_id)
      AND public.is_org_member(c.organization_id)
      AND (
        EXISTS (
          SELECT 1 FROM public.conversation_participants AS cp
          WHERE cp.conversation_id = c.id AND cp.user_id = auth.uid()
        )
        OR (c.conversation_type = 'group' AND public.can_access_group(c.target_id))
      )
  )
$$;

CREATE OR REPLACE FUNCTION public.can_access_conversation(p_conversation_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.can_access_conversation(p_conversation_id::text)
$$;

CREATE OR REPLACE FUNCTION public.is_group_moderator(p_group_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.groups AS g
    LEFT JOIN public.group_members AS gm
      ON public.same_kryintalk_key(gm.group_id, g.id::text)
      AND public.same_kryintalk_key(gm.user_id, auth.uid()::text)
    LEFT JOIN public.group_roles AS gr ON public.same_kryintalk_key(gr.id::text, gm.role_id)
    WHERE public.same_kryintalk_key(g.id::text, p_group_id)
      AND (
        public.same_kryintalk_key(g.created_by, auth.uid()::text)
        OR public.is_org_admin(g.organization_id)
        OR lower(coalesce(gr.name, '')) IN ('owner', 'admin', 'moderator')
        OR coalesce(gr.permissions, '') LIKE '%manage_roles%'
      )
  )
$$;

CREATE OR REPLACE FUNCTION public.is_group_moderator(p_group_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.is_group_moderator(p_group_id::text)
$$;

CREATE OR REPLACE FUNCTION public.write_kryintalk_audit(
  p_action text,
  p_resource_type text,
  p_resource_id text,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, p_action, p_resource_type, p_resource_id, p_details);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_direct_conversation(p_recipient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid;
  v_organization_id text;
  v_conversation public.conversations;
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL OR p_recipient_id IS NULL OR p_recipient_id = v_actor THEN
    RAISE EXCEPTION 'A different authenticated recipient is required';
  END IF;

  v_organization_id := public.current_user_org_id();
  IF v_organization_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = p_recipient_id
      AND public.same_kryintalk_key(organization_id, v_organization_id::text)
      AND is_active AND NOT is_suspended AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Recipient is unavailable';
  END IF;

  SELECT c.* INTO v_conversation
  FROM public.conversations AS c
  WHERE public.same_kryintalk_key(c.organization_id, v_organization_id::text)
    AND c.conversation_type = 'direct'
    AND EXISTS (
      SELECT 1 FROM public.conversation_participants AS cp
      WHERE cp.conversation_id = c.id AND cp.user_id = v_actor
    )
    AND EXISTS (
      SELECT 1 FROM public.conversation_participants AS cp
      WHERE cp.conversation_id = c.id AND cp.user_id = p_recipient_id
    )
    AND 2 = (
      SELECT count(*) FROM public.conversation_participants AS cp
      WHERE cp.conversation_id = c.id
    )
  ORDER BY c.created_at
  LIMIT 1;

  IF v_conversation.id IS NULL THEN
    INSERT INTO public.conversations (organization_id, conversation_type)
    VALUES (v_organization_id::text, 'direct')
    RETURNING * INTO v_conversation;

    INSERT INTO public.conversation_participants (conversation_id, user_id)
    VALUES (v_conversation.id, v_actor), (v_conversation.id, p_recipient_id);

    PERFORM public.write_kryintalk_audit(
      'conversation.direct_created', 'conversation', v_conversation.id::text,
      jsonb_build_object('recipient_id', p_recipient_id)
    );
  END IF;

  RETURN to_jsonb(v_conversation);
END;
$$;

CREATE OR REPLACE FUNCTION public.send_conversation_message(
  p_conversation_id uuid,
  p_content text,
  p_message_type text DEFAULT 'text',
  p_parent_id uuid DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid;
  v_message public.messages;
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL OR p_conversation_id IS NULL THEN
    RAISE EXCEPTION 'An authenticated conversation member is required';
  END IF;
  IF coalesce(length(trim(p_content)), 0) = 0 THEN
    RAISE EXCEPTION 'Message content is required';
  END IF;
  IF p_message_type NOT IN ('text', 'file', 'image') THEN
    RAISE EXCEPTION 'Unsupported message type';
  END IF;
  IF NOT public.can_access_conversation(p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation access denied';
  END IF;
  IF p_parent_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE id = p_parent_id AND conversation_id = p_conversation_id AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reply target is unavailable';
  END IF;

  INSERT INTO public.messages (
    conversation_id, sender_id, content, message_type, parent_id, metadata_json
  ) VALUES (
    p_conversation_id, v_actor, trim(p_content), p_message_type, p_parent_id,
    coalesce(p_metadata, '{}'::jsonb)
  ) RETURNING * INTO v_message;

  UPDATE public.conversations SET updated_at = now() WHERE id = p_conversation_id;

  INSERT INTO public.notification_items (user_id, title, body, notification_type, resource_id)
  SELECT cp.user_id, 'New message', left(v_message.content, 255), 'message', v_message.id::text
  FROM public.conversation_participants AS cp
  LEFT JOIN public.conversation_preferences AS pref
    ON pref.conversation_id = cp.conversation_id AND pref.user_id = cp.user_id
  WHERE cp.conversation_id = p_conversation_id
    AND cp.user_id <> v_actor
    AND coalesce(pref.is_muted, false) = false
    AND coalesce(pref.notifications_enabled, true) = true;

  PERFORM public.write_kryintalk_audit(
    'message.sent', 'message', v_message.id::text,
    jsonb_build_object('conversation_id', p_conversation_id, 'message_type', p_message_type)
  );
  RETURN to_jsonb(v_message);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_conversation_read(
  p_conversation_id uuid,
  p_message_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid;
  v_read_at timestamptz := now();
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL OR NOT public.can_access_conversation(p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation access denied';
  END IF;
  IF p_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE id = p_message_id AND conversation_id = p_conversation_id
  ) THEN
    RAISE EXCEPTION 'Message is not in this conversation';
  END IF;

  -- This also supports legacy group conversations with no participant row yet.
  PERFORM 1 FROM public.conversations WHERE id = p_conversation_id FOR UPDATE;
  UPDATE public.conversation_participants
  SET last_read_at = v_read_at, updated_at = v_read_at
  WHERE conversation_id = p_conversation_id AND user_id = v_actor;
  IF NOT FOUND THEN
    INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at)
    VALUES (p_conversation_id, v_actor, v_read_at);
  END IF;

  UPDATE public.notification_items
  SET is_read = true
  WHERE user_id = v_actor
    AND notification_type = 'message'
    AND is_read = false
    AND resource_id IN (
      SELECT id::text FROM public.messages WHERE conversation_id = p_conversation_id
    );

  RETURN jsonb_build_object('conversation_id', p_conversation_id, 'last_read_at', v_read_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_conversation_state()
RETURNS TABLE (
  conversation_id uuid,
  last_read_at timestamptz,
  unread_count bigint,
  is_muted boolean,
  is_archived boolean,
  notifications_enabled boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    c.id,
    cp.last_read_at,
    count(m.id) FILTER (
      WHERE m.sender_id <> auth.uid()
        AND m.deleted_at IS NULL
        AND m.created_at > coalesce(cp.last_read_at, '-infinity'::timestamptz)
    ),
    coalesce(pref.is_muted, false),
    coalesce(pref.is_archived, false),
    coalesce(pref.notifications_enabled, true)
  FROM public.conversations AS c
  JOIN public.conversation_participants AS cp
    ON cp.conversation_id = c.id AND cp.user_id = auth.uid()
  LEFT JOIN public.conversation_preferences AS pref
    ON pref.conversation_id = c.id AND pref.user_id = auth.uid()
  LEFT JOIN public.messages AS m ON m.conversation_id = c.id
  WHERE public.can_access_conversation(c.id)
  GROUP BY c.id, cp.last_read_at, pref.is_muted, pref.is_archived, pref.notifications_enabled
$$;

CREATE OR REPLACE FUNCTION public.request_friendship(p_addressee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid;
  v_friendship public.friendships;
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL OR p_addressee_id IS NULL OR p_addressee_id = v_actor THEN
    RAISE EXCEPTION 'A different authenticated user is required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = p_addressee_id
      AND public.same_kryintalk_key(organization_id, public.current_user_org_id()::text)
      AND is_active AND NOT is_suspended AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'User is unavailable';
  END IF;

  SELECT * INTO v_friendship FROM public.friendships
  WHERE (requester_id = v_actor AND addressee_id = p_addressee_id)
     OR (requester_id = p_addressee_id AND addressee_id = v_actor)
  LIMIT 1;
  IF v_friendship.id IS NOT NULL THEN
    IF v_friendship.status = 'blocked' THEN RAISE EXCEPTION 'Friend request unavailable'; END IF;
    RETURN to_jsonb(v_friendship);
  END IF;

  INSERT INTO public.friendships (requester_id, addressee_id)
  VALUES (v_actor, p_addressee_id)
  RETURNING * INTO v_friendship;
  INSERT INTO public.notification_items (user_id, title, body, notification_type, resource_id)
  VALUES (p_addressee_id, 'Friend request', 'You have a new friend request.', 'friend_request', v_friendship.id::text);
  RETURN to_jsonb(v_friendship);
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_to_friendship(
  p_friendship_id uuid,
  p_accept boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid;
  v_friendship public.friendships;
BEGIN
  v_actor := auth.uid();
  SELECT * INTO v_friendship FROM public.friendships
  WHERE id = p_friendship_id AND addressee_id = v_actor AND status = 'pending'
  FOR UPDATE;
  IF v_friendship.id IS NULL THEN RAISE EXCEPTION 'Friend request is unavailable'; END IF;
  UPDATE public.friendships
  SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'blocked' END,
      blocked_by = CASE WHEN p_accept THEN NULL ELSE v_actor END,
      updated_at = now()
  WHERE id = p_friendship_id
  RETURNING * INTO v_friendship;
  RETURN to_jsonb(v_friendship);
END;
$$;

CREATE OR REPLACE FUNCTION public.kryintalk_preserve_profile_security_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() = old.id AND NOT public.is_org_admin(old.organization_id) THEN
    new.organization_id := old.organization_id;
    new.password_hash := old.password_hash;
    new.is_active := old.is_active;
    new.is_suspended := old.is_suspended;
    new.deleted_at := old.deleted_at;
  END IF;
  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_organization_id uuid;
  v_username text;
  v_member_role_id uuid;
BEGIN
  v_organization_id := nullif(new.raw_user_meta_data ->> 'organization_id', '')::uuid;
  IF v_organization_id IS NULL THEN
    SELECT id INTO v_organization_id FROM public.organizations
    WHERE is_active AND deleted_at IS NULL ORDER BY created_at LIMIT 1;
  END IF;
  IF v_organization_id IS NULL THEN RAISE EXCEPTION 'No active workspace is available'; END IF;

  v_username := lower(trim(coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1))));
  IF v_username !~ '^[a-z0-9_]{3,100}$' THEN RAISE EXCEPTION 'Username must be 3-100 lowercase letters, numbers, or underscores'; END IF;

  INSERT INTO public.users (
    id, organization_id, email, username, display_name, password_hash
  ) VALUES (
    new.id, v_organization_id::text, new.email, v_username,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), v_username),
    'managed-by-supabase-auth'
  ) ON CONFLICT (id) DO UPDATE
  SET email = excluded.email,
      username = excluded.username,
      display_name = excluded.display_name,
      updated_at = now();

  SELECT id INTO v_member_role_id FROM public.roles
  WHERE code IN ('member', 'user') AND is_active
    AND (public.same_kryintalk_key(organization_id, v_organization_id::text) OR organization_id IS NULL)
  ORDER BY organization_id NULLS LAST LIMIT 1;
  IF v_member_role_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE public.same_kryintalk_key(user_id, new.id::text)
      AND public.same_kryintalk_key(role_id, v_member_role_id::text)
  ) THEN
    INSERT INTO public.user_roles (user_id, role_id) VALUES (new.id::text, v_member_role_id::text);
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS kryintalk_preserve_profile_security_fields ON public.users;
CREATE TRIGGER kryintalk_preserve_profile_security_fields
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.kryintalk_preserve_profile_security_fields();
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

DO $$
DECLARE policy_row record;
BEGIN
  FOR policy_row IN
    SELECT policyname, tablename FROM pg_policies
    WHERE schemaname = 'public' AND (policyname LIKE 'kt_%' OR policyname LIKE 'ch_%')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', policy_row.policyname, policy_row.tablename);
  END LOOP;
END;
$$;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY kt_organizations_select ON public.organizations FOR SELECT TO authenticated
  USING (public.is_org_member(id));
CREATE POLICY kt_users_select ON public.users FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_org_member(organization_id));
CREATE POLICY kt_users_update_self ON public.users FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (
    id = auth.uid()
    AND public.same_kryintalk_key(organization_id, public.current_user_org_id()::text)
  );
CREATE POLICY kt_roles_select ON public.roles FOR SELECT TO authenticated
  USING (organization_id IS NULL OR public.is_org_member(organization_id));
CREATE POLICY kt_user_roles_select ON public.user_roles FOR SELECT TO authenticated
  USING (public.same_kryintalk_key(user_id, auth.uid()::text) OR EXISTS (
    SELECT 1 FROM public.roles AS r
    WHERE public.same_kryintalk_key(r.id::text, user_roles.role_id)
      AND public.is_org_admin(r.organization_id)
  ));
CREATE POLICY kt_departments_select ON public.departments FOR SELECT TO authenticated
  USING (public.is_org_member(organization_id));
CREATE POLICY kt_teams_select ON public.teams FOR SELECT TO authenticated
  USING (public.is_org_member(organization_id));
CREATE POLICY kt_groups_select ON public.groups FOR SELECT TO authenticated
  USING (public.can_access_group(id));
CREATE POLICY kt_groups_insert ON public.groups FOR INSERT TO authenticated
  WITH CHECK (
    public.is_org_member(organization_id)
    AND public.same_kryintalk_key(created_by, auth.uid()::text)
  );
CREATE POLICY kt_groups_update ON public.groups FOR UPDATE TO authenticated
  USING (public.is_group_moderator(id)) WITH CHECK (public.is_group_moderator(id));
CREATE POLICY kt_group_roles_select ON public.group_roles FOR SELECT TO authenticated
  USING (public.can_access_group(group_id));
CREATE POLICY kt_group_roles_write ON public.group_roles FOR ALL TO authenticated
  USING (public.is_group_moderator(group_id)) WITH CHECK (public.is_group_moderator(group_id));
CREATE POLICY kt_group_members_select ON public.group_members FOR SELECT TO authenticated
  USING (public.can_access_group(group_id));
CREATE POLICY kt_group_invites_select ON public.group_invites FOR SELECT TO authenticated
  USING (public.is_group_moderator(group_id));
CREATE POLICY kt_channels_select ON public.channels FOR SELECT TO authenticated
  USING (public.is_org_member(organization_id));
CREATE POLICY kt_channel_members_select ON public.channel_members FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.channels AS c
    WHERE public.same_kryintalk_key(c.id::text, channel_members.channel_id)
      AND public.is_org_member(c.organization_id)
  ));
CREATE POLICY kt_conversations_select ON public.conversations FOR SELECT TO authenticated
  USING (public.can_access_conversation(id));
CREATE POLICY kt_conversation_participants_select ON public.conversation_participants FOR SELECT TO authenticated
  USING (public.can_access_conversation(conversation_id));
CREATE POLICY kt_conversation_participants_update ON public.conversation_participants FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY kt_conversation_preferences_self ON public.conversation_preferences FOR ALL TO authenticated
  USING (user_id = auth.uid() AND public.can_access_conversation(conversation_id))
  WITH CHECK (user_id = auth.uid() AND public.can_access_conversation(conversation_id));
CREATE POLICY kt_messages_select ON public.messages FOR SELECT TO authenticated
  USING (public.can_access_conversation(conversation_id));
CREATE POLICY kt_messages_update_own ON public.messages FOR UPDATE TO authenticated
  USING (sender_id = auth.uid()) WITH CHECK (sender_id = auth.uid() AND public.can_access_conversation(conversation_id));
CREATE POLICY kt_messages_delete_own ON public.messages FOR DELETE TO authenticated
  USING (sender_id = auth.uid());
CREATE POLICY kt_reactions_select ON public.message_reactions FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.messages AS m
    WHERE public.same_kryintalk_key(m.id::text, message_reactions.message_id)
      AND public.can_access_conversation(m.conversation_id)
  ));
CREATE POLICY kt_reactions_write ON public.message_reactions FOR ALL TO authenticated
  USING (public.same_kryintalk_key(user_id, auth.uid()::text))
  WITH CHECK (public.same_kryintalk_key(user_id, auth.uid()::text));
CREATE POLICY kt_files_select ON public.file_attachments FOR SELECT TO authenticated
  USING (public.can_access_conversation(conversation_id));
CREATE POLICY kt_friendships_select ON public.friendships FOR SELECT TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());
CREATE POLICY kt_notifications_self ON public.notification_items FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY kt_audit_logs_select ON public.audit_logs FOR SELECT TO authenticated
  USING (public.same_kryintalk_key(user_id, auth.uid()::text)
    OR public.is_org_admin(public.current_user_org_id()));

REVOKE ALL ON FUNCTION public.current_user_org_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.same_kryintalk_key(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_org_member(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_org_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_org_admin(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_org_admin(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_group(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_group(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_conversation(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_conversation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_group_moderator(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_group_moderator(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.write_kryintalk_audit(text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_auth_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.kryintalk_preserve_profile_security_fields() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_direct_conversation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_conversation_message(uuid, text, text, uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_conversation_read(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_conversation_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.request_friendship(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.respond_to_friendship(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_org_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.same_kryintalk_key(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_org_member(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_org_admin(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_org_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_group(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_group(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_conversation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_conversation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_moderator(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_moderator(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_direct_conversation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_conversation_message(uuid, text, text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversation_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_friendship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_to_friendship(uuid, boolean) TO authenticated;

COMMIT;
