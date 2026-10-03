// Firebase user administration: list, create, edit, disable, delete, reset.
//
// Deliberately not the `firebase-admin` package. It pulls in google-auth-library,
// gaxios, Firestore and Storage for the six calls below, and this API already
// depends on `jose` to verify ID tokens. Minting a service-account access token
// is one signed JWT; the rest is the Identity Toolkit REST API that
// `firebase-admin` itself calls. Same reasoning as domain/xlsx.js.
//
// Everything here needs a service-account key, which the API otherwise does not
// have — token verification uses Google's public JWKS. Without one this module
// reports `configured: false` and the admin page falls back to what the ledger
// knows about its own users. That is deliberate: a key that can mint a token for
// any user should be opt-in, not a requirement to boot.
import { readFileSync } from 'node:fs';
import { importPKCS8, SignJWT } from 'jose';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPES = 'https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/firebase';
const IDENTITY = 'https://identitytoolkit.googleapis.com/v1';

function fail(message, code, statusCode = 502) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

let cachedAccount;
// Read once. A key that changes needs a restart, which is the same contract as
// every other secret in the unit file.
export function serviceAccount() {
  if (cachedAccount !== undefined) return cachedAccount;
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT;
  const path = process.env.FIREBASE_SERVICE_ACCOUNT_FILE;
  let raw = null;
  try {
    if (inline) raw = inline;
    else if (path) raw = readFileSync(path, 'utf8');
  } catch (error) {
    throw fail(`FIREBASE_SERVICE_ACCOUNT_FILE could not be read: ${error.message}`, 'SERVICE_ACCOUNT_UNREADABLE', 500);
  }
  if (!raw) return (cachedAccount = null);
  let parsed;
  try { parsed = JSON.parse(raw); } catch { throw fail('The Firebase service account is not valid JSON', 'SERVICE_ACCOUNT_INVALID', 500); }
  if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
    throw fail('The Firebase service account is missing client_email, private_key or project_id', 'SERVICE_ACCOUNT_INVALID', 500);
  }
  // An inline key carries its newlines escaped; a file has them already.
  return (cachedAccount = { ...parsed, private_key: parsed.private_key.replace(/\\n/g, '\n') });
}

export function firebaseAdminConfigured() {
  try { return Boolean(serviceAccount()); } catch { return false; }
}

let cachedToken = null;
async function accessToken() {
  const account = serviceAccount();
  if (!account) throw fail('No Firebase service account is configured on this server', 'FIREBASE_ADMIN_UNCONFIGURED', 501);
  // Google issues these for an hour. Re-mint a minute early rather than find
  // out mid-request.
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;

  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: SCOPES })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(account.client_email).setSubject(account.client_email)
    .setAudience(TOKEN_URL).setIssuedAt(now).setExpirationTime(now + 3600)
    .sign(await importPKCS8(account.private_key, 'RS256'));

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    signal: AbortSignal.timeout(10_000),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.access_token) {
    throw fail(`Google refused the service account: ${body.error_description ?? body.error ?? response.status}`, 'FIREBASE_ADMIN_AUTH_FAILED');
  }
  cachedToken = { value: body.access_token, expiresAt: Date.now() + (body.expires_in ?? 3600) * 1000 };
  return cachedToken.value;
}

async function call(path, { method = 'POST', body } = {}) {
  const account = serviceAccount();
  const token = await accessToken();
  const response = await fetch(`${IDENTITY}/projects/${account.project_id}${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(15_000),
  });
  const parsed = await response.json().catch(() => ({}));
  if (!response.ok) {
    const reason = parsed?.error?.message ?? `HTTP ${response.status}`;
    // Identity Toolkit speaks in constants. Translate the ones an operator will
    // actually hit, so the dashboard does not show EMAIL_EXISTS to a human.
    const readable = {
      EMAIL_EXISTS: 'That email address already has a Firebase account',
      INVALID_EMAIL: 'That is not a valid email address',
      USER_NOT_FOUND: 'Firebase has no account with that id',
      WEAK_PASSWORD: 'Firebase rejected that password as too weak',
      PERMISSION_DENIED: 'The service account is not allowed to manage users. Give it the Firebase Authentication Admin role',
    }[reason.split(' ')[0]] ?? reason;
    throw fail(readable, 'FIREBASE_ADMIN_ERROR', response.status === 403 ? 403 : 502);
  }
  return parsed;
}

function shape(account) {
  return {
    uid: account.localId,
    email: account.email ?? null,
    displayName: account.displayName ?? null,
    emailVerified: account.emailVerified === true,
    disabled: account.disabled === true,
    createdAt: account.createdAt ? new Date(Number(account.createdAt)).toISOString() : null,
    lastSignInAt: account.lastLoginAt ? new Date(Number(account.lastLoginAt)).toISOString() : null,
  };
}

// Every account in the project. A household-sized project fits in one page;
// the loop is there so a bigger one does not silently truncate.
export async function listFirebaseUsers({ limit = 2000 } = {}) {
  const users = [];
  let pageToken;
  do {
    const query = new URLSearchParams({ maxResults: '500', ...(pageToken ? { nextPageToken: pageToken } : {}) });
    const page = await call(`/accounts:batchGet?${query}`, { method: 'GET' });
    for (const account of page.users ?? []) users.push(shape(account));
    pageToken = page.nextPageToken;
  } while (pageToken && users.length < limit);
  return users;
}

// No password is set here on purpose. The new user receives a reset link and
// chooses their own, so nobody — including whoever is running this page — ever
// handles their password.
export async function createFirebaseUser({ email, displayName }) {
  const created = await call('/accounts', { body: { email, displayName: displayName || undefined, emailVerified: false } });
  return shape({ ...created, email, displayName });
}

// One account, read back authoritatively.
export async function lookupFirebaseUser(uid) {
  const found = await call('/accounts:lookup', { body: { localId: [uid] } });
  return found.users?.length ? shape(found.users[0]) : null;
}

// The same lookup keyed on the address. Approving an access request has an
// email and needs to know whether that account already exists, because
// creating it a second time is an error rather than a no-op.
export async function findFirebaseUserByEmail(email) {
  const found = await call('/accounts:lookup', { body: { email: [email] } });
  return found.users?.length ? shape(found.users[0]) : null;
}

export async function updateFirebaseUser(uid, { email, displayName, disabled }) {
  await call('/accounts:update', {
    body: {
      localId: uid,
      ...(email === undefined ? {} : { email }),
      ...(displayName === undefined ? {} : { displayName }),
      ...(disabled === undefined ? {} : { disableUser: disabled }),
    },
  });
  // accounts:update echoes back only some of what it was given — notably not
  // `disabled`, so shaping its response reported every disable as a no-op even
  // though it had worked. Read the record instead of trusting the write.
  return await lookupFirebaseUser(uid) ?? shape({ localId: uid, email, displayName });
}

export async function deleteFirebaseUser(uid) {
  await call('/accounts:delete', { body: { localId: uid } });
}

// Firebase sends the email itself. Returning the link instead would hand
// whoever is on this page a one-click takeover of somebody else's account.
export async function sendFirebasePasswordReset(email) {
  await call('/accounts:sendOobCode', { body: { requestType: 'PASSWORD_RESET', email, returnOobLink: false } });
}

// Tests reach in here; nothing else should.
export function resetFirebaseAdminCache() { cachedAccount = undefined; cachedToken = null; }
