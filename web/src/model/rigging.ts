// Stands and camera supports. Port of FrameScout/Core/Models/Rigging.swift: keep the automatic
// rules and ranges the same on both sides. Drawing and labels only; never changes the lux maths.
import type { CameraRig, FloorPlan, LightFixture, PlanPoint } from './types';
import { fixtureModifier, fixtureProfile } from './photometrics';
import { intersect, unitBearing } from './calculator';

export type LightSupport = 'cStand' | 'comboStand' | 'turtleBase' | 'megaBoom' | 'rollerStand' | 'overhead' | 'floor' | 'none';
export type CameraSupport = 'tripod' | 'babyLegs' | 'highHat' | 'dolly' | 'slider' | 'handheld' | 'gimbal';

type Range = [number, number];

export const LIGHT_SUPPORTS: { id: LightSupport; label: string; range?: Range }[] = [
  { id: 'cStand', label: 'C-stand', range: [1.0, 3.3] },
  { id: 'comboStand', label: 'Combo stand', range: [1.2, 4.0] },
  { id: 'turtleBase', label: 'Turtle base', range: [0.2, 0.75] },
  { id: 'megaBoom', label: 'MegaBoom', range: [1.5, 4.5] },
  { id: 'rollerStand', label: 'Roller stand', range: [1.4, 4.9] },
  { id: 'overhead', label: 'Rigged overhead' },
  { id: 'floor', label: 'On the floor' },
  { id: 'none', label: 'No stand' },
];

export const CAMERA_SUPPORTS: { id: CameraSupport; label: string; short: string; range: Range }[] = [
  { id: 'tripod', label: "Tripod · O'Connor head", short: 'tripod', range: [0.9, 2.0] },
  { id: 'babyLegs', label: 'Baby legs', short: 'baby legs', range: [0.45, 1.05] },
  { id: 'highHat', label: 'High hat', short: 'high hat', range: [0.1, 0.45] },
  { id: 'dolly', label: 'Dolly', short: 'dolly', range: [0.6, 2.1] },
  { id: 'slider', label: 'Slider', short: 'slider', range: [0.2, 1.9] },
  { id: 'handheld', label: 'Handheld', short: 'handheld', range: [0.6, 1.9] },
  { id: 'gimbal', label: 'Gimbal', short: 'gimbal', range: [0.6, 1.9] },
];

export const lightSupportInfo = (s: LightSupport) => LIGHT_SUPPORTS.find(x => x.id === s)!;
export const cameraSupportInfo = (s: CameraSupport) => CAMERA_SUPPORTS.find(x => x.id === s)!;

/** Practicals sit on their own, space lights hang, very low units go on a turtle base, heavy heads and
 *  big frames on a combo, the rest on a C-stand. */
export function automaticLightSupport(l: LightFixture): LightSupport {
  if (l.kind === 'practical') return 'none';
  if (l.kind === 'spaceLight') return 'overhead';
  if (l.height < 0.15) return 'floor';
  if (l.height < 0.75) return 'turtleBase';
  if (l.kind === 'bounce' || l.kind === 'negative' || l.kind === 'diffusion') return l.width >= 1 ? 'comboStand' : 'cStand';
  if (l.kind === 'flag') return 'cStand';
  const p = fixtureProfile(l);
  const modSize = fixtureModifier(l)?.size ?? 0;
  if (p.category === 'hmi' || p.ratedPower >= 1000 || modSize >= 0.9 || p.emitterWidth >= 0.9) return 'comboStand';
  return 'cStand';
}

export const lightSupport = (l: LightFixture): LightSupport => (l.support as LightSupport | undefined) ?? automaticLightSupport(l);

export function automaticCameraSupport(height: number): CameraSupport {
  if (height < 0.45) return 'highHat';
  if (height < 0.9) return 'babyLegs';
  return 'tripod';
}

export const cameraSupport = (r: CameraRig): CameraSupport => (r.support as CameraSupport | undefined) ?? automaticCameraSupport(r.height);

const m1 = (v: number) => `${v.toFixed(1)} m`;

export function lightSupportWarning(l: LightFixture): string | undefined {
  const s = lightSupportInfo(lightSupport(l));
  if (!s.range) return undefined;
  if (l.height > s.range[1] + 0.05) return `Higher than a ${s.label} usually goes (${m1(s.range[1])})`;
  if (l.height < s.range[0] - 0.05) return `Lower than a ${s.label} usually goes (${m1(s.range[0])})`;
  return undefined;
}

export function cameraSupportWarning(r: CameraRig): string | undefined {
  const s = cameraSupportInfo(cameraSupport(r));
  if (r.height > s.range[1] + 0.05) return `Higher than ${s.short} usually goes (${m1(s.range[1])})`;
  if (r.height < s.range[0] - 0.05) return `Lower than ${s.short} usually goes (${m1(s.range[0])})`;
  return undefined;
}

/** Plan distance from `origin` along `bearing` to the first wall, window or closed door, capped at
 *  `limit`, so drawn beams stop at the room. Same as BeamClip.planReach on iOS. */
export function planReach(origin: PlanPoint, bearing: number, limit: number, plan?: FloorPlan): number {
  if (!plan || limit <= 0) return limit;
  const u = unitBearing(bearing);
  const end = { x: origin.x + u.x * limit, z: origin.z + u.z * limit };
  let best = 1;
  for (const seg of [...plan.walls, ...plan.windows, ...plan.doors]) {
    if (seg.isOpen) continue;
    const hit = intersect(origin, end, seg.a, seg.b);
    if (hit && hit[0] < best) best = hit[0];
  }
  return limit * best;
}
