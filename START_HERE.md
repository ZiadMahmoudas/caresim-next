# CareSim V15

Current build: V15 Timeout Exit Fix.

When a timed simulation reaches 00:00, CareSim saves/finalizes the attempt and automatically returns the learner to the simulations catalog. Manual completion still shows the normal result/debrief.

# CareSim v6 — Start Here

## 1. Install and run
```bash
npm install
npm run dev
```

## 2. Environment
Create `.env.local` from `.env.example` and set:

```env
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=...
SUPABASE_SECRET_KEY=...
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-3.5-flash-lite
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

`SUPABASE_SECRET_KEY` stays server-side. It is required for Admin Console account creation/deletion and provides a server-side fallback for avatar upload.

## 3. Existing Supabase project (you already ran earlier CareSim SQL)
Run only this file in Supabase SQL Editor:

```text
supabase/migrations/006_admin_workspace.sql
```

It adds/rebuilds:
- avatar Storage bucket policies
- courses / rosters / assignments permissions
- staff course management RPCs
- scenario CRUD RPCs
- instructor-scoped attempt access
- admin audit access

Then sign out and back in once.

## 4. Fresh Supabase project
Run:

```text
supabase/SETUP_FRESH_PROJECT.sql
```

## 5. Roles — important
There are two separate concepts:

### System role
- **Learner** (`student` in the DB): trains in simulations.
- **Clinical Instructor** (`instructor`): manages assigned courses and their learners.
- **Administrator** (`admin`): platform-wide operations.

### Learner type
Only applies to a Learner account:
- Nursing student
- Practicing nurse / continuing education

Public `/register` always creates a **Learner**. The user chooses only the learner type. Admin creates/promotes Instructors from **Admin → Users & Roles**.

## 6. Create an Instructor for testing
Login as Admin → **Users & Roles → Create account**.
Choose:
- System role: `Clinical Instructor`
- email + temporary password

That account can immediately log in. It will automatically open `/instructor` and see Instructor navigation instead of learner navigation.

Alternative: change an existing Learner role to `Instructor`, then sign that user out and sign in again.

## 7. Admin workspace
The Admin sidebar is separate from learner training:
- Admin Dashboard
- Users & Roles
- Courses
- Scenarios & Tests
- Attempts & Logs
- Reports
- Audit Log

Admin can:
- create users / instructors
- change roles
- delete users (requires `SUPABASE_SECRET_KEY`)
- create/edit/delete courses
- assign instructors
- enrol/remove learners
- create/remove assignments
- create/edit/publish/unpublish scenarios
- delete unused scenarios
- inspect attempts and action logs
- export Excel workbook (Attempts + Action Logs)
- inspect administrative audit activity

## 8. Instructor workspace
Instructor sees only teaching tools:
- Instructor Hub
- My Courses
- My Learners
- Training Library
- Attempts & Results

After migration 006, learner attempt data is scoped to learners enrolled in that instructor's courses.

## 9. What is a “test” in CareSim?
A published clinical scenario / Skills Lab procedure becomes an assessment when it is assigned to a course. The learner attempt stores:
- score
- result/outcome
- action sequence
- timing
- clinical logs

Admin/Instructor reviews those records from Attempts & Logs.

## 10. Avatar upload / Storage
Migration 006 recreates the `avatars` bucket configuration and policies.
The app now uploads through `/api/profile/avatar`.

If `SUPABASE_SECRET_KEY` is configured, the server can upload after authenticating the current user even if a browser-side Storage policy is misconfigured.

Allowed:
- JPG
- PNG
- WebP
- max 5 MB

If upload still fails, verify `.env.local` contains `SUPABASE_SECRET_KEY` and restart `npm run dev`.

## 11. Excel reports
Admin → Reports → **Export Excel** produces an `.xlsx` file with:
- Attempts sheet
- Action Logs sheet

Instructors can export only the attempts visible to their scoped account.


## V7 auth testing note
If public registration shows `email rate limit exceeded`, see `V7_AUTH_AND_MODAL_FIX.md`. For local testing you can temporarily disable **Confirm Email** in Supabase. Admin-created accounts do not depend on confirmation email delivery.


## V8 registration behavior
Public `/register` no longer sends a confirmation email. It creates a confirmed **Learner** account through the server-only `/api/auth/register` route, then signs the learner in immediately. This requires `SUPABASE_SECRET_KEY` in `.env.local`. Forgot Password remains Supabase email recovery; Contact remains EmailJS. See `V8_DIRECT_REGISTRATION.md`.

## V9 upgrade — Instructor Builder + RAG
If this project already has V8 installed, run `RUN_THIS_IN_SUPABASE_V9.sql` once in Supabase SQL Editor.

Then:
1. Sign in as an Instructor.
2. Open `Instructor → Training Library`.
3. Create a scenario draft; CareSim opens the full builder.
4. Add patient image/facts, clinical actions/rules, assessment questions + correct answers, RAG notes and scoring weights.
5. Save and publish.
6. Sign in as a Learner and open Simulations. Only published database scenarios appear.
7. The learner finishes the clinical actions, answers the post-simulation assessment, and receives one combined server-verified score.
8. Instructor → Attempts & Results shows the action timeline and assessment answer review.

The floating `Ask CareSim` button is the general CareSim Assistant. The AI inside a simulation is a separate Scenario-Bounded Simulated Patient.

---

## V10 update
If your database already has V9 installed, run `RUN_THIS_IN_SUPABASE_V10.sql` once in Supabase SQL Editor.

After V10:
- instructors author simulations from **Simulation Builder**;
- learners see enrolments and assignments under **My Courses**;
- learner personal skills appear separately in Skills Lab;
- admins see full user/session/simulation activity under **Activity & Audit**;
- logout is visible in both the sidebar and the top-right account menu.

Important: instructors can only assign **published** scenarios. If a learner cannot see an assignment, verify that the scenario is published and the learner is enrolled in that course.

## V11 upgrade — learner roster / published simulations

If your database already has V10 installed, run `RUN_THIS_IN_SUPABASE_V11.sql` once in Supabase SQL Editor.

V11 fixes:
- Nursing Student + Practicing Nurse discovery for instructors.
- My Learners showing enrolled learners reliably.
- Published simulations appearing to learners even if an older version pointer became stale.

After running the SQL, restart the app and sign out/sign back in for a clean session.
