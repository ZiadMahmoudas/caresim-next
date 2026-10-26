import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';

export async function POST(request: Request){
 const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:'Authentication required.'},{status:401});
 const {data:me}=await supabase.from('profiles').select('role').eq('id',user.id).single();if(me?.role!=='admin')return NextResponse.json({error:'Admin access required.'},{status:403});
 const admin=createAdminClient();if(!admin)return NextResponse.json({error:'SUPABASE_SECRET_KEY is required to create Auth users from the Admin Console.'},{status:500});
 const body=await request.json();const fullName=String(body.full_name||'').trim();const email=String(body.email||'').trim().toLowerCase();const password=String(body.password||'');const role=['student','instructor','admin'].includes(body.role)?body.role:'student';const learnerType=body.learner_type==='nurse'?'nurse':'student';
 if(fullName.length<2||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||password.length<8)return NextResponse.json({error:'Enter a valid name, email and password of at least 8 characters.'},{status:400});
 const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name:fullName,learner_type:learnerType}});if(error)return NextResponse.json({error:error.message},{status:400});
 if(data.user){await admin.from('profiles').update({full_name:fullName,role,learner_type:learnerType,email,updated_at:new Date().toISOString()}).eq('id',data.user.id);await admin.from('audit_logs').insert({actor_id:user.id,action:'user_created',entity_type:'profile',entity_id:data.user.id,metadata:{role,email}})}
 return NextResponse.json({ok:true,id:data.user?.id});
}
