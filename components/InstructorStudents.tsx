'use client';
import Link from 'next/link';
import { useEffect,useMemo,useState } from 'react';
import { createClient } from '@/lib/supabase/client';

type RosterRow={id:string;full_name:string;email:string|null;learner_type:string|null;course_titles:string[]|null;attempts_count:number;completed_attempts:number;average_score:number};
type DirectoryRow={id:string;full_name:string;email:string|null;role:string;learner_type:string|null};

export function InstructorStudents(){
 const [rows,setRows]=useState<RosterRow[]>([]),[directory,setDirectory]=useState<DirectoryRow[]>([]),[q,setQ]=useState(''),[loading,setLoading]=useState(true),[message,setMessage]=useState('');
 useEffect(()=>{(async()=>{const s=createClient();const [r,d]=await Promise.all([s.rpc('staff_instructor_roster'),s.rpc('staff_people_directory')]);if(r.error||d.error)setMessage(r.error?.message||d.error?.message||'Unable to load learner directory.');else{setRows((r.data||[]) as RosterRow[]);setDirectory(((d.data||[]) as DirectoryRow[]).filter(x=>x.role==='student'))}setLoading(false)})()},[]);
 const enrolledIds=useMemo(()=>new Set(rows.map(x=>x.id)),[rows]);
 const visible=useMemo(()=>rows.filter(x=>`${x.full_name||''} ${x.email||''} ${(x.course_titles||[]).join(' ')}`.toLowerCase().includes(q.toLowerCase())),[rows,q]);
 const available=useMemo(()=>directory.filter(x=>`${x.full_name||''} ${x.email||''} ${x.learner_type||''}`.toLowerCase().includes(q.toLowerCase())),[directory,q]);
 return <div className="instructor-roster-stack">
  <section className="panel">
   <div className="panel-head"><div><span>My roster</span><h2>Enrolled learners</h2></div><div className="roster-counts"><span className="admin-note">{rows.filter(x=>x.learner_type!=='nurse').length} students</span><span className="admin-note">{rows.filter(x=>x.learner_type==='nurse').length} practicing nurses</span></div></div>
   <div className="table-search wide"><i className="fa-solid fa-magnifying-glass"/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search learners or courses…"/></div>
   {message&&<div className="profile-message">{message}</div>}
   {loading?<p>Loading learners…</p>:visible.length?<div className="learner-review-grid">{visible.map(x=><article key={x.id}><div className="avatar">{(x.full_name||x.email||'L').slice(0,2).toUpperCase()}</div><div className="learner-review-main"><b>{x.full_name||x.email}</b><span className={`learner-kind ${x.learner_type==='nurse'?'nurse':'student'}`}>{x.learner_type==='nurse'?'Practicing nurse / continuing education':'Nursing student'}</span><small>{(x.course_titles||[]).join(' · ')}</small></div><div className="learner-metric"><strong>{Number(x.average_score||0)}%</strong><span>avg score</span></div><div className="learner-metric"><strong>{Number(x.attempts_count||0)}</strong><span>attempts</span></div></article>)}</div>:<div className="mini-empty"><i className="fa-solid fa-user-plus"/><b>No learners enrolled in your courses yet</b><span>The accounts below exist in CareSim, but they become “My Learners” only after you enrol them into one of your courses.</span><Link href="/instructor/courses" className="btn primary">Open My Courses</Link></div>}
  </section>

  <section className="panel learner-directory-panel">
   <div className="panel-head"><div><span>CareSim learner directory</span><h2>Available learner accounts</h2></div><span className="admin-note">{directory.length} total</span></div>
   <p className="muted-copy">Both account types below are Learners. “Nursing Student” and “Practicing Nurse” only describe the learner type; enrolment into your course is what makes them part of your teaching roster.</p>
   {loading?<p>Loading directory…</p>:available.length?<div className="learner-directory-list">{available.map(x=><div key={x.id} className="learner-directory-row"><div className="avatar small">{(x.full_name||x.email||'L').slice(0,2).toUpperCase()}</div><div><b>{x.full_name||x.email}</b><span>{x.email}</span></div><span className={`learner-kind ${x.learner_type==='nurse'?'nurse':'student'}`}>{x.learner_type==='nurse'?'Practicing Nurse':'Nursing Student'}</span><span className={`directory-status ${enrolledIds.has(x.id)?'enrolled':''}`}>{enrolledIds.has(x.id)?'Enrolled':'Available'}</span></div>)}</div>:<div className="mini-empty"><b>No learner accounts found</b><span>Create a Nursing Student or Practicing Nurse account first.</span></div>}
   <div className="directory-cta"><Link href="/instructor/courses" className="btn white"><i className="fa-solid fa-graduation-cap"/> Enrol learners from My Courses</Link></div>
  </section>
 </div>
}
