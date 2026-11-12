// Studio builds, daylight and window dressing. Port of FrameScout/Core/Models/Stage.swift: same ids,
// same numbers, same rules (tests on both sides, parity in CI). See Docs/DECISIONS.md D-014.
//
// - A studio backdrop (cyc, chroma screen, paper roll or LED wall) stands against one wall or runs
//   on round several (a corner cyc, a U, an LED volume), and the floor can be given a finish. Only the LED wall gives light in the readings; the others are
//   surfaces, and the readings don't include light bouncing off surfaces.
// - Daylight: a sun and a sky outside the windows, from the location's clock (when the scan knows
//   north and the location has coordinates) or set by hand. Levels come from the IES daylight
//   availability model for a clear, hazy or overcast sky. Estimates: no buildings or trees outside,
//   a uniform sky, and no light reflected round the room.
// - Curtains on a window: sheer passes about half the light and turns sun into a soft glow, blackout
//   passes none.
import type { FloorPlan, Location, PlanPoint, PlanSegment, ScanRecord, UUID } from './types';
import { solarPosition } from './solar';

// MARK: Settings stored on the location (all optional, so older files load)

export type SkyKind = 'clear' | 'hazy' | 'overcast';
export interface DaylightSetup {
  isOn?: boolean;
  sky?: SkyKind;
  /** Place the sun from `time` and the location's coordinates (needs the scan's north). */
  fromClock?: boolean;
  /** Seconds since 1970 (UTC). */
  time?: number;
  /** Set by hand: where the sun is, as a bearing on the plan (0 = plan up, clockwise), and its height. */
  sunBearing?: number;
  sunElevation?: number;
}

export interface StudioSetup {
  /** BACKDROPS id; absent = no backdrop. */
  backdrop?: string;
  /** The wall it stands against; absent = the wall facing the camera (or the longest). */
  wallID?: UUID;
  /** Metres from the wall's middle, along the wall. Absent = centred, or into the corner it shares
   *  with another backdrop wall. */
  offset?: number;
  width?: number;
  height?: number;
  /** Paint or paper colour for the "colour" backdrops, #rrggbb. */
  colour?: string;
  /** LED wall: average brightness of what it shows, cd/m² (nits). */
  nits?: number;
  /** LED wall: white point of the content, K (3D colour only; the readings are lux). */
  kelvin?: number;
  /** FLOORS id; absent = as scanned or drawn. */
  floor?: string;
  floorColour?: string;
  /** The same backdrop carried on round more walls (a corner, a U). Each piece has its own width and
   *  place along its wall; where two pieces meet in a corner they join (a cyc curves round it). */
  moreWalls?: BackdropWall[];
}

/** One more wall a backdrop runs on (see `StudioSetup.moreWalls`). */
export interface BackdropWall {
  wallID: UUID;
  /** As `StudioSetup.offset` and `.width`, for this wall. */
  offset?: number;
  width?: number;
}

export type CurtainKind = 'sheer' | 'blackout';

// MARK: Catalogues

export type BackdropKind = 'cyc' | 'paper' | 'led';
export interface BackdropInfo {
  id: string; label: string; kind: BackdropKind;
  colour: string;
  /** Rough share of light the surface reflects (shown as a guide; not in the readings). */
  reflectance: number;
  /** Lets the user pick the colour. */
  pickColour?: boolean;
  note: string;
}

