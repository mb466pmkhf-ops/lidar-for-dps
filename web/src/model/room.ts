// A room drawn by hand instead of scanned: a starting shape plus typed sizes become the same
// FloorPlan a scan produces, so the 2D plan, the 3D view and the lighting maths all work on it.
// Every size here is typed in, so the app treats it as "manual", never as a measurement.
import type { FloorPlan, Location, PlanPoint, PlanSegment, ScanRecord } from './types';
import { isoNow, newLocation, uuid } from './factory';

export type RoomShape = 'box' | 'l';
export interface RoomSpec {
  shape: RoomShape;
  /** Longer side, along x (m). */
  length: number;
  /** Shorter side, along z (m). */
  width: number;
  ceiling: number;
  /** Windows spread along the top wall. */
  windows: number;
  door: boolean;
}

export const ROOM_LIMITS = { min: 1.5, max: 60, ceilingMin: 1.8, ceilingMax: 20 };
export const defaultRoom: RoomSpec = { shape: 'box', length: 6, width: 4.5, ceiling: 2.7, windows: 1, door: true };

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, Number.isFinite(v) ? v : lo));
const P = (x: number, z: number): PlanPoint => ({ x: Math.round(x * 1000) / 1000, z: Math.round(z * 1000) / 1000 });

export function normalise(spec: RoomSpec): RoomSpec {
  return {
    shape: spec.shape === 'l' ? 'l' : 'box',
    length: clamp(spec.length, ROOM_LIMITS.min, ROOM_LIMITS.max),
    width: clamp(spec.width, ROOM_LIMITS.min, ROOM_LIMITS.max),
    ceiling: clamp(spec.ceiling, ROOM_LIMITS.ceilingMin, ROOM_LIMITS.ceilingMax),
    windows: Math.round(clamp(spec.windows, 0, 4)),
    door: !!spec.door,
  };
}

/** Corners, clockwise from the top-left, centred on the origin. The L shape loses its bottom-right quarter. */
export function roomOutline(raw: RoomSpec): PlanPoint[] {
  const s = normalise(raw);
  const hx = s.length / 2, hz = s.width / 2;
  if (s.shape === 'l') return [P(-hx, -hz), P(hx, -hz), P(hx, 0), P(0, 0), P(0, hz), P(-hx, hz)];
  return [P(-hx, -hz), P(hx, -hz), P(hx, hz), P(-hx, hz)];
}

export function roomArea(raw: RoomSpec): number {
  const s = normalise(raw);
  return s.length * s.width * (s.shape === 'l' ? 0.75 : 1);
}

export function buildRoomPlan(raw: RoomSpec): FloorPlan {
  const s = normalise(raw);
  const corners = roomOutline(s);
  const hx = s.length / 2, hz = s.width / 2;
  const seg = (kind: PlanSegment['kind'], a: PlanPoint, b: PlanPoint, height: number, bottom: number): PlanSegment =>
    ({ id: uuid(), kind, a, b, height, bottom, isOpen: false });
  const windows: PlanSegment[] = [];
  if (s.windows > 0) {
    // Evenly spaced along the top wall, never wider than 1.4 m or 60% of their slot.
    const slot = s.length / s.windows;
    const w = Math.min(1.4, slot * 0.6);
    const top = Math.min(s.ceiling - 0.2, 2.3), sill = Math.min(0.8, top - 0.5);
    for (let i = 0; i < s.windows; i++) {
      const cx = -hx + slot * (i + 0.5);
      windows.push(seg('window', P(cx - w / 2, -hz), P(cx + w / 2, -hz), top - sill, sill));
    }
  }
  const doors: PlanSegment[] = [];
  if (s.door) {
    // On the left wall, half a metre from the bottom corner when the wall is long enough.
    const dw = Math.min(0.9, s.width * 0.5);
    const inset = Math.min(0.5, (s.width - dw) / 2);
    doors.push(seg('door', P(-hx, hz - inset), P(-hx, hz - inset - dw), Math.min(2.05, s.ceiling), 0));
  }
  return {
    walls: corners.map((c, i) => seg('wall', c, corners[(i + 1) % corners.length], s.ceiling, 0)),
    doors, windows, openings: [], floorPolygons: [corners], objects: [], occupancy: [], occupancyCellSize: 0.1, floorY: 0,
    bounds: { minX: -hx, minZ: -hz, maxX: hx, maxZ: hz },
  };
}

/** A new location holding the drawn room, with its plan keyed by the new scan id. */
export function buildRoom(name: string, raw: RoomSpec): { location: Location; scanID: string; plan: FloorPlan } {
  const s = normalise(raw);
  const plan = buildRoomPlan(s);
  const scanID = uuid();
  const scan: ScanRecord = {
    id: scanID, name: 'Drawn by hand', kind: 'room', createdAt: isoNow(), segmentCount: 1, deviceModel: '',
    notes: 'Drawn by hand. Sizes were typed in, not measured.',
    stats: {
      floorArea: Math.round(roomArea(s) * 100) / 100, floorAreaIsEstimate: false,
      width: Math.min(s.width, s.length), length: Math.max(s.width, s.length), ceilingHeight: s.ceiling,
      wallCount: plan.walls.length, doorCount: plan.doors.length, windowCount: plan.windows.length, openingCount: 0, floorCount: 1,
      objectCount: 0, objectCategories: {},
      doors: plan.doors.map(d => ({ width: Math.hypot(d.b.x - d.a.x, d.b.z - d.a.z), height: d.height, sillHeight: 0 })),
      windows: plan.windows.map(w => ({ width: Math.hypot(w.b.x - w.a.x, w.b.z - w.a.z), height: w.height, sillHeight: w.bottom })),
      meshVertexCount: 0, meshFaceCount: 0,
      // The phone reads this to label the figures as manual rather than measured.
      enteredByHand: true,
    },
  };
  const location: Location = { ...newLocation(name.trim() || 'New room'), scans: [scan], primaryScanID: scanID };
  return { location, scanID, plan };
}
