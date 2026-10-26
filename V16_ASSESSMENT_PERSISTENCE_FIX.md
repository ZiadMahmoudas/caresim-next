# CareSim V16 — Assessment persistence fix

This release fixes the case where an instructor typed assessment questions but the Builder later showed `0 instructor-authored questions` and learners received no post-simulation exam.

## What changed
- `Save draft` now verifies the exact number of questions and clinical actions persisted in Supabase.
- Publish is blocked unless the Builder save succeeds and is verified.
- Q&A has a dedicated **Save Q&A** button.
- Valid Builder changes autosave after a short debounce.
- The Builder displays both the local question/action count and the count confirmed in Supabase.
- `RUN_THIS_IN_SUPABASE_V16.sql` ensures the assessment tables and RPC functions exist even if an older V9 SQL run rolled back because of PostgreSQL error 42601.
- Correct answers remain server-side and are never returned by the learner assessment GET endpoint.

## Required database step
Run `RUN_THIS_IN_SUPABASE_V16.sql` once in Supabase SQL Editor.

Then open an Instructor scenario, add at least one complete question, choose the correct answer, and click **Save Q&A**. The UI should report something like:

`Saved successfully. Supabase confirmed 2 questions and 6 actions.`

Only after that should you publish the scenario.
