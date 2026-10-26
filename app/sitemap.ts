import type { MetadataRoute } from 'next';
import { siteUrl } from '@/lib/seo';
export default function sitemap():MetadataRoute.Sitemap{return [
 {url:siteUrl,lastModified:new Date(),changeFrequency:'weekly',priority:1},
 {url:`${siteUrl}/about`,lastModified:new Date(),changeFrequency:'monthly',priority:.8},
 {url:`${siteUrl}/contact`,lastModified:new Date(),changeFrequency:'monthly',priority:.7},
]}
