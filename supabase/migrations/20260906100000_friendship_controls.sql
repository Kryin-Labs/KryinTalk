-- Keep every friendship mutation on an authenticated Supabase RPC.

BEGIN;

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
  v_actor uuid := auth.uid();
  v_friendship public.friendships;
BEGIN
  SELECT * INTO v_friendship
  FROM public.friendships
  WHERE id = p_friendship_id AND addressee_id = v_actor AND status = 'pending'
  FOR UPDATE;

  IF v_friendship.id IS NULL THEN
    RAISE EXCEPTION 'Friend request is unavailable';
  END IF;

  IF p_accept THEN
    UPDATE public.friendships
    SET status = 'accepted', updated_at = now()
    WHERE id = p_friendship_id
    RETURNING * INTO v_friendship;
    PERFORM public.write_kryintalk_audit(
      'friendship.accepted', 'friendship', v_friendship.id::text,
      jsonb_build_object('requester_id', v_friendship.requester_id)
    );
    RETURN to_jsonb(v_friendship);
  END IF;

  DELETE FROM public.friendships WHERE id = p_friendship_id;
  PERFORM public.write_kryintalk_audit(
    'friendship.rejected', 'friendship', p_friendship_id::text,
    jsonb_build_object('requester_id', v_friendship.requester_id)
  );
  RETURN jsonb_build_object('id', p_friendship_id, 'status', 'rejected');
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_friendship(p_friendship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_friendship public.friendships;
BEGIN
  SELECT * INTO v_friendship
  FROM public.friendships
  WHERE id = p_friendship_id
    AND (requester_id = v_actor OR addressee_id = v_actor)
  FOR UPDATE;

  IF v_friendship.id IS NULL THEN
    RAISE EXCEPTION 'Friendship is unavailable';
  END IF;
  IF v_friendship.status = 'blocked' AND v_friendship.blocked_by IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'Only the person who blocked this user can remove the block';
  END IF;

  DELETE FROM public.friendships WHERE id = p_friendship_id;
  PERFORM public.write_kryintalk_audit(
    'friendship.removed', 'friendship', p_friendship_id::text,
    jsonb_build_object('other_user_id', CASE
      WHEN v_friendship.requester_id = v_actor THEN v_friendship.addressee_id
      ELSE v_friendship.requester_id
    END)
  );
  RETURN jsonb_build_object('id', p_friendship_id, 'status', 'removed');
END;
$$;

CREATE OR REPLACE FUNCTION public.block_user(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_friendship public.friendships;
BEGIN
  IF v_actor IS NULL OR p_user_id IS NULL OR p_user_id = v_actor THEN
    RAISE EXCEPTION 'A different authenticated user is required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = p_user_id
      AND public.same_kryintalk_key(organization_id, public.current_user_org_id())
      AND is_active AND NOT is_suspended AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'User is unavailable';
  END IF;

  SELECT * INTO v_friendship
  FROM public.friendships
  WHERE (requester_id = v_actor AND addressee_id = p_user_id)
     OR (requester_id = p_user_id AND addressee_id = v_actor)
  FOR UPDATE;

  IF v_friendship.id IS NULL THEN
    INSERT INTO public.friendships (requester_id, addressee_id, status, blocked_by)
    VALUES (v_actor, p_user_id, 'blocked', v_actor)
    RETURNING * INTO v_friendship;
  ELSE
    UPDATE public.friendships
    SET status = 'blocked', blocked_by = v_actor, updated_at = now()
    WHERE id = v_friendship.id
    RETURNING * INTO v_friendship;
  END IF;

  PERFORM public.write_kryintalk_audit(
    'friendship.blocked', 'friendship', v_friendship.id::text,
    jsonb_build_object('blocked_user_id', p_user_id)
  );
  RETURN to_jsonb(v_friendship);
END;
$$;

REVOKE ALL ON FUNCTION public.remove_friendship(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.block_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_friendship(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_user(uuid) TO authenticated;

COMMIT;
