// Sign in with Apple or Google through Supabase, PKCE flow.
//
// Web: the page goes to the provider and comes back with ?code=… (finishRedirect picks it up).
// Desktop: Google and Apple refuse sign-in inside an embedded web view, so the Tauri side opens the
// system browser and catches the redirect on http://127.0.0.1:<port>/auth-callback (src-tauri/src/lib.rs).
// Every redirect URL must be listed in Supabase → Authentication → URL Configuration → Redirect URLs.
import type { OAuthProvider, Session, SupabaseClient } from './supabase';

const VERIFIER_KEY = 'framescan.oauth.verifier';

type TauriInvoke = (cmd: string, args?: Record<string, unknown>) => Promise<unknown>;
function tauriInvoke(): TauriInvoke | undefined {
  const internals = (window as unknown as { __TAURI_INTERNALS__?: { invoke?: TauriInvoke } }).__TAURI_INTERNALS__;
  return internals?.invoke;
}
export const isDesktop = () => typeof window !== 'undefined' && !!tauriInvoke();

function base64url(bytes: Uint8Array) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function challengeFor(verifier: string) {
  return base64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
}

export async function pkcePair() {
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
  return { verifier, challenge: await challengeFor(verifier) };
}

/// The web planner's own address without query or hash: where the provider sends the browser back.
export function webRedirectURL() { return window.location.origin + window.location.pathname; }

function callbackError(q: URLSearchParams) {
  const e = q.get('error_description') || q.get('error');
  return e ? new Error(e.replace(/\+/g, ' ')) : undefined;
}

/// Desktop: resolves with a session. Web: navigates away (the promise never resolves) and the session
/// arrives through finishRedirect when the page loads again.
export async function startOAuth(client: SupabaseClient, provider: OAuthProvider): Promise<Session | undefined> {
  await client.requireProvider(provider);
  const { verifier, challenge } = await pkcePair();
  const invoke = tauriInvoke();
  if (invoke) {
    const port = await invoke('oauth_listen') as number;
    const url = client.authorizeURL(provider, `http://127.0.0.1:${port}/auth-callback`, challenge);
    const query = new URLSearchParams(await invoke('oauth_wait', { url }) as string);
    const err = callbackError(query);
    if (err) throw err;
    const code = query.get('code');
    if (!code) throw new Error('Sign-in was cancelled.');
    return client.exchangeCode(code, verifier);
  }
  try { sessionStorage.setItem(VERIFIER_KEY, verifier); } catch { throw new Error('This browser blocks the storage sign-in needs. Use email instead.'); }
  window.location.assign(client.authorizeURL(provider, webRedirectURL(), challenge));
  return new Promise<never>(() => {});
}

/// Web only: finishes a sign-in the provider redirected back from. Returns true when it signed in.
export async function finishRedirect(client: SupabaseClient): Promise<boolean> {
  if (isDesktop()) return false;
  const q = new URLSearchParams(window.location.search);
  if (!q.has('code') && !q.has('error') && !q.has('error_description')) return false;
  let verifier: string | null = null;
  try { verifier = sessionStorage.getItem(VERIFIER_KEY); sessionStorage.removeItem(VERIFIER_KEY); } catch { /* blocked */ }
  // Clean the address bar either way so a reload doesn't reuse the code.
  window.history.replaceState(null, '', webRedirectURL() + window.location.hash);
  const err = callbackError(q);
  if (err) throw err;
  const code = q.get('code');
  if (!code || !verifier) return false;
  await client.exchangeCode(code, verifier);
  return true;
}