export const BACKDROPS: BackdropInfo[] = [
  { id: 'cyc-white', label: 'White cyc', kind: 'cyc', colour: '#f1f1ee', reflectance: 0.85, note: 'Curves into the floor, so there is no line where wall meets floor.' },
  { id: 'cyc-black', label: 'Black cyc', kind: 'cyc', colour: '#151515', reflectance: 0.04, note: 'Matt black. Takes light without giving much back.' },
  { id: 'cyc-green', label: 'Green screen', kind: 'cyc', colour: '#3a9b4c', reflectance: 0.3, note: 'Chroma green. Keep it evenly lit and keep people a few metres off it to cut spill.' },
  { id: 'cyc-blue', label: 'Blue screen', kind: 'cyc', colour: '#2a54b0', reflectance: 0.18, note: 'Chroma blue. Spills less than green, needs more light.' },
  { id: 'cyc-colour', label: 'Painted cyc', kind: 'cyc', colour: '#c8b9a0', reflectance: 0.5, pickColour: true, note: 'Any paint colour.' },
  { id: 'led-wall', label: 'LED wall', kind: 'led', colour: '#0d0f12', reflectance: 0.03, note: 'Gives light: it counts in the readings at the brightness you set.' },
  { id: 'paper-white', label: 'White paper roll', kind: 'paper', colour: '#f4f4f1', reflectance: 0.85, note: 'Seamless paper on two stands and a crossbar, swept onto the floor.' },
  { id: 'paper-grey', label: 'Mid-grey paper roll', kind: 'paper', colour: '#8d8d8b', reflectance: 0.18, note: 'About an 18 % grey card.' },
  { id: 'paper-black', label: 'Black paper roll', kind: 'paper', colour: '#1a1a1a', reflectance: 0.05, note: '' },
  { id: 'paper-colour', label: 'Colour paper roll', kind: 'paper', colour: '#3c6e8f', reflectance: 0.3, pickColour: true, note: 'Pick the colour.' },
];

export interface FloorInfo { id: string; label: string; colour: string; reflectance: number; roughness: number; pickColour?: boolean }
export const FLOORS: FloorInfo[] = [
  { id: 'concrete-grey', label: 'Grey concrete', colour: '#8f8c87', reflectance: 0.25, roughness: 0.8 },
  { id: 'concrete-black', label: 'Black concrete', colour: '#262626', reflectance: 0.06, roughness: 0.55 },
  { id: 'concrete-colour', label: 'Painted concrete', colour: '#6b7f73', reflectance: 0.2, roughness: 0.6, pickColour: true },
  { id: 'painted-white', label: 'White painted floor', colour: '#ecebe7', reflectance: 0.8, roughness: 0.5 },
];

export const backdropInfo = (id?: string) => BACKDROPS.find(b => b.id === id);
export const floorInfo = (id?: string) => FLOORS.find(f => f.id === id);

/** Standard seamless paper width (m). */
export const PAPER_WIDTH = 2.72;
export const LED_DEFAULT_NITS = 300;
export const LED_NITS_RANGE = { min: 10, max: 2000 };
/** How far each kind stands off its wall (m). */
const STANDOFF: Record<BackdropKind, number> = { cyc: 0.02, paper: 0.35, led: 0.15 };
/** How far a cyc or paper sweeps onto the floor (m). */
export const SWEEP: Record<BackdropKind, number> = { cyc: 1.5, paper: 2.0, led: 0 };

export const SHEER_TRANSMISSION = 0.5;
export const curtainPass = (c?: CurtainKind) => (c === 'sheer' ? SHEER_TRANSMISSION : c === 'blackout' ? 0 : 1);
export const CURTAIN_LABEL: Record<CurtainKind, string> = { sheer: 'Sheer', blackout: 'Blackout' };

// MARK: Daylight levels (IES daylight availability model)

/** IES Lighting Handbook coefficients: extinction for the direct sun, and the sky's horizontal
 *  illuminance A + B·sin(α)^C in kilolux. */
export const SKY: Record<SkyKind, { label: string; extinction: number; a: number; b: number; c: number }> = {
  clear: { label: 'Clear', extinction: 0.21, a: 0.8, b: 15.5, c: 0.5 },
  hazy: { label: 'Hazy, some cloud', extinction: 0.8, a: 0.3, b: 45.0, c: 1.0 },
  overcast: { label: 'Overcast', extinction: Infinity, a: 0.3, b: 21.0, c: 1.0 },
};
/** Sunlight above the atmosphere, lux. */
export const EXTRATERRESTRIAL_LUX = 127500;
export const GROUND_REFLECTANCE = 0.2;

/** Relative air mass at elevation `el` degrees (Kasten & Young 1989). */
export function airMass(el: number): number {
  return 1 / (Math.sin(el * Math.PI / 180) + 0.50572 * Math.pow(el + 6.07995, -1.6364));
}

