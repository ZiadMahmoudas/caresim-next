'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
export function ResetPasswordForm(){
 const router=useRouter();const [password,setPassword]=useState('');const [confirm,setConfirm]=useState('');const [loading,setLoading]=useState(false);const [error,setError]=useState('');
 async function submit(e:React.FormEvent){e.preventDefault();setError('');if(password.length<8||!/[A-Z]/.test(password)||!/[a-z]/.test(password)||!/[0-9]/.test(password)){setError('Use 8+ characters with uppercase, lowercase and a number.');return}if(password!==confirm){setError('Passwords do not match.');return}setLoading(true);try{const supabase=createClient();const {error}=await supabase.auth.updateUser({password});if(error)throw error;router.replace('/dashboard');router.refresh()}catch(err){setError(err instanceof Error?err.message:'Unable to update password')}finally{setLoading(false)}}
 return <form className="auth-form" onSubmit={submit}><label>New password<input type="password" autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="8+ characters" required/></label><label>Confirm password<input type="password" autoComplete="new-password" value={confirm} onChange={e=>setConfirm(e.target.value)} placeholder="Repeat password" required/></label>{error&&<div className="form-message error">{error}</div>}<button className="btn primary full" disabled={loading}>{loading?'Updating…':'Update password'}</button></form>
}
