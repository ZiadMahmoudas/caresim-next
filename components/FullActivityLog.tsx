'use client';
import { useEffect,useMemo,useState } from 'react';
import { createClient } from '@/lib/supabase/client';

type Profile={id:string;full_name:string;email:string|null;role:string};
type AppLog={id:number;actor_id:string|null;action:string;entity_type:string|null;entity_id:string|null;metadata:Record<string,unknown>;created_at:string};
type Audit={id:number;actor_id:string|null;action:string;entity_type:string;entity_id:string|null;metadata:Record<string,unknown>;created_at:string};

type Row={key:string;actor_id:string|null;action:string;kind:'activity'|'audit';entity:string;metadata:Record<string,unknown>;created_at:string};

function label(action:string){return action.replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase())}
function icon(action:string){if(action.includes('login'))return 'fa-right-to-bracket';if(action.includes('logout'))return 'fa-arrow-right-from-bracket';if(action.includes('simulation'))return 'fa-heart-pulse';if(action.includes('course'))return 'fa-graduation-cap';if(action.includes('scenario'))return 'fa-book-medical';if(action.includes('role')||action.includes('user'))return 'fa-user-shield';return 'fa-shield-halved'}

export function FullActivityLog(){
 const [activity,setActivity]=useState<AppLog[]>([]),[audit,setAudit]=useState<Audit[]>([]),[profiles,setProfiles]=useState<Profile[]>([]),[q,setQ]=useState(''),[type,setType]=useState('all'),[loading,setLoading]=useState(true),[message,setMessage]=useState('');
 useEffect(()=>{(async()=>{const s=createClient();const [a,b,p]=await Promise.all([s.from('app_activity_logs').select('id,actor_id,action,entity_type,entity_id,metadata,created_at').order('created_at',{ascending:false}).limit(2500),s.from('audit_logs').select('id,actor_id,action,entity_type,entity_id,metadata,created_at').order('created_at',{ascending:false}).limit(2500),s.from('profiles').select('id,full_name,email,role')]);setActivity((a.data||[]) as AppLog[]);setAudit((b.data||[]) as Audit[]);setProfiles((p.data||[]) as Profile[]);setMessage(a.error?.message||b.error?.message||'');setLoading(false)})()},[]);
 const pMap=useMemo(()=>Object.fromEntries(profiles.map(p=>[p.id,p])),[profiles]);
 const rows=useMemo<Row[]>(()=>[
  ...activity.map(x=>({key:`a-${x.id}`,actor_id:x.actor_id,action:x.action,kind:'activity' as const,entity:[x.entity_type,x.entity_id].filter(Boolean).join(' · '),metadata:x.metadata||{},created_at:x.created_at})),
  ...audit.map(x=>({key:`u-${x.id}`,actor_id:x.actor_id,action:x.action,kind:'audit' as const,entity:[x.entity_type,x.entity_id].filter(Boolean).join(' · '),metadata:x.metadata||{},created_at:x.created_at})),
 ].sort((a,b)=>+new Date(b.created_at)-+new Date(a.created_at)),[activity,audit]);
 const filtered=rows.filter(r=>{const p=pMap[r.actor_id||''];const text=`${r.action} ${r.entity} ${p?.full_name||''} ${p?.email||''} ${JSON.stringify(r.metadata)}`.toLowerCase();return(type==='all'||r.kind===type)&&text.includes(q.toLowerCase())});
 return <section className="panel full-activity-panel"><div className="panel-head"><div><span>Platform-wide trace</span><h2>All user & system activity</h2></div><span className="admin-note">{filtered.length} events</span></div><div className="activity-toolbar"><div className="table-search wide"><i className="fa-solid fa-magnifying-glass"/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search user, email, action, course or attempt…"/></div><select value={type} onChange={e=>setType(e.target.value)}><option value="all">All activity</option><option value="activity">Learner & session activity</option><option value="audit">Administrative audit</option></select></div>{message&&<div className="profile-message">{message}</div>}{loading?<p>Loading platform activity…</p>:filtered.length?<div className="full-activity-list">{filtered.map(r=>{const p=pMap[r.actor_id||''];return <article key={r.key}><span className={`activity-icon ${r.kind}`}><i className={`fa-solid ${icon(r.action)}`}/></span><div className="activity-main"><b>{label(r.action)}</b><span>{r.entity||'CareSim platform'}</span>{Object.keys(r.metadata||{}).length>0&&<small>{Object.entries(r.metadata).slice(0,4).map(([k,v])=>`${k.replaceAll('_',' ')}: ${String(v??'—')}`).join(' · ')}</small>}</div><div className="activity-person"><b>{p?.full_name||p?.email||'System'}</b><span>{p?.email||p?.role||'Automated event'}</span></div><time>{new Date(r.created_at).toLocaleString()}</time></article>})}</div>:<div className="mini-empty"><i className="fa-solid fa-clock-rotate-left"/><b>No activity found</b><span>Try another filter. New logins and simulation actions will appear after V10 SQL is installed.</span></div>}</section>
}
