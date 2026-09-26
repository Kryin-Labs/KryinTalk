-- ============================================================================
-- ConnectHub — Supabase PostgreSQL Production Schema & Seed Migration
-- Project ID: mujhkmuhlmuqbansrdwp
-- ============================================================================

-- Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- 1. Organizations
CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    domain VARCHAR(255) NOT NULL UNIQUE,
    settings_json JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 2. Users
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    username VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    avatar_url TEXT,
    phone_number VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    is_suspended BOOLEAN DEFAULT FALSE,
    hide_from_dm BOOLEAN DEFAULT FALSE,
    last_login_at TIMESTAMPTZ,
    presence_status VARCHAR(50) DEFAULT 'offline',
    last_active_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 3. Roles
CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(50) NOT NULL,
    description TEXT,
    is_system BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 4. User Roles
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    granted_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Departments
CREATE TABLE IF NOT EXISTS public.departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    manager_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 6. Teams
CREATE TABLE IF NOT EXISTS public.teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    lead_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 7. Groups
CREATE TABLE IF NOT EXISTS public.groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_private BOOLEAN DEFAULT FALSE,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 8. Group Roles
CREATE TABLE IF NOT EXISTS public.group_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    color VARCHAR(50) DEFAULT '#0F766E',
    position INT DEFAULT 0,
    can_send_messages BOOLEAN DEFAULT TRUE,
    can_manage_roles BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Group Members
CREATE TABLE IF NOT EXISTS public.group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'member',
    group_role_id UUID REFERENCES public.group_roles(id) ON DELETE SET NULL,
    joined_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Group Invites
CREATE TABLE IF NOT EXISTS public.group_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    invited_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    invited_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. Channels
CREATE TABLE IF NOT EXISTS public.channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_private BOOLEAN DEFAULT FALSE,
    channel_type VARCHAR(50) DEFAULT 'text',
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 12. Channel Members
CREATE TABLE IF NOT EXISTS public.channel_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id UUID REFERENCES public.channels(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'member',
    joined_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. Conversations
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    conversation_type VARCHAR(50) NOT NULL, -- direct, group, channel
    target_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. Conversation Participants
CREATE TABLE IF NOT EXISTS public.conversation_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 15. Messages
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sequence_num BIGSERIAL,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    message_type VARCHAR(50) DEFAULT 'text', -- text, file, system
    parent_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    metadata_json JSONB DEFAULT '{}'::jsonb,
    is_pinned BOOLEAN DEFAULT FALSE,
    pinned_at TIMESTAMPTZ,
    pinned_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 16. Message Reactions
CREATE TABLE IF NOT EXISTS public.message_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    reaction VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 17. File Attachments
CREATE TABLE IF NOT EXISTS public.file_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
    message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    uploader_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100) NOT NULL,
    size_bytes BIGINT NOT NULL,
    storage_path TEXT NOT NULL,
    public_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 17b. Friend Requests & Blocks
CREATE TABLE IF NOT EXISTS public.friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    addressee_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked')),
    blocked_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT friendships_distinct_users CHECK (requester_id <> addressee_id),
    CONSTRAINT friendships_unique_direction UNIQUE (requester_id, addressee_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_requester ON public.friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON public.friendships(addressee_id);

-- 18. Notification Items
CREATE TABLE IF NOT EXISTS public.notification_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    notification_type VARCHAR(50) DEFAULT 'message',
    resource_id UUID,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- 19. Audit Logs
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(100),
    resource_id VARCHAR(255),
    ip_address VARCHAR(100),
    user_agent TEXT,
    details JSONB,
    changes JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);


-- Enable Supabase Realtime Publication
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_items;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.groups;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.channels;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Enable Row Level Security. Authenticated policies are installed by the
-- security hardening migration below.
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
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- RLS is enabled above. Install the authenticated, organization-scoped
-- policies from supabase/migrations/20260905120000_security_hardening.sql.


-- ============================================================================
-- SEED DATA INSERT STATEMENTS
-- ============================================================================

