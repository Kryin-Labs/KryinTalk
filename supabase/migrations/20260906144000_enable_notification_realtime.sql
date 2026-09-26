-- Notification delivery is event-driven; the browser subscribes under the
-- existing self-only RLS policy instead of polling every few seconds.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notification_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_items;
  END IF;
END;
$$;
