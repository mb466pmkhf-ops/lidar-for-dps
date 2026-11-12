// Keeps stand-in people out of the furniture: a standing person is moved to the nearest free
// floor beside a piece, and a sitting person dropped on a sofa, chair or bed sits on its seat at
// the seat's height. Mirrors FrameScout/Core/Models/Placement.swift; keep the numbers identical
// (tests on both sides check the same cases).
//
// Seat heights and sitting lines follow the furniture the 3D view draws (ui/scene3d/room.ts and
// PlanSceneBuilder.swift), so a seated figure rests on the cushion rather than inside it. They
// are drawing sizes, not measurements: nothing here is shown as a figure.
import type { FloorPlan, PlanObject, PlanPoint, PlanSegment, PrevisCharacter } from './types';
import { insideRoom } from './stage';

const r3 = (v: number) => Math.round(v * 1000) / 1000;
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

/** How close (m) to a seat a sitting person may be dropped and still sit on it. */
export const SEAT_REACH = 0.15;
/** Switching a person to Sitting finds a seat this close (m). */
export const SIT_DOWN_REACH = 0.6;
/** A seated person may turn this far (°) from straight ahead on the seat before they are squared up. */
export const SEAT_TURN = 45;
/** Gap (m) left between a person and the furniture they are moved away from. */
const GAP = 0.02;

export function distToWalls(p: PlanPoint, walls: PlanSegment[]): number {
  let best = Infinity;
  for (const w of walls) {
    const dx = w.b.x - w.a.x, dz = w.b.z - w.a.z, l2 = dx * dx + dz * dz || 1e-6;
    const t = clamp(((p.x - w.a.x) * dx + (p.z - w.a.z) * dz) / l2, 0, 1);
    best = Math.min(best, Math.hypot(p.x - (w.a.x + dx * t), p.z - (w.a.z + dz * t)));
  }
  return best;
}

/** Local axes of a piece: X along its width, Z along its depth. */
export const widthAxis = (o: PlanObject): PlanPoint => ({ x: Math.cos(o.rotation), z: Math.sin(o.rotation) });
export const depthAxis = (o: PlanObject): PlanPoint => ({ x: -Math.sin(o.rotation), z: Math.cos(o.rotation) });

/** Which long side (+1 or −1 along local Z) backs onto the nearest wall. Sofas, chairs, beds and cupboards turn their back to it. */
export function backSide(o: PlanObject, walls: PlanSegment[]): 1 | -1 {
  const ax = depthAxis(o);
  const at = (s: number) => distToWalls({ x: o.center.x + ax.x * s * o.depth / 2, z: o.center.z + ax.z * s * o.depth / 2 }, walls);
  return at(1) <= at(-1) ? 1 : -1;
}

export type SeatKind = 'sofa' | 'chair' | 'bed';
export function seatKind(category: string): SeatKind | undefined {
  const k = category.toLowerCase();
  if (k.includes('sofa') || k.includes('couch')) return 'sofa';
  if (k.includes('chair') || k.includes('stool')) return 'chair';
  if (k.includes('bed')) return 'bed';
  return undefined;
}

/** Shapes the 3D views draw for seats (m). Shared with room.ts and PlanSceneBuilder.swift. */
export const sofaShape = (o: PlanObject) => ({ seat: Math.min(0.44, o.height * 0.55), arm: Math.min(0.2, o.width * 0.12), back: Math.min(0.24, o.depth * 0.3) });
export const chairSeat = (o: PlanObject) => Math.min(0.46, o.height * 0.55);
export const bedBase = (o: PlanObject) => Math.min(0.3, o.height * 0.5);

/** Pieces a person can't stand in. Stairs and anything flat on the floor are walked on. */
export const isSolid = (o: PlanObject) => o.height >= 0.05 && !/stair/i.test(o.category);