export interface DaylightLevels {
  /** Sun on a surface square to it, lux. */
  directNormal: number;
  /** Sky alone on a level surface, lux. */
  skyHorizontal: number;
}

export function daylightLevels(sky: SkyKind, elevation: number): DaylightLevels {
  const k = SKY[sky];
  if (!(elevation > -6)) return { directNormal: 0, skyHorizontal: 0 };
  if (elevation <= 0) return { directNormal: 0, skyHorizontal: k.a * 1000 * (elevation + 6) / 6 }; // twilight, fading out
  const s = Math.sin(elevation * Math.PI / 180);
  const directNormal = Number.isFinite(k.extinction) ? EXTRATERRESTRIAL_LUX * Math.exp(-k.extinction * airMass(elevation)) : 0;
  return { directNormal, skyHorizontal: (k.a + k.b * Math.pow(s, k.c)) * 1000 };
}

/** What a window shows from inside, before the glass: the sky in its upper half, sunlit ground in the
 *  lower half (uniform sky, nothing outside). cd/m². */
export function windowViewLuminance(l: DaylightLevels, elevation: number): number {
  const s = Math.max(0, Math.sin(elevation * Math.PI / 180));
  const ground = GROUND_REFLECTANCE * (l.skyHorizontal + l.directNormal * s);
  return 0.5 * l.skyHorizontal / Math.PI + 0.5 * ground / Math.PI;
}

// MARK: Where the sun is

export const DEFAULT_SUN = { bearing: 135, elevation: 35 };

export interface SunPlacement {
  /** Plan bearing the sun shines from (0 = plan up, clockwise). */
  bearing: number;
  elevation: number;
  from: 'clock' | 'hand';
  /** True bearing (from north), when known. */
  azimuth?: number;
}

/** Why the clock can't place the sun, or undefined when it can. */
export function clockProblem(loc: Location, scan?: ScanRecord): string | undefined {
  if (!loc.coordinate) return 'The location has no coordinates. Add the address or a pin on the phone.';
  if (scan?.northOffset === undefined) return 'The scan doesn\'t know which way is north. Set north on the phone, or place the sun by hand.';
  return undefined;
}

export function sunPlacement(loc: Location, scan?: ScanRecord): SunPlacement {
  const d = loc.daylight ?? {};
  if (d.fromClock && d.time !== undefined && !clockProblem(loc, scan)) {
    const pos = solarPosition(new Date(d.time * 1000), loc.coordinate!.latitude, loc.coordinate!.longitude);
    const bearing = ((pos.azimuth - scan!.northOffset! + 360) % 360 + 360) % 360;
    return { bearing, elevation: pos.elevation, from: 'clock', azimuth: pos.azimuth };
  }
  return { bearing: d.sunBearing ?? DEFAULT_SUN.bearing, elevation: d.sunElevation ?? DEFAULT_SUN.elevation, from: 'hand' };
}

// MARK: Room geometry

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const segLen = (s: { a: PlanPoint; b: PlanPoint }) => Math.hypot(s.b.x - s.a.x, s.b.z - s.a.z);

export function pointInPolygon(p: PlanPoint, poly: PlanPoint[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i], b = poly[j];
    if ((a.z > p.z) !== (b.z > p.z) && p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x) inside = !inside;
  }
  return inside;
}

/** Inside the room: in a floor polygon, or inside the plan's bounds when it has none. */
export function insideRoom(p: PlanPoint, plan: FloorPlan): boolean {
  const polys = plan.floorPolygons.filter(q => q.length >= 3);
  if (polys.length) return polys.some(q => pointInPolygon(p, q));
  const b = plan.bounds;
  return p.x > b.minX && p.x < b.maxX && p.z > b.minZ && p.z < b.maxZ;
}

