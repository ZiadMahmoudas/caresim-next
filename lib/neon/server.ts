import { NeonPostgrestClient } from '@neondatabase/postgrest-js';
import { getAuth } from './auth-server';

async function jwt(): Promise<string | null> {
  try {
    const auth = getAuth();
    const result: any = await (auth as any).token();
    return result?.data?.token ?? result?.token ?? null;
  } catch {
    return null;
  }
}

export async function createClient() {
  const dataApiUrl = process.env.NEXT_PUBLIC_NEON_DATA_API_URL;
  if (!dataApiUrl) throw new Error('NEXT_PUBLIC_NEON_DATA_API_URL is not configured.');

  const authFetch: typeof fetch = async (input, init) => {
    const token = await jwt();
    const headers = new Headers(init?.headers);
    if (token) headers.set('Authorization', `Bearer ${token}`);
    return fetch(input, { ...init, headers, cache: 'no-store' });
  };

  const db: any = new NeonPostgrestClient({
    dataApiUrl,
    options: { global: { fetch: authFetch }, db: { schema: 'public' } },
  });

  // Compatibility layer so existing server code can keep db.auth.getUser().
  db.auth = {
    getUser: async () => {
      try {
        const auth = getAuth();
        const result: any = await auth.getSession();
        return {
          data: { user: result?.data?.user ?? result?.data?.session?.user ?? null },
          error: result?.error ?? null,
        };
      } catch (error) {
        return {
          data: { user: null },
          error,
        };
      }
    },
  };

  return db;
}
