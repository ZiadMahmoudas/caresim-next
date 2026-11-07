import { createNeonAuth } from '@neondatabase/auth/next/server';

/**
 * Create Neon Auth lazily.
 *
 * Next.js evaluates route modules while running `next build`. Reading required
 * environment variables and throwing at module scope makes the build fail even
 * before a request is handled. This factory defers validation/creation until
 * Auth is actually used at request time.
 */
let authInstance: ReturnType<typeof createNeonAuth> | null = null;

export function getAuth() {
  if (authInstance) return authInstance;

  const baseUrl = process.env.NEON_AUTH_BASE_URL;
  const cookieSecret = process.env.NEON_AUTH_COOKIE_SECRET;

  if (!baseUrl) {
    throw new Error('NEON_AUTH_BASE_URL is not configured. Add it to the runtime environment.');
  }

  if (!cookieSecret || cookieSecret.length < 32) {
    throw new Error('NEON_AUTH_COOKIE_SECRET must be at least 32 characters.');
  }

  authInstance = createNeonAuth({
    baseUrl,
    cookies: {
      secret: cookieSecret,
      sessionDataTtl: 300,
    },
  });

  return authInstance;
}