/** Unit normal of a wall or window pointing into the room. */
export function inwardNormal(s: { a: PlanPoint; b: PlanPoint }, plan: FloorPlan): PlanPoint {
  const L = segLen(s) || 1e-6;
  const n = { x: -(s.b.z - s.a.z) / L, z: (s.b.x - s.a.x) / L };
  const mid = { x: (s.a.x + s.b.x) / 2, z: (s.a.z + s.b.z) / 2 };
  const plus = insideRoom({ x: mid.x + n.x * 0.3, z: mid.z + n.z * 0.3 }, plan);
  const minus = insideRoom({ x: mid.x - n.x * 0.3, z: mid.z - n.z * 0.3 }, plan);
  if (plus !== minus) return plus ? n : { x: -n.x, z: -n.z };
  const c = { x: (plan.bounds.minX + plan.bounds.maxX) / 2, z: (plan.bounds.minZ + plan.bounds.maxZ) / 2 };
  return (c.x - mid.x) * n.x + (c.z - mid.z) * n.z >= 0 ? n : { x: -n.x, z: -n.z };
}

// MARK: Backdrop placement

export interface BackdropPlacement {
  info: BackdropInfo;
  wall: PlanSegment;
  /** Left and right ends of the backdrop's face (in the room, looking at it from the room: a is left). */
  a: PlanPoint; b: PlanPoint;
  /** Into the room. */
  inward: PlanPoint;
  width: number; height: number;
  /** How far it runs onto the floor. */
  sweep: number;
  /** Where it sits along its wall: metres from the wall's middle (before any corner trim). */
  offset: number;
  colour: string;
}

/** The wall a backdrop goes on when none is chosen: the one the camera looks at, else the longest. */
export function defaultBackdropWall(loc: Location, plan: FloorPlan): PlanSegment | undefined {
  const walls = plan.walls.filter(w => segLen(w) > 0.5);
  if (!walls.length) return undefined;
  const rig = loc.shots[0]?.rig ?? loc.cameraPositions[0]?.rig;
  if (rig) {
    // Where the camera's axis meets a wall.
    const dir = { x: Math.sin(rig.pan * Math.PI / 180), z: -Math.cos(rig.pan * Math.PI / 180) };
    let best: { w: PlanSegment; t: number } | undefined;
    for (const w of walls) {
      const r = dir, s = { x: w.b.x - w.a.x, z: w.b.z - w.a.z };
      const denom = r.x * s.z - r.z * s.x;
      if (Math.abs(denom) < 1e-9) continue;
      const ac = { x: w.a.x - rig.position.x, z: w.a.z - rig.position.z };
      const t = (ac.x * s.z - ac.z * s.x) / denom, u = (ac.x * r.z - ac.z * r.x) / denom;
      if (t > 0.1 && u >= 0 && u <= 1 && (!best || t < best.t)) best = { w, t };
    }
    if (best) return best.w;
  }
  return walls.reduce((m, w) => (segLen(w) > segLen(m) ? w : m));
}

/** Where two backdrop pieces meet in an inside corner. `point` is where their faces would meet; a cyc
 *  curves round a vertical radius centred on `centre`, so each piece stops at its tangent point. Paper
 *  and LED pieces simply butt together (radius 0). */
export interface BackdropCorner {
  point: PlanPoint; centre: PlanPoint; radius: number;
  /** Tangent points on the two faces, and the two faces' into-the-room directions. */
  tangentA: PlanPoint; tangentB: PlanPoint;
  inwardA: PlanPoint; inwardB: PlanPoint;
  height: number; bottom: number;
}

export interface BackdropLayout {
  info: BackdropInfo;
  /** The first is on the main wall (`StudioSetup.wallID`). */
  pieces: BackdropPlacement[];
  corners: BackdropCorner[];
}

/** Radius of the vertical bend where a cyc turns a corner (more than the floor cove). */
export const CYC_CORNER_RADIUS = 0.75;
/** How close two wall ends must be to count as the same corner. */
export const CORNER_SNAP = 0.15;

const SIDE_NAMES = ['Top', 'Top right', 'Right', 'Bottom right', 'Bottom', 'Bottom left', 'Left', 'Top left'];
/** Names for the walls as they sit on the plan ("Top wall", "Left wall"; numbered when two share a
 *  side), for walls longer than half a metre. Keyed by wall id. */
