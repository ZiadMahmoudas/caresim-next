'use client';

import Link from 'next/link';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/neon/client';
import { homeForRole } from '@/lib/auth';

export function LoginForm({ nextPath = '' }: { nextPath?: string }){
  const router=useRouter();
  const [email,setEmail]=useState('');
  const [password,setPassword]=useState('');
  const [show,setShow]=useState(false);
  const [loading,setLoading]=useState(false);
  const [error,setError]=useState('');

  async function submit(e:React.FormEvent){
    e.preventDefault(); setError('');
    if(!email.trim() || password.length < 6){ setError('Enter a valid email and password.'); return; }
    setLoading(true);
    try{
      const db=createClient();
      const {data,error}=await db.auth.signInWithPassword({email:email.trim().toLowerCase(),password});
      if(error) throw error;
      try{await db.rpc('record_app_activity',{p_action:'login',p_metadata:{source:'password'},p_entity_type:'session',p_entity_id:null})}catch{}
      const {data:profile}=await db.from('profiles').select('role').eq('id',data.user.id).maybeSingle();
      const requested=nextPath;
      const target=requested && requested.startsWith('/') ? requested : homeForRole(profile?.role);
      router.replace(target); router.refresh();
    }catch(err){const m=err instanceof Error?err.message:'Unable to sign in';setError(m==='Invalid login credentials'?'Invalid email or password. If you do not have an account yet, create one first.':m);}finally{setLoading(false)}
  }

  return <form className="auth-form" onSubmit={submit} noValidate>
    <label>Email<input type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="student@university.edu" required /></label>
    <label>Password<div className="input-icon"><input type={show?'text':'password'} autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="••••••••" required /><button type="button" className="input-eye" aria-label="Toggle password visibility" onClick={()=>setShow(v=>!v)}><i className={`fa-regular ${show?'fa-eye-slash':'fa-eye'}`} /></button></div></label>
    {error&&<div className="form-message error"><i className="fa-solid fa-circle-exclamation" />{error}</div>}
    <div className="form-row"><span className="secure-hint"><i className="fa-solid fa-shield-halved"/> Secure sign in</span><Link href="/forgot-password">Forgot password?</Link></div>
    <button className="btn primary full" disabled={loading}>{loading?<><i className="fa-solid fa-spinner fa-spin"/> Signing in…</>:'Sign in'}</button>
    <div className="auth-switch">New to CareSim? <Link href="/register">Create learner account</Link></div>
  </form>
}
