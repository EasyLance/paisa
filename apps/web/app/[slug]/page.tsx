/* eslint-disable @next/next/no-html-link-for-pages -- vinext is not Next: its
   next/link prefetch throws "ee is not a function" at runtime on these routes.
   These are static content pages, so a full navigation is the right behaviour
   anyway. Revisit if vinext fixes Link. */
import type { Metadata } from 'next';
import { sitePages, siteNav } from '../site-pages';
import '../globals.css';

// One route for all thirteen information pages: they share a layout and differ
// only in their content, so thirteen near-identical files would be thirteen
// places to edit the footer.
export function generateStaticParams() {
  return siteNav.map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const page = sitePages[(await params).slug];
  return page ? { title: `${page.title} — Paisa`, description: page.summary } : { title: 'Page not found — Paisa' };
}

export default async function InfoPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const page = sitePages[slug];

  return (
    <main className="info-page">
      <header className="info-top">
        <a className="brand info-brand" href="/"><span className="brand-mark">₹</span><span>Paisa</span></a>
        <a className="text-button" href="/">Back to the dashboard →</a>
      </header>

      {page ? (
        <article className="info-body">
          <p className="eyebrow">{page.title.toUpperCase()}</p>
          <h1>{page.title}</h1>
          <p className="info-summary">{page.summary}</p>
          {page.sections.map((section) => (
            <section key={section.heading}>
              <h2>{section.heading}</h2>
              {section.body.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
            </section>
          ))}
        </article>
      ) : (
        <article className="info-body">
          <p className="eyebrow">NOT FOUND</p>
          <h1>That page does not exist</h1>
          <p className="info-summary">The link may be out of date. Everything Paisa publishes is listed below.</p>
        </article>
      )}

      <footer className="info-footer">
        <p className="eyebrow">PAISA</p>
        <nav>
          {siteNav.filter((item) => item !== slug).map((item) => (
            <a key={item} href={`/${item}`}>{sitePages[item].title}</a>
          ))}
        </nav>
        <small>Paisa is a private record-keeping tool. It is not a bank, and nothing here is financial advice.</small>
      </footer>
    </main>
  );
}
