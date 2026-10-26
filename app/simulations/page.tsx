import { AppShell } from '@/components/AppShell';
import { SimulationsBrowser } from '@/components/simulations/SimulationsBrowser';
import { createClient } from '@/lib/supabase/server';
export default async function Simulations(){const supabase=await createClient();const {data}=await supabase.rpc('list_published_simulations');return <AppShell><div className="page"><div className="page-head"><div><span className="eyebrow simple">Clinical Simulation</span><h1>Practice clinical reasoning.</h1><p>Every case below is authored and published by CareSim clinical staff.</p></div></div><SimulationsBrowser cases={(data||[]) as any}/></div></AppShell>}
