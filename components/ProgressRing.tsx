export function ProgressRing({ value, label }: { value: number; label?: string }) {
  return <div className="ring" style={{'--value': `${value * 3.6}deg`} as React.CSSProperties}><div><strong>{value}%</strong><span>{label || 'mastery'}</span></div></div>;
}
