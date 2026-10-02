'use client';

import { apiAuthHeaders } from './firebase-client';

// One fetch wrapper for every page that talks to the ledger. The dashboard and
// the master admin page both need it, and a second copy would drift on the
// parts that matter: the timeout, the 429 wording, and the unreachable flag the
// dashboard uses to tell "this failed" from "the ledger is down".
const configuredApiUrl = process.env.NEXT_PUBLIC_API_URL;
export function apiBase() { if(configuredApiUrl)return configuredApiUrl; if(typeof window!=='undefined'&&['localhost','127.0.0.1'].includes(window.location.hostname))return 'http://localhost:4000'; return ''; }
// `status` is carried so callers can branch on what happened rather than on
// the wording of the message, which is prose and will be reworded.
export class ApiError extends Error { unreachable:boolean; status:number; constructor(message:string,unreachable=false,status=0){super(message);this.unreachable=unreachable;this.status=status;} }
export async function api<T>(path:string,options:RequestInit={}):Promise<T> {
  const base=apiBase(); if(!base)throw new ApiError('The dashboard is not configured with an API address',true);
  const authHeaders=await apiAuthHeaders();
  let response:Response;
  try{ response=await fetch(`${base}${path}`,{...options,signal:options.signal??AbortSignal.timeout(12000),headers:{...(options.body?{'content-type':'application/json'}:{}),...authHeaders,...options.headers}}); }
  catch(error){ throw new ApiError(error instanceof DOMException&&error.name==='TimeoutError'?`${base} did not respond in time`:`Cannot reach the ledger at ${base}`,true); }
  if(!response.ok){let message='Request failed';try{message=((await response.json()) as {message?:string}).message??message;}catch{}throw new ApiError(response.status===429?'Too many requests in a short time. Wait a moment and try again.':message,false,response.status);}
  if(response.status===204)return undefined as T;
  return response.json() as Promise<T>;
}