-- Table: organizations (2 records)
INSERT INTO public.organizations (name, slug, is_active, settings, id, created_at, updated_at, deleted_at) VALUES ('ConnectHub Enterprise', 'connecthub', 1, NULL, 'a93f73ca27c54f8199a679968324442e', '2026-08-18 14:24:48', '2026-08-18 14:24:48', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.organizations (name, slug, is_active, settings, id, created_at, updated_at, deleted_at) VALUES ('Acme Corporation', 'acme-corp', 1, NULL, '01bc537029694be7ba70552ac6131dca', '2026-08-18 14:36:18', '2026-08-18 14:36:18', NULL) ON CONFLICT DO NOTHING;

-- Table: roles (5 records)
INSERT INTO public.roles (organization_id, code, name, description, is_system, is_active, id, created_at, updated_at) VALUES ('a93f73ca27c54f8199a679968324442e', 'super_admin', 'Super Admin', 'Full administrative access across all domains', 1, 1, 'e256266e5bd148b796e25b35342cdef0', '2026-08-18 14:24:48', '2026-08-18 14:36:18') ON CONFLICT DO NOTHING;
INSERT INTO public.roles (organization_id, code, name, description, is_system, is_active, id, created_at, updated_at) VALUES (NULL, 'admin', 'Admin', 'Admin role', 1, 1, '1871cc1f94f74785b1cd67b460e0aa60', '2026-08-18 14:36:18', '2026-08-18 14:36:18') ON CONFLICT DO NOTHING;
INSERT INTO public.roles (organization_id, code, name, description, is_system, is_active, id, created_at, updated_at) VALUES (NULL, 'manager', 'Manager', 'Manager role', 1, 1, '7ddf4ba1507f4ea2b4af680dd34b2ed7', '2026-08-18 14:36:18', '2026-08-18 14:36:18') ON CONFLICT DO NOTHING;
INSERT INTO public.roles (organization_id, code, name, description, is_system, is_active, id, created_at, updated_at) VALUES (NULL, 'user', 'User', 'User role', 1, 1, 'aaafdea0927f48a4a370944f5714b8b2', '2026-08-18 14:36:18', '2026-08-18 14:36:18') ON CONFLICT DO NOTHING;
INSERT INTO public.roles (organization_id, code, name, description, is_system, is_active, id, created_at, updated_at) VALUES (NULL, 'guest', 'Guest', 'Guest role', 1, 1, '7626da6d58624363839b468ff7c64dc2', '2026-08-18 14:36:18', '2026-08-18 14:36:18') ON CONFLICT DO NOTHING;

-- Table: users (10 records)
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('a93f73ca27c54f8199a679968324442e', 'admin@connecthub.com', 'admin', 'Super Admin (Global)', '$2b$12$mhMzjka..ZGEc4b/p/c.y..ywclm4JZ8.DjRA7W7TqyYDz5chQLMC', 1, 0, '2026-08-18 17:38:52.959090', '2e2e7ea830544d089942546c4a529c09', '2026-08-18 14:24:48', '2026-08-18 17:38:52', NULL, 0) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'superadmin@connecthub.local', 'superadmin', 'Super Administrator', '$2b$12$jNNhAUhJLOHj.t0LJUtFh.mEdly1HM1YIj6Lq2FgjeCUDdYrHpLNG', 1, 0, '2026-08-18 18:22:29.114285', '3dfcccaab1d140b4a979acf5f4d7d613', '2026-08-18 14:36:18', '2026-08-18 18:22:29', NULL, 1) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'manager@connecthub.local', 'manager', 'Operations Manager', '$2b$12$q69GK0nz5ToeGLlK0pr2QOyO8nLZ6smHyYFpnwRbxzncutnjuyhYC', 1, 0, '2026-08-18 17:38:58.191940', '5e25e9f8a22c4f799b009a6923497289', '2026-08-18 14:36:18', '2026-08-18 17:38:58', NULL, 0) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'user@connecthub.local', 'regularuser', 'Regular User', '$2b$12$BZxz2kisz8KDBOYT0Q7mJOy6pNMhQqsh8ZWjDOaC8HtLvU7MkPajS', 1, 0, '2026-08-18 17:39:26.271176', '417fd4d288524a3f97a119bbbc825c5f', '2026-08-18 14:36:19', '2026-08-18 17:39:26', NULL, 0) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'guest@connecthub.local', 'guest', 'Guest User', '$2b$12$lOwIPoaVcWChX07db1krneKHQEhs9PyOYl2T9IwdEBKApGmsh5FW.', 1, 0, '2026-08-18 14:37:26.544245', 'fcce8ea19cdc49f3b2e0d9c6e78bd743', '2026-08-18 14:36:19', '2026-08-18 14:37:26', NULL, 0) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'guestuser@connecthub.local', 'guestuser', 'Guest User', '$2b$12$wXbiabp6Aafxk0odmZXRWeQzGBdym7Jz7p9d28L6WwzOLv/6on0vK', 1, 0, '2026-08-18 17:02:53.671389', '8039c19ab09a492bb941f17eeeeff4bd', '2026-08-18 14:36:19', '2026-08-18 17:02:53', NULL, 0) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'alice@connecthub.com', 'alice', 'Alice Smith', '$2b$12$4m.AuhYYMmMyw.9EI/KYl.GclDSf27CnrNNOPQFGYivpuTJ03MfsS', 1, 0, '2026-08-18 17:57:21.166414', '9d82cd1e2c444a64a663477765a035d5', '2026-08-18 14:36:20', '2026-08-18 17:57:21', NULL, 1) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'bob@connecthub.com', 'bob', 'Bob Jones', '$2b$12$XtXj.aiuiU08FA6WH9Gpe.nMoyqs6Z4J9oNS8Z63mFw6PUUel/nNW', 1, 0, '2026-08-18 17:02:51.064029', '1f56d5d3b607485eaef0467198e9414c', '2026-08-18 14:36:20', '2026-08-18 17:02:51', NULL, 0) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'charlie@connecthub.com', 'charlie', 'Charlie Brown', '$2b$12$Z3IcbdQWcZbZaksx490m0OQNV58Y2EBIhkSoiTanGlpenQCrLok7K', 1, 0, '2026-08-18 17:02:51.962039', 'e3dd1e2b3c884abaadf7785009761d99', '2026-08-18 14:36:21', '2026-08-18 17:02:51', NULL, 0) ON CONFLICT DO NOTHING;
INSERT INTO public.users (organization_id, email, username, display_name, password_hash, is_active, is_suspended, last_login_at, id, created_at, updated_at, deleted_at, hide_from_dm) VALUES ('01bc537029694be7ba70552ac6131dca', 'diana@connecthub.com', 'diana', 'Diana Prince', '$2b$12$eqU.Cyfpwz/FK.Ms/mlfdOB5EFp3QI9qs6Mis37jVfRdLmanHb2zq', 1, 0, '2026-08-18 17:02:52.787197', '8b0a8684cdad4a55a641b2b9d3d73212', '2026-08-18 14:36:21', '2026-08-18 17:02:52', NULL, 0) ON CONFLICT DO NOTHING;

-- Table: user_roles (10 records)
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'e256266e5bd148b796e25b35342cdef0', '2e2e7ea830544d089942546c4a529c09', '2026-08-18 14:24:48', '9998a15387884b40a44396c91b868417') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'e256266e5bd148b796e25b35342cdef0', NULL, '2026-08-18 14:36:18', '5623df4d9a4049828de1a09ca753b4a0') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('5e25e9f8a22c4f799b009a6923497289', '7ddf4ba1507f4ea2b4af680dd34b2ed7', NULL, '2026-08-18 14:36:18', 'd7d8bf1fe90e464f97b29b9e7c98d98f') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'aaafdea0927f48a4a370944f5714b8b2', NULL, '2026-08-18 14:36:19', '04467d1d860e40228ddfb0809fc40a07') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('fcce8ea19cdc49f3b2e0d9c6e78bd743', '7626da6d58624363839b468ff7c64dc2', NULL, '2026-08-18 14:36:19', 'c33d413445074b90bc2f40d70908e04d') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', '7626da6d58624363839b468ff7c64dc2', NULL, '2026-08-18 14:36:20', 'd1021f2ced374340884564219826b09c') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', '7ddf4ba1507f4ea2b4af680dd34b2ed7', NULL, '2026-08-18 14:36:20', '6d4d8cebf4134e6b8ab8a7e79a139806') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'aaafdea0927f48a4a370944f5714b8b2', NULL, '2026-08-18 14:36:21', '3b1cfb9441704a1eb3d8cef85c220d4a') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'aaafdea0927f48a4a370944f5714b8b2', NULL, '2026-08-18 14:36:21', '58f0a195bcdb4105ae4ee024003bd548') ON CONFLICT DO NOTHING;
INSERT INTO public.user_roles (user_id, role_id, granted_by, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'aaafdea0927f48a4a370944f5714b8b2', NULL, '2026-08-18 14:36:21', 'a29814370f37459e8ba548195ae91634') ON CONFLICT DO NOTHING;

-- Table: conversations (4 records)
INSERT INTO public.conversations (organization_id, conversation_type, target_id, id, created_at, updated_at) VALUES ('01bc537029694be7ba70552ac6131dca', 'DIRECT', NULL, '40b5e9506e2448fcaed5c6213758f4cd', '2026-08-18 15:45:14', '2026-08-18 15:45:14') ON CONFLICT DO NOTHING;
INSERT INTO public.conversations (organization_id, conversation_type, target_id, id, created_at, updated_at) VALUES ('01bc537029694be7ba70552ac6131dca', 'DIRECT', NULL, '78b43dca724346bb8363783062e038c1', '2026-08-18 15:46:13', '2026-08-18 15:46:13') ON CONFLICT DO NOTHING;
INSERT INTO public.conversations (organization_id, conversation_type, target_id, id, created_at, updated_at) VALUES ('01bc537029694be7ba70552ac6131dca', 'DIRECT', NULL, '28233491f0cb48dda4ea7b511a87ff08', '2026-08-18 15:56:14', '2026-08-18 15:56:14') ON CONFLICT DO NOTHING;
INSERT INTO public.conversations (organization_id, conversation_type, target_id, id, created_at, updated_at) VALUES ('01bc537029694be7ba70552ac6131dca', 'DIRECT', NULL, 'c9e148f30df94e58814a84081aa24fe2', '2026-08-18 16:17:19', '2026-08-18 16:17:19') ON CONFLICT DO NOTHING;

