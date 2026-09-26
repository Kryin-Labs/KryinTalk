-- Soft-delete a group and revoke every group conversation participant.

CREATE OR REPLACE FUNCTION public.delete_kryintalk_group(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group public.groups%ROWTYPE;
  v_conversation_id uuid;
BEGIN
  PERFORM public.kryintalk_require_group_permission(p_group_id, 'delete_group');
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found.' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.groups SET deleted_at = now(), updated_at = now() WHERE id = p_group_id;
  SELECT id INTO v_conversation_id
  FROM public.conversations
  WHERE organization_id = v_group.organization_id
    AND conversation_type = 'group'
    AND target_id = p_group_id::text
  LIMIT 1;
  IF v_conversation_id IS NOT NULL THEN
    DELETE FROM public.conversation_participants WHERE conversation_id = v_conversation_id;
  END IF;

  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, 'group.deleted', 'group', p_group_id::text,
    jsonb_build_object('name', v_group.name));
END;
$$;

REVOKE ALL ON FUNCTION public.delete_kryintalk_group(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_kryintalk_group(uuid) TO authenticated;
