# CareSim V9 — Instructor Builder, RAG Assistant & Assessment

## What changed

### Full Instructor Scenario Builder
Create a draft from **Instructor → Training Library** and CareSim opens the full builder:
1. Basics & learning objectives
2. Patient profile, vital signs and patient/case images
3. Clinical actions, prerequisites, consequences and points
4. Post-simulation assessment questions with correct answers, explanations and points
5. Knowledge / RAG notes
6. Clinical-vs-assessment scoring weights and passing score

Correct answers are stored in `scenario_questions` and are not sent to learners. The learner assessment API returns questions/options only; grading is performed server-side.

### CareSim Assistant (general chatbot)
The floating **Ask CareSim** assistant is separate from the AI Simulated Patient. It retrieves relevant CareSim knowledge from Supabase before asking Gemini to answer.

Knowledge can include:
- CareSim platform/role documentation
- published scenarios and specialties
- instructor-reviewed RAG notes
- the logged-in user's visible courses

Draft scenario knowledge remains staff-only. Published scenario knowledge becomes available to the public assistant.

### AI Simulated Patient
The patient AI now loads the instructor-authored patient profile and hidden AI boundary from the active scenario on the server. It no longer trusts patient facts sent by the browser.

### Final learner score
If a scenario has assessment questions:
`Final = Clinical score × clinical weight + Assessment score × assessment weight`

If there are no questions, clinical simulation score is 100% of the final score.

Instructor/Admin attempt review now shows action timeline plus assessment answers, correct answers and awarded points. Excel export contains a third sheet: `Assessment Answers`.

## Required Supabase step
For an existing V8 database, run exactly:

`RUN_THIS_IN_SUPABASE_V9.sql`

Then restart Next.js.

`SUPABASE_SECRET_KEY` is required server-side for scenario image uploads, direct registration and AI-patient hidden scenario context.
