# CareSim v19 — FINAL Neon / Vercel setup

This folder is the production-clean CareSim build. Runtime Supabase code has been removed.

Backend:
- Neon Postgres
- Neon Managed Better Auth
- Neon Data API
- Neon Object Storage (`avatars`, `scenario-assets`)
- Gemini API
- EmailJS
- Vercel / Next.js

## 1. Neon project requirements

Use **one Neon project / one production branch / one `neondb` database** for Auth, Data API and CareSim tables.

For full file-upload support, create the Neon project in a region that supports Object Storage. Frankfurt (`aws-eu-central-1`) is the natural Europe choice.

In Neon:
1. Enable Managed Better Auth for `neondb`.
2. Keep Email Sign-up ON (CareSim has public learner registration).
3. Keep Email Sign-in ON.
4. Add `https://caresim-iota.vercel.app` to Better Auth trusted domains.
5. Enable Data API for `neondb` using Neon Auth.

## 2. Database schema

For a fresh CareSim database, run once in Neon SQL Editor:

`neon/SETUP_CARESIM_NEON.sql`

If the CareSim tables already exist, use:

`neon/PRODUCTION_REPAIR_AND_ADMIN.sql`

Replace `YOUR_ADMIN_EMAIL` before running the repair/admin script.

## 3. Local Neon link + storage

Requires Node >= 20.19.

```powershell
npm install
npm i -g neon@latest
neon auth
neon link
neon branches list
neon deploy
neon env pull --file .env.local
```

Before `neon deploy`, confirm `neon branches list` shows the intended CareSim production branch.

`neon.ts` provisions:
- Auth
- Data API
- public-read `avatars`
- public-read `scenario-assets`

If `neon deploy` says Object Storage is unavailable in the region, do not deploy that project as the final CareSim backend. Create/use a supported-region Neon project and relink.

## 4. Environment

Copy `.env.example` to `.env.local`, then fill real values.

Generate the cookie secret:

```powershell
npm run secret
```

`DATABASE_URL` must be the **Pooled** connection from Neon -> Connect.

Never commit:
- `DATABASE_URL`
- `NEON_AUTH_COOKIE_SECRET`
- `AWS_SECRET_ACCESS_KEY`
- `GEMINI_API_KEY`

Run:

```powershell
npm run check:env
```

before production deploy.

## 5. First admin

Create the account normally from `/register`, then run:

`neon/RUN_NOW_FIX_AND_MAKE_ADMIN.sql`

after replacing `YOUR_ADMIN_EMAIL`.

Both values must verify as `admin`:
- `public.profiles.role`
- `neon_auth.user.role`

Sign out and back in once after promotion.

## 6. Vercel

Add all values from `VERCEL_ENV_PRODUCTION.txt` under:
Vercel -> Project -> Settings -> Environment Variables -> Production.

Then deploy.

Production URL:
`https://caresim-iota.vercel.app`

## 7. Final smoke test

Open:

`https://caresim-iota.vercel.app/api/health`

You want:
- `ok: true`
- `productionReady: true`
- `database: "ok"`

Then test:
1. `/register`
2. `/login`
3. `/forgot-password`
4. `/dashboard`
5. `/instructor`
6. `/admin`
7. avatar upload
8. scenario image upload
9. AI Patient / Ask CareSim
10. contact form
11. logout/login again

## Security

Any Gemini key, cookie secret, database password, or storage secret previously pasted into chat/screenshots should be rotated before the client receives production access.
