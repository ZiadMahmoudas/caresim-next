import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';

const allowed = new Set(['image/jpeg','image/png','image/webp']);

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data: profile } = await supabase.from('profiles').select('role').eq('id', user.id).maybeSingle();
  if (!profile || !['admin','instructor'].includes(profile.role)) return NextResponse.json({ error: 'Staff access required' }, { status: 403 });

  const form = await request.formData();
  const scenarioId = String(form.get('scenarioId') || '');
  const kind = String(form.get('kind') || 'patient');
  const file = form.get('file');
  if (!scenarioId || !(file instanceof File)) return NextResponse.json({ error: 'Scenario and image are required' }, { status: 400 });
  if (!allowed.has(file.type)) return NextResponse.json({ error: 'Use JPG, PNG or WebP images only' }, { status: 400 });
  if (file.size > 5 * 1024 * 1024) return NextResponse.json({ error: 'Image must be 5 MB or smaller' }, { status: 400 });

  const { data: scenario } = await supabase.from('scenarios').select('id,created_by').eq('id', scenarioId).maybeSingle();
  if (!scenario || (profile.role === 'instructor' && scenario.created_by !== user.id)) return NextResponse.json({ error: 'You cannot edit this scenario' }, { status: 403 });

  const admin = createAdminClient();
  if (!admin) return NextResponse.json({ error: 'SUPABASE_SECRET_KEY is required for staff media uploads' }, { status: 500 });
  const ext = file.name.split('.').pop()?.toLowerCase() || 'jpg';
  const path = `${scenarioId}/${kind}-${Date.now()}.${ext}`;
  const bytes = Buffer.from(await file.arrayBuffer());
  const { error: uploadError } = await admin.storage.from('scenario-assets').upload(path, bytes, { contentType: file.type, upsert: false });
  if (uploadError) return NextResponse.json({ error: uploadError.message }, { status: 400 });
  const { data: publicData } = admin.storage.from('scenario-assets').getPublicUrl(path);
  const publicUrl = publicData.publicUrl;
  await admin.from('scenario_assets').insert({ scenario_id: scenarioId, uploaded_by: user.id, kind, name: file.name, storage_path: path, public_url: publicUrl, mime_type: file.type, size_bytes: file.size });
  return NextResponse.json({ url: publicUrl, path });
}
