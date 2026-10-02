// Who may use the master admin page.
//
// An environment variable rather than a column, because a column can be set by
// anything that can write to the database — an SQL injection, a restored
// backup, a mistyped seed — while this needs shell access to the host and a
// service restart. Platform admin is the one role that must be harder to grant
// than everything else, since it can read and delete any household's ledger.
//
// Empty by default: a deployment that never sets it has no master admin at all,
// and the routes behave as if they do not exist.
export function platformAdmins() {
  return (process.env.PLATFORM_ADMINS ?? '')
    .split(',').map((entry) => entry.trim().toLowerCase()).filter(Boolean);
}

export function isPlatformAdmin(email) {
  if (typeof email !== 'string' || !email) return false;
  return platformAdmins().includes(email.trim().toLowerCase());
}

// One row of the master admin user table. Both stores assemble the same list of
// books first and then come here, so the counts cannot drift apart — they have
// before.
//
// `books` is `[{ id, name, workspaceId, role, transactionCount, lastActivityAt }]`.
export function summariseUser(user, books) {
  const owned = books.filter((book) => book.role === 'book_owner');
  const activity = books.map((book) => book.lastActivityAt).filter(Boolean).map((value) => new Date(value).getTime());
  return {
    id: user.id,
    firebaseUid: user.firebaseUid,
    email: user.email,
    displayName: user.displayName ?? null,
    disabledAt: user.disabledAt ? new Date(user.disabledAt).toISOString() : null,
    createdAt: user.createdAt ? new Date(user.createdAt).toISOString() : null,
    isPlatformAdmin: isPlatformAdmin(user.email),
    workspaceCount: new Set(books.map((book) => book.workspaceId)).size,
    bookCount: books.length,
    // Only books they own count towards "their" data: a CA reviewing a
    // household has a membership there, not a ledger of their own.
    ownedBookCount: owned.length,
    transactionCount: owned.reduce((sum, book) => sum + (book.transactionCount ?? 0), 0),
    lastActivityAt: activity.length ? new Date(Math.max(...activity)).toISOString() : null,
    books: books.map(({ id, name, role }) => ({ id, name, role })),
  };
}

// A Firebase account and a ledger profile are matched on uid first, because an
// email can be changed in either place; falling back to email is what catches
// the rows seeded before a real sign-in existed.
export function mergeDirectory(profiles, firebaseUsers) {
  const byUid = new Map(firebaseUsers.map((account) => [account.uid, account]));
  const byEmail = new Map(firebaseUsers.map((account) => [(account.email ?? '').toLowerCase(), account]));
  const claimed = new Set();
  const rows = profiles.map((profile) => {
    const account = byUid.get(profile.firebaseUid) ?? byEmail.get((profile.email ?? '').toLowerCase()) ?? null;
    if (account) claimed.add(account.uid);
    return { ...profile, firebase: account };
  });
  // Accounts that exist in Firebase but have never signed in have no ledger
  // profile yet. They are the ones an operator most needs to see — an invitation
  // that was created and then forgotten looks like nothing at all otherwise.
  for (const account of firebaseUsers) {
    if (claimed.has(account.uid)) continue;
    rows.push({
      id: null, firebaseUid: account.uid, email: account.email, displayName: account.displayName,
      disabledAt: null, createdAt: account.createdAt, isPlatformAdmin: isPlatformAdmin(account.email),
      workspaceCount: 0, bookCount: 0, ownedBookCount: 0, transactionCount: 0, lastActivityAt: null,
      books: [], firebase: account,
    });
  }
  return rows.sort((a, b) => (a.email ?? '').localeCompare(b.email ?? ''));
}
