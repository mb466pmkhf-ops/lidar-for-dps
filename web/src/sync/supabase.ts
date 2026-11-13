// Minimal Supabase client over plain REST (Auth + PostgREST). No SDK, so the iPhone app can talk
// to the same endpoints with URLSession. Setup SQL: web/supabase/schema.sql.
import type { FloorPlan, Project, UUID } from '../model/types';

export interface SyncConfig { url: string; anonKey: string }
export interface Session { accessToken: string; refreshToken: string; expiresAt: number; userID: string; email: string }

export interface RemoteRow {
  id: UUID; name: string; doc: Project; plans: Record<UUID, FloorPlan>; rev: number;
  deleted: boolean; updated_at: string; updated_by: string | null;
}
export type RemoteHead = Pick<RemoteRow, 'id' | 'rev' | 'deleted'>;

export const TABLE = 'framescan_projects';
export type OAuthProvider = 'apple' | 'google';

/// Plain words for the auth server's errors. Same wording as CloudSync.authMessage on iOS.
export function authMessage(j: Record<string, any>, status: number): string {
  switch (j.error_code) {
    case 'email_not_confirmed': return 'Confirm your email first: click the link we sent, or enter its code under Create account.';
    case 'invalid_credentials': return 'Wrong email or password.';
    case 'user_already_exists': case 'email_exists': return "There's already an account with this email. Sign in instead.";
    case 'weak_password': return 'Choose a longer password (at least 8 characters).';
    case 'otp_expired': return 'That code has expired. Send a new email and use the newest code.';
    case 'over_email_send_rate_limit': return 'Too many emails just now. Wait a minute and try again.';
    default: return j.error_description || j.msg || j.message || `Sign-in failed (${status})`;
  }
}

export class AuthError extends Error {
  constructor(message: string, readonly status: number) { super(message); }
}

export class SupabaseClient {
  constructor(readonly config: SyncConfig, public session?: Session, private onSession?: (s?: Session) => void) {}

  private base() { return this.config.url.replace(/\/+$/, ''); }

