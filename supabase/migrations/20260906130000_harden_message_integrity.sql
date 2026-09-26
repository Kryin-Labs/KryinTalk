-- Keep direct PostgREST updates from changing message identity or bypassing
-- the message RPC's basic input checks.
BEGIN;

CREATE OR REPLACE FUNCTION public.kryintalk_validate_message_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND (
    NEW.conversation_id IS DISTINCT FROM OLD.conversation_id
    OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
    OR NEW.parent_id IS DISTINCT FROM OLD.parent_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  ) THEN
    RAISE EXCEPTION 'Message identity cannot be changed';
  END IF;

  IF coalesce(length(trim(NEW.content)), 0) = 0 THEN
    RAISE EXCEPTION 'Message content is required';
  END IF;
  IF length(NEW.content) > 10000 THEN
    RAISE EXCEPTION 'Message content is too long';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS kryintalk_validate_message_mutation ON public.messages;
CREATE TRIGGER kryintalk_validate_message_mutation
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.kryintalk_validate_message_mutation();

DROP POLICY IF EXISTS kt_reactions_write ON public.message_reactions;
CREATE POLICY kt_reactions_write ON public.message_reactions FOR ALL TO authenticated
  USING (
    public.same_kryintalk_key(user_id, auth.uid()::text)
    AND EXISTS (
      SELECT 1 FROM public.messages AS m
      WHERE public.same_kryintalk_key(m.id::text, message_reactions.message_id)
        AND public.can_access_conversation(m.conversation_id)
    )
  )
  WITH CHECK (
    public.same_kryintalk_key(user_id, auth.uid()::text)
    AND EXISTS (
      SELECT 1 FROM public.messages AS m
      WHERE public.same_kryintalk_key(m.id::text, message_reactions.message_id)
        AND public.can_access_conversation(m.conversation_id)
    )
  );

REVOKE ALL ON FUNCTION public.kryintalk_validate_message_mutation() FROM PUBLIC, anon, authenticated;

COMMIT;
