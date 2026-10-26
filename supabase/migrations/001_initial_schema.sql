create extension if not exists "pgcrypto";
create type public.user_role as enum ('student','instructor','admin');
create type public.scenario_type as enum ('skill','clinical_case');
create type public.attempt_status as enum ('in_progress','completed','abandoned');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id),
  role public.user_role not null default 'student',
  full_name text not null default '',
  avatar_url text,
  bio text,
  academic_level text,
  specialization text,
  personal_skills text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  instructor_id uuid references public.profiles(id),
  title text not null,
  code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.course_members (
  course_id uuid references public.courses(id) on delete cascade,
  student_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key(course_id, student_id)
);

create table public.scenarios (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id),
  type public.scenario_type not null,
  title text not null,
  slug text unique not null,
  description text,
  specialty text,
  current_version int not null default 1,
  is_published boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.scenario_versions (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references public.scenarios(id) on delete cascade,
  version int not null,
  config jsonb not null default '{}'::jsonb,
  rubric jsonb not null default '{}'::jsonb,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique(scenario_id, version)
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  scenario_id uuid not null references public.scenarios(id),
  assigned_by uuid not null references public.profiles(id),
  due_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  scenario_version_id uuid not null references public.scenario_versions(id),
  assignment_id uuid references public.assignments(id),
  status public.attempt_status not null default 'in_progress',
  current_state jsonb not null default '{}'::jsonb,
  score numeric(5,2) not null default 0,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.attempt_actions (
  id bigint generated always as identity primary key,
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  action_key text not null,
  payload jsonb not null default '{}'::jsonb,
  state_before jsonb not null,
  state_after jsonb not null,
  score_delta numeric(5,2) not null default 0,
  sequence_no int not null,
  created_at timestamptz not null default now(),
  unique(attempt_id, sequence_no)
);

create table public.attempt_results (
  attempt_id uuid primary key references public.attempts(id) on delete cascade,
  final_score numeric(5,2) not null,
  competency_scores jsonb not null default '{}'::jsonb,
  patient_outcome text,
  structured_debrief jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.skill_mastery (
  student_id uuid references public.profiles(id) on delete cascade,
  skill_key text not null,
  mastery numeric(5,2) not null default 0,
  attempts_count int not null default 0,
  best_score numeric(5,2) not null default 0,
  updated_at timestamptz not null default now(),
  primary key(student_id, skill_key)
);

create table public.ai_conversations (
  id bigint generated always as identity primary key,
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  role text not null check(role in ('student','patient','system')),
  message text not null,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.course_members enable row level security;
alter table public.scenarios enable row level security;
alter table public.scenario_versions enable row level security;
alter table public.assignments enable row level security;
alter table public.attempts enable row level security;
alter table public.attempt_actions enable row level security;
alter table public.attempt_results enable row level security;
alter table public.skill_mastery enable row level security;
alter table public.ai_conversations enable row level security;
alter table public.audit_logs enable row level security;

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid(); $$;

create policy "profile_self_read" on public.profiles for select using (id=auth.uid() or public.current_role() in ('instructor','admin'));
create policy "profile_self_update" on public.profiles for update using (id=auth.uid()) with check (id=auth.uid());
create policy "students_read_published_scenarios" on public.scenarios for select using (is_published=true or public.current_role() in ('instructor','admin'));
create policy "scenario_versions_read" on public.scenario_versions for select using (exists(select 1 from public.scenarios s where s.id=scenario_id and (s.is_published or public.current_role() in ('instructor','admin'))));
create policy "student_attempts_read" on public.attempts for select using (student_id=auth.uid() or public.current_role() in ('instructor','admin'));
create policy "student_attempts_insert" on public.attempts for insert with check (student_id=auth.uid());
create policy "student_attempt_actions_read" on public.attempt_actions for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.current_role() in ('instructor','admin'))));
create policy "student_results_read" on public.attempt_results for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.current_role() in ('instructor','admin'))));
create policy "student_mastery_read" on public.skill_mastery for select using (student_id=auth.uid() or public.current_role() in ('instructor','admin'));
create policy "ai_conversation_read" on public.ai_conversations for select using (exists(select 1 from public.attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.current_role() in ('instructor','admin'))));

-- Intentionally no INSERT/UPDATE policies for attempt_actions/results/score.
-- They should be written only by trusted server/Edge Function code using the secret/service role.
