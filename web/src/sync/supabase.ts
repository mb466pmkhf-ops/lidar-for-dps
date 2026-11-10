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

export class SupabaseClient {
  constructor(readonly config: SyncConfig, public session?: Session, private onSession?: (s?: Session) => void) {}

  private base() { return this.config.url.replace(/\/+$/, ''); }

  private async auth(path: string, body: unknown): Promise<Session> {
    const res = await fetch(`${this.base()}/auth/v1/${path}`, {
      method: 'POST',
      headers: { apikey: this.config.anonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(j.error_description || j.msg || j.message || `Sign-in failed (${res.status})`);
    if (!j.access_token) throw new Error('Check your email to confirm the account, then sign in.');
    const s: Session = {
      accessToken: j.access_token, refreshToken: j.refresh_token,
      expiresAt: Date.now() + (j.expires_in ?? 3600) * 1000, userID: j.user?.id, email: j.user?.email,
    };
    this.session = s;
    this.onSession?.(s);
    return s;
  }

  signIn(email: string, password: string) { return this.auth('token?grant_type=password', { email, password }); }
  signUp(email: string, password: string) { return this.auth('signup', { email, password }); }
  signOut() { this.session = undefined; this.onSession?.(undefined); }

  private async token(): Promise<string> {
    if (!this.session) throw new Error('Not signed in');
    if (Date.now() > this.session.expiresAt - 60_000) {
      await this.auth('token?grant_type=refresh_token', { refresh_token: this.session.refreshToken });
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
