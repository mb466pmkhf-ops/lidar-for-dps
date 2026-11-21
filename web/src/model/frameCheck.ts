// What a camera would see that shouldn't be in the shot: units, their stands and grip frames.
// Port of FrameScout/Core/Models/FrameCheck.swift: keep the sample points and rules the same.
// Geometry only (no lens distortion, no set pieces hiding things), so the panels call it a check, not a
// guarantee. Practicals are meant to be seen and are never listed.
import type { CameraRig, FloorPlan, LightFixture } from './types';
import { direction, intersect, unitBearing } from './calculator';
import { imageArea } from './camera';
import { gripStandCount, lightSupport } from './rigging';
import { gripSpan, isGrip } from './grip';
import { modifierByID } from './photometrics';

export type FramePart = 'unit' | 'stand';
export interface FrameIntrusion { id: string; name: string; part: FramePart }

/** Nearer than this to the lens is ignored (the unit is beside the camera, not in front of it). */
export const FRAME_NEAR = 0.25;
/** How far a stand's legs reach from its column (m), roughly, for a C-stand or combo. */
export const STAND_SPREAD = 0.4;
/** A MegaBoom's column stands this far behind the head, as the 3D view draws it (m). */
export const BOOM_REACH = 2.2;

interface P3 { x: number; y: number; z: number }

/** True when the point sits inside the camera's frame (image area at the rig's focal length). */
export function pointInFrame(rig: CameraRig, p: P3): boolean {
  const area = imageArea(rig);
  if (!(rig.focalLength > 0)) return false;
  const f = direction(rig.pan, rig.tilt);
  const right = direction(rig.pan + 90, 0);
  // up = right × forward, so a camera tilted down still has its frame's top edge up.
  const up = { x: right.y * f.z - right.z * f.y, y: right.z * f.x - right.x * f.z, z: right.x * f.y - right.y * f.x };
  const v = { x: p.x - rig.position.x, y: p.y - rig.height, z: p.z - rig.position.z };
  const depth = v.x * f.x + v.y * f.y + v.z * f.z;
  if (depth < FRAME_NEAR) return false;
  const sx = (v.x * right.x + v.y * right.y + v.z * right.z) / depth;
  const sy = (v.x * up.x + v.y * up.y + v.z * up.z) / depth;
  return Math.abs(sx) <= area.width / (2 * rig.focalLength) && Math.abs(sy) <= area.height / (2 * rig.focalLength);
}

/** Walls between the lens and the point hide it where the sight line passes between the wall's bottom
 *  and top (doors and windows are treated as wall). */
function hiddenByWall(rig: CameraRig, p: P3, plan?: FloorPlan): boolean {
  if (!plan) return false;
  for (const w of plan.walls) {
    const hit = intersect(rig.position, { x: p.x, z: p.z }, w.a, w.b);
    if (!hit || hit[0] <= 1e-3 || hit[0] >= 1 - 1e-3) continue;
    const y = rig.height + (p.y - rig.height) * hit[0];
    if (y >= w.bottom && y <= w.bottom + w.height) return true;
  }
  return false;
}

/** Points along a unit and its stand(s), in metres: the head (and both edges of anything wide), a
 *  board's whole face (tilt and an opened floppy included), a softbox's front, then the stand from the
 *  floor to just under the head (a MegaBoom's column and arm behind it). Rigged, floor and stand-less
 *  units have no stand. */
