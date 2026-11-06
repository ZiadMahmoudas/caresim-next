import { NextResponse } from 'next/server';
import { auth } from '@/lib/neon/auth-server';
import { adminSql } from '@/lib/neon/sql';

function validPassword(value: string) {
  return value.length >= 8 && /[a-z]/.test(value) && /[A-Z]/.test(value) && /[0-9]/.test(value);
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const fullName = String(body.full_name || '').trim();
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    const learnerType = body.learner_type === 'nurse' ? 'nurse' : 'student';
    const honeypot = String(body.website || '').trim();

    if (honeypot) return NextResponse.json({ error: 'Unable to create account.' }, { status: 400 });
    if (fullName.length < 2) return NextResponse.json({ error: 'Enter your full name.' }, { status: 400 });
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return NextResponse.json({ error: 'Enter a valid email address.' }, { status: 400 });
    if (!validPassword(password)) return NextResponse.json({ error: 'Use at least 8 characters with uppercase, lowercase and a number.' }, { status: 400 });

    const result: any = await (auth as any).signUp.email({ email, password, name: fullName });
    if (result?.error) {
      const message = /already|registered|exists/i.test(result.error.message || '')
        ? 'An account already exists with this email. Sign in or use Forgot Password.'
        : (result.error.message || 'Unable to create account.');
      return NextResponse.json({ error: message }, { status: result.error.status || 400 });
    }
    const user = result?.data?.user ?? result?.user;
    if (!user?.id) return NextResponse.json({ error: 'Account could not be created.' }, { status: 500 });

    const sql = adminSql();
    await sql`update public.profiles set full_name=${fullName}, email=${email}, learner_type=${learnerType}, role='student', updated_at=now() where id=${user.id}`;
    await sql`insert into public.app_activity_logs(actor_id,action,entity_type,entity_id,metadata) values(${user.id},'registered','profile',${user.id},${JSON.stringify({learner_type:learnerType})}::jsonb)`;
    await sql`insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(${user.id},'public_learner_registered','profile',${user.id},${JSON.stringify({learner_type:learnerType})}::jsonb)`;
    return NextResponse.json({ ok: true, user_id: user.id });
  } catch (error) {
    console.error('Neon registration error', error);
    return NextResponse.json({ error: 'Unable to create account.' }, { status: 500 });
  }
}
