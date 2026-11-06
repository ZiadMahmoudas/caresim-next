

-- ===== SOURCE: original CareSim fresh schema (adapted for Neon) =====
-- CARESIM ONE-SHOT SETUP FOR A FRESH NEON DATABASE
-- Enable Managed Better Auth + Data API first, then run this file in Neon SQL Editor.
create extension if not exists "pgcrypto";
do $$ begin create type public.user_role as enum ('student','instructor','admin'); exception when duplicate_object then null; end $$;
do $$ begin create type public.scenario_type as enum ('skill','clinical_case'); exception when duplicate_object then null; end $$;
do $$ begin create type public.attempt_status as enum ('in_progress','completed','abandoned'); exception when duplicate_object then null; end $$;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id text primary key,
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
  instructor_id text references public.profiles(id),
  title text not null,
  code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.course_members (
  course_id uuid references public.courses(id) on delete cascade,
  student_id text references public.profiles(id) on delete cascade,
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
  created_by text references public.profiles(id),
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
  assigned_by text not null references public.profiles(id),
  due_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  student_id text not null references public.profiles(id) on delete cascade,
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
  student_id text references public.profiles(id) on delete cascade,
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
  actor_id text references public.profiles(id),
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

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.user_id(); $$;

create policy "profile_self_read" on public.profiles for select using (id=auth.user_id() or public.current_role() in ('instructor','admin'));
create policy "profile_self_update" on public.profiles for update using (id=auth.user_id()) with check (id=auth.user_id());
create policy "students_read_published_scenarios" on public.scenarios for select using (is_published=true or public.current_role() in ('instructor','admin'));
create policy "scenario_versions_read" on public.scenario_versions for select using (exists(select 1 from public.scenarios s where s.id=scenario_id and (s.is_published or public.current_role() in ('instructor','admin'))));
create policy "student_attempts_read" on public.attempts for select using (student_id=auth.user_id() or public.current_role() in ('instructor','admin'));
create policy "student_attempts_insert" on public.attempts for insert with check (student_id=auth.user_id());
create policy "student_attempt_actions_read" on public.attempt_actions for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.user_id() or public.current_role() in ('instructor','admin'))));
create policy "student_results_read" on public.attempt_results for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.user_id() or public.current_role() in ('instructor','admin'))));
create policy "student_mastery_read" on public.skill_mastery for select using (student_id=auth.user_id() or public.current_role() in ('instructor','admin'));
create policy "ai_conversation_read" on public.ai_conversations for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.user_id() or public.current_role() in ('instructor','admin'))));

-- Intentionally no INSERT/UPDATE policies for attempt_actions/results/score.
-- They should be written only by trusted server/Edge Function code using the secret/service role.

-- CareSim production authentication, profile provisioning and role hardening
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists learner_type text not null default 'student' check (learner_type in ('student','nurse'));

-- Organizations are not public browsing data.
alter table public.organizations enable row level security;
drop policy if exists organizations_authenticated_read on public.organizations;
create policy organizations_authenticated_read on public.organizations for select to authenticated using(true);

update public.profiles p set email=u.email from neon_auth.user u where p.id=u.id and p.email is null;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name,learner_type,role)
  values(new.id,new.email,coalesce(new.name,''),'student','student')
  on conflict(id) do update set email=excluded.email;
  return new;
end;$$;

drop trigger if exists on_neon_auth_user_created on neon_auth.user;
create trigger on_neon_auth_user_created after insert or update of email,name on neon_auth.user for each row execute procedure public.handle_new_user();

-- Backfill missing profiles for existing Auth users.
insert into public.profiles(id,email,full_name,learner_type,role)
select u.id,u.email,coalesce(u.name,''),'student','student'::public.user_role
from neon_auth.user u left join public.profiles p on p.id=u.id where p.id is null;

-- Users may edit only safe profile columns. Role is deliberately excluded.
revoke update on public.profiles from authenticated;
grant update(full_name,avatar_url,bio,academic_level,specialization,personal_skills,learner_type,updated_at) on public.profiles to authenticated;
grant select on public.profiles to authenticated;

create or replace function public.admin_set_user_role(target_user_id text,new_role public.user_role)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_role() <> 'admin' then raise exception 'Admin access required'; end if;
  if target_user_id = auth.user_id() and new_role <> 'admin' then raise exception 'You cannot remove your own admin access'; end if;
  update public.profiles set role=new_role,updated_at=now() where id=target_user_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.user_id(),'role_changed','profile',target_user_id::text,jsonb_build_object('new_role',new_role));
end;$$;
grant execute on function public.admin_set_user_role(text,public.user_role) to authenticated;

-- Profile self update remains row-restricted; admin role changes happen only through the secured RPC above.
drop policy if exists profile_self_update on public.profiles;
create policy profile_self_update on public.profiles for update using(id=auth.user_id()) with check(id=auth.user_id());

-- Avatar files are stored in Neon Object Storage (see neon.ts).

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
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

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
  values(auth.user_id(),v_version_id,v_state,0)
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
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.user_id() then raise exception 'Attempt not found'; end if;
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
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
  if p_role not in ('student','patient') then raise exception 'Invalid message role'; end if;
  if length(trim(p_message))=0 or length(p_message)>1000 then raise exception 'Invalid message'; end if;
  if p_role='student' and (select count(*) from public.ai_conversations where attempt_id=p_attempt_id and role='student')>=30 then raise exception 'Conversation limit reached for this attempt'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.user_id() or v_attempt.status<>'in_progress' then raise exception 'Attempt not found'; end if;
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
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.user_id() then raise exception 'Attempt not found'; end if;
  v_state:=v_attempt.current_state;v_keys:=coalesce(v_state->'performedActionKeys','[]'::jsonb);v_actions:=coalesce(v_state->'actions','[]'::jsonb);v_score:=least(100,greatest(0,coalesce((v_state->>'score')::numeric,v_attempt.score,0)));
  v_comp:=jsonb_build_object('assessment',case when v_keys?'check_vitals' then 90 else 55 end,'patient_safety',case when v_keys?'oxygen' then 92 else 60 end,'clinical_reasoning',case when jsonb_array_length(v_keys)>=5 then 84 else 68 end,'reassessment',case when v_keys?'reassess' then 88 else 50 end);
  v_outcome:=case when v_state#>>'{patient,status}'='improving' then 'Stable / improving' else 'Requires further intervention' end;
  v_debrief:=jsonb_build_object('what_went_well',v_actions,'improve_next','Complete a full assessment, intervene promptly, and reassess after every meaningful intervention.');
  update public.attempts set status='completed',score=v_score,completed_at=now() where id=p_attempt_id;
  insert into public.attempt_results(attempt_id,final_score,competency_scores,patient_outcome,structured_debrief)
  values(p_attempt_id,v_score,v_comp,v_outcome,v_debrief)
  on conflict(attempt_id) do update set final_score=excluded.final_score,competency_scores=excluded.competency_scores,patient_outcome=excluded.patient_outcome,structured_debrief=excluded.structured_debrief;

  insert into public.skill_mastery(student_id,skill_key,mastery,attempts_count,best_score,updated_at)
  values(auth.user_id(),'respiratory_distress',v_score,1,v_score,now())
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
  user_id text not null references public.profiles(id) on delete cascade,
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
create policy notification_self_read on public.notifications for select to authenticated using(user_id=auth.user_id());
drop policy if exists notification_self_update on public.notifications;
create policy notification_self_update on public.notifications for update to authenticated using(user_id=auth.user_id()) with check(user_id=auth.user_id());
grant select on public.notifications to authenticated;
grant update(is_read,read_at) on public.notifications to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name,learner_type,role)
  values(new.id,new.email,coalesce(new.name,''),'student','student')
  on conflict(id) do update set email=excluded.email;
  insert into public.notifications(user_id,title,body,kind,href)
  select new.id,'Welcome to CareSim','Your learner profile is ready. Start with a clinical simulation or complete your profile.','success','/dashboard'
  where not exists(select 1 from public.notifications where user_id=new.id and title='Welcome to CareSim');
  return new;
end;$$;

create or replace function public.notify_attempt_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_user text; v_title text;
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

-- ===== CareSim v5: training catalog =====
create or replace function public.admin_create_training_skill(p_title text,p_description text default null,p_specialty text default null,p_difficulty text default 'Beginner')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_id uuid; v_slug text; v_base text; v_counter int:=0;
begin
 if auth.user_id() is null then raise exception 'Authentication required'; end if;
 select role into v_role from public.profiles where id=auth.user_id();
 if v_role not in ('admin','instructor') then raise exception 'Admin or instructor access required'; end if;
 if length(trim(coalesce(p_title,'')))<3 then raise exception 'Title is required'; end if;
 v_base:=lower(regexp_replace(trim(p_title),'[^a-zA-Z0-9]+','-','g')); v_base:=trim(both '-' from v_base); if v_base='' then v_base:='training-skill'; end if;
 v_slug:=v_base; while exists(select 1 from public.scenarios where slug=v_slug) loop v_counter:=v_counter+1;v_slug:=v_base||'-'||v_counter::text;end loop;
 insert into public.scenarios(type,title,slug,description,specialty,current_version,is_published,created_by) values('skill',trim(p_title),v_slug,nullif(trim(coalesce(p_description,'')),''),nullif(trim(coalesce(p_specialty,'')),''),1,false,auth.user_id()) returning id into v_id;
 insert into public.scenario_versions(scenario_id,version,config,rubric) values(v_id,1,jsonb_build_object('difficulty',coalesce(nullif(trim(p_difficulty),''),'Beginner'),'module_status','catalog','rules','[]'::jsonb),'{}'::jsonb);
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'training_skill_created','scenario',v_id::text,jsonb_build_object('title',trim(p_title)));
 return v_id;
end;$$;
grant execute on function public.admin_create_training_skill(text,text,text,text) to authenticated;

create or replace function public.admin_set_scenario_published(p_scenario_id uuid,p_published boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role;
begin
 if auth.user_id() is null then raise exception 'Authentication required'; end if;
 select role into v_role from public.profiles where id=auth.user_id();
 if v_role not in ('admin','instructor') then raise exception 'Admin or instructor access required'; end if;
 update public.scenarios set is_published=p_published where id=p_scenario_id;
 if not found then raise exception 'Scenario not found'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),case when p_published then 'scenario_published' else 'scenario_unpublished' end,'scenario',p_scenario_id::text,'{}'::jsonb);
end;$$;
grant execute on function public.admin_set_scenario_published(uuid,boolean) to authenticated;


