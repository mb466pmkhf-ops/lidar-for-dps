// Named looks per room: a look is a saved copy of the room's lights ("Day", "Night", "Close-up").
// The room's `lights` stay the live set every reading and view works from; switching a look first
// writes the live lights back into the look you were on, then loads the other one. A shot can name
// the look it uses. Same rules as FrameScout/Core/Models/Looks.swift: keep both in step.
import type { LightFixture, Location, UUID } from './types';
import { uuid } from './factory';

export interface LightingLook { id: UUID; name: string; lights: LightFixture[]; scanID?: UUID; [key: string]: unknown }

const inScan = (scanID?: UUID) => (l: { scanID?: UUID }) => !l.scanID || !scanID || l.scanID === scanID;
const sameID = (a?: string, b?: string) => !!a && !!b && a.toUpperCase() === b.toUpperCase();

export const looksOf = (loc: Location, scanID?: UUID): LightingLook[] => ((loc.looks as LightingLook[] | undefined) ?? []).filter(inScan(scanID));
export const activeLook = (loc: Location, scanID?: UUID) => looksOf(loc, scanID).find(l => sameID(l.id, loc.activeLookID as string | undefined));

/** The live lights of this scan, copied so later edits don't reach the saved look. */
const snapshot = (loc: Location, scanID?: UUID) => structuredClone((loc.lights ?? []).filter(inScan(scanID)));

/** Writes the live lights back into the look you are on, so its edits are kept. */
function storeActive(loc: Location, scanID?: UUID): LightingLook[] {
  const all = (loc.looks as LightingLook[] | undefined) ?? [];
  const id = loc.activeLookID as string | undefined;
  return all.map(l => (sameID(l.id, id) && inScan(scanID)(l) ? { ...l, lights: snapshot(loc, scanID) } : l));
}

/** Saves the live lights as a new look and makes it the one you are on ("save as": the look you
 *  were on keeps what it had when you last switched to or saved it). */
export function saveLook(loc: Location, name: string, scanID?: UUID): Location {
  const look: LightingLook = { id: uuid(), name: name.trim() || `Look ${looksOf(loc, scanID).length + 1}`, lights: snapshot(loc, scanID), ...(scanID ? { scanID } : {}) };
  return { ...loc, looks: [...((loc.looks as LightingLook[] | undefined) ?? []), look], activeLookID: look.id };
}

/** Keeps the look you are on, then puts the other look's lights in the room. Lights of other scans stay. */
export function switchLook(loc: Location, id: UUID, scanID?: UUID): Location {
  const target = looksOf(loc, scanID).find(l => sameID(l.id, id));
  if (!target || sameID(id, loc.activeLookID as string | undefined)) return loc;
  const others = (loc.lights ?? []).filter(l => !inScan(scanID)(l));
  return { ...loc, looks: storeActive(loc, scanID), lights: [...others, ...structuredClone(target.lights)], activeLookID: target.id };
}

export function renameLook(loc: Location, id: UUID, name: string): Location {
  return { ...loc, looks: ((loc.looks as LightingLook[] | undefined) ?? []).map(l => (sameID(l.id, id) ? { ...l, name } : l)) };
}

/** Removes a saved look. The lights in the room stay as they are; shots that named it lose the link. */
export function deleteLook(loc: Location, id: UUID): Location {
  const looks = ((loc.looks as LightingLook[] | undefined) ?? []).filter(l => !sameID(l.id, id));
  const next: Location = { ...loc, looks: looks.length ? looks : undefined, shots: loc.shots.map(s => (sameID(s.lookID as string | undefined, id) ? { ...s, lookID: undefined } : s)) };
  if (sameID(loc.activeLookID as string | undefined, id)) next.activeLookID = undefined;
  if (!next.looks) delete next.looks;
  if (!next.activeLookID) delete next.activeLookID;
  for (const s of next.shots) if (s.lookID === undefined) delete s.lookID;
  return next;
}

/** Links a shot to a look (or clears it). */
export function setShotLook(loc: Location, shotID: UUID, lookID?: UUID): Location {
  return { ...loc, shots: loc.shots.map(s => { if (s.id !== shotID) return s; const n = { ...s }; if (lookID) n.lookID = lookID; else delete n.lookID; return n; }) };
}
