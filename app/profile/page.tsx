export const dynamic = 'force-dynamic';
import { AppShell } from '@/components/AppShell';import { ProfileEditor } from '@/components/ProfileEditor';import { createClient } from '@/lib/neon/server';import type { AppRole } from '@/lib/auth';
export default async function Profile(){const s=await createClient();const {data:{user}}=await s.auth.getUser();let role:AppRole='student';if(user){const {data}=await s.from('profiles').select('role').eq('id',user.id).maybeSingle();if(data?.role)role=data.role as AppRole}return <AppShell role={role}><ProfileEditor/></AppShell>}
