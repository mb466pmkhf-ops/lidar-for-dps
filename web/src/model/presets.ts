// The user's own lighting presets ("my presets"): a saved arrangement of units to drop in again with
// one click. Units are kept relative to an anchor, either a person (seen from the camera) or a
// window, and are placed and levelled again for the new scene when used. A starting point like the
// built-in setups; levels are estimates.
// Port of FrameScout/Core/Models/LightingPresets.swift: keep the fields, maths and wording the same.
import type { ExposureSettings, FloorPlan, LightFixture, PlanPoint, PlanSegment, PrevisCharacter, UUID } from './types';
import { DEFAULT_WINDOW_TRANSMISSION, at, bearingFrom, buildScene, direction, planAdd, planDist, planScale, planSub, reading, solveOutput, unitBearing, worldBearing, type Vec } from './calculator';
import { KIND_INFO, fixtureProfile } from './photometrics';
import { eyeHeight } from './characters';
import { keyLux } from './exposure';
import { uuid } from './factory';
import { levelNote, room } from './setups';

export type PresetAnchor = 'person' | 'window';
export const ANCHOR_LABEL: Record<PresetAnchor, string> = { person: 'Round a person', window: 'At a window' };

export interface PresetUnit {
  /** The saved unit: fixture, modifier, colour, gels, barn doors. Where it stands, its aim and level
   *  come from the fields below. */
  light: LightFixture;
  // Person anchor.
  /** Degrees from the camera direction, seen from the person (+ = the key's side). */
  angle: number;
  /** Metres from the person (shortened if a wall is in the way). */
  distance: number;
  /** Height above the person's eyes (m). */
  rise: number;
  // Window anchor.
  /** Metres along the window from its centre (+ = right, standing inside facing the window). */
  along: number;
  /** Metres out from the glass (+ = outside, − = inside the room). */
  out: number;
  /** Height above the floor (m). */
  height: number;
  // Both.
  /** Pan relative to "aimed at the person" (person) or "aimed straight in" (window). */
  panOffset: number;
  /** Tilt in degrees; absent aims at the person's face (person anchor only). */
  tilt?: number;
  /** Level against the camera's key: 0 = at the set stop, 2 = two stops under, −1 = one over.
   *  Absent keeps the saved dimmer. */
  stopsUnderKey?: number;
}

export interface LightingPreset {
  id: UUID; name: string; anchor: PresetAnchor;
  /** Person presets: false puts the key on whichever side has more room, like the built-in setups;
   *  true keeps the sides exactly as saved. */
  keepSides: boolean;
  units: PresetUnit[];
}

export interface PresetResult { lights: LightFixture[]; notes: string[] }

const wrap180 = (d: number) => { let a = d % 360; if (a > 180) a -= 360; if (a <= -180) a += 360; return a; };
const wrap360 = (d: number) => { const a = d % 360; return a < 0 ? a + 360 : a; };
const round1 = (v: number) => Math.round(v * 10) / 10 + 0; // + 0 turns −0 into 0, which JSON keeps the same
const round2 = (v: number) => Math.round(v * 100) / 100 + 0;
const unitVec = (a: Vec): Vec => { const l = Math.hypot(a.x, a.y, a.z) || 1; return { x: a.x / l, y: a.y / l, z: a.z / l }; };
const emits = (l: LightFixture) => KIND_INFO[l.kind].emits;
/** Back and edge lights are metered facing the unit, the rest towards camera. */
export const isRim = (u: PresetUnit) => Math.abs(u.angle) > 100;

export function emptyUnit(light: LightFixture): PresetUnit {
  return { light, angle: 0, distance: 2, rise: 0.5, along: 0, out: 0, height: 1.5, panOffset: 0 };
}

/** One part per unit, for lists: "Key 45° · Fill −40° …". */
export function presetSummary(p: LightingPreset): string {
  return p.units.map(u => p.anchor === 'person' ? `${u.light.name} ${Math.round(u.angle)}°` : `${u.light.name} ${u.out > 0 ? 'outside' : 'inside'}`).join(' · ');
}

/** The unit as stored: no id, place, aim or scan; the person's name taken off its label. */
function template(light: LightFixture, person?: string): LightFixture {
  const t: LightFixture = { ...light, id: uuid(), position: { x: 0, z: 0 }, pan: 0 };
  delete t.scanID;
  if (person && t.name.endsWith(` · ${person}`)) t.name = t.name.slice(0, -(person.length + 3));
  return t;
}

/** Mirror across the camera axis: angles, aim and the barn doors swap sides. */
function mirrored(u: PresetUnit): PresetUnit {
  const light = u.light.barnDoors ? { ...u.light, barnDoors: { ...u.light.barnDoors, left: u.light.barnDoors.right, right: u.light.barnDoors.left } } : u.light;
  return { ...u, light, angle: -u.angle, panOffset: -u.panOffset };
}

// MARK: Windows

