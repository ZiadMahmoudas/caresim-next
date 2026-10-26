# CareSim — Vercel deployment

## 1. Before deploying

Run locally:

```bash
npm install
npm run build
```

Make sure the latest CareSim Supabase migrations have already been applied to the production Supabase project.

## 2. Push to GitHub

Create a private repository and push the project. Do not commit `.env.local`.

## 3. Import into Vercel

Vercel → Add New → Project → Import the GitHub repository.

Framework preset: **Next.js**. Leave Build Command and Output Directory on their automatic Next.js defaults.

## 4. Environment variables

Add these in **Vercel → Project → Settings → Environment Variables**.

Required:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY
GEMINI_API_KEY
GEMINI_MODEL=gemini-3.5-flash-lite
NEXT_PUBLIC_APP_URL=https://YOUR-PRODUCTION-DOMAIN
NEXT_PUBLIC_SITE_URL=https://YOUR-PRODUCTION-DOMAIN
```

Contact form:

```text
NEXT_PUBLIC_EMAILJS_SERVICE_ID
NEXT_PUBLIC_EMAILJS_TEMPLATE_ID
NEXT_PUBLIC_EMAILJS_PUBLIC_KEY
```

Use Production scope for the live deployment. Add the same safe/test values to Preview only if you want preview deployments to be fully functional.

After changing environment variables, redeploy.

## 5. Supabase Auth URLs

Supabase → Authentication → URL Configuration.

Set **Site URL** to the final production URL, for example:

```text
https://caresim.example.com
```

Add redirects:

```text
http://localhost:3000/**
https://caresim.example.com/**
```

If you use Vercel preview deployments, also allow your Vercel preview pattern as documented by Supabase, for example:

```text
https://*-YOUR-VERCEL-TEAM-SLUG.vercel.app/**
```

The exact production domain is preferred for production redirects.

## 6. Forgot Password email

Public registration does not send confirmation email in CareSim. Forgot Password still uses Supabase Auth.

For production password recovery, configure Custom SMTP in Supabase so you are not dependent on the limited default test mailer.

## 7. Deploy and verify

After deployment open:

```text
https://YOUR-DOMAIN/api/health
```

Healthy production output should include:

```json
{
  "ok": true,
  "database": "ok"
}
```

The endpoint only returns configuration booleans. It never returns your secret values.

Then test this flow:

1. `/register` — create a Learner without email confirmation.
2. `/login` — sign in.
3. Profile avatar upload.
4. Instructor login and Simulation Builder.
5. Publish a scenario.
6. Add a Learner to a Course and assign the scenario.
7. Learner → My Courses → run the simulation.
8. Assessment + score + attempt result.
9. Admin → Activity & Audit / Reports.
10. Forgot Password email.
11. Contact form EmailJS delivery.
12. CareSim Assistant / AI Patient.

## 8. Secrets

Never put these into a `NEXT_PUBLIC_` variable:

```text
SUPABASE_SECRET_KEY
GEMINI_API_KEY
```

Do not commit `.env.local`.

## 9. Production domain

After adding a custom domain in Vercel, update both:

```text
NEXT_PUBLIC_APP_URL
NEXT_PUBLIC_SITE_URL
```

and update Supabase Site URL / Redirect URLs, then redeploy.


## Next.js 16 build note
V18 removes runtime `useSearchParams()` from `/instructor/scenarios`, `/admin/scenarios`, and `/login`. Query params are read by Server Components and passed as props, avoiding the production prerender error `missing-suspense-with-csr-bailout`.