export function wallNames(plan: FloorPlan): Map<string, string> {
  const walls = plan.walls.filter(w => segLen(w) > 0.5);
  const side = walls.map(w => {
    const n = inwardNormal(w, plan);
    // The wall sits on the side opposite its inward normal; plan up is −z.
    const bearing = ((Math.atan2(-n.x, n.z) * 180) / Math.PI + 360) % 360;
    return SIDE_NAMES[Math.round(bearing / 45) % 8];
  });
  const out = new Map<string, string>();
  walls.forEach((w, i) => {
    const same = side.filter(x => x === side[i]).length;
    const k = side.slice(0, i + 1).filter(x => x === side[i]).length;
    out.set(w.id, same > 1 ? `${side[i]} wall ${k}` : `${side[i]} wall`);
  });
  return out;
}

/** Two walls that meet end to end (a corner a backdrop can turn). */
export const wallsTouch = (w: { a: PlanPoint; b: PlanPoint }, o: { a: PlanPoint; b: PlanPoint }) =>
  [w.a, w.b].some(p => [o.a, o.b].some(q => dist(p, q) < CORNER_SNAP));

export const defaultBackdropWidth = (k: BackdropKind, L: number) => (k === 'cyc' ? L : k === 'paper' ? PAPER_WIDTH : Math.min(L, 6));

/** The main piece only (the wall the backdrop was first put on). */
export function backdropPlacement(loc: Location, plan: FloorPlan | undefined): BackdropPlacement | undefined {
  return backdropLayout(loc, plan)?.pieces[0];
}

const sameID = (a?: string, b?: string) => !!a && !!b && a.toUpperCase() === b.toUpperCase();
const sub = (a: PlanPoint, b: PlanPoint) => ({ x: a.x - b.x, z: a.z - b.z });
const add = (a: PlanPoint, b: PlanPoint) => ({ x: a.x + b.x, z: a.z + b.z });
const mul = (a: PlanPoint, k: number) => ({ x: a.x * k, z: a.z * k });
const dot = (a: PlanPoint, b: PlanPoint) => a.x * b.x + a.z * b.z;
const dist = (a: PlanPoint, b: PlanPoint) => Math.hypot(a.x - b.x, a.z - b.z);

