# CareSim v6 product architecture

## Roles
**Learner** is the system role used for both Nursing Students and Practicing Nurses. Learner type is profile context, not authorization.

**Clinical Instructor** manages assigned courses, rosters, course assignments, training content and learner results within their course scope.

**Administrator** controls the platform: users, roles, courses, content, all attempts, reports, audit and governance.

## Academic model
Course → Learners → Assignment → Scenario Version → Attempt → Action Log → Result.

A “test” is a published scenario assigned to a course. This keeps grading attached to an immutable scenario version and preserves historical attempt validity.

## Security
- Neon Managed Better Auth owns login identities.
- Profiles own application roles.
- RLS scopes learner and instructor data.
- Admin-only Auth operations use protected Next.js server routes and Neon Auth admin APIs.
- Student score/state are never trusted from the browser.
- Avatar upload is authenticated server-side with RLS/service fallback.

## Reporting
Attempt summaries and action logs can be exported to Excel from the Admin Reports workspace.
