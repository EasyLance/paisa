import type { MetadataRoute } from 'next';
import { siteNav } from './site-pages';

const origin = 'https://paisa.easylancefreelance.com';

// Built from siteNav so a new information page cannot be left out.
export default function sitemap(): MetadataRoute.Sitemap {
  return ['', 'login', ...siteNav].map((slug) => ({ url: `${origin}/${slug}` }));
}
