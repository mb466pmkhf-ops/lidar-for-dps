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
  afterEach(() => { vi.useRealTimers(); });

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
});
