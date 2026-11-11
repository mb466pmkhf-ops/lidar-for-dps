// "My presets": the user's own lighting presets, kept in this browser (or desktop app). The same JSON
// as the phone, so a preset can be copied from one and pasted into the other.
import { useSyncExternalStore } from 'react';
import { decodePresets, encodePresets, type LightingPreset } from '../model/presets';

const KEY = 'framescan.presets';
let cache: LightingPreset[] | undefined;
const listeners = new Set<() => void>();

function load(): LightingPreset[] {
  if (cache) return cache;
  try { cache = decodePresets(localStorage.getItem(KEY) ?? '') ?? []; } catch { cache = []; }
  return cache;
}

export function savePresets(next: LightingPreset[]) {
  cache = next;
  try { localStorage.setItem(KEY, encodePresets(next)); } catch { /* private mode: kept for this visit */ }
  listeners.forEach(l => l());
}

export function usePresets(): LightingPreset[] {
  return useSyncExternalStore(cb => { listeners.add(cb); return () => listeners.delete(cb); }, load);
}

export const addPreset = (p: LightingPreset) => savePresets([...load(), p]);
export const updatePreset = (p: LightingPreset) => savePresets(load().map(x => (x.id === p.id ? p : x)));
export const removePreset = (id: string) => savePresets(load().filter(x => x.id !== id));
