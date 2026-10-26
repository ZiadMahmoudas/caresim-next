import { AppShell } from '@/components/AppShell';
import { FullActivityLog } from '@/components/FullActivityLog';
export default function AdminAudit(){return <AppShell role="admin"><div className="page page-airy"><div className="page-head compact-head"><div><span className="eyebrow simple">Governance & activity</span><h1>Complete platform log.</h1><p>See learner sessions, simulation actions, logins/logouts and every administrative change in one traceable timeline.</p></div></div><FullActivityLog/></div></AppShell>}
