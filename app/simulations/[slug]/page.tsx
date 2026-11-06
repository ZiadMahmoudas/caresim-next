export const dynamic = 'force-dynamic';
import { notFound } from 'next/navigation';
import { SimulationRunner } from '@/components/simulations/SimulationRunner';
import { createClient } from '@/lib/neon/server';
export default async function SimulationPage({params}:{params:Promise<{slug:string}>}){const {slug}=await params;const db=await createClient();const {data,error}=await db.rpc('get_simulation_brief',{p_slug:slug});if(error||!data)notFound();return <SimulationRunner brief={data as any}/>}
