-- CareSim / Neon production repair for the current database.
-- Replace YOUR_ADMIN_EMAIL with the first administrator email before running.
-- Safe to run after the core CareSim tables already exist.

-- 1) Bring profiles up to the current production shape.
alter table public.profiles
  add column if not exists email text;

alter table public.profiles
  add column if not exists learner_type text not null default 'student';

-- 2) Sync all existing Neon Auth users into public.profiles.
insert into public.profiles (id, email, full_name, learner_type, role)
select
  u.id,
  u.email,
  coalesce(u.name, ''),
  'student',
  'student'::public.user_role
from neon_auth.user u
on conflict (id) do update
set email = excluded.email,
    full_name = case
      when public.profiles.full_name = '' then excluded.full_name
      else public.profiles.full_name
    end,
    updated_at = now();

-- 3) Keep future Auth users in sync automatically.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id,email,full_name,learner_type,role)
  values(new.id,new.email,coalesce(new.name,''),'student','student')
  on conflict(id) do update
  set email=excluded.email,
      full_name=case
        when public.profiles.full_name='' then excluded.full_name
        else public.profiles.full_name
      end,
      updated_at=now();
  return new;
end;
$$;

drop trigger if exists on_neon_auth_user_created on neon_auth.user;
create trigger on_neon_auth_user_created
after insert or update of email,name on neon_auth.user
for each row execute procedure public.handle_new_user();

-- 4) Promote YOUR_ADMIN_EMAIL in both CareSim and Neon Auth.
update public.profiles p
set role='admin'::public.user_role,
    email=u.email,
    updated_at=now()
from neon_auth.user u
where u.id=p.id
  and lower(u.email)=lower('YOUR_ADMIN_EMAIL');

update neon_auth.user
set role='admin'
where lower(email)=lower('YOUR_ADMIN_EMAIL');

-- 5) Production verification.
select
  p.id,
  u.email,
  p.role as app_role,
  u.role as auth_role,
  p.learner_type
from public.profiles p
join neon_auth.user u on u.id=p.id
where lower(u.email)=lower('YOUR_ADMIN_EMAIL');
