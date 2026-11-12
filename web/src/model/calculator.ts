// Port of FrameScout/Core/Models/LightingCalculator.swift. Same model, same assumptions (D-006):
// direct light from every unit with beam shape, inverse square (with near-field terms), cosine
// incidence, barn doors, walls/windows/doors/grip occlusion, and grip as a second source: bounce
// boards, flags and negs send back what they reflect, diffusion frames re-emit what they pass.
// Not modelled: room inter-reflections, daylight, furniture shadows. Every figure is an estimate.
import type { FloorPlan, LightFixture, LightKind, LightMeter, Location, PlanPoint, PlanSegment, UUID, PlanRect, MeterFacing } from './types';
import { barnDoorTransmission, barnDoorsOpen, distanceFactor, fixtureProfile, openBarnDoors, photometrics, relativeIntensity, type ResolvedPhotometrics } from './photometrics';
import type { BarnDoors } from './types';
import { horizontalFOV } from './camera';
import { eyeHeight } from './characters';

export interface Vec { x: number; y: number; z: number }
export const vec = (x: number, y: number, z: number): Vec => ({ x, y, z });
export const at = (p: PlanPoint, height: number): Vec => ({ x: p.x, y: height, z: p.z });
const sub = (a: Vec, b: Vec): Vec => ({ x: a.x - b.x, y: a.y - b.y, z: a.z - b.z });
const scale = (a: Vec, s: number): Vec => ({ x: a.x * s, y: a.y * s, z: a.z * s });
const dot = (a: Vec, b: Vec) => a.x * b.x + a.y * b.y + a.z * b.z;
const len = (a: Vec) => Math.sqrt(dot(a, a));
const norm = (a: Vec): Vec => { const l = len(a); return l > 1e-12 ? scale(a, 1 / l) : vec(0, 1, 0); };
const cross = (a: Vec, b: Vec): Vec => ({ x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x });

export const planSub = (a: PlanPoint, b: PlanPoint): PlanPoint => ({ x: a.x - b.x, z: a.z - b.z });
export const planAdd = (a: PlanPoint, b: PlanPoint): PlanPoint => ({ x: a.x + b.x, z: a.z + b.z });
export const planScale = (a: PlanPoint, s: number): PlanPoint => ({ x: a.x * s, z: a.z * s });
export const planDist = (a: PlanPoint, b: PlanPoint) => Math.hypot(a.x - b.x, a.z - b.z);
/// Bearing in the plan frame: 0° = −Z (plan up), clockwise.
export function worldBearing(p: PlanPoint): number { const d = Math.atan2(p.x, -p.z) * 180 / Math.PI; return d < 0 ? d + 360 : d; }
export const bearingFrom = (a: PlanPoint, b: PlanPoint) => worldBearing(planSub(b, a));
export function unitBearing(deg: number): PlanPoint { const r = deg * Math.PI / 180; return { x: Math.sin(r), z: -Math.cos(r) }; }

export function direction(bearing: number, tilt: number): Vec {
  const b = bearing * Math.PI / 180, t = tilt * Math.PI / 180;
  return vec(Math.sin(b) * Math.cos(t), Math.sin(t), -Math.cos(b) * Math.cos(t));
}

interface Emitter { id: UUID; position: Vec; axis: Vec; right: Vec; up: Vec; pm: ResolvedPhotometrics; barnDoors: BarnDoors }
/** How a piece of grip treats light that lands on it (same numbers as BoardOptics in Swift).
 *  `transmission`: fraction that gets through; `scatter`: share of that which is diffused (1 = full
 *  diffusion, 0 = a net: the beam just gets dimmer); `reflectance`: fraction thrown back off the lit face. */
export interface BoardOptics { transmission: number; scatter: number; reflectance: number }
/// Defaults by kind (D-013): white board 0.8; black duvetyne about 3–4 %; a full diffusion passes
/// about half, all of it scattered, and throws about a third back.
export function boardOptics(kind: LightKind): BoardOptics {
  switch (kind) {
    case 'bounce': return { transmission: 0, scatter: 0, reflectance: 0.8 };
    case 'negative': return { transmission: 0, scatter: 0, reflectance: 0.03 };
    case 'flag': return { transmission: 0, scatter: 0, reflectance: 0.04 };
    case 'diffusion': return { transmission: 0.5, scatter: 1, reflectance: 0.35 };
    default: return { transmission: 1, scatter: 0, reflectance: 0 };
  }
}
interface Board extends BoardOptics { id: UUID; kind: LightKind; centre: Vec; normal: Vec; a: PlanPoint; b: PlanPoint; bottom: number; top: number; area: number }
/** One patch of a board lit by one unit, re-emitting like a matte surface into the side `normal` faces:
 *  the reflected part on the lit side, the scattered part out of the far side of a diffusion. */
