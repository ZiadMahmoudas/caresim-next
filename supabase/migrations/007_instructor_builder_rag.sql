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
  uploaded_by uuid references public.profiles(id) on delete set null,
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
  uploaded_by uuid references public.profiles(id) on delete set null,
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
using(exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.staff_can_view_student(a.student_id))));

drop policy if exists knowledge_sources_read on public.knowledge_sources;
create policy knowledge_sources_read on public.knowledge_sources for select to authenticated
using(is_active and (visibility in ('public','authenticated') or public.current_role() in ('admin','instructor')));

drop policy if exists scenario_assets_read on public.scenario_assets;
create policy scenario_assets_read on public.scenario_assets for select to authenticated
using(exists(select 1 from public.scenarios s where s.id=scenario_id and (s.is_published or public.current_role() in ('admin','instructor'))));

-- Public image bucket for scenario/patient artwork. Reference documents should be summarized into knowledge text.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('scenario-assets','scenario-assets',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists scenario_assets_public_read on storage.objects;
create policy scenario_assets_public_read on storage.objects for select using(bucket_id='scenario-assets');

-- Staff can manage only scenarios they authored; admins can manage all.
create or replace function public.staff_can_manage_scenario(p_scenario_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select case
    when public.current_role()='admin' then true
    when public.current_role()='instructor' then exists(select 1 from public.scenarios s where s.id=p_scenario_id and s.created_by=auth.uid())
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
  if auth.uid() is null or not public.staff_can_manage_scenario(p_scenario_id) then raise exception 'You cannot manage this scenario'; end if;

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
  select organization_id,p_scenario_id,v_title,'scenario',v_content,case when is_published then 'public' else 'staff' end,auth.uid()
  from public.scenarios where id=p_scenario_id;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'scenario_builder_saved','scenario',p_scenario_id::text,jsonb_build_object('questions',jsonb_array_length(v_questions),'rules',jsonb_array_length(v_rules)));
end;$$;
grant execute on function public.staff_save_scenario_builder(uuid,jsonb) to authenticated;

create or replace function public.search_knowledge(p_query text,p_limit int default 6)
returns table(id uuid,title text,source_type text,content text,scenario_id uuid,rank real)
language sql stable security definer set search_path=public as $$
  select k.id,k.title,k.source_type,k.content,k.scenario_id,
         ts_rank_cd(k.search_vector,websearch_to_tsquery('simple',coalesce(nullif(trim(p_query),''),'CareSim'))) as rank
  from public.knowledge_sources k
  where k.is_active
    and (k.visibility='public' or (auth.uid() is not null and k.visibility='authenticated') or (public.current_role() in ('admin','instructor') and k.visibility='staff'))
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id;
  if not found or v_attempt.student_id<>auth.uid() or v_attempt.status<>'in_progress' then raise exception 'Attempt not found'; end if;
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_attempt from public.attempts where id=p_attempt_id for update;
  if not found or v_attempt.student_id<>auth.uid() then raise exception 'Attempt not found'; end if;
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
  values(auth.uid(),v_scenario.slug,v_final,1,v_final,now())
  on conflict(student_id,skill_key) do update set mastery=round(((skill_mastery.mastery*skill_mastery.attempts_count)+excluded.mastery)/(skill_mastery.attempts_count+1),2),attempts_count=skill_mastery.attempts_count+1,best_score=greatest(skill_mastery.best_score,excluded.best_score),updated_at=now();
  return jsonb_build_object('finalScore',v_final,'clinicalScore',v_clinical,'assessmentScore',v_assessment,'competencyScores',v_comp,'patientOutcome',v_outcome,'debrief',v_debrief,'passed',v_final>=v_pass);
end;$$;
grant execute on function public.finish_simulation(uuid) to authenticated;

-- Keep scenario knowledge visibility aligned with publication.
create or replace function public.staff_update_scenario(p_scenario_id uuid,p_title text,p_description text,p_specialty text,p_published boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.user_role;
begin
  select role into v_role from public.profiles where id=auth.uid(); if v_role not in ('admin','instructor') then raise exception 'Staff access required'; end if;
  if v_role='instructor' and not public.staff_can_manage_scenario(p_scenario_id) then raise exception 'You can only update scenarios you created'; end if;
  update public.scenarios set title=trim(p_title),description=nullif(trim(coalesce(p_description,'')),''),specialty=nullif(trim(coalesce(p_specialty,'')),''),is_published=p_published where id=p_scenario_id;
  if not found then raise exception 'Scenario not found'; end if;
  update public.knowledge_sources set visibility=case when p_published then 'public' else 'staff' end,updated_at=now() where scenario_id=p_scenario_id and source_type='scenario';
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'scenario_updated','scenario',p_scenario_id::text,jsonb_build_object('published',p_published));
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
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
