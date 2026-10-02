/* eslint-disable @next/next/no-html-link-for-pages -- vinext is not Next: its
   next/link prefetch throws "ee is not a function" at runtime. Full navigation
   is correct for these static pages anyway. */
import { siteNav, sitePages } from './site-pages';
import './landing.css';

// Shared header and footer for everything outside the dashboard: the landing
// page, the sign-in page and the thirteen information pages. One copy, so the
// footer links cannot drift apart.

export function Leaf() {
  return (
    <svg className="leaf" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 22.5C6.2 19.4 3.2 14.3 3.2 8.4c0-3 1-5.6 1-5.6s4.2 1 6.7 3.7c2.2 2.4 1.1 16 1.1 16z" fill="#9dc07f" />
      <path d="M12 22.5c5.8-3.1 8.8-8.2 8.8-14.1 0-3-1-5.6-1-5.6s-4.2 1-6.7 3.7c-2.2 2.4-1.1 16-1.1 16z" fill="#1e5c45" />
    </svg>
  );
}

// The pages worth surfacing before someone has read anything. The footer still
// lists all thirteen.
const headerNav = ['about-us', 'why-use-us', 'help', 'contact-us'];

// Nothing is sold and there is no public sign-up, so "request access" is an
// email, not a form.
export const REQUEST_ACCESS_HREF = '/contact-us';

export function SiteHeader({ compact = false }: { compact?: boolean }) {
  return (
    <header className="site-header">
      <a className="site-brand" href="/"><Leaf /><span>Paisa</span></a>
      {compact ? null : (
        <nav className="site-nav">
          {headerNav.map((slug) => <a key={slug} href={`/${slug}`}>{sitePages[slug].title}</a>)}
        </nav>
      )}
      <div className="site-actions">
        <a className="ghost-link" href="/login">Login</a>
        <a className="pill-button" href={REQUEST_ACCESS_HREF}>Request access</a>
      </div>
    </header>
  );
}

export function SiteFooter({ current }: { current?: string }) {
  // Grouped so thirteen links read as a directory rather than a wall.
  const columns: { heading: string; slugs: string[] }[] = [
    { heading: 'Paisa', slugs: ['about-us', 'why-use-us', 'blog', 'testimonials-and-feedback'] },
    { heading: 'Using it', slugs: ['my-account', 'help', 'contact-us', 'customer-service-and-returns-policy'] },
    { heading: 'Legal', slugs: ['terms-and-conditions', 'privacy-policy', 'cookies', 'payment-policy', 'disclaimer'] },
  ];
  return (
    <footer className="site-footer">
      <div className="site-footer-grid">
        <div className="site-footer-brand">
          <a className="site-brand" href="/"><Leaf /><span>Paisa</span></a>
          <p>Household finance for India. Invite-only, in rupees, on Asia/Kolkata time.</p>
          <a className="pill-button small" href={REQUEST_ACCESS_HREF}>Request access</a>
        </div>
        {columns.map((column) => (
          <nav key={column.heading}>
            <p className="eyebrow">{column.heading.toUpperCase()}</p>
            {column.slugs.map((slug) => (
              <a key={slug} href={`/${slug}`} aria-current={slug === current ? 'page' : undefined}>{sitePages[slug].title}</a>
            ))}
          </nav>
        ))}
      </div>
      <div className="site-footer-base">
        <small>Paisa is a private record-keeping tool. It is not a bank, and nothing here is financial advice.</small>
        <small>© {new Date().getFullYear()} Paisa · {siteNav.length} published pages · <a href="/login">Login</a></small>
      </div>
    </footer>
  );
}
