import { NextResponse } from 'next/server';
import { adminSql } from '@/lib/neon/sql';
import { storageConfigured } from '@/lib/neon/storage';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  const configured = {
    dataApi: Boolean(process.env.NEXT_PUBLIC_NEON_DATA_API_URL),
    auth: Boolean(process.env.NEON_AUTH_BASE_URL),
    authCookieSecret: Boolean(process.env.NEON_AUTH_COOKIE_SECRET && process.env.NEON_AUTH_COOKIE_SECRET.length >= 32),
    databaseUrl: Boolean(process.env.DATABASE_URL),
    storage: storageConfigured(),
    gemini: Boolean(process.env.GEMINI_API_KEY),
    emailjs: Boolean(
      process.env.NEXT_PUBLIC_EMAILJS_SERVICE_ID &&
      process.env.NEXT_PUBLIC_EMAILJS_TEMPLATE_ID &&
      process.env.NEXT_PUBLIC_EMAILJS_PUBLIC_KEY
    ),
    siteUrl: Boolean(
      process.env.NEXT_PUBLIC_SITE_URL ||
      process.env.NEXT_PUBLIC_APP_URL ||
      process.env.VERCEL_PROJECT_PRODUCTION_URL ||
      process.env.VERCEL_URL
    ),
  };

  let database: 'ok' | 'error' | 'not-configured' = 'not-configured';
  if (configured.databaseUrl) {
    try {
      const sql = adminSql();
      await sql`select 1 from public.profiles limit 1`;
      database = 'ok';
    } catch {
      database = 'error';
    }
  }

  const coreReady =
    configured.dataApi &&
    configured.auth &&
    configured.authCookieSecret &&
    configured.databaseUrl &&
    configured.siteUrl &&
    database === 'ok';

  const productionReady =
    coreReady &&
    configured.storage &&
    configured.gemini &&
    configured.emailjs;

  return NextResponse.json(
    {
      ok: coreReady,
      productionReady,
      service: 'CareSim',
      backend: 'Neon',
      environment: process.env.VERCEL_ENV || process.env.NODE_ENV || 'unknown',
      database,
      configured,
      timestamp: new Date().toISOString(),
    },
    {
      status: coreReady ? 200 : 503,
      headers: { 'Cache-Control': 'no-store, max-age=0' },
    }
  );
}
