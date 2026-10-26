import { AppShell } from '@/components/AppShell';
import { ScenarioBuilder } from '@/components/ScenarioBuilder';
export default async function AdminScenarioBuilder({params}:{params:Promise<{id:string}>}){const {id}=await params;return <AppShell role="admin"><div className="page page-airy"><ScenarioBuilder scenarioId={id} role="admin"/></div></AppShell>}