-- ===== CareSim v6: staff workspace / course management =====
-- CareSim v6: complete staff workspaces, course/assignment management and storage hardening.

-- 1) Storage is managed by Neon Object Storage (see neon.ts).

-- 2) Staff read policies for courses, rosters, assignments and audit logs.
alter table public.courses enable row level security;
alter table public.course_members enable row level security;
alter table public.assignments enable row level security;
alter table public.audit_logs enable row level security;

grant select on public.courses, public.course_members, public.assignments, public.audit_logs to authenticated;

create or replace function public.can_manage_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.current_role()='admin' or exists(select 1 from public.courses c where c.id=p_course_id and c.instructor_id=auth.user_id());
$$;
grant execute on function public.can_manage_course(uuid) to authenticated;

create or replace function public.can_view_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.current_role()='admin'
    or exists(select 1 from public.courses c where c.id=p_course_id and c.instructor_id=auth.user_id())
    or exists(select 1 from public.course_members cm where cm.course_id=p_course_id and cm.student_id=auth.user_id());
$$;
grant execute on function public.can_view_course(uuid) to authenticated;

drop policy if exists courses_staff_and_member_read on public.courses;
create policy courses_staff_and_member_read on public.courses for select to authenticated using(public.can_view_course(id));

drop policy if exists course_members_staff_and_self_read on public.course_members;
create policy course_members_staff_and_self_read on public.course_members for select to authenticated using(student_id=auth.user_id() or public.can_manage_course(course_id));

drop policy if exists assignments_staff_and_student_read on public.assignments;
create policy assignments_staff_and_student_read on public.assignments for select to authenticated using(public.can_view_course(course_id));

drop policy if exists audit_admin_read on public.audit_logs;
create policy audit_admin_read on public.audit_logs for select to authenticated using(public.current_role()='admin');

-- 3) Course management. Instructors manage their own courses; admins manage everything.
create or replace function public.staff_create_course(p_title text,p_code text default null,p_instructor_id text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_org uuid; v_instructor text; v_id uuid;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
  select role,organization_id into v_role,v_org from public.profiles where id=auth.user_id();
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  if length(trim(coalesce(p_title,'')))<3 then raise exception 'Course title is required'; end if;
  if v_org is null then select id into v_org from public.organizations order by created_at limit 1; end if;
  if v_org is null then insert into public.organizations(name,slug) values('CareSim Academy','caresim-academy') returning id into v_org; end if;
  v_instructor := case when v_role='instructor' then auth.user_id() else p_instructor_id end;
  insert into public.courses(organization_id,instructor_id,title,code,is_active)
  values(v_org,v_instructor,trim(p_title),nullif(trim(coalesce(p_code,'')),''),true) returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.user_id(),'course_created','course',v_id::text,jsonb_build_object('title',trim(p_title)));
  return v_id;
end;$$;
grant execute on function public.staff_create_course(text,text,text) to authenticated;

create or replace function public.staff_update_course(p_course_id uuid,p_title text,p_code text,p_instructor_id text,p_is_active boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner text;
begin
  select role into v_role from public.profiles where id=auth.user_id();
  select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.user_id() then raise exception 'You can only edit your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.courses set title=trim(p_title),code=nullif(trim(coalesce(p_code,'')),''),instructor_id=case when v_role='admin' then p_instructor_id else auth.user_id() end,is_active=coalesce(p_is_active,true) where id=p_course_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'course_updated','course',p_course_id::text,'{}');
end;$$;
grant execute on function public.staff_update_course(uuid,text,text,text,boolean) to authenticated;

create or replace function public.staff_delete_course(p_course_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner text;
begin
  select role into v_role from public.profiles where id=auth.user_id();
  select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.user_id() then raise exception 'You can only delete your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.attempts set assignment_id=null where assignment_id in(select id from public.assignments where course_id=p_course_id);
  delete from public.courses where id=p_course_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'course_deleted','course',p_course_id::text,'{}');
end;$$;
grant execute on function public.staff_delete_course(uuid) to authenticated;

create or replace function public.staff_add_course_member(p_course_id uuid,p_student_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner text; v_target_role public.user_role;
begin
  select role into v_role from public.profiles where id=auth.user_id();
  select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.user_id() then raise exception 'You can only manage your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  select role into v_target_role from public.profiles where id=p_student_id;
  if v_target_role<>'student' then raise exception 'Only learner accounts can be enrolled'; end if;
  insert into public.course_members(course_id,student_id) values(p_course_id,p_student_id) on conflict do nothing;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'course_member_added','course',p_course_id::text,jsonb_build_object('student_id',p_student_id));
end;$$;
grant execute on function public.staff_add_course_member(uuid,text) to authenticated;

create or replace function public.staff_remove_course_member(p_course_id uuid,p_student_id text)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner text;
begin
  select role into v_role from public.profiles where id=auth.user_id(); select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.user_id() then raise exception 'You can only manage your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  delete from public.course_members where course_id=p_course_id and student_id=p_student_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'course_member_removed','course',p_course_id::text,jsonb_build_object('student_id',p_student_id));
end;$$;
grant execute on function public.staff_remove_course_member(uuid,text) to authenticated;

create or replace function public.staff_create_assignment(p_course_id uuid,p_scenario_id uuid,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner text; v_id uuid;
begin
  select role into v_role from public.profiles where id=auth.user_id(); select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.user_id() then raise exception 'You can only assign work to your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  insert into public.assignments(course_id,scenario_id,assigned_by,due_at) values(p_course_id,p_scenario_id,auth.user_id(),p_due_at) returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'assignment_created','assignment',v_id::text,jsonb_build_object('course_id',p_course_id,'scenario_id',p_scenario_id));
  return v_id;
end;$$;
grant execute on function public.staff_create_assignment(uuid,uuid,timestamptz) to authenticated;

create or replace function public.staff_delete_assignment(p_assignment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner text;
begin
  select p.role,c.instructor_id into v_role,v_owner from public.profiles p, public.assignments a join public.courses c on c.id=a.course_id where p.id=auth.user_id() and a.id=p_assignment_id;
  if v_role='instructor' and v_owner<>auth.user_id() then raise exception 'You can only manage assignments in your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.attempts set assignment_id=null where assignment_id=p_assignment_id;
  delete from public.assignments where id=p_assignment_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'assignment_deleted','assignment',p_assignment_id::text,'{}');
end;$$;
grant execute on function public.staff_delete_assignment(uuid) to authenticated;

-- 4) Scenario catalog CRUD for staff. Scenario logic/rubric can be enriched later by the clinical builder.
create or replace function public.staff_create_scenario(p_type public.scenario_type,p_title text,p_description text default null,p_specialty text default null,p_difficulty text default 'Beginner')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_id uuid; v_slug text; v_base text; n int:=0; v_org uuid;
begin
  select role,organization_id into v_role,v_org from public.profiles where id=auth.user_id();
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  if length(trim(coalesce(p_title,'')))<3 then raise exception 'Title is required'; end if;
  v_base:=trim(both '-' from lower(regexp_replace(trim(p_title),'[^a-zA-Z0-9]+','-','g'))); if v_base='' then v_base:='scenario'; end if; v_slug:=v_base;
  while exists(select 1 from public.scenarios where slug=v_slug) loop n:=n+1;v_slug:=v_base||'-'||n::text; end loop;
  insert into public.scenarios(organization_id,type,title,slug,description,specialty,current_version,is_published,created_by)
  values(v_org,p_type,trim(p_title),v_slug,nullif(trim(coalesce(p_description,'')),''),nullif(trim(coalesce(p_specialty,'')),''),1,false,auth.user_id()) returning id into v_id;
  insert into public.scenario_versions(scenario_id,version,config,rubric) values(v_id,1,jsonb_build_object('difficulty',p_difficulty,'runtime_initial_state','{}'::jsonb,'rules','[]'::jsonb),'{}');
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'scenario_created','scenario',v_id::text,jsonb_build_object('type',p_type,'title',trim(p_title)));
  return v_id;
end;$$;
grant execute on function public.staff_create_scenario(public.scenario_type,text,text,text,text) to authenticated;

create or replace function public.staff_update_scenario(p_scenario_id uuid,p_title text,p_description text,p_specialty text,p_published boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role;
begin
  select role into v_role from public.profiles where id=auth.user_id(); if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  update public.scenarios set title=trim(p_title),description=nullif(trim(coalesce(p_description,'')),''),specialty=nullif(trim(coalesce(p_specialty,'')),''),is_published=p_published where id=p_scenario_id;
  if not found then raise exception 'Scenario not found'; end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'scenario_updated','scenario',p_scenario_id::text,jsonb_build_object('published',p_published));
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
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'scenario_deleted','scenario',p_scenario_id::text,'{}');
end;$$;
grant execute on function public.admin_delete_scenario(uuid) to authenticated;

-- 5) Scope instructor clinical data to learners enrolled in their courses.
create or replace function public.staff_can_view_student(p_student_id text)
returns boolean language sql stable security definer set search_path=public as $$
  select case
    when public.current_role()='admin' then true
    when public.current_role()='instructor' then exists(
      select 1 from public.course_members cm join public.courses c on c.id=cm.course_id
      where cm.student_id=p_student_id and c.instructor_id=auth.user_id()
    )
    else false
  end;
$$;
grant execute on function public.staff_can_view_student(text) to authenticated;

drop policy if exists student_attempts_read on public.attempts;
create policy student_attempts_read on public.attempts for select to authenticated using(student_id=auth.user_id() or public.staff_can_view_student(student_id));
drop policy if exists student_attempt_actions_read on public.attempt_actions;
create policy student_attempt_actions_read on public.attempt_actions for select to authenticated using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.user_id() or public.staff_can_view_student(a.student_id))));
drop policy if exists student_results_read on public.attempt_results;
create policy student_results_read on public.attempt_results for select to authenticated using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.user_id() or public.staff_can_view_student(a.student_id))));
drop policy if exists student_mastery_read on public.skill_mastery;
create policy student_mastery_read on public.skill_mastery for select to authenticated using(student_id=auth.user_id() or public.staff_can_view_student(student_id));
drop policy if exists ai_conversation_read on public.ai_conversations;
create policy ai_conversation_read on public.ai_conversations for select to authenticated using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.user_id() or public.staff_can_view_student(a.student_id))));


-- ===== SOURCE: RUN_THIS_IN_NEON_V9.sql (adapted for Neon) =====
-- CareSim v9: Instructor Scenario Builder + knowledge retrieval + assessment grading.
-- Run after v6 migrations. Safe to re-run where possible.

