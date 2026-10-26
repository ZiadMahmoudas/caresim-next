'use client';

import Link from 'next/link';
import { useState } from 'react';
import { createClient } from '@/lib/supabase/client';

function passwordError(value:string){
  if(value.length<8) return 'Use at least 8 characters.';
  if(!/[a-z]/.test(value)||!/[A-Z]/.test(value)||!/[0-9]/.test(value)) return 'Use upper/lowercase letters and at least one number.';
  return '';
}

export function RegisterForm(){
  const [fullName,setFullName]=useState('');
  const [email,setEmail]=useState('');
  const [learnerType,setLearnerType]=useState<'student'|'nurse'>('student');
  const [password,setPassword]=useState('');
  const [confirm,setConfirm]=useState('');
  const [show,setShow]=useState(false);
  const [terms,setTerms]=useState(false);
  const [loading,setLoading]=useState(false);
  const [error,setError]=useState('');

  async function submit(e:React.FormEvent){
    e.preventDefault();
    setError('');
    if(fullName.trim().length<2){setError('Enter your full name.');return}
    if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())){setError('Enter a valid email address.');return}
    const pe=passwordError(password); if(pe){setError(pe);return}
    if(password!==confirm){setError('Passwords do not match.');return}
    if(!terms){setError('Please accept the Terms and Privacy Policy.');return}

    setLoading(true);
    try{
      // Public registration is created server-side as a confirmed LEARNER only.
      // No signup/confirmation email is sent. Forgot Password remains email-based.
      const response=await fetch('/api/auth/register',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({
          full_name:fullName.trim(),
          email:email.trim().toLowerCase(),
          password,
          learner_type:learnerType,
          website:'',
        }),
      });
      const result=await response.json();
      if(!response.ok) throw new Error(result.error||'Unable to create account');

      const supabase=createClient();
      const {error:signInError}=await supabase.auth.signInWithPassword({
        email:email.trim().toLowerCase(),
        password,
      });
      if(signInError) throw signInError;
      window.location.assign('/dashboard');
    }catch(err){
      setError(err instanceof Error?err.message:'Unable to create account');
    }finally{setLoading(false)}
  }

  return <form className="auth-form register-form" onSubmit={submit} noValidate>
    <label>Full name<input value={fullName} autoComplete="name" onChange={e=>setFullName(e.target.value)} placeholder="Omar Hassan" required/></label>
    <label>Email<input type="email" value={email} autoComplete="email" onChange={e=>setEmail(e.target.value)} placeholder="you@university.edu" required/></label>
    <label>Account type<select value={learnerType} onChange={e=>setLearnerType(e.target.value as 'student'|'nurse')}><option value="student">Nursing student</option><option value="nurse">Practicing nurse / continuing education</option></select></label>
    <label>Password<div className="input-icon"><input type={show?'text':'password'} value={password} autoComplete="new-password" onChange={e=>setPassword(e.target.value)} placeholder="8+ characters" required/><button type="button" className="input-eye" aria-label={show?'Hide password':'Show password'} onClick={()=>setShow(v=>!v)}><i className={`fa-regular ${show?'fa-eye-slash':'fa-eye'}`}/></button></div><small className="field-hint">Uppercase, lowercase and a number.</small></label>
    <label>Confirm password<input type={show?'text':'password'} value={confirm} autoComplete="new-password" onChange={e=>setConfirm(e.target.value)} placeholder="Repeat password" required/></label>
    <label className="terms-check"><input type="checkbox" checked={terms} onChange={e=>setTerms(e.target.checked)}/><span>I agree to the Terms and Privacy Policy.</span></label>
    {error&&<div className="form-message error"><i className="fa-solid fa-circle-exclamation"/>{error}</div>}
    <button className="btn primary full" disabled={loading}>{loading?<><i className="fa-solid fa-spinner fa-spin"/> Creating account…</>:'Create learner account'}</button>
    <div className="auth-switch">Already have an account? <Link href="/login">Sign in</Link></div>
  </form>
}
