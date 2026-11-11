// Starting points for lighting a person: units placed round them relative to the camera and set
// (with the photometric model) to sensible levels for the camera's exposure. A starting point to
// adjust, not a finished setup; levels are estimates like every other reading.
// Port of FrameScout/Core/Models/LightingSetups.swift: keep the setups and their numbers the same.
import type { ExposureSettings, FloorPlan, LightFixture, LightKind, LightRole, PlanPoint, PrevisCharacter } from './types';
import { DEFAULT_WINDOW_TRANSMISSION, at, bearingFrom, direction, intersect, planAdd, planScale, solveOutput, unitBearing, type IntensitySolution, type Vec } from './calculator';
import { applyProfile, fixtureProfile, modifiersFor, profileByID } from './photometrics';
import { eyeHeight } from './characters';
import { keyLux } from './exposure';
import { newLight } from './factory';

export type LightingSetup = 'threePoint' | 'softSide' | 'beauty' | 'hardSingle' | 'keyAndEdge';

interface Spec {
  name: string; role: LightRole;
  /** Candidate units, smallest first: the first that reaches its level with headroom is used. */
  profiles: string[];
  modifier?: string;
  offset: number;   // degrees from the camera direction, seen from the person
  distance: number;
  rise: number;     // height above eye level
  stopsUnderKey: number;
  rim?: boolean;
  kind?: LightKind; width?: number;
}

export const LIGHTING_SETUPS: { id: LightingSetup; label: string; summary: string; specs: Spec[] }[] = [
  { id: 'threePoint', label: 'Three-point', summary: 'Key, fill 2 stops under, back light', specs: [
    { name: 'Key', role: 'key', profiles: ['cob-100-bi', 'cob-300-d', 'cob-600-d', 'cob-1200-d'], modifier: 'softbox-90-grid', offset: 45, distance: 2.2, rise: 0.6, stopsUnderKey: 0 },
    { name: 'Fill', role: 'fill', profiles: ['panel-1x1-bi', 'panel-2x1-bi'], offset: -40, distance: 2.5, rise: 0.3, stopsUnderKey: 2 },
    { name: 'Back', role: 'back', profiles: ['fresnel-led-200-bi', 'fresnel-led-600-d'], offset: 160, distance: 2.4, rise: 1.0, stopsUnderKey: 0, rim: true },
  ] },
  { id: 'softSide', label: 'Soft side light', summary: 'Big soft key from the side, neg fill', specs: [
    { name: 'Key', role: 'key', profiles: ['cob-300-d', 'cob-600-d', 'cob-1200-d'], modifier: 'softbox-150', offset: 80, distance: 2.0, rise: 0.4, stopsUnderKey: 0 },
    { name: 'Neg', role: 'fill', profiles: [], offset: -80, distance: 1.2, rise: 0, stopsUnderKey: 0, kind: 'negative', width: 1.2 },
  ] },
  { id: 'beauty', label: 'Soft front (beauty)', summary: 'Soft key near the lens, gentle fill', specs: [
    { name: 'Key', role: 'key', profiles: ['cob-100-bi', 'cob-300-d', 'cob-600-d'], modifier: 'softbox-90', offset: 20, distance: 1.8, rise: 0.5, stopsUnderKey: 0 },
    { name: 'Fill', role: 'fill', profiles: ['mat-2x2-bi', 'mat-4x4-bi'], offset: -10, distance: 2.0, rise: -0.4, stopsUnderKey: 1 },
  ] },
  { id: 'hardSingle', label: 'Hard single source', summary: 'One fresnel high from the side, no fill', specs: [
    { name: 'Key', role: 'key', profiles: ['fresnel-led-200-bi', 'fresnel-led-600-d'], offset: 60, distance: 2.6, rise: 1.0, stopsUnderKey: 0 },
  ] },
  { id: 'keyAndEdge', label: 'Key and edge', summary: 'Soft key, hard edge 1 stop over', specs: [
    { name: 'Key', role: 'key', profiles: ['cob-100-bi', 'cob-300-d', 'cob-600-d', 'cob-1200-d'], modifier: 'softbox-90', offset: 50, distance: 2.0, rise: 0.5, stopsUnderKey: 0 },
    { name: 'Edge', role: 'edge', profiles: ['fresnel-led-200-bi', 'fresnel-led-600-d'], offset: -135, distance: 2.4, rise: 0.9, stopsUnderKey: -1, rim: true },
  ] },
];

/** Sets the unit's dimmer from a solved level and says what it was set to, or why it couldn't reach
 *  it. Shared with the user's own presets (presets.ts). */