-- Table: conversation_participants (8 records)
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('40b5e9506e2448fcaed5c6213758f4cd', '3dfcccaab1d140b4a979acf5f4d7d613', NULL, 'b42532d6e55245a7807a31fc0241d398', '2026-08-18 15:45:14', '2026-08-18 15:45:14') ON CONFLICT DO NOTHING;
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('40b5e9506e2448fcaed5c6213758f4cd', '9d82cd1e2c444a64a663477765a035d5', NULL, '4abfc0471ad7435286e91daeb0153761', '2026-08-18 15:45:14', '2026-08-18 15:45:14') ON CONFLICT DO NOTHING;
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('78b43dca724346bb8363783062e038c1', '417fd4d288524a3f97a119bbbc825c5f', NULL, 'aa2740b845694058a52bc4619480f7c8', '2026-08-18 15:46:13', '2026-08-18 15:46:13') ON CONFLICT DO NOTHING;
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('78b43dca724346bb8363783062e038c1', '3dfcccaab1d140b4a979acf5f4d7d613', NULL, 'dcb83edfad9349ddad973fbdbac6c138', '2026-08-18 15:46:13', '2026-08-18 15:46:13') ON CONFLICT DO NOTHING;
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('28233491f0cb48dda4ea7b511a87ff08', '417fd4d288524a3f97a119bbbc825c5f', NULL, 'd23af089f6794461a12fd2359f199c53', '2026-08-18 15:56:14', '2026-08-18 15:56:14') ON CONFLICT DO NOTHING;
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('28233491f0cb48dda4ea7b511a87ff08', '9d82cd1e2c444a64a663477765a035d5', NULL, '5de8a9c3bd2a4838b40a0c5030d12b7d', '2026-08-18 15:56:14', '2026-08-18 15:56:14') ON CONFLICT DO NOTHING;
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('c9e148f30df94e58814a84081aa24fe2', '9d82cd1e2c444a64a663477765a035d5', '2026-08-18 16:18:47.000000', '9f6010e5d81d414cb526e77f0fca00b2', '2026-08-18 16:17:19', '2026-08-18 16:18:47') ON CONFLICT DO NOTHING;
INSERT INTO public.conversation_participants (conversation_id, user_id, last_read_at, id, created_at, updated_at) VALUES ('c9e148f30df94e58814a84081aa24fe2', '1f56d5d3b607485eaef0467198e9414c', NULL, '73d07c2813144c8db2244e5774928be1', '2026-08-18 16:17:19', '2026-08-18 16:17:19') ON CONFLICT DO NOTHING;

-- Table: messages (3 records)
INSERT INTO public.messages (sequence_num, conversation_id, sender_id, content, message_type, parent_id, metadata_json, is_pinned, pinned_at, pinned_by, id, created_at, updated_at, deleted_at) VALUES (1787069866776557000, 'c9e148f30df94e58814a84081aa24fe2', '9d82cd1e2c444a64a663477765a035d5', 'Hey Bob! This is Alice with hidden presence setting.', 'TEXT', NULL, 'null', 0, NULL, NULL, '3d1af6952f6a45c88f26173092179528', '2026-08-18 16:17:46', '2026-08-18 16:17:46', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.messages (sequence_num, conversation_id, sender_id, content, message_type, parent_id, metadata_json, is_pinned, pinned_at, pinned_by, id, created_at, updated_at, deleted_at) VALUES (1787069881680972800, 'c9e148f30df94e58814a84081aa24fe2', '9d82cd1e2c444a64a663477765a035d5', 'Hey Bob! This is Alice with hidden presence setting.', 'TEXT', NULL, 'null', 0, NULL, NULL, 'ea852e8f6df8451ab7d84bdeb73f12f9', '2026-08-18 16:18:01', '2026-08-18 16:18:01', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.messages (sequence_num, conversation_id, sender_id, content, message_type, parent_id, metadata_json, is_pinned, pinned_at, pinned_by, id, created_at, updated_at, deleted_at) VALUES (1787069927021224200, 'c9e148f30df94e58814a84081aa24fe2', '9d82cd1e2c444a64a663477765a035d5', 'Hey Bob! This is Alice with hidden presence setting.', 'TEXT', NULL, 'null', 0, NULL, NULL, '638f4bb38628404d95bbef5966e278c3', '2026-08-18 16:18:47', '2026-08-18 16:18:47', NULL) ON CONFLICT DO NOTHING;

-- Table: notification_items (8 records)
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'MESSAGE', 'New message from Alice Smith (@alice)', 'Hey Bob! This is Alice with hidden presence setting.', 'message', '3d1af695-2f6a-45c8-8f26-173092179528', 'c9e148f30df94e58814a84081aa24fe2', 0, 'c8e528545a2e458782ede8eeb53640d1', '2026-08-18 16:17:46', '2026-08-18 16:17:46', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'MESSAGE', 'New message from Alice Smith (@alice)', 'Hey Bob! This is Alice with hidden presence setting.', 'message', 'ea852e8f-6df8-451a-b7d8-4bdeb73f12f9', 'c9e148f30df94e58814a84081aa24fe2', 0, 'd5156eb5c19a424087a3e4ee08cd02e2', '2026-08-18 16:18:01', '2026-08-18 16:18:01', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'MESSAGE', 'New message from Alice Smith (@alice)', 'Hey Bob! This is Alice with hidden presence setting.', 'message', '638f4bb3-8628-404d-95bb-ef5966e278c3', 'c9e148f30df94e58814a84081aa24fe2', 0, 'b2a1fdf23036441f80e585225f9c1abb', '2026-08-18 16:18:47', '2026-08-18 16:18:47', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'INVITATION', 'Group Invitation: Secret View-Only Squad', 'Super Administrator (@superadmin) invited you to join ''Secret View-Only Squad''.', 'group_invite', '58e51653-d2e1-4ea4-9638-3a6415d8ad8e', 'eaadca80fb7d402e96825589a495ba8a', 1, '35cfd4db362c42d3887daf62747d8ebd', '2026-08-18 16:35:51', '2026-08-18 16:35:52', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'INVITATION', 'Group Invitation: Secret View-Only Squad', 'Super Administrator (@superadmin) invited you to join ''Secret View-Only Squad''.', 'group_invite', '5ac6c369-9883-4105-af59-825644eb7852', '166f797fa5334f37a1cafffbae4284af', 1, 'c27c2ed9a16b4da08c21e9fcc8217615', '2026-08-18 16:36:30', '2026-08-18 16:36:31', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'INVITATION', 'Group Invitation: Secret View-Only Squad', 'Super Administrator (@superadmin) invited you to join ''Secret View-Only Squad''.', 'group_invite', 'f403ba11-b6b1-4ed8-b767-82dab3a063e5', 'cc68bfd749b7496ba210d25e4cb93d9c', 1, '36d5af143b0943e3a520ff02d0a2cc63', '2026-08-18 16:37:30', '2026-08-18 16:37:31', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'INVITATION', 'Group Invitation: Secret View-Only Squad', 'Super Administrator (@superadmin) invited you to join ''Secret View-Only Squad''.', 'group_invite', '768c06f8-659c-4d47-bcc1-0383299d0182', '62cb716377214b71b7715b2fde5f6c25', 1, 'b00d04f491b045268f12beae69ef9401', '2026-08-18 16:52:22', '2026-08-18 16:52:23', NULL) ON CONFLICT DO NOTHING;
INSERT INTO public.notification_items (user_id, notification_type, title, body, resource_type, resource_id, conversation_id, is_read, id, created_at, updated_at, deleted_at) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'INVITATION', 'Group Invitation: Secret View-Only Squad', 'Super Administrator (@superadmin) invited you to join ''Secret View-Only Squad''.', 'group_invite', '6ab63fca-4e86-47d1-9ea7-0be346f24ecc', 'ded8b6d7c0b84aaaa4f0b22f1216e1b7', 1, 'b9080552adab4b76a04e448dac7891a5', '2026-08-18 17:02:57', '2026-08-18 17:02:58', NULL) ON CONFLICT DO NOTHING;

