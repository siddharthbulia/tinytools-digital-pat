-- Digital Pat v2 (Rooms) schema. Applied via the Management API database/query endpoint.
-- Tables: profiles, rooms, room_members, pokes, blocks, usage_counters.
-- Poke send is gated by send_poke() (membership + block + rate-limit). Poke delivery is via
-- Realtime Postgres Changes on `pokes` (respects RLS). Presence/mood is client-published.

create extension if not exists pgcrypto;

-- profiles -----------------------------------------------------------------
create table if not exists public.profiles (
  uid uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'friend',
  active_character text not null default 'cat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- rooms --------------------------------------------------------------------
create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null default 'the Room',
  owner uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.room_members (
  room_id uuid references public.rooms(id) on delete cascade,
  uid uuid references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (room_id, uid)
);

-- pokes --------------------------------------------------------------------
create table if not exists public.pokes (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rooms(id) on delete cascade,
  from_uid uuid references auth.users(id) on delete cascade,
  to_uid uuid references auth.users(id) on delete cascade,
  from_name text,
  from_character text,
  kind text not null default 'poke',  -- 'poke' | 'msg'
  body text,
  created_at timestamptz not null default now()
);
create index if not exists pokes_to_idx on public.pokes(to_uid, created_at desc);
create index if not exists pokes_room_idx on public.pokes(room_id, created_at desc);

-- blocks -------------------------------------------------------------------
create table if not exists public.blocks (
  uid uuid references auth.users(id) on delete cascade,
  blocked_uid uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (uid, blocked_uid)
);

-- usage counters (per uid per day) — server-side AI cost cap -----------------
create table if not exists public.usage_counters (
  uid uuid references auth.users(id) on delete cascade,
  day date not null default current_date,
  generations int not null default 0,
  primary key (uid, day)
);

-- membership helper (SECURITY DEFINER, avoids RLS recursion) -----------------
create or replace function public.is_member(p_room uuid, p_uid uuid)
returns boolean language sql security definer stable set search_path=public as $$
  select exists(select 1 from public.room_members where room_id=p_room and uid=p_uid);
$$;

-- send_poke: the only path to create a poke (gated) --------------------------
create or replace function public.send_poke(p_room uuid, p_to uuid, p_kind text, p_body text, p_from_name text, p_from_character text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_recent int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.is_member(p_room, auth.uid()) then raise exception 'not a room member'; end if;
  if not public.is_member(p_room, p_to) then raise exception 'target not in room'; end if;
  if exists(select 1 from public.blocks where uid=p_to and blocked_uid=auth.uid()) then
    raise exception 'blocked';
  end if;
  select count(*) into v_recent from public.pokes
    where from_uid=auth.uid() and created_at > now() - interval '60 seconds';
  if v_recent >= 30 then raise exception 'rate limited'; end if;
  insert into public.pokes(room_id, from_uid, to_uid, kind, body, from_name, from_character)
    values (p_room, auth.uid(), p_to, coalesce(p_kind,'poke'), p_body, p_from_name, p_from_character)
    returning id into v_id;
  return v_id;
end $$;

-- join_room_by_code: idempotent join + autocreate membership -----------------
create or replace function public.join_room_by_code(p_code text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_room uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select id into v_room from public.rooms where code = upper(p_code);
  if v_room is null then raise exception 'no such room'; end if;
  insert into public.room_members(room_id, uid) values (v_room, auth.uid())
    on conflict do nothing;
  return v_room;
end $$;

-- RLS ----------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.rooms          enable row level security;
alter table public.room_members   enable row level security;
alter table public.pokes          enable row level security;
alter table public.blocks         enable row level security;
alter table public.usage_counters enable row level security;

-- profiles: SELF-only read by default (safe). friends.sql widens this to "self OR accepted
-- friend" via is_friend(); never use `using (true)` — that leaked every profile globally.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (uid = auth.uid());
drop policy if exists profiles_upsert on public.profiles;
create policy profiles_upsert on public.profiles for insert to authenticated with check (uid = auth.uid());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated using (uid = auth.uid());

-- rooms: members can read; anyone authed can create
drop policy if exists rooms_read on public.rooms;
create policy rooms_read on public.rooms for select to authenticated using (public.is_member(id, auth.uid()) or owner = auth.uid());
drop policy if exists rooms_insert on public.rooms;
create policy rooms_insert on public.rooms for insert to authenticated with check (owner = auth.uid());

-- room_members: you can see members of rooms you're in; you can add only yourself
drop policy if exists rm_read on public.room_members;
create policy rm_read on public.room_members for select to authenticated using (public.is_member(room_id, auth.uid()));
drop policy if exists rm_insert on public.room_members;
create policy rm_insert on public.room_members for insert to authenticated with check (uid = auth.uid());
drop policy if exists rm_delete on public.room_members;
create policy rm_delete on public.room_members for delete to authenticated using (uid = auth.uid());

-- pokes: you see pokes to/from you; NO direct insert (must use send_poke())
drop policy if exists pokes_read on public.pokes;
create policy pokes_read on public.pokes for select to authenticated using (to_uid = auth.uid() or from_uid = auth.uid());

-- blocks: own rows only
drop policy if exists blocks_all on public.blocks;
create policy blocks_all on public.blocks for all to authenticated using (uid = auth.uid()) with check (uid = auth.uid());

-- usage_counters: readable by owner; writes happen via service role (bypasses RLS)
drop policy if exists usage_read on public.usage_counters;
create policy usage_read on public.usage_counters for select to authenticated using (uid = auth.uid());

-- consume_generation: the generate-image Edge Function calls this (as the service role) to
-- check + increment a user's daily generation count atomically; returns false when over the cap.
create or replace function public.consume_generation(p_uid uuid, p_cap int)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_count int;
begin
  select generations into v_count from public.usage_counters where uid = p_uid and day = current_date;
  if v_count is null then v_count := 0; end if;
  if v_count >= p_cap then return false; end if;
  insert into public.usage_counters(uid, day, generations) values (p_uid, current_date, 1)
    on conflict (uid, day) do update set generations = public.usage_counters.generations + 1;
  return true;
end $$;

-- realtime: ensure pokes changes are published
alter publication supabase_realtime add table public.pokes;

-- the default Room ---------------------------------------------------------
insert into public.rooms(code, name) values ('PATPARTY', 'the Room')
  on conflict (code) do nothing;
