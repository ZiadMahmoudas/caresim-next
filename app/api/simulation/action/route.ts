import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json().catch(() => ({}));
  const attemptId = String(body.attemptId || '');
  const action = String(body.action || '');
  if (!attemptId || !action) return NextResponse.json({ error: 'Attempt and action are required' }, { status: 400 });

  const { data, error } = await supabase.rpc('perform_simulation_action', {
    p_attempt_id: attemptId,
    p_action_key: action,
    p_payload: body.payload || {},
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json(data);
}