/** Centroid used to decide which side of a wall is "outside" (FloorPlan.interiorCentroid). */
function interiorCentroid(plan: FloorPlan): PlanPoint {
  const pts = plan.floorPolygons.flat();
  const source = pts.length ? pts : plan.walls.flatMap(w => [w.a, w.b]);
  if (!source.length) return { x: (plan.bounds.minX + plan.bounds.maxX) / 2, z: (plan.bounds.minZ + plan.bounds.maxZ) / 2 };
  const sum = source.reduce((s, p) => planAdd(s, p), { x: 0, z: 0 });
  return planScale(sum, 1 / source.length);
}
const midpoint = (s: PlanSegment): PlanPoint => ({ x: (s.a.x + s.b.x) / 2, z: (s.a.z + s.b.z) / 2 });

/** Outward-facing bearing of a window, pointing away from the room (FloorPlan.outwardBearing). */
export function outwardBearing(plan: FloorPlan, s: PlanSegment): number {
  const d = planSub(s.b, s.a);
  let n = { x: -d.z, z: d.x };
  const toCentre = planSub(interiorCentroid(plan), midpoint(s));
  if (n.x * toCentre.x + n.z * toCentre.z > 0) n = planScale(n, -1);
  return worldBearing(n);
}

function windowFrame(window: PlanSegment, plan: FloorPlan) {
  const out = outwardBearing(plan, window);
  return { centre: midpoint(window), outward: unitBearing(out), right: unitBearing(out + 90), inward: wrap360(out + 180) };
}

function closestOnSegment(a: PlanPoint, b: PlanPoint, p: PlanPoint): PlanPoint {
  const d = planSub(b, a), len2 = d.x * d.x + d.z * d.z;
  if (!(len2 > 1e-12)) return a;
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * d.x + (p.z - a.z) * d.z) / len2));
  return planAdd(a, planScale(d, t));
}

export function nearestWindow(p: PlanPoint, plan: FloorPlan): PlanSegment | undefined {
  let best: PlanSegment | undefined, bestD = Infinity;
  for (const w of plan.windows) { const d = planDist(closestOnSegment(w.a, w.b, p), p); if (d < bestD) { bestD = d; best = w; } }
  return best;
}

// MARK: Saving

/** Saves `lights` relative to `person`, seen from `camera` (absent: from the way they face). Each unit
 *  lit onto the face keeps its level as stops against the key, so it follows the stop when used
 *  again; the rest keep their dimmer. */
export function capturePersonPreset(name: string, lights: LightFixture[], person: PrevisCharacter, camera: PlanPoint | undefined,
  exposure: ExposureSettings, plan?: FloorPlan, windowTransmission = DEFAULT_WINDOW_TRANSMISSION): LightingPreset {
  const p = person.position;
  const towardCamera = camera ? bearingFrom(p, camera) : person.facing;
  const face = at(p, Math.max(0.3, eyeHeight(person) - 0.03));
  const scene = buildScene(lights, plan, windowTransmission);
  let units = lights.map(light => {
    const u = emptyUnit(template(light, person.name));
    const d = Math.max(0.1, planDist(p, light.position));
    u.angle = round1(wrap180(bearingFrom(p, light.position) - towardCamera));
    u.distance = round2(d);
    u.rise = round2(light.height - face.y);
    const pan = wrap180(light.pan - bearingFrom(light.position, p));
    u.panOffset = Math.abs(pan) < 3 ? 0 : round1(pan);
    const aimedTilt = -Math.atan2(light.height - face.y, d) * 180 / Math.PI;
    if (!(u.panOffset === 0 && Math.abs(light.tilt - aimedTilt) < 3)) u.tilt = round1(light.tilt);
    if (emits(light) && light.isOn) {
      const normal = isRim(u) ? unitVec({ x: light.position.x - face.x, y: light.height - face.y, z: light.position.z - face.z }) : direction(towardCamera, 0);
      const lux = reading(face, normal, scene).contributions.filter(c => c.lightID === light.id).reduce((s, c) => s + c.lux, 0);
      if (lux > 0.5) u.stopsUnderKey = round1(Math.log2(keyLux(exposure) / lux));
    }
    return u;
  });
  // Saved with the key on the + side, so it can be mirrored to whichever side has room.
  const key = units.find(u => u.light.role === 'key') ?? units.find(u => u.stopsUnderKey !== undefined) ?? units[0];
  if (key && key.angle < 0) units = units.map(mirrored);
  return { id: uuid(), name, anchor: 'person', keepSides: false, units };
}

/** Saves `lights` relative to `window`: along it, out from the glass and how high. */
export function captureWindowPreset(name: string, lights: LightFixture[], window: PlanSegment, plan: FloorPlan): LightingPreset {
  const f = windowFrame(window, plan);
  const units = lights.map(light => {
    const u = emptyUnit(template(light));
    const v = planSub(light.position, f.centre);
    u.along = round2(v.x * f.right.x + v.z * f.right.z);
    u.out = round2(v.x * f.outward.x + v.z * f.outward.z);
    u.height = round2(light.height);
    u.panOffset = round1(wrap180(light.pan - f.inward));
    u.tilt = round1(light.tilt);
    return u;
  });
  return { id: uuid(), name, anchor: 'window', keepSides: false, units };
}

