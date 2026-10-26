import { AppShell } from '@/components/AppShell';
import { ScenarioBuilder } from '@/components/ScenarioBuilder';
export default async function InstructorScenarioBuilder({params}:{params:Promise<{id:string}>}){const {id}=await params;return <AppShell role="instructor"><div className="page page-airy"><ScenarioBuilder scenarioId={id} role="instructor"/></div></AppShell>}
