'use client';

import { FormEvent, useEffect, useState } from 'react';
import { createClient } from '@/lib/neon/client';

type Skill = {
  id: string;
  title: string;
  slug: string;
  description: string | null;
  specialty: string | null;
  is_published: boolean;
  current_version: number;
};

export function AdminTrainingLibrary() {
  const [items, setItems] = useState<Skill[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [form, setForm] = useState({ title: '', specialty: '', difficulty: 'Beginner', description: '' });

  async function load() {
    const db = createClient();
    const { data, error } = await db
      .from('scenarios')
      .select('id,title,slug,description,specialty,is_published,current_version')
      .eq('type', 'skill')
      .order('created_at', { ascending: false });
    if (error) setMessage(error.message);
    else setItems((data || []) as Skill[]);
    setLoading(false);
  }

  useEffect(() => { void load(); }, []);

  async function createSkill(event: FormEvent) {
    event.preventDefault();
    if (!form.title.trim()) return;
    setSaving(true); setMessage('');
    const db = createClient();
    const { error } = await db.rpc('admin_create_training_skill', {
      p_title: form.title.trim(),
      p_description: form.description.trim() || null,
      p_specialty: form.specialty.trim() || null,
      p_difficulty: form.difficulty,
    });
    if (error) setMessage(error.message);
    else {
      setMessage('Training skill created as draft. Publish it when the content is ready.');
      setForm({ title: '', specialty: '', difficulty: 'Beginner', description: '' });
      await load();
    }
    setSaving(false);
  }

  async function toggle(skill: Skill) {
    setMessage('');
    const db = createClient();
    const { error } = await db.rpc('admin_set_scenario_published', {
      p_scenario_id: skill.id,
      p_published: !skill.is_published,
    });
    if (error) setMessage(error.message);
    else setItems((rows) => rows.map((row) => row.id === skill.id ? { ...row, is_published: !row.is_published } : row));
  }

  return (
    <section className="panel admin-training-panel">
      <div className="panel-head">
        <div><span>Training catalog</span><h2>Skills Lab modules</h2></div>
        <span className="admin-note">Admin / instructor controlled</span>
      </div>
      <p className="admin-section-copy">
        These modules appear in the learner Skills Lab only after you publish them. They are not the learner&apos;s personal skills.
      </p>
      {message && <div className={`profile-message ${message.includes('created') ? 'success' : ''}`}>{message}</div>}

      <div className="admin-training-layout">
        <form className="training-create-form" onSubmit={createSkill}>
          <label>Skill / procedure title<input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="e.g. IV Cannulation" required /></label>
          <div className="training-form-row">
            <label>Specialty<input value={form.specialty} onChange={(e) => setForm({ ...form, specialty: e.target.value })} placeholder="Fundamentals of Nursing" /></label>
            <label>Difficulty<select value={form.difficulty} onChange={(e) => setForm({ ...form, difficulty: e.target.value })}><option>Beginner</option><option>Intermediate</option><option>Advanced</option><option>Expert</option></select></label>
          </div>
          <label>Description<textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="What will the learner practice?" /></label>
          <button className="btn primary" disabled={saving}>{saving ? 'Creating…' : 'Create draft skill'}</button>
        </form>

        <div className="training-library-list">
          {loading ? <p>Loading training catalog…</p> : items.length ? items.map((skill) => (
            <div className="training-library-row" key={skill.id}>
              <div>
                <b>{skill.title}</b>
                <span>{skill.specialty || 'General nursing'} · v{skill.current_version}</span>
              </div>
              <span className={`publish-pill ${skill.is_published ? 'live' : ''}`}>{skill.is_published ? 'Published' : 'Draft'}</span>
              <button className="subtle-btn" onClick={() => toggle(skill)}>{skill.is_published ? 'Unpublish' : 'Publish'}</button>
            </div>
          )) : <div className="mini-empty"><i className="fa-solid fa-syringe" /><b>No training skills yet</b><span>Create the first official Skills Lab module.</span></div>}
        </div>
      </div>
    </section>
  );
}
