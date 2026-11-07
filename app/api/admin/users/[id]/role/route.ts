import { NextResponse } from 'next/server';
import { createClient } from '@/lib/neon/server';
import { getAuth } from '@/lib/neon/auth-server';
import { adminSql } from '@/lib/neon/sql';

export async function PATCH(request: Request, context: { params: Promise<{ id: string }> }) {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Authentication required.' }, { status: 401 });

  const { data: me } = await db.from('profiles').select('role').eq('id', user.id).single();
  if (me?.role !== 'admin') return NextResponse.json({ error: 'Admin access required.' }, { status: 403 });

  const { id } = await context.params;
  const body = await request.json();
  const role = ['student', 'instructor', 'admin'].includes(body.role) ? body.role : null;
  if (!role) return NextResponse.json({ error: 'Invalid role.' }, { status: 400 });

  if (id === user.id && role !== 'admin') {
    return NextResponse.json({ error: 'You cannot remove your own administrator access.' }, { status: 400 });
  }

  // Better Auth's admin plugin gates privileged user-management methods on the Auth role.
  // Keep that role in sync with CareSim's application role: app admins => auth admin; everyone else => auth user.
  const auth = getAuth();
  const authResult: any = await (auth as any).admin.setRole({ userId: id, role: role === 'admin' ? 'admin' : 'user' });
  if (authResult?.error) {
    return NextResponse.json({ error: authResult.error.message || 'Unable to update authentication role.' }, { status: authResult.error.status || 400 });
  }

  const sql = adminSql();
  await sql`update public.profiles set role=${role}::public.user_role, updated_at=now() where id=${id}`;
  await sql`insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(${user.id},'user_role_changed','profile',${id},${JSON.stringify({ role })}::jsonb)`;

  return NextResponse.json({ ok: true, role });
}
