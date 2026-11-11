// Reference photos added with "Build from a listing" on the web or desktop app. They stay in this
// browser (IndexedDB), like scan meshes stay on the phone: only the plan and the listing text sync.
// A separate database, so the projects store and its upgrade path are untouched.
export interface ListingPhoto { id: string; locationID: string; name: string; blob: Blob; createdAt: string }

const DB = 'framescan-photos';
const STORE = 'photos';
let dbPromise: Promise<IDBDatabase> | undefined;

function db(): Promise<IDBDatabase> {
  return (dbPromise ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => {
      const s = req.result.createObjectStore(STORE, { keyPath: 'id' });
      s.createIndex('location', 'locationID');
    };
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

export const listingPhotos = {
  add: (locationID: string, files: { name: string; blob: Blob }[]) =>
    run('readwrite', s => { for (const f of files) s.put({ id: crypto.randomUUID(), locationID, name: f.name, blob: f.blob, createdAt: new Date().toISOString() }); })
      .then(() => undefined),
  forLocation: (locationID: string) =>
    run<ListingPhoto[]>('readonly', s => s.index('location').getAll(locationID) as IDBRequest<ListingPhoto[]>).then(r => r ?? []),
  remove: (id: string) => run('readwrite', s => s.delete(id)).then(() => undefined),
};
