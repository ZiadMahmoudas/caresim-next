import { privateMetadata } from '@/lib/private-metadata';
export const metadata = privateMetadata;
export default function PrivateLayout({ children }: Readonly<{ children: React.ReactNode }>) { return children; }