export function levelNote(light: LightFixture, solution: IntensitySolution, name: string, target: number): string {
  const pct = (o: number) => Math.round(o * 100);
  switch (solution.kind) {
    case 'output':
      light.dimmer = solution.output;
      return `${name}: ${fixtureProfile(light).name} at ${pct(solution.output)} % for ≈ ${Math.round(target)} lx`;
    case 'tooDim':
      light.dimmer = 1;
      return `${name}: even at full ≈ ${Math.round(solution.maxLux)} lx, so move it closer or open the lens`;
    case 'atMinimum':
      light.dimmer = solution.output;
      return `${name}: at its lowest (${pct(solution.output)} %) ≈ ${Math.round(solution.lux)} lx, over the target, so move it back or add ND`;
    default:
      light.dimmer = 0.5;
      return `${name}: couldn't reach the face from here; check its aim`;
  }
}

/** Free distance from `p` along a bearing before the nearest wall (8 m with no plan). */
export function room(p: PlanPoint, bearing: number, plan?: FloorPlan): number {
  if (!plan || !plan.walls.length) return 8;
  const far = planAdd(p, planScale(unitBearing(bearing), 8));
  let best = 8;
  for (const w of plan.walls) { const hit = intersect(p, far, w.a, w.b); if (hit) best = Math.min(best, hit[0] * 8); }
  return best;
}

const unit = (a: Vec): Vec => { const l = Math.hypot(a.x, a.y, a.z) || 1; return { x: a.x / l, y: a.y / l, z: a.z / l }; };

/** Units for `person`, seen from `camera` (absent: from the way the person faces), with one line per
 *  unit on what it was set to or why it couldn't reach its level. The key goes on the side of the
 *  camera axis with more room in the plan. */
export function buildSetup(id: LightingSetup, person: PrevisCharacter, camera: PlanPoint | undefined, exposure: ExposureSettings,
  plan?: FloorPlan, windowTransmission = DEFAULT_WINDOW_TRANSMISSION): { lights: LightFixture[]; notes: string[] } {
  const p = person.position;
  const towardCamera = camera ? bearingFrom(p, camera) : person.facing;
  const face = at(p, Math.max(0.3, eyeHeight(person) - 0.03));
  const faceNormal = direction(towardCamera, 0);
  const key = keyLux(exposure);
  const side = room(p, towardCamera + 60, plan) >= room(p, towardCamera - 60, plan) ? 1 : -1;
  const lights: LightFixture[] = [], notes: string[] = [];
  for (const spec of LIGHTING_SETUPS.find(s => s.id === id)!.specs) {
    const bearing = towardCamera + side * spec.offset;
    const d = Math.min(spec.distance, Math.max(0.6, room(p, bearing, plan) - 0.4));
    const pos = planAdd(p, planScale(unitBearing(bearing), d));
    const pan = bearingFrom(pos, p);
    const name = `${spec.name} · ${person.name}`;
    if (spec.kind || !spec.profiles.length) {
      // Grip: a board standing at face height.
      const board = { ...newLight(spec.kind ?? 'negative', pos, pan, person.scanID), name, role: spec.role, height: Math.max(0.6, face.y), boardHeight: 1.2 };
      if (spec.width) board.width = spec.width;
      lights.push(board);
      continue;
    }
    const target = key / Math.pow(2, spec.stopsUnderKey);
    let chosen: { light: LightFixture; solution: IntensitySolution } | undefined;
    for (const pid of spec.profiles) {
      const profile = profileByID(pid);
      if (!profile) continue;
      const light = applyProfile({ ...newLight(profile.kind, pos, pan, person.scanID), name }, profile);
      light.role = spec.role;
      if (spec.modifier && modifiersFor(profile).some(m => m.id === spec.modifier)) light.modifierID = spec.modifier;
      light.height = Math.max(0.4, face.y + spec.rise);
      light.tilt = -Math.atan2(light.height - face.y, d) * 180 / Math.PI;
      // Back light: metered facing the unit (rim), the others towards camera.
      const normal = spec.rim ? unit({ x: pos.x - face.x, y: light.height - face.y, z: pos.z - face.z }) : faceNormal;
      const solution = solveOutput(light, target, face, normal, [light], plan, windowTransmission);
      chosen = { light, solution };
      if (solution.kind === 'output' && solution.output <= 0.8) break;
    }
    if (!chosen) continue;
    const { light, solution } = chosen;
    notes.push(levelNote(light, solution, spec.name, target));
    lights.push(light);
  }
  return { lights, notes };
}
