'use client';

import { FormEvent, useState } from 'react';
import { createPortal } from 'react-dom';
import { apiBase } from './api-client';

// The "Request access" button, wherever it appears. Paisa is invite-only, so
// this form is the only way in from outside: it writes a row the master admin
// console shows, and nothing else.

type Status = 'received' | 'pending' | 'granted';

// What the server already knows decides the wording. The three cases are
// deliberately distinct: being told to wait when you have already been let in
// would send you back here a third time.
const outcomes: Record<Status, { heading: string; body: string }> = {
  received: {
    heading: 'Request sent',
    body: 'Thank you — the administrator can see your request. You will get an email with a link to set a password once they let you in.',
  },
  pending: {
    heading: 'Already on the list',
    body: 'You have asked for access before and it is still waiting for the administrator. Nothing more to do — please wait your turn.',
  },
  granted: {
    heading: 'You already have access',
    body: 'This address has been approved. Check your email for the link to set a password, then sign in — there is no need to ask again.',
  },
};

// `api()` cannot be used here: it attaches a Firebase token and throws without
// one, and the whole point of this form is that nobody is signed in.
async function submit(name: string, email: string): Promise<Status> {
  const response = await fetch(`${apiBase()}/v1/access-requests`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name, email }),
    signal: AbortSignal.timeout(12000),
  });
  const payload = await response.json().catch(() => ({})) as { status?: Status; message?: string };
  if (!response.ok) throw new Error(response.status === 429 ? 'Too many requests from here. Try again in a few minutes.' : payload.message ?? 'That did not go through');
  return payload.status ?? 'received';
}

export function RequestAccess({ className = 'pill-button' }: { className?: string }) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [outcome, setOutcome] = useState<Status | null>(null);

  function close() { setOpen(false); setError(''); setOutcome(null); }

  async function send(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true); setError('');
    try { setOutcome(await submit(String(form.get('name')).trim(), String(form.get('email')).trim().toLowerCase())); }
    catch (failure) { setError(failure instanceof Error ? failure.message : 'That did not go through'); }
    finally { setBusy(false); }
  }

  return (
    <>
      <button type="button" className={className} onClick={() => setOpen(true)}>Request access</button>
      {/* Portalled to <body>. The header and the footer both create stacking
          contexts, so a backdrop rendered in place paints underneath the hero
          card however high its z-index is. Only ever mounted after a click,
          which is always client-side, so there is nothing to hydrate. */}
      {open ? createPortal((
        <div className="modal-backdrop" onClick={(event) => { if (event.target === event.currentTarget) close(); }}>
          <section className="modal" role="dialog" aria-modal="true" aria-label="Request access to Paisa">
            <button className="modal-close" onClick={close} aria-label="Close">×</button>
            {outcome ? (
              <>
                <h2>{outcomes[outcome].heading}</h2>
                <p className="modal-copy">{outcomes[outcome].body}</p>
                <button className="primary-button submit" onClick={close}>Close</button>
              </>
            ) : (
              <>
                <h2>Request access</h2>
                <p className="modal-copy">Paisa is invite-only. Leave your name and email and the administrator will set up an account for you.</p>
                <form onSubmit={(event) => void send(event)}>
                  <label>Name<input name="name" required maxLength={120} autoComplete="name" /></label>
                  <label>Email<input name="email" type="email" required maxLength={320} autoComplete="email" /></label>
                  {error ? <p className="form-error" role="alert">{error}</p> : null}
                  <button className="primary-button submit" disabled={busy}>{busy ? 'Sending…' : 'Send request'}</button>
                  <small className="quiet">Only your name and email are stored, and only so somebody can reply to you.</small>
                </form>
              </>
            )}
          </section>
        </div>
      ), document.body) : null}
    </>
  );
}
