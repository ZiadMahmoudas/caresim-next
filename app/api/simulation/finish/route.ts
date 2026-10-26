import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json().catch(() => ({}));
  const attemptId = String(body.attemptId || '');
  if (!attemptId) return NextResponse.json({ error: 'Attempt is required' }, { status: 400 });

  const { data, error } = await supabase.rpc('finish_simulation', { p_attempt_id: attemptId });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json(data);
}
