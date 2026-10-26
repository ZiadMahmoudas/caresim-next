import { AppShell } from '@/components/AppShell';
import { ScenarioCatalogManager } from '@/components/ScenarioCatalogManager';

type PageProps = {
  searchParams?: Promise<{ q?: string | string[] }>;
};

export default async function InstructorScenarios({ searchParams }: PageProps) {
  const params = searchParams ? await searchParams : {};
  const q = Array.isArray(params.q) ? params.q[0] ?? '' : params.q ?? '';

  return (
    <AppShell role="instructor">
      <div className="page page-airy">
        <div className="page-head compact-head">
          <div>
            <span className="eyebrow simple">Simulation Builder</span>
            <h1>Author complete clinical training.</h1>
            <p>Build the patient, images, clinical actions, consequences, assessment questions, correct answers, RAG knowledge and scoring — then publish it to your learners.</p>
          </div>
        </div>
        <ScenarioCatalogManager role="instructor" initialQuery={q} />
      </div>
    </AppShell>
  );
}
