-- NEXUS CHAT: Supabase setup
-- Run this in: Supabase Dashboard > SQL Editor > New query > Run

-- 1. Tables
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  first_name text,
  last_name text,
  country text,
  phone text,
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  conversation_id text not null,
  sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  text text not null check (char_length(text) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists messages_conv_idx on public.messages (conversation_id, created_at);

-- 2. Auto-create a profile when someone signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, first_name, last_name, country, phone)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name',
    new.raw_user_meta_data->>'country',
    new.raw_user_meta_data->>'phone'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3. Row Level Security
alter table public.profiles enable row level security;
alter table public.messages enable row level security;

drop policy if exists "profiles readable by signed-in users" on public.profiles;
create policy "profiles readable by signed-in users"
  on public.profiles for select to authenticated using (true);

drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "read own messages" on public.messages;
create policy "read own messages"
  on public.messages for select to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "send as yourself" on public.messages;
create policy "send as yourself"
  on public.messages for insert to authenticated
  with check (auth.uid() = sender_id);

-- 4. Realtime
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.profiles;
