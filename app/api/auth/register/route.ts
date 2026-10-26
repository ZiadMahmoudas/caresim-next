import { NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/admin';

function validPassword(value: string) {
  return value.length >= 8 && /[a-z]/.test(value) && /[A-Z]/.test(value) && /[0-9]/.test(value);
}

export async function POST(request: Request) {
  const admin = createAdminClient();
  if (!admin) {
    return NextResponse.json(
      { error: 'SUPABASE_SECRET_KEY is required for direct learner registration.' },
      { status: 500 }
    );
  }

  try {
    const body = await request.json();
    const fullName = String(body.full_name || '').trim();
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    const learnerType = body.learner_type === 'nurse' ? 'nurse' : 'student';
    const honeypot = String(body.website || '').trim();

    if (honeypot) {
      return NextResponse.json({ error: 'Unable to create account.' }, { status: 400 });
    }
    if (fullName.length < 2) {
      return NextResponse.json({ error: 'Enter your full name.' }, { status: 400 });
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return NextResponse.json({ error: 'Enter a valid email address.' }, { status: 400 });
    }
    if (!validPassword(password)) {
      return NextResponse.json(
        { error: 'Use at least 8 characters with uppercase, lowercase and a number.' },
        { status: 400 }
      );
    }

    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        learner_type: learnerType,
      },
    });

    if (error) {
      const message = /already|registered|exists/i.test(error.message)
        ? 'An account already exists with this email. Sign in or use Forgot Password.'
        : error.message;
      return NextResponse.json({ error: message }, { status: 400 });
    }

    if (!data.user) {
      return NextResponse.json({ error: 'Account could not be created.' }, { status: 500 });
    }

    // The auth trigger normally creates this profile. Upsert makes the route resilient
    // if an older database was created before the trigger migration was installed.
    await admin.from('profiles').upsert(
      {
        id: data.user.id,
        email,
        full_name: fullName,
        learner_type: learnerType,
        role: 'student',
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'id' }
    );

    await admin.from('app_activity_logs').insert({ actor_id:data.user.id, action:'registered', entity_type:'profile', entity_id:data.user.id, metadata:{ learner_type:learnerType } });

    await admin.from('audit_logs').insert({
      actor_id: data.user.id,
      action: 'public_learner_registered',
      entity_type: 'profile',
      entity_id: data.user.id,
      metadata: { learner_type: learnerType },
    });

    return NextResponse.json({ ok: true, user_id: data.user.id });
  } catch {
    return NextResponse.json({ error: 'Unable to create account.' }, { status: 500 });
  }
}
