# CareSim production deployment

## 1. GitHub

This package intentionally contains no real API keys.

On Windows, double-click:

`PUSH_TO_GITHUB.cmd`

It initializes a fresh Git history and pushes the clean project to:

`https://github.com/ZiadMahmoudas/caresim-next`

`.env.local`, `.next`, `node_modules`, logs and `.vercel` are ignored.

## 2. Vercel

1. Open Vercel Dashboard.
2. Add New -> Project.
3. Import `ZiadMahmoudas/caresim-next`.
4. Framework Preset: Next.js.
5. Keep the default Build Command (`next build`).
6. Add these Environment Variables for Production:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SECRET_KEY`
- `GEMINI_API_KEY`
- `GEMINI_MODEL=gemini-3.5-flash-lite`
- `NEXT_PUBLIC_EMAILJS_SERVICE_ID`
- `NEXT_PUBLIC_EMAILJS_TEMPLATE_ID`
- `NEXT_PUBLIC_EMAILJS_PUBLIC_KEY`

For the first deployment, `NEXT_PUBLIC_APP_URL` and `NEXT_PUBLIC_SITE_URL` may be omitted if the application code does not require them at build time. After Vercel assigns the production URL, set both to that exact HTTPS URL and redeploy.

## 3. Supabase Auth URL configuration

After Vercel gives you the production URL, in Supabase -> Authentication -> URL Configuration:

- Site URL: your final Vercel production URL
- Redirect URL: `https://YOUR-VERCEL-DOMAIN/**`
- Keep `http://localhost:3000/**` for local development if needed.

## 4. Production test

Check:

- `/api/health`
- Register / Login / Forgot password
- Learner / Instructor / Admin role routing
- Instructor Simulation Builder
- Q&A persistence
- Publish + learner simulation visibility
- Timer + timeout exit
- Course enrollment
- Attempts / Reports / Logs
- AI Patient / Ask CareSim
- Contact email

## Security

Do not commit `.env.local` or any real Supabase/Gemini secret. Rotate any key that was previously exposed in chat, Git history or screenshots before production.