export interface Patch { board: UUID; lightID: UUID; centre: Vec; normal: Vec; intensity: number; radius: number }

export const DEFAULT_WINDOW_TRANSMISSION = 0.78;
/** Each board is split into this many patches a side, so a frame only half in the beam glows only where it is lit. */
const PATCHES = 3;

export interface Scene { emitters: Emitter[]; boards: Board[]; walls: PlanSegment[]; apertures: PlanSegment[]; windowTransmission: number; patches: Patch[] }

export function buildScene(lights: LightFixture[], plan?: FloorPlan, windowTransmission = DEFAULT_WINDOW_TRANSMISSION): Scene {
  const scene: Scene = { emitters: [], boards: [], walls: plan?.walls ?? [], apertures: plan ? [...plan.windows, ...plan.doors, ...plan.openings] : [], windowTransmission, patches: [] };
  for (const l of lights) {
    const axis = direction(l.pan, l.tilt);
    const emits = !['bounce', 'negative', 'flag', 'diffusion'].includes(l.kind);
    if (emits) {
      const right = direction(l.pan + 90, 0);
      scene.emitters.push({ id: l.id, position: at(l.position, l.height), axis, right, up: norm(cross(right, axis)), pm: photometrics(l), barnDoors: l.barnDoors ?? openBarnDoors });
    } else {
      const side = planScale(unitBearing(l.pan + 90), l.width / 2);
      const h = l.boardHeight ?? (l.kind === 'flag' ? Math.min(l.width, 0.9) : l.width);
      scene.boards.push({ id: l.id, kind: l.kind, centre: at(l.position, l.height), normal: axis, a: planSub(l.position, side), b: planAdd(l.position, side), bottom: l.height - h / 2, top: l.height + h / 2, area: l.width * h, ...boardOptics(l.kind) });
    }
  }
  scene.patches = secondarySources(scene);
  return scene;
}

/** What every board re-emits, worked out once per scene: for each unit, the light landing on each
 *  patch (with everything else in the way), sent back off the lit face and, through a diffusion, out
 *  of the far face. One bounce: light off one board doesn't light another. */
function secondarySources(scene: Scene): Patch[] {
  const patches: Patch[] = [];
  for (const board of scene.boards) {
    if (!(board.reflectance > 0) && !(board.transmission * board.scatter > 0)) continue;
    const patchArea = board.area / (PATCHES * PATCHES), radius = Math.sqrt(patchArea / Math.PI);
    for (let i = 0; i < PATCHES; i++) for (let j = 0; j < PATCHES; j++) {
      const f = (i + 0.5) / PATCHES, p = planAdd(board.a, planScale(planSub(board.b, board.a), f));
      const centre = vec(p.x, board.bottom + (j + 0.5) / PATCHES * (board.top - board.bottom), p.z);
      for (const e of scene.emitters) {
        const side = dot(sub(e.position, centre), board.normal);
        if (side === 0) continue;
        const lit = side > 0 ? board.normal : scale(board.normal, -1);
        const incident = illuminanceFrom(e, centre, lit, scene, board.id);
        if (!(incident > 0)) continue;
        const each = incident * patchArea / Math.PI; // a matte surface's intensity: exitance × area ÷ π
        if (board.reflectance > 0) patches.push({ board: board.id, lightID: e.id, centre, normal: lit, intensity: board.reflectance * each, radius });
        if (board.transmission * board.scatter > 0) patches.push({ board: board.id, lightID: e.id, centre, normal: scale(lit, -1), intensity: board.transmission * board.scatter * each, radius });
      }
    }
  }
  return patches;
}

export function intersect(a: PlanPoint, b: PlanPoint, c: PlanPoint, d: PlanPoint): [number, PlanPoint] | undefined {
  const r = planSub(b, a), s = planSub(d, c);
  const denom = r.x * s.z - r.z * s.x;
  if (!(Math.abs(denom) > 1e-12)) return undefined;
  const ac = planSub(c, a);
  const t = (ac.x * s.z - ac.z * s.x) / denom;
  const u = (ac.x * r.z - ac.z * r.x) / denom;
  if (!(t > 1e-4 && t < 1 - 1e-4 && u >= 0 && u <= 1)) return undefined;
  return [t, planAdd(a, planScale(r, t))];
}

export function distanceToSegment(p: PlanPoint, a: PlanPoint, b: PlanPoint): number {
  const ab = planSub(b, a);
  const len2 = ab.x * ab.x + ab.z * ab.z;
  if (!(len2 > 1e-12)) return planDist(p, a);
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * ab.x + (p.z - a.z) * ab.z) / len2));
  return planDist(p, planAdd(a, planScale(ab, t)));
}

