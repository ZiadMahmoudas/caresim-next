import { NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const configured = {
    supabaseUrl: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    supabasePublishableKey: Boolean(process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY),
    supabaseSecretKey: Boolean(process.env.SUPABASE_SECRET_KEY),
    gemini: Boolean(process.env.GEMINI_API_KEY),
    emailjs:
      Boolean(process.env.NEXT_PUBLIC_EMAILJS_SERVICE_ID) &&
      Boolean(process.env.NEXT_PUBLIC_EMAILJS_TEMPLATE_ID) &&
      Boolean(process.env.NEXT_PUBLIC_EMAILJS_PUBLIC_KEY),
    siteUrl: Boolean(
      process.env.NEXT_PUBLIC_SITE_URL ||
      process.env.VERCEL_PROJECT_PRODUCTION_URL ||
      process.env.VERCEL_URL
    ),
  };

  let database: 'ok' | 'error' | 'not-configured' = 'not-configured';
  const admin = createAdminClient();

  if (admin) {
    const { error } = await admin
      .from('profiles')
      .select('id', { count: 'exact', head: true });
    database = error ? 'error' : 'ok';
  }

  const required =
    configured.supabaseUrl &&
    configured.supabasePublishableKey &&
    configured.supabaseSecretKey &&
    configured.gemini &&
    configured.siteUrl &&
    database === 'ok';

  return NextResponse.json(
    {
      ok: required,
      service: 'CareSim',
      environment: process.env.VERCEL_ENV || process.env.NODE_ENV || 'unknown',
      database,
      configured,
      timestamp: new Date().toISOString(),
    },
    {
      status: required ? 200 : 503,
      headers: {
        'Cache-Control': 'no-store, max-age=0',
      },
    }
  );
}
