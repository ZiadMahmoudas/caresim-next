-- CareSim diagnostics: run in Supabase SQL Editor when auth/profile/upload setup is unclear.

-- 1) Authentication users created through /register
select id,email,email_confirmed_at,created_at from auth.users order by created_at desc limit 20;

-- 2) Matching CareSim profiles and roles
select id,email,full_name,role,learner_type,created_at from public.profiles order by created_at desc limit 20;

-- 3) Avatar Storage bucket
select id,name,public,file_size_limit,allowed_mime_types from storage.buckets where id='avatars';

-- 4) Notifications table
select count(*) as notifications_count from public.notifications;

-- 5) Published scenarios
select title,slug,type,is_published,current_version from public.scenarios order by created_at desc;

-- 6) Published Skills Lab modules (V5)
select id,title,slug,specialty,is_published,current_version from public.scenarios where type='skill' order by created_at desc;

-- 7) Current learner mastery rows
select student_id,skill_key,mastery,attempts_count,best_score,updated_at from public.skill_mastery order by updated_at desc limit 50;

-- 8) Avatar policies
select policyname,cmd,roles,qual,with_check from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'avatar_%' order by policyname;
