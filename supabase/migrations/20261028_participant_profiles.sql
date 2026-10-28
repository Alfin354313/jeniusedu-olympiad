-- Jalankan pada proyek Supabase khusus Olympiad.
create table if not exists public.olympiad_participant_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null check (char_length(trim(full_name)) between 1 and 120),
 school_level text not null check (school_level in ('SD','SMP','SMA')),
 created_at timestamptz not null default now()
);
alter table public.olympiad_participant_profiles enable row level security;
revoke all on public.olympiad_participant_profiles from anon, authenticated;
grant select, insert, update on public.olympiad_participant_profiles to authenticated;
drop policy if exists participant_select_self on public.olympiad_participant_profiles;
create policy participant_select_self on public.olympiad_participant_profiles for select to authenticated using ((select auth.uid())=id);
drop policy if exists participant_insert_self on public.olympiad_participant_profiles;
create policy participant_insert_self on public.olympiad_participant_profiles for insert to authenticated with check ((select auth.uid())=id);
drop policy if exists participant_update_self on public.olympiad_participant_profiles;
create policy participant_update_self on public.olympiad_participant_profiles for update to authenticated using ((select auth.uid())=id) with check ((select auth.uid())=id);
