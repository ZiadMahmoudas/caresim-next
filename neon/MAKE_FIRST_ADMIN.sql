-- CareSim: promote an existing Neon Auth user to application admin.
-- Replace YOUR_ADMIN_EMAIL, then run against the same `neondb` database used by Neon Auth.

-- Repair/sync the public profile shape first (safe to rerun).
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists learner_type text not null default 'student';

insert into public.profiles (id, email, full_name, learner_type, role)
select u.id, u.email, coalesce(u.name, ''), 'student', 'student'::public.user_role
from neon_auth.user u
where lower(u.email) = lower('YOUR_ADMIN_EMAIL')
on conflict (id) do update
set email = excluded.email,
    full_name = case when public.profiles.full_name = '' then excluded.full_name else public.profiles.full_name end,
    updated_at = now();

update public.profiles p
set role = 'admin'::public.user_role,
    email = u.email,
    updated_at = now()
from neon_auth.user u
where u.id = p.id
  and lower(u.email) = lower('YOUR_ADMIN_EMAIL');

-- Keep Neon Auth's admin plugin role aligned with the app role.
update neon_auth.user
set role = 'admin'
where lower(email) = lower('YOUR_ADMIN_EMAIL');

select p.id, u.email, p.role as app_role, u.role as auth_role
from public.profiles p
join neon_auth.user u on u.id = p.id
where lower(u.email) = lower('YOUR_ADMIN_EMAIL');
