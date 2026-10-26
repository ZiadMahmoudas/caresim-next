'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CareModal } from '@/components/CareModal';
import { initialState, SimState } from '@/lib/simulation';

type Message = { type: 'patient' | 'system' | 'student'; text: string };
type Brief = {
  slug: string;
  title: string;
  type?: 'clinical_case' | 'skill';
  description?: string | null;
  specialty?: string | null;
  difficulty?: string;
  estimatedMinutes?: number;
  coverUrl?: string;
  patientImageUrl?: string;
  actions: Array<{ key: string; label: string }>;
};
type Question = {
  id: string;
  questionText: string;
  type: 'single_choice' | 'true_false' | 'short_text';
  options: string[];
  points: number;
};
type FinishData = {
  finalScore: number;
  clinicalScore?: number;
  assessmentScore?: number;
  competencyScores?: Record<string, number>;
  patientOutcome?: string;
  debrief?: { what_went_well?: unknown; improve_next?: string; passed?: boolean };
  passed?: boolean;
};

const icons: Record<string, string> = {
  vital: 'fa-heart-pulse',
  breath: 'fa-lungs',
  history: 'fa-clipboard-list',
  position: 'fa-bed',
  oxygen: 'fa-mask-face',
  reassess: 'fa-rotate',
  escalate: 'fa-phone',
  medication: 'fa-pills',
  glucose: 'fa-droplet',
  wound: 'fa-bandage',
  hygiene: 'fa-hands-bubbles',
};

function iconFor(key: string) {
  const lowered = key.toLowerCase();
  const found = Object.keys(icons).find((part) => lowered.includes(part));
  return found ? icons[found] : 'fa-hand-pointer';
}

