export const dynamic = 'force-dynamic';
import { SimulationRunner } from '@/components/simulations/SimulationRunner';
import { createClient } from '@/lib/neon/server';
import { notFound } from 'next/navigation';
export default async function RespiratoryDistress(){const db=await createClient();const {data,error}=await db.rpc('get_simulation_brief',{p_slug:'respiratory-distress'});if(error||!data)notFound();return <SimulationRunner brief={data as any}/>}
