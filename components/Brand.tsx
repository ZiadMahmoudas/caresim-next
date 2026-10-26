import Image from 'next/image';
import Link from 'next/link';

export function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <Link href="/" className={`brand ${compact ? 'brand-compact' : ''}`}>
      <Image src="/caresim-logo.jpeg" width={compact ? 42 : 48} height={compact ? 42 : 48} alt="CareSim" className="brand-logo" />
      {!compact && <span className="brand-word"><b>Care</b><strong>Sim</strong></span>}
    </Link>
  );
}
