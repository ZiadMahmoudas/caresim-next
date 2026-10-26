# CareSim V10 — Instructor flow, learner courses, full logs, logout

## What changed

### Instructor
- Sidebar now exposes **Simulation Builder** directly.
- Instructor Hub includes a primary **Create simulation** action.
- The authoring page explains the 6-step flow: case → patient → clinical actions → Q&A → knowledge/RAG → publish.
- Published simulations/skills can be assigned to the instructor's courses.

### Learner
- New **My Courses** page in the sidebar.
- A learner sees only courses in which they are enrolled.
- Each course shows its instructor, assignments, due dates, and direct Start/Practice actions.
- Dashboard shows the real enrolled course count.
- Skills Lab now shows the learner's self-added personal skills separately from official CareSim training modules.
- Published Skills Lab modules have a working Practice action using the same simulation engine.

### Admin logs
- **Activity & Audit** combines session/user activity with administrative audit events.
- V10 records registration, login, logout, simulation start, simulation completion and every clinical action.
- Existing audit events continue to cover role/course/scenario/assignment administration.

### Logout
- Logout is visible in the sidebar.
- Clicking the top-right avatar opens an account menu with My Profile + Logout.
- Logout always returns to `/login`.

## Database update
If V9 is already installed, run only:

`RUN_THIS_IN_SUPABASE_V10.sql`

This creates the full activity trail, adds simulation activity triggers, protects assignments from unpublished scenarios, and notifies learners when enrolled/assigned.

## Expected teaching flow
1. Admin creates or promotes a Clinical Instructor.
2. Instructor → Simulation Builder → creates and publishes a clinical case or Skills Lab procedure.
3. Instructor → My Courses → creates a course and enrols learners.
4. Instructor assigns a published simulation to the course.
5. Learner → My Courses → sees the course and assignment immediately.
6. Learner completes the training.
7. Instructor reviews Attempts & Results.
8. Admin can see the complete platform trace in Activity & Audit.
