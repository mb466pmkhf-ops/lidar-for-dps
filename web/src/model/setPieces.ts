// Adding and changing the set by hand: doors, windows and openings that sit in a wall, and
// furniture that stands on the floor. Mirrors FrameScout/Core/Models/SetPieces.swift; keep the
// sizes and the snapping rules identical (tests on both sides check the same cases).
//
// Every size here is a typical one picked from a list or typed in, never a measurement, so
// everything placed or changed here carries `byHand: true` and the panels say so.
import type { FloorPlan, PlanObject, PlanPoint, PlanSegment, PlanSegmentKind } from './types';
import { uuid } from './factory';

export interface OpeningPreset { id: string; label: string; kind: Exclude<PlanSegmentKind, 'wall'>; width: number; height: number; sill: number }
export interface FurniturePreset { id: string; label: string; category: string; width: number; depth: number; height: number }

/** Width along the wall, height of the hole, sill above the floor (m). */
export const OPENING_PRESETS: OpeningPreset[] = [
  { id: 'door', label: 'Door', kind: 'door', width: 0.9, height: 2.05, sill: 0 },
  { id: 'double-door', label: 'Double door', kind: 'door', width: 1.6, height: 2.1, sill: 0 },
  { id: 'window', label: 'Window', kind: 'window', width: 1.2, height: 1.4, sill: 0.85 },
  { id: 'tall-window', label: 'Tall window', kind: 'window', width: 1.4, height: 2.2, sill: 0.1 },
  { id: 'opening', label: 'Opening', kind: 'opening', width: 1.0, height: 2.1, sill: 0 },
];

/** Typical sizes. `category` is what the 3D view and the phone draw it as (RoomPlan's names). */
export const FURNITURE_PRESETS: FurniturePreset[] = [
  { id: 'sofa', label: 'Sofa', category: 'Sofa', width: 2.0, depth: 0.9, height: 0.85 },
  { id: 'armchair', label: 'Armchair', category: 'Chair', width: 0.85, depth: 0.85, height: 0.9 },
  { id: 'chair', label: 'Chair', category: 'Chair', width: 0.48, depth: 0.5, height: 0.9 },
  { id: 'dining-table', label: 'Dining table', category: 'Table', width: 1.6, depth: 0.9, height: 0.75 },
  { id: 'coffee-table', label: 'Coffee table', category: 'Table', width: 1.1, depth: 0.6, height: 0.45 },
  { id: 'desk', label: 'Desk', category: 'Desk', width: 1.4, depth: 0.7, height: 0.75 },
  { id: 'bed', label: 'Double bed', category: 'Bed', width: 2.0, depth: 1.5, height: 0.55 },
  { id: 'wardrobe', label: 'Wardrobe', category: 'Storage', width: 1.2, depth: 0.6, height: 2.0 },
  { id: 'sideboard', label: 'Sideboard', category: 'Storage', width: 1.6, depth: 0.45, height: 0.8 },
  { id: 'shelves', label: 'Shelves', category: 'Shelf', width: 0.9, depth: 0.35, height: 1.8 },
  { id: 'fridge', label: 'Fridge', category: 'Refrigerator', width: 0.6, depth: 0.65, height: 1.8 },
  { id: 'cooker', label: 'Cooker', category: 'Stove', width: 0.6, depth: 0.6, height: 0.9 },
  { id: 'sink', label: 'Sink unit', category: 'Sink', width: 0.8, depth: 0.6, height: 0.9 },
  { id: 'bath', label: 'Bath', category: 'Bathtub', width: 1.7, depth: 0.75, height: 0.55 },
  { id: 'toilet', label: 'Toilet', category: 'Toilet', width: 0.4, depth: 0.65, height: 0.8 },
  { id: 'fireplace', label: 'Fireplace', category: 'Fireplace', width: 1.4, depth: 0.4, height: 1.1 },
  { id: 'box', label: 'Box', category: 'Box', width: 0.6, depth: 0.6, height: 0.6 },
];

export const openingPreset = (id: string) => OPENING_PRESETS.find(p => p.id === id);
export const furniturePreset = (id: string) => FURNITURE_PRESETS.find(p => p.id === id);

/** How far from a wall a click may be and still put a door or window in it (m). */
export const WALL_REACH = 1.0;
/** Furniture dropped this close to a wall (beyond its own half depth) turns and backs onto it. */
export const FURNITURE_WALL_SNAP = 0.5;
export const MIN_OPENING = 0.3;
export const SIZE_LIMITS = { min: 0.1, max: 12, heightMax: 6 };

const r3 = (v: number) => Math.round(v * 1000) / 1000;
/** Angles keep more places, so four quarter turns come back to where they started. */
const r6 = (v: number) => Math.round(v * 1e6) / 1e6;
const P = (x: number, z: number): PlanPoint => ({ x: r3(x), z: r3(z) });
const len = (a: PlanPoint, b: PlanPoint) => Math.hypot(b.x - a.x, b.z - a.z);
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export interface WallHit { wall: PlanSegment; t: number; point: PlanPoint; distance: number }

