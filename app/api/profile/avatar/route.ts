import { NextResponse } from 'next/server';
import { createClient } from '@/lib/neon/server';
import { putPublicObject, storageConfigured } from '@/lib/neon/storage';

const allowed = new Set(['image/jpeg', 'image/png', 'image/webp']);
export const runtime = 'nodejs';

export async function POST(request: Request) {
  if (!storageConfigured()) return NextResponse.json({ error: 'File storage is not configured yet.' }, { status: 503 });
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Authentication required.' }, { status: 401 });
  const form = await request.formData();
  const file = form.get('file');
  if (!(file instanceof File)) return NextResponse.json({ error: 'Choose an image first.' }, { status: 400 });
  if (!allowed.has(file.type)) return NextResponse.json({ error: 'Use a JPG, PNG or WebP image.' }, { status: 400 });
  if (file.size > 5 * 1024 * 1024) return NextResponse.json({ error: 'Profile image must be 5 MB or smaller.' }, { status: 400 });
  const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
  const path = `${user.id}/avatar-${Date.now()}.${ext}`;
  try {
    const publicUrl = await putPublicObject('avatars', path, new Uint8Array(await file.arrayBuffer()), file.type);
    const { error } = await db.from('profiles').update({ avatar_url: publicUrl, updated_at: new Date().toISOString() }).eq('id', user.id);
    if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    return NextResponse.json({ url: publicUrl });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Unable to upload image.' }, { status: 500 });
  }
}
