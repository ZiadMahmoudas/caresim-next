import { NextResponse } from 'next/server';
import { createClient } from '@/lib/neon/server';

export async function POST(request: Request) {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json().catch(() => ({}));
  const slug = String(body.slug || '').trim();
  if (!slug) return NextResponse.json({ error: 'Scenario slug is required' }, { status: 400 });

  const { data, error } = await db.rpc('start_simulation', { p_slug: slug });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json(data);
}