function safeNumber(value: unknown, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function parsePossibleJson(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function safeArray<T = unknown>(value: unknown): T[] {
  const parsed = parsePossibleJson(value);
  if (Array.isArray(parsed)) return parsed as T[];
  if (parsed && typeof parsed === 'object') return Object.values(parsed as Record<string, unknown>) as T[];
  return [];
}

function normalizeMessages(value: unknown): Message[] {
  return safeArray<any>(value)
    .map((message): Message | null => {
      if (typeof message === 'string') return { type: 'system', text: message };
      if (!message || typeof message !== 'object') return null;
      const rawType = String(message.type || 'system');
      const type: Message['type'] = rawType === 'patient' || rawType === 'student' ? rawType : 'system';
      const text = String(message.text ?? message.message ?? '').trim();
      return text ? { type, text } : null;
    })
    .filter((message): message is Message => Boolean(message));
}

function normalizeActions(value: unknown): string[] {
  return safeArray<any>(value)
    .map((action) => {
      if (typeof action === 'string') return action;
      if (action && typeof action === 'object') return String(action.label ?? action.action ?? action.key ?? '').trim();
      return '';
    })
    .filter(Boolean);
}

function normalizeSimState(value: unknown): SimState {
  let raw: any = parsePossibleJson(value);
  if (!raw || typeof raw !== 'object') raw = {};
  const patient = raw.patient && typeof raw.patient === 'object' ? raw.patient : {};
  const messages = normalizeMessages(raw.messages);

  return {
    patient: {
      spo2: safeNumber(patient.spo2, initialState.patient.spo2),
      heartRate: safeNumber(patient.heartRate ?? patient.heart_rate, initialState.patient.heartRate),
      respiratoryRate: safeNumber(patient.respiratoryRate ?? patient.respiratory_rate, initialState.patient.respiratoryRate),
      condition: String(patient.condition ?? initialState.patient.condition) || initialState.patient.condition,
      status: String(patient.status ?? initialState.patient.status) || initialState.patient.status,
    },
    score: safeNumber(raw.score, 0),
    actions: normalizeActions(raw.actions),
    messages: messages.length ? messages : [...initialState.messages],
    elapsed: safeNumber(raw.elapsed, 0),
  };
}

function formatTime(seconds: number) {
  const safe = Math.max(0, Math.floor(seconds));
  return `${String(Math.floor(safe / 60)).padStart(2, '0')}:${String(safe % 60).padStart(2, '0')}`;
}

export function SimulationRunner({ brief }: { brief: Brief }) {
  const router = useRouter();
  const [state, setState] = useState<SimState>(() => normalizeSimState(initialState));
  const [attemptId, setAttemptId] = useState('');
  const [chat, setChat] = useState('');
  const [asking, setAsking] = useState(false);
  const [acting, setActing] = useState('');
  const [starting, setStarting] = useState(true);
  const [error, setError] = useState('');
  const [finished, setFinished] = useState(false);
  const [finishData, setFinishData] = useState<FinishData | null>(null);
  const [questions, setQuestions] = useState<Question[]>([]);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [assessmentOpen, setAssessmentOpen] = useState(false);
  const [submittingAssessment, setSubmittingAssessment] = useState(false);
  const [endedByTimeout, setEndedByTimeout] = useState(false);
  const [finalizing, setFinalizing] = useState(false);
  const startedRef = useRef(false);
  const timeoutHandledRef = useRef(false);

  const durationSeconds = useMemo(() => {
    const minutes = Math.min(180, Math.max(1, safeNumber(brief.estimatedMinutes, 15)));
    return Math.round(minutes * 60);
  }, [brief.estimatedMinutes]);
  const [timeLeft, setTimeLeft] = useState(durationSeconds);

  const safeState = useMemo(() => normalizeSimState(state), [state]);
  const grade = useMemo(() => Math.min(100, Math.max(0, Number(finishData?.finalScore ?? safeState.score ?? 0))), [safeState.score, finishData]);
  const timeRatio = durationSeconds > 0 ? timeLeft / durationSeconds : 0;
  const timerLevel: 'normal' | 'warning' | 'critical' = timeLeft <= 60 ? 'critical' : timeRatio <= 0.2 ? 'warning' : 'normal';

  const begin = useCallback(async () => {
    setStarting(true);
    setError('');
    setFinished(false);
    setFinishData(null);
    setQuestions([]);
    setAnswers({});
    setAssessmentOpen(false);
    setEndedByTimeout(false);
    setFinalizing(false);
    timeoutHandledRef.current = false;
    try {
      const response = await fetch('/api/simulation/start', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ slug: brief.slug }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to start simulation');
      const normalized = normalizeSimState(data.state);
      setAttemptId(String(data.attemptId || ''));
      setState(normalized);
      setTimeLeft(Math.max(0, durationSeconds - normalized.elapsed));
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Unable to start simulation');
    } finally {
      setStarting(false);
    }
  }, [brief.slug, durationSeconds]);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;
    void begin();
  }, [begin]);

  async function act(id: string) {
    if (!attemptId || acting || finalizing || finished || timeLeft <= 0) return;
    setActing(id);
    setError('');
    try {
      const response = await fetch('/api/simulation/action', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ attemptId, action: id }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Action failed');
      setState(normalizeSimState(data.state));
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Action failed');
    } finally {
      setActing('');
    }
  }

  async function ask() {
    const message = chat.trim();
    if (!message || asking || !attemptId || finalizing || finished || timeLeft <= 0) return;
    setChat('');
    setAsking(true);
    setError('');
    setState((previous) => {
      const safe = normalizeSimState(previous);
      return { ...safe, messages: [...safe.messages, { type: 'student', text: message }] };
    });
    try {
      const response = await fetch('/api/ai/patient', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ attemptId, message }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Patient response failed');
      setState((previous) => {
        const safe = normalizeSimState(previous);
        return { ...safe, messages: [...safe.messages, { type: 'patient', text: data.reply || 'I’m not sure.' }] };
      });
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Patient response failed');
    } finally {
      setAsking(false);
    }
  }

  const fetchAssessmentQuestions = useCallback(async () => {
    if (!attemptId) return [] as Question[];
    const response = await fetch(`/api/simulation/assessment?attemptId=${encodeURIComponent(attemptId)}`);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Unable to load assessment');
    const loaded = Array.isArray(data.questions) ? (data.questions as Question[]) : [];
    setQuestions(loaded);
    return loaded;
  }, [attemptId]);

  const saveAssessment = useCallback(async (assessmentQuestions: Question[], allowEmpty: boolean) => {
    if (!attemptId) throw new Error('Attempt is missing');
    if (!allowEmpty) {
      const missing = assessmentQuestions.find((question) => !String(answers[question.id] || '').trim());
      if (missing) throw new Error('Answer every assessment question before submitting.');
    }
    const response = await fetch('/api/simulation/assessment', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        attemptId,
        answers: assessmentQuestions.map((question) => ({ questionId: question.id, answer: answers[question.id] ?? '' })),
      }),
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Unable to save assessment');
  }, [attemptId, answers]);

  const completeAttempt = useCallback(async (options?: { redirectAfterTimeout?: boolean }) => {
    if (!attemptId) throw new Error('Attempt is missing');

    const response = await fetch('/api/simulation/finish', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ attemptId }),
    });

    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Unable to finish case');

    setAssessmentOpen(false);

    // On timeout we do not stop on a result screen. The attempt is already
    // persisted server-side, so return the learner to the simulation catalog.
    if (options?.redirectAfterTimeout) {
      router.replace('/simulations?timedOut=1');
      return data as FinishData;
    }

    setFinishData(data as FinishData);
    setFinished(true);
    return data as FinishData;
  }, [attemptId, router]);

  async function loadAssessment() {
    if (!attemptId || finalizing || finished) return;
    setError('');
    try {
      const loaded = questions.length ? questions : await fetchAssessmentQuestions();
      if (loaded.length) {
        setAssessmentOpen(true);
        return;
      }
      setFinalizing(true);
      await completeAttempt();
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Unable to load assessment');
    } finally {
      setFinalizing(false);
    }
  }

  async function submitAssessment() {
    if (submittingAssessment || finalizing) return;
    setSubmittingAssessment(true);
    setError('');
    try {
      await saveAssessment(questions, false);
      setAssessmentOpen(false);
      setFinalizing(true);
      await completeAttempt();
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Unable to save assessment');
    } finally {
      setSubmittingAssessment(false);
      setFinalizing(false);
    }
  }

  const handleTimeExpired = useCallback(async (force = false) => {
    if (!attemptId || finished || finalizing) return;
    if (timeoutHandledRef.current && !force) return;
    timeoutHandledRef.current = true;
    setEndedByTimeout(true);
    setAssessmentOpen(false);
    setFinalizing(true);
    setError('');
    try {
      const loaded = questions.length ? questions : await fetchAssessmentQuestions();
      if (loaded.length) await saveAssessment(loaded, true);

      // Persist the score/result, then leave the exam immediately.
      await completeAttempt({ redirectAfterTimeout: true });
    } catch (exception) {
      setError(exception instanceof Error ? exception.message : 'Unable to submit timed-out attempt');
      timeoutHandledRef.current = false;
    } finally {
      setFinalizing(false);
    }
  }, [attemptId, finished, finalizing, questions, fetchAssessmentQuestions, saveAssessment, completeAttempt]);

  useEffect(() => {
    if (!attemptId || starting || finished || finalizing || timeLeft <= 0) return;
    const timer = window.setInterval(() => {
      setTimeLeft((current) => Math.max(0, current - 1));
      setState((previous) => {
        const safe = normalizeSimState(previous);
        return { ...safe, elapsed: safe.elapsed + 1 };
      });
    }, 1000);
    return () => window.clearInterval(timer);
  }, [attemptId, starting, finished, finalizing, timeLeft]);

  useEffect(() => {
    if (timeLeft === 0 && attemptId && !finished && !starting) void handleTimeExpired();
  }, [timeLeft, attemptId, finished, starting, handleTimeExpired]);

  if (starting) {
    return <main className="simulation-page sim-loading"><div><i className="fa-solid fa-heart-pulse fa-beat"/><h2>Preparing your patient…</h2><p>Loading the instructor-authored scenario state.</p></div></main>;
  }

  if (error && !attemptId) {
    return <main className="sim-finish"><div className="finish-card"><span className="finish-icon error"><i className="fa-solid fa-triangle-exclamation"/></span><h1>Simulation setup required</h1><p>{error}</p><div className="finish-actions"><Link href="/simulations" className="btn white">Back to simulations</Link><button className="btn primary" onClick={begin}>Retry</button></div></div></main>;
  }

  if (finished) {
    const went = normalizeActions(finishData?.debrief?.what_went_well ?? safeState.actions).slice(0, 5).join(', ');
    return <main className="sim-finish"><div className="finish-card"><Link href="/dashboard" className="sim-back"><i className="fa-solid fa-arrow-left"/> Back to dashboard</Link><span className={`finish-icon ${endedByTimeout ? 'timeout' : ''}`}><i className={`fa-solid ${endedByTimeout ? 'fa-clock' : 'fa-circle-check'}`}/></span><span className="eyebrow simple">{endedByTimeout ? 'Time expired' : 'Simulation complete'}</span><h1>{brief.title}</h1>{endedByTimeout&&<div className="timeout-result-note"><i className="fa-solid fa-clock"/><span>Your time expired. CareSim automatically submitted your current clinical actions and assessment answers.</span></div>}<div className="final-score"><strong>{grade}%</strong><span>{finishData?.passed===false?'Needs another attempt':grade>=80?'Excellent performance':'Keep practicing'}</span></div><div className="score-breakdown"><div><span>Clinical simulation</span><b>{Math.round(Number(finishData?.clinicalScore??grade))}%</b></div><div><span>Knowledge assessment</span><b>{questions.length?`${Math.round(Number(finishData?.assessmentScore??0))}%`:'Not used'}</b></div><div><span>Final score</span><b>{grade}%</b></div><div><span>Outcome</span><b>{finishData?.passed===false?'Review':'Completed'}</b></div></div><div className="debrief"><h3><i className="fa-solid fa-sparkles"/> Structured debrief</h3><p><b>Patient outcome:</b> {finishData?.patientOutcome||'Recorded'}</p><p><b>What went well:</b> {went||'Complete more actions to generate feedback.'}</p><p><b>Improve next:</b> {finishData?.debrief?.improve_next||'Review your timeline and the instructor-authored assessment.'}</p></div><div className="finish-actions"><Link href="/simulations" className="btn white">Browse simulations</Link><button className="btn primary" onClick={begin}>Start a new attempt</button></div></div></main>;
  }

  const lastPatient = [...safeState.messages].reverse().find((message) => message.type === 'patient')?.text || 'The patient is waiting for your assessment.';
  const room = brief.coverUrl || 'https://images.unsplash.com/photo-1538108149393-fbbd81895907?auto=format&fit=crop&w=1600&q=85';
  const patient = brief.patientImageUrl || 'https://images.unsplash.com/photo-1584982751601-97dcc096659c?auto=format&fit=crop&w=650&q=85';

  return <main className={`simulation-page time-${timerLevel}`}>
    {timerLevel==='critical'&&<div className="sim-time-pressure" aria-hidden="true"/>}
    <header className="sim-header">
      <Link href="/simulations" className="sim-back"><i className="fa-solid fa-arrow-left"/> Exit simulation</Link>
      <div><span>{brief.type==='skill'?'Skills Lab':'Clinical Simulation'}</span><b>{brief.title}</b></div>
      <div className="sim-head-right"><div className={`exam-clock ${timerLevel}`}><i className="fa-solid fa-stopwatch"/><div><span>Time remaining</span><b>{formatTime(timeLeft)}</b></div></div></div>
    </header>

    {timerLevel!=='normal'&&<div className={`simulation-time-alert ${timerLevel}`} role="status" aria-live="polite"><i className={`fa-solid ${timerLevel==='critical'?'fa-triangle-exclamation':'fa-clock'}`}/><div><b>{timerLevel==='critical'?'Time is almost up':'Watch your time'}</b><span>{timerLevel==='critical'?`${formatTime(timeLeft)} remaining. Your attempt will be submitted automatically when time expires.`:`${formatTime(timeLeft)} remaining in this attempt.`}</span></div></div>}

    {error&&<div className="sim-error"><i className="fa-solid fa-circle-exclamation"/><span>{error}</span>{timeLeft===0&&!finished&&!finalizing&&<button type="button" onClick={()=>{timeoutHandledRef.current=false;void handleTimeExpired(true)}}>Retry submission</button>}</div>}

    <div className="sim-workspace">
      <section className="patient-stage">
        <div className="patient-room">
          <Image src={room} fill alt="Virtual clinical environment" sizes="70vw"/>
          <div className="room-shade"/>
          <div className="patient-person"><Image src={patient} fill alt="Simulated patient" sizes="430px"/></div>
          <div className="patient-speech">{lastPatient}<span/></div>
          <div className="monitor"><small>Patient monitor</small><div className="vital-main"><span>SpO₂</span><strong className={safeState.patient.spo2<90?'danger':'good'}>{safeState.patient.spo2}%</strong></div><div className="monitor-grid"><div><span>HR</span><b>{safeState.patient.heartRate}</b></div><div><span>RR</span><b>{safeState.patient.respiratoryRate}</b></div></div></div>
          <div className={`condition-badge ${safeState.patient.status}`}><span/>{safeState.patient.condition}</div>
        </div>

        <div className="action-dock"><div className="dock-head"><div><span>Instructor-authored interactions</span><b>What will you do next?</b></div><span>{safeState.actions.length} actions taken</span></div><div className="action-grid">{brief.actions.map((action)=><button key={action.key} disabled={Boolean(acting)||finalizing||timeLeft<=0} onClick={()=>act(action.key)}><i className={`fa-solid ${acting===action.key?'fa-spinner fa-spin':iconFor(action.key)}`}/><span>{action.label}</span></button>)}</div></div>
      </section>

      <aside data-lenis-prevent className="sim-side">
        <div className="sim-case-label"><span>Case overview</span></div>
        <div className="case-brief"><span className="case-tag">{brief.type==='skill'?'Skills Lab':brief.specialty||'Clinical training'}</span><h2>{brief.title}</h2><p>{brief.description||'Assess the patient, prioritize actions, intervene and reassess.'}</p><div className="brief-row"><span>Goal</span><b>Assess → intervene → reassess</b></div><div className="brief-row"><span>Difficulty</span><b>{brief.difficulty||'Intermediate'}</b></div><div className="brief-row"><span>Time limit</span><b>{Math.round(durationSeconds/60)} min</b></div></div>

        <div className="ai-patient"><div className="ai-title"><span><i className="fa-solid fa-wand-magic-sparkles"/></span><div><b>AI Simulated Patient</b><small>Bound to instructor-approved patient facts</small></div><i className="fa-solid fa-circle online"/></div><div data-lenis-prevent className="chat-log">{safeState.messages.slice(-8).map((message,index)=><div key={`${message.type}-${index}`} className={`chat ${message.type}`}><span>{message.type==='patient'?'Patient':message.type==='student'?'You':'CareSim'}</span><p>{message.text}</p></div>)}{asking&&<div className="chat patient typing"><span>Patient</span><p><i className="fa-solid fa-ellipsis fa-beat-fade"/> Thinking…</p></div>}</div><div className="chat-box"><input value={chat} onChange={(event)=>setChat(event.target.value)} onKeyDown={(event)=>{if(event.key==='Enter')void ask()}} placeholder={timeLeft<=0?'Time expired':'Ask the patient a question…'} disabled={asking||finalizing||timeLeft<=0}/><button onClick={()=>void ask()} disabled={asking||finalizing||timeLeft<=0} aria-label="Send question"><i className="fa-solid fa-paper-plane"/></button></div><small className="ai-note"><i className="fa-solid fa-lock"/> Dialogue uses instructor-approved case facts. Grading stays rule-based.</small></div>

        <div className="sim-footer-side"><div><span>Clinical score</span><b>{grade} pts</b></div><button className="btn primary full" onClick={()=>void loadAssessment()} disabled={finalizing||timeLeft<=0}>{finalizing?<><i className="fa-solid fa-spinner fa-spin"/> Submitting…</>:'End case & assessment'}</button></div>
      </aside>
    </div>

    <CareModal
      open={assessmentOpen}
      onClose={()=>{if(timeLeft>0&&!submittingAssessment)setAssessmentOpen(false)}}
      title="Post-simulation assessment"
      subtitle="Answer the instructor-authored questions. Correct answers remain hidden until grading."
      icon="fa-list-check"
      width="lg"
      footer={<><button className="btn white" onClick={()=>setAssessmentOpen(false)} disabled={timeLeft<=0||submittingAssessment}>Back to case</button><button className="btn primary" onClick={()=>void submitAssessment()} disabled={submittingAssessment||finalizing||timeLeft<=0}>{submittingAssessment?'Submitting…':'Submit & finish'}</button></>}
    >
      <div className={`assessment-timer ${timerLevel}`}><div><i className="fa-solid fa-stopwatch"/><span>Time remaining</span></div><strong>{formatTime(timeLeft)}</strong></div>
      {timerLevel==='critical'&&<div className="assessment-critical-note"><i className="fa-solid fa-triangle-exclamation"/> Less than one minute remaining. The exam will be submitted automatically.</div>}
      <div className="learner-assessment">{questions.map((question,index)=><article key={question.id}><div className="assessment-q-head"><span>Q{index+1}</span><b>{question.points} pts</b></div><h3>{question.questionText}</h3>{question.type==='short_text'?<textarea value={answers[question.id]||''} onChange={(event)=>setAnswers((previous)=>({...previous,[question.id]:event.target.value}))} placeholder="Type your answer…" disabled={timeLeft<=0}/>:<div className="assessment-options">{(question.type==='true_false'?['True','False']:question.options).map((option)=><label key={option}><input type="radio" name={question.id} checked={answers[question.id]===option} disabled={timeLeft<=0} onChange={()=>setAnswers((previous)=>({...previous,[question.id]:option}))}/><span>{option}</span></label>)}</div>}</article>)}</div>
    </CareModal>

    {finalizing&&endedByTimeout&&<div className="timeout-submitting"><div><i className="fa-solid fa-clock fa-beat"/><h2>Time expired</h2><p>Your attempt is being saved. You will be returned to simulations automatically.</p><Link href="/simulations" className="btn white timeout-return">Return to simulations</Link></div></div>}
  </main>;
}
