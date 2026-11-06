export const dynamic = 'force-dynamic';
import Link from 'next/link';
import { AppShell } from '@/components/AppShell';
import { StatCard } from '@/components/StatCard';
import { ProgressRing } from '@/components/ProgressRing';
import { createClient } from '@/lib/neon/server';

type Attempt = { id:string; score:number; completed_at:string|null };
type Mastery = { skill_key:string; mastery:number; attempts_count:number };
type Scenario = { title:string; slug:string; description:string|null; specialty:string|null; type:'clinical_case'|'skill' };

function humanize(v:string){return v.replace(/[-_]/g,' ').replace(/\b\w/g,c=>c.toUpperCase())}

export default async function Dashboard() {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();

  const [{ data: profile }, { data: attemptsData }, { data: masteryData }, { data: scenariosData }, { data: memberships }] = await Promise.all([
    user ? db.from('profiles').select('full_name,learner_type').eq('id',user.id).maybeSingle() : Promise.resolve({data:null}),
    user ? db.from('attempts').select('id,score,completed_at').eq('student_id',user.id).eq('status','completed').order('completed_at',{ascending:false}).limit(8) : Promise.resolve({data:[] as Attempt[]}),
    user ? db.from('skill_mastery').select('skill_key,mastery,attempts_count').eq('student_id',user.id).order('updated_at',{ascending:false}).limit(5) : Promise.resolve({data:[] as Mastery[]}),
    db.from('scenarios').select('title,slug,description,specialty,type').eq('is_published',true).order('created_at',{ascending:false}).limit(6),
    user ? db.from('course_members').select('course_id').eq('student_id',user.id) : Promise.resolve({data:[] as {course_id:string}[]}),
  ]);

  const attempts=(attemptsData||[]) as Attempt[];
  const masteryRows=(masteryData||[]) as Mastery[];
  const scenarios=(scenariosData||[]) as Scenario[];
  const firstName=(profile?.full_name||user?.user_metadata?.full_name||'there').split(' ')[0];
  const completed=attempts.length;
  const average=completed?Math.round(attempts.reduce((sum,row)=>sum+Number(row.score||0),0)/completed):0;
  const mastery=masteryRows.length?Math.round(masteryRows.reduce((sum,row)=>sum+Number(row.mastery||0),0)/masteryRows.length):average;
  const best=completed?Math.round(Math.max(...attempts.map(x=>Number(x.score||0)))):0;
  const nextScenario=scenarios.find(x=>x.type==='clinical_case')||scenarios[0];
  const courseCount=(memberships||[]).length;

  return <AppShell><div className="page page-airy">
    <div className="page-head compact-head"><div><span className="eyebrow simple">Your clinical learning space</span><h1>Good to see you, {firstName} 👋</h1><p>Your dashboard now shows verified CareSim data only.</p></div><Link href="/simulations" className="btn primary"><i className="fa-solid fa-plus"/> Start simulation</Link></div>

    <div className="stats-grid clean-stats"><StatCard icon="fa-graduation-cap" label="My courses" value={String(courseCount)} note="Instructor-enrolled courses"/><StatCard icon="fa-circle-check" label="Completed" value={String(completed)} note="Verified attempts"/><StatCard icon="fa-chart-line" label="Average score" value={`${average}%`} note="Completed simulations" tone="teal"/><StatCard icon="fa-bullseye" label="Overall mastery" value={`${mastery}%`} note="From mastery records" tone="rose"/></div>

    <div className="dashboard-clean-grid">
      <section className="panel next-case-panel">
        <div className="panel-head"><div><span>Available training</span><h2>{nextScenario?'Continue learning':'No published cases yet'}</h2></div><div className="panel-head-links"><Link href="/courses">My courses</Link><Link href="/simulations">Browse all</Link></div></div>
        {nextScenario?<div className="next-case-clean"><span className="case-type-pill">{nextScenario.type==='skill'?'Skills Lab':'Clinical case'}</span><h3>{nextScenario.title}</h3><p>{nextScenario.description||'Open the module to review the case and begin a verified attempt.'}</p><div className="next-case-meta"><span><i className="fa-solid fa-building"/> {nextScenario.specialty||'Nursing'}</span><Link href={`/simulations/${nextScenario.slug}`} className="btn primary">Open training <i className="fa-solid fa-arrow-right"/></Link></div></div>:<div className="mini-empty"><i className="fa-solid fa-book-medical"/><b>No training published</b><span>An administrator or instructor can publish the first module.</span></div>}
      </section>

      <section className="panel mastery-card-clean">
        <div className="panel-head"><div><span>Verified mastery</span><h2>Current snapshot</h2></div></div>
        <ProgressRing value={mastery}/>
        <p className="muted-copy">Calculated only from saved CareSim mastery records.</p>
        <Link href="/progress" className="text-link">View progress <i className="fa-solid fa-arrow-right"/></Link>
      </section>
    </div>

    <div className="dashboard-clean-grid lower">
      <section className="panel recent-attempts-panel">
        <div className="panel-head"><div><span>History</span><h2>Recent attempts</h2></div></div>
        {attempts.length?<div className="recent-attempt-list">{attempts.slice(0,5).map((row,index)=><div key={row.id}><span className="attempt-index">#{completed-index}</span><div><b>Completed simulation</b><small>{row.completed_at?new Date(row.completed_at).toLocaleDateString():'Saved attempt'}</small></div><strong>{Math.round(Number(row.score||0))}%</strong></div>)}</div>:<div className="mini-empty"><i className="fa-solid fa-clock-rotate-left"/><b>No completed attempts yet</b><span>Your history will appear after your first simulation.</span></div>}
      </section>

      <section className="panel recent-attempts-panel">
        <div className="panel-head"><div><span>Competencies</span><h2>Latest mastery records</h2></div><Link href="/profile">Profile</Link></div>
        {masteryRows.length?<div className="recent-mastery-list">{masteryRows.map(row=><div key={row.skill_key}><div><b>{humanize(row.skill_key)}</b><small>{row.attempts_count} verified attempt{row.attempts_count===1?'':'s'}</small></div><strong>{Math.round(Number(row.mastery||0))}%</strong></div>)}</div>:<div className="mini-empty"><i className="fa-solid fa-shield-heart"/><b>No verified mastery yet</b><span>Complete training to generate competency records.</span></div>}
      </section>
    </div>
  </div></AppShell>
}
