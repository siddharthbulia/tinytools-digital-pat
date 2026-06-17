-- Digital Pat v2.3 — friend graph (Model A). Replaces the Room/invite-code model with mutual
-- 1:1 friendships. Applied via the Management API database/query endpoint.

create extension if not exists pgcrypto;

-- one canonical row per pair (a_uid < b_uid)
create table if not exists public.friendships (
  a_uid uuid references auth.users(id) on delete cascade,
  b_uid uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a_uid, b_uid),
  check (a_uid < b_uid)
);

-- an invite token that, when accepted, creates a friendship TO the inviter
create table if not exists public.friend_invites (
  token uuid primary key default gen_random_uuid(),
  inviter uuid not null references auth.users(id) on delete cascade,
  multi_use boolean not null default false,
  revoked boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days')
);
create index if not exists friend_invites_inviter_idx on public.friend_invites(inviter);

-- is the current user friends with p_other?
create or replace function public.is_friend(p_other uuid)
returns boolean language sql security definer stable set search_path=public as $$
  select exists(
    select 1 from public.friendships
    where a_uid = least(auth.uid(), p_other) and b_uid = greatest(auth.uid(), p_other)
  );
$$;

-- create an invite (returns the token)
create or replace function public.create_invite(p_multi boolean default false)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_token uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.friend_invites(inviter, multi_use) values (auth.uid(), coalesce(p_multi,false))
    returning token into v_token;
  return v_token;
end $$;

-- accept an invite → create the mutual friendship; returns the inviter uid
create or replace function public.accept_invite(p_token uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_inv public.friend_invites;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into v_inv from public.friend_invites where token = p_token;
  if v_inv.token is null then raise exception 'invalid invite'; end if;
  if v_inv.revoked then raise exception 'invite already used or revoked'; end if;
  if v_inv.expires_at < now() then raise exception 'invite expired'; end if;
  if v_inv.inviter = auth.uid() then raise exception 'cannot add yourself'; end if;
  insert into public.friendships(a_uid, b_uid)
    values (least(v_inv.inviter, auth.uid()), greatest(v_inv.inviter, auth.uid()))
    on conflict do nothing;
  if not v_inv.multi_use then update public.friend_invites set revoked = true where token = v_inv.token; end if;
  return v_inv.inviter;
end $$;

-- my friends with their profile (uid + name + character)
create or replace function public.my_friends()
returns table(uid uuid, name text, active_character text)
language sql security definer stable set search_path=public as $$
  select p.uid, p.name, p.active_character
  from public.friendships f
  join public.profiles p on p.uid = case when f.a_uid = auth.uid() then f.b_uid else f.a_uid end
  where f.a_uid = auth.uid() or f.b_uid = auth.uid();
$$;

-- remove a friend (both directions, since the row is canonical)
create or replace function public.remove_friend(p_other uuid)
returns void language sql security definer set search_path=public as $$
  delete from public.friendships
  where a_uid = least(auth.uid(), p_other) and b_uid = greatest(auth.uid(), p_other);
$$;

-- RLS
alter table public.friendships   enable row level security;
alter table public.friend_invites enable row level security;

drop policy if exists fr_read on public.friendships;
create policy fr_read on public.friendships for select to authenticated
  using (a_uid = auth.uid() or b_uid = auth.uid());

drop policy if exists inv_read on public.friend_invites;
create policy inv_read on public.friend_invites for select to authenticated using (inviter = auth.uid());

-- friendships are created only via accept_invite() (SECURITY DEFINER); no direct insert policy.

-- profiles readable by self OR an accepted friend (the Room model is gone, so no room-scope term)
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (uid = auth.uid() or public.is_friend(uid));

-- realtime: broadcast friendship inserts/deletes so the OTHER party syncs live (no restart).
-- replica identity full → DELETE payloads carry both uids so the unfriend reaches both sides.
do $$ begin
  alter publication supabase_realtime add table public.friendships;
exception when duplicate_object then null; end $$;
alter table public.friendships replica identity full;

-- Self-serve account reset (app "Reset Pat…"): delete the CALLING user and everything they own.
-- SECURITY DEFINER so it can remove the auth.users row (which cascades), and the friendship deletes
-- make the user vanish from every friend's graph live. Idempotent / null-safe.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path=public,auth as $fn$
declare me uuid := auth.uid();
begin
  if me is null then return; end if;
  delete from public.friendships where a_uid = me or b_uid = me;
  delete from public.friend_invites where inviter = me;
  delete from public.profiles where uid = me;
  delete from auth.users where id = me;
end $fn$;
grant execute on function public.delete_my_account() to authenticated;
