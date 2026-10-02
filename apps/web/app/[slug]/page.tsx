import type { Metadata } from 'next';
import { sitePages, siteNav } from '../site-pages';
import { SiteFooter, SiteHeader } from '../site-chrome';
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
    <div className="info-shell">
      <SiteHeader />
      <main className="info-page">
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

      </main>
      <SiteFooter current={slug} />
    </div>
  );
}
