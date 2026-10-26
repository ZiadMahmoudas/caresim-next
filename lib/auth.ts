export type AppRole = 'student' | 'instructor' | 'admin';

export function homeForRole(role?: string | null) {
  if (role === 'admin') return '/admin';
  if (role === 'instructor') return '/instructor';
  return '/dashboard';
}

export function initials(name?: string | null, email?: string | null) {
  const source = (name || email || 'Care Sim').trim();
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return `${parts[0][0] || ''}${parts[parts.length - 1][0] || ''}`.toUpperCase();
}

export function roleLabel(role?: string | null, learnerType?: string | null) {
  if (role === 'admin') return 'Administrator';
  if (role === 'instructor') return 'Clinical Instructor';
  return learnerType === 'nurse' ? 'Practicing Nurse' : 'Nursing Student';
}
