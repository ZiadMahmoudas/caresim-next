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
  if auth.uid() is null then raise exception 'Authentication required'; end if;

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
  if auth.uid() is null then raise exception 'Authentication required'; end if;

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
  values(auth.uid(),v_version_id,v_state,0)
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select a.* into v_attempt
  from public.attempts a
  where a.id=p_attempt_id
  for update;

  if not found or v_attempt.student_id<>auth.uid() then raise exception 'Attempt not found'; end if;

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
  values(auth.uid(),v_scenario.slug,v_final,1,v_final,now())
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
