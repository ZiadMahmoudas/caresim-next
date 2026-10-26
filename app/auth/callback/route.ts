import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { homeForRole } from '@/lib/auth';
export async function GET(request:Request){
 const url=new URL(request.url);const code=url.searchParams.get('code');const requested=url.searchParams.get('next');
 if(code){const supabase=await createClient();const {data,error}=await supabase.auth.exchangeCodeForSession(code);if(!error&&data.user){if(requested==='/reset-password') return NextResponse.redirect(new URL('/reset-password',url.origin));const {data:profile}=await supabase.from('profiles').select('role').eq('id',data.user.id).maybeSingle();return NextResponse.redirect(new URL(requested&&requested.startsWith('/')?requested:homeForRole(profile?.role),url.origin));}}
 return NextResponse.redirect(new URL('/login?error=auth_callback_failed',url.origin));
}
