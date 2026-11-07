# CareSim Auth final fix

1. Neon -> Settings -> Better Auth -> Domains
2. Enter `https://caresim-iota.vercel.app`
3. CLICK **Add domain**. Do not leave it only in the input field.
4. Confirm it appears under **Your trusted domains**.
5. Keep Sign-up with Email and Sign-in with Email enabled.
6. Deploy this build. Registration now calls Neon Auth directly instead of `/api/auth/register`.