-- Table: audit_logs (206 records)
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:10', 'd838e2398f1e454c856d7fbc0b2aa553') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'auth.login_success', 'user', '2e2e7ea8-3054-4d08-9942-546c4a529c09', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:10', 'c574b6d79b914470af6e0b75cd348171') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('5e25e9f8a22c4f799b009a6923497289', 'auth.login_success', 'user', '5e25e9f8-a22c-4f79-9b00-9a6923497289', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:11', 'a2c7dbd89b1c4440a3672292e6d47a22') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:11', 'ab3b3460b33343a79b43c7a5daeba42c') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:12', '4a1249abdb1b4c1c9aeb8c6ce9d8eadf') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('fcce8ea19cdc49f3b2e0d9c6e78bd743', 'auth.login_success', 'user', 'fcce8ea1-9cdc-49f3-b2e0-d9c6e78bd743', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:12', 'acb2c40644c24a8580d9cc46e8f4bb62') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'auth.login_success', 'user', '2e2e7ea8-3054-4d08-9942-546c4a529c09', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:12', '8665ba68228f42518b57ff91622932e3') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:13', 'f7c4956f45de4fb9a732f8caa0fd6ca9') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:13', '6b2e55b53ed7449d95d58033a7d7d7cd') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:14', 'e60e253b500943bfb22681c8899e7b63') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:14', '5f5438b006ca4a68bee4bc5a31e2b3ba') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:24', '587048765131426b944179d47fbef8fb') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'auth.login_success', 'user', '2e2e7ea8-3054-4d08-9942-546c4a529c09', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:25', '610717441e254810b9ba0a18b90c1f3f') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('5e25e9f8a22c4f799b009a6923497289', 'auth.login_success', 'user', '5e25e9f8-a22c-4f79-9b00-9a6923497289', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:25', 'bf87895f1c764e4e86fc4dd31aa003b6') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:25', 'b2838d8593fa4d78b6dc8b1034162f41') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:26', 'dc5595f8e313494db93c75c2eb3f6a66') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('fcce8ea19cdc49f3b2e0d9c6e78bd743', 'auth.login_success', 'user', 'fcce8ea1-9cdc-49f3-b2e0-d9c6e78bd743', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:26', 'a36806cddf15475ab4404cacdff9a5b5') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'auth.login_success', 'user', '2e2e7ea8-3054-4d08-9942-546c4a529c09', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:26', '9239f9ad22194cbdabf30b63f0fa501b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:27', 'ee4cdd0e048542b29bc268846371e417') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:27', 'e64bc34595f546c3aaaaf4020fbc26ea') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:28', 'c134b8daa7a3402a82f6404eac1c1e89') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'Python-urllib/3.12', 'null', 'null', '2026-08-18 14:37:28', '1c6c3d0c3ee74ba29bd845a67fb4aa9e') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 14:38:56', '9b4654d8e09c417782482d9572c7ed12') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '192.168.1.13', 'Dart/3.12 (dart:io)', 'null', 'null', '2026-08-18 14:39:30', '2828cd0c166440f3ad1f728d8610b847') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 14:50:24', '62aa4f0058e3475e9d3b9a2cb860282c') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 14:50:32', 'd0c0645e60784a58b61713cd7e669c39') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 14:50:33', 'e9c66ac1bfa0412ab764857835881cb2') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.created', 'group', 'f4781330-1b20-49aa-bd7c-d77cf0069510', NULL, NULL, '{"name": "Announcements Only", "slug": "viewonly-test-39049140", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 14:50:33', 'd31e7f5ec5ee4173b486744c7ae2f337') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "c6c45505-b448-4871-b64d-2e0900936b08", "role_name": "Group Member"}', 'null', '2026-08-18 14:50:33', 'b77d832e57194333a6f7bbe179c0a796') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 15:25:34', '0b33845dc4a44c2c9a43cc758b7fc263') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'conversation.dm.created', 'conversation', '40b5e950-6e24-48fc-aed5-c6213758f4cd', NULL, NULL, 'null', 'null', '2026-08-18 15:45:14', 'ed8fd33e22f54d62817b8330b4a5d72f') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 15:46:02', '271c2d538561462794eb4451d13c8803') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'conversation.dm.created', 'conversation', '78b43dca-7243-46bb-8363-783062e038c1', NULL, NULL, 'null', 'null', '2026-08-18 15:46:13', '11d36e03135e49f3b7a0b44d4aba39a2') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.password_changed', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', '{"message": "Password updated successfully"}', 'null', '2026-08-18 15:50:52', 'c1dba5cf371a4beea0e8711568e8a810') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 15:51:13', 'ae6eb66123464148a9cf3e437c0c705e') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 15:52:17', 'a59b9979bfc342e69dff53a867ee47ce') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 15:52:18', '2f03138043f841d1844b1d8c84042dba') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 15:55:42', 'f99251ceaf4d4b44823c6704c8f19a18') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'conversation.dm.created', 'conversation', '28233491-f0cb-48dd-a4ea-7b511a87ff08', NULL, NULL, 'null', 'null', '2026-08-18 15:56:14', 'a2313be12228409bad8204aa9f6bfaf1') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:04:43', '8da934e1028245afb1fdd32dd43aa461') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.deleted', 'group', 'f4781330-1b20-49aa-bd7c-d77cf0069510', NULL, NULL, '{"name": "Announcements Only"}', 'null', '2026-08-18 16:14:58', 'cea682bf12be43a48a6bad7a67611b9f') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:17:07', 'ff4045a7ec7e4a66ba05643eac9a61c7') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:17:16', '19ea0e7ae8d547e0878bb562a8ceb3c6') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'conversation.dm.created', 'conversation', 'c9e148f3-0df9-4e58-814a-84081aa24fe2', NULL, NULL, 'null', 'null', '2026-08-18 16:17:19', '3879d9310e2c461eb090694cedb5beb0') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'group.created', 'group', '5461dd11-892e-43d5-ae3b-28efcfe447fa', NULL, NULL, '{"name": "4", "slug": "4", "visibility": "private", "initial_members": 1}', 'null', '2026-08-18 16:17:35', '3756965731364f6b9fae0e6da27b47fd') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:17:44', '68e4eadef348446aa64a6e6abe7b5ea8') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:17:45', 'aef18cc2f2d34da180b36d3f146a9079') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:17:59', 'd7bf46c494e547c6bd6a8741b62994a7') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:18:43', '82f7c085e8bc404da7968ee752d6d9b9') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 16:21:32', '39da34c2e10a4d0d89bd77bba7a1f5bb') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.updated', 'group', '5461dd11-892e-43d5-ae3b-28efcfe447fa', NULL, NULL, '{"name": "\ud83d\udc65 4", "description": "", "icon": "group", "color": "#6366F1", "visibility": "organization", "is_private": false}', 'null', '2026-08-18 16:21:46', '9317909bb126422eb868035e511384cf') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.updated', 'group', '5461dd11-892e-43d5-ae3b-28efcfe447fa', NULL, NULL, '{"name": "\ud83d\udc65 4", "description": "", "icon": "group", "color": "#6366F1", "visibility": "private", "is_private": true}', 'null', '2026-08-18 16:21:57', '38a061aba57946dcaa03f1eb71828d1d') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.updated', 'group', '5461dd11-892e-43d5-ae3b-28efcfe447fa', NULL, NULL, '{"name": "\ud83d\udc65 4", "description": "", "icon": "group", "color": "#6366F1", "visibility": "private", "is_private": true}', 'null', '2026-08-18 16:21:58', '01031a04c0e343538554f972321f2d63') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 16:26:48', 'ea4dfd1508ac409e8ca5259698be539f') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:20', '6e92ceb62f994bcbbb2e6389ba7a23a0') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:21', '92d8f18168c7403680f9453b9df3224e') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:22', 'c94aee25f92f4d3c9bd661c48009ec43') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:22', 'efb2eeb3637148fcb7371285a56b3210') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:23', '6a818d63ca054eb4ab22897472af3033') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:47', '9e6e923fb85a4c058ea4d74b6c61a36d') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:49', '4edff810743d41c1a93fc030d96ef80b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:50', '1c8b0fd37307411a9428f1db0a9cca9b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:32:50', '499fc4b3d5324defb1e4431fa86ceddd') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.created', 'group', '5524d54e-c717-41b3-b91f-d6b109e44bbd', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787070771", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:32:51', '9e1d4e43d42849358a0e59037d0ecb77') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "436fdeb6-ba11-4f0e-8914-4dbf15ec4dce", "role_name": "Group Member"}', 'null', '2026-08-18 16:32:53', '73f0299fce1f4c55ae2d2a62ff96d1dd') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:33:13', 'f14832e80fe34c69a5b20050a8b70a17') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:33:14', '8ccc2532296740f7a5f34f742a045c30') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:33:15', 'd34dd044166a47f0bc105cf44b75af80') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:33:16', '17caa94c1ef643d18ed1edf8ac92fca5') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:33:16', '6cb8d406aa0443348d0f8da784b0659f') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.created', 'group', 'd823bbbf-f158-437a-ae7b-4e636c588df0', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787070797", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:33:17', '93a066ef19de486c9585904d3d7dc8da') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "8503a150-bf60-48f5-8658-33d9504d7bf3", "role_name": "Group Member"}', 'null', '2026-08-18 16:33:19', '3172f9331175470ca99cff93af889a18') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:02', 'b5449ba0a14c476ca1e2662876d5cddb') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:03', 'e8397f9ffe95475db8236d7f08a04bc5') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:04', '579115f06f9445ad80e4e4f9de393eed') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:05', 'fed139c0c205436f90a46eda2294cbcf') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:05', '0080ef69de7c438eb1db4ca2cf5d9ba4') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'auth.login_success', 'user', '2e2e7ea8-3054-4d08-9942-546c4a529c09', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:22', 'b54147a739a54a6ba3ae1f915760a22f') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:23', '439d4ee8dfbc4ced96d6c1a2bc57b3c8') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:23', '803e084af7c44e6a86a0966f43fdef9e') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:24', '2a9e08fed2024fd690195f5ba85118f0') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:25', 'f14edec3753e4721913d7d7a7bd72636') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'group.created', 'group', '66f65ec0-a63f-4a18-b1b4-139f3f6b9dff', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787070865", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:34:26', '2097a5c8f9be49218f953bab8ae9e146') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:55', '00961c9e8aaa4cfba53a8dc35e37a2ce') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:56', 'e13096fb0c0f42ef83a482c66cb0be25') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:57', 'aa1b3ce4e07e4b51bb154cea2fca1073') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:58', '3fb6dd9fb87b480d9e5f25fdca855d59') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:34:59', '261eb7d2cdba494b86f6dd5d7ee8d5b3') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', '1f5c6360-1ff6-440e-80fe-a765eac0703b', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787070899", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:34:59', 'ec7c3b1511b24232a130b63fe19811ce') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:07', '45972eaec1014a78ba7ec8114e7854df') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:08', 'c432c20c10a043a98166c013b4d24b38') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:09', '946fd51979cd4ff5b6f10879fe7b87aa') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:09', '80f7f0521a0a46088409a86c991019e9') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:10', '1fa954d994704f7f9582fc8549e9340a') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', 'bda645ff-6287-4e34-a4f2-27812a1e2111', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787070910", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:35:11', '79b9e96cfdf2438188080e07f5fb6843') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "647a7062-9402-44e0-95f4-ed1d4c105d34", "role_name": "Group Member"}', 'null', '2026-08-18 16:35:13', 'eca0a1cf402c423a97a93802b2b61035') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:45', '5719f366e7b4406499cd16ff028c7606') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:45', 'a78d433eedaf4e93858c54850f9429ba') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:46', 'abec46ce3cd84ee2a28006be34051dee') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:47', '103a61854b6c47ebb9ecfd52dd8fd2ee') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:35:48', 'e8fdb9af9bce4ccba0c800261beb32b7') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', '58e51653-d2e1-4ea4-9638-3a6415d8ad8e', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787070948", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:35:48', 'ec148e937a974557b4b023edf9b16d78') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "3b0d17e2-3a5e-4dbc-96ff-5a3c7f8bd520", "role_name": "Group Member"}', 'null', '2026-08-18 16:35:50', '85962ccfc7a34d57a3401f878ae2c9f2') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.invited', 'group', '58e51653-d2e1-4ea4-9638-3a6415d8ad8e', NULL, NULL, '{"invited_user_id": "e3dd1e2b-3c88-4aba-adf7-785009761d99", "invited_username": "charlie"}', 'null', '2026-08-18 16:35:51', '66127a9c345247489ee570bc7d122f42') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'group.invitation.accepted', 'group', '58e51653-d2e1-4ea4-9638-3a6415d8ad8e', NULL, NULL, 'null', 'null', '2026-08-18 16:35:52', '9da64ef32c6741a5b3b65a50c545f8bf') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:36:24', '2f4bf8bb793944948e957b22a499bb8e') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:36:25', '7dd653142d8f4456a69979700f464c21') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:36:26', '7ba2db9472e5482390fa8693f2615557') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:36:27', '755547c9c2e441329af41033bd9cf4a0') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:36:27', '2f4a5236cb934312813ba1846850441d') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', '5ac6c369-9883-4105-af59-825644eb7852', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787070988", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:36:28', '1353e3fcc8fa4e04bb16d41f2c49acf1') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "bad10ce1-efc6-4fc2-bb3b-eadec0b983ee", "role_name": "Group Member"}', 'null', '2026-08-18 16:36:30', 'bee061dcaa114b1798962abf8cf462d7') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.invited', 'group', '5ac6c369-9883-4105-af59-825644eb7852', NULL, NULL, '{"invited_user_id": "e3dd1e2b-3c88-4aba-adf7-785009761d99", "invited_username": "charlie"}', 'null', '2026-08-18 16:36:30', 'ef76783bdfe74361b48cf2f84b73b677') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'group.invitation.accepted', 'group', '5ac6c369-9883-4105-af59-825644eb7852', NULL, NULL, 'null', 'null', '2026-08-18 16:36:31', '5f29e68153b8497abc5cc133b35c96a8') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.invite.created', 'group_invite', 'e8739908-14d0-4245-9ba4-26781a2e5ade', NULL, NULL, '{"group_id": "5ac6c369-9883-4105-af59-825644eb7852", "token": "1s-AKWSC-26BFInASsxWR_Wng6UkJQrC"}', 'null', '2026-08-18 16:36:32', 'aca18ab96dfd4bf7b4ea514ee0ed0e29') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:37:24', '64a1ea8204c444e4a075bb0bc5592e02') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:37:25', '781d3897032447748b98403b54a16365') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:37:26', 'be907b0067b2430cbce82896fe07d3c8') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:37:27', '780c9472fe77490090de1bfea0737539') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:37:27', 'd50ca96f9e0245719c221950b960f235') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', 'f403ba11-b6b1-4ed8-b767-82dab3a063e5', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787071048", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:37:28', '9d350bc5885d43608184b7a27b76205e') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "164e6379-4727-4afc-b020-b4ea042acdcf", "role_name": "Group Member"}', 'null', '2026-08-18 16:37:30', 'a849261c9d0b42899f13953509e5a395') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.invited', 'group', 'f403ba11-b6b1-4ed8-b767-82dab3a063e5', NULL, NULL, '{"invited_user_id": "e3dd1e2b-3c88-4aba-adf7-785009761d99", "invited_username": "charlie"}', 'null', '2026-08-18 16:37:30', 'fe5278a376a94d3f8c6cd8b961187ab3') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'group.invitation.accepted', 'group', 'f403ba11-b6b1-4ed8-b767-82dab3a063e5', NULL, NULL, 'null', 'null', '2026-08-18 16:37:31', '29607941ed7a47a9908243bda2023be4') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.invite.created', 'group_invite', 'db5cf9ba-85c0-4f45-bc9e-e69cabac8c3c', NULL, NULL, '{"group_id": "f403ba11-b6b1-4ed8-b767-82dab3a063e5", "token": "rMMo-bQIRlnGMqxbJmg3Y2s6VDXSTzey"}', 'null', '2026-08-18 16:37:32', '916fc3b56a2641d6a00e714da00b9665') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'group.invite.accepted', 'group', 'f403ba11-b6b1-4ed8-b767-82dab3a063e5', NULL, NULL, '{"token": "rMMo-bQIRlnGMqxbJmg3Y2s6VDXSTzey"}', 'null', '2026-08-18 16:37:32', '033108ef18874a45b33674135ee2f052') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:52:15', '34e5be40fb9045668925c4b83bb48b46') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:52:17', '08eecca30f2c453880eb95cb7fbdbf2e') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:52:18', 'b9a07b5b7545469b9a95f873ab22b6a6') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 16:52:18', 'f16cc9055e2d48b1a89fd8a9e9f79f06') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', '768c06f8-659c-4d47-bcc1-0383299d0182', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787071939", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 16:52:19', '07ada3e4ea0645ed9098a9068c3476ef') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "ab131c68-d8c7-4af1-9890-df3602488b42", "role_name": "Group Member"}', 'null', '2026-08-18 16:52:22', '07f5b44ef30f438b997b592b61067281') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.invited', 'group', '768c06f8-659c-4d47-bcc1-0383299d0182', NULL, NULL, '{"invited_user_id": "e3dd1e2b-3c88-4aba-adf7-785009761d99", "invited_username": "charlie"}', 'null', '2026-08-18 16:52:22', '81b8d0720d5d47e48adcade8b1b082be') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'group.invitation.accepted', 'group', '768c06f8-659c-4d47-bcc1-0383299d0182', NULL, NULL, 'null', 'null', '2026-08-18 16:52:23', 'f24a4b3adb1145a580e715a9f7159374') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.invite.created', 'group_invite', '2699243e-febf-4393-988e-2af8637bc07f', NULL, NULL, '{"group_id": "768c06f8-659c-4d47-bcc1-0383299d0182", "token": "9vC5-5CWX12L1Ruq_MtGUnOAm4gYCzVA"}', 'null', '2026-08-18 16:52:24', 'f8e2b8ab1f1f4d48849c196123483337') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'group.invite.accepted', 'group', '768c06f8-659c-4d47-bcc1-0383299d0182', NULL, NULL, '{"token": "9vC5-5CWX12L1Ruq_MtGUnOAm4gYCzVA"}', 'null', '2026-08-18 16:52:24', '1dae53c1bdc14f85a5c0a69008752927') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 16:56:35', '7a6d9b1fc7c746a0abc4a0b990a018c3') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 16:57:09', '26501bb6da344347b549229dd0d06f0c') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'auth.login_success', 'user', '2e2e7ea8-3054-4d08-9942-546c4a529c09', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 16:57:19', '8f3bd169e8a3490183a1f1e34cbd1ef0') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 16:57:26', 'b5c65edc1487403eb9f4f0e4cb565dd8') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:33', '957be90a712c4dda80c5ccc286905385') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:33', 'ca452e1903bc4c77bd2203cf8a6dfce5') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:33', 'c7756df3b87e4df097a986f5c5889782') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:34', '9a74ed9f03d1459997d50a4b720add5c') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:44', 'b9bf5ee4818b45f5b6585aeedf295533') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:45', '5ee33d1803394cd2823e54dabce75424') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:45', 'd3af0077077740a9a5d2f1685daf71cc') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:45', '26ea0b20b9174aca8ecfff9a25c89de0') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:46', 'aa04bb36d473432fb112ea0358273996') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', 'cded2597-0346-4294-a1f2-830f87e3386b', NULL, NULL, '{"name": "Strict Classified Ops", "slug": "classified-ops-1787072566147", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 17:02:46', '5a7b3bf2e9914acb998804aac16e6a77') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.members.added', 'group', 'cded2597-0346-4294-a1f2-830f87e3386b', NULL, NULL, '{"added": ["e3dd1e2b-3c88-4aba-adf7-785009761d99"], "role_id": "d9ebd809-c471-4f82-99b0-2772a9f5d490"}', 'null', '2026-08-18 17:02:46', '5e8c53fba031484593d9d83d372da882') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.removed', 'group', 'cded2597-0346-4294-a1f2-830f87e3386b', NULL, NULL, '{"removed_user_id": "e3dd1e2b-3c88-4aba-adf7-785009761d99"}', 'null', '2026-08-18 17:02:46', 'a388543977844843b4d78a0ec193620d') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:50', '9fe9ee8b66494b6eb2fc8f022e8a7136') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('1f56d5d3b607485eaef0467198e9414c', 'auth.login_success', 'user', '1f56d5d3-b607-485e-aef0-467198e9414c', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:51', '5ea0794a3d8443aabde0ac52bafbbbce') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'auth.login_success', 'user', 'e3dd1e2b-3c88-4aba-adf7-785009761d99', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:51', 'c71352b03b004d44b3c60b1619ce409a') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'auth.login_success', 'user', '8b0a8684-cdad-4a55-a641-b2b9d3d73212', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:52', 'd0f9608f084944698d48a3373f637077') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8039c19ab09a492bb941f17eeeeff4bd', 'auth.login_success', 'user', '8039c19a-b09a-492b-b941-f17eeeeff4bd', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:02:53', '2c99d4b0fe1c4fd192087aadc7302000') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.created', 'group', '6ab63fca-4e86-47d1-9ea7-0be346f24ecc', NULL, NULL, '{"name": "Secret View-Only Squad", "slug": "secret-squad-1787072573", "visibility": "private", "initial_members": 2}', 'null', '2026-08-18 17:02:54', 'c37bcc9e1b404312a192bb4266ba5449') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.role_assigned', 'group_member', '1f56d5d3-b607-485e-aef0-467198e9414c', NULL, NULL, '{"role_id": "cff7519e-9fc4-44b4-93c8-71cd9ebc4f62", "role_name": "Group Member"}', 'null', '2026-08-18 17:02:56', '68db7e77aaa64b5dbe143e8713785250') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.member.invited', 'group', '6ab63fca-4e86-47d1-9ea7-0be346f24ecc', NULL, NULL, '{"invited_user_id": "e3dd1e2b-3c88-4aba-adf7-785009761d99", "invited_username": "charlie"}', 'null', '2026-08-18 17:02:57', '2da8ca6bb5ba425c90cf2046e27a5f88') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('e3dd1e2b3c884abaadf7785009761d99', 'group.invitation.accepted', 'group', '6ab63fca-4e86-47d1-9ea7-0be346f24ecc', NULL, NULL, 'null', 'null', '2026-08-18 17:02:58', '6abc44bc785642018347297e9061248c') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.invite.created', 'group_invite', 'f1ce4406-a742-479f-a786-fe89e258c4d3', NULL, NULL, '{"group_id": "6ab63fca-4e86-47d1-9ea7-0be346f24ecc", "token": "QkEiZSOjWO8JlNK-FLzXANJ2WOTExPHH"}', 'null', '2026-08-18 17:02:58', '08038390aba147db91aaaec65a6b391b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('8b0a8684cdad4a55a641b2b9d3d73212', 'group.invite.accepted', 'group', '6ab63fca-4e86-47d1-9ea7-0be346f24ecc', NULL, NULL, '{"token": "QkEiZSOjWO8JlNK-FLzXANJ2WOTExPHH"}', 'null', '2026-08-18 17:02:59', 'df6b0f85311f4506add69a53979ab7ec') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:12:10', 'd8fcb53710f4424c87596ef7ad331898') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:12:11', '50a7f9b62e594fd1882d6d4f37dc3e65') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.created', 'group', '980fecb9-691c-4b81-821b-5c0722b249c3', NULL, NULL, '{"name": "Secret Project Horizon", "slug": "secret-horizon-1787073131025", "visibility": "private", "initial_members": 1}', 'null', '2026-08-18 17:12:11', 'f10e9d5712654738bdf4c65403ad0ed2') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:12:54', '11728e1449a54e1c81be304de6bfdf6a') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:12:54', '4460efcfecfb4ff6999d477148ca684d') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.created', 'group', '0d6ac5f5-f18f-4960-83f0-56751855e85b', NULL, NULL, '{"name": "Secret Project Horizon", "slug": "secret-horizon-1787073174800", "visibility": "private", "initial_members": 1}', 'null', '2026-08-18 17:12:54', '944dfb58919943e6a68abc8e3ead543f') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.force_message_override.activated', 'group', '0d6ac5f5-f18f-4960-83f0-56751855e85b', NULL, NULL, '{"duration_seconds": 120, "expires_at": "2026-08-18T17:14:54.915178+00:00"}', 'null', '2026-08-18 17:12:54', '2210251077a844a89a4b1fd380531a33') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:16:57', 'd6634ed956f8438bb75746590924840c') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:16:58', '536db8b44c614acb9d84065f155574ee') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:22:19', '69a8b70723f04d47b0a6c92394d88136') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:22:19', 'a6cdf22f3ac44423861047368920e788') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:38:12', '1aa9133a26dd43128683a0e30df57f1d') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:38:13', '0a7edaba2e564bada2b283e49ce78124') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.deleted', 'group', '980fecb9-691c-4b81-821b-5c0722b249c3', NULL, NULL, '{"name": "Secret Project Horizon"}', 'null', '2026-08-18 17:38:13', '552d0809e4c14fb081c9edf17b961e48') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.deleted', 'group', '0d6ac5f5-f18f-4960-83f0-56751855e85b', NULL, NULL, '{"name": "Secret Project Horizon"}', 'null', '2026-08-18 17:38:13', '75846e53077740d583dd429598ac9429') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.created', 'group', '0952500d-4282-4c6d-9ef6-3214b3873bd8', NULL, NULL, '{"name": "Secret Project Horizon", "slug": "secret-horizon-1787074693284", "visibility": "private", "initial_members": 1}', 'null', '2026-08-18 17:38:13', '78142bb0861f4665be45a78aa30bc2ed') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.force_message_override.activated', 'group', '0952500d-4282-4c6d-9ef6-3214b3873bd8', NULL, NULL, '{"duration_seconds": 120, "expires_at": "2026-08-18T17:40:13.423483+00:00"}', 'null', '2026-08-18 17:38:13', '1075574cbd5846159f80220ddd0e2173') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 17:38:34', 'be36b55d678c44f8872a14551159d67b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('2e2e7ea830544d089942546c4a529c09', 'auth.login_success', 'user', '2e2e7ea8-3054-4d08-9942-546c4a529c09', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 17:38:52', 'c47f302da2034a58ae2340448536f701') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('5e25e9f8a22c4f799b009a6923497289', 'auth.login_success', 'user', '5e25e9f8-a22c-4f79-9b00-9a6923497289', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 17:38:58', '0fddd638cc804c08a6422d24b6c27b81') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('417fd4d288524a3f97a119bbbc825c5f', 'auth.login_success', 'user', '417fd4d2-8852-4a3f-97a1-19bbbc825c5f', '192.168.1.14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36', 'null', 'null', '2026-08-18 17:39:26', 'b43e97a5f3b04094a95424b9da2021e6') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:45:43', '5b8cbce6cc054ed899042b69a442f71c') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'auth.login_success', 'user', '9d82cd1e-2c44-4a64-a663-477765a035d5', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:57:21', '350fb14f6c1c41ae8a7293e036cfed59') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 17:57:21', '7a2b5cbe8a7943248fc34df99a8831f2') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.deleted', 'group', '0952500d-4282-4c6d-9ef6-3214b3873bd8', NULL, NULL, '{"name": "Secret Project Horizon"}', 'null', '2026-08-18 17:57:22', '8da515662d9e43ac8a5e06f2ceb761de') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('9d82cd1e2c444a64a663477765a035d5', 'group.created', 'group', 'badb89db-8703-4418-930c-fba58a28f1ad', NULL, NULL, '{"name": "Secret Project Horizon", "slug": "secret-horizon-1787075842042", "visibility": "private", "initial_members": 1}', 'null', '2026-08-18 17:57:22', '7d341159b73644eda80593ea56b13446') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'group.force_message_override.activated', 'group', 'badb89db-8703-4418-930c-fba58a28f1ad', NULL, NULL, '{"duration_seconds": 120, "expires_at": "2026-08-18T17:59:22.243856+00:00"}', 'null', '2026-08-18 17:57:22', 'fe3880bd30fc40a096c51f7118cd7102') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 18:20:59', '0a49918b9a5c4c6ea85ec275900b539a') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182059_b0dbd5', NULL, NULL, '{"filename": "backup_20260818_182059_b0dbd5.vault.zip", "tables": 18, "size_bytes": 67931608, "formatted_title": "Website Backup 18/08/26 18:20:59 & Database backup 18/08/26 18:20:59"}', 'null', '2026-08-18 18:21:09', '342b322045a04a3b8f197366fc3d355b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182109_7b7102', NULL, NULL, '{"filename": "backup_20260818_182109_7b7102.vault.zip", "tables": 18, "size_bytes": 67931777, "formatted_title": "Website Backup 18/08/26 18:21:09 & Database backup 18/08/26 18:21:09"}', 'null', '2026-08-18 18:21:18', '0d31ec6c6bd64e5d9448b36dd1296a5b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182119_25233d', NULL, NULL, '{"filename": "backup_20260818_182119_25233d.vault.zip", "tables": 18, "size_bytes": 67931832, "formatted_title": "Website Backup 18/08/26 18:21:19 & Database backup 18/08/26 18:21:19"}', 'null', '2026-08-18 18:21:28', '9c39e933eae7476f9a4c72554492fdcd') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182128_2d0392', NULL, NULL, '{"filename": "backup_20260818_182128_2d0392.vault.zip", "tables": 18, "size_bytes": 67931883, "formatted_title": "Website Backup 18/08/26 18:21:28 & Database backup 18/08/26 18:21:28"}', 'null', '2026-08-18 18:21:38', 'a5afba3127ac4bae94768e394c20e797') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182138_512b3b', NULL, NULL, '{"filename": "backup_20260818_182138_512b3b.vault.zip", "tables": 18, "size_bytes": 67931939, "formatted_title": "Website Backup 18/08/26 18:21:38 & Database backup 18/08/26 18:21:38"}', 'null', '2026-08-18 18:21:48', 'aa608816a96d402fbc554f1ba7308f47') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182148_d988cf', NULL, NULL, '{"filename": "backup_20260818_182148_d988cf.vault.zip", "tables": 18, "size_bytes": 65505070, "formatted_title": "Website Backup 18/08/26 18:21:48 & Database backup 18/08/26 18:21:48"}', 'null', '2026-08-18 18:21:58', '5fad39e6d34b417d968d196925ea77ad') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182158_45c2d1', NULL, NULL, '{"filename": "backup_20260818_182158_45c2d1.vault.zip", "tables": 18, "size_bytes": 67932050, "formatted_title": "Website Backup 18/08/26 18:21:58 & Database backup 18/08/26 18:21:58"}', 'null', '2026-08-18 18:22:08', 'c6322b70e6824c2ab4a639070752dfd1') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'auth.login_success', 'user', '3dfcccaa-b1d1-40b4-a979-acf5f4d7d613', '127.0.0.1', 'python-httpx/0.28.1', 'null', 'null', '2026-08-18 18:22:29', '2f31d9e5cc754f008de04784f633f396') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182229_c3d11e', NULL, NULL, '{"filename": "backup_20260818_182229_c3d11e.vault.zip", "tables": 18, "size_bytes": 67933967, "formatted_title": "Website Backup 18/08/26 18:22:29 & Database backup 18/08/26 18:22:29"}', 'null', '2026-08-18 18:22:38', 'a9148b8fe30c4b89b05e189e5611ada6') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182238_e972b2', NULL, NULL, '{"filename": "backup_20260818_182238_e972b2.vault.zip", "tables": 18, "size_bytes": 67934023, "formatted_title": "Website Backup 18/08/26 18:22:38 & Database backup 18/08/26 18:22:38"}', 'null', '2026-08-18 18:22:48', '5d2ccedfa6f04f18a368d56b7f65e474') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182248_d61427', NULL, NULL, '{"filename": "backup_20260818_182248_d61427.vault.zip", "tables": 18, "size_bytes": 67934080, "formatted_title": "Website Backup 18/08/26 18:22:48 & Database backup 18/08/26 18:22:48"}', 'null', '2026-08-18 18:22:58', '3a0a5c8576f04dd4ad0ff9c7436ce45b') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182258_a6ccf1', NULL, NULL, '{"filename": "backup_20260818_182258_a6ccf1.vault.zip", "tables": 18, "size_bytes": 67934128, "formatted_title": "Website Backup 18/08/26 18:22:58 & Database backup 18/08/26 18:22:58"}', 'null', '2026-08-18 18:23:08', '87d0414bd4d2489dab06f3c0b9df8f62') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182308_f49e9b', NULL, NULL, '{"filename": "backup_20260818_182308_f49e9b.vault.zip", "tables": 18, "size_bytes": 67934183, "formatted_title": "Website Backup 18/08/26 18:23:08 & Database backup 18/08/26 18:23:08"}', 'null', '2026-08-18 18:23:18', '71575e26babd4720830dc7a6f35b9c49') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182318_58d3dc', NULL, NULL, '{"filename": "backup_20260818_182318_58d3dc.vault.zip", "tables": 18, "size_bytes": 67934236, "formatted_title": "Website Backup 18/08/26 18:23:18 & Database backup 18/08/26 18:23:18"}', 'null', '2026-08-18 18:23:28', 'b4e15763d4b142ad9d5ac9f27adeb7fa') ON CONFLICT DO NOTHING;
INSERT INTO public.audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, details, changes, created_at, id) VALUES ('3dfcccaab1d140b4a979acf5f4d7d613', 'admin.backup.created', 'backup', 'backup_20260818_182328_b3537f', NULL, NULL, '{"filename": "backup_20260818_182328_b3537f.vault.zip", "tables": 18, "size_bytes": 67934293, "formatted_title": "Website Backup 18/08/26 18:23:28 & Database backup 18/08/26 18:23:28"}', 'null', '2026-08-18 18:23:38', 'a4c80fd127ef4aa99be3c2d37a38ce51') ON CONFLICT DO NOTHING;
