# Final production build fixes

This package combines the two fixes that were separately blocking deployment:

1. `app/instructor/page.tsx` — explicit type for the `courses.map()` callback so strict TypeScript does not fail with TS7006.
2. `app/reset-password/page.tsx` — wraps `ResetPasswordForm` in React `Suspense`, required by Next.js for the nested `useSearchParams()` usage during prerender.

Also verified:
- No Supabase runtime references remain in `app/`, `components/`, `lib/`, or `scripts/`.
- `.env.example` contains placeholders only; no real Gemini/GCP key.
- Neon health route reports Neon configuration, not Supabase configuration.

Before deployment, set the real environment variables only in Vercel / local `.env.local`, never in `.env.example`.
