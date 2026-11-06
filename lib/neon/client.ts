'use client';

import { createAuthClient } from '@neondatabase/auth/next';
import { NeonPostgrestClient } from '@neondatabase/postgrest-js';

let singleton: any;
const neonAuth: any = createAuthClient();

async function jwtToken(): Promise<string | null> {
  try {
    const result: any = await neonAuth.getJWTToken?.();
    if (typeof result === 'string') return result;
    return result?.data?.token ?? result?.token ?? result?.data ?? null;
  } catch {
    return null;
  }
}

// Compatibility wrapper preserving CareSim's existing auth call shape.
const authCompat = {
  signInWithPassword: async ({ email, password }: { email: string; password: string }) => {
    const result: any = await neonAuth.signIn.email({ email, password });
    if (result?.error) return { data: { user: null, session: null }, error: result.error };

    const sessionResult: any = await neonAuth.getSession();
    return {
      data: {
        user: sessionResult?.data?.user ?? result?.data?.user ?? null,
        session: sessionResult?.data?.session ?? null,
      },
      error: sessionResult?.error ?? null,
    };
  },
  signOut: async () => neonAuth.signOut(),
  getUser: async () => {
    const result: any = await neonAuth.getSession();
    return { data: { user: result?.data?.user ?? null }, error: result?.error ?? null };
  },
  getSession: async () => {
    const result: any = await neonAuth.getSession();
    return { data: { session: result?.data ?? null }, error: result?.error ?? null };
  },
};

export function createClient() {
  if (singleton) return singleton;

  const dataApiUrl = process.env.NEXT_PUBLIC_NEON_DATA_API_URL;
  if (!dataApiUrl) throw new Error('NEXT_PUBLIC_NEON_DATA_API_URL is not configured.');

  const authFetch: typeof fetch = async (input, init) => {
    const token = await jwtToken();
    const headers = new Headers(init?.headers);
    if (token) headers.set('Authorization', `Bearer ${token}`);
    return fetch(input, { ...init, headers });
  };

  const db: any = new NeonPostgrestClient({
    dataApiUrl,
    options: { global: { fetch: authFetch }, db: { schema: 'public' } },
  });

  db.auth = authCompat;
  singleton = db;
  return singleton;
}
