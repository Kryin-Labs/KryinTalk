-- Authenticated, validated self-service profile updates for the Supabase-only app.

CREATE OR REPLACE FUNCTION public.update_kryintalk_profile(
  p_display_name text DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_hide_from_dm boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_display_name text;
  v_username text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_user FROM public.users
  WHERE id = auth.uid() AND deleted_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found.' USING ERRCODE = 'P0002';
  END IF;

  v_display_name := v_user.display_name;
  IF p_display_name IS NOT NULL THEN
    v_display_name := btrim(p_display_name);
    IF char_length(v_display_name) NOT BETWEEN 1 AND 120 THEN
      RAISE EXCEPTION 'Display name must be 1–120 characters.' USING ERRCODE = '22023';
    END IF;
  END IF;

  v_username := v_user.username;
  IF p_username IS NOT NULL THEN
    v_username := lower(btrim(p_username));
    IF v_username !~ '^[a-z0-9_]{3,100}$' THEN
      RAISE EXCEPTION 'Username must be 3–100 lowercase letters, numbers, or underscores.' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.users WHERE lower(username) = v_username AND id <> auth.uid()) THEN
      RAISE EXCEPTION 'That username is already taken.' USING ERRCODE = '23505';
    END IF;
  END IF;

  UPDATE public.users
  SET display_name = v_display_name,
      username = v_username,
      hide_from_dm = coalesce(p_hide_from_dm, hide_from_dm),
      updated_at = now()
  WHERE id = auth.uid()
  RETURNING * INTO v_user;

  INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, details)
  VALUES (auth.uid()::text, 'profile.updated', 'user', auth.uid()::text,
    jsonb_build_object('changed_display_name', p_display_name IS NOT NULL,
      'changed_username', p_username IS NOT NULL,
      'changed_hide_from_dm', p_hide_from_dm IS NOT NULL));

  RETURN jsonb_build_object(
    'id', v_user.id, 'email', v_user.email, 'username', v_user.username,
    'display_name', v_user.display_name, 'avatar_url', v_user.avatar_url,
    'hide_from_dm', v_user.hide_from_dm
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_kryintalk_profile(text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_kryintalk_profile(text, text, boolean) TO authenticated;