/** Every piece of the backdrop, trimmed where pieces meet in a corner, and the corners. */
export function backdropLayout(loc: Location, plan: FloorPlan | undefined): BackdropLayout | undefined {
  const st = loc.studio;
  const info = backdropInfo(st?.backdrop);
  if (!st || !info || !plan) return undefined;
  const main = plan.walls.find(w => sameID(w.id, st.wallID)) ?? defaultBackdropWall(loc, plan);
  if (!main) return undefined;
  const parts: { wall: PlanSegment; offset?: number; width?: number }[] = [{ wall: main, offset: st.offset, width: st.width }];
  for (const m of st.moreWalls ?? []) {
    const w = plan.walls.find(x => sameID(x.id, m.wallID));
    if (!w || !(segLen(w) > 0.5) || parts.some(p => p.wall.id === w.id)) continue;
    parts.push({ wall: w, offset: m.offset, width: m.width });
  }
  const ends = parts.map(p => [p.wall.a, p.wall.b]);
  const shared = (i: number, p: PlanPoint) => ends.some((e, j) => j !== i && e.some(q => dist(q, p) < CORNER_SNAP));
  const pieces: BackdropPlacement[] = parts.map((part, i) => {
    const wall = part.wall, L = segLen(wall);
    const inward = inwardNormal(wall, plan);
    const width = clamp(part.width ?? defaultBackdropWidth(info.kind, L), 0.5, L);
    const wallTop = wall.bottom + wall.height;
    const height = clamp(st.height ?? (info.kind === 'cyc' ? wallTop : info.kind === 'paper' ? Math.min(wallTop, 3.0) : Math.min(wallTop, 3.5)), 0.5, Math.max(0.5, wallTop));
    // Along the wall, with "left" as seen from the room.
    let u = { x: (wall.b.x - wall.a.x) / L, z: (wall.b.z - wall.a.z) / L };
    if (u.x * inward.z - u.z * inward.x < 0) u = { x: -u.x, z: -u.z };
    const half = width / 2, slack = L / 2 - half;
    const wallMid = { x: (wall.a.x + wall.b.x) / 2, z: (wall.a.z + wall.b.z) / 2 };
    let off = part.offset ?? 0;
    if (part.offset === undefined && slack > 1e-6) {
      // Into the corner it shares with another backdrop wall.
      const left = shared(i, { x: wallMid.x - u.x * L / 2, z: wallMid.z - u.z * L / 2 });
      const right = shared(i, { x: wallMid.x + u.x * L / 2, z: wallMid.z + u.z * L / 2 });
      if (left !== right) off = left ? -slack : slack;
    }
    off = clamp(off, -slack, slack);
    const off2 = STANDOFF[info.kind];
    const mid = { x: wallMid.x + u.x * off + inward.x * off2, z: wallMid.z + u.z * off + inward.z * off2 };
    return {
      info, wall, inward, width, height, sweep: SWEEP[info.kind], offset: off,
      a: { x: mid.x - u.x * half, z: mid.z - u.z * half }, b: { x: mid.x + u.x * half, z: mid.z + u.z * half },
      colour: info.pickColour && st.colour ? st.colour : info.colour,
    };
  });
  // Join pieces whose ends reach the same room corner.
  const corners: BackdropCorner[] = [];
  const reach = STANDOFF[info.kind] + 0.05;
  const atCorner = (k: number, end: number) => {
    const p = pieces[k], e = end === 0 ? p.a : p.b;
    return [p.wall.a, p.wall.b].find(q => dist(q, e) < reach * 1.5);
  };
  for (let i = 0; i < pieces.length; i++) {
    for (let j = i + 1; j < pieces.length; j++) {
      for (let ei = 0; ei < 2; ei++) {
        for (let ej = 0; ej < 2; ej++) {
          const ci = atCorner(i, ei), cj = atCorner(j, ej);
          if (!ci || !cj || !(dist(ci, cj) < CORNER_SNAP)) continue;
          const pi = pieces[i], pj = pieces[j];
          const ei0 = ei === 0 ? pi.a : pi.b, ei1 = ei === 0 ? pi.b : pi.a;
          const ej0 = ej === 0 ? pj.a : pj.b, ej1 = ej === 0 ? pj.b : pj.a;
          // Where the two faces meet.
          const di = mul(sub(ei1, ei0), 1 / Math.max(dist(ei0, ei1), 1e-9));
          const dj = mul(sub(ej1, ej0), 1 / Math.max(dist(ej0, ej1), 1e-9));
          const denom = di.x * dj.z - di.z * dj.x;
          if (!(Math.abs(denom) > 0.05)) continue;
          const w = sub(ej0, ei0);
          const t = (w.x * dj.z - w.z * dj.x) / denom;
          const x = add(ei0, mul(di, t));
          // Inside corners only: each piece on the room side of the other.
          if (!(dot(sub(ei1, x), pj.inward) > 0.05) || !(dot(sub(ej1, x), pi.inward) > 0.05)) continue;
          const fi = dot(sub(ei1, x), di) >= 0 ? di : mul(di, -1);
          const fj = dot(sub(ej1, x), dj) >= 0 ? dj : mul(dj, -1);
          const phi = Math.acos(Math.max(-1, Math.min(1, dot(fi, fj))));
          const leni = dist(x, ei1), lenj = dist(x, ej1);
          let r = info.kind === 'cyc' ? CYC_CORNER_RADIUS : 0;
          let tn = r > 0 ? r / Math.tan(phi / 2) : 0;
          const room = Math.min(leni, lenj) * 0.5;
          if (tn > room) { r *= room / tn; tn = room; }
          const ti = add(x, mul(fi, tn)), tj = add(x, mul(fj, tn));
          const sum = add(fi, fj);
          const bis = mul(sum, 1 / Math.max(Math.hypot(sum.x, sum.z), 1e-9));
          const centre = r > 0 ? add(x, mul(bis, r / Math.sin(phi / 2))) : x;
          const a = { ...pieces[i] }, b = { ...pieces[j] };
          if (ei === 0) a.a = ti; else a.b = ti;
          if (ej === 0) b.a = tj; else b.b = tj;
          a.width = dist(a.a, a.b);
          b.width = dist(b.a, b.b);
          pieces[i] = a;
          pieces[j] = b;
          corners.push({ point: x, centre, radius: r, tangentA: ti, tangentB: tj, inwardA: a.inward, inwardB: b.inward,
            height: Math.min(a.height, b.height), bottom: Math.max(a.wall.bottom, b.wall.bottom) });
        }
      }
    }
  }
  return { info, pieces, corners };
}

