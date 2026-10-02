/* eslint-disable @next/next/no-html-link-for-pages -- see site-chrome.tsx */
import { REQUEST_ACCESS_HREF, SiteFooter, SiteHeader, Leaf } from './site-chrome';

// The public front door. Everything on it is static: no fetch, no state, no
// auth. The figures inside the product preview are sample data and say so.

const trustPoints = [
  { icon: '🔒', title: 'Private by design', body: 'Raw SMS stays on your device' },
  { icon: '✦', title: 'Automatically organized', body: 'UPI spending made simple' },
  { icon: '👥', title: 'Built for households', body: 'Share with family and your CA' },
];

const categories = [
  { icon: '🍽', name: 'Food & Dining', amount: '₹14,200', width: 100, tone: '#244e3c' },
  { icon: '🏠', name: 'Home & Utilities', amount: '₹9,480', width: 67, tone: '#38715a' },
  { icon: '🚌', name: 'Transport', amount: '₹5,320', width: 37, tone: '#7ea268' },
  { icon: '🛍', name: 'Shopping', amount: '₹4,950', width: 35, tone: '#a9c467' },
  { icon: '⋯', name: 'Others', amount: '₹14,300', width: 100, tone: '#c9cec6' },
];

const recent = [
  { icon: '🍽', tint: '#fde7e0', name: 'Zomato', when: '12 Mar', amount: '₹624' },
  { icon: '🛒', tint: '#e4f1dc', name: 'Blinkit', when: '11 Mar', amount: '₹1,240' },
  { icon: '🚗', tint: '#e2eaf8', name: 'Uber', when: '10 Mar', amount: '₹478' },
  { icon: '💡', tint: '#fdf0d8', name: 'Electricity bill', when: '10 Mar', amount: '₹2,320' },
  { icon: '📱', tint: '#e3f0ea', name: 'Jio recharge', when: '9 Mar', amount: '₹349' },
];

// Six months of savings, as a share of the chart's height.
const savings = [18, 32, 44, 55, 73, 92];
const savingsMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];

function SavingsChart() {
  const points = savings.map((value, index) => `${(index / (savings.length - 1)) * 100},${100 - value}`);
  return (
    <svg className="spark" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
      <polygon points={`0,100 ${points.join(' ')} 100,100`} fill="url(#sparkFill)" />
      <polyline points={points.join(' ')} fill="none" stroke="#2e7255" strokeWidth="2.2" vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
      <defs>
        <linearGradient id="sparkFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#2e7255" stopOpacity="0.22" />
          <stop offset="100%" stopColor="#2e7255" stopOpacity="0" />
        </linearGradient>
      </defs>
    </svg>
  );
}

function Preview() {
  return (
    <aside className="preview" aria-label="Preview of the Paisa dashboard">
      <div className="preview-top">
        <span className="site-brand small"><Leaf /><span>Paisa</span></span>
        <span className="preview-select">This month ⌄</span>
      </div>

      <div className="preview-grid">
        <section className="preview-card total">
          <p className="preview-label">Total spending</p>
          <strong>₹48,250</strong>
          <span className="preview-delta">↓ 12% lower than last month</span>
        </section>

        <section className="preview-card">
          <h3>Spending by category</h3>
          <ul className="preview-categories">
            {categories.map((row) => (
              <li key={row.name}>
                <span className="preview-icon plain">{row.icon}</span>
                <span className="preview-name">{row.name}</span>
                <span className="preview-bar"><i style={{ width: `${row.width}%`, background: row.tone }} /></span>
                <span className="preview-amount">{row.amount}</span>
              </li>
            ))}
          </ul>
        </section>

        <section className="preview-card">
          <h3>Recent UPI transactions <span className="preview-more">View all</span></h3>
          <ul className="preview-rows">
            {recent.map((row) => (
              <li key={row.name}>
                <span className="preview-icon" style={{ background: row.tint }}>{row.icon}</span>
                <span className="preview-name">{row.name}<small>{row.when}</small></span>
                <span className="preview-amount">{row.amount}</span>
              </li>
            ))}
          </ul>
        </section>

        <section className="preview-card">
          <h3>Savings trend</h3>
          <div className="preview-savings">
            <strong>₹1,28,600</strong>
            <span className="preview-delta up">↑ 20%<small>vs. last 3 months</small></span>
          </div>
          <SavingsChart />
          <ol className="preview-months">{savingsMonths.map((month) => <li key={month}>{month}</li>)}</ol>
        </section>
      </div>
      <p className="preview-note">Sample data</p>
    </aside>
  );
}

export default function Landing() {
  return (
    <div className="landing">
      <div className="landing-blobs" aria-hidden="true"><i /><i /><i /></div>
      <SiteHeader />

      <main className="hero">
        <div className="hero-copy">
          <h1>
            Your <span className="swoosh">money,
              <svg viewBox="0 0 200 10" preserveAspectRatio="none" aria-hidden="true">
                <path d="M2 7C45 2 140 1 198 5" fill="none" stroke="#9dc07f" strokeWidth="3" strokeLinecap="round" />
              </svg>
            </span>
            <br />finally in one place.
          </h1>
          <p className="hero-sub">
            Automatically organize UPI spending, share household books, and give
            your CA exactly the access they need.
          </p>
          <div className="hero-actions">
            <a className="pill-button outline" href="/login">Login</a>
            <a className="pill-button" href={REQUEST_ACCESS_HREF}>Request access</a>
          </div>
          <ul className="hero-trust">
            {trustPoints.map((point) => (
              <li key={point.title}>
                <span aria-hidden="true">{point.icon}</span>
                <p><strong>{point.title}</strong>{point.body}</p>
              </li>
            ))}
          </ul>
        </div>
        <Preview />
      </main>

      <SiteFooter />
    </div>
  );
}