export function transmission(a: Vec, b: Vec, scene: Scene, ignoring: UUID[] = []): number {
  let t = 1;
  const ap = { x: a.x, z: a.z }, bp = { x: b.x, z: b.z };
  for (const w of scene.walls) {
    const hit = intersect(ap, bp, w.a, w.b);
    if (!hit) continue;
    const [s, q] = hit;
    const y = a.y + s * (b.y - a.y);
    if (!(y >= w.bottom - 0.01 && y <= w.bottom + w.height + 0.01)) continue;
    const opening = scene.apertures.find(o => distanceToSegment(q, o.a, o.b) < 0.15 && y >= o.bottom - 0.01 && y <= o.bottom + o.height + 0.01);
    if (opening) {
      if (opening.kind === 'window') t *= scene.windowTransmission;
      else if (opening.kind === 'door') t *= opening.isOpen ? 1 : 0;
    } else return 0;
    if (t <= 0) return 0;
  }
  for (const board of scene.boards) {
    if (ignoring.includes(board.id)) continue;
    const hit = intersect(ap, bp, board.a, board.b);
    if (!hit) continue;
    const y = a.y + hit[0] * (b.y - a.y);
    if (!(y >= board.bottom && y <= board.top)) continue;
    t *= board.transmission * (1 - board.scatter); // what a diffusion scatters comes out as its own soft source
    if (t <= 0) return 0;
  }
  return t;
}

function illuminanceFrom(e: Emitter, point: Vec, normal: Vec, scene: Scene, ignoringBoard?: UUID): number {
  const toPoint = sub(point, e.position);
  const d = len(toPoint);
  if (!(d > 0.05) || !(e.pm.peakIntensity > 0)) return 0;
  const v = scale(toPoint, 1 / d);
  const incidence = -dot(v, normal);
  if (!(incidence > 0)) return 0;
  const pm = e.pm;
  let relative: number;
  if (pm.distribution === 'tube') {
    const along = Math.min(1, Math.abs(dot(v, e.right)));
    relative = Math.sqrt(1 - along * along);
  } else {
    const cosT = Math.min(1, Math.max(-1, dot(v, e.axis)));
    relative = relativeIntensity(pm.distribution, Math.acos(cosT) * 180 / Math.PI, pm.beamAngle);
  }
  if (pm.barnDoorsAvailable && !barnDoorsOpen(e.barnDoors)) {
    const fwd = dot(v, e.axis);
    if (fwd <= 0) return 0;
    const h = Math.atan2(dot(v, e.right), fwd) * 180 / Math.PI;
    const vert = Math.atan2(dot(v, e.up), fwd) * 180 / Math.PI;
    relative *= barnDoorTransmission(e.barnDoors, h, vert);
  }
  if (!(relative > 1e-6)) return 0;
  const lux = pm.peakIntensity * relative * distanceFactor(d, pm.distribution, pm.emitterRadius, pm.tubeLength) * incidence;
  if (!(lux > 1e-6)) return 0;
  return lux * transmission(e.position, point, scene, ignoringBoard ? [e.id, ignoringBoard] : [e.id]);
}

export interface Contribution { lightID: UUID; lux: number; viaBounce?: UUID }
export interface Reading { lux: number; contributions: Contribution[] }

/** Light one re-emitting patch sends to `point`: a small matte source (with the near-field term). */
function fromPatch(patch: Patch, point: Vec, normal: Vec, scene: Scene): number {
  const toPoint = sub(point, patch.centre);
  const d = len(toPoint);
  if (!(d > 0.05)) return 0;
  const v = scale(toPoint, 1 / d);
  const out = dot(v, patch.normal), incidence = -dot(v, normal);
  if (!(out > 0 && incidence > 0)) return 0;
  const lux = patch.intensity * out * incidence / (d * d + patch.radius * patch.radius);
  if (!(lux > 1e-6)) return 0;
  return lux * transmission(patch.centre, point, scene, [patch.board]);
}

export function reading(point: Vec, normal: Vec, scene: Scene): Reading {
  const contributions: Contribution[] = [];
  let total = 0;
  for (const e of scene.emitters) {
    const lux = illuminanceFrom(e, point, normal, scene);
    if (lux > 0) { contributions.push({ lightID: e.id, lux }); total += lux; }
  }
  for (const patch of scene.patches) {
    const lux = fromPatch(patch, point, normal, scene);
    if (!(lux > 0)) continue;
    // One contribution per unit and board, however many patches it came off.
    const had = contributions.find(c => c.lightID === patch.lightID && c.viaBounce === patch.board);
    if (had) had.lux += lux; else contributions.push({ lightID: patch.lightID, lux, viaBounce: patch.board });
    total += lux;
  }
  return { lux: total, contributions };
}

