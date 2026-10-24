'use client';

import { getApp, getApps, initializeApp } from 'firebase/app';
import { getToken, initializeAppCheck, ReCaptchaV3Provider } from 'firebase/app-check';
import { createUserWithEmailAndPassword, getAuth, onAuthStateChanged, sendEmailVerification, sendPasswordResetEmail, signInWithEmailAndPassword, signOut, type User } from 'firebase/auth';

export const firebaseEnabled = process.env.NEXT_PUBLIC_AUTH_MODE === 'firebase';
let appCheckInstance: ReturnType<typeof initializeAppCheck> | undefined;

function app() {
  if (getApps().length) return getApp();
  return initializeApp({
    apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
    authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
    projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
    appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
  });
}

export function observeUser(callback: (user: User | null) => void) {
  if (!firebaseEnabled) {
    callback(null);
    return () => undefined;
  }
  return onAuthStateChanged(getAuth(app()), callback);
}

export async function signIn(email: string, password: string) {
  if (firebaseEnabled) await signInWithEmailAndPassword(getAuth(app()), email, password);
}

export async function registerInvitedUser(email: string, password: string) {
  if (!firebaseEnabled) return;
  const auth = getAuth(app());
  const credential = await createUserWithEmailAndPassword(auth, email, password);
  await sendEmailVerification(credential.user);
  await signOut(auth);
}

export async function sendPasswordReset(email: string) {
  if (firebaseEnabled) await sendPasswordResetEmail(getAuth(app()), email);
}

// The admin API trusts a listed email only once Firebase has verified it, and a
// console-created account never is. These let that admin verify their own
// address from the gate page instead of needing shell access to the server.
export async function sendOwnVerificationEmail() {
  const user = firebaseEnabled ? getAuth(app()).currentUser : null;
  if (user) await sendEmailVerification(user);
}

// The link is clicked in another tab; reload the user and force a new token so
// the next request carries email_verified.
export async function refreshVerification() {
  const user = firebaseEnabled ? getAuth(app()).currentUser : null;
  if (!user) return false;
  await user.reload();
  await user.getIdToken(true);
  return user.emailVerified;
}

export async function signOutUser() {
  if (firebaseEnabled) await signOut(getAuth(app()));
}

export async function apiAuthHeaders(): Promise<Record<string, string>> {
  if (!firebaseEnabled) return { 'x-dev-user-id': 'user_owner' };
  const current = getAuth(app()).currentUser;
  if (!current) throw new Error('Please sign in to continue');
  const headers: Record<string, string> = {
    authorization: `Bearer ${await current.getIdToken()}`,
  };
  const siteKey = process.env.NEXT_PUBLIC_FIREBASE_APP_CHECK_SITE_KEY;
  if (siteKey) {
    const appCheck = appCheckInstance ??= initializeAppCheck(app(), {
      provider: new ReCaptchaV3Provider(siteKey),
      isTokenAutoRefreshEnabled: true,
    });
    headers['x-firebase-appcheck'] = (await getToken(appCheck)).token;
  }
  return headers;
}
