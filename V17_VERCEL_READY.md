# V17 — Vercel-ready production package

Changes:

- Added explicit Vercel project configuration.
- Added Node.js engine requirement compatible with current Next.js 16 requirements.
- Added `/api/health` production configuration check.
- Added production-safe security headers.
- Added Cloudinary to Next Image allow-list.
- Reworked `.env.example` for Local / Vercel production usage.
- Added complete `VERCEL_DEPLOY.md` deployment checklist.
- No `.env.local`, Supabase secret, Gemini key, or other private secrets are included in this ZIP.

No new Supabase SQL is required specifically for V17. Keep the latest database schema/migrations from the previous CareSim version.
