-- CareSim v6: complete staff workspaces, course/assignment management and storage hardening.

-- 1) Storage hardening. Safe to run repeatedly.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists avatar_select_authenticated on storage.objects;
create policy avatar_select_authenticated on storage.objects for select to authenticated using(bucket_id='avatars');
drop policy if exists avatar_insert_own on storage.objects;
create policy avatar_insert_own on storage.objects for insert to authenticated
with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_update_own on storage.objects;
create policy avatar_update_own on storage.objects for update to authenticated
using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_delete_own on storage.objects;
create policy avatar_delete_own on storage.objects for delete to authenticated
using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

-- 2) Staff read policies for courses, rosters, assignments and audit logs.
alter table public.courses enable row level security;
alter table public.course_members enable row level security;
alter table public.assignments enable row level security;
alter table public.audit_logs enable row level security;

grant select on public.courses, public.course_members, public.assignments, public.audit_logs to authenticated;

create or replace function public.can_manage_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.current_role()='admin' or exists(select 1 from public.courses c where c.id=p_course_id and c.instructor_id=auth.uid());
$$;
grant execute on function public.can_manage_course(uuid) to authenticated;

create or replace function public.can_view_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.current_role()='admin'
    or exists(select 1 from public.courses c where c.id=p_course_id and c.instructor_id=auth.uid())
    or exists(select 1 from public.course_members cm where cm.course_id=p_course_id and cm.student_id=auth.uid());
$$;
grant execute on function public.can_view_course(uuid) to authenticated;

drop policy if exists courses_staff_and_member_read on public.courses;
create policy courses_staff_and_member_read on public.courses for select to authenticated using(public.can_view_course(id));

drop policy if exists course_members_staff_and_self_read on public.course_members;
create policy course_members_staff_and_self_read on public.course_members for select to authenticated using(student_id=auth.uid() or public.can_manage_course(course_id));

drop policy if exists assignments_staff_and_student_read on public.assignments;
create policy assignments_staff_and_student_read on public.assignments for select to authenticated using(public.can_view_course(course_id));

drop policy if exists audit_admin_read on public.audit_logs;
create policy audit_admin_read on public.audit_logs for select to authenticated using(public.current_role()='admin');

-- 3) Course management. Instructors manage their own courses; admins manage everything.
create or replace function public.staff_create_course(p_title text,p_code text default null,p_instructor_id uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_org uuid; v_instructor uuid; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role,organization_id into v_role,v_org from public.profiles where id=auth.uid();
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  if length(trim(coalesce(p_title,'')))<3 then raise exception 'Course title is required'; end if;
  if v_org is null then select id into v_org from public.organizations order by created_at limit 1; end if;
  if v_org is null then insert into public.organizations(name,slug) values('CareSim Academy','caresim-academy') returning id into v_org; end if;
  v_instructor := case when v_role='instructor' then auth.uid() else p_instructor_id end;
  insert into public.courses(organization_id,instructor_id,title,code,is_active)
  values(v_org,v_instructor,trim(p_title),nullif(trim(coalesce(p_code,'')),''),true) returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'course_created','course',v_id::text,jsonb_build_object('title',trim(p_title)));
  return v_id;
end;$$;
grant execute on function public.staff_create_course(text,text,uuid) to authenticated;

