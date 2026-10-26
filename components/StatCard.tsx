export function StatCard({ icon, label, value, note, tone = 'blue' }: { icon: string; label: string; value: string; note: string; tone?: 'blue'|'rose'|'teal'|'gold' }) {
  return <div className="stat-card"><div className={`stat-icon ${tone}`}><i className={`fa-solid ${icon}`} /></div><div><span>{label}</span><strong>{value}</strong><small>{note}</small></div></div>;
}