create extension if not exists pgcrypto;

create table if not exists public.scenario_questions (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references public.scenarios(id) on delete cascade,
  question_text text not null,
  question_type text not null default 'single_choice' check(question_type in ('single_choice','true_false','short_text')),
  options jsonb not null default '[]'::jsonb,
  correct_answer jsonb not null default 'null'::jsonb,
  explanation text,
  points numeric(6,2) not null default 10 check(points > 0),
  order_no int not null default 1,
  created_at timestamptz not null default now()
);

create table if not exists public.attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  question_id uuid not null references public.scenario_questions(id) on delete cascade,
  answer jsonb not null default 'null'::jsonb,
  is_correct boolean not null default false,
  awarded_points numeric(6,2) not null default 0,
  created_at timestamptz not null default now(),
  unique(attempt_id, question_id)
);

create table if not exists public.knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  scenario_id uuid references public.scenarios(id) on delete cascade,
  course_id uuid references public.courses(id) on delete cascade,
  title text not null,
  source_type text not null default 'reference' check(source_type in ('platform','specialty','scenario','course','reference')),
  content text not null,
  visibility text not null default 'authenticated' check(visibility in ('public','authenticated','staff')),
  uploaded_by text references public.profiles(id) on delete set null,
  storage_path text,
  is_active boolean not null default true,
  search_vector tsvector generated always as (to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(content,''))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists knowledge_sources_search_idx on public.knowledge_sources using gin(search_vector);
create index if not exists knowledge_sources_scenario_idx on public.knowledge_sources(scenario_id);

create table if not exists public.scenario_assets (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references public.scenarios(id) on delete cascade,
  uploaded_by text references public.profiles(id) on delete set null,
  kind text not null default 'patient' check(kind in ('cover','patient','reference')),
  name text not null,
  storage_path text not null,
  public_url text,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now()
);

alter table public.attempt_results add column if not exists clinical_score numeric(5,2);
alter table public.attempt_results add column if not exists assessment_score numeric(5,2);
alter table public.attempt_results add column if not exists passed boolean;

alter table public.scenario_questions enable row level security;
alter table public.attempt_answers enable row level security;
alter table public.knowledge_sources enable row level security;
alter table public.scenario_assets enable row level security;

grant select on public.scenario_questions, public.attempt_answers, public.knowledge_sources, public.scenario_assets to authenticated;

drop policy if exists scenario_questions_staff_read on public.scenario_questions;
create policy scenario_questions_staff_read on public.scenario_questions for select to authenticated
using(public.current_role() in ('admin','instructor'));

drop policy if exists attempt_answers_owner_staff_read on public.attempt_answers;
create policy attempt_answers_owner_staff_read on public.attempt_answers for select to authenticated
using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.user_id() or public.staff_can_view_student(a.student_id))));

drop policy if exists knowledge_sources_read on public.knowledge_sources;
create policy knowledge_sources_read on public.knowledge_sources for select to authenticated
using(is_active and (visibility in ('public','authenticated') or public.current_role() in ('admin','instructor')));

drop policy if exists scenario_assets_read on public.scenario_assets;
create policy scenario_assets_read on public.scenario_assets for select to authenticated
using(exists(select 1 from public.scenarios s where s.id=scenario_id and (s.is_published or public.current_role() in ('admin','instructor'))));

-- Scenario/patient artwork is stored in Neon Object Storage.

