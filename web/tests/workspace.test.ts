import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// In-memory stand-in for IndexedDB.
const stored = new Map<string, unknown>();
vi.mock('../src/sync/localStore', () => ({
  localStore: {
    all: async () => [...stored.values()],
    put: async (p: { id: string }) => { stored.set(p.id, structuredClone(p)); },
    remove: async (id: string) => { stored.delete(id); },
  },
}));

import { Workspace } from '../src/sync/workspace';
import { newProject } from '../src/model/factory';
import type { SupabaseClient } from '../src/sync/supabase';

function offline() {
  const w = new Workspace();
  w.disconnect();
  return w;
}

describe('workspace saving and sync', () => {
  beforeEach(() => { stored.clear(); vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

  it('a project deleted before its edit was saved stays deleted', async () => {
    const w = offline();
    await w.load();
    const p = newProject('Test');
    w.add({ project: p, plans: {} });
    w.commit({ ...p, name: 'Renamed' });          // debounced save waiting
    w.remove(p.id);
    await vi.advanceTimersByTimeAsync(2000);
    expect(stored.has(p.id)).toBe(false);
  });

  it('flushSaves writes an edit still waiting for its debounce', async () => {
    const w = offline();
    await w.load();
    const p = newProject('Test');
    w.add({ project: p, plans: {} });
    await vi.advanceTimersByTimeAsync(0);
    w.commit({ ...p, name: 'Renamed' });
    w.flushSaves();
    await vi.advanceTimersByTimeAsync(0);
    expect((stored.get(p.id) as { bundle: { project: { name: string } } }).bundle.project.name).toBe('Renamed');
  });

  it('drops a local delete when the server has deleted the project too', async () => {
    const w = offline();
    const p = newProject('Gone');
    stored.set(p.id, { id: p.id, bundle: { project: p, plans: {} }, base: { project: p, plans: {} }, rev: 3, dirty: true, deleted: true });
    const update = vi.fn(async () => false);
    w.client = {
      session: { accessToken: 'a', refreshToken: 'r', expiresAt: Date.now() + 1e6, userID: 'u', email: 'e' },
      heads: async () => [{ id: p.id, rev: 4, deleted: true }],
      fetch: async () => undefined,
      update,
    } as unknown as SupabaseClient;
    await w.load();
    await vi.advanceTimersByTimeAsync(0);
    await w.sync();
    expect(stored.has(p.id)).toBe(false);
    expect(w.hasPendingChanges()).toBe(false);
    expect(update).not.toHaveBeenCalled();
  });

  it('shows when the browser refuses to store a change', async () => {
    const w = offline();
    await w.load();
    const { localStore } = await import('../src/sync/localStore');
    const put = vi.spyOn(localStore, 'put').mockRejectedValueOnce(new Error('QuotaExceededError'));
    const p = newProject('Big');
    w.add({ project: p, plans: {} });
    await vi.advanceTimersByTimeAsync(0);
    expect(w.saveError).toMatch(/QuotaExceededError/);
    put.mockRestore();
  });

  it('a project removed while its first upload was on the way is deleted on the server next', async () => {
    const w = offline();
    await w.load();
    const p = newProject('Short-lived');
    let release!: () => void;
    const update = vi.fn(async () => true);
    w.client = {
      session: { accessToken: 'a', refreshToken: 'r', expiresAt: Date.now() + 1e6, userID: 'u', email: 'e' },
      heads: async () => [],
      fetch: async () => undefined,
      insert: () => new Promise<boolean>(r => { release = () => r(true); }),
      update,
    } as unknown as SupabaseClient;
    w.add({ project: p, plans: {} });
    await vi.advanceTimersByTimeAsync(0);   // adding it starts a sync; its insert now waits
    expect(release).toBeTypeOf('function');
    w.remove(p.id);                         // while the insert is waiting
    release();
    await vi.advanceTimersByTimeAsync(0);
    await w.sync();
    expect(update).toHaveBeenCalledWith(p.id, 1, { deleted: true });
    expect(stored.has(p.id)).toBe(false);
  });

  it('a copy re-added while its old delete is on the way is kept', async () => {
    const w = offline();
    const p = newProject('Back again');
    stored.set(p.id, { id: p.id, bundle: { project: p, plans: {} }, base: { project: p, plans: {} }, rev: 2, dirty: true, deleted: true });
    let release!: () => void;
    w.client = {
      session: { accessToken: 'a', refreshToken: 'r', expiresAt: Date.now() + 1e6, userID: 'u', email: 'e' },
      heads: async () => [],
      fetch: async () => undefined,
      insert: async () => false,
      update: () => new Promise<boolean>(r => { release = () => r(true); }),
    } as unknown as SupabaseClient;
    await w.load();
    const running = w.sync();
    await vi.advanceTimersByTimeAsync(0);   // the delete's update now waits
    expect(release).toBeTypeOf('function');
    w.add({ project: { ...p, name: 'Re-imported' }, plans: {} });
    release();
    await running;
    await vi.advanceTimersByTimeAsync(0);
    expect(w.bundle(p.id)?.project.name).toBe('Re-imported');
    expect(stored.has(p.id)).toBe(true);
  });

  it('keeps the save warning until every failed project has saved', async () => {
    const w = offline();
    await w.load();
    const { localStore } = await import('../src/sync/localStore');
    const put = vi.spyOn(localStore, 'put').mockRejectedValueOnce(new Error('full'));
    const a = newProject('A'), b = newProject('B');
    w.add({ project: a, plans: {} });
    await vi.advanceTimersByTimeAsync(0);
    w.add({ project: b, plans: {} });
    await vi.advanceTimersByTimeAsync(0);
    expect(w.saveError).toMatch(/full/);
    w.commit({ ...a, name: 'A2' });
    w.flushSaves();
    await vi.advanceTimersByTimeAsync(0);
    expect(w.saveError).toBeUndefined();
    put.mockRestore();
  });

  const session = () => ({ accessToken: 'a', refreshToken: 'r', expiresAt: Date.now() + 1e6, userID: 'u1', email: 'e' });

  it('one project the server refuses does not stop the others from syncing', async () => {
    const w = offline();
    await w.load();
    const big = newProject('Big shoot'), small = newProject('Small shoot');
    const inserted: string[] = [];
    w.client = {
      session: session(),
      heads: async () => [],
      fetch: async () => undefined,
      insert: async (row: { id: string }) => {
        if (row.id === big.id) throw new Error('Sync server: 400 {"code":"23514","message":"new row violates check constraint"}');
        inserted.push(row.id); return true;
      },
      update: async () => true,
    } as unknown as SupabaseClient;
    w.add({ project: big, plans: {} });
    w.add({ project: small, plans: {} });
    await vi.advanceTimersByTimeAsync(0);
    await w.sync();
    expect(inserted).toContain(small.id);
    expect(w.unsyncedProjects()).toEqual(['Big shoot']);
    expect(w.syncProblems.get(big.id)).toMatch(/too large/);
    expect(w.state.kind).toBe('error');
    expect(w.state.kind === 'error' && w.state.message).toMatch(/Big shoot/);
  });

  it('losing the connection still stops the whole run as offline', async () => {
    const w = offline();
    await w.load();
    const a = newProject('A'), b = newProject('B');
    const insert = vi.fn(async (_row: { id: string }) => { throw new TypeError('Failed to fetch'); });
    w.client = { session: session(), heads: async () => [], fetch: async () => undefined, insert, update: async () => true } as unknown as SupabaseClient;
    w.add({ project: a, plans: {} });
    w.add({ project: b, plans: {} });
    await vi.advanceTimersByTimeAsync(0);
    await w.sync();
    expect(w.state.kind).toBe('offline');
    // Each run gave up at the first project instead of trying every other one too.
    expect(insert.mock.calls.every(c => (c as unknown as [{ id: string }])[0].id === a.id)).toBe(true);
  });

  it('signing out removes the account\'s projects from this computer once they are uploaded', async () => {
    const w = offline();
    await w.load();
    const p = newProject('Mine');
    const client = {
      session: session() as ReturnType<typeof session> | undefined,
      heads: async () => [], fetch: async () => undefined, insert: async () => true, update: async () => true,
      signOut() { this.session = undefined; },
    };
    w.client = client as unknown as SupabaseClient;
    w.add({ project: p, plans: {} });
    w.commit({ ...p, name: 'Mine, edited' });   // still waiting for its debounce
    expect(await w.signOut()).toBeUndefined();
    await vi.advanceTimersByTimeAsync(0);
    expect(w.getProjects()).toEqual([]);
    expect(stored.size).toBe(0);
    expect(client.session).toBeUndefined();
  });

  it('signing out with changes the server does not have asks first', async () => {
    const w = offline();
    await w.load();
    const p = newProject('Offline edits');
    const client = {
      session: session() as ReturnType<typeof session> | undefined,
      heads: async () => [], fetch: async () => undefined,
      insert: async () => { throw new Error('Sync server: 500 boom'); }, update: async () => true,
      signOut() { this.session = undefined; },
    };
    w.client = client as unknown as SupabaseClient;
    w.add({ project: p, plans: {} });
    await vi.advanceTimersByTimeAsync(0);
    expect(await w.signOut()).toEqual({ unsynced: ['Offline edits'] });
    expect(client.session).toBeDefined();
    expect(stored.has(p.id)).toBe(true);
    await w.signOut({ discardUnsynced: true });
    await vi.advanceTimersByTimeAsync(0);
    expect(stored.size).toBe(0);
    expect(client.session).toBeUndefined();
  });

  it('a different account signing in does not take over the last account\'s synced projects', async () => {
    const theirs = newProject('Theirs'), unsent = newProject('Unsent');
    stored.set(theirs.id, { id: theirs.id, bundle: { project: theirs, plans: {} }, base: { project: theirs, plans: {} }, rev: 2, dirty: false });
    stored.set(unsent.id, { id: unsent.id, bundle: { project: unsent, plans: {} }, rev: undefined, dirty: true });
    const kept = new Map<string, string>([['framescan.sync.owner', JSON.stringify('u1')]]);
    vi.stubGlobal('localStorage', { getItem: (k: string) => kept.get(k) ?? null, setItem: (k: string, v: string) => kept.set(k, v), removeItem: (k: string) => kept.delete(k) });
    const w = offline();
    await w.load();
    const inserted: string[] = [];
    const client = {
      session: undefined as ReturnType<typeof session> | undefined,
      heads: async () => [], fetch: async () => undefined,
      insert: async (row: { id: string }) => { inserted.push(row.id); return true; }, update: async () => true,
      async signIn() { client.session = { ...session(), userID: 'u2' }; },
    };
    w.client = client as unknown as SupabaseClient;
    await w.signIn('b@example.com', 'password');
    await vi.advanceTimersByTimeAsync(0);
    expect(w.bundle(theirs.id)).toBeUndefined();
    expect(inserted).toEqual([unsent.id]);
    expect(JSON.parse(kept.get('framescan.sync.owner')!)).toBe('u2');
  });
});