  private async post(path: string, body: unknown): Promise<Record<string, any>> {
    const res = await fetch(`${this.base()}/auth/v1/${path}`, {
      method: 'POST',
      headers: { apikey: this.config.anonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) throw new AuthError(authMessage(j, res.status), res.status);
    return j;
  }

  /// Returns undefined when the server answered without a session (a sign-up waiting for its email).
  private async auth(path: string, body: unknown): Promise<Session | undefined> {
    const j = await this.post(path, body);
    if (!j.access_token) return undefined;
    const s: Session = {
      accessToken: j.access_token, refreshToken: j.refresh_token,
      expiresAt: Date.now() + (j.expires_in ?? 3600) * 1000, userID: j.user?.id, email: j.user?.email,
    };
    this.session = s;
    this.onSession?.(s);
    return s;
  }

  private async mustAuth(path: string, body: unknown, failure = 'Sign-in failed'): Promise<Session> {
    const s = await this.auth(path, body);
    if (!s) throw new Error(failure);
    return s;
  }

  signIn(email: string, password: string) { return this.mustAuth('token?grant_type=password', { email, password }); }
  /// Undefined: the account waits for its confirmation email (link or code).
  signUp(email: string, password: string) { return this.auth('signup', { email, password }); }
  verifySignup(email: string, code: string) {
    return this.mustAuth('verify', { type: 'signup', email, token: code.replace(/\s+/g, '') },
      "That code didn't work. Check the newest email, or click its link and then sign in.");
  }
  async resendSignup(email: string) { await this.post('resend', { type: 'signup', email }); }

  /// Fails with plain words when the server hasn't switched the provider on (instead of a raw error
  /// page in the browser). An unreadable answer lets the attempt go ahead.
  async requireProvider(provider: OAuthProvider) {
    let enabled: unknown;
    try {
      const res = await fetch(`${this.base()}/auth/v1/settings`, { headers: { apikey: this.config.anonKey } });
      enabled = (await res.json())?.external?.[provider];
    } catch { return; }
    if (enabled === false) throw new Error(`${provider === 'apple' ? 'Apple' : 'Google'} sign-in isn't switched on for this server yet. Use email for now.`);
  }

  /// The provider's sign-in page (through Supabase). PKCE: only the holder of the verifier can use the code.
  authorizeURL(provider: OAuthProvider, redirectTo: string, challenge: string) {
    const q = new URLSearchParams({ provider, redirect_to: redirectTo, code_challenge: challenge, code_challenge_method: 's256' });
    return `${this.base()}/auth/v1/authorize?${q}`;
  }
  exchangeCode(code: string, verifier: string) {
    return this.mustAuth('token?grant_type=pkce', { auth_code: code, code_verifier: verifier });
  }

  signOut() { this.session = undefined; this.onSession?.(undefined); }

  /** Deletes the account and every project synced to it, then signs out. Local copies stay. */
  async deleteAccount(): Promise<void> {
    const res = await fetch(`${this.base()}/rest/v1/rpc/delete_my_account`, {
      method: 'POST',
      headers: { apikey: this.config.anonKey, Authorization: `Bearer ${await this.token()}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    if (res.status === 404) throw new Error("This sync server can't delete accounts yet. Its owner needs to run the newest web/supabase/schema.sql.");
    if (!res.ok) throw new Error(`Couldn't delete the account: ${res.status} ${await res.text()}`);
    this.signOut();
  }

  private async token(): Promise<string> {
    if (!this.session) throw new Error('Not signed in');
    if (Date.now() > this.session.expiresAt - 60_000) {
      try {
        await this.auth('token?grant_type=refresh_token', { refresh_token: this.session.refreshToken });
      } catch (e) {
        // A revoked or expired refresh token never recovers: sign out instead of retrying forever.
        if (e instanceof AuthError && e.status >= 400 && e.status < 500) { this.signOut(); throw new Error('Signed out — sign in again'); }
        throw e;
      }
    }
    return this.session!.accessToken;
  }

  private async rest<T>(method: string, query: string, body?: unknown, prefer?: string): Promise<T> {
    const headers: Record<string, string> = {
      apikey: this.config.anonKey, Authorization: `Bearer ${await this.token()}`, 'Content-Type': 'application/json',
    };
    if (prefer) headers.Prefer = prefer;
    const res = await fetch(`${this.base()}/rest/v1/${TABLE}?${query}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    if (res.status === 401) { this.signOut(); throw new Error('Signed out — sign in again'); }
    if (!res.ok) throw new Error(`Sync server: ${res.status} ${await res.text()}`);
    return res.status === 204 ? (undefined as T) : res.json();
  }

  heads() { return this.rest<RemoteHead[]>('GET', 'select=id,rev,deleted'); }

  async fetch(id: UUID): Promise<RemoteRow | undefined> {
    const rows = await this.rest<RemoteRow[]>('GET', `select=*&id=eq.${encodeURIComponent(id)}`);
    return rows[0];
  }

  async insert(row: Omit<RemoteRow, 'updated_at'>): Promise<boolean> {
    try {
      await this.rest('POST', 'select=id', row, 'return=minimal');
      return true;
    } catch (e) {
      if (String(e).includes('409') || String(e).includes('23505')) return false; // already exists
      throw e;
    }
  }

  /// Compare-and-swap: only writes when the server is still at `expectedRev`. Returns false on conflict.
  async update(id: UUID, expectedRev: number, patch: Partial<RemoteRow>): Promise<boolean> {
    const rows = await this.rest<RemoteHead[]>('PATCH', `id=eq.${encodeURIComponent(id)}&rev=eq.${expectedRev}&select=id,rev`,
      { ...patch, rev: expectedRev + 1, updated_at: new Date().toISOString() }, 'return=representation');
    return rows.length === 1;
  }
}
