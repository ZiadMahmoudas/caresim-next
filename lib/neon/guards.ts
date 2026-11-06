import { redirect } from 'next/navigation';
import { createClient } from './server';
import { homeForRole, type AppRole } from '@/lib/auth';

export async function requireAppRole(allowed: AppRole[]) {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) redirect('/login');
  const { data: profile } = await db.from('profiles').select('role').eq('id', user.id).maybeSingle();
  const role = (profile?.role || 'student') as AppRole;
  if (!allowed.includes(role)) redirect(homeForRole(role));
  return { user, role, db };
}