export function samplePoints(l: LightFixture): { part: FramePart; p: P3 }[] {
  const out: { part: FramePart; p: P3 }[] = [];
  const side = unitBearing(l.pan + 90);
  const half = Math.max(0, l.width) / 2;
  const head = (dx: number) => ({ x: l.position.x + side.x * dx, y: l.height, z: l.position.z + side.z * dx });
  const along = (o: P3, d: P3, k: number) => ({ x: o.x + d.x * k, y: o.y + d.y * k, z: o.z + d.z * k });
  out.push({ part: 'unit', p: head(0) });
  if (half > 0.05) { out.push({ part: 'unit', p: head(-half) }, { part: 'unit', p: head(half) }); }
  if (isGrip(l.kind)) {
    // The face runs lo…hi along its own up, which leans with the board's tilt.
    const span = gripSpan(l);
    const up = direction(l.pan, l.tilt + 90);
    const lo = span.bottom - l.height, hi = span.top - l.height;
    for (const du of [lo, (lo + hi) / 2, hi]) {
      for (const dx of half > 0.05 ? [-half, 0, half] : [0]) if (du !== 0) out.push({ part: 'unit', p: along(head(dx), up, du) });
    }
  } else {
    const mod = modifierByID(l.modifierID);
    if (mod?.id.startsWith('softbox')) {
      // Same face as the 3D view: radius size/2, its depth (size/2) plus the mount ahead of the head.
      const size = mod.size ?? 0.9, r = size / 2;
      const axis = direction(l.pan, l.tilt), right = direction(l.pan + 90, 0);
      const up = { x: right.y * axis.z - right.z * axis.y, y: right.z * axis.x - right.x * axis.z, z: right.x * axis.y - right.y * axis.x };
      const face = along(head(0), axis, 0.03 + size * 0.5);
      out.push({ part: 'unit', p: face });
      for (const [a, b] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) out.push({ part: 'unit', p: along(along(face, right, a * r), up, b * r) });
    }
  }
  const s = lightSupport(l);
  if (s === 'overhead' || s === 'floor' || s === 'none') return out;
  const column = (at: P3) => {
    for (const t of [0.05, 0.35, 0.65]) out.push({ part: 'stand', p: { ...at, y: Math.max(0.02, l.height * t) } });
    // The legs spread out round the base.
    for (const b of [0, 120, 240]) {
      const d = unitBearing(l.pan + b);
      out.push({ part: 'stand', p: { x: at.x + d.x * STAND_SPREAD, y: 0.02, z: at.z + d.z * STAND_SPREAD } });
    }
  };
  if (s === 'megaBoom') {
    // The column stands behind the head; the arm runs out over the head and on to a counterweight.
    const back = unitBearing(l.pan + 180);
    const base = head(0);
    const arm = (k: number) => ({ x: base.x + back.x * k, y: l.height + 0.12, z: base.z + back.z * k });
    column({ ...arm(BOOM_REACH), y: l.height });
    for (const k of [0.5, 1.1, 1.65, BOOM_REACH + 0.95]) out.push({ part: 'stand', p: arm(k) });
    return out;
  }
  for (const dx of gripStandCount(l) === 2 ? [-half, half] : [0]) column(head(dx));
  return out;
}

/** Units, grip and stands the camera would see, in the order they're listed in the room. Units that
 *  are off are still listed: a dark stand is still in shot. */
export function unitsInFrame(rig: CameraRig, lights: LightFixture[], plan?: FloorPlan): FrameIntrusion[] {
  const result: FrameIntrusion[] = [];
  for (const l of lights) {
    if (l.kind === 'practical' || l.role === 'practical') continue;
    let part: FramePart | undefined;
    for (const s of samplePoints(l)) {
      if (!pointInFrame(rig, s.p) || hiddenByWall(rig, s.p, plan)) continue;
      if (s.part === 'unit') { part = 'unit'; break; }
      part = 'stand';
    }
    if (part) result.push({ id: l.id, name: l.name, part });
  }
  return result;
}

/** "Key and Fill are in shot", "Back's stand is in shot". Empty when the frame is clean. */
export function inFrameSentence(list: FrameIntrusion[]): string {
  if (!list.length) return '';
  const units = list.filter(i => i.part === 'unit').map(i => i.name);
  const stands = list.filter(i => i.part === 'stand').map(i => i.name);
  const join = (n: string[]) => (n.length <= 1 ? n.join('') : `${n.slice(0, -1).join(', ')} and ${n[n.length - 1]}`);
  const parts: string[] = [];
  if (units.length) parts.push(`${join(units)} ${units.length === 1 ? 'is' : 'are'} in shot`);
  if (stands.length) parts.push(`${stands.length === 1 ? `${stands[0]}'s stand is` : `the stands of ${join(stands)} are`} in shot`);
  const s = parts.join('; ');
  return s.charAt(0).toUpperCase() + s.slice(1) + '.';
}