export interface Seat {
  object: PlanObject; kind: SeatKind;
  /** Top of the cushion or mattress above the floor (m). */
  height: number;
  /** Middle of the line a person's hips sit on, the direction along it, and how far either way they can slide. */
  centre: PlanPoint; along: PlanPoint; reach: number;
  /** The way a seated person faces. */
  front: PlanPoint;
}

/** Where a person sits on a piece. A bed is sat on along the long side nearest `near`. */
export function seatOf(o: PlanObject, plan: FloorPlan, near?: PlanPoint): Seat | undefined {
  const kind = seatKind(o.category);
  if (!kind || !isSolid(o)) return undefined;
  const ax = widthAxis(o), az = depthAxis(o), d = o.depth;
  let side: number, inset: number, height: number, reach: number;
  if (kind === 'bed') {
    const lz = near ? (near.x - o.center.x) * az.x + (near.z - o.center.z) * az.z : 1;
    side = lz >= 0 ? 1 : -1;          // the edge they sit on
    inset = Math.min(d / 2, 0.2);
    height = bedBase(o) + 0.22;
    reach = Math.max(0, o.width / 2 - 0.45);
    const z = side * (d / 2 - inset);
    return { object: o, kind, height: r3(height), centre: { x: o.center.x + az.x * z, z: o.center.z + az.z * z }, along: ax, reach, front: { x: az.x * side, z: az.z * side } };
  }
  const back = backSide(o, plan.walls);
  if (kind === 'sofa') {
    const s = sofaShape(o);
    // Hips sit a body's half depth in front of the back cushions.
    inset = Math.min(d / 2, s.back + 0.25);
    height = s.seat;
    reach = Math.max(0, o.width / 2 - s.arm - 0.25);
  } else {
    inset = Math.min(d / 2, 0.16);
    height = chairSeat(o) + 0.025;
    reach = Math.max(0, o.width / 2 - 0.3);
  }
  const z = back * (d / 2 - inset);
  return { object: o, kind, height: r3(height), centre: { x: o.center.x + az.x * z, z: o.center.z + az.z * z }, along: ax, reach, front: { x: -az.x * back, z: -az.z * back } };
}

/** Local position of `p` in a piece's frame (x along the width, z along the depth). */
function local(o: PlanObject, p: PlanPoint): PlanPoint {
  const ax = widthAxis(o), az = depthAxis(o), dx = p.x - o.center.x, dz = p.z - o.center.z;
  return { x: dx * ax.x + dz * ax.z, z: dx * az.x + dz * az.z };
}
const world = (o: PlanObject, q: PlanPoint): PlanPoint => {
  const ax = widthAxis(o), az = depthAxis(o);
  return { x: o.center.x + ax.x * q.x + az.x * q.z, z: o.center.z + ax.z * q.x + az.z * q.z };
};

/** The seat whose footprint (grown by `margin`) holds `p`, the closest to its middle first. */
export function seatAt(p: PlanPoint, plan: FloorPlan, margin = SEAT_REACH): Seat | undefined {
  let best: { seat: Seat; d: number } | undefined;
  for (const o of plan.objects) {
    if (!seatKind(o.category) || !isSolid(o)) continue;
    const q = local(o, p);
    if (Math.abs(q.x) > o.width / 2 + margin || Math.abs(q.z) > o.depth / 2 + margin) continue;
    const d = Math.hypot(Math.max(0, Math.abs(q.x) - o.width / 2), Math.max(0, Math.abs(q.z) - o.depth / 2)) + Math.hypot(q.x, q.z) * 1e-3;
    const seat = seatOf(o, plan, p);
    if (seat && (!best || d < best.d)) best = { seat, d };
  }
  return best?.seat;
}

/** How much floor a person takes up, as a circle round their position (m). */
export const bodyRadius = (c: PrevisCharacter) => Math.max(0.15, c.height * 0.12);

const bearingOf = (dir: PlanPoint) => (Math.atan2(dir.x, -dir.z) * 180) / Math.PI;
const wrap180 = (a: number) => { let x = a % 360; if (x > 180) x -= 360; if (x <= -180) x += 360; return x; };
const wrap360 = (a: number) => ((a % 360) + 360) % 360;

