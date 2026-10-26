import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';

const allowed = new Set(['image/jpeg', 'image/png', 'image/webp']);

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Authentication required.' }, { status: 401 });

  const form = await request.formData();
  const file = form.get('file');
  if (!(file instanceof File)) return NextResponse.json({ error: 'Choose an image first.' }, { status: 400 });
  if (!allowed.has(file.type)) return NextResponse.json({ error: 'Use a JPG, PNG or WebP image.' }, { status: 400 });
  if (file.size > 5 * 1024 * 1024) return NextResponse.json({ error: 'Profile image must be 5 MB or smaller.' }, { status: 400 });

  const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
  const path = `${user.id}/avatar.${ext}`;
  const bytes = new Uint8Array(await file.arrayBuffer());
  const admin = createAdminClient();
  const storage = admin ?? supabase;
  const { error: uploadError } = await storage.storage.from('avatars').upload(path, bytes, {
    upsert: true,
    contentType: file.type,
    cacheControl: '3600',
  });
  if (uploadError) {
    return NextResponse.json({
      error: `${uploadError.message}. Run supabase/migrations/006_admin_workspace.sql and configure SUPABASE_SECRET_KEY for the server-side fallback.`,
    }, { status: 400 });
  }

  const { data } = storage.storage.from('avatars').getPublicUrl(path);
  const publicUrl = `${data.publicUrl}?v=${Date.now()}`;
  const db = admin ?? supabase;
  const { error: profileError } = await db.from('profiles').update({ avatar_url: publicUrl, updated_at: new Date().toISOString() }).eq('id', user.id);
  if (profileError) return NextResponse.json({ error: profileError.message }, { status: 400 });

  return NextResponse.json({ url: publicUrl });
}
