// The app's data layer: projects in memory, persisted to IndexedDB, synced to Supabase when the
// user has signed in. Works fully offline; sync catches up when the connection is back.
import type { FloorPlan, Project, ProjectBundle, UUID } from '../model/types';
import { isoNow } from '../model/factory';
import { localStore, type StoredProject } from './localStore';
import { SupabaseClient, type OAuthProvider, type Session, type SyncConfig, type RemoteRow } from './supabase';
import { finishRedirect, startOAuth } from './oauth';
import { deepEqual, mergeDocuments, upperKeys } from './merge';

export type SyncState =
  | { kind: 'local' }                 // no sync set up
  | { kind: 'signedOut' }
  | { kind: 'syncing' }
  | { kind: 'synced'; at: number }
  | { kind: 'offline'; message: string }
  | { kind: 'error'; message: string };

type Entry = StoredProject & { version: number };

const CONFIG_KEY = 'framescan.sync.config';
const SESSION_KEY = 'framescan.sync.session';
const OFF_KEY = 'framescan.sync.off';

/// FrameScan's own sync server. The anon key is public by design: row-level security limits every
/// row to the account that owns it (web/supabase/schema.sql). Same values as CloudSync.builtIn on iOS.
export const BUILT_IN_SERVER: SyncConfig = {
  url: 'https://nuprvuipspqmhsczdqrk.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im51cHJ2dWlwc3BxbWhzY3pkcXJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5MTYzNDIsImV4cCI6MjEwOTQ5MjM0Mn0.tNQo2XqWI1krE3KMfzuRFzqXSz55eWdgnjgJQFK-jcY',
};
const DEVICE = typeof navigator !== 'undefined' && '__TAURI_INTERNALS__' in window ? 'desktop' : 'web';

function readJSON<T>(key: string): T | undefined {
  try { const v = localStorage.getItem(key); return v ? JSON.parse(v) as T : undefined; } catch { return undefined; }
}
function writeJSON(key: string, v: unknown) {
  try { if (v === undefined) localStorage.removeItem(key); else localStorage.setItem(key, JSON.stringify(v)); } catch { /* private mode */ }
}

/// Default server: VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY when set at build time, otherwise the
/// built-in one. Overridable under Sync → Server…, and absent once the user turns sync off.
export function defaultConfig(): SyncConfig | undefined {
  if (readJSON<boolean>(OFF_KEY)) return undefined;
  const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
  const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;
  return url && anonKey ? { url, anonKey } : BUILT_IN_SERVER;
}

export class Workspace {
  private entries = new Map<UUID, Entry>();
  private listeners = new Set<() => void>();
  private saveTimers = new Map<UUID, ReturnType<typeof setTimeout>>();
  private syncTimer?: ReturnType<typeof setInterval>;
  private syncing = false;
  private listening = false;
  private snapshot: Project[] = [];
  client?: SupabaseClient;
  state: SyncState = { kind: 'local' };
  loaded = false;

  constructor() {
    const config = readJSON<SyncConfig>(CONFIG_KEY) ?? defaultConfig();
    if (config) this.connect(config, readJSON<Session>(SESSION_KEY));
  }

  // MARK: Subscriptions (for useSyncExternalStore)

  subscribe = (fn: () => void) => { this.listeners.add(fn); return () => { this.listeners.delete(fn); }; };
  getProjects = () => this.snapshot;
  private emit() {
    this.snapshot = [...this.entries.values()].filter(e => !e.deleted).map(e => e.bundle.project)
      .sort((a, b) => Date.parse(b.modifiedAt) - Date.parse(a.modifiedAt));
    this.listeners.forEach(f => f());
  }

  async load() {
    for (const p of await localStore.all()) this.entries.set(p.id, { ...p, version: 0 });
    this.loaded = true;
    this.emit();
    void this.sync();
  }

  bundle(id: UUID): ProjectBundle | undefined { return this.entries.get(id)?.bundle; }
  hasPendingChanges() { return [...this.entries.values()].some(e => e.dirty); }

  // MARK: Edits

