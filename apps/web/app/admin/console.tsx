'use client';

/* eslint-disable @next/next/no-html-link-for-pages -- see site-chrome.tsx */
import { FormEvent, useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api-client';
import { firebaseEnabled, observeUser, signOutUser } from '../firebase-client';
import { Leaf } from '../site-chrome';
import '../globals.css';
import '../admin.css';

// The master admin page. Separate route, separate chrome, deliberately: this is
// not the household dashboard with extra buttons, and it should not look like
// it. Everything it can do is destructive to somebody else's records.

type FirebaseAccount = { uid:string; email:string|null; displayName:string|null; emailVerified:boolean; disabled:boolean; createdAt:string|null; lastSignInAt:string|null };
type AdminUser = {
  id:string|null; firebaseUid:string; email:string; displayName:string|null; disabledAt:string|null; createdAt:string|null;
  isPlatformAdmin:boolean; workspaceIds:string[]; workspaceCount:number; bookCount:number; ownedBookCount:number; transactionCount:number;
  lastActivityAt:string|null; books:{id:string;name:string;role:string}[]; firebase:FirebaseAccount|null;
};
type Directory = { items:AdminUser[]; firebaseConfigured:boolean; firebaseReachable:boolean; reason:string|null; admins:string[] };
type AccessRequest = { id:string; email:string; name:string; createdAt:string; approvedAt:string|null };
type Dialog = { kind:'add' }|{ kind:'edit'|'reset-ledger'|'factory-reset'|'delete'; user:AdminUser }|null;

const empty:Directory = { items:[], firebaseConfigured:false, firebaseReachable:false, reason:null, admins:[] };
const roleLabels:Record<string,string> = { book_owner:'owner', editor:'editor', reviewer:'reviewer', viewer:'viewer' };

function when(value:string|null) {
  if (!value) return '—';
  return new Date(value).toLocaleDateString('en-IN', { day:'numeric', month:'short', year:'numeric', timeZone:'Asia/Kolkata' });
}
// The backup has to leave the browser as a file; it is the only copy that
// survives the delete it is taken before.
function download(name:string, data:unknown) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type:'application/json' }));
  const link = document.createElement('a');
  link.href = url; link.download = name; link.click();
  URL.revokeObjectURL(url);
}
const targetOf = (user:AdminUser) => user.id ?? user.firebaseUid;

