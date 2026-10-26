import { AppShell } from '@/components/AppShell';
import { ScenarioCatalogManager } from '@/components/ScenarioCatalogManager';

type PageProps = {
  searchParams?: Promise<{ q?: string | string[] }>;
};

export default async function AdminScenarios({ searchParams }: PageProps) {
  const params = searchParams ? await searchParams : {};
  const q = Array.isArray(params.q) ? params.q[0] ?? '' : params.q ?? '';

  return (
    <AppShell role="admin">
      <div className="page page-airy">
        <div className="page-head compact-head">
          <div>
            <span className="eyebrow simple">Clinical content</span>
            <h1>Scenarios & assessments.</h1>
            <p>Create the catalog, publish approved cases and assign them to courses as assessments.</p>
          </div>
        </div>
        <ScenarioCatalogManager role="admin" initialQuery={q} />
      </div>
    </AppShell>
  );
}
