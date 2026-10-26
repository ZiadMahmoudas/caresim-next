# CareSim V7 — Auth testing + branded modals

## What changed
- Removed the registration banner that explained the Learner system role.
- Removed all browser `prompt()`, `confirm()` and `alert()` usage from the app UI.
- Scenario edit/delete now uses CareSim modals.
- Course edit/delete now uses CareSim modals.
- User deletion now uses a CareSim confirmation modal.
- Registration now shows a friendly explanation when Supabase's built-in email sender hits its rate limit.

## Why `email rate limit exceeded` happens
Supabase's built-in Auth email provider is intended for low-volume testing and is limited. Public sign-up with **Confirm Email** enabled tries to send a confirmation email. When the provider limit is reached, sign-up returns an email rate limit error.

## Fastest local testing setup
In the Supabase Dashboard:
1. Open **Authentication**.
2. Open **Sign In / Providers**.
3. Open the **Email** provider.
4. Keep email/password sign-in enabled.
5. Temporarily turn **Confirm Email** OFF.
6. Save.

Now `/register` creates the learner and signs them in without sending a confirmation email.

Before production, turn Confirm Email back ON and configure a real SMTP provider.

## Create a specific account right now without email delivery
Because the CareSim Admin Console uses the Supabase Admin API, an administrator can create a confirmed account immediately:
1. Put `SUPABASE_SECRET_KEY` in `.env.local`.
2. Restart `npm run dev`.
3. Sign in as CareSim Admin.
4. Open **Admin → Users & Roles → Create account**.
5. Enter name, email, temporary password and choose Learner / Clinical Instructor / Administrator.
6. The new account can sign in immediately. No confirmation email is required for admin-created accounts.

Never expose `SUPABASE_SECRET_KEY` in browser code or prefix it with `NEXT_PUBLIC_`.
