-- CareSim V11 — reliable instructor learner directory/roster and robust published simulation discovery.
-- Run AFTER V10.

-- Keep existing users in the academy organization so learner discovery is deterministic.
do $$
declare v_org uuid;
begin
  select id into v_org from public.organizations order by created_at asc limit 1;
  if v_org is null then
    insert into public.organizations(name,slug) values('CareSim Academy','caresim-academy') returning id into v_org;
  end if;
  update public.profiles set organization_id=v_org where organization_id is null;
end $$;

-- Staff-safe people directory. This avoids browser-side profile RLS joins becoming an empty roster.
create or replace function public.staff_people_directory()
returns table(id uuid,full_name text,email text,role public.user_role,learner_type text,organization_id uuid)
language plpgsql stable security definer set search_path=public as $$
declare v_role public.user_role; v_org uuid;
begin
  select p.role,p.organization_id into v_role,v_org from public.profiles p where p.id=auth.uid();
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  return query
  select p.id,p.full_name,p.email,p.role,p.learner_type,p.organization_id
  from public.profiles p
  where (v_role='admin' or v_org is null or p.organization_id=v_org)
    and p.role in ('student','instructor')
  order by case when p.role='student' then 0 else 1 end, lower(coalesce(p.full_name,p.email,''));
end;$$;
grant execute on function public.staff_people_directory() to authenticated;

-- One authoritative roster query for the Instructor "My Learners" page.
create or replace function public.staff_instructor_roster()
returns table(
  id uuid,
  full_name text,
  email text,
  learner_type text,
  course_titles text[],
  attempts_count bigint,
  completed_attempts bigint,
  average_score numeric
)
language plpgsql stable security definer set search_path=public as $$
declare v_role public.user_role;
begin
  select role into v_role from public.profiles where id=auth.uid();
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;

  return query
  with visible_members as (
    select distinct cm.student_id, cm.course_id
    from public.course_members cm
    join public.courses c on c.id=cm.course_id
    where v_role='admin' or c.instructor_id=auth.uid()
  ), roster as (
    select p.id,p.full_name,p.email,p.learner_type,
      array_agg(distinct c.title order by c.title) as course_titles
    from visible_members vm
    join public.profiles p on p.id=vm.student_id
    join public.courses c on c.id=vm.course_id
    where p.role='student'
    group by p.id,p.full_name,p.email,p.learner_type
  )
  select r.id,r.full_name,r.email,r.learner_type,r.course_titles,
    count(a.id)::bigint as attempts_count,
    count(a.id) filter(where a.status='completed')::bigint as completed_attempts,
    coalesce(round(avg(a.score) filter(where a.status='completed'),1),0)::numeric as average_score
  from roster r
  left join public.attempts a on a.student_id=r.id
  group by r.id,r.full_name,r.email,r.learner_type,r.course_titles
  order by lower(coalesce(r.full_name,r.email,''));
end;$$;
grant execute on function public.staff_instructor_roster() to authenticated;

-- Repair stale current_version pointers if any older draft/publish flow left them inconsistent.
update public.scenarios s
set current_version=x.latest_version
from (
  select scenario_id,max(version) latest_version from public.scenario_versions group by scenario_id
) x
where x.scenario_id=s.id
  and not exists(select 1 from public.scenario_versions sv where sv.scenario_id=s.id and sv.version=s.current_version);

-- Published catalog: prefer current_version, safely fall back to the latest saved version.
create or replace function public.list_published_simulations()
returns table(id uuid,title text,slug text,type public.scenario_type,description text,specialty text,difficulty text,estimated_minutes int,cover_url text)
language sql stable security definer set search_path=public as $$
  select s.id,s.title,s.slug,s.type,s.description,s.specialty,
    coalesce(v.config->>'difficulty','Beginner') as difficulty,
    coalesce(nullif(v.config->>'estimated_minutes','')::int,15) as estimated_minutes,
    nullif(v.config->>'cover_url','') as cover_url
  from public.scenarios s
  left join lateral (
    select sv.config,sv.version
    from public.scenario_versions sv
    where sv.scenario_id=s.id
    order by case when sv.version=s.current_version then 0 else 1 end, sv.version desc
    limit 1
  ) v on true
  where s.is_published=true and s.type='clinical_case'
  order by s.created_at desc;
$$;
grant execute on function public.list_published_simulations() to authenticated;

create or replace function public.get_simulation_brief(p_slug text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_s public.scenarios%rowtype; v_config jsonb; v_actions jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select s.*,v.config into v_s,v_config
  from public.scenarios s
  left join lateral (
    select sv.config,sv.version from public.scenario_versions sv
    where sv.scenario_id=s.id
    order by case when sv.version=s.current_version then 0 else 1 end,sv.version desc limit 1
  ) v on true
  where s.slug=p_slug and s.is_published=true limit 1;
  if v_s.id is null then raise exception 'Published scenario not found'; end if;
  v_config:=coalesce(v_config,'{}'::jsonb);
  select coalesce(jsonb_agg(jsonb_build_object('key',x.value->>'action','label',coalesce(x.value->>'label',x.value->>'action')) order by x.ord),'[]'::jsonb) into v_actions
  from jsonb_array_elements(coalesce(v_config->'rules','[]'::jsonb)) with ordinality as x(value,ord);
  return jsonb_build_object('id',v_s.id,'slug',v_s.slug,'title',v_s.title,'description',v_s.description,'specialty',v_s.specialty,'type',v_s.type,'difficulty',coalesce(v_config->>'difficulty','Beginner'),'estimatedMinutes',coalesce(nullif(v_config->>'estimated_minutes','')::int,15),'coverUrl',coalesce(v_config->>'cover_url',''),'patientImageUrl',coalesce(v_config->>'patient_image_url',''),'actions',v_actions);
end;$$;
grant execute on function public.get_simulation_brief(text) to authenticated;

-- Start the exact current version when available, otherwise latest saved version.
create or replace function public.start_simulation(p_slug text)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_version_id uuid; v_config jsonb; v_state jsonb; v_attempt_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select v.id,v.config into v_version_id,v_config
  from public.scenarios s
  join lateral (
    select sv.id,sv.config,sv.version from public.scenario_versions sv
    where sv.scenario_id=s.id
    order by case when sv.version=s.current_version then 0 else 1 end,sv.version desc limit 1
  ) v on true
  where s.slug=p_slug and s.is_published=true limit 1;
  if v_version_id is null then raise exception 'Published scenario has no saved builder version'; end if;

  v_state := coalesce(v_config->'runtime_initial_state', jsonb_build_object(
    'patient', jsonb_build_object(
      'spo2',coalesce((v_config#>>'{initial_state,spo2}')::int,96),
      'heartRate',coalesce((v_config#>>'{initial_state,heart_rate}')::int,80),
      'respiratoryRate',coalesce((v_config#>>'{initial_state,respiratory_rate}')::int,18),
      'condition','Awaiting assessment','status','stable'
    ),
    'score',0,'actions','[]'::jsonb,'performedActionKeys','[]'::jsonb,
    'messages',jsonb_build_array(jsonb_build_object('type','patient','text',coalesce(v_config#>>'{patient,openingComplaint}','Hello, nurse.'))),
    'elapsed',0
  ));
  insert into public.attempts(student_id,scenario_version_id,current_state,score)
  values(auth.uid(),v_version_id,v_state,0) returning id into v_attempt_id;
  return jsonb_build_object('attemptId',v_attempt_id,'state',v_state);
end;$$;
grant execute on function public.start_simulation(text) to authenticated;