/** The wall closest to `p`, with the closest point on it (t from a to b). */
export function nearestWall(plan: FloorPlan | undefined, p: PlanPoint): WallHit | undefined {
  let best: WallHit | undefined;
  for (const wall of plan?.walls ?? []) {
    const dx = wall.b.x - wall.a.x, dz = wall.b.z - wall.a.z, l2 = dx * dx + dz * dz;
    if (l2 < 1e-6) continue;
    const t = clamp(((p.x - wall.a.x) * dx + (p.z - wall.a.z) * dz) / l2, 0, 1);
    const point = { x: wall.a.x + dx * t, z: wall.a.z + dz * t };
    const distance = len(point, p);
    if (!best || distance < best.distance) best = { wall, t, point, distance };
  }
  return best;
}

/** Middle of the floor, used to tell which side of a wall is the room. */
export function interiorCentroid(plan: FloorPlan): PlanPoint {
  const pts = plan.floorPolygons.flat();
  const src = pts.length ? pts : plan.walls.flatMap(w => [w.a, w.b]);
  if (!src.length) return { x: (plan.bounds.minX + plan.bounds.maxX) / 2, z: (plan.bounds.minZ + plan.bounds.maxZ) / 2 };
  return { x: src.reduce((s, q) => s + q.x, 0) / src.length, z: src.reduce((s, q) => s + q.z, 0) / src.length };
}

/** A segment `width` wide centred on the wall at `centre`, kept inside the wall's ends. */
function onWall(wall: PlanSegment, centre: PlanPoint, width: number): { a: PlanPoint; b: PlanPoint } {
  const L = len(wall.a, wall.b);
  const w = clamp(width, Math.min(MIN_OPENING, L), Math.max(Math.min(MIN_OPENING, L), L - 0.1));
  const ux = (wall.b.x - wall.a.x) / L, uz = (wall.b.z - wall.a.z) / L;
  const along = clamp((centre.x - wall.a.x) * ux + (centre.z - wall.a.z) * uz, w / 2, L - w / 2);
  return { a: P(wall.a.x + ux * (along - w / 2), wall.a.z + uz * (along - w / 2)), b: P(wall.a.x + ux * (along + w / 2), wall.a.z + uz * (along + w / 2)) };
}

/** Keeps the hole inside the wall's height: the sill first, then the height. */
function fitHeight(wall: PlanSegment, height: number, sill: number): { height: number; bottom: number } {
  const top = wall.bottom + wall.height - 0.05;
  const bottom = r3(clamp(sill, 0, Math.max(0, top - 0.3)));
  return { bottom, height: r3(clamp(height, 0.3, Math.max(0.3, top - bottom))) };
}

/** A door, window or opening in the wall nearest `p`, or undefined when no wall is within reach. */
export function placeOpening(plan: FloorPlan | undefined, p: PlanPoint, preset: OpeningPreset, reach = WALL_REACH): PlanSegment | undefined {
  const hit = nearestWall(plan, p);
  if (!hit || hit.distance > reach) return undefined;
  const { a, b } = onWall(hit.wall, hit.point, preset.width);
  return { id: uuid(), kind: preset.kind, a, b, ...fitHeight(hit.wall, preset.height, preset.sill), isOpen: false, byHand: true };
}

/** Slides an opening to the point on the nearest wall under `p` (it can change walls). Same size. */
export function slideOpening(plan: FloorPlan, seg: PlanSegment, p: PlanPoint): PlanSegment {
  const hit = nearestWall(plan, p);
  if (!hit) return seg;
  const { a, b } = onWall(hit.wall, hit.point, len(seg.a, seg.b));
  return { ...seg, a, b, ...fitHeight(hit.wall, seg.height, seg.bottom), byHand: true };
}

/** New width, same centre, on the same wall. */
export function resizeOpening(plan: FloorPlan, seg: PlanSegment, width: number): PlanSegment {
  const mid = { x: (seg.a.x + seg.b.x) / 2, z: (seg.a.z + seg.b.z) / 2 };
  const hit = nearestWall(plan, mid);
  if (!hit) return seg;
  return { ...seg, ...onWall(hit.wall, mid, width), byHand: true };
}

/** Height and sill, kept inside the wall. */
export function setOpeningHeight(plan: FloorPlan, seg: PlanSegment, height: number, sill: number): PlanSegment {
  const mid = { x: (seg.a.x + seg.b.x) / 2, z: (seg.a.z + seg.b.z) / 2 };
  const hit = nearestWall(plan, mid);
  const fitted = hit ? fitHeight(hit.wall, height, sill) : { height: r3(Math.max(0.3, height)), bottom: r3(Math.max(0, sill)) };
  return { ...seg, ...fitted, byHand: true };
}

