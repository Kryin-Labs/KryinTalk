-- Retire the legacy organization hierarchy after Channels, Departments, and Teams were replaced by Groups.
BEGIN;

DELETE FROM public.messages AS message
USING public.conversations AS conversation
WHERE message.conversation_id = conversation.id
  AND conversation.conversation_type::text = 'channel';

DELETE FROM public.conversation_participants AS participant
USING public.conversations AS conversation
WHERE participant.conversation_id = conversation.id
  AND conversation.conversation_type::text = 'channel';

DELETE FROM public.conversations
WHERE conversation_type::text = 'channel';

DROP TABLE IF EXISTS public.channel_members;
DROP TABLE IF EXISTS public.channels;
DROP TABLE IF EXISTS public.teams;
DROP TABLE IF EXISTS public.departments;

COMMIT;
