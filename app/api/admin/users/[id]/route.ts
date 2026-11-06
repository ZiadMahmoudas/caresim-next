import { NextResponse } from 'next/server';
import { createClient } from '@/lib/neon/server';
import { auth } from '@/lib/neon/auth-server';
import { adminSql } from '@/lib/neon/sql';

export async function DELETE(_: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Authentication required.' }, { status: 401 });
  const { data: me } = await db.from('profiles').select('role').eq('id', user.id).single();
  if (me?.role !== 'admin') return NextResponse.json({ error: 'Admin access required.' }, { status: 403 });
  if (id === user.id) return NextResponse.json({ error: 'You cannot delete your own administrator account.' }, { status: 400 });

  const sql = adminSql();
  await sql`update public.courses set instructor_id=null where instructor_id=${id}`;
  await sql`update public.scenarios set created_by=null where created_by=${id}`;
  await sql`update public.attempts set assignment_id=null where assignment_id in (select id from public.assignments where assigned_by=${id})`;
  await sql`delete from public.assignments where assigned_by=${id}`;
  await sql`update public.audit_logs set actor_id=null where actor_id=${id}`;
  await sql`insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(${user.id},'user_deleted','profile',${id},'{}'::jsonb)`;

  const result:any = await (auth as any).admin.removeUser({ userId: id });
  if (result?.error) return NextResponse.json({ error: result.error.message || 'Unable to delete Auth user.' }, { status: result.error.status || 400 });

  // The auth identity is gone; now remove the CareSim profile. User-owned attempts, memberships,
  // mastery and notifications cascade through the schema, while historical audit/activity rows keep a null actor.
  await sql`delete from public.profiles where id=${id}`;
  return NextResponse.json({ ok: true });
}
