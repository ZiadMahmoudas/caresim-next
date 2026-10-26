-- CARESIM ONE-SHOT SETUP FOR A FRESH SUPABASE PROJECT
-- Run this file once in Supabase SQL Editor.
create extension if not exists "pgcrypto";
create type public.user_role as enum ('student','instructor','admin');
create type public.scenario_type as enum ('skill','clinical_case');
create type public.attempt_status as enum ('in_progress','completed','abandoned');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id),
  role public.user_role not null default 'student',
  full_name text not null default '',
  avatar_url text,
  bio text,
  academic_level text,
  specialization text,
  personal_skills text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  instructor_id uuid references public.profiles(id),
  title text not null,
  code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.course_members (
  course_id uuid references public.courses(id) on delete cascade,
  student_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(course_id, student_id)
);

create table public.scenarios (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id),
  type public.scenario_type not null,
  title text not null,
  slug text unique not null,
  description text,
  specialty text,
  current_version int not null default 1,
  is_published boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.scenario_versions (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references public.scenarios(id) on delete cascade,
  version int not null,
  config jsonb not null default '{}'::jsonb,
  rubric jsonb not null default '{}'::jsonb,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique(scenario_id, version)
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  scenario_id uuid not null references public.scenarios(id),
  assigned_by uuid not null references public.profiles(id),
  due_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  scenario_version_id uuid not null references public.scenario_versions(id),
  assignment_id uuid references public.assignments(id),
  status public.attempt_status not null default 'in_progress',
  current_state jsonb not null default '{}'::jsonb,
  score numeric(5,2) not null default 0,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.attempt_actions (
  id bigint generated always as identity primary key,
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  action_key text not null,
  payload jsonb not null default '{}'::jsonb,
  state_before jsonb not null,
  state_after jsonb not null,
  score_delta numeric(5,2) not null default 0,
  sequence_no int not null,
  created_at timestamptz not null default now(),
  unique(attempt_id, sequence_no)
);

create table public.attempt_results (
  attempt_id uuid primary key references public.attempts(id) on delete cascade,
  final_score numeric(5,2) not null,
  competency_scores jsonb not null default '{}'::jsonb,
  patient_outcome text,
  structured_debrief jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.skill_mastery (
  student_id uuid references public.profiles(id) on delete cascade,
  skill_key text not null,
  mastery numeric(5,2) not null default 0,
  attempts_count int not null default 0,
  best_score numeric(5,2) not null default 0,
  updated_at timestamptz not null default now(),
  primary key(student_id, skill_key)
);

create table public.ai_conversations (
  id bigint generated always as identity primary key,
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  role text not null check(role in ('student','patient','system')),
  message text not null,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.course_members enable row level security;
alter table public.scenarios enable row level security;
alter table public.scenario_versions enable row level security;
alter table public.assignments enable row level security;
alter table public.attempts enable row level security;
alter table public.attempt_actions enable row level security;
alter table public.attempt_results enable row level security;
alter table public.skill_mastery enable row level security;
alter table public.ai_conversations enable row level security;
alter table public.audit_logs enable row level security;

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid(); $$;

create policy "profile_self_read" on public.profiles for select using (id=auth.uid() or public.current_role() in ('instructor','admin'));
create policy "profile_self_update" on public.profiles for update using (id=auth.uid()) with check (id=auth.uid());
create policy "students_read_published_scenarios" on public.scenarios for select using (is_published=true or public.current_role() in ('instructor','admin'));
create policy "scenario_versions_read" on public.scenario_versions for select using (exists(select 1 from public.scenarios s where s.id=scenario_id and (s.is_published or public.current_role() in ('instructor','admin'))));
create policy "student_attempts_read" on public.attempts for select using (student_id=auth.uid() or public.current_role() in ('instructor','admin'));
create policy "student_attempts_insert" on public.attempts for insert with check (student_id=auth.uid());
create policy "student_attempt_actions_read" on public.attempt_actions for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.current_role() in ('instructor','admin'))));
create policy "student_results_read" on public.attempt_results for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.current_role() in ('instructor','admin'))));
create policy "student_mastery_read" on public.skill_mastery for select using (student_id=auth.uid() or public.current_role() in ('instructor','admin'));
create policy "ai_conversation_read" on public.ai_conversations for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.current_role() in ('instructor','admin'))));

