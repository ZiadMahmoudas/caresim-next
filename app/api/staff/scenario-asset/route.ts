import { NextResponse } from 'next/server';
import { createClient } from '@/lib/neon/server';
import { putPublicObject, storageConfigured } from '@/lib/neon/storage';

const allowed = new Set(['image/jpeg','image/png','image/webp']);
export const runtime = 'nodejs';

export async function POST(request: Request) {
  if (!storageConfigured()) return NextResponse.json({ error: 'File storage is not configured yet.' }, { status: 503 });
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data: profile } = await db.from('profiles').select('role').eq('id', user.id).maybeSingle();
  if (!profile || !['admin','instructor'].includes(profile.role)) return NextResponse.json({ error: 'Staff access required' }, { status: 403 });
  const form = await request.formData();const scenarioId=String(form.get('scenarioId')||'');const kind=String(form.get('kind')||'patient');const file=form.get('file');
  if (!scenarioId || !(file instanceof File)) return NextResponse.json({ error: 'Scenario and image are required' }, { status: 400 });
  if (!allowed.has(file.type)) return NextResponse.json({ error: 'Use JPG, PNG or WebP images only' }, { status: 400 });
  if (file.size > 5*1024*1024) return NextResponse.json({ error: 'Image must be 5 MB or smaller' }, { status: 400 });
  const { data: scenario } = await db.from('scenarios').select('id,created_by').eq('id', scenarioId).maybeSingle();
  if (!scenario || (profile.role === 'instructor' && scenario.created_by !== user.id)) return NextResponse.json({ error: 'You cannot edit this scenario' }, { status: 403 });
  const ext=file.name.split('.').pop()?.toLowerCase()||'jpg';const path=`${scenarioId}/${kind}-${Date.now()}.${ext}`;
  try {
    const publicUrl=await putPublicObject('scenario-assets',path,new Uint8Array(await file.arrayBuffer()),file.type);
    const {error}=await db.from('scenario_assets').insert({scenario_id:scenarioId,uploaded_by:user.id,kind,name:file.name,storage_path:path,public_url:publicUrl,mime_type:file.type,size_bytes:file.size});
    if(error)return NextResponse.json({error:error.message},{status:400});
    return NextResponse.json({url:publicUrl,path});
  } catch(error){return NextResponse.json({error:error instanceof Error?error.message:'Unable to upload image.'},{status:500})}
}
