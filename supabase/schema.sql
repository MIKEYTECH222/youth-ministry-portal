-- Run in Supabase SQL Editor as project owner.
create extension if not exists pgcrypto;
create type public.member_role as enum ('member','leader','admin');
create type public.member_status as enum ('pending','approved','rejected');
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '',
 role public.member_role not null default 'member',
 status public.member_status not null default 'pending',
 created_at timestamptz not null default now()
);
create table public.point_transactions (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.profiles(id) on delete cascade,
 amount integer not null check (amount between -1000 and 1000 and amount <> 0),
 reason text not null check (char_length(trim(reason)) between 1 and 250),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create table public.events (
 id uuid primary key default gen_random_uuid(),
 title text not null check (char_length(trim(title)) between 1 and 150),
 description text not null default '', starts_at timestamptz not null,
 location text not null default '', published boolean not null default true,
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.event_registrations (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.events(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(), unique(event_id,user_id)
);
create table public.lessons (
 id uuid primary key default gen_random_uuid(), title text not null,
 description text not null default '', material_url text not null default '',
 published boolean not null default true, created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create index point_transactions_member_idx on public.point_transactions(member_id,created_at desc);
create index events_date_idx on public.events(starts_at);

-- Signups are always pending members; browser metadata cannot set role/status.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,full_name,role,status) values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),'New member'),'member','pending');
 return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.current_role() returns public.member_role language sql stable security definer set search_path = '' as $$
 select role from public.profiles where id=(select auth.uid()) and status='approved'; $$;
create or replace function public.is_approved() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and status='approved'); $$;
create or replace function public.is_leader_or_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select coalesce(public.current_role() in ('leader'::public.member_role,'admin'::public.member_role),false); $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select coalesce(public.current_role()='admin'::public.member_role,false); $$;

create or replace function public.approve_member(target_user_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_admin() then raise exception 'Only an admin can approve members'; end if;
 update public.profiles set status='approved' where id=target_user_id and status='pending';
 if not found then raise exception 'Pending member not found'; end if;
end; $$;
create or replace function public.set_member_role(target_user_id uuid,new_role public.member_role) returns void language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_admin() then raise exception 'Only an admin can change roles'; end if;
 if target_user_id=(select auth.uid()) then raise exception 'Cannot change your own role'; end if;
 if new_role='admin'::public.member_role then raise exception 'Assign additional admins in SQL as project owner'; end if;
 update public.profiles set role=new_role where id=target_user_id and status='approved';
 if not found then raise exception 'Approved member not found'; end if;
end; $$;

alter table public.profiles enable row level security;
alter table public.point_transactions enable row level security;
alter table public.events enable row level security;
alter table public.event_registrations enable row level security;
alter table public.lessons enable row level security;
revoke all on public.profiles from anon,authenticated;
grant select on public.profiles to authenticated;
grant update(full_name) on public.profiles to authenticated;
revoke all on public.point_transactions from anon,authenticated;
grant select,insert on public.point_transactions to authenticated;
revoke all on public.events from anon,authenticated;
grant select,insert,update,delete on public.events to authenticated;
revoke all on public.event_registrations from anon,authenticated;
grant select,insert,delete on public.event_registrations to authenticated;
revoke all on public.lessons from anon,authenticated;
grant select,insert,update,delete on public.lessons to authenticated;

create policy "profiles read self admin or leader" on public.profiles for select to authenticated using(id=(select auth.uid()) or public.is_admin() or (public.current_role()='leader'::public.member_role and status='approved'));
create policy "profiles update own name only" on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy "points read self or leaders" on public.point_transactions for select to authenticated using(member_id=(select auth.uid()) or public.is_leader_or_admin());
create policy "leaders award points" on public.point_transactions for insert to authenticated with check(public.is_leader_or_admin() and created_by=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=member_id and p.status='approved'));
create policy "read published events" on public.events for select to authenticated using(public.is_approved() and (published or public.is_leader_or_admin()));
create policy "leaders create events" on public.events for insert to authenticated with check(public.is_leader_or_admin() and created_by=(select auth.uid()));
create policy "leaders update events" on public.events for update to authenticated using(public.is_leader_or_admin()) with check(public.is_leader_or_admin() and created_by=(select auth.uid()));
create policy "leaders delete events" on public.events for delete to authenticated using(public.is_leader_or_admin());
create policy "read own registrations or leader" on public.event_registrations for select to authenticated using(public.is_approved() and (user_id=(select auth.uid()) or public.is_leader_or_admin()));
create policy "register self for published event" on public.event_registrations for insert to authenticated with check(public.is_approved() and user_id=(select auth.uid()) and exists(select 1 from public.events e where e.id=event_id and e.published));
create policy "cancel own registration or leader" on public.event_registrations for delete to authenticated using(user_id=(select auth.uid()) or public.is_leader_or_admin());
create policy "read published lessons" on public.lessons for select to authenticated using(public.is_approved() and (published or public.is_leader_or_admin()));
create policy "leaders create lessons" on public.lessons for insert to authenticated with check(public.is_leader_or_admin() and created_by=(select auth.uid()));
create policy "leaders update lessons" on public.lessons for update to authenticated using(public.is_leader_or_admin()) with check(public.is_leader_or_admin() and created_by=(select auth.uid()));
create policy "leaders delete lessons" on public.lessons for delete to authenticated using(public.is_leader_or_admin());
grant execute on function public.approve_member(uuid) to authenticated;
grant execute on function public.set_member_role(uuid,public.member_role) to authenticated;
grant execute on function public.current_role() to authenticated;
grant execute on function public.is_approved() to authenticated;
grant execute on function public.is_leader_or_admin() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- After signing up with your intended admin email, run this once as project owner:
-- update public.profiles set role='admin',status='approved' where id=(select id from auth.users where email='YOUR-ADMIN-EMAIL');