/** The floor a corner covers: between the two faces, out to `sweep` from each. */
export function cornerFootprint(c: BackdropCorner, sweep: number): PlanPoint[] {
  // The point `sweep` in from both faces: (q − x)·nA = (q − x)·nB = sweep.
  const a = c.inwardA, b = c.inwardB;
  const det = a.x * b.z - a.z * b.x;
  if (!(Math.abs(det) > 1e-6)) return [];
  const q = { x: c.point.x + sweep * (b.z - a.z) / det, z: c.point.z + sweep * (a.x - b.x) / det };
  return [c.point, c.tangentA, add(c.tangentA, mul(a, sweep)), q, add(c.tangentB, mul(b, sweep)), c.tangentB];
}

// MARK: For the calculator

/** A flat rectangle that gives diffuse light: a window seen from inside, or an LED wall. */
export interface AreaSource {
  id: string;
  /** Bottom-left corner, seen from the side it lights. */
  origin: PlanPoint; bottom: number;
  /** Unit direction along its width (plan). */
  along: PlanPoint;
  width: number; height: number;
  /** Unit plan direction it lights towards (it is vertical). */
  facing: PlanPoint;
  luminance: number;
  columns: number; rows: number;
}

/** Light from outside the room and from the set itself, ready for the calculator. */
export interface Environment {
  sun?: { bearing: number; elevation: number; directNormal: number };
  /** What a window shows from inside, before glass and curtains. */
  windowLuminance: number;
  /** One per LED piece (a volume round several walls has several); all count as "LED wall". */
  ledWalls: AreaSource[];
}

export const AMBIENT_IDS = {
  sun: '5A11D000-0000-4000-8000-000000000001',
  sky: '5A11D000-0000-4000-8000-000000000002',
  ledWall: '5A11D000-0000-4000-8000-000000000003',
};
export function ambientName(id: string): string | undefined {
  const k = id.toUpperCase();
  if (k === AMBIENT_IDS.sun) return 'Sun through the window';
  if (k === AMBIENT_IDS.sky) return 'Daylight through the windows';
  if (k === AMBIENT_IDS.ledWall) return 'LED wall';
  return undefined;
}

export const LED_CELL = 0.5;
export const WINDOW_CELL = 0.4;

export function environment(loc: Location, plan: FloorPlan | undefined, scan?: ScanRecord): Environment | undefined {
  let env: Environment | undefined;
  const d = loc.daylight;
  if (d?.isOn) {
    const sun = sunPlacement(loc, scan);
    const levels = daylightLevels(d.sky ?? 'clear', sun.elevation);
    env = { windowLuminance: windowViewLuminance(levels, sun.elevation), ledWalls: [] };
    if (levels.directNormal > 0) env.sun = { bearing: sun.bearing, elevation: sun.elevation, directNormal: levels.directNormal };
  }
  const layout = backdropLayout(loc, plan);
  if (layout && layout.info.kind === 'led') {
    const nits = clamp(loc.studio?.nits ?? LED_DEFAULT_NITS, 0, LED_NITS_RANGE.max);
    const ledWalls: AreaSource[] = layout.pieces.filter(bd => bd.width > 0.01).map(bd => ({
      id: AMBIENT_IDS.ledWall, origin: bd.a, bottom: bd.wall.bottom, along: { x: (bd.b.x - bd.a.x) / bd.width, z: (bd.b.z - bd.a.z) / bd.width },
      width: bd.width, height: bd.height, facing: bd.inward,
      luminance: nits, columns: Math.round(clamp(Math.round(bd.width / LED_CELL), 2, 12)), rows: Math.round(clamp(Math.round(bd.height / LED_CELL), 2, 8)),
    }));
    env = { ...(env ?? { windowLuminance: 0, ledWalls: [] }), ledWalls };
  }
  return env;
}