export default function AdminConsole() {
  const [authState, setAuthState] = useState<'loading'|'in'|'out'>(firebaseEnabled ? 'loading' : 'in');
  const [email, setEmail] = useState('');
  const [state, setState] = useState<'loading'|'ready'|'forbidden'|'error'>('loading');
  const [directory, setDirectory] = useState<Directory>(empty);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState('');
  const [dialog, setDialog] = useState<Dialog>(null);
  const [requests, setRequests] = useState<AccessRequest[]>([]);

  useEffect(() => { if (!firebaseEnabled) return; return observeUser((user) => { setEmail(user?.email ?? ''); setAuthState(user ? 'in' : 'out'); }); }, []);
  useEffect(() => { if (authState === 'out') window.location.replace('/login'); }, [authState]);

  const flash = useCallback((message:string) => { setNote(message); window.setTimeout(() => setNote(''), 4000); }, []);

  const load = useCallback(async () => {
    try {
      const [users, access] = await Promise.all([
        api<Directory>('/v1/admin/users'),
        api<{ items:AccessRequest[] }>('/v1/admin/access-requests'),
      ]);
      setDirectory(users);
      setRequests(access.items);
      setState('ready');
    } catch (failure) {
      // The API 404s this route for anyone not in PLATFORM_ADMINS, so a 404 is
      // "you are not an admin", not "something broke".
      const message = failure instanceof Error ? failure.message : 'Could not load the directory';
      if (failure instanceof ApiError && failure.status === 404) { setState('forbidden'); return; }
      setError(message); setState('error');
    }
  }, []);
  // Fetching on mount is the whole point of the page, and `load` only ever
  // sets state once the request has come back.
  // eslint-disable-next-line react-hooks/set-state-in-effect -- async fetch, not a synchronous render loop
  useEffect(() => { if (authState === 'in') void load(); }, [authState, load]);

  async function run(work:() => Promise<string>) {
    setBusy(true); setError('');
    try { flash(await work()); setDialog(null); await load(); }
    catch (failure) { setError(failure instanceof Error ? failure.message : 'That did not work'); }
    finally { setBusy(false); }
  }

  const backup = (user:AdminUser) => run(async () => {
    const data = await api<unknown>(`/v1/admin/users/${targetOf(user)}/export`);
    download(`paisa-backup-${user.email.replace(/[^a-z0-9]+/gi, '-')}-${new Date().toISOString().slice(0, 10)}.json`, data);
    return `Backup of ${user.email} downloaded`;
  });
  // Approving is the whole grant: it creates the Firebase account, emails the
  // link that lets them choose a password, gives them a household and ticks
  // the row — so the form stops telling them to wait.
  const approve = (row:AccessRequest) => run(async () => {
    await api<unknown>(`/v1/admin/access-requests/${row.id}/approve`, { method:'POST', body:JSON.stringify({}) });
    return `${row.email} approved — they have been sent a link to set a password`;
  });
  const dismiss = (row:AccessRequest) => run(async () => {
    await api<unknown>(`/v1/admin/access-requests/${row.id}/delete`, { method:'POST', body:JSON.stringify({}) });
    return `Removed the request from ${row.email}`;
  });
  const resetPassword = (user:AdminUser) => run(async () => {
    await api<void>(`/v1/admin/users/${targetOf(user)}/password-reset`, { method:'POST', body:JSON.stringify({}) });
    return `A password reset link is on its way to ${user.email}`;
  });

  if (authState === 'loading' || state === 'loading') {
    return <main className="admin-gate"><div className="loading-line" /><p>Checking your access…</p></main>;
  }
  if (state === 'error') {
    // Zeroed tiles beside an error banner read as "nobody is signed up", which
    // is a worse lie than showing nothing at all.
    return (
      <main className="admin-gate">
        <h1>The ledger is unreachable</h1>
        <p>{error}</p>
        <p className="quiet">Nothing is shown rather than a page of zeros, which would read as an empty deployment.</p>
        <p><button className="primary-button" onClick={() => { setState('loading'); void load(); }}>Try again</button></p>
      </main>
    );
  }
  if (state === 'forbidden') {
    return (
      <main className="admin-gate">
        <h1>Not a master admin</h1>
        <p><strong>{email || 'This account'}</strong> is not listed in <code>PLATFORM_ADMINS</code> on the server, so this page has nothing to show.</p>
        <p className="quiet">Add the address to that variable in the API&apos;s environment file and restart the service. It is deliberately not something that can be granted from inside the app.</p>
        <p><a className="text-button" href="/">Back to the dashboard</a></p>
      </main>
    );
  }

  const pending = requests.filter((row) => !row.approvedAt);
  const users = directory.items.filter((user) => !query || `${user.email} ${user.displayName ?? ''}`.toLowerCase().includes(query.toLowerCase()));
  const signedIn = directory.items.filter((user) => user.id).length;
  const tiles = [
    { label:'Accounts', value:directory.items.length, note:directory.firebaseReachable ? 'in Firebase' : 'known to the ledger' },
    { label:'Active', value:signedIn, note:'have signed in at least once' },
    { label:'Never signed in', value:directory.items.length - signedIn, note:'created but unused' },
    // Distinct workspaces, not books. The label has to be literally true.
    { label:'Households', value:new Set(directory.items.flatMap((user) => user.workspaceIds)).size, note:'separate, fully isolated workspaces' },
    { label:'Books', value:new Set(directory.items.flatMap((user) => user.books.map((book) => book.id))).size, note:'ledgers across all households' },
    { label:'Waiting', value:pending.length, note:'asked for access, not yet approved' },
  ];

  return (
    <div className="admin-shell">
      <header className="admin-top">
        <span className="site-brand small"><Leaf /><span>Paisa</span></span>
        <span className="admin-badge">Master admin</span>
        <div className="admin-top-actions">
          <a className="text-button" href="/">Dashboard</a>
          <span className="quiet">{email}</span>
          <button className="text-button" onClick={() => void signOutUser()}>Sign out</button>
        </div>
      </header>

      <main className="admin-main">
        {note ? <p className="admin-note" role="status">{note}</p> : null}
        {error ? <p className="admin-error" role="alert">{error}</p> : null}
        {!directory.firebaseReachable && directory.reason ? (
          <section className="admin-banner">
            <strong>Firebase user management is off</strong>
            <p>{directory.reason}</p>
            <p className="quiet">Adding, renaming, disabling and password resets all need a service-account key. Backing up and clearing ledger data work without one.</p>
          </section>
        ) : null}

        <section className="admin-tiles">
          {tiles.map((tile) => (
            <article key={tile.label}>
              <p className="eyebrow">{tile.label.toUpperCase()}</p>
              <strong>{tile.value}</strong>
              <small>{tile.note}</small>
            </article>
          ))}
        </section>

        <section className="admin-card">
          <div className="admin-card-head">
            <div>
              <h2>Access requests</h2>
              <p className="quiet">People who filled in the form on the landing page. Approving one creates their account and emails them a link to set a password.</p>
            </div>
          </div>
          <div className="admin-table-scroll">
            <table className="admin-table requests">
              <thead><tr><th>Who</th><th>Asked</th><th>Status</th><th>Actions</th></tr></thead>
              <tbody>
                {requests.map((row) => (
                  <tr key={row.id}>
                    <td><strong>{row.email}</strong><small>{row.name}</small></td>
                    <td>{when(row.createdAt)}</td>
                    <td className="admin-pills">
                      {row.approvedAt
                        ? <span className="pill ok">approved {when(row.approvedAt)}</span>
                        : <span className="pill warn">waiting</span>}
                    </td>
                    <td className="admin-actions">
                      <button
                        className="text-button"
                        disabled={busy || Boolean(row.approvedAt) || !directory.firebaseReachable}
                        title={directory.firebaseReachable ? undefined : 'Needs a Firebase service account'}
                        onClick={() => void approve(row)}
                      >Approve</button>
                      <button className="text-button danger-link" disabled={busy} onClick={() => void dismiss(row)}>Remove</button>
                    </td>
                  </tr>
                ))}
                {requests.length ? null : <tr><td colSpan={4} className="quiet">Nobody has asked for access yet.</td></tr>}
              </tbody>
            </table>
          </div>
        </section>

        <section className="admin-card">
          <div className="admin-card-head">
            <div>
              <h2>Users</h2>
              <p className="quiet">Every account, what it owns, and what can be done with it.</p>
            </div>
            <div className="admin-card-actions">
              <input className="admin-search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search email or name" aria-label="Search users" />
              <button className="primary-button" disabled={!directory.firebaseReachable} onClick={() => setDialog({ kind:'add' })} title={directory.firebaseReachable ? undefined : 'Needs a Firebase service account'}>Add user</button>
            </div>
          </div>

          <div className="admin-table-scroll">
            <table className="admin-table">
              <thead>
                <tr><th>Account</th><th>Status</th><th>Books</th><th>Entries</th><th>Last activity</th><th>Actions</th></tr>
              </thead>
              <tbody>
                {users.map((user) => (
                  <tr key={user.firebaseUid || user.email}>
                    <td>
                      <strong>{user.email}</strong>
                      <small>{user.displayName ?? 'No name set'} · joined {when(user.createdAt)}</small>
                    </td>
                    <td className="admin-pills">
                      {user.isPlatformAdmin ? <span className="pill admin">master admin</span> : null}
                      {user.firebase?.disabled || user.disabledAt ? <span className="pill off">disabled</span> : null}
                      {!user.id ? <span className="pill warn">never signed in</span> : null}
                      {user.firebase && !user.firebase.emailVerified ? <span className="pill quiet-pill">unverified</span> : null}
                      {user.id && !user.disabledAt && !user.firebase?.disabled ? <span className="pill ok">active</span> : null}
                    </td>
                    <td>{user.ownedBookCount} owned<small>{user.books.map((book) => `${book.name} (${roleLabels[book.role] ?? book.role})`).join(', ') || '—'}</small></td>
                    <td>{user.transactionCount.toLocaleString('en-IN')}</td>
                    <td>{when(user.lastActivityAt ?? user.firebase?.lastSignInAt ?? null)}</td>
                    <td className="admin-actions">
                      <button className="text-button" disabled={busy || !user.id} onClick={() => void backup(user)}>Back up</button>
                      <button className="text-button" disabled={busy || !directory.firebaseReachable || !user.firebase} onClick={() => void resetPassword(user)} title={directory.firebaseReachable && !user.firebase ? 'No Firebase account for this profile' : undefined}>Reset password</button>
                      <button className="text-button" disabled={busy} onClick={() => setDialog({ kind:'edit', user })}>Edit</button>
                      <button className="text-button danger-link" disabled={busy || !user.id} onClick={() => setDialog({ kind:'reset-ledger', user })}>Clear data</button>
                      <button className="text-button danger-link" disabled={busy || !user.id} onClick={() => setDialog({ kind:'factory-reset', user })}>Reset to new</button>
                      <button className="text-button danger-link" disabled={busy || user.email === email} onClick={() => setDialog({ kind:'delete', user })}>Delete</button>
                    </td>
                  </tr>
                ))}
                {users.length ? null : <tr><td colSpan={6} className="quiet">No account matches that search.</td></tr>}
              </tbody>
            </table>
          </div>
        </section>
      </main>

      {dialog ? <Dialogs dialog={dialog} busy={busy} error={error} onClose={() => { setDialog(null); setError(''); }} run={run} /> : null}
    </div>
  );
}

