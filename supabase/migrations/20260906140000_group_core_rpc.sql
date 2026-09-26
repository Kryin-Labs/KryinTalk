-- Supabase-only group lifecycle, role, membership, and message permission boundary.
-- The deployed schema has legacy text foreign keys; all public RPC arguments stay UUID.

CREATE OR REPLACE FUNCTION public.kryintalk_group_default_permissions(p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_all text[] := ARRAY[
    'view_messages','send_messages','edit_own_messages','edit_other_messages',
    'delete_own_messages','delete_other_messages','reply_messages','add_reactions',
    'remove_reactions','pin_messages','unpin_messages','send_links','send_attachments',
    'send_images','send_files','view_members','add_members','remove_members',
    'manage_members','view_member_profiles','view_roles','create_roles','edit_roles',
    'delete_roles','assign_roles','manage_role_hierarchy','manage_role_permissions',
    'view_group','edit_group_name','edit_group_description','change_group_icon',
    'change_group_visibility','manage_group_settings','delete_group','mention_users'
  ];
  v_enabled text[];
  v_result jsonb := '{}'::jsonb;
BEGIN
  IF p_kind IN ('owner', 'admin') THEN
    v_enabled := v_all;
  ELSIF p_kind = 'member' THEN
    v_enabled := ARRAY[
      'view_messages','send_messages','edit_own_messages','delete_own_messages',
      'reply_messages','add_reactions','remove_reactions','send_links','send_attachments',
      'send_images','send_files','view_members','view_member_profiles','view_roles',
      'view_group','mention_users'
    ];
  ELSE
    v_enabled := ARRAY['view_messages','view_members','view_member_profiles','view_roles','view_group'];
  END IF;

  SELECT jsonb_object_agg(permission, permission = ANY(v_enabled))
  INTO v_result
  FROM unnest(v_all) AS permission;
  RETURN coalesce(v_result, '{}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.kryintalk_group_actor(
  p_group_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group public.groups%ROWTYPE;
  v_role public.group_roles%ROWTYPE;
  v_is_owner boolean := false;
BEGIN
  SELECT * INTO v_group
  FROM public.groups
  WHERE id = p_group_id AND deleted_at IS NULL;
  IF NOT FOUND OR v_group.organization_id IS DISTINCT FROM public.current_user_org_id() THEN
    RETURN '{}'::jsonb;
  END IF;

  v_is_owner := v_group.created_by = p_user_id::text
    OR public.is_org_admin(v_group.organization_id);

  SELECT gr.* INTO v_role
  FROM public.group_members gm
  JOIN public.group_roles gr ON gr.id::text = gm.role_id
  WHERE gm.group_id = p_group_id::text AND gm.user_id = p_user_id::text
  LIMIT 1;

  RETURN jsonb_build_object(
    'exists', true,
    'is_owner', v_is_owner,
    'is_member', FOUND,
    'rank', CASE WHEN v_is_owner THEN 0 WHEN FOUND THEN v_role.hierarchy_rank ELSE 10000 END,
    'permissions', CASE
      WHEN v_is_owner THEN public.kryintalk_group_default_permissions('owner')
      WHEN FOUND THEN coalesce(nullif(v_role.permissions, '')::jsonb, '{}'::jsonb)
      ELSE '{}'::jsonb
    END,
    'visibility', v_group.visibility,
    'is_private', v_group.is_private
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.kryintalk_has_group_permission(
  p_group_id uuid,
  p_permission text,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor jsonb := public.kryintalk_group_actor(p_group_id, p_user_id);
BEGIN
  IF coalesce((v_actor ->> 'is_owner')::boolean, false) THEN
    RETURN true;
  END IF;
  IF coalesce((v_actor -> 'permissions' ->> p_permission)::boolean, false) THEN
    RETURN true;
  END IF;
  RETURN p_permission IN ('view_group', 'view_messages', 'view_members', 'view_roles')
    AND v_actor ->> 'visibility' = 'organization'
    AND NOT coalesce((v_actor ->> 'is_private')::boolean, true);
END;
$$;

CREATE OR REPLACE FUNCTION public.kryintalk_require_group_permission(
  p_group_id uuid,
  p_permission text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.kryintalk_has_group_permission(p_group_id, p_permission) THEN
    RAISE EXCEPTION 'You do not have permission to % in this group.', replace(p_permission, '_', ' ')
      USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.kryintalk_group_role_json(p_role public.group_roles)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'id', p_role.id,
    'group_id', p_role.group_id,
    'name', p_role.name,
    'color', p_role.color,
    'description', p_role.description,
    'hierarchy_rank', p_role.hierarchy_rank,
    'is_system', p_role.is_system,
    'is_default', coalesce(p_role.is_default, 'false')::boolean,
    'permissions', coalesce(nullif(p_role.permissions, '')::jsonb, '{}'::jsonb),
    'member_count', (SELECT count(*) FROM public.group_members WHERE role_id = p_role.id::text),
    'created_at', p_role.created_at
  );
$$;

CREATE OR REPLACE FUNCTION public.kryintalk_group_summary(p_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group public.groups%ROWTYPE;
  v_actor jsonb;
  v_role public.group_roles%ROWTYPE;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'view_group');
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  v_actor := public.kryintalk_group_actor(p_group_id);
  SELECT gr.* INTO v_role
  FROM public.group_members gm JOIN public.group_roles gr ON gr.id::text = gm.role_id
  WHERE gm.group_id = p_group_id::text AND gm.user_id = auth.uid()::text
  LIMIT 1;

  RETURN jsonb_build_object(
    'id', v_group.id,
    'organization_id', v_group.organization_id,
    'name', v_group.name,
    'slug', v_group.slug,
    'description', v_group.description,
    'icon', v_group.icon,
    'color', v_group.color,
    'visibility', v_group.visibility,
    'is_active', v_group.is_active,
    'is_private', v_group.is_private,
    'only_admin_invites', coalesce(v_group.only_admin_invites, 'true')::boolean,
    'created_by', v_group.created_by,
    'member_count', (SELECT count(*) FROM public.group_members WHERE group_id = p_group_id::text),
    'current_user_role', CASE WHEN FOUND THEN public.kryintalk_group_role_json(v_role) ELSE NULL END,
    'current_user_permissions', v_actor -> 'permissions',
    'created_at', v_group.created_at,
    'updated_at', v_group.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_kryintalk_groups()
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group public.groups%ROWTYPE;
BEGIN
  FOR v_group IN
    SELECT * FROM public.groups
    WHERE deleted_at IS NULL
      AND organization_id = public.current_user_org_id()
      AND public.kryintalk_has_group_permission(id, 'view_group')
    ORDER BY updated_at DESC
  LOOP
    RETURN NEXT public.kryintalk_group_summary(v_group.id);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_kryintalk_group(
  p_name text,
  p_slug text,
  p_description text DEFAULT NULL,
  p_icon text DEFAULT NULL,
  p_color text DEFAULT NULL,
  p_visibility text DEFAULT 'private',
  p_is_view_only boolean DEFAULT false,
  p_only_admin_invites boolean DEFAULT true,
  p_member_ids uuid[] DEFAULT ARRAY[]::uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id text := public.current_user_org_id();
  v_group_id uuid;
  v_owner_role uuid;
  v_member_role uuid;
  v_viewer_role uuid;
  v_default_role uuid;
  v_conversation_id uuid;
BEGIN
  IF auth.uid() IS NULL OR v_org_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
  END IF;
  IF length(trim(coalesce(p_name, ''))) NOT BETWEEN 1 AND 255
    OR trim(coalesce(p_slug, '')) !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'Group name or slug is invalid.' USING ERRCODE = '22023';
  END IF;
  IF p_visibility NOT IN ('private', 'organization') THEN
    RAISE EXCEPTION 'Group visibility is invalid.' USING ERRCODE = '22023';
  END IF;
  IF NOT public.is_org_admin(v_org_id) AND (
    SELECT count(*) FROM public.groups
    WHERE organization_id = v_org_id AND created_by = auth.uid()::text AND deleted_at IS NULL
  ) >= 2 THEN
    RAISE EXCEPTION 'You are limited to a maximum of 2 groups.' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(coalesce(p_member_ids, ARRAY[]::uuid[])) AS member_id
    WHERE NOT EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id::text = member_id::text AND u.organization_id = v_org_id
        AND u.deleted_at IS NULL AND u.is_active
    )
  ) THEN
    RAISE EXCEPTION 'Every initial member must belong to your organization.' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.groups (
    organization_id, name, slug, description, icon, color, visibility, is_active,
    is_private, only_admin_invites, created_by
  ) VALUES (
    v_org_id, trim(p_name), trim(p_slug), nullif(trim(p_description), ''),
    nullif(trim(p_icon), ''), nullif(trim(p_color), ''), p_visibility, true,
    p_visibility = 'private', p_only_admin_invites::text, auth.uid()::text
  ) RETURNING id INTO v_group_id;

  INSERT INTO public.group_roles (group_id, name, color, description, hierarchy_rank, is_system, is_default, permissions)
  VALUES (v_group_id::text, 'Group Owner', '#F59E0B', 'Permanent group owner with absolute management authority', 0, true, 'false', public.kryintalk_group_default_permissions('owner')::text)
  RETURNING id INTO v_owner_role;
  INSERT INTO public.group_roles (group_id, name, color, description, hierarchy_rank, is_system, is_default, permissions)
  VALUES (v_group_id::text, 'Group Admin', '#8B5CF6', 'Group administrator with management authority', 10, true, 'false', public.kryintalk_group_default_permissions('admin')::text);
  INSERT INTO public.group_roles (group_id, name, color, description, hierarchy_rank, is_system, is_default, permissions)
  VALUES (v_group_id::text, 'Group Member', '#64748B', 'Standard group member', 100, true, (NOT p_is_view_only)::text, public.kryintalk_group_default_permissions('member')::text)
  RETURNING id INTO v_member_role;
  INSERT INTO public.group_roles (group_id, name, color, description, hierarchy_rank, is_system, is_default, permissions)
  VALUES (v_group_id::text, 'Group Viewer', '#94A3B8', 'View-only participant with no posting or management rights', 200, true, p_is_view_only::text, public.kryintalk_group_default_permissions('viewer')::text)
  RETURNING id INTO v_viewer_role;
  v_default_role := CASE WHEN p_is_view_only THEN v_viewer_role ELSE v_member_role END;

  INSERT INTO public.group_members (group_id, user_id, role_id, added_by)
  VALUES (v_group_id::text, auth.uid()::text, v_owner_role::text, auth.uid()::text)
  ON CONFLICT (group_id, user_id) DO NOTHING;
  INSERT INTO public.group_members (group_id, user_id, role_id, added_by)
  SELECT v_group_id::text, member_id::text, v_default_role::text, auth.uid()::text
  FROM unnest(coalesce(p_member_ids, ARRAY[]::uuid[])) AS member_id
  WHERE member_id <> auth.uid()
  ON CONFLICT (group_id, user_id) DO NOTHING;

  SELECT id INTO v_conversation_id
  FROM public.conversations
  WHERE organization_id = v_org_id AND conversation_type = 'group' AND target_id = v_group_id::text
  LIMIT 1;
  IF v_conversation_id IS NULL THEN
    INSERT INTO public.conversations (organization_id, conversation_type, target_id)
    VALUES (v_org_id, 'group', v_group_id::text)
    RETURNING id INTO v_conversation_id;
  END IF;
  INSERT INTO public.conversation_participants (conversation_id, user_id)
  SELECT v_conversation_id, gm.user_id::uuid
  FROM public.group_members gm WHERE gm.group_id = v_group_id::text
  ON CONFLICT (conversation_id, user_id) DO NOTHING;

  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, 'group.created', 'group', v_group_id::text,
    jsonb_build_object('name', trim(p_name), 'slug', trim(p_slug), 'initial_members', cardinality(coalesce(p_member_ids, ARRAY[]::uuid[]))));
  RETURN public.kryintalk_group_summary(v_group_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_kryintalk_group(p_group_id uuid, p_changes jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_visibility text := coalesce(p_changes ->> 'visibility', NULL);
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'manage_group_settings');
  IF v_visibility IS NOT NULL AND v_visibility NOT IN ('private', 'organization') THEN
    RAISE EXCEPTION 'Group visibility is invalid.' USING ERRCODE = '22023';
  END IF;
  IF p_changes ? 'name' AND length(trim(coalesce(p_changes ->> 'name', ''))) NOT BETWEEN 1 AND 255 THEN
    RAISE EXCEPTION 'Group name is invalid.' USING ERRCODE = '22023';
  END IF;
  UPDATE public.groups SET
    name = CASE WHEN p_changes ? 'name' THEN trim(p_changes ->> 'name') ELSE name END,
    description = CASE WHEN p_changes ? 'description' THEN nullif(trim(p_changes ->> 'description'), '') ELSE description END,
    icon = CASE WHEN p_changes ? 'icon' THEN nullif(trim(p_changes ->> 'icon'), '') ELSE icon END,
    color = CASE WHEN p_changes ? 'color' THEN nullif(trim(p_changes ->> 'color'), '') ELSE color END,
    visibility = coalesce(v_visibility, visibility),
    is_private = CASE WHEN v_visibility IS NOT NULL THEN v_visibility = 'private' WHEN p_changes ? 'is_private' THEN coalesce((p_changes ->> 'is_private')::boolean, is_private) ELSE is_private END,
    is_active = CASE WHEN p_changes ? 'is_active' THEN coalesce((p_changes ->> 'is_active')::boolean, is_active) ELSE is_active END,
    only_admin_invites = CASE WHEN p_changes ? 'only_admin_invites' THEN coalesce((p_changes ->> 'only_admin_invites')::boolean, true)::text ELSE only_admin_invites END,
    updated_at = now()
  WHERE id = p_group_id AND deleted_at IS NULL;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, 'group.updated', 'group', p_group_id::text, p_changes);
  RETURN public.kryintalk_group_summary(p_group_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_kryintalk_group_roles(p_group_id uuid)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_role public.group_roles%ROWTYPE;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'view_roles');
  FOR v_role IN SELECT * FROM public.group_roles WHERE group_id = p_group_id::text ORDER BY hierarchy_rank, created_at LOOP
    RETURN NEXT public.kryintalk_group_role_json(v_role);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_kryintalk_group_role(
  p_group_id uuid, p_name text, p_color text DEFAULT '#64748B',
  p_description text DEFAULT NULL, p_permissions jsonb DEFAULT NULL, p_is_default boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor jsonb := public.kryintalk_group_actor(p_group_id);
  v_permissions jsonb := coalesce(p_permissions, public.kryintalk_group_default_permissions('member'));
  v_role public.group_roles%ROWTYPE;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'create_roles');
  IF length(trim(coalesce(p_name, ''))) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Role name is invalid.' USING ERRCODE = '22023'; END IF;
  IF EXISTS (SELECT 1 FROM public.group_roles WHERE group_id = p_group_id::text AND lower(name) = lower(trim(p_name))) THEN RAISE EXCEPTION 'A role with that name already exists.' USING ERRCODE = '23505'; END IF;
  IF NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND EXISTS (
    SELECT 1 FROM jsonb_each_text(v_permissions) AS permission(key, value)
    WHERE value = 'true' AND NOT coalesce((v_actor -> 'permissions' ->> key)::boolean, false)
  ) THEN RAISE EXCEPTION 'A role cannot grant a permission you do not have.' USING ERRCODE = '42501'; END IF;
  IF p_is_default THEN UPDATE public.group_roles SET is_default = 'false' WHERE group_id = p_group_id::text; END IF;
  INSERT INTO public.group_roles (group_id, name, color, description, hierarchy_rank, is_system, is_default, permissions)
  VALUES (p_group_id::text, trim(p_name), coalesce(nullif(trim(p_color), ''), '#64748B'), nullif(trim(p_description), ''),
    greatest(coalesce((v_actor ->> 'rank')::bigint, 0) + 10, coalesce((SELECT max(hierarchy_rank) + 1 FROM public.group_roles WHERE group_id = p_group_id::text), 20)),
    false, p_is_default::text, v_permissions::text)
  RETURNING * INTO v_role;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details) VALUES (auth.uid()::text, 'group.role.created', 'group_role', v_role.id::text, jsonb_build_object('group_id', p_group_id, 'name', v_role.name));
  RETURN public.kryintalk_group_role_json(v_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_kryintalk_group_role(p_group_id uuid, p_role_id uuid, p_changes jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor jsonb := public.kryintalk_group_actor(p_group_id);
  v_role public.group_roles%ROWTYPE;
  v_permissions jsonb;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'edit_roles');
  SELECT * INTO v_role FROM public.group_roles WHERE id = p_role_id AND group_id = p_group_id::text;
  IF NOT FOUND THEN RAISE EXCEPTION 'Role not found.' USING ERRCODE = 'P0002'; END IF;
  IF (v_role.is_system OR v_role.hierarchy_rank = 0) AND NOT coalesce((v_actor ->> 'is_owner')::boolean, false) THEN RAISE EXCEPTION 'Built-in roles are protected.' USING ERRCODE = '42501'; END IF;
  IF NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND v_role.hierarchy_rank <= coalesce((v_actor ->> 'rank')::bigint, 10000) THEN RAISE EXCEPTION 'You cannot edit an equal or higher role.' USING ERRCODE = '42501'; END IF;
  v_permissions := CASE WHEN p_changes ? 'permissions' THEN p_changes -> 'permissions' ELSE coalesce(nullif(v_role.permissions, '')::jsonb, '{}'::jsonb) END;
  IF NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND EXISTS (
    SELECT 1 FROM jsonb_each_text(v_permissions) AS permission(key, value)
    WHERE value = 'true' AND NOT coalesce((v_actor -> 'permissions' ->> key)::boolean, false)
  ) THEN RAISE EXCEPTION 'A role cannot grant a permission you do not have.' USING ERRCODE = '42501'; END IF;
  IF coalesce((p_changes ->> 'is_default')::boolean, false) THEN UPDATE public.group_roles SET is_default = 'false' WHERE group_id = p_group_id::text AND id <> p_role_id; END IF;
  UPDATE public.group_roles SET
    name = CASE WHEN p_changes ? 'name' THEN trim(p_changes ->> 'name') ELSE name END,
    color = CASE WHEN p_changes ? 'color' THEN nullif(trim(p_changes ->> 'color'), '') ELSE color END,
    description = CASE WHEN p_changes ? 'description' THEN nullif(trim(p_changes ->> 'description'), '') ELSE description END,
    is_default = CASE WHEN p_changes ? 'is_default' AND hierarchy_rank <> 0 THEN (p_changes ->> 'is_default') ELSE is_default END,
    permissions = v_permissions::text,
    updated_at = now()
  WHERE id = p_role_id
  RETURNING * INTO v_role;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details) VALUES (auth.uid()::text, 'group.role.updated', 'group_role', p_role_id::text, p_changes);
  RETURN public.kryintalk_group_role_json(v_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_kryintalk_group_role(p_group_id uuid, p_role_id uuid, p_fallback_role_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor jsonb := public.kryintalk_group_actor(p_group_id);
  v_role public.group_roles%ROWTYPE;
  v_fallback uuid;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'delete_roles');
  SELECT * INTO v_role FROM public.group_roles WHERE id = p_role_id AND group_id = p_group_id::text;
  IF NOT FOUND THEN RAISE EXCEPTION 'Role not found.' USING ERRCODE = 'P0002'; END IF;
  IF v_role.is_system OR v_role.hierarchy_rank = 0 OR v_role.name IN ('Group Owner', 'Group Admin', 'Group Member', 'Group Viewer') OR coalesce(v_role.is_default, 'false')::boolean THEN RAISE EXCEPTION 'This protected role cannot be deleted.' USING ERRCODE = '42501'; END IF;
  IF NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND v_role.hierarchy_rank <= coalesce((v_actor ->> 'rank')::bigint, 10000) THEN RAISE EXCEPTION 'You cannot delete an equal or higher role.' USING ERRCODE = '42501'; END IF;
  IF p_fallback_role_id IS NOT NULL THEN
    SELECT id INTO v_fallback FROM public.group_roles WHERE id = p_fallback_role_id AND group_id = p_group_id::text;
    IF v_fallback IS NULL THEN RAISE EXCEPTION 'Fallback role not found.' USING ERRCODE = 'P0002'; END IF;
  ELSE
    SELECT id INTO v_fallback FROM public.group_roles WHERE group_id = p_group_id::text AND coalesce(is_default, 'false')::boolean LIMIT 1;
  END IF;
  UPDATE public.group_members SET role_id = v_fallback::text, updated_at = now() WHERE group_id = p_group_id::text AND role_id = p_role_id::text;
  DELETE FROM public.group_roles WHERE id = p_role_id;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details) VALUES (auth.uid()::text, 'group.role.deleted', 'group_role', p_role_id::text, jsonb_build_object('fallback_role_id', v_fallback));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_kryintalk_group_members(p_group_id uuid)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'id', gm.id, 'group_id', gm.group_id, 'user_id', gm.user_id,
    'username', u.username, 'display_name', u.display_name, 'email', u.email,
    'role_id', gm.role_id, 'role', CASE WHEN gr.id IS NULL THEN NULL ELSE public.kryintalk_group_role_json(gr) END,
    'added_by', gm.added_by, 'created_at', gm.created_at
  )
  FROM public.group_members gm
  LEFT JOIN public.users u ON u.id::text = gm.user_id
  LEFT JOIN public.group_roles gr ON gr.id::text = gm.role_id
  WHERE gm.group_id = p_group_id::text
    AND public.kryintalk_has_group_permission(p_group_id, 'view_members')
  ORDER BY lower(coalesce(u.display_name, u.username, gm.user_id));
$$;

CREATE OR REPLACE FUNCTION public.add_kryintalk_group_members(p_group_id uuid, p_user_ids uuid[], p_role_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group public.groups%ROWTYPE;
  v_actor jsonb := public.kryintalk_group_actor(p_group_id);
  v_role_id uuid := p_role_id;
  v_role_rank bigint;
  v_conversation_id uuid;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'add_members');
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Group not found.' USING ERRCODE = 'P0002'; END IF;
  IF coalesce(v_group.only_admin_invites, 'true')::boolean AND NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND coalesce((v_actor ->> 'rank')::bigint, 10000) > 10 THEN RAISE EXCEPTION 'Only group owners and administrators can add members.' USING ERRCODE = '42501'; END IF;
  IF cardinality(coalesce(p_user_ids, ARRAY[]::uuid[])) = 0 THEN RAISE EXCEPTION 'Choose at least one member.' USING ERRCODE = '22023'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(p_user_ids) member_id WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id::text = member_id::text AND u.organization_id = v_group.organization_id AND u.deleted_at IS NULL AND u.is_active)) THEN RAISE EXCEPTION 'Members must belong to your organization.' USING ERRCODE = '42501'; END IF;
  IF v_role_id IS NULL THEN SELECT id INTO v_role_id FROM public.group_roles WHERE group_id = p_group_id::text AND coalesce(is_default, 'false')::boolean LIMIT 1; ELSE SELECT hierarchy_rank INTO v_role_rank FROM public.group_roles WHERE id = v_role_id AND group_id = p_group_id::text; IF v_role_rank IS NULL THEN RAISE EXCEPTION 'Role not found.' USING ERRCODE = 'P0002'; END IF; IF NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND v_role_rank <= coalesce((v_actor ->> 'rank')::bigint, 10000) THEN RAISE EXCEPTION 'You cannot assign an equal or higher role.' USING ERRCODE = '42501'; END IF; END IF;
  INSERT INTO public.group_members (group_id, user_id, role_id, added_by)
  SELECT p_group_id::text, member_id::text, v_role_id::text, auth.uid()::text FROM unnest(p_user_ids) member_id
  ON CONFLICT (group_id, user_id) DO UPDATE SET role_id = EXCLUDED.role_id, added_by = EXCLUDED.added_by, updated_at = now();
  SELECT id INTO v_conversation_id FROM public.conversations WHERE organization_id = v_group.organization_id AND conversation_type = 'group' AND target_id = p_group_id::text LIMIT 1;
  IF v_conversation_id IS NOT NULL THEN INSERT INTO public.conversation_participants (conversation_id, user_id) SELECT v_conversation_id, member_id FROM unnest(p_user_ids) member_id ON CONFLICT (conversation_id, user_id) DO NOTHING; END IF;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details) VALUES (auth.uid()::text, 'group.members.added', 'group', p_group_id::text, jsonb_build_object('user_ids', p_user_ids, 'role_id', v_role_id));
  RETURN public.kryintalk_group_summary(p_group_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_kryintalk_group_member_role(p_group_id uuid, p_user_id uuid, p_role_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor jsonb := public.kryintalk_group_actor(p_group_id);
  v_group public.groups%ROWTYPE;
  v_target_rank bigint;
  v_new_role public.group_roles%ROWTYPE;
  v_member public.group_members%ROWTYPE;
  v_user public.users%ROWTYPE;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'assign_roles');
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id;
  IF v_group.created_by = p_user_id::text THEN RAISE EXCEPTION 'The group owner cannot be demoted.' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_member FROM public.group_members WHERE group_id = p_group_id::text AND user_id = p_user_id::text;
  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found.' USING ERRCODE = 'P0002'; END IF;
  SELECT hierarchy_rank INTO v_target_rank FROM public.group_roles WHERE id::text = v_member.role_id;
  SELECT * INTO v_new_role FROM public.group_roles WHERE id = p_role_id AND group_id = p_group_id::text;
  IF NOT FOUND THEN RAISE EXCEPTION 'Role not found.' USING ERRCODE = 'P0002'; END IF;
  IF NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND (coalesce(v_target_rank, 10000) <= coalesce((v_actor ->> 'rank')::bigint, 10000) OR v_new_role.hierarchy_rank <= coalesce((v_actor ->> 'rank')::bigint, 10000)) THEN RAISE EXCEPTION 'You cannot change an equal or higher member role.' USING ERRCODE = '42501'; END IF;
  UPDATE public.group_members SET role_id = p_role_id::text, updated_at = now() WHERE id = v_member.id RETURNING * INTO v_member;
  SELECT * INTO v_user FROM public.users WHERE id::text = p_user_id::text;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details) VALUES (auth.uid()::text, 'group.member.role_assigned', 'group_member', p_user_id::text, jsonb_build_object('group_id', p_group_id, 'role_id', p_role_id));
  RETURN jsonb_build_object('id', v_member.id, 'group_id', v_member.group_id, 'user_id', v_member.user_id, 'username', v_user.username, 'display_name', v_user.display_name, 'email', v_user.email, 'role_id', v_member.role_id, 'role', public.kryintalk_group_role_json(v_new_role), 'added_by', v_member.added_by, 'created_at', v_member.created_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_kryintalk_group_member(p_group_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group public.groups%ROWTYPE;
  v_actor jsonb := public.kryintalk_group_actor(p_group_id);
  v_target_rank bigint;
  v_conversation_id uuid;
BEGIN
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Group not found.' USING ERRCODE = 'P0002'; END IF;
  IF v_group.created_by = p_user_id::text THEN RAISE EXCEPTION 'The group owner cannot be removed.' USING ERRCODE = '42501'; END IF;
  IF p_user_id <> auth.uid() THEN
    PERFORM public.kryintalk_require_group_permission(p_group_id, 'remove_members');
    SELECT gr.hierarchy_rank INTO v_target_rank FROM public.group_members gm LEFT JOIN public.group_roles gr ON gr.id::text = gm.role_id WHERE gm.group_id = p_group_id::text AND gm.user_id = p_user_id::text;
    IF NOT coalesce((v_actor ->> 'is_owner')::boolean, false) AND coalesce(v_target_rank, 10000) <= coalesce((v_actor ->> 'rank')::bigint, 10000) THEN RAISE EXCEPTION 'You cannot remove an equal or higher member.' USING ERRCODE = '42501'; END IF;
  END IF;
  DELETE FROM public.group_members WHERE group_id = p_group_id::text AND user_id = p_user_id::text;
  SELECT id INTO v_conversation_id FROM public.conversations WHERE organization_id = v_group.organization_id AND conversation_type = 'group' AND target_id = p_group_id::text LIMIT 1;
  IF v_conversation_id IS NOT NULL THEN DELETE FROM public.conversation_participants WHERE conversation_id = v_conversation_id AND user_id = p_user_id; END IF;
  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details) VALUES (auth.uid()::text, 'group.member.removed', 'group', p_group_id::text, jsonb_build_object('user_id', p_user_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.find_or_create_kryintalk_group_conversation(p_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_group public.groups%ROWTYPE; v_conversation_id uuid;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'view_messages');
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  SELECT id INTO v_conversation_id FROM public.conversations WHERE organization_id = v_group.organization_id AND conversation_type = 'group' AND target_id = p_group_id::text LIMIT 1;
  IF v_conversation_id IS NULL THEN INSERT INTO public.conversations (organization_id, conversation_type, target_id) VALUES (v_group.organization_id, 'group', p_group_id::text) RETURNING id INTO v_conversation_id; END IF;
  INSERT INTO public.conversation_participants (conversation_id, user_id) VALUES (v_conversation_id, auth.uid()) ON CONFLICT (conversation_id, user_id) DO NOTHING;
  RETURN (SELECT jsonb_build_object('id', id, 'organization_id', organization_id, 'conversation_type', conversation_type, 'target_id', target_id, 'created_at', created_at, 'updated_at', updated_at) FROM public.conversations WHERE id = v_conversation_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.kryintalk_enforce_group_message_permission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_group_id uuid; v_permission text;
BEGIN
  SELECT target_id::uuid INTO v_group_id FROM public.conversations WHERE id = NEW.conversation_id AND conversation_type = 'group';
  IF v_group_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NOT public.kryintalk_has_group_permission(v_group_id, 'send_messages', NEW.sender_id) THEN RAISE EXCEPTION 'You do not have permission to send group messages.' USING ERRCODE = '42501'; END IF;
    IF NEW.parent_id IS NOT NULL AND NOT public.kryintalk_has_group_permission(v_group_id, 'reply_messages', NEW.sender_id) THEN RAISE EXCEPTION 'You do not have permission to reply in this group.' USING ERRCODE = '42501'; END IF;
  ELSE
    IF NEW.content IS DISTINCT FROM OLD.content THEN v_permission := CASE WHEN OLD.sender_id = auth.uid() THEN 'edit_own_messages' ELSE 'edit_other_messages' END; ELSIF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN v_permission := CASE WHEN OLD.sender_id = auth.uid() THEN 'delete_own_messages' ELSE 'delete_other_messages' END; ELSIF NEW.is_pinned IS DISTINCT FROM OLD.is_pinned THEN v_permission := CASE WHEN NEW.is_pinned THEN 'pin_messages' ELSE 'unpin_messages' END; END IF;
    IF v_permission IS NOT NULL AND NOT public.kryintalk_has_group_permission(v_group_id, v_permission, auth.uid()) THEN RAISE EXCEPTION 'You do not have permission to modify this group message.' USING ERRCODE = '42501'; END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS kryintalk_enforce_group_message_permission ON public.messages;
CREATE TRIGGER kryintalk_enforce_group_message_permission
BEFORE INSERT OR UPDATE ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.kryintalk_enforce_group_message_permission();

CREATE OR REPLACE FUNCTION public.kryintalk_can_message_action(p_message_id text, p_permission text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_type text; v_target text; v_conversation uuid;
BEGIN
  SELECT c.conversation_type, c.target_id, c.id INTO v_type, v_target, v_conversation FROM public.messages m JOIN public.conversations c ON c.id = m.conversation_id WHERE m.id::text = p_message_id;
  IF v_type = 'group' THEN RETURN public.kryintalk_has_group_permission(v_target::uuid, p_permission); END IF;
  RETURN public.can_access_conversation(v_conversation);
END;
$$;

DROP POLICY IF EXISTS kt_messages_update_own ON public.messages;
CREATE POLICY kt_messages_update_own ON public.messages FOR UPDATE TO authenticated
  USING ((sender_id = auth.uid() AND public.kryintalk_can_message_action(id::text, 'edit_own_messages')) OR public.kryintalk_can_message_action(id::text, 'edit_other_messages'))
  WITH CHECK (true);
DROP POLICY IF EXISTS kt_messages_delete_own ON public.messages;
CREATE POLICY kt_messages_delete_own ON public.messages FOR DELETE TO authenticated
  USING ((sender_id = auth.uid() AND public.kryintalk_can_message_action(id::text, 'delete_own_messages')) OR public.kryintalk_can_message_action(id::text, 'delete_other_messages'));
DROP POLICY IF EXISTS kt_reactions_write ON public.message_reactions;
CREATE POLICY kt_reactions_write ON public.message_reactions FOR ALL TO authenticated
  USING (user_id = auth.uid()::text AND public.kryintalk_can_message_action(message_id, 'remove_reactions'))
  WITH CHECK (user_id = auth.uid()::text AND public.kryintalk_can_message_action(message_id, 'add_reactions'));

REVOKE ALL ON FUNCTION public.kryintalk_group_actor(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.kryintalk_has_group_permission(uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.kryintalk_require_group_permission(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.kryintalk_group_summary(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_kryintalk_groups() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_kryintalk_group(text, text, text, text, text, text, boolean, boolean, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_kryintalk_group(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_kryintalk_group_roles(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_kryintalk_group_role(uuid, text, text, text, jsonb, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_kryintalk_group_role(uuid, uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_kryintalk_group_role(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_kryintalk_group_members(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_kryintalk_group_members(uuid, uuid[], uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.assign_kryintalk_group_member_role(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_kryintalk_group_member(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_or_create_kryintalk_group_conversation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_kryintalk_groups() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_kryintalk_group(text, text, text, text, text, text, boolean, boolean, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_kryintalk_group(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.kryintalk_group_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_kryintalk_group_roles(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_kryintalk_group_role(uuid, text, text, text, jsonb, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_kryintalk_group_role(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_kryintalk_group_role(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_kryintalk_group_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_kryintalk_group_members(uuid, uuid[], uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_kryintalk_group_member_role(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_kryintalk_group_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_or_create_kryintalk_group_conversation(uuid) TO authenticated;
