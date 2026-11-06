# CareSim v19 — Neon Production Build

CareSim is a Next.js clinical simulation platform with learner, instructor and administrator workspaces.

This production build uses Neon for:
- PostgreSQL
- Managed Better Auth
- Data API
- Object Storage

It also integrates Gemini and EmailJS.

Start with `START_HERE.md`.

Useful commands:

```bash
npm install
npm run lint
npm run build
npm run secret
npm run check:env
```

Health endpoint:

`/api/health`

Supabase runtime files and old Supabase setup scripts are intentionally removed from this final package.
