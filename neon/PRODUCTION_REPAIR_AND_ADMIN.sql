-- CareSim production repair + first admin promotion. Safe for a database where the base tables already exist.
-- Replace YOUR_ADMIN_EMAIL before running.

-- 1) Ensure profile columns required by the current app exist.
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists learner_type text not null default 'student';

-- 2) Backfill public profiles from Managed Better Auth.
insert into public.profiles (id, email, full_name, learner_type, role)
select u.id, u.email, coalesce(u.name, ''), 'student', 'student'::public.user_role
from neon_auth.user u
on conflict (id) do update
set email = excluded.email,
    full_name = case when public.profiles.full_name = '' then excluded.full_name else public.profiles.full_name end,
    updated_at = now();

-- 3) Keep new/updated Neon Auth users synchronized with public.profiles.
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
      full_name=case when public.profiles.full_name='' then excluded.full_name else public.profiles.full_name end,
      updated_at=now();
  return new;
end;
$$;

drop trigger if exists on_neon_auth_user_created on neon_auth.user;
create trigger on_neon_auth_user_created
after insert or update of email,name on neon_auth.user
for each row execute procedure public.handle_new_user();

-- 4) Promote the requested user. Email lives in neon_auth.user, not necessarily public.profiles on older installs.
update public.profiles p
set role='admin'::public.user_role, email=u.email, updated_at=now()
from neon_auth.user u
where u.id=p.id
  and lower(u.email)=lower('YOUR_ADMIN_EMAIL');

update neon_auth.user
set role='admin'
where lower(email)=lower('YOUR_ADMIN_EMAIL');

-- 5) Verify. Expect app_role=admin and auth_role=admin.
select p.id, u.email, p.role as app_role, u.role as auth_role
from public.profiles p
join neon_auth.user u on u.id=p.id
where lower(u.email)=lower('YOUR_ADMIN_EMAIL');
