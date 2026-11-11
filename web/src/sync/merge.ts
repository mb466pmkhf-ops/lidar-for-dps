// Three-way merge of project JSON, used when the phone and another device both changed a project
// since they last synced. The Swift side (FrameScout/Core/Sync/SyncMerge.swift) implements the
// same rules; keep them in step.
//
// Rules, applied recursively from the project document down:
// - a side that didn't change since the base loses to the side that did;
// - objects merge key by key (a key removed on one side and untouched on the other is removed);
// - arrays whose elements all carry an `id` (locations, lights, shots, people, meters…) merge by
//   id: each item merges on its own, items added on either side are kept, an item deleted on one
//   side is deleted unless the other side changed it;
// - anything else changed on both sides (a single number, a list of tags) keeps the local value.
// - `modifiedAt` takes the later of the two.

export type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
type Obj = { [k: string]: Json };

export function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b || a === null || b === null || typeof a !== 'object') {
    return typeof a === 'number' && typeof b === 'number' && Math.abs(a - b) < 1e-9;
  }
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) {
    const bb = b as unknown[];
    return a.length === bb.length && a.every((v, i) => deepEqual(v, bb[i]));
  }
  const ka = Object.keys(a as object), kb = Object.keys(b as object);
  if (ka.length !== kb.length) return false;
  return ka.every(k => Object.prototype.hasOwnProperty.call(b, k) && deepEqual((a as Obj)[k], (b as Obj)[k]));
}

const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v);
const idOf = (v: Json): string | undefined => (isObj(v) && typeof v.id === 'string' ? v.id.toUpperCase() : undefined);
const isIdArray = (v: unknown): v is Obj[] => Array.isArray(v) && v.every(e => idOf(e as Json) !== undefined);

const MISSING = Symbol('missing');
type Maybe = Json | typeof MISSING;

function merge3(base: Maybe, local: Maybe, remote: Maybe): Maybe {
  if (deepEqual(local, remote)) return local;
  if (deepEqual(base, local)) return remote;
  if (deepEqual(base, remote)) return local;
  if (local === MISSING || remote === MISSING) {
    // Deleted on one side, changed on the other: keep the change.
    return local === MISSING ? remote : local;
  }
  if (isObj(local) && isObj(remote)) {
    const b = isObj(base) ? base : {};
    const out: Obj = {};
    const keys = new Set([...Object.keys(remote), ...Object.keys(local)]);
    for (const k of keys) {
      const v = k === 'modifiedAt'
        ? later(local[k], remote[k])
        : merge3(k in b ? b[k] : MISSING, k in local ? local[k] : MISSING, k in remote ? remote[k] : MISSING);
      if (v !== MISSING) out[k] = v;
    }
    return out;
  }
  if (isIdArray(local) && isIdArray(remote) && (base === MISSING || isIdArray(base))) {
    const index = (arr: Obj[]) => new Map(arr.map(e => [idOf(e)!, e] as const));
    const b = index(base === MISSING ? [] : (base as Obj[])), l = index(local), r = index(remote);
    const order: string[] = [];
    for (const id of r.keys()) order.push(id);
    for (const id of l.keys()) if (!r.has(id)) {
      // Insert local-only items after their local predecessor, so new items keep their place.
      const li = local.findIndex(e => idOf(e) === id);
      const prev = li > 0 ? idOf(local[li - 1]) : undefined;
      const at = prev ? order.indexOf(prev) : -1;
      order.splice(at + 1, 0, id);
    }
    const out: Json[] = [];
    for (const id of order) {
      const v = merge3(b.has(id) ? b.get(id)! : MISSING, l.has(id) ? l.get(id)! : MISSING, r.has(id) ? r.get(id)! : MISSING);
      if (v !== MISSING) out.push(v);
    }
    return out;
  }
  return local;
}

function later(a: Json | undefined, b: Json | undefined): Json {
  if (typeof a !== 'string') return b ?? null;
  if (typeof b !== 'string') return a;
  return Date.parse(a) >= Date.parse(b) ? a : b;
}

export function mergeDocuments<T>(base: T | undefined, local: T, remote: T): T {
  const v = merge3(base === undefined ? MISSING : (base as Json), local as Json, remote as Json);
  return (v === MISSING ? local : v) as T;
}

/// Plans are keyed by scan id. The phone writes ids in upper case; older web copies may not have.
export function upperKeys<T>(plans: Record<string, T>): Record<string, T> {
  const out: Record<string, T> = {};
  for (const [k, v] of Object.entries(plans)) out[k.toUpperCase()] = v;
  return out;
}
