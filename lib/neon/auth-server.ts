import { createNeonAuth } from '@neondatabase/auth/next/server';

const baseUrl = process.env.NEON_AUTH_BASE_URL;
const cookieSecret = process.env.NEON_AUTH_COOKIE_SECRET;

if (!baseUrl) throw new Error('NEON_AUTH_BASE_URL is not configured.');
if (!cookieSecret || cookieSecret.length < 32) throw new Error('NEON_AUTH_COOKIE_SECRET must be at least 32 characters.');

export const auth = createNeonAuth({
  baseUrl,
  cookies: { secret: cookieSecret, sessionDataTtl: 300 },
});
