import Link from 'next/link';
import { AppShell } from '@/components/AppShell';
import { ProgressRing } from '@/components/ProgressRing';
import { createClient } from '@/lib/supabase/server';

type Attempt = { id: string; score: number; completed_at: string | null };
type Result = { attempt_id: string; final_score: number; competency_scores: Record<string, number> | null };
type Mastery = { skill_key: string; mastery: number; attempts_count: number; best_score: number };

function titleCase(value: string) {
  return value.replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

export default async function Progress() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  const { data: attemptsData } = user
    ? await supabase
        .from('attempts')
        .select('id,score,completed_at')
        .eq('student_id', user.id)
        .eq('status', 'completed')
        .order('completed_at', { ascending: false })
        .limit(50)
    : { data: [] };

  const attempts = (attemptsData || []) as Attempt[];
  const attemptIds = attempts.map((a) => a.id);

  const [{ data: resultData }, { data: masteryData }] = await Promise.all([
    attemptIds.length
      ? supabase.from('attempt_results').select('attempt_id,final_score,competency_scores').in('attempt_id', attemptIds)
      : Promise.resolve({ data: [] as Result[] }),
    user
      ? supabase
          .from('skill_mastery')
          .select('skill_key,mastery,attempts_count,best_score')
          .eq('student_id', user.id)
          .order('updated_at', { ascending: false })
      : Promise.resolve({ data: [] as Mastery[] }),
  ]);

  const results = (resultData || []) as Result[];
  const mastery = (masteryData || []) as Mastery[];
  const scores = attempts.map((a) => Number(a.score || 0));
  const completed = attempts.length;
  const average = completed ? Math.round(scores.reduce((a, b) => a + b, 0) / completed) : 0;
  const best = completed ? Math.round(Math.max(...scores)) : 0;
  const overallMastery = mastery.length
    ? Math.round(mastery.reduce((sum, row) => sum + Number(row.mastery || 0), 0) / mastery.length)
    : average;

  const recent = [...attempts].slice(0, 6).reverse();
  const competencyBuckets = new Map<string, number[]>();
  for (const result of results) {
    for (const [key, raw] of Object.entries(result.competency_scores || {})) {
      const value = Number(raw);
      if (!Number.isFinite(value)) continue;
      competencyBuckets.set(key, [...(competencyBuckets.get(key) || []), value]);
    }
  }
  const competencies = [...competencyBuckets.entries()]
    .map(([key, values]) => ({
      key,
      value: Math.round(values.reduce((a, b) => a + b, 0) / values.length),
    }))
    .sort((a, b) => b.value - a.value);

  return (
    <AppShell>
      <div className="page page-airy">
        <div className="page-head compact-head">
          <div>
            <span className="eyebrow simple">Progress</span>
            <h1>Your verified clinical progress.</h1>
            <p>Only completed, server-verified attempts are included here. No demo scores.</p>
          </div>
        </div>

        {!completed ? (
          <section className="panel empty-state-panel">
            <span className="empty-state-icon"><i className="fa-solid fa-chart-line" /></span>
            <h2>Your progress starts with your first simulation</h2>
            <p>Complete a clinical case or Skills Lab procedure and CareSim will build your progress automatically.</p>
            <Link href="/simulations" className="btn primary">Start a simulation</Link>
          </section>
        ) : (
          <>
            <div className="progress-summary-grid">
              <section className="panel progress-primary-card">
                <ProgressRing value={overallMastery} label="verified" />
                <div>
                  <span className="metric-kicker">Overall mastery</span>
                  <h2>{overallMastery}%</h2>
                  <p>Average of your verified competency records.</p>
                </div>
              </section>
              <section className="mini-metric-card"><span>Completed attempts</span><strong>{completed}</strong><small>Saved in CareSim</small></section>
              <section className="mini-metric-card"><span>Average score</span><strong>{average}%</strong><small>Across completed attempts</small></section>
              <section className="mini-metric-card"><span>Best score</span><strong>{best}%</strong><small>Your highest verified result</small></section>
            </div>

            <div className="progress-two-col">
              <section className="panel trend-panel">
                <div className="panel-head"><div><span>Recent attempts</span><h2>Performance trend</h2></div></div>
                <div className="chart clean-chart">
                  {recent.map((attempt, index) => {
                    const score = Math.round(Number(attempt.score || 0));
                    return <span key={attempt.id} style={{ height: `${Math.max(16, score)}%` }} title={`Attempt ${index + 1}: ${score}%`}>{score}</span>;
                  })}
                </div>
                <p className="chart-caption">Oldest → newest, last {recent.length} completed attempt{recent.length === 1 ? '' : 's'}.</p>
              </section>

              <section className="panel competency-compact">
                <div className="panel-head"><div><span>Clinical domains</span><h2>Competency averages</h2></div></div>
                {competencies.length ? competencies.slice(0, 6).map((item) => (
                  <div className="compact-progress-row" key={item.key}>
                    <div><b>{titleCase(item.key)}</b><strong>{item.value}%</strong></div>
                    <div className="bar"><i style={{ width: `${item.value}%` }} /></div>
                  </div>
                )) : <p className="muted-copy">Your completed attempts do not contain competency breakdowns yet.</p>}
              </section>
            </div>

            <section className="panel mastery-list-panel">
              <div className="panel-head"><div><span>Verified mastery</span><h2>Skills & case competencies</h2></div><Link href="/skills">Skills Lab</Link></div>
              {mastery.length ? (
                <div className="mastery-list-clean">
                  {mastery.map((row) => (
                    <div className="mastery-list-row" key={row.skill_key}>
                      <div><b>{titleCase(row.skill_key)}</b><span>{row.attempts_count} verified attempt{row.attempts_count === 1 ? '' : 's'} · best {Math.round(row.best_score)}%</span></div>
                      <div className="bar"><i style={{ width: `${Math.round(row.mastery)}%` }} /></div>
                      <strong>{Math.round(row.mastery)}%</strong>
                    </div>
                  ))}
                </div>
              ) : <p className="muted-copy">No mastery records yet.</p>}
            </section>
          </>
        )}
      </div>
    </AppShell>
  );
}
