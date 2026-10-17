-- Vura backend: Row Level Security. Run last.

alter table public.users enable row level security;
alter table public.wallet enable row level security;
alter table public.transactions enable row level security;
alter table public.goals enable row level security;
alter table public.groups enable row level security;
alter table public.group_recipients enable row level security;
alter table public.chama_types enable row level security;
alter table public.chama_groups enable row level security;
alter table public.chama_members enable row level security;
alter table public.chama_contribution enable row level security;
alter table public.chama_payouts enable row level security;
alter table public.chats enable row level security;
alter table public.chat_participants enable row level security;
alter table public.messages enable row level security;
alter table public.user_presence enable row level security;
alter table public.notifications enable row level security;
alter table public.polls enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Clients may only edit safe profile columns (never role or is_verified)
revoke update on public.users from authenticated;
grant update (display_name, phone_number, bio, avatar_url, currency, notifications_enabled,
              "autoSaveMedia", muted_user_ids, blocked_user_ids, updated_at)
  on public.users to authenticated;

-- Users
create policy users_read on public.users for select to authenticated using (true);
create policy users_insert on public.users for insert to authenticated with check (id = auth.uid());
create policy users_update on public.users for update to authenticated using (id = auth.uid());

-- Wallet and transactions (writes happen through RPC functions only)
create policy wallet_read on public.wallet for select to authenticated using (user_id = auth.uid());
create policy tx_read on public.transactions for select to authenticated
  using (user_id = auth.uid() or (chama_id is not null and public.is_chama_member(chama_id)));

-- Goals
create policy goals_own on public.goals for all to authenticated
  using (user_id = auth.uid() or created_by = auth.uid())
  with check (user_id = auth.uid() or created_by = auth.uid());

-- Group Pay
create policy groups_own on public.groups for all to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy group_recipients_own on public.group_recipients for all to authenticated
  using (exists (select 1 from groups g where g.id = group_id and g.created_by = auth.uid()))
  with check (exists (select 1 from groups g where g.id = group_id and g.created_by = auth.uid()));

-- Chamas
create policy chama_types_read on public.chama_types for select to authenticated using (true);
create policy chama_groups_read on public.chama_groups for select to authenticated
  using (admin_id = auth.uid() or public.is_chama_member(id));
create policy chama_groups_insert on public.chama_groups for insert to authenticated with check (admin_id = auth.uid());
create policy chama_groups_update on public.chama_groups for update to authenticated using (admin_id = auth.uid());
create policy chama_groups_delete on public.chama_groups for delete to authenticated using (admin_id = auth.uid());

create policy cm_read on public.chama_members for select to authenticated
  using (user_id = auth.uid() or public.is_chama_member(chama_id));
create policy cm_insert on public.chama_members for insert to authenticated
  with check (user_id = auth.uid()
    or exists (select 1 from chama_groups g where g.id = chama_id and g.admin_id = auth.uid()));
create policy cm_update on public.chama_members for update to authenticated
  using (user_id = auth.uid()
    or exists (select 1 from chama_groups g where g.id = chama_id and g.admin_id = auth.uid()));
create policy cm_delete on public.chama_members for delete to authenticated
  using (user_id = auth.uid()
    or exists (select 1 from chama_groups g where g.id = chama_id and g.admin_id = auth.uid()));

create policy contrib_read on public.chama_contribution for select to authenticated
  using (user_id = auth.uid() or public.is_chama_member(chama_id));
create policy payouts_read on public.chama_payouts for select to authenticated
  using (user_id = auth.uid() or public.is_chama_member(chama_id));

-- Chat
create policy chats_read on public.chats for select to authenticated using (public.can_access_chat(id));
create policy chats_insert on public.chats for insert to authenticated with check (true);
create policy cp_read on public.chat_participants for select to authenticated using (public.can_access_chat(chat_id));
create policy cp_insert on public.chat_participants for insert to authenticated with check (true);
create policy messages_read on public.messages for select to authenticated using (public.can_access_chat(chat_id));
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.can_access_chat(chat_id));

-- Presence and notifications
create policy presence_read on public.user_presence for select to authenticated using (true);
create policy presence_write on public.user_presence for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_read on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notif_update on public.notifications for update to authenticated using (user_id = auth.uid());

-- Polls
create policy polls_read on public.polls for select to authenticated using (true);
create policy polls_insert on public.polls for insert to authenticated with check (creator_id = auth.uid());
