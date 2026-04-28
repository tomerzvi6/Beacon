-- =============================================================
-- Beacon — Supabase Schema (Auth + Multi-tenancy)
-- Run this in Supabase Dashboard → SQL Editor → New query
-- =============================================================

-- ─── 1. TABLES ───────────────────────────────────────────────

create table if not exists families (
  id           uuid primary key default gen_random_uuid(),
  patient_name text not null,
  created_at   timestamptz default now()
);

create table if not exists profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null,
  avatar_symbol text default 'person.crop.circle',
  created_at    timestamptz default now()
);

create table if not exists family_members (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references profiles(id) on delete cascade,
  family_id    uuid references families(id) on delete cascade,
  role         text not null check (role in ('admin','member','patient')),
  permissions  jsonb default '{}',
  created_at   timestamptz default now(),
  unique(user_id, family_id)
);

create table if not exists invite_tokens (
  token       uuid primary key default gen_random_uuid(),
  family_id   uuid references families(id) on delete cascade,
  created_by  uuid references profiles(id),
  expires_at  timestamptz default (now() + interval '7 days'),
  used_at     timestamptz,
  created_at  timestamptz default now()
);

-- ─── 2. RLS ENABLEMENT ──────────────────────────────────────

alter table families       enable row level security;
alter table profiles       enable row level security;
alter table family_members enable row level security;
alter table invite_tokens  enable row level security;

-- ─── 3. HELPER FUNCTION ─────────────────────────────────────

create or replace function get_my_family_id()
returns uuid
language sql
security definer
stable
as $$
  select family_id from family_members
   where user_id = auth.uid()
   limit 1;
$$;

-- ─── 4. RLS POLICIES ────────────────────────────────────────

-- profiles: each user can read/write their own profile only
drop policy if exists profiles_select_own on profiles;
create policy profiles_select_own on profiles
  for select using (id = auth.uid());

drop policy if exists profiles_insert_own on profiles;
create policy profiles_insert_own on profiles
  for insert with check (id = auth.uid());

drop policy if exists profiles_update_own on profiles;
create policy profiles_update_own on profiles
  for update using (id = auth.uid());

-- families: members can read; INSERT/UPDATE done via SECURITY DEFINER funcs
drop policy if exists families_select_my on families;
create policy families_select_my on families
  for select using (id = get_my_family_id());

-- family_members: read/write only for your own family
drop policy if exists family_members_select_my on family_members;
create policy family_members_select_my on family_members
  for select using (family_id = get_my_family_id());

drop policy if exists family_members_modify_admin on family_members;
create policy family_members_modify_admin on family_members
  for all
  using (
    family_id = get_my_family_id()
    and exists (
      select 1 from family_members fm
       where fm.user_id = auth.uid()
         and fm.family_id = family_members.family_id
         and fm.role in ('admin','patient')
    )
  );

-- invite_tokens: only admins can create / read tokens for their family
drop policy if exists invite_tokens_select_my on invite_tokens;
create policy invite_tokens_select_my on invite_tokens
  for select using (family_id = get_my_family_id());

drop policy if exists invite_tokens_insert_admin on invite_tokens;
create policy invite_tokens_insert_admin on invite_tokens
  for insert with check (
    family_id = get_my_family_id()
    and exists (
      select 1 from family_members fm
       where fm.user_id = auth.uid()
         and fm.family_id = invite_tokens.family_id
         and fm.role in ('admin','patient')
    )
  );

-- ─── 5. SECURITY DEFINER BOOTSTRAP FUNCTIONS ────────────────
-- These run with elevated privileges to bypass RLS for legitimate
-- bootstrap operations (creating first family, accepting invite).

-- Create profile + family + admin membership in one transaction.
-- Called the first time a new authenticated user opens the app.
create or replace function create_family_for_current_user(
  p_patient_name   text,
  p_caregiver_name text
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_user_id   uuid := auth.uid();
  v_family_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Ensure profile exists
  insert into profiles (id, display_name)
  values (v_user_id, p_caregiver_name)
  on conflict (id) do update set display_name = excluded.display_name;

  -- Refuse if user already belongs to a family
  if exists (select 1 from family_members where user_id = v_user_id) then
    raise exception 'User already belongs to a family';
  end if;

  -- Create family
  insert into families (patient_name)
  values (p_patient_name)
  returning id into v_family_id;

  -- Add as admin
  insert into family_members (user_id, family_id, role)
  values (v_user_id, v_family_id, 'admin');

  return v_family_id;
end;
$$;

-- Accept an invite token: adds current user as a member of the family.
create or replace function accept_invite(p_token uuid)
returns uuid
language plpgsql
security definer
as $$
declare
  v_user_id   uuid := auth.uid();
  v_family_id uuid;
  v_used_at   timestamptz;
  v_expires   timestamptz;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select family_id, used_at, expires_at
    into v_family_id, v_used_at, v_expires
    from invite_tokens
   where token = p_token;

  if v_family_id is null then raise exception 'Invalid invite token'; end if;
  if v_used_at  is not null then raise exception 'Invite already used'; end if;
  if v_expires  < now()    then raise exception 'Invite expired'; end if;

  -- Add member (idempotent on unique(user_id, family_id))
  insert into family_members (user_id, family_id, role)
  values (v_user_id, v_family_id, 'member')
  on conflict (user_id, family_id) do nothing;

  update invite_tokens set used_at = now() where token = p_token;

  return v_family_id;
end;
$$;

-- Allow authenticated users to call these functions
grant execute on function create_family_for_current_user(text, text) to authenticated;
grant execute on function accept_invite(uuid)                         to authenticated;
grant execute on function get_my_family_id()                          to authenticated;
