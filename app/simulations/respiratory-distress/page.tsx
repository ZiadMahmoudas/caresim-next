import { SimulationRunner } from '@/components/simulations/SimulationRunner';
import { createClient } from '@/lib/supabase/server';
import { notFound } from 'next/navigation';
export default async function RespiratoryDistress(){const supabase=await createClient();const {data,error}=await supabase.rpc('get_simulation_brief',{p_slug:'respiratory-distress'});if(error||!data)notFound();return <SimulationRunner brief={data as any}/>}
