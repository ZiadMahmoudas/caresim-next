const vercelUrl = process.env.VERCEL_PROJECT_PRODUCTION_URL
  ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
  : undefined;

export const siteUrl = (process.env.NEXT_PUBLIC_SITE_URL || vercelUrl || 'http://localhost:3000').replace(/\/$/, '');

export const seo = {
  name: 'CareSim Clinical',
  shortName: 'CareSim',
  title: 'CareSim Clinical — AI Nursing & Clinical Simulation Platform',
  description:
    'CareSim is an interactive nursing education platform for clinical simulation, nursing skills practice, patient assessment, structured debriefing, and competency tracking.',
};
