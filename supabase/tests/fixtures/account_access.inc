INSERT INTO public.organizations(id,name,slug,is_active,created_at)
VALUES('a2000000-0000-4000-8000-000000000001','Local account tests','account-tests',true,now());
INSERT INTO public.roles(id,organization_id,code,name,is_active)
VALUES('a3000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','member','Member',true),
('a3000000-0000-4000-8000-000000000002','a2000000-0000-4000-8000-000000000001','admin','Admin',true),
('a3000000-0000-4000-8000-000000000003',NULL,'super_admin','Superadmin',true);
INSERT INTO auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
raw_user_meta_data,confirmation_token,recovery_token,email_change_token_new,email_change,created_at,updated_at)
SELECT ('a1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
'actor'||n||'@example.test',extensions.crypt('local-only-test-password',extensions.gen_salt('bf')),
CASE WHEN n=2 THEN NULL ELSE now() END,
jsonb_build_object('username','test_actor_'||n,'display_name','Actor '||n,'agreement',true,'policy_version','2026-09-26','role','super_admin'),
'','','','',now(),now() FROM generate_series(1,6) n;
SELECT set_config('kryintalk.account_write','trusted',true);
UPDATE public.users SET access_status='approved',role='member',is_active=true,is_suspended=false,
policy_version='2026-09-26' WHERE id IN ('a1000000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000004','a1000000-0000-4000-8000-000000000005');
UPDATE public.users SET email='mismatch@example.test' WHERE id='a1000000-0000-4000-8000-000000000006';
SELECT set_config('kryintalk.account_write','',true);
INSERT INTO public.user_roles(user_id,role_id)
VALUES('a1000000-0000-4000-8000-000000000003','a3000000-0000-4000-8000-000000000001'),
('a1000000-0000-4000-8000-000000000004','a3000000-0000-4000-8000-000000000002'),
('a1000000-0000-4000-8000-000000000005','a3000000-0000-4000-8000-000000000003');
INSERT INTO public.conversations(id,organization_id,conversation_type)
VALUES('a4000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','direct'),
('a4000000-0000-4000-8000-000000000002','a2000000-0000-4000-8000-000000000001','direct');
INSERT INTO public.conversation_participants(conversation_id,user_id)
VALUES('a4000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001'),
('a4000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003'),
('a4000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000004');
INSERT INTO public.messages(conversation_id,sender_id,content,message_type)
VALUES('a4000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003','Local fixture one','text'),
('a4000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000004','Local fixture two','text');
INSERT INTO public.notification_items(user_id,title,body,notification_type)
VALUES('a1000000-0000-4000-8000-000000000001','Pending private fixture','Fixture','message'),
('a1000000-0000-4000-8000-000000000003','Member private fixture','Fixture','message');
INSERT INTO public.file_attachments(organization_id,conversation_id,uploader_id,original_filename,stored_filename,storage_path,size_bytes,content_type)
VALUES('a2000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000003',
'fixture.md','conversations/a4000000-0000-4000-8000-000000000001/fixture.md',
'conversations/a4000000-0000-4000-8000-000000000001/fixture.md',10,'text/markdown');
INSERT INTO storage.objects(bucket_id,name,owner_id)
VALUES('attachments','conversations/a4000000-0000-4000-8000-000000000001/fixture.md','a1000000-0000-4000-8000-000000000003');

