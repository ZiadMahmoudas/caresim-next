import type { MetadataRoute } from 'next';
import { seo } from '@/lib/seo';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: seo.name,
    short_name: seo.shortName,
    description: seo.description,
    start_url: '/',
    display: 'standalone',
    background_color: '#fbf8f3',
    theme_color: '#173d68',
    icons: [
      { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
    ],
  };
}
