import type { Metadata } from 'next';
import '@fortawesome/fontawesome-free/css/all.min.css';
import 'lenis/dist/lenis.css';
import './globals.css';
import { seo, siteUrl } from '@/lib/seo';
import { SmoothScroll } from '@/components/SmoothScroll';
import { CareSimAssistant } from '@/components/CareSimAssistant';

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  applicationName: seo.name,
  title: { default: seo.title, template: `%s | ${seo.shortName}` },
  description: seo.description,
  keywords: ['nursing simulation','clinical simulation','virtual patient simulation','nursing education platform','nursing skills lab','AI simulated patient','clinical reasoning training','healthcare simulation'],
  authors: [{ name: 'CareSim' }], creator: 'CareSim', publisher: 'CareSim', category: 'Education',
  alternates: { canonical: '/' },
  openGraph: { type: 'website', url: '/', siteName: seo.name, title: seo.title, description: seo.description, images: [{ url: '/caresim-logo.jpeg', width: 1200, height: 1200, alt: 'CareSim Clinical Simulation Platform' }] },
  twitter: { card: 'summary_large_image', title: seo.title, description: seo.description, images: ['/caresim-logo.jpeg'] },
  robots: { index: true, follow: true, googleBot: { index: true, follow: true, 'max-image-preview': 'large', 'max-snippet': -1, 'max-video-preview': -1 } },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><SmoothScroll>{children}</SmoothScroll><CareSimAssistant/></body></html>;
}