function Modal({ title, children, onClose }:{ title:string; children:React.ReactNode; onClose:() => void }) {
  return (
    <div className="modal-backdrop" onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <section className="modal admin-modal">
        <button className="modal-close" onClick={onClose} aria-label="Close">×</button>
        <h2>{title}</h2>
        {children}
      </section>
    </div>
  );
}

function Dialogs({ dialog, busy, error, onClose, run }:{
  dialog:Exclude<Dialog,null>; busy:boolean; error:string; onClose:() => void;
  run:(work:() => Promise<string>) => Promise<void>;
}) {
  const [confirm, setConfirm] = useState('');
  const [alsoFirebase, setAlsoFirebase] = useState(false);

  if (dialog.kind === 'add') {
    return (
      <Modal title="Add a user" onClose={onClose}>
        <p className="modal-copy">
          Creates the Firebase account and emails them a link to set their own
          password. No password is typed or stored here by anyone.
        </p>
        <form onSubmit={(event:FormEvent<HTMLFormElement>) => {
          event.preventDefault();
          const form = new FormData(event.currentTarget);
          void run(async () => {
            const email = String(form.get('email')).trim().toLowerCase();
            await api<unknown>('/v1/admin/users', { method:'POST', body:JSON.stringify({
              email, displayName: String(form.get('displayName')).trim() || undefined, provision: form.get('provision') === 'on',
            }) });
            return `${email} created — they have been sent a link to set a password`;
          });
        }}>
          <label>Email<input name="email" type="email" required autoComplete="off" /></label>
          <label>Name<input name="displayName" maxLength={120} autoComplete="off" placeholder="Optional" /></label>
          <label className="checkbox"><input name="provision" type="checkbox" defaultChecked /> Give them their own household straight away</label>
          <p className="quiet">Without a household they can sign in but will see nothing until they are invited to a book.</p>
          {error ? <p className="form-error" role="alert">{error}</p> : null}
          <button className="primary-button submit" disabled={busy}>{busy ? 'Creating…' : 'Create account'}</button>
        </form>
      </Modal>
    );
  }

  const user = dialog.user;

  if (dialog.kind === 'edit') {
    return (
      <Modal title={`Edit ${user.email}`} onClose={onClose}>
        <p className="modal-copy">The email is changed in Firebase and in the ledger together — leaving one behind gives them an account that signs in and resolves to nobody.</p>
        <form onSubmit={(event:FormEvent<HTMLFormElement>) => {
          event.preventDefault();
          const form = new FormData(event.currentTarget);
          void run(async () => {
            const body:Record<string,unknown> = {};
            const nextEmail = String(form.get('email')).trim().toLowerCase();
            const nextName = String(form.get('displayName')).trim();
            const nextDisabled = form.get('disabled') === 'on';
            if (nextEmail && nextEmail !== user.email) body.email = nextEmail;
            if (nextName && nextName !== (user.displayName ?? '')) body.displayName = nextName;
            if (nextDisabled !== Boolean(user.disabledAt || user.firebase?.disabled)) body.disabled = nextDisabled;
            if (!Object.keys(body).length) return 'Nothing changed';
            await api<unknown>(`/v1/admin/users/${targetOf(user)}`, { method:'PATCH', body:JSON.stringify(body) });
            return `${user.email} updated`;
          });
        }}>
          <label>Email<input name="email" type="email" defaultValue={user.email} required /></label>
          <label>Name<input name="displayName" defaultValue={user.displayName ?? ''} maxLength={120} /></label>
          <label className="checkbox"><input name="disabled" type="checkbox" defaultChecked={Boolean(user.disabledAt || user.firebase?.disabled)} /> Disabled — cannot sign in</label>
          {error ? <p className="form-error" role="alert">{error}</p> : null}
          <button className="primary-button submit" disabled={busy}>{busy ? 'Saving…' : 'Save changes'}</button>
        </form>
      </Modal>
    );
  }

  const wiping = dialog.kind === 'reset-ledger';
  const factory = dialog.kind === 'factory-reset';
  const books = <><strong>{user.ownedBookCount}</strong> book{user.ownedBookCount === 1 ? '' : 's'} <strong>{user.email}</strong> owns</>;
  const matches = confirm.trim().toLowerCase() === user.email.toLowerCase();
  const title = wiping ? 'Clear this user’s data' : factory ? 'Reset this household to new' : 'Delete this user';
  return (
    <Modal title={title} onClose={onClose}>
      <p className="modal-copy">
        {wiping
          ? <>Every transaction, import and monthly review in the {books} will be deleted. Their accounts, categories, rules and budgets stay, so a re-import files itself.</>
          : factory
            ? <>Everything inside the {books}: transactions, imports, accounts, categorization rules, budgets, the percentage plan, recurring plans, pending invitations and the audit trail. The starter categories are put back, so the books still work.</>
            : <>Removes <strong>{user.email}</strong> from the ledger, along with any book nobody else is a member of. Books shared with someone else survive.</>}
      </p>
      {factory ? <p className="quiet">They keep their login, their books and everyone who can see them. Signing in afterwards looks like a brand-new account.</p> : null}
      {wiping ? <p className="quiet">Recurring plans survive, but a posting this removes will not come back — the plan has already advanced past it.</p> : null}
      <p className="admin-warning">This cannot be undone. Take a backup first — the button is on their row.</p>
      <form onSubmit={(event:FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        void run(async () => {
          const path = wiping ? 'ledger-reset' : factory ? 'factory-reset' : 'delete';
          await api<unknown>(`/v1/admin/users/${targetOf(user)}/${path}`, { method:'POST', body:JSON.stringify({ confirmEmail:user.email, ...(wiping || factory ? {} : { deleteFirebaseAccount:alsoFirebase }) }) });
          if (wiping) return `Cleared the ledger for ${user.email}`;
          return factory ? `${user.email} reset to a new household` : `${user.email} deleted`;
        });
      }}>
        <label><span>Type <code>{user.email}</code> to confirm</span><input value={confirm} onChange={(event) => setConfirm(event.target.value)} autoComplete="off" /></label>
        {wiping || factory ? null : (
          <label className="checkbox"><input type="checkbox" checked={alsoFirebase} onChange={(event) => setAlsoFirebase(event.target.checked)} /> Also delete the Firebase account, so they cannot sign in again</label>
        )}
        {error ? <p className="form-error" role="alert">{error}</p> : null}
        <button className="danger-button submit" disabled={busy || !matches}>{busy ? 'Working…' : wiping ? 'Clear the data' : factory ? 'Reset to new' : 'Delete the user'}</button>
      </form>
    </Modal>
  );
}