export function grid(bounds: PlanRect, columns: number, rows: number, height: number, scene: Scene, normal: (p: Vec) => Vec): number[] {
  const values: number[] = [];
  const cw = (bounds.maxX - bounds.minX) / columns, ch = (bounds.maxZ - bounds.minZ) / rows;
  for (let r = 0; r < rows; r++) for (let c = 0; c < columns; c++) {
    const p = vec(bounds.minX + (c + 0.5) * cw, height, bounds.minZ + (r + 0.5) * ch);
    values.push(reading(p, normal(p), scene).lux);
  }
  return values;
}

export type IntensitySolution =
  | { kind: 'output'; output: number }
  | { kind: 'tooDim'; maxLux: number; suggestedDistance?: number }
  | { kind: 'atMinimum'; output: number; lux: number }
  | { kind: 'othersTooBright'; othersLux: number }
  | { kind: 'noContribution' };

export function solveOutput(light: LightFixture, target: number, point: Vec, normal: Vec, allLights: LightFixture[], plan?: FloorPlan, windowTransmission = DEFAULT_WINDOW_TRANSMISSION): IntensitySolution {
  const others = allLights.filter(l => l.id !== light.id);
  const full = { ...light, dimmer: 1, isOn: true };
  const fullReading = reading(point, normal, buildScene([...others, full], plan, windowTransmission));
  const mine = fullReading.contributions.filter(c => c.lightID === light.id).reduce((s, c) => s + c.lux, 0);
  const othersLux = fullReading.lux - mine;
  if (!(mine > 1e-6)) return { kind: 'noContribution' };
  const need = target - othersLux;
  if (need <= 0) return { kind: 'othersTooBright', othersLux };
  const output = need / mine;
  if (output > 1.0001) {
    const d = len(sub(point, at(light.position, light.height)));
    return { kind: 'tooDim', maxLux: fullReading.lux, suggestedDistance: d * Math.sqrt(mine / need) };
  }
  const minOutput = fixtureProfile(light).minOutput;
  if (output < minOutput - 1e-9) return { kind: 'atMinimum', output: minOutput, lux: othersLux + mine * minOutput };
  return { kind: 'output', output: Math.min(1, output) };
}

// MARK: Meter points (Location.meterPoints)

interface MeterCamera { position: PlanPoint; height: number; pan: number; horizontalFOV: number }
export type MeterSource = { meter: UUID } | { character: UUID };
export interface MeterPoint { key: string; source: MeterSource; name: string; point: Vec; normal: Vec; targetLux?: number }

export function meterCameras(loc: Location): MeterCamera[] {
  return [...loc.shots.map(s => s.rig), ...loc.cameraPositions.map(c => c.rig)]
    .map(r => ({ position: r.position, height: r.height, pan: r.pan, horizontalFOV: horizontalFOV(r) }));
}

export function cameraSeeing(point: PlanPoint, cameras: MeterCamera[]): MeterCamera | undefined {
  const inFrame = (c: MeterCamera) => {
    let diff = Math.abs(bearingFrom(c.position, point) - c.pan) % 360;
    if (diff > 180) diff = 360 - diff;
    return diff <= c.horizontalFOV / 2;
  };
  const framed = cameras.filter(inFrame);
  const pool = framed.length ? framed : cameras;
  return pool.reduce<MeterCamera | undefined>((m, c) => (!m || planDist(c.position, point) < planDist(m.position, point) ? c : m), undefined);
}

export function meterNormal(facing: MeterFacing, bearing: number, p: Vec, cameras: MeterCamera[]): Vec {
  if (facing === 'up') return vec(0, 1, 0);
  if (facing === 'bearing') return direction(bearing, 0);
  const cam = cameraSeeing({ x: p.x, z: p.z }, cameras);
  return cam ? norm(sub(at(cam.position, cam.height), p)) : direction(bearing, 0);
}

export function meterPoints(loc: Location, scanID?: UUID): MeterPoint[] {
  const cams = meterCameras(loc);
  const result: MeterPoint[] = [];
  for (const m of (loc.meters ?? []) as LightMeter[]) {
    if (m.scanID && m.scanID !== scanID) continue;
    const p = at(m.position, m.height);
    result.push({ key: 'm:' + m.id, source: { meter: m.id }, name: m.name, point: p, normal: meterNormal(m.facing, m.bearing, p, cams), targetLux: m.targetLux });
  }
  for (const c of loc.characters ?? []) {
    if (c.scanID && c.scanID !== scanID) continue;
    const p = at(c.position, Math.max(0.3, eyeHeight(c) - 0.03));
    const normal = cams.length ? meterNormal('camera', c.facing, p, cams) : direction(c.facing, 0);
    result.push({ key: 'c:' + c.id, source: { character: c.id }, name: c.name, point: p, normal });
  }
  return result;
}
