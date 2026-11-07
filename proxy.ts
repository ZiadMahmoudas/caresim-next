import type { NextFetchEvent, NextRequest } from 'next/server';
import { getAuth } from '@/lib/neon/auth-server';

export default function proxy(request: NextRequest, event: NextFetchEvent) {
  const middleware: any = getAuth().middleware({ loginUrl: '/login' });
  return middleware(request, event);
}

export const config = {
  matcher: [
    '/dashboard/:path*',
    '/courses/:path*',
    '/simulations/:path*',
    '/skills/:path*',
    '/progress/:path*',
    '/profile/:path*',
    '/instructor/:path*',
    '/admin/:path*',
  ],
};
