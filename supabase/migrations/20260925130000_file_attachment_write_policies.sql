BEGIN;

DROP POLICY IF EXISTS kt_files_select ON public.file_attachments;
CREATE POLICY kt_files_select ON public.file_attachments FOR SELECT TO authenticated
  USING (deleted_at IS NULL AND public.can_access_file(organization_id::text, conversation_id::text));

DROP POLICY IF EXISTS kt_files_insert ON public.file_attachments;
CREATE POLICY kt_files_insert ON public.file_attachments FOR INSERT TO authenticated
  WITH CHECK (
    uploader_id = auth.uid()
    AND size_bytes BETWEEN 1 AND 52428800
    AND nullif(original_filename, '') IS NOT NULL
    AND nullif(content_type, '') IS NOT NULL
    AND stored_filename = storage_path
    AND (organization_id IS NULL OR public.same_kryintalk_key(organization_id::text, public.current_user_org_id()))
    AND (
      (conversation_id IS NOT NULL
        AND public.can_access_conversation(conversation_id::text)
        AND starts_with(storage_path, 'conversations/' || conversation_id::text || '/'))
      OR (conversation_id IS NULL
        AND public.same_kryintalk_key(organization_id::text, public.current_user_org_id())
        AND starts_with(storage_path, 'files/' || auth.uid()::text || '/'))
    )
  );

-- Metadata edits never grant permission to reassign a file to another user or location.
REVOKE UPDATE ON public.file_attachments FROM authenticated;
GRANT UPDATE (original_filename, deleted_at) ON public.file_attachments TO authenticated;
DROP POLICY IF EXISTS kt_files_update ON public.file_attachments;
CREATE POLICY kt_files_update ON public.file_attachments FOR UPDATE TO authenticated
  USING (deleted_at IS NULL AND uploader_id = auth.uid()
    AND public.can_access_file(organization_id::text, conversation_id::text))
  WITH CHECK (uploader_id = auth.uid()
    AND public.can_access_file(organization_id::text, conversation_id::text));

COMMIT;
