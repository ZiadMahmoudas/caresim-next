import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { homeForRole } from '@/lib/auth';

const protectedPrefixes=['/dashboard','/courses','/simulations','/skills','/progress','/profile','/instructor','/admin','/reset-password'];
const guestOnly=['/login','/register','/forgot-password'];

export async function updateSession(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL;const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key) return NextResponse.next({request});
 let response=NextResponse.next({request});
 const supabase=createServerClient(url,key,{cookies:{getAll(){return request.cookies.getAll()},setAll(cookies){cookies.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request});cookies.forEach(({name,value,options})=>response.cookies.set(name,value,options));}}});
 const {data:claimsData}=await supabase.auth.getClaims();
 const userId=claimsData?.claims?.sub;
 const path=request.nextUrl.pathname;
 const needsAuth=protectedPrefixes.some(p=>path===p||path.startsWith(`${p}/`));
 if(needsAuth&&!userId){const login=request.nextUrl.clone();login.pathname='/login';login.searchParams.set('next',`${path}${request.nextUrl.search}`);return NextResponse.redirect(login)}
 let role:string|undefined;
 if(userId){const {data}=await supabase.from('profiles').select('role').eq('id',userId).maybeSingle();role=data?.role;
   if(path.startsWith('/admin')&&role!=='admin') return NextResponse.redirect(new URL(homeForRole(role),request.url));
   if(path.startsWith('/instructor')&&role!=='instructor'&&role!=='admin') return NextResponse.redirect(new URL('/dashboard',request.url));
   const learnerOnly=['/dashboard','/courses','/progress','/skills'];
   if(role && role!=='student'&&learnerOnly.some(p=>path===p||path.startsWith(`${p}/`))) return NextResponse.redirect(new URL(homeForRole(role),request.url));
   if(guestOnly.includes(path)) return NextResponse.redirect(new URL(homeForRole(role),request.url));
 }
 return response;
}
