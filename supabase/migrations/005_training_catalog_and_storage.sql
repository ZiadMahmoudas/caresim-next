-- CareSim v5: training catalog controls + avatar storage policy repair.

-- Storage: authenticated users may read avatar metadata and only write inside their own folder.
drop policy if exists avatar_select_authenticated on storage.objects;
create policy avatar_select_authenticated
on storage.objects for select to authenticated
using (bucket_id = 'avatars');

drop policy if exists avatar_insert_own on storage.objects;
create policy avatar_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists avatar_update_own on storage.objects;
create policy avatar_update_own
on storage.objects for update to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists avatar_delete_own on storage.objects;
create policy avatar_delete_own
on storage.objects for delete to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Admin/instructor controlled Skills Lab catalog.
create or replace function public.admin_create_training_skill(
  p_title text,
  p_description text default null,
  p_specialty text default null,
  p_difficulty text default 'Beginner'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role public.user_role;
  v_id uuid;
  v_slug text;
  v_base text;
  v_counter int := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id=auth.uid();
  if v_role not in ('admin','instructor') then raise exception 'Admin or instructor access required'; end if;
  if length(trim(coalesce(p_title,''))) < 3 then raise exception 'Title is required'; end if;

  v_base := lower(regexp_replace(trim(p_title), '[^a-zA-Z0-9]+', '-', 'g'));
  v_base := trim(both '-' from v_base);
  if v_base = '' then v_base := 'training-skill'; end if;
  v_slug := v_base;
  while exists(select 1 from public.scenarios where slug=v_slug) loop
    v_counter := v_counter + 1;
    v_slug := v_base || '-' || v_counter::text;
  end loop;

  insert into public.scenarios(type,title,slug,description,specialty,current_version,is_published,created_by)
  values('skill',trim(p_title),v_slug,nullif(trim(coalesce(p_description,'')),''),nullif(trim(coalesce(p_specialty,'')),''),1,false,auth.uid())
  returning id into v_id;

  insert into public.scenario_versions(scenario_id,version,config,rubric)
  values(
    v_id,
    1,
    jsonb_build_object(
      'difficulty', coalesce(nullif(trim(p_difficulty),''),'Beginner'),
      'module_status','catalog',
      'rules','[]'::jsonb
    ),
    '{}'::jsonb
  );

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'training_skill_created','scenario',v_id::text,jsonb_build_object('title',trim(p_title)));

  return v_id;
end;$$;

grant execute on function public.admin_create_training_skill(text,text,text,text) to authenticated;

create or replace function public.admin_set_scenario_published(
  p_scenario_id uuid,
  p_published boolean
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id=auth.uid();
  if v_role not in ('admin','instructor') then raise exception 'Admin or instructor access required'; end if;

  update public.scenarios
  set is_published=p_published
  where id=p_scenario_id;

  if not found then raise exception 'Scenario not found'; end if;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),case when p_published then 'scenario_published' else 'scenario_unpublished' end,'scenario',p_scenario_id::text,'{}'::jsonb);
end;$$;

grant execute on function public.admin_set_scenario_published(uuid,boolean) to authenticated;
