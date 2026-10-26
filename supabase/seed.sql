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