/** Seats a person on a seat: hips on its sitting line, facing out (or turned a little), at its height. */
export function sitOn(c: PrevisCharacter, seat: Seat): PrevisCharacter {
  const t = clamp((c.position.x - seat.centre.x) * seat.along.x + (c.position.z - seat.centre.z) * seat.along.z, -seat.reach, seat.reach);
  const position = { x: r3(seat.centre.x + seat.along.x * t), z: r3(seat.centre.z + seat.along.z * t) };
  const ahead = bearingOf(seat.front);
  const facing = Math.abs(wrap180(c.facing - ahead)) <= SEAT_TURN ? c.facing : Math.round(wrap360(ahead));
  return { ...c, posture: 'sitting', position, facing, seatHeight: seat.height };
}

/** How far `p` is inside a piece grown by `r`, or 0 when it is clear. */
function overlap(o: PlanObject, p: PlanPoint, r: number): number {
  const q = local(o, p);
  const ox = Math.abs(q.x) - o.width / 2, oz = Math.abs(q.z) - o.depth / 2;
  if (ox <= 0 && oz <= 0) return r - Math.max(ox, oz);           // inside the box
  const out = Math.hypot(Math.max(0, ox), Math.max(0, oz));
  return out < r - 1e-6 ? r - out : 0;
}

/** Places to step to that clear piece `o`: straight out from its nearest point, and out past each side. */
function exits(o: PlanObject, p: PlanPoint, r: number): PlanPoint[] {
  const q = local(o, p), hw = o.width / 2, hd = o.depth / 2, gap = r + GAP;
  const out: PlanPoint[] = [];
  const cx = clamp(q.x, -hw, hw), cz = clamp(q.z, -hd, hd), dx = q.x - cx, dz = q.z - cz, d = Math.hypot(dx, dz);
  if (d > 1e-6) out.push({ x: cx + (dx / d) * gap, z: cz + (dz / d) * gap });
  out.push({ x: q.x, z: hd + gap }, { x: q.x, z: -hd - gap }, { x: hw + gap, z: q.z }, { x: -hw - gap, z: q.z });
  return out.map(e => world(o, e));
}

/**
 * The nearest point to `p` where a body of radius `r` stands clear of every solid piece and on the
 * floor. Tries a few steps (pieces can sit side by side); keeps the start when nothing nearby is clear.
 */
export function clearOfFurniture(p: PlanPoint, r: number, plan: FloorPlan, ignore?: string): PlanPoint {
  const solids = plan.objects.filter(o => isSolid(o) && o.id !== ignore);
  const hits = (x: PlanPoint) => solids.some(o => overlap(o, x, r) > 1e-4);
  const onFloor = (x: PlanPoint) => !(plan.walls.length || plan.floorPolygons.length) || (insideRoom(x, plan) && distToWalls(x, plan.walls) >= Math.min(r, 0.1));
  let at = p;
  for (let step = 0; step < 4; step++) {
    const blocker = solids.find(o => overlap(o, at, r) > 1e-4);
    if (!blocker) return at;
    const from = at;
    const options = exits(blocker, at, r).sort((a, b) => Math.hypot(a.x - from.x, a.z - from.z) - Math.hypot(b.x - from.x, b.z - from.z));
    const free = options.find(x => onFloor(x) && !hits(x));
    if (free) return { x: r3(free.x), z: r3(free.z) };
    // Boxed in: step out of this piece and try the next one in the way.
    const next = options.find(onFloor);
    if (!next) return p;
    at = next;
  }
  return p;
}

/**
 * Settles one person against the plan's furniture after an edit. `before` is the same person
 * before the edit (missing for a new one): it tells a sitting-down or standing-up from a move.
 *
 * - Sitting on or near a sofa, chair or bed: sits on it at its seat height.
 * - Sitting with no seat under them: sits on the usual chair height wherever they are, moved out of
 *   any furniture.
 * - Standing up from a seat: steps out in front of it.
 * - Standing: moved to the nearest clear floor if they are inside a piece.
 */
