export const dynamic = 'force-dynamic';
import Link from 'next/link';
import { AppShell } from '@/components/AppShell';
import { createClient } from '@/lib/neon/server';

type SkillScenario = {
  id: string;
  title: string;
  slug: string;
  description: string | null;
  specialty: string | null;
  current_version: number;
};

type MasteryRow = {
  skill_key: string;
  mastery: number;
  attempts_count: number;
  best_score: number;
};

function humanize(value: string) {
  return value.replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

export default async function Skills() {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();

  const [{ data: skills }, { data: masteryRows }, { data: profile }] = await Promise.all([
    db
      .from('scenarios')
      .select('id,title,slug,description,specialty,current_version')
      .eq('type', 'skill')
      .eq('is_published', true)
      .order('created_at', { ascending: false }),
    user
      ? db
          .from('skill_mastery')
          .select('skill_key,mastery,attempts_count,best_score')
          .eq('student_id', user.id)
      : Promise.resolve({ data: [] as MasteryRow[] }),
    user
      ? db.from('profiles').select('personal_skills').eq('id', user.id).maybeSingle()
      : Promise.resolve({ data: null as { personal_skills?: string[] } | null }),
  ]);

  const personalSkills = Array.isArray((profile as any)?.personal_skills) ? (profile as any).personal_skills as string[] : [];

  const mastery = new Map(
    ((masteryRows || []) as MasteryRow[]).map((row) => [row.skill_key, row]),
  );

  return (
    <AppShell>
      <div className="page page-airy">
        <div className="page-head compact-head">
          <div>
            <span className="eyebrow simple">Skills Lab</span>
            <h1>Practice verified nursing procedures.</h1>
            <p>
              These are CareSim training modules published by your instructors or administrators.
              Your own personal skills are managed separately in your profile.
            </p>
          </div>
          <Link href="/profile" className="btn white">
            <i className="fa-solid fa-user-pen" /> Manage personal skills
          </Link>
        </div>


        <section className="panel personal-skills-showcase">
          <div className="personal-skills-copy">
            <span className="eyebrow simple">Your profile</span>
            <h2>Personal skills you chose.</h2>
            <p>These are self-described strengths such as communication, teamwork or patient education. They are shown on your profile but are not graded by CareSim.</p>
          </div>
          <div className="personal-skills-side">
            <div className="personal-skill-cloud">{personalSkills.length?personalSkills.map(skill=><span key={skill}><i className="fa-solid fa-sparkles"/>{skill}</span>):<em>No personal skills added yet.</em>}</div>
            <Link href="/profile" className="btn white"><i className="fa-solid fa-user-pen"/> {personalSkills.length?'Edit personal skills':'Add personal skills'}</Link>
          </div>
        </section>

        <div className="info-banner teal-banner">
          <i className="fa-solid fa-circle-info" />
          <div>
            <b>Training skill vs. personal skill</b>
            <span>
              Training skills are official practice modules. Personal skills such as communication,
              teamwork or patient education are added by you from My Profile.
            </span>
          </div>
        </div>

        {(skills || []).length ? (
          <div className="skill-grid clean-skill-grid">
            {((skills || []) as SkillScenario[]).map((skill) => {
              const row = mastery.get(skill.slug.replace(/-/g, '_')) || mastery.get(skill.slug);
              const score = Math.round(Number(row?.mastery || 0));
              const attempts = row?.attempts_count || 0;
              return (
                <article className="skill-card clean-skill-card" key={skill.id}>
                  <div className="skill-top">
                    <span className="skill-icon"><i className="fa-solid fa-stethoscope" /></span>
                    <span className={`skill-status ${score >= 85 ? 'mastered' : ''}`}>
                      {attempts ? (score >= 85 ? 'Mastered' : 'In progress') : 'Not started'}
                    </span>
                  </div>
                  <span className="skill-specialty">{skill.specialty || 'Nursing procedure'}</span>
                  <h3>{skill.title}</h3>
                  <p>{skill.description || 'Practice this nursing procedure in a structured, safe environment.'}</p>

                  <div className="mastery-row">
                    <div><span>Verified mastery</span><strong>{attempts ? `${score}%` : '—'}</strong></div>
                    <div className="bar"><i style={{ width: `${attempts ? score : 0}%` }} /></div>
                  </div>

                  <footer>
                    <span><i className="fa-solid fa-rotate" /> {attempts} verified attempt{attempts === 1 ? '' : 's'}</span>
                    <Link href={`/simulations/${skill.slug}`} className="skill-practice-link">Practice <i className="fa-solid fa-arrow-right"/></Link>
                  </footer>
                </article>
              );
            })}
          </div>
        ) : (
          <section className="panel empty-state-panel">
            <span className="empty-state-icon"><i className="fa-solid fa-syringe" /></span>
            <h2>No Skills Lab modules published yet</h2>
            <p>
              Your Skills Lab should not contain fake or manually hard-coded mastery cards. Once an
              admin or instructor publishes a procedure, it will appear here automatically.
            </p>
            <div className="empty-state-actions">
              <Link className="btn white" href="/profile">Add personal skills</Link>
              <Link className="btn primary" href="/simulations">Practice clinical cases</Link>
            </div>
          </section>
        )}
      </div>
    </AppShell>
  );
}
