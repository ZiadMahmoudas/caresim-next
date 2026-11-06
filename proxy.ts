import { auth } from '@/lib/neon/auth-server';

export default auth.middleware({ loginUrl: '/login' });

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
