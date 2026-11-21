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
/// The account whose projects are on this computer (its user id), so a different account signing in
/// later doesn't take them over.
const OWNER_KEY = 'framescan.sync.owner';

/// FrameScan's own sync server. The anon key is public by design: row-level security limits every
/// row to the account that owns it (web/supabase/schema.sql). Same values as CloudSync.builtIn on iOS.
export const BUILT_IN_SERVER: SyncConfig = {
  url: 'https://nuprvuipspqmhsczdqrk.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im51cHJ2dWlwc3BxbWhzY3pkcXJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5MTYzNDIsImV4cCI6MjEwOTQ5MjM0Mn0.tNQo2XqWI1krE3KMfzuRFzqXSz55eWdgnjgJQFK-jcY',
};
const DEVICE = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window ? 'desktop' : 'web';

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
  private syncing?: Promise<void>;
  private listening = false;
  private snapshot: Project[] = [];
  client?: SupabaseClient;
  state: SyncState = { kind: 'local' };
  loaded = false;
  /// Set when this browser refused to store a change (storage full or blocked). Shown in the top bar.
  saveError?: string;
  private failedSaves = new Set<UUID>();
  /// Projects the server refused on the last sync, with the reason. The other projects sync anyway.
  syncProblems = new Map<UUID, string>();

  constructor() {
    const config = readJSON<SyncConfig>(CONFIG_KEY) ?? defaultConfig();
    if (config) this.connect(config, readJSON<Session>(SESSION_KEY));
    if (typeof window !== 'undefined') {
      window.addEventListener('pagehide', () => this.flushSaves());
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') this.flushSaves(); });
    }
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
    // A debounced save still waiting would otherwise write the project back after it's gone.
    clearTimeout(this.saveTimers.get(id)); this.saveTimers.delete(id); this.pendingWrites.delete(id);
    if (e.rev === undefined) {
      this.entries.delete(id); void localStore.remove(id);
      this.clearFailedSave(id);
    }
    else { e.deleted = true; e.dirty = true; e.version++; this.persist(e, true); }
    this.emit();
    void this.sync();
  }

  private clearFailedSave(id: string) {
    if (this.failedSaves.delete(id) && this.failedSaves.size === 0) this.saveError = undefined;
  }

  private persist(e: Entry, now = false) {
    clearTimeout(this.saveTimers.get(e.id));
    const write = () => {
      this.saveTimers.delete(e.id);
      const { version: _v, ...stored } = e;
      // The warning stays until every project whose write failed has saved again.
      localStore.put(stored).then(
        () => {
          if (this.failedSaves.delete(e.id) && this.failedSaves.size === 0) { this.saveError = undefined; this.emit(); }
        },
        err => {
          // A write that fails after the project was removed has nothing left to warn about.
          if (this.entries.get(e.id) !== e) return;
          this.failedSaves.add(e.id);
          this.saveError = `Couldn't save on this device: ${err instanceof Error ? err.message : String(err)}`;
          this.emit();
        });
      if (e.dirty) void this.sync();
    };
    if (now) { this.pendingWrites.delete(e.id); write(); return; }
    this.pendingWrites.set(e.id, write);
    this.saveTimers.set(e.id, setTimeout(() => this.writeLater(e.id), 600));
  }

  private pendingWrites = new Map<UUID, () => void>();
  private writeLater(id: UUID) { const w = this.pendingWrites.get(id); this.pendingWrites.delete(id); w?.(); }

  /// Writes every edit still waiting for its debounce. Called when the page is hidden or closed, so
  /// an edit made just before closing the tab or the desktop window isn't lost.
  flushSaves() {
    for (const id of [...this.saveTimers.keys()]) { clearTimeout(this.saveTimers.get(id)); this.writeLater(id); }
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
    const owner = this.client?.session?.userID;
    const previous = readJSON<string>(OWNER_KEY);
    const otherAccount = previous !== undefined && owner !== undefined && previous !== owner;
    for (const e of [...this.entries.values()]) {
      if (e.deleted) { this.forget(e.id); continue; }
      // Another account's projects that are safely on the server (its session ran out, nobody signed
      // out) leave this computer instead of moving into this account. Unsent changes stay: they'd
      // only exist here.
      if (otherAccount && e.rev !== undefined && !e.dirty) { this.forget(e.id); continue; }
      e.rev = undefined; e.base = undefined; e.dirty = true; e.version++;
      this.persist(e, true);
    }
    writeJSON(OWNER_KEY, owner);
    this.emit();
    await this.sync();
  }

  /// Drops a project from this computer only (memory, storage and any save still waiting).
  private forget(id: UUID) {
    clearTimeout(this.saveTimers.get(id)); this.saveTimers.delete(id); this.pendingWrites.delete(id);
    this.entries.delete(id);
    this.syncProblems.delete(id);
    this.clearFailedSave(id);
    void localStore.remove(id);
  }

  /// Projects with changes the server doesn't have yet (a pending delete doesn't count: nothing is lost).
  unsyncedProjects(): string[] {
    return [...this.entries.values()].filter(e => e.dirty && !e.deleted).map(e => e.bundle.project.name || 'Untitled');
  }

  /**
   * Signs out and removes this account's projects from this computer, so whoever signs in here next
   * neither sees nor uploads them. They stay on the server and come back on the next sign-in.
   * Uploads waiting changes first; if some still haven't reached the server (offline, or the server
   * refused them) nothing happens unless `discardUnsynced`, and their names come back instead.
   */
  async signOut(opts: { discardUnsynced?: boolean } = {}): Promise<{ unsynced: string[] } | undefined> {
    const client = this.client;
    if (!client?.session) { client?.signOut(); return undefined; }
    if (!opts.discardUnsynced) {
      this.flushSaves();
      await this.syncing;        // one already running may have started before the last edit
      await this.sync();
      const unsynced = this.unsyncedProjects();
      if (unsynced.length) return { unsynced };
    }
    for (const id of [...this.entries.keys()]) this.forget(id);
    writeJSON(OWNER_KEY, undefined);
    client.signOut();
    this.emit();
    return undefined;
  }

  /** Deletes the account on the server. Projects on this device are kept and upload again only
   *  if someone signs in to an account later. */
  async deleteAccount() {
    if (!this.client?.session) throw new Error('Not signed in');
    await this.client.deleteAccount();
    // Their rows are gone with the account: from now on these are this computer's own projects.
    for (const e of [...this.entries.values()]) {
      if (e.deleted) { this.forget(e.id); continue; }
      e.rev = undefined; e.base = undefined; e.dirty = true; e.version++;
      this.persist(e, true);
    }
    this.syncProblems.clear();
    writeJSON(OWNER_KEY, undefined);
    this.emit();
  }

  private setState(s: SyncState) { this.state = s; this.emit(); }

  // MARK: Sync

  sync(): Promise<void> {
    if (this.syncing) return this.syncing;
    const client = this.client;
    if (!client?.session || !this.loaded) return Promise.resolve();
    this.syncing = this.runSync(client).finally(() => { this.syncing = undefined; this.emit(); });
    return this.syncing;
  }

  private async runSync(client: SupabaseClient): Promise<void> {
    // A known problem with one project stays on show while the next round runs (no flicker).
    if (this.state.kind !== 'synced' && !(this.state.kind === 'error' && this.syncProblems.size)) this.setState({ kind: 'syncing' });
    if (client.session && readJSON<string>(OWNER_KEY) === undefined) writeJSON(OWNER_KEY, client.session.userID);
    // One project the server refuses (too large, a row it can't take) must not hold up the others:
    // its error is kept against it and the loop moves on. Losing the connection or the sign-in
    // still stops the whole run, since every other request would fail the same way.
    const problems = new Map<UUID, string>();
    const each = async (id: UUID, step: () => Promise<void>) => {
      try { await step(); } catch (err) {
        if (stopsEverything(err, client)) throw err;
        problems.set(id, plainReason(err));
      }
    };
    try {
      const heads = await client.heads();
      for (const head of heads) {
        const id = head.id;
        const local = this.entries.get(id);
        if (head.deleted) {
          // Deleted here and on the server too: nothing left to send.
          if (local?.deleted) { this.entries.delete(id); await localStore.remove(id); continue; }
          if (local && !local.dirty) { this.entries.delete(id); await localStore.remove(id); }
          continue;
        }
        if (local && local.rev === head.rev) continue;
        await each(id, async () => { const row = await client.fetch(id); if (row) this.absorb(row); });
      }
      for (const e of [...this.entries.values()]) if (e.dirty) await each(e.id, () => this.push(client, e));
      this.syncProblems = problems;
      if (problems.size) this.setState({ kind: 'error', message: this.problemSummary() });
      else this.setState({ kind: 'synced', at: Date.now() });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (isOffline(message)) this.setState({ kind: 'offline', message: 'Offline — changes are saved here and will sync later' });
      else if (!client.session) this.setState({ kind: 'signedOut' });
      else this.setState({ kind: 'error', message });
    }
  }

  /// "“Big shoot” couldn't sync: too large for the sync server. Everything else is up to date."
  private problemSummary(): string {
    const named = [...this.syncProblems].map(([id, why]) => `“${this.entries.get(id)?.bundle.project.name || 'Untitled'}” couldn't sync: ${why}`);
    const shown = named.slice(0, 3).join(' ');
    const more = named.length > 3 ? ` (and ${named.length - 3} more)` : '';
    return `${shown}${more} Everything else is up to date.`;
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
      if (this.entries.get(e.id) !== e) {
        // A new copy with the same id took its place (imported again): leave it alone. It uploads,
        // meets this row and merges with it like any other conflict.
        if (this.entries.has(e.id)) return;
        // Removed here while its first upload was on the way: the row exists now, so delete it there.
        e.rev = rev; e.deleted = true; e.dirty = true; e.version++;
        this.entries.set(e.id, e);
        this.persist(e, true);
        return;
      }
      e.base = bundle; e.rev = rev;
      if (e.version === version) e.dirty = false;
      this.persist(e, true);
    };
    if (e.deleted) {
      if (e.rev === undefined || await client.update(e.id, e.rev, { deleted: true })) {
        // A copy re-added under the same id while the delete was on the way stays: it uploads and
        // meets the deleted row like any other conflict.
        if (this.entries.get(e.id) !== e) return;
        this.entries.delete(e.id);
        this.clearFailedSave(e.id);
        await localStore.remove(e.id);
      }
      return;
    }
    const doc = bundle.project;
    if (e.rev === undefined) {
      const ok = await client.insert({ id: e.id, name: doc.name, doc, plans: bundle.plans, rev: 1, deleted: false, updated_by: DEVICE });
      if (ok) done(1);
      else {
        const row = await client.fetch(e.id);
        if (row) { if (!this.entries.has(e.id)) done(row.rev); else this.absorb(row); }
      }
      return;
    }
    const patch: Partial<RemoteRow> = { name: doc.name, doc, deleted: false, updated_by: DEVICE };
    if (!deepEqual(bundle.plans, e.base?.plans)) patch.plans = bundle.plans;
    if (await client.update(e.id, e.rev, patch)) done(e.rev + 1);
    else { const row = await client.fetch(e.id); if (row) this.absorb(row); }
  }
}

function isOffline(message: string) {
  return (typeof navigator !== 'undefined' && navigator.onLine === false) || /Failed to fetch|NetworkError|Load failed/i.test(message);
}

/// Errors that would fail every other project too: no connection, or no longer signed in.
function stopsEverything(err: unknown, client: SupabaseClient) {
  return !client.session || isOffline(err instanceof Error ? err.message : String(err));
}

/// The server's answer for one project, in plain words where we know it.
function plainReason(err: unknown): string {
  const message = err instanceof Error ? err.message : String(err);
  // 23514: the size limits in web/supabase/schema.sql. 413: the request itself was too big.
  if (/\b(23514|413)\b|too large|payload/i.test(message)) return 'too large for the sync server. It stays saved on this device.';
  return message.endsWith('.') ? message : `${message}.`;
}

export const workspace = new Workspace();
