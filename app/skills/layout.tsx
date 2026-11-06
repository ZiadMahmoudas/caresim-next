import { privateMetadata } from '@/lib/private-metadata';
import { requireAppRole } from '@/lib/neon/guards';
export const metadata = privateMetadata;
export const dynamic = 'force-dynamic';
export default async function PrivateLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  await requireAppRole(['student']);
  return children;
}
