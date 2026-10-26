# CareSim V12 — Simulation runtime + exam timer

## Fixed
- Prevents `state.messages is not iterable` by normalizing every simulation state returned from Supabase.
- Normalizes `messages`, `actions`, patient vitals and numeric fields before rendering.
- Adds an instructor-defined countdown timer using `estimatedMinutes`.
- Warning state begins during the final 20% of the allotted time.
- Critical state begins during the final 60 seconds with red visual pressure.
- At `00:00`, clinical actions and patient chat are locked and the attempt is submitted automatically.
- If a post-simulation assessment exists, unanswered questions are submitted empty and receive zero points before final grading.
- The final screen clearly indicates when an attempt ended because time expired.

## Database
If V11 previously failed with PostgreSQL error 42601, run:

`RUN_THIS_IN_SUPABASE_V11_FIXED.sql`

in Supabase SQL Editor once.

## Run
```bash
npm install
npm run dev
```
