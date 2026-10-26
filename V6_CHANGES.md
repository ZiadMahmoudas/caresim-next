# CareSim v6 changes

- Clear separation between Learner, Clinical Instructor and Administrator.
- Admin no longer uses learner navigation.
- Instructor no longer sees demo teaching metrics; dashboard is database-driven.
- Admin can create accounts (including Instructor), promote roles and delete users.
- Course CRUD, instructor assignment, learner enrolment and course assignments.
- Scenario / Skills Lab catalog creation, edit, publish/unpublish and safe delete.
- Attempts & action logs with real learner/scenario data.
- Excel `.xlsx` export with Attempts and Action Logs sheets.
- Admin audit log.
- Instructor-scoped learners and attempt data through RLS.
- Staff profile UI separated from learner competency profile.
- Avatar upload moved to authenticated server endpoint with service-key fallback.
- Storage bucket/policies rebuilt in migration 006.
- Visible provider name removed from the simulated-patient UI.
