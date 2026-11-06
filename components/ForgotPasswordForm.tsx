'use client';
import Link from 'next/link';
import { useState } from 'react';
import { authClient } from '@/lib/neon/auth-client';
export function ForgotPasswordForm(){
 const [email,setEmail]=useState('');const [loading,setLoading]=useState(false);const [error,setError]=useState('');const [sent,setSent]=useState(false);
 async function submit(e:React.FormEvent){e.preventDefault();setError('');setLoading(true);try{const {error}=await authClient.requestPasswordReset({email:email.trim().toLowerCase(),redirectTo:`${window.location.origin}/reset-password`});if(error)throw new Error(error.message||'Unable to send reset email');setSent(true)}catch(err){setError(err instanceof Error?err.message:'Unable to send reset email')}finally{setLoading(false)}}
 return <form className="auth-form" onSubmit={submit}>{sent?<div className="reset-success"><span><i className="fa-solid fa-envelope-open-text"/></span><h3>Check your inbox</h3><p>If an account exists for <b>{email}</b>, you’ll receive a secure reset link from CareSim authentication. Check spam too.</p><Link href="/login" className="btn white full">Back to sign in</Link></div>:<><label>Email<input type="email" autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="you@university.edu" required/></label>{error&&<div className="form-message error">{error}</div>}<button className="btn primary full" disabled={loading}>{loading?'Sending…':'Send reset link'}</button><small className="auth-mail-note"><i className="fa-solid fa-shield-halved"/> Recovery is handled by Neon Auth.</small><div className="auth-switch"><Link href="/login"><i className="fa-solid fa-arrow-left"/> Back to sign in</Link></div></>}</form>
}
