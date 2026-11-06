import { NextResponse } from 'next/server';
import { createClient } from '@/lib/neon/server';
import { auth } from '@/lib/neon/auth-server';
import { adminSql } from '@/lib/neon/sql';

export async function POST(request: Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return NextResponse.json({error:'Authentication required.'},{status:401});
 const {data:me}=await db.from('profiles').select('role').eq('id',user.id).single();if(me?.role!=='admin')return NextResponse.json({error:'Admin access required.'},{status:403});
 const body=await request.json();const fullName=String(body.full_name||'').trim();const email=String(body.email||'').trim().toLowerCase();const password=String(body.password||'');const role=['student','instructor','admin'].includes(body.role)?body.role:'student';const learnerType=body.learner_type==='nurse'?'nurse':'student';
 if(fullName.length<2||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||password.length<8)return NextResponse.json({error:'Enter a valid name, email and password of at least 8 characters.'},{status:400});
 const result:any=await (auth as any).admin.createUser({email,password,name:fullName,role:role==='admin'?'admin':'user'});
 if(result?.error)return NextResponse.json({error:result.error.message||'Unable to create user'},{status:result.error.status||400});
 const created=result?.data?.user??result?.data??result?.user;const id=created?.id;if(!id)return NextResponse.json({error:'Auth user was created but no user ID was returned.'},{status:500});
 const sql=adminSql();
 await sql`update public.profiles set full_name=${fullName},role=${role}::public.user_role,learner_type=${learnerType},email=${email},updated_at=now() where id=${id}`;
 await sql`insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(${user.id},'user_created','profile',${id},${JSON.stringify({role,email})}::jsonb)`;
 return NextResponse.json({ok:true,id});
}
