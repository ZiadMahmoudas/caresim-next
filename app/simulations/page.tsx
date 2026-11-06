export const dynamic = 'force-dynamic';
import { AppShell } from '@/components/AppShell';
import { SimulationsBrowser } from '@/components/simulations/SimulationsBrowser';
import { createClient } from '@/lib/neon/server';
export default async function Simulations(){const db=await createClient();const {data}=await db.rpc('list_published_simulations');return <AppShell><div className="page"><div className="page-head"><div><span className="eyebrow simple">Clinical Simulation</span><h1>Practice clinical reasoning.</h1><p>Every case below is authored and published by CareSim clinical staff.</p></div></div><SimulationsBrowser cases={(data||[]) as any}/></div></AppShell>}
