export const dynamic = 'force-dynamic';
import Link from 'next/link';
import { AppShell } from '@/components/AppShell';
import { createClient } from '@/lib/neon/server';

type Member={course_id:string;student_id:string};
type Course={id:string;title:string;code:string|null;instructor_id:string|null;is_active:boolean};
type Assignment={id:string;course_id:string;scenario_id:string;due_at:string|null;created_at:string};
type Scenario={id:string;title:string;slug:string;type:'clinical_case'|'skill';description:string|null;specialty:string|null;is_published:boolean};
type Profile={id:string;full_name:string;email:string|null};

export default async function LearnerCourses(){
  const db=await createClient();
  const {data:{user}}=await db.auth.getUser();
  if(!user) return null;

  const {data:memberRows}=await db.from('course_members').select('course_id,student_id').eq('student_id',user.id);
  const courseIds=((memberRows||[]) as Member[]).map(x=>x.course_id);
  const {data:coursesData}=courseIds.length?await db.from('courses').select('id,title,code,instructor_id,is_active').in('id',courseIds).order('created_at',{ascending:false}):{data:[] as Course[]};
  const courses=(coursesData||[]) as Course[];
  const instructorIds=[...new Set(courses.map(c=>c.instructor_id).filter(Boolean))] as string[];
  const [{data:assignmentData},{data:instructorData}]=await Promise.all([
    courseIds.length?db.from('assignments').select('id,course_id,scenario_id,due_at,created_at').in('course_id',courseIds).order('created_at',{ascending:false}):Promise.resolve({data:[] as Assignment[]}),
    instructorIds.length?db.from('profiles').select('id,full_name,email').in('id',instructorIds):Promise.resolve({data:[] as Profile[]}),
  ]);
  const assignments=(assignmentData||[]) as Assignment[];
  const scenarioIds=[...new Set(assignments.map(a=>a.scenario_id))];
  const {data:scenarioData}=scenarioIds.length?await db.from('scenarios').select('id,title,slug,type,description,specialty,is_published').in('id',scenarioIds):{data:[] as Scenario[]};
  const scenarios=(scenarioData||[]) as Scenario[];
  const iMap=Object.fromEntries(((instructorData||[]) as Profile[]).map(x=>[x.id,x]));
  const sMap=Object.fromEntries(scenarios.map(x=>[x.id,x]));

  return <AppShell><div className="page page-airy">
    <div className="page-head compact-head"><div><span className="eyebrow simple">My Courses</span><h1>Your assigned learning.</h1><p>Courses appear here after an instructor enrols you. Each assignment links directly to the published simulation or Skills Lab module.</p></div><Link href="/simulations" className="btn white"><i className="fa-solid fa-heart-pulse"/> Practice library</Link></div>

    {courses.length?<div className="learner-course-grid">{courses.map(course=>{const rows=assignments.filter(a=>a.course_id===course.id);const inst=course.instructor_id?iMap[course.instructor_id]:null;return <article className="panel learner-course-card" key={course.id}>
      <div className="learner-course-head"><div><span className="course-code">{course.code||'CARESIM COURSE'}</span><h2>{course.title}</h2><p><i className="fa-solid fa-chalkboard-user"/> {inst?.full_name||inst?.email||'Clinical instructor'} · {rows.length} assignment{rows.length===1?'':'s'}</p></div><span className={`publish-pill ${course.is_active?'live':''}`}>{course.is_active?'Active':'Paused'}</span></div>
      <div className="learner-assignment-list">{rows.length?rows.map(a=>{const sc=sMap[a.scenario_id];return <div className="learner-assignment" key={a.id}><div className={`assignment-icon ${sc?.type==='skill'?'teal':'rose'}`}><i className={`fa-solid ${sc?.type==='skill'?'fa-syringe':'fa-heart-pulse'}`}/></div><div><b>{sc?.title||'Assigned training'}</b><span>{sc?.specialty||'Nursing'}{a.due_at?` · Due ${new Date(a.due_at).toLocaleDateString()}`:' · No due date'}</span></div>{sc?.is_published?<Link href={`/simulations/${sc.slug}`} className="btn primary">{sc.type==='skill'?'Practice':'Start'} <i className="fa-solid fa-arrow-right"/></Link>:<span className="assignment-unavailable"><i className="fa-solid fa-lock"/> Awaiting publication</span>}</div>}):<div className="mini-empty"><i className="fa-solid fa-clipboard"/><b>No assignments yet</b><span>Your instructor has enrolled you, but has not assigned training yet.</span></div>}</div>
    </article>})}</div>:<section className="panel empty-state-panel"><span className="empty-state-icon"><i className="fa-solid fa-graduation-cap"/></span><h2>You are not enrolled in a course yet</h2><p>Once an instructor adds you to a course, it will appear here automatically with its simulations, skills and due dates.</p><Link href="/simulations" className="btn primary">Browse available practice</Link></section>}
  </div></AppShell>
}