-- Staff can manage only scenarios they authored; admins can manage all.
create or replace function public.staff_can_manage_scenario(p_scenario_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select case
    when public.current_role()='admin' then true
    when public.current_role()='instructor' then exists(select 1 from public.scenarios s where s.id=p_scenario_id and s.created_by=auth.user_id())
    else false
  end;
$$;
grant execute on function public.staff_can_manage_scenario(uuid) to authenticated;

-- Full builder save. The builder remains server-authoritative and compiles its rules into scenario_versions.config.
create or replace function public.staff_save_scenario_builder(p_scenario_id uuid,p_payload jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_title text; v_description text; v_specialty text; v_difficulty text; v_estimated int;
  v_config jsonb; v_rubric jsonb; v_patient jsonb; v_vitals jsonb; v_rules jsonb; v_objectives jsonb;
  v_questions jsonb; v_q jsonb; v_notes text; v_content text; v_current_version int;
  v_clinical_weight numeric; v_assessment_weight numeric; v_passing numeric;
begin
  if auth.user_id() is null or not public.staff_can_manage_scenario(p_scenario_id) then raise exception 'You cannot manage this scenario'; end if;

  v_title:=trim(coalesce(p_payload#>>'{basics,title}',''));
  if length(v_title)<3 then raise exception 'Scenario title is required'; end if;
  v_description:=nullif(trim(coalesce(p_payload#>>'{basics,description}','')),'');
  v_specialty:=nullif(trim(coalesce(p_payload#>>'{basics,specialty}','')),'');
  v_difficulty:=coalesce(nullif(trim(p_payload#>>'{basics,difficulty}'),''),'Beginner');
  v_estimated:=greatest(1,least(180,coalesce((p_payload#>>'{basics,estimatedMinutes}')::int,15)));
  v_patient:=coalesce(p_payload->'patient','{}'::jsonb);
  v_vitals:=coalesce(p_payload->'vitals','{}'::jsonb);
  v_rules:=coalesce(p_payload->'actions','[]'::jsonb);
  v_objectives:=coalesce(p_payload->'objectives','[]'::jsonb);
  v_questions:=coalesce(p_payload->'questions','[]'::jsonb);
  v_notes:=nullif(trim(coalesce(p_payload#>>'{rag,notes}','')),'');
  v_clinical_weight:=greatest(0,least(100,coalesce((p_payload#>>'{scoring,clinicalWeight}')::numeric,70)));
  v_assessment_weight:=greatest(0,least(100,coalesce((p_payload#>>'{scoring,assessmentWeight}')::numeric,30)));
  if v_clinical_weight+v_assessment_weight=0 then v_clinical_weight:=100; v_assessment_weight:=0; end if;
  v_passing:=greatest(0,least(100,coalesce((p_payload#>>'{scoring,passingScore}')::numeric,70)));

  select current_version into v_current_version from public.scenarios where id=p_scenario_id for update;
  if v_current_version is null then raise exception 'Scenario not found'; end if;

  update public.scenarios set title=v_title,description=v_description,specialty=v_specialty where id=p_scenario_id;

  v_config:=jsonb_build_object(
    'difficulty',v_difficulty,
    'estimated_minutes',v_estimated,
    'objectives',v_objectives,
    'patient',v_patient,
    'cover_url',coalesce(p_payload#>>'{media,coverUrl}',''),
    'patient_image_url',coalesce(p_payload#>>'{media,patientImageUrl}',''),
    'rag_notes',coalesce(v_notes,''),
    'runtime_initial_state',jsonb_build_object(
      'patient',jsonb_build_object(
        'spo2',coalesce((v_vitals->>'spo2')::int,96),
        'heartRate',coalesce((v_vitals->>'heartRate')::int,80),
        'respiratoryRate',coalesce((v_vitals->>'respiratoryRate')::int,18),
        'bloodPressure',coalesce(v_vitals->>'bloodPressure','120/80'),
        'temperature',coalesce((v_vitals->>'temperature')::numeric,37),
        'condition',coalesce(v_vitals->>'condition','Awaiting assessment'),
        'status',coalesce(v_vitals->>'status','stable')
      ),
      'score',0,'actions','[]'::jsonb,'performedActionKeys','[]'::jsonb,
      'messages',jsonb_build_array(jsonb_build_object('type','patient','text',coalesce(v_patient->>'openingComplaint','Hello, nurse.'))),
      'elapsed',0
    ),
    'rules',v_rules
  );
  v_rubric:=jsonb_build_object('clinical_weight',v_clinical_weight,'assessment_weight',v_assessment_weight,'passing_score',v_passing);

  insert into public.scenario_versions(scenario_id,version,config,rubric)
  values(p_scenario_id,v_current_version,v_config,v_rubric)
  on conflict(scenario_id,version) do update set config=excluded.config,rubric=excluded.rubric;

  delete from public.scenario_questions where scenario_id=p_scenario_id;
  for v_q in select value from jsonb_array_elements(v_questions) loop
    if length(trim(coalesce(v_q->>'questionText','')))>0 then
      insert into public.scenario_questions(scenario_id,question_text,question_type,options,correct_answer,explanation,points,order_no)
      values(
        p_scenario_id,trim(v_q->>'questionText'),coalesce(v_q->>'type','single_choice'),coalesce(v_q->'options','[]'::jsonb),
        coalesce(v_q->'correctAnswer','null'::jsonb),nullif(trim(coalesce(v_q->>'explanation','')),''),
        greatest(1,coalesce((v_q->>'points')::numeric,10)),coalesce((v_q->>'orderNo')::int,1)
      );
    end if;
  end loop;

  v_content:=concat_ws(E'\n',
    'CareSim clinical scenario: '||v_title,
    'Specialty: '||coalesce(v_specialty,'General nursing'),
    'Description: '||coalesce(v_description,''),
    'Learning objectives: '||coalesce((select string_agg(value,'; ') from jsonb_array_elements_text(v_objectives)),''),
    'Patient profile: '||coalesce(v_patient::text,''),
    'Instructor reference notes: '||coalesce(v_notes,'')
  );
  delete from public.knowledge_sources where scenario_id=p_scenario_id and source_type='scenario';
  insert into public.knowledge_sources(organization_id,scenario_id,title,source_type,content,visibility,uploaded_by)
  select organization_id,p_scenario_id,v_title,'scenario',v_content,case when is_published then 'public' else 'staff' end,auth.user_id()
  from public.scenarios where id=p_scenario_id;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.user_id(),'scenario_builder_saved','scenario',p_scenario_id::text,jsonb_build_object('questions',jsonb_array_length(v_questions),'rules',jsonb_array_length(v_rules)));
end;$$;
grant execute on function public.staff_save_scenario_builder(uuid,jsonb) to authenticated;

create or replace function public.search_knowledge(p_query text,p_limit int default 6)
returns table(id uuid,title text,source_type text,content text,scenario_id uuid,rank real)
language sql stable security definer set search_path=public as $$
  select k.id,k.title,k.source_type,k.content,k.scenario_id,
         ts_rank_cd(k.search_vector,websearch_to_tsquery('simple',coalesce(nullif(trim(p_query),''),'CareSim'))) as rank
  from public.knowledge_sources k
  where k.is_active
    and (k.visibility='public' or (auth.user_id() is not null and k.visibility='authenticated') or (public.current_role() in ('admin','instructor') and k.visibility='staff'))
    and (k.search_vector @@ websearch_to_tsquery('simple',coalesce(nullif(trim(p_query),''),'CareSim'))
         or lower(k.title) like '%'||lower(trim(p_query))||'%'
         or lower(k.content) like '%'||lower(trim(p_query))||'%')
  order by rank desc,k.updated_at desc
  limit greatest(1,least(coalesce(p_limit,6),10));
$$;
grant execute on function public.search_knowledge(text,int) to anon,authenticated;

-- Save answers server-side. Correct answers never need to be exposed to the learner browser.
create or replace function public.submit_attempt_answer(p_attempt_id uuid,p_question_id uuid,p_answer jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_attempt public.attempts%rowtype; v_q public.scenario_questions%rowtype; v_correct boolean:=false; v_awarded numeric:=0; v_a text; v_c text;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id;
  if not found or v_attempt.student_id<>auth.user_id() or v_attempt.status<>'in_progress' then raise exception 'Attempt not found'; end if;
  select q.* into v_q from public.scenario_questions q join public.scenario_versions sv on sv.scenario_id=q.scenario_id where q.id=p_question_id and sv.id=v_attempt.scenario_version_id limit 1;
  if not found then raise exception 'Question not found'; end if;
  v_a:=lower(trim(both '"' from coalesce(p_answer::text,'')));
  v_c:=lower(trim(both '"' from coalesce(v_q.correct_answer::text,'')));
  if v_q.question_type='short_text' and jsonb_typeof(v_q.correct_answer)='array' then
    select exists(select 1 from jsonb_array_elements_text(v_q.correct_answer) x where lower(trim(x))=lower(trim(both '"' from coalesce(p_answer::text,'')))) into v_correct;
  else
    v_correct:=(v_a=v_c);
  end if;
  if v_correct then v_awarded:=v_q.points; end if;
  insert into public.attempt_answers(attempt_id,question_id,answer,is_correct,awarded_points)
  values(p_attempt_id,p_question_id,coalesce(p_answer,'null'::jsonb),v_correct,v_awarded)
  on conflict(attempt_id,question_id) do update set answer=excluded.answer,is_correct=excluded.is_correct,awarded_points=excluded.awarded_points,created_at=now();
  return jsonb_build_object('saved',true);
end;$$;
grant execute on function public.submit_attempt_answer(uuid,uuid,jsonb) to authenticated;

-- Generic final scoring: clinical rules + instructor-authored assessment.
create or replace function public.finish_simulation(p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_attempt public.attempts%rowtype; v_state jsonb; v_actions jsonb; v_scenario public.scenarios%rowtype; v_rubric jsonb;
  v_clinical numeric:=0; v_assessment numeric:=0; v_final numeric:=0; v_total_q int:=0; v_answered int:=0; v_total_pts numeric:=0; v_awarded numeric:=0;
  v_cw numeric:=100; v_aw numeric:=0; v_pass numeric:=70; v_outcome text; v_debrief jsonb; v_comp jsonb;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.user_id() then raise exception 'Attempt not found'; end if;
  if v_attempt.status='completed' then select final_score,clinical_score,assessment_score,patient_outcome,structured_debrief into v_final,v_clinical,v_assessment,v_outcome,v_debrief from public.attempt_results where attempt_id=p_attempt_id; return jsonb_build_object('finalScore',v_final,'clinicalScore',v_clinical,'assessmentScore',v_assessment,'patientOutcome',v_outcome,'debrief',v_debrief); end if;

  select s,sv.rubric into v_scenario,v_rubric from public.scenario_versions sv join public.scenarios s on s.id=sv.scenario_id where sv.id=v_attempt.scenario_version_id;
  v_state:=v_attempt.current_state; v_actions:=coalesce(v_state->'actions','[]'::jsonb); v_clinical:=least(100,greatest(0,coalesce((v_state->>'score')::numeric,v_attempt.score,0)));
  select count(*),coalesce(sum(points),0) into v_total_q,v_total_pts from public.scenario_questions where scenario_id=v_scenario.id;
  select count(*),coalesce(sum(awarded_points),0) into v_answered,v_awarded from public.attempt_answers aa join public.scenario_questions q on q.id=aa.question_id where aa.attempt_id=p_attempt_id and q.scenario_id=v_scenario.id;
  if v_total_q>0 and v_answered<v_total_q then raise exception 'Complete the knowledge assessment before finishing the case'; end if;
  v_assessment:=case when v_total_pts>0 then round((v_awarded/v_total_pts)*100,2) else 0 end;
  v_cw:=coalesce((v_rubric->>'clinical_weight')::numeric,case when v_total_q>0 then 70 else 100 end);
  v_aw:=coalesce((v_rubric->>'assessment_weight')::numeric,case when v_total_q>0 then 30 else 0 end);
  v_pass:=coalesce((v_rubric->>'passing_score')::numeric,70);
  if v_total_q=0 then v_cw:=100;v_aw:=0; end if;
  v_final:=round(((v_clinical*v_cw)+(v_assessment*v_aw))/greatest(v_cw+v_aw,1),2);
  v_outcome:=coalesce(v_state#>>'{patient,condition}',v_state#>>'{patient,status}','Recorded');
  v_comp:=jsonb_build_object('clinical_simulation',v_clinical,'knowledge_assessment',v_assessment);
  v_debrief:=jsonb_build_object('what_went_well',v_actions,'improve_next','Review the action timeline and instructor explanations for missed assessment questions.','passed',v_final>=v_pass);
  update public.attempts set status='completed',score=v_final,completed_at=now() where id=p_attempt_id;
  insert into public.attempt_results(attempt_id,final_score,clinical_score,assessment_score,competency_scores,patient_outcome,structured_debrief,passed)
  values(p_attempt_id,v_final,v_clinical,v_assessment,v_comp,v_outcome,v_debrief,v_final>=v_pass)
  on conflict(attempt_id) do update set final_score=excluded.final_score,clinical_score=excluded.clinical_score,assessment_score=excluded.assessment_score,competency_scores=excluded.competency_scores,patient_outcome=excluded.patient_outcome,structured_debrief=excluded.structured_debrief,passed=excluded.passed;
  insert into public.skill_mastery(student_id,skill_key,mastery,attempts_count,best_score,updated_at)
  values(auth.user_id(),v_scenario.slug,v_final,1,v_final,now())
  on conflict(student_id,skill_key) do update set mastery=round(((skill_mastery.mastery*skill_mastery.attempts_count)+excluded.mastery)/(skill_mastery.attempts_count+1),2),attempts_count=skill_mastery.attempts_count+1,best_score=greatest(skill_mastery.best_score,excluded.best_score),updated_at=now();
  return jsonb_build_object('finalScore',v_final,'clinicalScore',v_clinical,'assessmentScore',v_assessment,'competencyScores',v_comp,'patientOutcome',v_outcome,'debrief',v_debrief,'passed',v_final>=v_pass);
end;$$;
grant execute on function public.finish_simulation(uuid) to authenticated;

-- Keep scenario knowledge visibility aligned with publication.
create or replace function public.staff_update_scenario(p_scenario_id uuid,p_title text,p_description text,p_specialty text,p_published boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role;
begin
  select role into v_role from public.profiles where id=auth.user_id(); if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  if v_role='instructor' and not public.staff_can_manage_scenario(p_scenario_id) then raise exception 'You can only update scenarios you created'; end if;
  update public.scenarios set title=trim(p_title),description=nullif(trim(coalesce(p_description,'')),''),specialty=nullif(trim(coalesce(p_specialty,'')),''),is_published=p_published where id=p_scenario_id;
  if not found then raise exception 'Scenario not found'; end if;
  update public.knowledge_sources set visibility=case when p_published then 'public' else 'staff' end,updated_at=now() where scenario_id=p_scenario_id and source_type='scenario';
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'scenario_updated','scenario',p_scenario_id::text,jsonb_build_object('published',p_published));
end;$$;
grant execute on function public.staff_update_scenario(uuid,text,text,text,boolean) to authenticated;

-- Core CareSim knowledge for the general assistant.
insert into public.knowledge_sources(title,source_type,content,visibility)
select 'CareSim platform overview','platform','CareSim is a nursing education and clinical simulation platform. Learners practice Skills Lab procedures and evolving clinical cases. Clinical scoring is rule-based and server-authoritative. The AI Simulated Patient only handles scenario-bounded patient dialogue. Instructors create clinical content, questions, correct answers, scoring rules, courses and assignments. Administrators manage users, roles, courses, scenarios, reports and audit logs.','public'
where not exists(select 1 from public.knowledge_sources where title='CareSim platform overview');

insert into public.knowledge_sources(title,source_type,content,visibility)
select 'CareSim roles','platform','Learner means a nursing student or practicing nurse who performs assigned simulations and sees personal progress. Clinical Instructor means an educator who authors scenarios and Skills Lab modules, adds patient facts and assessment questions with correct answers, assigns content to courses, and reviews learner attempts. Administrator controls the whole platform, users, permissions, courses, content, reports and governance.','public'
where not exists(select 1 from public.knowledge_sources where title='CareSim roles');

-- Do not expose hidden scenario config/rules/answer-adjacent patient facts directly to learners.
drop policy if exists scenario_versions_read on public.scenario_versions;
create policy scenario_versions_staff_read on public.scenario_versions for select to authenticated
using(public.current_role() in ('admin','instructor'));

create or replace function public.get_simulation_brief(p_slug text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_s public.scenarios%rowtype; v_config jsonb; v_actions jsonb;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
  select s.*,sv.config into v_s,v_config from public.scenarios s join public.scenario_versions sv on sv.scenario_id=s.id and sv.version=s.current_version where s.slug=p_slug and s.is_published=true limit 1;
  if v_s.id is null then raise exception 'Published scenario not found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('key',x.value->>'action','label',x.value->>'label') order by x.ord),'[]'::jsonb) into v_actions
  from jsonb_array_elements(coalesce(v_config->'rules','[]'::jsonb)) with ordinality as x(value,ord);
  return jsonb_build_object('id',v_s.id,'slug',v_s.slug,'title',v_s.title,'description',v_s.description,'specialty',v_s.specialty,'type',v_s.type,'difficulty',coalesce(v_config->>'difficulty','Beginner'),'estimatedMinutes',coalesce((v_config->>'estimated_minutes')::int,15),'coverUrl',coalesce(v_config->>'cover_url',''),'patientImageUrl',coalesce(v_config->>'patient_image_url',''),'actions',v_actions);
end;$$;
grant execute on function public.get_simulation_brief(text) to authenticated;

create or replace function public.list_published_simulations()
returns table(id uuid,title text,slug text,type public.scenario_type,description text,specialty text,difficulty text,estimated_minutes int,cover_url text)
language sql stable security definer set search_path=public as $$
  select s.id,s.title,s.slug,s.type,s.description,s.specialty,coalesce(sv.config->>'difficulty','Beginner'),coalesce((sv.config->>'estimated_minutes')::int,15),nullif(sv.config->>'cover_url','')
  from public.scenarios s join public.scenario_versions sv on sv.scenario_id=s.id and sv.version=s.current_version
  where s.is_published=true and s.type='clinical_case'
  order by s.created_at desc;
$$;
grant execute on function public.list_published_simulations() to authenticated;

-- Index any scenarios that already existed before v9.
insert into public.knowledge_sources(organization_id,scenario_id,title,source_type,content,visibility,uploaded_by)
select s.organization_id,s.id,s.title,'scenario',concat_ws(E'\n','CareSim clinical scenario: '||s.title,'Specialty: '||coalesce(s.specialty,'General nursing'),'Description: '||coalesce(s.description,''),'Learning objectives: '||coalesce((select string_agg(value,'; ') from jsonb_array_elements_text(coalesce(sv.config->'objectives','[]'::jsonb))),'')),case when s.is_published then 'public' else 'staff' end,s.created_by
from public.scenarios s join public.scenario_versions sv on sv.scenario_id=s.id and sv.version=s.current_version
where not exists(select 1 from public.knowledge_sources k where k.scenario_id=s.id and k.source_type='scenario');


-- ===== SOURCE: RUN_THIS_IN_NEON_V10.sql (adapted for Neon) =====
-- CareSim V10 — learner courses, full activity trail and assignment safety.
-- Run AFTER V9.

create extension if not exists pgcrypto;

create table if not exists public.app_activity_logs (
  id bigint generated by default as identity primary key,
  actor_id text references public.profiles(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists app_activity_logs_actor_idx on public.app_activity_logs(actor_id,created_at desc);
create index if not exists app_activity_logs_created_idx on public.app_activity_logs(created_at desc);
alter table public.app_activity_logs enable row level security;
grant select on public.app_activity_logs to authenticated;
drop policy if exists app_activity_admin_read on public.app_activity_logs;
create policy app_activity_admin_read on public.app_activity_logs for select to authenticated using(public.current_role()='admin');

create or replace function public.record_app_activity(p_action text,p_metadata jsonb default '{}'::jsonb,p_entity_type text default null,p_entity_id text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
  insert into public.app_activity_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.user_id(),left(trim(p_action),120),p_entity_type,p_entity_id,coalesce(p_metadata,'{}'::jsonb));
end;$$;
grant execute on function public.record_app_activity(text,jsonb,text,text) to authenticated;

create or replace function public.log_attempt_activity()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.app_activity_logs(actor_id,action,entity_type,entity_id,metadata)
    values(new.student_id,'simulation_started','attempt',new.id::text,jsonb_build_object('scenario_version_id',new.scenario_version_id,'assignment_id',new.assignment_id));
  elsif tg_op='UPDATE' and old.status is distinct from new.status and new.status='completed' then
    insert into public.app_activity_logs(actor_id,action,entity_type,entity_id,metadata)
    values(new.student_id,'simulation_completed','attempt',new.id::text,jsonb_build_object('score',new.score,'scenario_version_id',new.scenario_version_id,'assignment_id',new.assignment_id));
  end if;
  return new;
end;$$;
drop trigger if exists caresim_attempt_activity on public.attempts;
create trigger caresim_attempt_activity after insert or update on public.attempts for each row execute function public.log_attempt_activity();

create or replace function public.log_attempt_action_activity()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_student text;
begin
  select student_id into v_student from public.attempts where id=new.attempt_id;
  insert into public.app_activity_logs(actor_id,action,entity_type,entity_id,metadata)
  values(v_student,'simulation_action','attempt',new.attempt_id::text,jsonb_build_object('action_key',new.action_key,'score_delta',new.score_delta,'sequence_no',new.sequence_no));
  return new;
end;$$;
drop trigger if exists caresim_attempt_action_activity on public.attempt_actions;
create trigger caresim_attempt_action_activity after insert on public.attempt_actions for each row execute function public.log_attempt_action_activity();

-- An instructor should never assign a hidden draft to learners.
create or replace function public.staff_create_assignment(p_course_id uuid,p_scenario_id uuid,p_due_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_owner text; v_id uuid; v_published boolean;
begin
  select role into v_role from public.profiles where id=auth.user_id();
  select instructor_id into v_owner from public.courses where id=p_course_id;
  if v_role='instructor' and v_owner<>auth.user_id() then raise exception 'You can only assign work to your courses'; end if;
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  select is_published into v_published from public.scenarios where id=p_scenario_id;
  if coalesce(v_published,false)=false then raise exception 'Publish the simulation before assigning it to learners'; end if;
  insert into public.assignments(course_id,scenario_id,assigned_by,due_at) values(p_course_id,p_scenario_id,auth.user_id(),p_due_at) returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.user_id(),'assignment_created','assignment',v_id::text,jsonb_build_object('course_id',p_course_id,'scenario_id',p_scenario_id));
  return v_id;
end;$$;
grant execute on function public.staff_create_assignment(uuid,uuid,timestamptz) to authenticated;

-- Useful learner notification when they are enrolled / assigned.
create or replace function public.notify_course_member()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_title text;
begin
  select title into v_title from public.courses where id=new.course_id;
  if to_regclass('public.notifications') is not null then
    insert into public.notifications(user_id,title,body,kind,href)
    values(new.student_id,'Added to a course',coalesce(v_title,'A CareSim course')||' is now available in My Courses.','info','/courses');
  end if;
  return new;
exception when others then return new;
end;$$;
drop trigger if exists caresim_notify_course_member on public.course_members;
create trigger caresim_notify_course_member after insert on public.course_members for each row execute function public.notify_course_member();

create or replace function public.notify_course_assignment()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_title text; r record;
begin
  select title into v_title from public.scenarios where id=new.scenario_id;
  if to_regclass('public.notifications') is not null then
    for r in select student_id from public.course_members where course_id=new.course_id loop
      insert into public.notifications(user_id,title,body,kind,href)
      values(r.student_id,'New training assigned',coalesce(v_title,'A CareSim simulation')||' was assigned to your course.','assignment','/courses');
    end loop;
  end if;
  return new;
exception when others then return new;
end;$$;
drop trigger if exists caresim_notify_assignment on public.assignments;
create trigger caresim_notify_assignment after insert on public.assignments for each row execute function public.notify_course_assignment();


-- ===== SOURCE: RUN_THIS_IN_NEON_V11.sql (adapted for Neon) =====
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
returns table(id text,full_name text,email text,role public.user_role,learner_type text,organization_id uuid)
language plpgsql stable security definer set search_path=public as $$
declare v_role public.user_role; v_org uuid;
begin
  select p.role,p.organization_id into v_role,v_org from public.profiles p where p.id=auth.user_id();
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
  id text,
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
  select role into v_role from public.profiles where id=auth.user_id();
  if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;

  return query
  with visible_members as (
    select distinct cm.student_id, cm.course_id
    from public.course_members cm
    join public.courses c on c.id=cm.course_id
    where v_role='admin' or c.instructor_id=auth.user_id()
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
declare
  v_s public.scenarios%rowtype;
  v_config jsonb;
  v_actions jsonb;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

  select s.* into v_s
  from public.scenarios s
  where s.slug=p_slug and s.is_published=true
  limit 1;

  if not found or v_s.id is null then raise exception 'Published scenario not found'; end if;

  select sv.config into v_config
  from public.scenario_versions sv
  where sv.scenario_id=v_s.id
  order by case when sv.version=v_s.current_version then 0 else 1 end, sv.version desc
  limit 1;

  if v_config is null then raise exception 'Published scenario has no saved builder version'; end if;
  v_config:=coalesce(v_config,'{}'::jsonb);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key',x.value->>'action',
        'label',coalesce(x.value->>'label',x.value->>'action')
      ) order by x.ord
    ),
    '[]'::jsonb
  ) into v_actions
  from jsonb_array_elements(coalesce(v_config->'rules','[]'::jsonb)) with ordinality as x(value,ord);

  return jsonb_build_object(
    'id',v_s.id,
    'slug',v_s.slug,
    'title',v_s.title,
    'description',v_s.description,
    'specialty',v_s.specialty,
    'type',v_s.type,
    'difficulty',coalesce(v_config->>'difficulty','Beginner'),
    'estimatedMinutes',coalesce(nullif(v_config->>'estimated_minutes','')::int,15),
    'coverUrl',coalesce(v_config->>'cover_url',''),
    'patientImageUrl',coalesce(v_config->>'patient_image_url',''),
    'actions',v_actions
  );
end;$$;
grant execute on function public.get_simulation_brief(text) to authenticated;

-- Start the exact current version when available, otherwise latest saved version.
create or replace function public.start_simulation(p_slug text)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_version_id uuid; v_config jsonb; v_state jsonb; v_attempt_id uuid;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;
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
  values(auth.user_id(),v_version_id,v_state,0) returning id into v_attempt_id;
  return jsonb_build_object('attemptId',v_attempt_id,'state',v_state);
end;$$;
grant execute on function public.start_simulation(text) to authenticated;


-- ===== SOURCE: RUN_THIS_IN_NEON_V12.sql (adapted for Neon) =====
-- CareSim V12 database hotfix.
-- Run after V9/V10 if you previously saw PostgreSQL 42601.
-- It does not delete application data.

-- Fix stale current_version pointers.
update public.scenarios s
set current_version=x.latest_version
from (
  select scenario_id,max(version) latest_version
  from public.scenario_versions
  group by scenario_id
) x
where x.scenario_id=s.id
  and not exists(
    select 1 from public.scenario_versions sv
    where sv.scenario_id=s.id and sv.version=s.current_version
  );

-- Safe learner-facing simulation brief.
create or replace function public.get_simulation_brief(p_slug text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_s public.scenarios%rowtype;
  v_config jsonb;
  v_actions jsonb;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

  select s.* into v_s
  from public.scenarios s
  where s.slug=p_slug and s.is_published=true
  limit 1;

  if not found or v_s.id is null then raise exception 'Published scenario not found'; end if;

  select sv.config into v_config
  from public.scenario_versions sv
  where sv.scenario_id=v_s.id
  order by case when sv.version=v_s.current_version then 0 else 1 end, sv.version desc
  limit 1;

  if v_config is null then raise exception 'Published scenario has no saved builder version'; end if;
  v_config:=coalesce(v_config,'{}'::jsonb);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key',x.value->>'action',
        'label',coalesce(x.value->>'label',x.value->>'action')
      ) order by x.ord
    ),
    '[]'::jsonb
  ) into v_actions
  from jsonb_array_elements(coalesce(v_config->'rules','[]'::jsonb)) with ordinality as x(value,ord);

  return jsonb_build_object(
    'id',v_s.id,
    'slug',v_s.slug,
    'title',v_s.title,
    'description',v_s.description,
    'specialty',v_s.specialty,
    'type',v_s.type,
    'difficulty',coalesce(v_config->>'difficulty','Beginner'),
    'estimatedMinutes',coalesce(nullif(v_config->>'estimated_minutes','')::int,15),
    'coverUrl',coalesce(v_config->>'cover_url',''),
    'patientImageUrl',coalesce(v_config->>'patient_image_url',''),
    'actions',v_actions
  );
end;$$;
grant execute on function public.get_simulation_brief(text) to authenticated;

-- Start current version or latest saved fallback.
create or replace function public.start_simulation(p_slug text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_version_id uuid;
  v_config jsonb;
  v_state jsonb;
  v_attempt_id uuid;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

  select v.id,v.config into v_version_id,v_config
  from public.scenarios s
  join lateral (
    select sv.id,sv.config,sv.version
    from public.scenario_versions sv
    where sv.scenario_id=s.id
    order by case when sv.version=s.current_version then 0 else 1 end, sv.version desc
    limit 1
  ) v on true
  where s.slug=p_slug and s.is_published=true
  limit 1;

  if v_version_id is null then raise exception 'Published scenario has no saved builder version'; end if;

  v_state:=coalesce(v_config->'runtime_initial_state',jsonb_build_object(
    'patient',jsonb_build_object(
      'spo2',coalesce((v_config#>>'{initial_state,spo2}')::int,96),
      'heartRate',coalesce((v_config#>>'{initial_state,heart_rate}')::int,80),
      'respiratoryRate',coalesce((v_config#>>'{initial_state,respiratory_rate}')::int,18),
      'condition','Awaiting assessment',
      'status','stable'
    ),
    'score',0,
    'actions','[]'::jsonb,
    'performedActionKeys','[]'::jsonb,
    'messages',jsonb_build_array(jsonb_build_object('type','patient','text',coalesce(v_config#>>'{patient,openingComplaint}','Hello, nurse.'))),
    'elapsed',0
  ));

  insert into public.attempts(student_id,scenario_version_id,current_state,score)
  values(auth.user_id(),v_version_id,v_state,0)
  returning id into v_attempt_id;

  return jsonb_build_object('attemptId',v_attempt_id,'state',v_state);
end;$$;
grant execute on function public.start_simulation(text) to authenticated;

-- Fix finish_simulation record/rubric loading.
create or replace function public.finish_simulation(p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_attempt public.attempts%rowtype;
  v_state jsonb;
  v_actions jsonb;
  v_scenario public.scenarios%rowtype;
  v_rubric jsonb;
  v_clinical numeric:=0;
  v_assessment numeric:=0;
  v_final numeric:=0;
  v_total_q int:=0;
  v_answered int:=0;
  v_total_pts numeric:=0;
  v_awarded numeric:=0;
  v_cw numeric:=100;
  v_aw numeric:=0;
  v_pass numeric:=70;
  v_outcome text;
  v_debrief jsonb;
  v_comp jsonb;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

  select a.* into v_attempt
  from public.attempts a
  where a.id=p_attempt_id
  for update;

  if not found or v_attempt.student_id<>auth.user_id() then raise exception 'Attempt not found'; end if;

  if v_attempt.status='completed' then
    select final_score,clinical_score,assessment_score,patient_outcome,structured_debrief
    into v_final,v_clinical,v_assessment,v_outcome,v_debrief
    from public.attempt_results
    where attempt_id=p_attempt_id;
    return jsonb_build_object('finalScore',v_final,'clinicalScore',v_clinical,'assessmentScore',v_assessment,'patientOutcome',v_outcome,'debrief',v_debrief);
  end if;

  select s.* into v_scenario
  from public.scenario_versions sv
  join public.scenarios s on s.id=sv.scenario_id
  where sv.id=v_attempt.scenario_version_id
  limit 1;

  if not found or v_scenario.id is null then raise exception 'Scenario for this attempt was not found'; end if;

  select sv.rubric into v_rubric
  from public.scenario_versions sv
  where sv.id=v_attempt.scenario_version_id
  limit 1;

  v_rubric:=coalesce(v_rubric,'{}'::jsonb);
  v_state:=coalesce(v_attempt.current_state,'{}'::jsonb);
  v_actions:=coalesce(v_state->'actions','[]'::jsonb);
  v_clinical:=least(100,greatest(0,coalesce(nullif(v_state->>'score','')::numeric,v_attempt.score,0)));

  select count(*),coalesce(sum(points),0)
  into v_total_q,v_total_pts
  from public.scenario_questions
  where scenario_id=v_scenario.id;

  select count(*),coalesce(sum(aa.awarded_points),0)
  into v_answered,v_awarded
  from public.attempt_answers aa
  join public.scenario_questions q on q.id=aa.question_id
  where aa.attempt_id=p_attempt_id and q.scenario_id=v_scenario.id;

  if v_total_q>0 and v_answered<v_total_q then raise exception 'Complete the knowledge assessment before finishing the case'; end if;

  v_assessment:=case when v_total_pts>0 then round((v_awarded/v_total_pts)*100,2) else 0 end;
  v_cw:=coalesce(nullif(v_rubric->>'clinical_weight','')::numeric,case when v_total_q>0 then 70 else 100 end);
  v_aw:=coalesce(nullif(v_rubric->>'assessment_weight','')::numeric,case when v_total_q>0 then 30 else 0 end);
  v_pass:=coalesce(nullif(v_rubric->>'passing_score','')::numeric,70);
  if v_total_q=0 then v_cw:=100;v_aw:=0; end if;

  v_final:=round(((v_clinical*v_cw)+(v_assessment*v_aw))/greatest(v_cw+v_aw,1),2);
  v_outcome:=coalesce(v_state#>>'{patient,condition}',v_state#>>'{patient,status}','Recorded');
  v_comp:=jsonb_build_object('clinical_simulation',v_clinical,'knowledge_assessment',v_assessment);
  v_debrief:=jsonb_build_object(
    'what_went_well',v_actions,
    'improve_next','Review the action timeline and instructor explanations for missed assessment questions.',
    'passed',v_final>=v_pass
  );

  update public.attempts
  set status='completed',score=v_final,completed_at=now()
  where id=p_attempt_id;

  insert into public.attempt_results(attempt_id,final_score,clinical_score,assessment_score,competency_scores,patient_outcome,structured_debrief,passed)
  values(p_attempt_id,v_final,v_clinical,v_assessment,v_comp,v_outcome,v_debrief,v_final>=v_pass)
  on conflict(attempt_id) do update set
    final_score=excluded.final_score,
    clinical_score=excluded.clinical_score,
    assessment_score=excluded.assessment_score,
    competency_scores=excluded.competency_scores,
    patient_outcome=excluded.patient_outcome,
    structured_debrief=excluded.structured_debrief,
    passed=excluded.passed;

  insert into public.skill_mastery as sm(student_id,skill_key,mastery,attempts_count,best_score,updated_at)
  values(auth.user_id(),v_scenario.slug,v_final,1,v_final,now())
  on conflict(student_id,skill_key) do update set
    mastery=round(((sm.mastery*sm.attempts_count)+excluded.mastery)/(sm.attempts_count+1),2),
    attempts_count=sm.attempts_count+1,
    best_score=greatest(sm.best_score,excluded.best_score),
    updated_at=now();

  return jsonb_build_object(
    'finalScore',v_final,
    'clinicalScore',v_clinical,
    'assessmentScore',v_assessment,
    'competencyScores',v_comp,
    'patientOutcome',v_outcome,
    'debrief',v_debrief,
    'passed',v_final>=v_pass
  );
end;$$;
grant execute on function public.finish_simulation(uuid) to authenticated;


-- ===== SOURCE: RUN_THIS_IN_NEON_V16.sql (adapted for Neon) =====
-- ============================================================
-- CareSim V16 — Assessment persistence + builder verification
-- Run ONCE after your existing CareSim schema.
-- Safe to re-run. Does NOT delete users, courses, scenarios or attempts.
-- ============================================================

create extension if not exists pgcrypto;

-- 1) Assessment tables -------------------------------------------------------
create table if not exists public.scenario_questions (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references public.scenarios(id) on delete cascade,
  question_text text not null,
  question_type text not null default 'single_choice'
    check (question_type in ('single_choice','true_false','short_text')),
  options jsonb not null default '[]'::jsonb,
  correct_answer jsonb not null default 'null'::jsonb,
  explanation text,
  points numeric(6,2) not null default 10 check(points > 0),
  order_no int not null default 1,
  created_at timestamptz not null default now()
);

create index if not exists scenario_questions_scenario_idx
  on public.scenario_questions(scenario_id,order_no);

create table if not exists public.attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  question_id uuid not null references public.scenario_questions(id) on delete cascade,
  answer jsonb not null default 'null'::jsonb,
  is_correct boolean not null default false,
  awarded_points numeric(6,2) not null default 0,
  created_at timestamptz not null default now(),
  unique(attempt_id,question_id)
);

create index if not exists attempt_answers_attempt_idx
  on public.attempt_answers(attempt_id);

alter table public.attempt_results add column if not exists clinical_score numeric(5,2);
alter table public.attempt_results add column if not exists assessment_score numeric(5,2);
alter table public.attempt_results add column if not exists passed boolean;

alter table public.scenario_questions enable row level security;
alter table public.attempt_answers enable row level security;

grant select on public.scenario_questions, public.attempt_answers to authenticated;

-- Staff can inspect authored questions. Learners receive safe questions through the server API only.
drop policy if exists scenario_questions_staff_read on public.scenario_questions;
create policy scenario_questions_staff_read
on public.scenario_questions
for select to authenticated
using (public.current_role() in ('admin','instructor'));

-- Learners can read their own graded answers after the attempt; staff can inspect their learners.
drop policy if exists attempt_answers_owner_staff_read on public.attempt_answers;
create policy attempt_answers_owner_staff_read
on public.attempt_answers
for select to authenticated
using (
  exists(
    select 1
    from public.attempts a
    where a.id=attempt_id
      and (
        a.student_id=auth.user_id()
        or public.current_role()='admin'
        or (
          public.current_role()='instructor'
          and exists(
            select 1
            from public.course_members cm
            join public.courses c on c.id=cm.course_id
            where cm.student_id=a.student_id
              and c.instructor_id=auth.user_id()
          )
        )
      )
  )
);

-- 2) Knowledge table, because builder save also updates CareSim RAG ----------
create table if not exists public.knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  scenario_id uuid references public.scenarios(id) on delete cascade,
  course_id uuid references public.courses(id) on delete cascade,
  title text not null,
  source_type text not null default 'reference'
    check(source_type in ('platform','specialty','scenario','course','reference')),
  content text not null,
  visibility text not null default 'authenticated'
    check(visibility in ('public','authenticated','staff')),
  uploaded_by text references public.profiles(id) on delete set null,
  storage_path text,
  is_active boolean not null default true,
  search_vector tsvector generated always as (
    to_tsvector('simple',coalesce(title,'')||' '||coalesce(content,''))
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists knowledge_sources_search_idx
  on public.knowledge_sources using gin(search_vector);
create index if not exists knowledge_sources_scenario_idx
  on public.knowledge_sources(scenario_id);

alter table public.knowledge_sources enable row level security;
grant select on public.knowledge_sources to authenticated;

drop policy if exists knowledge_sources_read on public.knowledge_sources;
create policy knowledge_sources_read
on public.knowledge_sources
for select to authenticated
using (
  is_active
  and (
    visibility in ('public','authenticated')
    or public.current_role() in ('admin','instructor')
  )
);

-- 3) Staff scenario ownership -----------------------------------------------
create or replace function public.staff_can_manage_scenario(p_scenario_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select case
    when public.current_role()='admin' then true
    when public.current_role()='instructor' then exists(
      select 1
      from public.scenarios s
      where s.id=p_scenario_id
        and s.created_by=auth.user_id()
    )
    else false
  end;
$$;

grant execute on function public.staff_can_manage_scenario(uuid) to authenticated;

-- 4) Full builder save -------------------------------------------------------
-- This function is the authoritative persistence layer for:
-- patient, vitals, actions, questions, correct answers, scoring and RAG notes.
create or replace function public.staff_save_scenario_builder(
  p_scenario_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_title text;
  v_description text;
  v_specialty text;
  v_difficulty text;
  v_estimated int;
  v_config jsonb;
  v_rubric jsonb;
  v_patient jsonb;
  v_vitals jsonb;
  v_rules jsonb;
  v_objectives jsonb;
  v_questions jsonb;
  v_q jsonb;
  v_notes text;
  v_content text;
  v_current_version int;
  v_clinical_weight numeric;
  v_assessment_weight numeric;
  v_passing numeric;
begin
  if auth.user_id() is null or not public.staff_can_manage_scenario(p_scenario_id) then
    raise exception 'You cannot manage this scenario';
  end if;

  v_title:=trim(coalesce(p_payload#>>'{basics,title}',''));
  if length(v_title)<3 then raise exception 'Scenario title is required'; end if;

  v_description:=nullif(trim(coalesce(p_payload#>>'{basics,description}','')),'');
  v_specialty:=nullif(trim(coalesce(p_payload#>>'{basics,specialty}','')),'');
  v_difficulty:=coalesce(nullif(trim(p_payload#>>'{basics,difficulty}'),''),'Beginner');
  v_estimated:=greatest(1,least(180,coalesce((p_payload#>>'{basics,estimatedMinutes}')::int,15)));
  v_patient:=coalesce(p_payload->'patient','{}'::jsonb);
  v_vitals:=coalesce(p_payload->'vitals','{}'::jsonb);
  v_rules:=coalesce(p_payload->'actions','[]'::jsonb);
  v_objectives:=coalesce(p_payload->'objectives','[]'::jsonb);
  v_questions:=coalesce(p_payload->'questions','[]'::jsonb);
  v_notes:=nullif(trim(coalesce(p_payload#>>'{rag,notes}','')),'');
  v_clinical_weight:=greatest(0,least(100,coalesce((p_payload#>>'{scoring,clinicalWeight}')::numeric,70)));
  v_assessment_weight:=greatest(0,least(100,coalesce((p_payload#>>'{scoring,assessmentWeight}')::numeric,30)));
  if v_clinical_weight+v_assessment_weight=0 then
    v_clinical_weight:=100;
    v_assessment_weight:=0;
  end if;
  v_passing:=greatest(0,least(100,coalesce((p_payload#>>'{scoring,passingScore}')::numeric,70)));

  select s.current_version
  into v_current_version
  from public.scenarios s
  where s.id=p_scenario_id
  for update;

  if v_current_version is null then raise exception 'Scenario not found'; end if;

  update public.scenarios
  set title=v_title,
      description=v_description,
      specialty=v_specialty
  where id=p_scenario_id;

  v_config:=jsonb_build_object(
    'difficulty',v_difficulty,
    'estimated_minutes',v_estimated,
    'objectives',v_objectives,
    'patient',v_patient,
    'cover_url',coalesce(p_payload#>>'{media,coverUrl}',''),
    'patient_image_url',coalesce(p_payload#>>'{media,patientImageUrl}',''),
    'rag_notes',coalesce(v_notes,''),
    'runtime_initial_state',jsonb_build_object(
      'patient',jsonb_build_object(
        'spo2',coalesce((v_vitals->>'spo2')::int,96),
        'heartRate',coalesce((v_vitals->>'heartRate')::int,80),
        'respiratoryRate',coalesce((v_vitals->>'respiratoryRate')::int,18),
        'bloodPressure',coalesce(v_vitals->>'bloodPressure','120/80'),
        'temperature',coalesce((v_vitals->>'temperature')::numeric,37),
        'condition',coalesce(v_vitals->>'condition','Awaiting assessment'),
        'status',coalesce(v_vitals->>'status','stable')
      ),
      'score',0,
      'actions','[]'::jsonb,
      'performedActionKeys','[]'::jsonb,
      'messages',jsonb_build_array(
        jsonb_build_object(
          'type','patient',
          'text',coalesce(v_patient->>'openingComplaint','Hello, nurse.')
        )
      ),
      'elapsed',0
    ),
    'rules',v_rules
  );

  v_rubric:=jsonb_build_object(
    'clinical_weight',v_clinical_weight,
    'assessment_weight',v_assessment_weight,
    'passing_score',v_passing
  );

  insert into public.scenario_versions(scenario_id,version,config,rubric)
  values(p_scenario_id,v_current_version,v_config,v_rubric)
  on conflict(scenario_id,version)
  do update set
    config=excluded.config,
    rubric=excluded.rubric;

  -- Atomic replacement: if any question insert fails, the whole RPC rolls back.
  delete from public.scenario_questions
  where scenario_id=p_scenario_id;

  for v_q in
    select value
    from jsonb_array_elements(v_questions)
  loop
    if length(trim(coalesce(v_q->>'questionText','')))>0 then
      if coalesce(v_q->'correctAnswer','null'::jsonb)='null'::jsonb then
        raise exception 'Every assessment question needs a correct answer';
      end if;

      insert into public.scenario_questions(
        scenario_id,
        question_text,
        question_type,
        options,
        correct_answer,
        explanation,
        points,
        order_no
      )
      values(
        p_scenario_id,
        trim(v_q->>'questionText'),
        coalesce(v_q->>'type','single_choice'),
        coalesce(v_q->'options','[]'::jsonb),
        v_q->'correctAnswer',
        nullif(trim(coalesce(v_q->>'explanation','')),''),
        greatest(1,coalesce((v_q->>'points')::numeric,10)),
        coalesce((v_q->>'orderNo')::int,1)
      );
    end if;
  end loop;

  v_content:=concat_ws(E'\n',
    'CareSim clinical scenario: '||v_title,
    'Specialty: '||coalesce(v_specialty,'General nursing'),
    'Description: '||coalesce(v_description,''),
    'Learning objectives: '||coalesce((
      select string_agg(value,'; ')
      from jsonb_array_elements_text(v_objectives)
    ),''),
    'Patient profile: '||coalesce(v_patient::text,''),
    'Instructor reference notes: '||coalesce(v_notes,'')
  );

  delete from public.knowledge_sources
  where scenario_id=p_scenario_id
    and source_type='scenario';

  insert into public.knowledge_sources(
    organization_id,
    scenario_id,
    title,
    source_type,
    content,
    visibility,
    uploaded_by
  )
  select
    organization_id,
    p_scenario_id,
    v_title,
    'scenario',
    v_content,
    case when is_published then 'public' else 'staff' end,
    auth.user_id()
  from public.scenarios
  where id=p_scenario_id;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(
    auth.user_id(),
    'scenario_builder_saved',
    'scenario',
    p_scenario_id::text,
    jsonb_build_object(
      'questions',jsonb_array_length(v_questions),
      'rules',jsonb_array_length(v_rules)
    )
  );
end;
$$;

grant execute on function public.staff_save_scenario_builder(uuid,jsonb) to authenticated;

-- 5) Submit learner answer server-side --------------------------------------
create or replace function public.submit_attempt_answer(
  p_attempt_id uuid,
  p_question_id uuid,
  p_answer jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_attempt public.attempts%rowtype;
  v_q public.scenario_questions%rowtype;
  v_correct boolean:=false;
  v_awarded numeric:=0;
  v_a text;
  v_c text;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

  select * into v_attempt
  from public.attempts
  where id=p_attempt_id;

  if not found
     or v_attempt.student_id<>auth.user_id()
     or v_attempt.status<>'in_progress' then
    raise exception 'Attempt not found';
  end if;

  select q.* into v_q
  from public.scenario_questions q
  join public.scenario_versions sv on sv.scenario_id=q.scenario_id
  where q.id=p_question_id
    and sv.id=v_attempt.scenario_version_id
  limit 1;

  if not found then raise exception 'Question not found'; end if;

  v_a:=lower(trim(both '"' from coalesce(p_answer::text,'')));
  v_c:=lower(trim(both '"' from coalesce(v_q.correct_answer::text,'')));

  if v_q.question_type='short_text'
     and jsonb_typeof(v_q.correct_answer)='array' then
    select exists(
      select 1
      from jsonb_array_elements_text(v_q.correct_answer) x
      where lower(trim(x))=lower(trim(both '"' from coalesce(p_answer::text,'')))
    ) into v_correct;
  else
    v_correct:=(v_a=v_c);
  end if;

  if v_correct then v_awarded:=v_q.points; end if;

  insert into public.attempt_answers(
    attempt_id,question_id,answer,is_correct,awarded_points
  )
  values(
    p_attempt_id,p_question_id,coalesce(p_answer,'null'::jsonb),v_correct,v_awarded
  )
  on conflict(attempt_id,question_id)
  do update set
    answer=excluded.answer,
    is_correct=excluded.is_correct,
    awarded_points=excluded.awarded_points,
    created_at=now();

  return jsonb_build_object('saved',true);
end;
$$;

grant execute on function public.submit_attempt_answer(uuid,uuid,jsonb) to authenticated;

-- 6) Publish/unpublish, keeping RAG visibility aligned -----------------------
create or replace function public.staff_update_scenario(
  p_scenario_id uuid,
  p_title text,
  p_description text,
  p_specialty text,
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
  select role into v_role
  from public.profiles
  where id=auth.user_id();

  if v_role not in ('admin','instructor') then
    raise exception 'Staff access required';
  end if;

  if v_role='instructor'
     and not public.staff_can_manage_scenario(p_scenario_id) then
    raise exception 'You can only update scenarios you created';
  end if;

  update public.scenarios
  set title=trim(p_title),
      description=nullif(trim(coalesce(p_description,'')),''),
      specialty=nullif(trim(coalesce(p_specialty,'')),''),
      is_published=p_published
  where id=p_scenario_id;

  if not found then raise exception 'Scenario not found'; end if;

  update public.knowledge_sources
  set visibility=case when p_published then 'public' else 'staff' end,
      updated_at=now()
  where scenario_id=p_scenario_id
    and source_type='scenario';

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(
    auth.user_id(),
    'scenario_updated',
    'scenario',
    p_scenario_id::text,
    jsonb_build_object('published',p_published)
  );
end;
$$;

grant execute on function public.staff_update_scenario(uuid,text,text,text,boolean) to authenticated;

-- 7) Correct final grading ---------------------------------------------------
create or replace function public.finish_simulation(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_attempt public.attempts%rowtype;
  v_state jsonb;
  v_actions jsonb;
  v_scenario public.scenarios%rowtype;
  v_rubric jsonb;
  v_clinical numeric:=0;
  v_assessment numeric:=0;
  v_final numeric:=0;
  v_total_q int:=0;
  v_answered int:=0;
  v_total_pts numeric:=0;
  v_awarded numeric:=0;
  v_cw numeric:=100;
  v_aw numeric:=0;
  v_pass numeric:=70;
  v_outcome text;
  v_debrief jsonb;
  v_comp jsonb;
begin
  if auth.user_id() is null then raise exception 'Authentication required'; end if;

  select a.* into v_attempt
  from public.attempts a
  where a.id=p_attempt_id
  for update;

  if not found or v_attempt.student_id<>auth.user_id() then
    raise exception 'Attempt not found';
  end if;

  if v_attempt.status='completed' then
    select final_score,clinical_score,assessment_score,patient_outcome,structured_debrief
    into v_final,v_clinical,v_assessment,v_outcome,v_debrief
    from public.attempt_results
    where attempt_id=p_attempt_id;

    return jsonb_build_object(
      'finalScore',v_final,
      'clinicalScore',v_clinical,
      'assessmentScore',v_assessment,
      'patientOutcome',v_outcome,
      'debrief',v_debrief
    );
  end if;

  select s.* into v_scenario
  from public.scenario_versions sv
  join public.scenarios s on s.id=sv.scenario_id
  where sv.id=v_attempt.scenario_version_id
  limit 1;

  if not found or v_scenario.id is null then
    raise exception 'Scenario for this attempt was not found';
  end if;

  select sv.rubric into v_rubric
  from public.scenario_versions sv
  where sv.id=v_attempt.scenario_version_id
  limit 1;

  v_rubric:=coalesce(v_rubric,'{}'::jsonb);
  v_state:=coalesce(v_attempt.current_state,'{}'::jsonb);
  v_actions:=coalesce(v_state->'actions','[]'::jsonb);
  v_clinical:=least(100,greatest(0,coalesce(nullif(v_state->>'score','')::numeric,v_attempt.score,0)));

  select count(*),coalesce(sum(points),0)
  into v_total_q,v_total_pts
  from public.scenario_questions
  where scenario_id=v_scenario.id;

  select count(*),coalesce(sum(aa.awarded_points),0)
  into v_answered,v_awarded
  from public.attempt_answers aa
  join public.scenario_questions q on q.id=aa.question_id
  where aa.attempt_id=p_attempt_id
    and q.scenario_id=v_scenario.id;

  if v_total_q>0 and v_answered<v_total_q then
    raise exception 'Complete the knowledge assessment before finishing the case';
  end if;

  v_assessment:=case when v_total_pts>0
    then round((v_awarded/v_total_pts)*100,2)
    else 0 end;

  v_cw:=coalesce(nullif(v_rubric->>'clinical_weight','')::numeric,case when v_total_q>0 then 70 else 100 end);
  v_aw:=coalesce(nullif(v_rubric->>'assessment_weight','')::numeric,case when v_total_q>0 then 30 else 0 end);
  v_pass:=coalesce(nullif(v_rubric->>'passing_score','')::numeric,70);

  if v_total_q=0 then
    v_cw:=100;
    v_aw:=0;
  end if;

  v_final:=round(((v_clinical*v_cw)+(v_assessment*v_aw))/greatest(v_cw+v_aw,1),2);
  v_outcome:=coalesce(v_state#>>'{patient,condition}',v_state#>>'{patient,status}','Recorded');
  v_comp:=jsonb_build_object('clinical_simulation',v_clinical,'knowledge_assessment',v_assessment);
  v_debrief:=jsonb_build_object(
    'what_went_well',v_actions,
    'improve_next','Review the action timeline and instructor explanations for missed assessment questions.',
    'passed',v_final>=v_pass
  );

  update public.attempts
  set status='completed',score=v_final,completed_at=now()
  where id=p_attempt_id;

  insert into public.attempt_results(
    attempt_id,final_score,clinical_score,assessment_score,
    competency_scores,patient_outcome,structured_debrief,passed
  )
  values(
    p_attempt_id,v_final,v_clinical,v_assessment,
    v_comp,v_outcome,v_debrief,v_final>=v_pass
  )
  on conflict(attempt_id) do update set
    final_score=excluded.final_score,
    clinical_score=excluded.clinical_score,
    assessment_score=excluded.assessment_score,
    competency_scores=excluded.competency_scores,
    patient_outcome=excluded.patient_outcome,
    structured_debrief=excluded.structured_debrief,
    passed=excluded.passed;

  insert into public.skill_mastery as sm(
    student_id,skill_key,mastery,attempts_count,best_score,updated_at
  )
  values(auth.user_id(),v_scenario.slug,v_final,1,v_final,now())
  on conflict(student_id,skill_key) do update set
    mastery=round(((sm.mastery*sm.attempts_count)+excluded.mastery)/(sm.attempts_count+1),2),
    attempts_count=sm.attempts_count+1,
    best_score=greatest(sm.best_score,excluded.best_score),
    updated_at=now();

  return jsonb_build_object(
    'finalScore',v_final,
    'clinicalScore',v_clinical,
    'assessmentScore',v_assessment,
    'competencyScores',v_comp,
    'patientOutcome',v_outcome,
    'debrief',v_debrief,
    'passed',v_final>=v_pass
  );
end;
$$;

grant execute on function public.finish_simulation(uuid) to authenticated;

-- 8) Verification -----------------------------------------------------------
select
  s.id,
  s.title,
  s.is_published,
  count(q.id) as saved_questions,
  coalesce(jsonb_array_length(sv.config->'rules'),0) as saved_actions
from public.scenarios s
left join public.scenario_versions sv
  on sv.scenario_id=s.id and sv.version=s.current_version
left join public.scenario_questions q
  on q.scenario_id=s.id
group by s.id,s.title,s.is_published,sv.config
order by s.created_at desc;


-- ===== Neon-specific finalization =====
-- Auth is Managed Better Auth in neon_auth.*. App roles remain in public.profiles.
-- Data API JWTs expose auth.user_id() as TEXT, matching all profile-linked IDs above.

grant insert on public.scenario_assets to authenticated;
drop policy if exists scenario_assets_staff_insert on public.scenario_assets;
create policy scenario_assets_staff_insert on public.scenario_assets
for insert to authenticated
with check (
  uploaded_by = auth.user_id()
  and public.staff_can_manage_scenario(scenario_id)
);

-- Keep the profile synchronized if the managed Auth user's email/name changes.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name,learner_type,role)
  values(new.id,new.email,coalesce(new.name,''),'student','student')
  on conflict(id) do update set
    email=excluded.email,
    full_name=case when coalesce(public.profiles.full_name,'')='' then excluded.full_name else public.profiles.full_name end,
    updated_at=now();
  insert into public.notifications(user_id,title,body,kind,href)
  select new.id,'Welcome to CareSim','Your learner profile is ready. Start with a clinical simulation or complete your profile.','success','/dashboard'
  where not exists(select 1 from public.notifications where user_id=new.id and title='Welcome to CareSim');
  return new;
end;$$;

drop trigger if exists on_neon_auth_user_created on neon_auth.user;
create trigger on_neon_auth_user_created
  after insert or update of email,name on neon_auth.user
  for each row execute function public.handle_new_user();

-- Backfill any Neon Auth users created before this SQL was run.
insert into public.profiles(id,email,full_name,learner_type,role)
select u.id,u.email,coalesce(u.name,''),'student','student'::public.user_role
from neon_auth.user u
left join public.profiles p on p.id=u.id
where p.id is null;

-- Harden RPC exposure: PostgreSQL grants EXECUTE to PUBLIC by default.
-- Existing explicit GRANT EXECUTE ... TO authenticated statements above remain in effect.
revoke execute on all functions in schema public from public;
grant execute on function public.current_role() to authenticated;

-- Helpful verification query (uncomment after setup):
-- select id,email,name,role from neon_auth.user order by "createdAt" desc;
-- select id,email,full_name,role,learner_type from public.profiles order by created_at desc;
