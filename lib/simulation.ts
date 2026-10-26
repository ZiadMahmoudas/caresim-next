export type PatientState = { spo2:number; heartRate:number; respiratoryRate:number; condition:string; status:string };
export type SimState = { patient:PatientState; score:number; actions:string[]; messages:{type:'patient'|'system'|'student';text:string}[]; elapsed:number };
export const initialState:SimState={patient:{spo2:86,heartRate:112,respiratoryRate:30,condition:'Moderate respiratory distress',status:'unstable'},score:0,actions:[],messages:[{type:'patient',text:"Nurse… I’m having difficulty breathing."}],elapsed:0};

const rules:Record<string,(s:SimState)=>SimState>={
  check_vitals:(s)=>({...s,score:s.score+10,actions:[...s.actions,'Checked vital signs'],messages:[...s.messages,{type:'system',text:'Vitals assessed: SpO₂ 86%, HR 112, RR 30.'}]}),
  assess_breathing:(s)=>({...s,score:s.score+10,actions:[...s.actions,'Assessed breathing'],messages:[...s.messages,{type:'patient',text:'It feels tight. I cannot catch my breath.'}]}),
  position_upright:(s)=>({...s,score:s.score+15,actions:[...s.actions,'Positioned patient upright'],patient:{...s.patient,spo2:88,respiratoryRate:27,condition:'Slight improvement'},messages:[...s.messages,{type:'patient',text:'Sitting up helps a little.'}]}),
  oxygen:(s)=>{const assessed=s.actions.includes('Checked vital signs'); const gain=assessed?25:12; return {...s,score:s.score+gain,actions:[...s.actions,'Administered oxygen'],patient:{...s.patient,spo2:assessed?94:91,respiratoryRate:23,condition:'Improving',status:'improving'},messages:[...s.messages,{type:'patient',text:'I can breathe more easily now.'}]};},
  history:(s)=>({...s,score:s.score+10,actions:[...s.actions,'Reviewed patient history'],messages:[...s.messages,{type:'patient',text:'I have COPD and high blood pressure. This started about two hours ago.'}]}),
  reassess:(s)=>({...s,score:s.score+15,actions:[...s.actions,'Reassessed patient'],messages:[...s.messages,{type:'system',text:`Reassessment documented. Current SpO₂ ${s.patient.spo2}%.`}]}),
  escalate:(s)=>({...s,score:s.score+15,actions:[...s.actions,'Escalated care'],messages:[...s.messages,{type:'system',text:'Escalation initiated and clinical team notified.'}]})
};
export function applyAction(state:SimState, action:string){return rules[action]?rules[action](state):state}
