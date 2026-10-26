-- ONE-TIME bootstrap after you register your own account through /register.
-- Replace the email below, run in Supabase SQL Editor, then sign out and sign in again.
update public.profiles
set role='admin',updated_at=now()
where id=(select id from auth.users where email='YOUR_ADMIN_EMAIL@example.com');

select id,email,full_name,role from public.profiles where email='YOUR_ADMIN_EMAIL@example.com';
