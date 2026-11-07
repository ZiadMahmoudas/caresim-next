import { getAuth } from '@/lib/neon/auth-server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request, context: unknown) {
  const handlers: any = getAuth().handler();
  return handlers.GET(request, context);
}

export async function POST(request: Request, context: unknown) {
  const handlers: any = getAuth().handler();
  return handlers.POST(request, context);
}