/** Rotation (radians, plan screen space) and centre that put the box's back flat against the wall. */
export function backOntoWall(plan: FloorPlan | undefined, center: PlanPoint, depth: number, snap = FURNITURE_WALL_SNAP): { center: PlanPoint; rotation: number } | undefined {
  if (!plan) return undefined;
  const hit = nearestWall(plan, center);
  if (!hit || hit.distance > depth / 2 + snap || hit.t <= 0 || hit.t >= 1) return undefined;
  const { wall } = hit;
  const L = len(wall.a, wall.b);
  const ux = (wall.b.x - wall.a.x) / L, uz = (wall.b.z - wall.a.z) / L;
  // Normal pointing into the room (towards the floor's middle).
  let nx = -uz, nz = ux;
  const c = interiorCentroid(plan);
  if ((c.x - hit.point.x) * nx + (c.z - hit.point.z) * nz < 0) { nx = -nx; nz = -nz; }
  const off = depth / 2 + 0.02;
  return { center: P(hit.point.x + nx * off, hit.point.z + nz * off), rotation: r6(Math.atan2(uz, ux)) };
}

/** A piece of furniture at `p`; near a wall it turns to back onto it. */
export function placeFurniture(plan: FloorPlan | undefined, p: PlanPoint, preset: FurniturePreset): PlanObject {
  const snapped = backOntoWall(plan, p, preset.depth);
  return {
    id: uuid(), category: preset.category, center: snapped?.center ?? P(p.x, p.z),
    width: preset.width, depth: preset.depth, height: preset.height, rotation: snapped?.rotation ?? 0, byHand: true,
  };
}

/** Turns a piece by a quarter (or any) turn about its centre, keeping rotation in (−π, π]. */
export function turnObject(o: PlanObject, radians: number): PlanObject {
  let r = o.rotation + radians;
  while (r > Math.PI) r -= 2 * Math.PI;
  while (r <= -Math.PI) r += 2 * Math.PI;
  return { ...o, rotation: r6(r), byHand: true };
}

export const clampSize = (v: number, max = SIZE_LIMITS.max) => r3(clamp(Number.isFinite(v) ? v : SIZE_LIMITS.min, SIZE_LIMITS.min, max));

// MARK: Editing a plan (pure: each returns a new plan)

const listFor = (kind: PlanSegmentKind): 'walls' | 'doors' | 'windows' | 'openings' =>
  kind === 'door' ? 'doors' : kind === 'window' ? 'windows' : kind === 'opening' ? 'openings' : 'walls';

export function findSegment(plan: FloorPlan | undefined, id: string): PlanSegment | undefined {
  if (!plan) return undefined;
  return [...plan.doors, ...plan.windows, ...plan.openings].find(s => s.id === id);
}

export function addSegment(plan: FloorPlan, seg: PlanSegment): FloorPlan {
  const key = listFor(seg.kind);
  return { ...plan, [key]: [...plan[key], seg] };
}

/** Replaces a door, window or opening; a changed kind moves it to the matching list. */
export function replaceSegment(plan: FloorPlan, seg: PlanSegment): FloorPlan {
  const cleared = removeSegment(plan, seg.id);
  const key = listFor(seg.kind);
  const old = findSegment(plan, seg.id);
  if (old && listFor(old.kind) === key) return { ...plan, [key]: plan[key].map(s => (s.id === seg.id ? seg : s)) };
  return addSegment(cleared, seg);
}

export function removeSegment(plan: FloorPlan, id: string): FloorPlan {
  return { ...plan, doors: plan.doors.filter(s => s.id !== id), windows: plan.windows.filter(s => s.id !== id), openings: plan.openings.filter(s => s.id !== id) };
}

export const addObject = (plan: FloorPlan, o: PlanObject): FloorPlan => ({ ...plan, objects: [...plan.objects, o] });
export const replaceObject = (plan: FloorPlan, o: PlanObject): FloorPlan => ({ ...plan, objects: plan.objects.map(x => (x.id === o.id ? o : x)) });
export const removeObject = (plan: FloorPlan, id: string): FloorPlan => ({ ...plan, objects: plan.objects.filter(x => x.id !== id) });

/** A display name for a set piece: the preset it matches, else its category. */
export function setPieceName(o: PlanObject): string {
  const p = FURNITURE_PRESETS.find(f => f.category === o.category && Math.abs(f.width - o.width) < 1e-6 && Math.abs(f.depth - o.depth) < 1e-6);
  return p?.label ?? o.category;
}

export const openingLabel = (kind: PlanSegmentKind) => (kind === 'door' ? 'Door' : kind === 'window' ? 'Window' : kind === 'opening' ? 'Opening' : 'Wall');
