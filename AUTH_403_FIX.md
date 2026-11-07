# CareSim Neon Auth 403 fix

1. Neon -> Settings -> Better Auth -> Domains
2. Delete `https://caresim-iota.vercel.app/`
3. Add exactly `https://caresim-iota.vercel.app` (no trailing slash)
4. Keep Sign-in with Email enabled. Keep Sign-up with Email enabled if public learner registration is required.
5. This build uses a relative password-reset redirect: `/reset-password`.
6. Push/deploy this build, then test `/login` and `/forgot-password` in an incognito window.
