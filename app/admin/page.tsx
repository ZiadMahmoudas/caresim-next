import Link from 'next/link';
import { AppShell } from '@/components/AppShell';
import { StatCard } from '@/components/StatCard';
import { createClient } from '@/lib/supabase/server';

export default async function Admin(){
 const s=await createClient();
 const [{count:users},{count:courses},{count:scenarios},{count:attempts},{count:instructors},{count:learners}]=await Promise.all([
  s.from('profiles').select('*',{count:'exact',head:true}),s.from('courses').select('*',{count:'exact',head:true}),s.from('scenarios').select('*',{count:'exact',head:true}),s.from('attempts').select('*',{count:'exact',head:true}),s.from('profiles').select('*',{count:'exact',head:true}).eq('role','instructor'),s.from('profiles').select('*',{count:'exact',head:true}).eq('role','student')
 ]);
 const {data:recent}=await s.from('audit_logs').select('id,actor_id,action,entity_type,created_at').order('created_at',{ascending:false}).limit(6);
 const actorIds=[...new Set((recent||[]).map((x:any)=>x.actor_id).filter(Boolean))];
 const {data:actors}=actorIds.length?await s.from('profiles').select('id,full_name,email').in('id',actorIds):{data:[] as any[]};
 const actorMap=Object.fromEntries((actors||[]).map((x:any)=>[x.id,x]));
 return <AppShell role="admin"><div className="page page-airy"><div className="page-head compact-head"><div><span className="eyebrow simple">Admin workspace</span><h1>Run the CareSim platform.</h1><p>Manage people, courses, clinical content, assignments, results and governance from one workspace.</p></div></div>
 <div className="stats-grid admin-stats"><StatCard icon="fa-users" label="Accounts" value={String(users||0)} note={`${learners||0} learners · ${instructors||0} instructors`}/><StatCard icon="fa-graduation-cap" label="Courses" value={String(courses||0)} note="Active teaching spaces" tone="teal"/><StatCard icon="fa-book-medical" label="Scenarios" value={String(scenarios||0)} note="Skills + clinical cases" tone="rose"/><StatCard icon="fa-clipboard-check" label="Attempts" value={String(attempts||0)} note="Recorded learner attempts" tone="gold"/></div>
 <div className="admin-module-grid">
  <Link href="/admin/users" className="admin-module"><i className="fa-solid fa-users-gear"/><div><b>Users & roles</b><span>Promote instructors, manage learners and remove accounts.</span></div><i className="fa-solid fa-arrow-right"/></Link>
  <Link href="/admin/courses" className="admin-module"><i className="fa-solid fa-graduation-cap"/><div><b>Courses</b><span>Create courses, choose instructors, enrol learners and assign work.</span></div><i className="fa-solid fa-arrow-right"/></Link>
  <Link href="/admin/scenarios" className="admin-module"><i className="fa-solid fa-book-medical"/><div><b>Scenarios & tests</b><span>Create, edit, publish and retire clinical learning content.</span></div><i className="fa-solid fa-arrow-right"/></Link>
  <Link href="/admin/attempts" className="admin-module"><i className="fa-solid fa-clipboard-list"/><div><b>Attempts & logs</b><span>Review every learner attempt, score, outcome and action history.</span></div><i className="fa-solid fa-arrow-right"/></Link>
  <Link href="/admin/reports" className="admin-module"><i className="fa-solid fa-file-excel"/><div><b>Reports</b><span>Filter performance data and export an Excel workbook.</span></div><i className="fa-solid fa-arrow-right"/></Link>
  <Link href="/admin/audit" className="admin-module"><i className="fa-solid fa-shield-halved"/><div><b>Audit & governance</b><span>Trace role changes, content changes and administrative actions.</span></div><i className="fa-solid fa-arrow-right"/></Link>
 </div>
 <section className="panel admin-recent"><div className="panel-head"><div><span>Governance</span><h2>Recent administrative activity</h2></div><Link className="subtle-btn" href="/admin/audit">View audit log</Link></div>{recent?.length?<div className="activity-list">{recent.map((row:any)=><div key={row.id}><i className="fa-solid fa-clock-rotate-left"/><div><b>{String(row.action).replaceAll('_',' ')}</b><span>{row.entity_type} · {actorMap[row.actor_id]?.full_name||actorMap[row.actor_id]?.email||'System'}</span></div><time>{new Date(row.created_at).toLocaleString()}</time></div>)}</div>:<div className="mini-empty"><i className="fa-solid fa-shield"/><b>No audit activity yet</b><span>Administrative changes will appear here.</span></div>}</section>
 </div></AppShell>
}
