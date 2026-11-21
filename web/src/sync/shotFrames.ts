// Previs frames saved from the 3D look-through, one per shot. They are renders of the plan, not
// photographs, and they stay in this browser (IndexedDB) like listing photos: only the plan syncs.
// A separate database, so the projects store and its upgrade path are untouched.
import type { CameraRig } from '../model/types';

/** `rig` is the shot's camera as it was when the frame was saved, so the sheet can say when the shot
 *  has changed since (older frames have none). */
export interface ShotFrame { shotID: string; blob: Blob; lens: string; createdAt: string; rig?: CameraRig }

const DB = 'framescan-frames';
const STORE = 'frames';
let dbPromise: Promise<IDBDatabase> | undefined;

function db(): Promise<IDBDatabase> {
  return (dbPromise ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => { req.result.createObjectStore(STORE, { keyPath: 'shotID' }); };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  }));
}

function run<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T> | void): Promise<T | undefined> {
  return db().then(d => new Promise((resolve, reject) => {
    const t = d.transaction(STORE, mode);
    const req = fn(t.objectStore(STORE));
    t.oncomplete = () => resolve(req ? req.result : undefined);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error ?? new Error('Storage transaction aborted'));
  }));
}

const listeners = new Set<() => void>();

export const shotFrames = {
  put: (shotID: string, blob: Blob, lens: string, rig?: CameraRig) =>
    run('readwrite', s => { s.put({ shotID, blob, lens, rig, createdAt: new Date().toISOString() }); })
      .then(() => { listeners.forEach(f => f()); }),
  get: (shotID: string) => run<ShotFrame>('readonly', s => s.get(shotID) as IDBRequest<ShotFrame>),
  forShots: async (ids: string[]) => {
    const out = new Map<string, ShotFrame>();
    for (const id of ids) { const f = await shotFrames.get(id).catch(() => undefined); if (f) out.set(id, f); }
    return out;
  },
  remove: (shotID: string) => run('readwrite', s => s.delete(shotID)).then(() => { listeners.forEach(f => f()); }),
  /** Called after a frame is saved or removed, so an open print sheet can reload. */
  subscribe: (f: () => void) => { listeners.add(f); return () => { listeners.delete(f); }; },
};

/** The frame-lines rectangle inside a view: the shot's aspect ratio at 92 % of the width or height,
 *  matching the overlay drawn over the 3D look-through. */
export function frameRect(viewW: number, viewH: number, ratio: number) {
  const r = ratio > 0 ? ratio : 16 / 9;
  let w = viewW * 0.92, h = w / r;
  if (h > viewH * 0.92) { h = viewH * 0.92; w = h * r; }
  return { x: (viewW - w) / 2, y: (viewH - h) / 2, w, h };
}