-- Intentionally no INSERT/UPDATE policies for attempt_actions/results/score.
-- They should be written only by trusted server/Edge Function code using the secret/service role.

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

-- Server-authoritative simulation runtime. The browser cannot write scores/action logs directly.

drop policy if exists student_attempts_insert on public.attempts;

create or replace function public.start_simulation(p_slug text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_version_id uuid;
  v_config jsonb;
  v_state jsonb;
  v_attempt_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select sv.id,sv.config into v_version_id,v_config
  from public.scenarios s
  join public.scenario_versions sv on sv.scenario_id=s.id and sv.version=s.current_version
  where s.slug=p_slug and s.is_published=true
  limit 1;

  if v_version_id is null then raise exception 'Published scenario not found'; end if;

  v_state := coalesce(v_config->'runtime_initial_state', jsonb_build_object(
    'patient', jsonb_build_object(
      'spo2',coalesce((v_config#>>'{initial_state,spo2}')::int,86),
      'heartRate',coalesce((v_config#>>'{initial_state,heart_rate}')::int,112),
      'respiratoryRate',coalesce((v_config#>>'{initial_state,respiratory_rate}')::int,30),
      'condition','Moderate respiratory distress','status','unstable'
    ),
    'score',0,'actions','[]'::jsonb,'performedActionKeys','[]'::jsonb,
    'messages',jsonb_build_array(jsonb_build_object('type','patient','text','Nurse… I’m having difficulty breathing.')),
    'elapsed',0
  ));

  insert into public.attempts(student_id,scenario_version_id,current_state,score)
  values(auth.uid(),v_version_id,v_state,0)
  returning id into v_attempt_id;

  return jsonb_build_object('attemptId',v_attempt_id,'state',v_state);
end;$$;

grant execute on function public.start_simulation(text) to authenticated;

create or replace function public.perform_simulation_action(p_attempt_id uuid,p_action_key text,p_payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_attempt public.attempts%rowtype;
  v_config jsonb;
  v_rule jsonb;
  v_before jsonb;
  v_after jsonb;
  v_patient jsonb;
  v_effects jsonb;
  v_keys jsonb;
  v_requirements jsonb;
  v_req_met boolean := true;
  v_already boolean := false;
  v_delta numeric := 0;
  v_score numeric := 0;
  v_label text;
  v_message text;
  v_message_type text;
  v_seq int;
  kv record;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.uid() then raise exception 'Attempt not found'; end if;
  if v_attempt.status<>'in_progress' then raise exception 'Attempt is not active'; end if;

  select config into v_config from public.scenario_versions where id=v_attempt.scenario_version_id;
  select value into v_rule from jsonb_array_elements(coalesce(v_config->'rules','[]'::jsonb)) where value->>'action'=p_action_key limit 1;
  if v_rule is null then raise exception 'Action is not available in this scenario'; end if;

  v_before := v_attempt.current_state;
  v_after := v_before;
  v_keys := coalesce(v_before->'performedActionKeys','[]'::jsonb);
  v_already := v_keys ? p_action_key;
  v_requirements := coalesce(v_rule->'requires','[]'::jsonb);

  if jsonb_array_length(v_requirements)>0 then
    select coalesce(bool_and(v_keys ? req),true) into v_req_met from jsonb_array_elements_text(v_requirements) as r(req);
  end if;

  if v_already then
    v_delta := 0;
    v_label := coalesce(v_rule->>'label',p_action_key);
    v_message_type := 'system';
    v_message := 'This action has already been recorded. Repetition does not add points.';
  else
    v_delta := case when v_req_met then coalesce((v_rule->>'score')::numeric,0) else coalesce((v_rule->>'scoreIfMissingRequirements')::numeric,(v_rule->>'score')::numeric,0) end;
    v_label := coalesce(v_rule->>'label',p_action_key);
    v_message_type := coalesce(v_rule->>'messageType','system');
    v_message := coalesce(v_rule->>'message','Action recorded.');
    v_effects := case when v_req_met then coalesce(v_rule->'effects','{}'::jsonb) else coalesce(v_rule->'effectsIfMissingRequirements',v_rule->'effects','{}'::jsonb) end;
    v_patient := coalesce(v_after->'patient','{}'::jsonb);
    for kv in select key,value from jsonb_each(v_effects) loop
      v_patient := jsonb_set(v_patient,array[kv.key],kv.value,true);
    end loop;
    v_after := jsonb_set(v_after,'{patient}',v_patient,true);
    v_after := jsonb_set(v_after,'{actions}',coalesce(v_after->'actions','[]'::jsonb)||jsonb_build_array(v_label),true);
    v_after := jsonb_set(v_after,'{performedActionKeys}',v_keys||jsonb_build_array(p_action_key),true);
  end if;

  v_after := jsonb_set(v_after,'{messages}',coalesce(v_after->'messages','[]'::jsonb)||jsonb_build_array(jsonb_build_object('type',v_message_type,'text',v_message)),true);
  v_score := least(100,greatest(0,coalesce((v_before->>'score')::numeric,0)+v_delta));
  v_after := jsonb_set(v_after,'{score}',to_jsonb(v_score),true);

  select coalesce(max(sequence_no),0)+1 into v_seq from public.attempt_actions where attempt_id=p_attempt_id;
  insert into public.attempt_actions(attempt_id,action_key,payload,state_before,state_after,score_delta,sequence_no)
  values(p_attempt_id,p_action_key,coalesce(p_payload,'{}'::jsonb),v_before,v_after,v_delta,v_seq);

  update public.attempts set current_state=v_after,score=v_score where id=p_attempt_id;
  return jsonb_build_object('attemptId',p_attempt_id,'state',v_after);
end;$$;

grant execute on function public.perform_simulation_action(uuid,text,jsonb) to authenticated;

create or replace function public.append_simulation_message(p_attempt_id uuid,p_role text,p_message text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_attempt public.attempts%rowtype; v_state jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_role not in ('student','patient') then raise exception 'Invalid message role'; end if;
  if length(trim(p_message))=0 or length(p_message)>1000 then raise exception 'Invalid message'; end if;
  if p_role='student' and (select count(*) from public.ai_conversations where attempt_id=p_attempt_id and role='student')>=30 then raise exception 'Conversation limit reached for this attempt'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.uid() or v_attempt.status<>'in_progress' then raise exception 'Attempt not found'; end if;
  v_state := jsonb_set(v_attempt.current_state,'{messages}',coalesce(v_attempt.current_state->'messages','[]'::jsonb)||jsonb_build_array(jsonb_build_object('type',p_role,'text',p_message)),true);
  update public.attempts set current_state=v_state where id=p_attempt_id;
  insert into public.ai_conversations(attempt_id,role,message) values(p_attempt_id,p_role,p_message);
end;$$;

grant execute on function public.append_simulation_message(uuid,text,text) to authenticated;

create or replace function public.finish_simulation(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_attempt public.attempts%rowtype;
  v_state jsonb;
  v_keys jsonb;
  v_actions jsonb;
  v_score numeric;
  v_comp jsonb;
  v_outcome text;
  v_debrief jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.uid() then raise exception 'Attempt not found'; end if;
  v_state:=v_attempt.current_state;v_keys:=coalesce(v_state->'performedActionKeys','[]'::jsonb);v_actions:=coalesce(v_state->'actions','[]'::jsonb);v_score:=least(100,greatest(0,coalesce((v_state->>'score')::numeric,v_attempt.score,0)));
  v_comp:=jsonb_build_object('assessment',case when v_keys?'check_vitals' then 90 else 55 end,'patient_safety',case when v_keys?'oxygen' then 92 else 60 end,'clinical_reasoning',case when jsonb_array_length(v_keys)>=5 then 84 else 68 end,'reassessment',case when v_keys?'reassess' then 88 else 50 end);
  v_outcome:=case when v_state#>>'{patient,status}'='improving' then 'Stable / improving' else 'Requires further intervention' end;
  v_debrief:=jsonb_build_object('what_went_well',v_actions,'improve_next','Complete a full assessment, intervene promptly, and reassess after every meaningful intervention.');
  update public.attempts set status='completed',score=v_score,completed_at=now() where id=p_attempt_id;
  insert into public.attempt_results(attempt_id,final_score,competency_scores,patient_outcome,structured_debrief)
  values(p_attempt_id,v_score,v_comp,v_outcome,v_debrief)
  on conflict(attempt_id) do update set final_score=excluded.final_score,competency_scores=excluded.competency_scores,patient_outcome=excluded.patient_outcome,structured_debrief=excluded.structured_debrief;

  insert into public.skill_mastery(student_id,skill_key,mastery,attempts_count,best_score,updated_at)
  values(auth.uid(),'respiratory_distress',v_score,1,v_score,now())
  on conflict(student_id,skill_key) do update set
    mastery=round(((skill_mastery.mastery*skill_mastery.attempts_count)+excluded.mastery)/(skill_mastery.attempts_count+1),2),
    attempts_count=skill_mastery.attempts_count+1,
    best_score=greatest(skill_mastery.best_score,excluded.best_score),
    updated_at=now();

  return jsonb_build_object('finalScore',v_score,'competencyScores',v_comp,'patientOutcome',v_outcome,'debrief',v_debrief);
end;$$;

grant execute on function public.finish_simulation(uuid) to authenticated;

insert into public.organizations (id,name,slug) values ('11111111-1111-1111-1111-111111111111','CareSim University','caresim-university') on conflict do nothing;
insert into public.scenarios (id,organization_id,type,title,slug,description,specialty,current_version,is_published)
values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','clinical_case','Respiratory Distress','respiratory-distress','Assess an evolving patient with acute shortness of breath.','Emergency Department',1,true) on conflict do nothing;
insert into public.scenario_versions (scenario_id,version,config,rubric,published_at)
values (
 '22222222-2222-2222-2222-222222222222',1,
 $json${
  "patient":{"name":"Robert","age":67,"complaint":"shortness of breath","history":["COPD","hypertension"],"symptoms_started":"2 hours ago","chest_pain":false,"allergies":"none known"},
  "runtime_initial_state":{"patient":{"spo2":86,"heartRate":112,"respiratoryRate":30,"condition":"Moderate respiratory distress","status":"unstable"},"score":0,"actions":[],"performedActionKeys":[],"messages":[{"type":"patient","text":"Nurse… I’m having difficulty breathing."}],"elapsed":0},
  "rules":[
    {"action":"check_vitals","label":"Checked vital signs","score":10,"effects":{},"messageType":"system","message":"Vitals assessed: SpO₂ 86%, HR 112, RR 30."},
    {"action":"assess_breathing","label":"Assessed breathing","score":10,"effects":{},"messageType":"patient","message":"It feels tight. I cannot catch my breath."},
    {"action":"history","label":"Reviewed patient history","score":10,"effects":{},"messageType":"patient","message":"I have COPD and high blood pressure. This started about two hours ago."},
    {"action":"position_upright","label":"Positioned patient upright","score":15,"effects":{"spo2":88,"respiratoryRate":27,"condition":"Slight improvement"},"messageType":"patient","message":"Sitting up helps a little."},
    {"action":"oxygen","label":"Administered oxygen","score":25,"requires":["check_vitals"],"scoreIfMissingRequirements":12,"effects":{"spo2":94,"respiratoryRate":23,"condition":"Improving","status":"improving"},"effectsIfMissingRequirements":{"spo2":91,"respiratoryRate":25,"condition":"Partial improvement","status":"unstable"},"messageType":"patient","message":"I can breathe more easily now."},
    {"action":"reassess","label":"Reassessed patient","score":15,"effects":{},"messageType":"system","message":"Reassessment documented. Review the current vital signs."},
    {"action":"escalate","label":"Escalated care","score":15,"effects":{},"messageType":"system","message":"Escalation initiated and the clinical team has been notified."}
  ]
 }$json$::jsonb,
 '{"assessment":20,"clinical_reasoning":25,"patient_safety":25,"timing":10,"intervention":10,"reassessment":10}'::jsonb,
 now()
) on conflict (scenario_id,version) do update set config=excluded.config,rubric=excluded.rubric,published_at=excluded.published_at;

-- ===== Notifications (CareSim v4) =====
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'info' check(kind in ('info','success','assignment','achievement')),
  href text,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
drop policy if exists notification_self_read on public.notifications;
create policy notification_self_read on public.notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists notification_self_update on public.notifications;
create policy notification_self_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select on public.notifications to authenticated;
grant update(is_read,read_at) on public.notifications to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name,learner_type,role)
  values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''),case when new.raw_user_meta_data->>'learner_type'='nurse' then 'nurse' else 'student' end,'student')
  on conflict(id) do update set email=excluded.email;
  insert into public.notifications(user_id,title,body,kind,href)
  select new.id,'Welcome to CareSim','Your learner profile is ready. Start with a clinical simulation or complete your profile.','success','/dashboard'
  where not exists(select 1 from public.notifications where user_id=new.id and title='Welcome to CareSim');
  return new;
end;$$;

create or replace function public.notify_attempt_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_title text;
begin
  select a.student_id,s.title into v_user,v_title
  from public.attempts a join public.scenario_versions sv on sv.id=a.scenario_version_id join public.scenarios s on s.id=sv.scenario_id
  where a.id=new.attempt_id;
  if v_user is not null then
    insert into public.notifications(user_id,title,body,kind,href)
    values(v_user,'Simulation completed',coalesce(v_title,'Clinical simulation')||' completed with a score of '||round(new.final_score)::text||'%.','achievement','/progress');
  end if;
  return new;
end;$$;
drop trigger if exists on_attempt_result_notification on public.attempt_results;
create trigger on_attempt_result_notification after insert on public.attempt_results for each row execute function public.notify_attempt_result();

-- ===== CareSim v5: training catalog + avatar policy repair =====
drop policy if exists avatar_select_authenticated on storage.objects;
create policy avatar_select_authenticated on storage.objects for select to authenticated using(bucket_id='avatars');

drop policy if exists avatar_insert_own on storage.objects;
create policy avatar_insert_own on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_update_own on storage.objects;
create policy avatar_update_own on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_delete_own on storage.objects;
create policy avatar_delete_own on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.admin_create_training_skill(p_title text,p_description text default null,p_specialty text default null,p_difficulty text default 'Beginner')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_id uuid; v_slug text; v_base text; v_counter int:=0;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select role into v_role from public.profiles where id=auth.uid();
 if v_role not in ('admin','instructor') then raise exception 'Admin or instructor access required'; end if;
 if length(trim(coalesce(p_title,'')))<3 then raise exception 'Title is required'; end if;
 v_base:=lower(regexp_replace(trim(p_title),'[^a-zA-Z0-9]+','-','g')); v_base:=trim(both '-' from v_base); if v_base='' then v_base:='training-skill'; end if;
 v_slug:=v_base; while exists(select 1 from public.scenarios where slug=v_slug) loop v_counter:=v_counter+1;v_slug:=v_base||'-'||v_counter::text;end loop;
 insert into public.scenarios(type,title,slug,description,specialty,current_version,is_published,created_by) values('skill',trim(p_title),v_slug,nullif(trim(coalesce(p_description,'')),''),nullif(trim(coalesce(p_specialty,'')),''),1,false,auth.uid()) returning id into v_id;
 insert into public.scenario_versions(scenario_id,version,config,rubric) values(v_id,1,jsonb_build_object('difficulty',coalesce(nullif(trim(p_difficulty),''),'Beginner'),'module_status','catalog','rules','[]'::jsonb),'{}'::jsonb);
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'training_skill_created','scenario',v_id::text,jsonb_build_object('title',trim(p_title)));
 return v_id;
end;$$;
grant execute on function public.admin_create_training_skill(text,text,text,text) to authenticated;

create or replace function public.admin_set_scenario_published(p_scenario_id uuid,p_published boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select role into v_role from public.profiles where id=auth.uid();
 if v_role not in ('admin','instructor') then raise exception 'Admin or instructor access required'; end if;
 update public.scenarios set is_published=p_published where id=p_scenario_id;
 if not found then raise exception 'Scenario not found'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),case when p_published then 'scenario_published' else 'scenario_unpublished' end,'scenario',p_scenario_id::text,'{}'::jsonb);
end;$$;
grant execute on function public.admin_set_scenario_published(uuid,boolean) to authenticated;


-- ===== CareSim v6: staff workspace / course management =====
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
