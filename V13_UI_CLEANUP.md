# CareSim V13 — Simulation UI cleanup

- Removed the learner-facing **Saved live** label from the simulation header.
- Removed the learner-facing **Timeline** tab. Action logs are still stored and remain available to Instructor/Admin review screens.
- Kept the Case overview panel as the only learner-side case tab/heading.
- Clarified in Instructor Simulation Builder → Step 4 (Q&A) that the Clinical Instructor authors all post-simulation questions, correct answers, points, and explanations.
- Question grading remains server-side; correct answers are never sent to the learner UI.
- Preserves V12 state normalization, timer warnings, red critical-time pressure, and automatic submission on timeout.
