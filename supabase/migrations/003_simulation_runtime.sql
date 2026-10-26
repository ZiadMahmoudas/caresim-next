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
