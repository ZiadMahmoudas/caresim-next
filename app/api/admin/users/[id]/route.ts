import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';

export async function DELETE(_: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Authentication required.' }, { status: 401 });
  const { data: me } = await supabase.from('profiles').select('role').eq('id', user.id).single();
  if (me?.role !== 'admin') return NextResponse.json({ error: 'Admin access required.' }, { status: 403 });
  if (id === user.id) return NextResponse.json({ error: 'You cannot delete your own administrator account.' }, { status: 400 });

  const admin = createAdminClient();
  if (!admin) return NextResponse.json({ error: 'SUPABASE_SECRET_KEY is required to delete Auth users.' }, { status: 500 });

  // Preserve referential integrity before removing auth.users/profile.
  await admin.from('courses').update({ instructor_id: null }).eq('instructor_id', id);
  await admin.from('scenarios').update({ created_by: null }).eq('created_by', id);
  const { data: assigned } = await admin.from('assignments').select('id').eq('assigned_by', id);
  const assignmentIds = (assigned || []).map((row) => row.id);
  if (assignmentIds.length) {
    await admin.from('attempts').update({ assignment_id: null }).in('assignment_id', assignmentIds);
    await admin.from('assignments').delete().in('id', assignmentIds);
  }
  await admin.from('audit_logs').update({ actor_id: null }).eq('actor_id', id);
  await admin.from('audit_logs').insert({ actor_id: user.id, action: 'user_deleted', entity_type: 'profile', entity_id: id, metadata: {} });

  const { error } = await admin.auth.admin.deleteUser(id);
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