  /// Replaces a project with an edited copy. Marks it for upload.
  commit(project: Project) {
    const e = this.entries.get(project.id);
    if (!e) return;
    e.bundle = { ...e.bundle, project: { ...project, modifiedAt: isoNow() } };
    e.dirty = true;
    e.version++;
    this.persist(e);
    this.emit();
  }

  /// Like commit, for an edit that also adds or changes a scan's 2D plan (a room drawn by hand).
  commitBundle(bundle: ProjectBundle) {
    const e = this.entries.get(bundle.project.id);
    if (!e) return;
    e.bundle = { project: { ...bundle.project, modifiedAt: isoNow() }, plans: bundle.plans };
    e.dirty = true;
    e.version++;
    this.persist(e);
    this.emit();
  }

  /// Replaces one scan's 2D plan (doors, windows, set pieces edited by hand). Marks it for upload.
  commitPlan(projectID: UUID, scanID: UUID, plan: FloorPlan) {
    const e = this.entries.get(projectID);
    if (!e) return;
    const key = Object.keys(e.bundle.plans).find(k => k.toUpperCase() === scanID.toUpperCase()) ?? scanID.toUpperCase();
    e.bundle = { project: { ...e.bundle.project, modifiedAt: isoNow() }, plans: { ...e.bundle.plans, [key]: plan } };
    e.dirty = true;
    e.version++;
    this.persist(e);
    this.emit();
  }

  add(bundle: ProjectBundle) {
    const e: Entry = { id: bundle.project.id, bundle, dirty: true, version: 1 };
    this.entries.set(e.id, e);
    this.persist(e, true);
    this.emit();
  }

  remove(id: UUID) {
    const e = this.entries.get(id);
    if (!e) return;
    if (e.rev === undefined) { this.entries.delete(id); void localStore.remove(id); }
    else { e.deleted = true; e.dirty = true; e.version++; this.persist(e, true); }
    this.emit();
    void this.sync();
  }

  private persist(e: Entry, now = false) {
    clearTimeout(this.saveTimers.get(e.id));
    const write = () => {
      const { version: _v, ...stored } = e;
      void localStore.put(stored);
      if (e.dirty) void this.sync();
    };
    if (now) write(); else this.saveTimers.set(e.id, setTimeout(write, 600));
  }

  // MARK: Sync setup

  connect(config: SyncConfig, session?: Session) {
    writeJSON(CONFIG_KEY, config);
    writeJSON(OFF_KEY, undefined);
    this.client = new SupabaseClient(config, session, s => { writeJSON(SESSION_KEY, s); if (!s) this.setState({ kind: 'signedOut' }); });
    this.setState(session ? { kind: 'syncing' } : { kind: 'signedOut' });
    clearInterval(this.syncTimer);
    this.syncTimer = setInterval(() => { if (document.visibilityState === 'visible') void this.sync(); }, 5000);
    if (!this.listening && typeof window !== 'undefined') {
      this.listening = true;
      window.addEventListener('online', () => void this.sync());
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') void this.sync(); });
    }
  }

  disconnect() {
    clearInterval(this.syncTimer);
    this.client = undefined;
    writeJSON(CONFIG_KEY, undefined);
    writeJSON(SESSION_KEY, undefined);
    writeJSON(OFF_KEY, true);
    this.setState({ kind: 'local' });
  }

  private need(): SupabaseClient {
    if (!this.client) throw new Error('Set up sync first');
    return this.client;
  }

  async signIn(email: string, password: string) {
    await this.need().signIn(email, password);
    await this.afterSignIn();
  }

  /// 'confirm': the account exists but waits for its confirmation email (link or code).
  async createAccount(email: string, password: string): Promise<'signedIn' | 'confirm'> {
    const s = await this.need().signUp(email, password);
    if (!s) return 'confirm';
    await this.afterSignIn();
    return 'signedIn';
  }

  async verifyEmail(email: string, code: string) {
    await this.need().verifySignup(email, code);
    await this.afterSignIn();
  }

  resendConfirmation(email: string) { return this.need().resendSignup(email); }

  /// Apple or Google. On the web this leaves the page and finishes in completeRedirect.
  async signInWith(provider: OAuthProvider) {
    const s = await startOAuth(this.need(), provider);
    if (s) await this.afterSignIn();
  }