// MARK: Using

/** Places the preset round `person`, seen from `camera` (absent: from the way they face), levelled
 *  for `exposure`. A window preset uses the window nearest the person. */
export function buildPreset(preset: LightingPreset, person: PrevisCharacter, camera: PlanPoint | undefined, exposure: ExposureSettings,
  plan?: FloorPlan, windowTransmission = DEFAULT_WINDOW_TRANSMISSION): PresetResult {
  if (preset.anchor === 'window') {
    const w = plan && nearestWindow(person.position, plan);
    if (!plan || !w) return { lights: [], notes: ['This preset needs a window in the plan'] };
    return buildPresetAtWindow(preset, w, plan, person.scanID);
  }
  const p = person.position;
  const towardCamera = camera ? bearingFrom(p, camera) : person.facing;
  const face = at(p, Math.max(0.3, eyeHeight(person) - 0.03));
  const faceNormal = direction(towardCamera, 0);
  const key = keyLux(exposure);
  const side = preset.keepSides ? 1 : room(p, towardCamera + 60, plan) >= room(p, towardCamera - 60, plan) ? 1 : -1;
  const lights: LightFixture[] = [], notes: string[] = [];
  for (const unit of preset.units) {
    const u = side < 0 ? mirrored(unit) : unit;
    const bearing = towardCamera + u.angle;
    const d = Math.min(u.distance, Math.max(0.6, room(p, bearing, plan) - 0.4));
    const pos = planAdd(p, planScale(unitBearing(bearing), d));
    const light: LightFixture = { ...u.light, id: uuid(), name: `${u.light.name} · ${person.name}`, position: pos,
      pan: wrap360(bearingFrom(pos, p) + u.panOffset), height: Math.max(0.3, face.y + u.rise) };
    light.tilt = u.tilt ?? -Math.atan2(light.height - face.y, d) * 180 / Math.PI;
    if (person.scanID) light.scanID = person.scanID; else delete light.scanID;
    if (u.stopsUnderKey !== undefined && emits(light)) {
      const target = key / Math.pow(2, u.stopsUnderKey);
      const normal = isRim(u) ? unitVec({ x: pos.x - face.x, y: light.height - face.y, z: pos.z - face.z }) : faceNormal;
      notes.push(levelNote(light, solveOutput(light, target, face, normal, [light], plan, windowTransmission), u.light.name, target));
    }
    lights.push(light);
  }
  return { lights, notes };
}

/** Places the preset at `window`, at the saved dimmer levels. */
export function buildPresetAtWindow(preset: LightingPreset, window: PlanSegment, plan: FloorPlan, scanID?: UUID): PresetResult {
  const f = windowFrame(window, plan);
  const lights: LightFixture[] = [], notes: string[] = [];
  for (const u of preset.units) {
    const light: LightFixture = { ...u.light, id: uuid(), position: planAdd(f.centre, planAdd(planScale(f.right, u.along), planScale(f.outward, u.out))),
      height: u.height, pan: wrap360(f.inward + u.panOffset), tilt: u.tilt ?? u.light.tilt };
    if (scanID) light.scanID = scanID; else delete light.scanID;
    if (emits(light)) notes.push(`${u.light.name}: ${fixtureProfile(light).name} at ${Math.round(light.dimmer * 100)} %, ${u.out > 0 ? 'outside' : 'inside'}`);
    lights.push(light);
  }
  return { lights, notes };
}

// MARK: Library file

/** Stored and shared as `{"framescanPresets":1,"presets":[…]}`, the same JSON as the phone. */
export function encodePresets(presets: LightingPreset[]): string {
  return JSON.stringify({ framescanPresets: 1, presets });
}

/** Reads a stored or shared list (one preset on its own works too); anything else gives undefined. */
export function decodePresets(text: string): LightingPreset[] | undefined {
  let v: unknown;
  try { v = JSON.parse(text.trim()); } catch { return undefined; }
  const list = Array.isArray((v as { presets?: unknown })?.presets) ? (v as { presets: unknown[] }).presets : [v];
  const ok = (p: unknown): p is LightingPreset => {
    const o = p as LightingPreset;
    return !!o && typeof o.name === 'string' && (o.anchor === 'person' || o.anchor === 'window') && Array.isArray(o.units)
      && o.units.every(u => u && typeof u.light === 'object' && typeof u.light.kind === 'string' && typeof u.angle === 'number');
  };
  if (!list.every(ok)) return undefined;
  return list.map(p => ({ ...p, id: typeof p.id === 'string' ? p.id : uuid(), keepSides: !!p.keepSides,
    units: p.units.map(u => ({ ...emptyUnit(u.light), ...u })) }));
}
