# CareSim V18 — Next.js 16 production build fix

This release removes client-side `useSearchParams()` usage from the production-critical pages that caused prerender failures in Next.js 16.

## Fixed
- `/instructor/scenarios` no longer fails `next build` with `missing-suspense-with-csr-bailout`.
- `/admin/scenarios` uses the same server-side search param pattern.
- `/login?next=...` keeps redirect behavior without `useSearchParams()`.
- Search params are read in Server Components and passed as plain props to Client Components.

## Verify
```bash
npm install
npm run build
```

Then push to GitHub and import the repository into Vercel.
