import { AppShell } from '@/components/AppShell';
import { AdminUsersPanel } from '@/components/AdminUsersPanel';
export default function AdminUsers(){return <AppShell role="admin"><div className="page page-airy"><div className="page-head compact-head"><div><span className="eyebrow simple">People & access</span><h1>Users and roles.</h1><p>Learners register publicly. Administrators decide who becomes an instructor or administrator.</p></div></div><AdminUsersPanel/></div></AppShell>}