create or replace function public.staff_update_course(p_course_id uuid,p_title text,p_code text,p_instructor_id uuid,p_is_active boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner uuid;
begin
  select role into v_role from public.profiles where id=auth.uid();
  select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.uid() then raise exception 'You can only edit your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.courses set title=trim(p_title),code=nullif(trim(coalesce(p_code,'')),''),instructor_id=case when v_role='admin' then p_instructor_id else auth.uid() end,is_active=coalesce(p_is_active,true) where id=p_course_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'course_updated','course',p_course_id::text,'{}');
end;$$;
grant execute on function public.staff_update_course(uuid,text,text,uuid,boolean) to authenticated;

create or replace function public.staff_delete_course(p_course_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner uuid;
begin
  select role into v_role from public.profiles where id=auth.uid();
  select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.uid() then raise exception 'You can only delete your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.attempts set assignment_id=null where assignment_id in(select id from public.assignments where course_id=p_course_id);
  delete from public.courses where id=p_course_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'course_deleted','course',p_course_id::text,'{}');
end;$$;
grant execute on function public.staff_delete_course(uuid) to authenticated;

create or replace function public.staff_add_course_member(p_course_id uuid,p_student_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner uuid; v_target_role public.user_role;
begin
  select role into v_role from public.profiles where id=auth.uid();
  select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.uid() then raise exception 'You can only manage your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  select role into v_target_role from public.profiles where id=p_student_id;
  if v_target_role<>'student' then raise exception 'Only learner accounts can be enrolled'; end if;
  insert into public.course_members(course_id,student_id) values(p_course_id,p_student_id) on conflict do nothing;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'course_member_added','course',p_course_id::text,jsonb_build_object('student_id',p_student_id));
end;$$;
grant execute on function public.staff_add_course_member(uuid,uuid) to authenticated;

create or replace function public.staff_remove_course_member(p_course_id uuid,p_student_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner uuid;
begin
  select role into v_role from public.profiles where id=auth.uid(); select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.uid() then raise exception 'You can only manage your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  delete from public.course_members where course_id=p_course_id and student_id=p_student_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'course_member_removed','course',p_course_id::text,jsonb_build_object('student_id',p_student_id));
end;$$;
grant execute on function public.staff_remove_course_member(uuid,uuid) to authenticated;

create or replace function public.staff_create_assignment(p_course_id uuid,p_scenario_id uuid,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner uuid; v_id uuid;
begin
  select role into v_role from public.profiles where id=auth.uid(); select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.uid() then raise exception 'You can only assign work to your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  insert into public.assignments(course_id,scenario_id,assigned_by,due_at) values(p_course_id,p_scenario_id,auth.uid(),p_due_at) returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'assignment_created','assignment',v_id::text,jsonb_build_object('course_id',p_course_id,'scenario_id',p_scenario_id));
  return v_id;
end;$$;
grant execute on function public.staff_create_assignment(uuid,uuid,timestamptz) to authenticated;

create or replace function public.staff_delete_assignment(p_assignment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner uuid;
begin
  select p.role,c.instructor_id into v_role,v_owner from public.profiles p, public.assignments a join public.courses c on c.id=a.course_id where p.id=auth.uid() and a.id=p_assignment_id;
  if v_role='instructor' and v_owner<>auth.uid() then raise exception 'You can only manage assignments in your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.attempts set assignment_id=null where assignment_id=p_assignment_id;
  delete from public.assignments where id=p_assignment_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'assignment_deleted','assignment',p_assignment_id::text,'{}');
end;$$;
grant execute on function public.staff_delete_assignment(uuid) to authenticated;

-- 4) Scenario catalog CRUD for staff. Scenario logic/rubric can be enriched later by the clinical builder.
create or replace function public.staff_create_scenario(p_type public.scenario_type,p_title text,p_description text default null,p_specialty text default null,p_difficulty text default 'Beginner')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_id uuid; v_slug text; v_base text; n int:=0; v_org uuid;
begin
  select role,organization_id into v_role,v_org from public.profiles where id=auth.uid();
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  if length(trim(coalesce(p_title,'')))<3 then raise exception 'Title is required'; end if;
  v_base:=trim(both '-' from lower(regexp_replace(trim(p_title),'[^a-zA-Z0-9]+','-','g'))); if v_base='' then v_base:='scenario'; end if; v_slug:=v_base;
  while exists(select 1 from public.scenarios where slug=v_slug) loop n:=n+1;v_slug:=v_base||'-'||n::text; end loop;
  insert into public.scenarios(organization_id,type,title,slug,description,specialty,current_version,is_published,created_by)
  values(v_org,p_type,trim(p_title),v_slug,nullif(trim(coalesce(p_description,'')),''),nullif(trim(coalesce(p_specialty,'')),''),1,false,auth.uid()) returning id into v_id;
  insert into public.scenario_versions(scenario_id,version,config,rubric) values(v_id,1,jsonb_build_object('difficulty',p_difficulty,'runtime_initial_state','{}'::jsonb,'rules','[]'::jsonb),'{}');
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'scenario_created','scenario',v_id::text,jsonb_build_object('type',p_type,'title',trim(p_title)));
  return v_id;
end;$$;
grant execute on function public.staff_create_scenario(public.scenario_type,text,text,text,text) to authenticated;

create or replace function public.staff_update_scenario(p_scenario_id uuid,p_title text,p_description text,p_specialty text,p_published boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role;
begin
  select role into v_role from public.profiles where id=auth.uid(); if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.scenarios set title=trim(p_title),description=nullif(trim(coalesce(p_description,'')),''),specialty=nullif(trim(coalesce(p_specialty,'')),''),is_published=p_published where id=p_scenario_id;
  if not found then raise exception 'Scenario not found'; end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'scenario_updated','scenario',p_scenario_id::text,jsonb_build_object('published',p_published));
end;$$;
grant execute on function public.staff_update_scenario(uuid,text,text,text,boolean) to authenticated;

create or replace function public.admin_delete_scenario(p_scenario_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_role()<>'admin' then raise exception 'Admin access required'; end if;
  if exists(select 1 from public.attempts a join public.scenario_versions sv on sv.id=a.scenario_version_id where sv.scenario_id=p_scenario_id) then
    raise exception 'This scenario has learner attempts. Unpublish it instead so historical records remain valid.';
  end if;
  delete from public.scenarios where id=p_scenario_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'scenario_deleted','scenario',p_scenario_id::text,'{}');
end;$$;
grant execute on function public.admin_delete_scenario(uuid) to authenticated;

-- 5) Scope instructor clinical data to learners enrolled in their courses.
create or replace function public.staff_can_view_student(p_student_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select case
    when public.current_role()='admin' then true
    when public.current_role()='instructor' then exists(
      select 1 from public.course_members cm join public.courses c on c.id=cm.course_id
      where cm.student_id=p_student_id and c.instructor_id=auth.uid()
    )
    else false
  end;
$$;
grant execute on function public.staff_can_view_student(uuid) to authenticated;

drop policy if exists student_attempts_read on public.attempts;
create policy student_attempts_read on public.attempts for select to authenticated using(student_id=auth.uid() or public.staff_can_view_student(student_id));
drop policy if exists student_attempt_actions_read on public.attempt_actions;
create policy student_attempt_actions_read on public.attempt_actions for select to authenticated using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.staff_can_view_student(a.student_id))));
drop policy if exists student_results_read on public.attempt_results;
create policy student_results_read on public.attempt_results for select to authenticated using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.staff_can_view_student(a.student_id))));
drop policy if exists student_mastery_read on public.skill_mastery;
create policy student_mastery_read on public.skill_mastery for select to authenticated using(student_id=auth.uid() or public.staff_can_view_student(student_id));
drop policy if exists ai_conversation_read on public.ai_conversations;
create policy ai_conversation_read on public.ai_conversations for select to authenticated using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.staff_can_view_student(a.student_id))));
