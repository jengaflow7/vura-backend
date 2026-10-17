-- Vura backend: helper functions, RPCs and triggers. Run after 01_schema.sql.

-- Helpers used by RLS policies
create or replace function public.is_chama_member(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from chama_members
    where chama_id = cid and user_id = auth.uid() and status = 'active'
  );
$$;

create or replace function public.can_access_chat(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_participants where chat_id = cid and user_id = auth.uid());
$$;

-- Signup: create profile and wallet
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into users (id, email, display_name, phone_number)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)), new.phone)
  on conflict (id) do nothing;
  insert into wallet (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- New chama: add creator as admin, create group chat, link it
create or replace function public.handle_new_chama_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_chat uuid;
begin
  insert into chama_members (chama_id, user_id, role, status) values (new.id, new.admin_id, 'admin', 'active');
  insert into chats (type, chama_id) values ('group', new.id) returning id into v_chat;
  insert into chat_participants (chat_id, user_id, role) values (v_chat, new.admin_id, 'admin');
  update chama_groups set chat_id = v_chat, member_ids = array[new.admin_id] where id = new.id;
  return new;
end $$;

drop trigger if exists trg_new_chama_group on public.chama_groups;
create trigger trg_new_chama_group
  after insert on public.chama_groups for each row execute function public.handle_new_chama_group();

-- Respect the user's notification preference
create or replace function public.respect_notification_pref()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from users where id = new.user_id and notifications_enabled = false) then
    return null;
  end if;
  return new;
end $$;

drop trigger if exists trg_respect_notification_pref on public.notifications;
create trigger trg_respect_notification_pref
  before insert on public.notifications for each row execute function public.respect_notification_pref();

-- Find or create a private chat with another user
create or replace function public.get_or_create_private_chat(p_other_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := auth.uid(); v_chat uuid;
begin
  if v_me is null then return jsonb_build_object('success', false, 'error', 'not authenticated'); end if;
  select c.id into v_chat
  from chats c
  join chat_participants a on a.chat_id = c.id and a.user_id = v_me
  join chat_participants b on b.chat_id = c.id and b.user_id = p_other_user_id
  where c.type = 'private' limit 1;
  if v_chat is null then
    insert into chats (type) values ('private') returning id into v_chat;
    insert into chat_participants (chat_id, user_id) values (v_chat, v_me), (v_chat, p_other_user_id);
  end if;
  return jsonb_build_object('success', true, 'chat_id', v_chat);
end $$;

-- Move money from wallet into a personal goal (atomic)
create or replace function public.deposit_to_goal(p_user_id uuid, p_goal_id uuid, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_wallet wallet%rowtype;
begin
  if auth.uid() is distinct from p_user_id then
    return jsonb_build_object('success', false, 'error', 'not allowed');
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('success', false, 'error', 'invalid amount');
  end if;

  select * into v_wallet from wallet where user_id = p_user_id for update;
  if not found or v_wallet.balance < p_amount then
    return jsonb_build_object('success', false, 'error', 'insufficient balance');
  end if;

  update goals set current_amount = current_amount + p_amount,
                   is_complete = (current_amount + p_amount) >= target_amount,
                   updated_at = now()
  where id = p_goal_id and user_id = p_user_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'goal not found');
  end if;

  update wallet set balance = balance - p_amount, updated_at = now() where id = v_wallet.id;

  insert into transactions (user_id, wallet_id, type, amount, status, goal_id, title, payment_method)
  values (p_user_id, v_wallet.id, 'goal_deposit', p_amount, 'success', p_goal_id, 'Goal deposit', 'Wallet');

  return jsonb_build_object('success', true);
end $$;

-- Admin-only edit of a chama's rules or updates list
create or replace function public.chama_edit_list(p_chama_id uuid, p_field text, p_op text, p_value text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from chama_members
                 where chama_id = p_chama_id and user_id = auth.uid() and role = 'admin' and status = 'active') then
    raise exception 'admin only';
  end if;
  if p_field = 'rules' then
    update chama_groups set rules = case p_op when 'add' then array_append(rules, p_value)
                                              else array_remove(rules, p_value) end where id = p_chama_id;
  elsif p_field = 'updates' then
    update chama_groups set updates = case p_op when 'add' then array_append(updates, p_value)
                                                else array_remove(updates, p_value) end where id = p_chama_id;
  else
    raise exception 'invalid field';
  end if;
end $$;
