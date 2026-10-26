# CareSim v6

Production-oriented nursing clinical simulation platform built with Next.js + Supabase.

Core workspaces:
- Learner: simulations, Skills Lab, verified progress and profile
- Instructor: courses, learners, assignments and attempt review
- Admin: users/roles, courses, clinical catalog, logs, reports and governance

AI is used only for the scenario-bounded simulated patient conversation. Clinical correctness, state changes and scoring remain rule-based/server-authoritative.

See `START_HERE.md` for setup and `supabase/migrations/006_admin_workspace.sql` when upgrading an existing CareSim database.


## V7 auth testing note
If public registration shows `email rate limit exceeded`, see `V7_AUTH_AND_MODAL_FIX.md`. For local testing you can temporarily disable **Confirm Email** in Supabase. Admin-created accounts do not depend on confirmation email delivery.


## V8 registration behavior
Public `/register` no longer sends a confirmation email. It creates a confirmed **Learner** account through the server-only `/api/auth/register` route, then signs the learner in immediately. This requires `SUPABASE_SECRET_KEY` in `.env.local`. Forgot Password remains Supabase email recovery; Contact remains EmailJS. See `V8_DIRECT_REGISTRATION.md`.
