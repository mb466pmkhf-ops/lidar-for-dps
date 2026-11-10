// Offline-first storage in the browser (IndexedDB). Each project keeps the working copy, the copy
// last agreed with the server (the merge base) and the server revision it came from.
import type { ProjectBundle, UUID } from '../model/types';

export interface StoredProject {
  id: UUID;
  bundle: ProjectBundle;
  /// The bundle as last synced; undefined if never synced.
  base?: ProjectBundle;
  /// Server revision of `base`.
  rev?: number;
  /// Local edits not yet pushed.
  dirty: boolean;
  /// Deleted locally, waiting to tell the server.
  deleted?: boolean;
}

const DB = 'framescan';
const STORE = 'projects';

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => { req.result.createObjectStore(STORE, { keyPath: 'id' }); };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

let dbPromise: Promise<IDBDatabase> | undefined;
const db = () => (dbPromise ??= open());

function tx<T>(mode: IDBTransactionMode, run: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return db().then(d => new Promise<T>((resolve, reject) => {
    const t = d.transaction(STORE, mode);
    const req = run(t.objectStore(STORE));
    t.oncomplete = () => resolve(req.result);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error ?? new Error('Storage transaction aborted'));
  }));
}

export const localStore = {
  all: () => tx<StoredProject[]>('readonly', s => s.getAll() as IDBRequest<StoredProject[]>),
  put: (p: StoredProject) => tx('readwrite', s => s.put(p)).then(() => undefined),
  remove: (id: UUID) => tx('readwrite', s => s.delete(id)).then(() => undefined),
};
