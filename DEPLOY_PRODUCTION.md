# CareSim production deployment — Vercel

## Before uploading

1. `npm install`
2. `npm run lint`
3. `npm run build`
4. `npm run check:env` (with the production env loaded)
5. Confirm Neon `production` is the intended CareSim project, not an old BSS/London link.

## Vercel environment variables

Use `VERCEL_ENV_PRODUCTION.txt` as the checklist.

Required for full production:
- NEXT_PUBLIC_APP_URL
- NEXT_PUBLIC_SITE_URL
- NEXT_PUBLIC_NEON_DATA_API_URL
- NEON_AUTH_BASE_URL
- NEON_AUTH_COOKIE_SECRET
- DATABASE_URL
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- AWS_ENDPOINT_URL_S3
- AWS_REGION
- GEMINI_API_KEY
- GEMINI_MODEL
- NEXT_PUBLIC_EMAILJS_SERVICE_ID
- NEXT_PUBLIC_EMAILJS_TEMPLATE_ID
- NEXT_PUBLIC_EMAILJS_PUBLIC_KEY

After changing env values, redeploy.

## Neon Auth

Add the exact Vercel production origin to Better Auth trusted domains:

`https://caresim-iota.vercel.app`

Keep email sign-up and sign-in enabled.

## Verification

Visit:

`/api/health`

For a complete production setup:
- `ok` = true
- `productionReady` = true
- `database` = ok

Then smoke-test learner, instructor and admin flows.
