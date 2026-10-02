'use client';

import { FormEvent, useEffect, useState } from 'react';
import { observeUser, registerInvitedUser, sendPasswordReset, signIn } from './firebase-client';
import { Leaf, SiteFooter, SiteHeader } from './site-chrome';
import './landing.css';

// Sign-in lives on its own route so that "/" can be the landing page. The same
// component is reused at "/" when an invitation token is in the URL, because an
// invited person arriving from a link should land on the form, not on marketing.
// Set once someone signs in, cleared when they sign out. It only decides which
// screen "/" shows while Firebase is still resolving — the landing page used to
// flash in front of a returning user. Nothing is trusted to it.
const RETURNING = 'paisa.returning';
export function returning(){ try{ return localStorage.getItem(RETURNING)==='1'; }catch{ return false; } }
export function rememberSignedIn(value:boolean){ try{ if(value)localStorage.setItem(RETURNING,'1'); else localStorage.removeItem(RETURNING); }catch{} }

export function invitationToken() { if(typeof window==='undefined')return null; const fragmentQuery=window.location.hash.split('?')[1]??''; return new URLSearchParams(fragmentQuery).get('invite')??new URLSearchParams(window.location.search).get('invite'); }
function signInMessage(error:unknown){const code=typeof error==='object'&&error&&'code' in error?String((error as {code:unknown}).code):'';return ({'auth/invalid-credential':'That email and password combination is not recognised.','auth/wrong-password':'That email and password combination is not recognised.','auth/user-not-found':'That email and password combination is not recognised.','auth/invalid-email':'Enter a valid email address.','auth/user-disabled':'This account has been disabled. Ask the workspace owner to restore it.','auth/too-many-requests':'Too many attempts. Wait a few minutes before trying again.','auth/network-request-failed':'Cannot reach the authentication service. Check your connection.','auth/multi-factor-auth-required':'This account requires a second factor, which this build cannot complete yet.','auth/operation-not-allowed':'Email sign-in is not enabled for this Firebase project.'} as Record<string,string>)[code]??(code.startsWith('auth/api-key-not-valid')||code==='auth/invalid-api-key'?'Authentication is not configured for this deployment.':'Sign-in failed. Verify your email and check your credentials.');}
export function SignIn(){const[message,setMessage]=useState('');const[busy,setBusy]=useState(false);const[hasInvite]=useState(()=>Boolean(invitationToken()));async function submit(event:FormEvent<HTMLFormElement>){event.preventDefault();setBusy(true);setMessage('');const form=new FormData(event.currentTarget);try{await signIn(String(form.get('email')),String(form.get('password')));}catch(error){setMessage(signInMessage(error));}finally{setBusy(false);}}async function createAccount(event:React.MouseEvent<HTMLButtonElement>){const form=event.currentTarget.form;if(!form||!form.reportValidity())return;setBusy(true);setMessage('');const data=new FormData(form);try{await registerInvitedUser(String(data.get('email')),String(data.get('password')));setMessage('Account created. Verify your email, then return here and sign in.');}catch{setMessage('Could not create the account. It may already exist; try signing in.');}finally{setBusy(false);}}async function resetPassword(event:React.MouseEvent<HTMLButtonElement>){const email=event.currentTarget.form?.querySelector<HTMLInputElement>('input[name=email]');if(!email?.value||!email.checkValidity()){setMessage('Enter your email address first, then choose reset.');return;}setBusy(true);setMessage('');try{await sendPasswordReset(email.value);setMessage(`If ${email.value} has an account, a reset link is on its way.`);}catch(error){setMessage(signInMessage(error));}finally{setBusy(false);}}return <main className="auth-page"><section className="auth-card"><div className="brand auth-brand"><Leaf/><span>Paisa</span></div><p className="eyebrow">PRIVATE FINANCIAL WORKSPACE</p><h1>Your finances, clearly shared.</h1><p>{hasInvite?'Create or sign in to the exact email address that received this invitation.':'Sign in to your private book, household workspace, or CA review view.'}</p><form onSubmit={submit}><label>Email<input name="email" type="email" autoComplete="email" required/></label><label>Password<input name="password" type="password" autoComplete={hasInvite?'new-password':'current-password'} minLength={8} required/></label>{message?<p className="form-error" role="status">{message}</p>:null}<button className="primary-button" disabled={busy}>{busy?'Please wait…':'Sign in securely'}</button>{hasInvite?<button type="button" className="secondary-button" disabled={busy} onClick={createAccount}>Create invited account</button>:null}<button type="button" className="text-button reset-link" disabled={busy} onClick={resetPassword}>Forgot your password?</button></form><small>Access is available only to users invited by a workspace owner.</small></section>
  <nav className="auth-links">{[['about-us','About'],['why-use-us','Why use us'],['help','Help'],['privacy-policy','Privacy'],['terms-and-conditions','Terms'],['contact-us','Contact']].map(([slug,label])=><a href={`/${slug}`} key={slug}>{label}</a>)}</nav></main>;}

// The sign-in route: same card, with the public header and footer around it so
// every page on the site links to every other.
export function SignInPage() {
  // Signing in does not navigate by itself — Firebase only flips its own state.
  // Watching it here means the form, the back button and an already-signed-in
  // visitor all end up in the same place.
  useEffect(() => observeUser((user) => { if (!user) return; rememberSignedIn(true); window.location.replace('/'); }), []);

  return (
    <div className="login-page">
      <div className="landing-blobs" aria-hidden="true"><i /><i /><i /></div>
      <SiteHeader compact />
      <SignIn />
      <SiteFooter />
    </div>
  );
}
