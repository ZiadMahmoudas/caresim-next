# Final deploy fix

This build fixes the Vercel/Next.js build-time Neon Auth failure by creating Neon Auth lazily at request time instead of throwing for missing environment variables during module evaluation.

Changed:
- `lib/neon/auth-server.ts`: lazy `getAuth()` factory.
- `lib/neon/server.ts`: resolves Auth only when a request needs a session/token.
- `app/api/auth/[...path]/route.ts`: builds GET/POST handlers at request time.
- `proxy.ts`: builds Neon Auth middleware at request time.
- Admin user APIs and registration route: use `getAuth()` inside handlers.
- Keeps prior TypeScript fix in `app/instructor/page.tsx`.
- Keeps prior Suspense fix for `/reset-password`.

Before production deploy, Vercel runtime still needs:
- `NEXT_PUBLIC_NEON_DATA_API_URL`
- `NEON_AUTH_BASE_URL`
- `NEON_AUTH_COOKIE_SECRET` (32+ chars)
- `DATABASE_URL`

Build should no longer fail simply because those variables are absent during local `next build` module evaluation. At runtime, routes that need Auth still validate them.