  /// Web: called once at start-up to pick up a sign-in the provider redirected back from.
  async completeRedirect() {
    if (this.client && await finishRedirect(this.client)) await this.afterSignIn();
  }

  // Revisions belong to the account (and server) they came from. After a sign-in every project
  // starts over: it is uploaded, or merged with the account's copy if one already exists.
  private async afterSignIn() {
    for (const e of this.entries.values()) {
      if (e.deleted) { this.entries.delete(e.id); void localStore.remove(e.id); continue; }
      e.rev = undefined; e.base = undefined; e.dirty = true; e.version++;
      this.persist(e, true);
    }
    this.emit();
    await this.sync();
  }

  signOut() { this.client?.signOut(); }

  private setState(s: SyncState) { this.state = s; this.emit(); }

  // MARK: Sync

  async sync(): Promise<void> {
    const client = this.client;
    if (!client?.session || this.syncing || !this.loaded) return;
    this.syncing = true;
    if (this.state.kind !== 'synced') this.setState({ kind: 'syncing' });
    try {
      const heads = await client.heads();
      for (const head of heads) {
        const id = head.id;
        const local = this.entries.get(id);
        if (head.deleted) {
          if (local && !local.dirty) { this.entries.delete(id); await localStore.remove(id); }
          continue;
        }
        if (local && local.rev === head.rev) continue;
        const row = await client.fetch(id);
        if (row) this.absorb(row);
      }
      for (const e of [...this.entries.values()]) if (e.dirty) await this.push(client, e);
      this.setState({ kind: 'synced', at: Date.now() });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (!navigator.onLine || /Failed to fetch|NetworkError|Load failed/i.test(message)) this.setState({ kind: 'offline', message: 'Offline — changes are saved here and will sync later' });
      else if (!client.session) this.setState({ kind: 'signedOut' });
      else this.setState({ kind: 'error', message });
    } finally {
      this.syncing = false;
      this.emit();
    }
  }

  /// Takes a server copy: replaces an unchanged local copy, or merges with local edits.
  private absorb(row: RemoteRow) {
    const remote: ProjectBundle = { project: row.doc, plans: upperKeys(row.plans ?? {}) };
    const local = this.entries.get(row.id);
    if (!local) {
      const e: Entry = { id: row.id, bundle: remote, base: remote, rev: row.rev, dirty: false, version: 0 };
      this.entries.set(row.id, e);
      this.persist(e, true);
      return;
    }
    if (local.dirty) {
      local.bundle = {
        project: mergeDocuments(local.base?.project, local.bundle.project, remote.project),
        // Plans merge like the project: set pieces, doors and windows by id, so a piece added on the
        // phone and one added here both survive (the phone's CloudSync does the same).
        plans: mergeDocuments(local.base ? upperKeys(local.base.plans) : undefined, upperKeys(local.bundle.plans), remote.plans),
      };
      local.version++;
    } else {
      local.bundle = remote;
    }
    local.base = remote;
    local.rev = row.rev;
    this.persist(local, true);
  }

  private async push(client: SupabaseClient, e: Entry) {
    const version = e.version;
    const bundle = e.bundle;
    const done = (rev: number) => {
      e.base = bundle; e.rev = rev;
      if (e.version === version) e.dirty = false;
      this.persist(e, true);
    };
    if (e.deleted) {
      if (e.rev === undefined || await client.update(e.id, e.rev, { deleted: true })) {
        this.entries.delete(e.id);
        await localStore.remove(e.id);
      }
      return;
    }
    const doc = bundle.project;
    if (e.rev === undefined) {
      const ok = await client.insert({ id: e.id, name: doc.name, doc, plans: bundle.plans, rev: 1, deleted: false, updated_by: DEVICE });
      if (ok) done(1);
      else { const row = await client.fetch(e.id); if (row) this.absorb(row); }
      return;
    }
    const patch: Partial<RemoteRow> = { name: doc.name, doc, deleted: false, updated_by: DEVICE };
    if (!deepEqual(bundle.plans, e.base?.plans)) patch.plans = bundle.plans;
    if (await client.update(e.id, e.rev, patch)) done(e.rev + 1);
    else { const row = await client.fetch(e.id); if (row) this.absorb(row); }
  }
}

export const workspace = new Workspace();
