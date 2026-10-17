-- Vura backend: core schema (PostgreSQL / Supabase)
-- Run first. Investment tables (investment, assets, portfolio) are omitted here.

create extension if not exists pgcrypto;

do $$ begin
  create type payment_methods as enum ('Wallet', 'Mpesa', 'Bank');
exception when duplicate_object then null; end $$;

-- Users (profile row linked to auth.users)
create table if not exists public.users (
  id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  display_name text,
  email text,
  phone_number text,
  avatar_url text default 'https://ui-avatars.com/api/?name=User&background=4c4dd6&color=fff&size=256',
  role text not null default 'user',
  is_verified boolean not null default false,
  bio text,
  currency text default 'KES',
  notifications_enabled boolean not null default true,
  "autoSaveMedia" boolean default false,
  muted_user_ids uuid[] default '{}',
  blocked_user_ids uuid[] default '{}'
);

-- Wallet (one per user)
create table if not exists public.wallet (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.users(id) on delete cascade,
  balance numeric(14,2) not null default 0 check (balance >= 0),
  currency text not null default 'KES' check (currency in ('KES', 'USD')),
  updated_at timestamptz not null default now()
);

-- Chat tables (chats first, so chama_groups can reference it)
create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('private', 'group')),
  chama_id uuid,
  created_at timestamptz not null default now()
);

-- Chama (savings group) tables
create table if not exists public.chama_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_active boolean not null default true
);

create table if not exists public.chama_groups (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  type text not null,
  rotation_mode text check (rotation_mode in ('random', 'sequential')),
  admin_id uuid not null default auth.uid() references public.users(id),
  currency text default 'KES',
  contribution_amount numeric(14,2),
  max_members int,
  status text not null default 'active',
  target_amount numeric(14,2),
  target_date timestamptz,
  rules text[] default '{}',
  updates text[] default '{}',
  announcement text,
  latest_announcement text,
  pinned_message text,
  wallet_balance numeric(14,2) not null default 0,
  image_url text,
  member_ids uuid[] default '{}',
  rotation_phase int,
  vote_to_randomize_approved boolean default false,
  bio text,
  chat_id uuid references public.chats(id),
  constraint chama_groups_type_check
    check (type in ('Chama pool', 'Invest pool', 'Rotation', 'Community pool'))
);

alter table public.chats
  add constraint chats_chama_fk foreign key (chama_id) references public.chama_groups(id) on delete cascade;

insert into public.chama_types (name, description) values
  ('Chama pool', 'Members contribute to a shared pool'),
  ('Invest pool', 'Members invest together'),
  ('Rotation', 'Members take turns receiving the pot'),
  ('Community pool', 'Open community savings')
on conflict (name) do nothing;

create table if not exists public.chama_members (
  id uuid primary key default gen_random_uuid(),
  joint_at timestamptz not null default now(),
  chama_id uuid not null references public.chama_groups(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member', 'treasurer')),
  status text not null default 'active' check (status in ('active', 'left', 'banned')),
  payout_position int,
  has_received_payout boolean not null default false,
  photo_url text,
  is_pinned boolean not null default false,
  unique (chama_id, user_id)
);

-- Group Pay (separate from chamas)
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null default auth.uid() references public.users(id),
  total_amount numeric(14,2) not null default 0
);

create table if not exists public.group_recipients (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  recipient_user_id uuid references public.users(id),
  recipient_name text,
  phone_number text,
  amount numeric(14,2) not null default 0,
  status text default 'pending'
);

-- Personal savings goals
create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  target_amount numeric(14,2) not null,
  current_amount numeric(14,2) not null default 0,
  is_complete boolean not null default false,
  "targetDate" timestamptz,
  user_id uuid default auth.uid() references public.users(id),
  created_by uuid default auth.uid(),
  chama_id uuid references public.chama_groups(id) on delete set null,
  group_id uuid references public.groups(id) on delete set null,
  updated_at timestamptz default now()
);

-- Transactions
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references public.users(id),
  wallet_id uuid not null references public.wallet(id),
  type text not null check (type in (
    'deposit','withdrawal','transfer_out','transfer_in','chama_deposit','chama_payout',
    'buy','sell','dividend','bill_payment','lock_savings','goal_deposit','goal_withdrawal')),
  amount numeric(14,2) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending','success','failed')),
  reference text,
  goal_id uuid references public.goals(id),
  chama_id uuid references public.chama_groups(id),
  investment_id uuid,
  category text,
  title text,
  note text,
  payment_method payment_methods not null default 'Wallet'
);

create table if not exists public.chama_contribution (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  chama_id uuid not null references public.chama_groups(id) on delete cascade,
  user_id uuid not null references public.users(id),
  amount numeric(14,2) not null check (amount > 0),
  payment_method text check (payment_method in ('wallet', 'mpesa', 'bank')),
  status text not null default 'pending' check (status in ('pending', 'success', 'failed')),
  reference text
);

create table if not exists public.chama_payouts (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  chama_id uuid not null references public.chama_groups(id) on delete cascade,
  user_id uuid not null references public.users(id),
  amount numeric(14,2) not null,
  reason text,
  cycle_number int,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  reference text,
  sequence_number int,
  request_type text,
  processing_fee numeric(14,2) default 0,
  approvals_count int default 0,
  required_approvals int,
  phase text
);

-- Chat, presence, notifications
create table if not exists public.chat_participants (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text default 'member',
  is_pinned boolean not null default false
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null references public.users(id),
  message text,
  message_type text not null default 'text',
  media_url text,
  amount numeric(14,2),
  status text default 'sent',
  created_at timestamptz not null default now()
);

create table if not exists public.user_presence (
  user_id uuid primary key references public.users(id) on delete cascade,
  last_seen timestamptz,
  last_active timestamptz,
  is_online boolean not null default false
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  title text,
  body text,
  type text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- Polls (chama requests and votes)
create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references public.groups(id),
  creator_id uuid not null references public.users(id),
  title text,
  amount numeric(14,2) not null,
  status text not null default 'open',
  yes_votes uuid[] default '{}',
  no_votes uuid[] default '{}',
  required_approval_count int,
  request_type text default 'normal' check (request_type in ('normal', 'urgent')),
  fee_percentage numeric(5,2) default 0,
  net_amount numeric(14,2) generated always as (amount - (amount * fee_percentage / 100)) stored
);

create index if not exists idx_transactions_user on public.transactions(user_id, created_at desc);
create index if not exists idx_messages_chat on public.messages(chat_id, created_at);
create index if not exists idx_chama_members_user on public.chama_members(user_id);
