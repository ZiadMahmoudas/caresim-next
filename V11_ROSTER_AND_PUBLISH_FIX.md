# CareSim V11 — learner roster + published simulation fix

This patch fixes two inconsistencies seen in V10:

1. A course could show `1 learner` while Instructor → My Learners showed `0`.
2. Instructor could see a scenario as Published while Learner → Simulations showed `0 published cases`.

## Why it happened

The instructor roster and course manager were assembling data from several browser-side Supabase queries (`profiles`, `course_members`, `attempts`, `courses`). RLS or a missing profile result could make the roster empty even while the membership row existed.

Published simulations also depended on an exact `scenarios.current_version = scenario_versions.version` join. An older publish flow could leave the pointer stale even though the scenario itself was marked Published.

## V11 behavior

- `staff_people_directory()` securely returns all learner accounts available to staff, including both Nursing Students and Practicing Nurses.
- `staff_instructor_roster()` securely returns only learners enrolled in the instructor's own courses, with course names and real performance metrics.
- Existing profiles with no organization are backfilled into the CareSim Academy organization.
- Published scenario discovery repairs stale version pointers and falls back safely to the latest saved builder version.
- `get_simulation_brief()` and `start_simulation()` use the same robust version selection.

## Upgrade

If V10 is already installed, run only:

`RUN_THIS_IN_SUPABASE_V11.sql`

Then restart Next.js and sign out/sign back in as Instructor and Learner.
