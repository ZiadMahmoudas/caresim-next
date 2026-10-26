# CareSim V15 — Timeout Exit Fix

- At 00:00 the active attempt is saved and finalized server-side.
- Unanswered post-assessment items are submitted as empty answers so finalization can complete.
- After the server confirms the attempt is finished, the learner is redirected automatically to `/simulations?timedOut=1`.
- The learner no longer stays on a timeout result screen.
- A manual **Return to simulations** fallback link remains visible while timeout submission is running.
- Manual `End case & assessment` behavior is unchanged and still shows the normal result/debrief screen.
