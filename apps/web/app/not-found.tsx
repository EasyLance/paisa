import type { Metadata } from 'next';
import { SiteFooter, SiteHeader } from './site-chrome';
import './globals.css';

export const metadata: Metadata = { title: 'Page not found — Paisa' };

// Rendered with a real 404 for any unknown path, including /a/b.
export default function NotFound() {
  return (
    <div className="info-shell">
      <SiteHeader />
      <main className="info-page">
        <article className="info-body">
          <p className="eyebrow">NOT FOUND</p>
          <h1>That page does not exist</h1>
          <p className="info-summary">The link may be out of date. Everything Paisa publishes is listed below.</p>
        </article>
      </main>
      <SiteFooter />
    </div>
  );
}