export function settlePerson(c: PrevisCharacter, plan: FloorPlan | undefined, before?: PrevisCharacter): PrevisCharacter {
  if (!plan) return c;
  if (c.posture === 'sitting') {
    const sittingDown = before !== undefined && before.posture !== 'sitting';
    const seat = seatAt(c.position, plan, sittingDown ? SIT_DOWN_REACH : SEAT_REACH);
    if (seat) return sitOn(c, seat);
  }
  let position = c.position;
  if (c.posture === 'standing' && before?.posture === 'sitting' && before.seatHeight !== undefined) {
    const seat = seatAt(before.position, plan);
    if (seat) {
      const t = clamp((before.position.x - seat.centre.x) * seat.along.x + (before.position.z - seat.centre.z) * seat.along.z, -seat.reach, seat.reach);
      // Out past the front edge, level with where they sat.
      const o = seat.object, step = o.depth / 2 + bodyRadius(c) + 0.05;
      const mid = { x: o.center.x + seat.along.x * t, z: o.center.z + seat.along.z * t };
      position = { x: mid.x + seat.front.x * step, z: mid.z + seat.front.z * step };
    }
  }
  const next: PrevisCharacter = { ...c, position: clearOfFurniture(position, bodyRadius(c), plan) };
  delete next.seatHeight;
  return next;
}

const same = (a: PrevisCharacter, b: PrevisCharacter) =>
  Math.abs(a.position.x - b.position.x) < 0.005 && Math.abs(a.position.z - b.position.z) < 0.005
  && Math.abs(wrap180(a.facing - b.facing)) < 0.5 && a.posture === b.posture
  && Math.abs((a.seatHeight ?? -1) - (b.seatHeight ?? -1)) < 0.005;

/**
 * Settles the people in `scanID` that an edit changed (or all of them when `all`), returning the
 * same array when nothing moved so callers can skip a write.
 */
export function settlePeople(people: PrevisCharacter[], plan: FloorPlan | undefined, scanID: string | undefined,
  before: PrevisCharacter[] = [], all = false): PrevisCharacter[] {
  if (!plan) return people;
  const old = new Map(before.map(c => [c.id, c]));
  let changed = false;
  const out = people.map(c => {
    if (scanID && c.scanID && c.scanID !== scanID) return c;
    const prev = old.get(c.id);
    if (!all && prev === c) return c;
    const next = settlePerson(c, plan, prev);
    if (same(next, c)) return c;
    changed = true;
    return next;
  });
  return changed ? out : people;
}

/**
 * After set pieces move, turn or change size: people seated on a piece go with it, then everyone
 * in the scan is settled again (a piece moved onto a standing person pushes them aside).
 */
export function carryPeople(people: PrevisCharacter[], oldPlan: FloorPlan, plan: FloorPlan, scanID: string | undefined): PrevisCharacter[] {
  let carried = false;
  const moved = people.map(c => {
    if (c.posture !== 'sitting' || c.seatHeight === undefined || (scanID && c.scanID && c.scanID !== scanID)) return c;
    const seat = seatAt(c.position, oldPlan);
    const now = seat && plan.objects.find(o => o.id === seat.object.id);
    if (!seat || !now || now === seat.object) return c;
    const was = seat.object;
    const q = local(was, c.position);
    // Keep the same place on the piece, scaled to its new size.
    const p = world(now, { x: q.x * (now.width / (was.width || 1)), z: q.z * (now.depth / (was.depth || 1)) });
    const turn = ((now.rotation - was.rotation) * 180) / Math.PI;
    carried = true;
    return { ...c, position: { x: r3(p.x), z: r3(p.z) }, facing: Math.round(wrap360(c.facing + turn)) };
  });
  const settled = settlePeople(moved, plan, scanID, moved, true);
  return settled !== moved || carried ? settled : people;
}
