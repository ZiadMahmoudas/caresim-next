# CareSim V8 — Direct learner registration

## Final email flow

- Register: **NO email**. A server route creates a confirmed learner account directly with Supabase Admin API, then the browser signs the user in.
- Login: **NO email**.
- Admin-created users: **NO email** unless you choose to build invitations later.
- Forgot Password: **YES**. It still uses `supabase.auth.resetPasswordForEmail()` because Supabase must generate the secure recovery token.
- Contact: **YES**. It remains EmailJS.

## Required environment variable

Direct registration now requires this server-only value:

```env
SUPABASE_SECRET_KEY=your_supabase_secret_key
```

Never prefix it with `NEXT_PUBLIC_` and never expose it in the browser.

## Important behavior

`/register` calls `/api/auth/register` instead of `supabase.auth.signUp()`.
The API route hardcodes every public account to role `student` (Learner). The visitor can only choose learner type: nursing student or practicing nurse.

This means the Supabase **Confirm Email** switch no longer controls public CareSim registration. Registration does not request a confirmation email at all.

## Forgot Password

Forgot Password is intentionally unchanged and email-based. For production delivery, configure a custom SMTP provider in Supabase Auth so password recovery is not dependent on the default test mailer limits.
