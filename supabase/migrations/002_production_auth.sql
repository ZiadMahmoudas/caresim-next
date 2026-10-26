-- CareSim production authentication, profile provisioning and role hardening
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists learner_type text not null default 'student' check (learner_type in ('student','nurse'));

-- Organizations are not public browsing data.
alter table public.organizations enable row level security;
drop policy if exists organizations_authenticated_read on public.organizations;
create policy organizations_authenticated_read on public.organizations for select to authenticated using(true);

update public.profiles p set email=u.email from auth.users u where p.id=u.id and p.email is null;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name,learner_type,role)
  values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''),case when new.raw_user_meta_data->>'learner_type'='nurse' then 'nurse' else 'student' end,'student')
  on conflict(id) do update set email=excluded.email;
  return new;
end;$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert or update of email on auth.users for each row execute procedure public.handle_new_user();

-- Backfill missing profiles for existing Auth users.
insert into public.profiles(id,email,full_name,learner_type,role)
select u.id,u.email,coalesce(u.raw_user_meta_data->>'full_name',''),case when u.raw_user_meta_data->>'learner_type'='nurse' then 'nurse' else 'student' end,'student'::public.user_role
from auth.users u left join public.profiles p on p.id=u.id where p.id is null;

-- Users may edit only safe profile columns. Role is deliberately excluded.
revoke update on public.profiles from authenticated;
grant update(full_name,avatar_url,bio,academic_level,specialization,personal_skills,learner_type,updated_at) on public.profiles to authenticated;
grant select on public.profiles to authenticated;

create or replace function public.admin_set_user_role(target_user_id uuid,new_role public.user_role)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_role() <> 'admin' then raise exception 'Admin access required'; end if;
  if target_user_id = auth.uid() and new_role <> 'admin' then raise exception 'You cannot remove your own admin access'; end if;
  update public.profiles set role=new_role,updated_at=now() where id=target_user_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'role_changed','profile',target_user_id::text,jsonb_build_object('new_role',new_role));
end;$$;
grant execute on function public.admin_set_user_role(uuid,public.user_role) to authenticated;

-- Profile self update remains row-restricted; admin role changes happen only through the secured RPC above.
drop policy if exists profile_self_update on public.profiles;
create policy profile_self_update on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());

-- Avatar storage. Files are public for rendering, but only the owner may write their folder.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists avatar_insert_own on storage.objects;
create policy avatar_insert_own on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_update_own on storage.objects;
create policy avatar_update_own on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_delete_own on storage.objects;
create policy avatar_delete_own on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
