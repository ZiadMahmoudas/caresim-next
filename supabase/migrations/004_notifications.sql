-- Run this migration if your Supabase project already has CareSim v3 installed.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'info' check(kind in ('info','success','assignment','achievement')),
  href text,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
drop policy if exists notification_self_read on public.notifications;
create policy notification_self_read on public.notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists notification_self_update on public.notifications;
create policy notification_self_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select on public.notifications to authenticated;
grant update(is_read,read_at) on public.notifications to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name,learner_type,role)
  values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''),case when new.raw_user_meta_data->>'learner_type'='nurse' then 'nurse' else 'student' end,'student')
  on conflict(id) do update set email=excluded.email;
  insert into public.notifications(user_id,title,body,kind,href)
  select new.id,'Welcome to CareSim','Your learner profile is ready. Start with a clinical simulation or complete your profile.','success','/dashboard'
  where not exists(select 1 from public.notifications where user_id=new.id and title='Welcome to CareSim');
  return new;
end;$$;

create or replace function public.notify_attempt_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_title text;
begin
  select a.student_id,s.title into v_user,v_title
  from public.attempts a join public.scenario_versions sv on sv.id=a.scenario_version_id join public.scenarios s on s.id=sv.scenario_id
  where a.id=new.attempt_id;
  if v_user is not null then
    insert into public.notifications(user_id,title,body,kind,href)
    values(v_user,'Simulation completed',coalesce(v_title,'Clinical simulation')||' completed with a score of '||round(new.final_score)::text||'%.','achievement','/progress');
  end if;
  return new;
end;$$;
drop trigger if exists on_attempt_result_notification on public.attempt_results;
create trigger on_attempt_result_notification after insert on public.attempt_results for each row execute function public.notify_attempt_result();
