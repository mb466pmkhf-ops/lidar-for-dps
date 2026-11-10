// Line-for-line port of FrameScout/Core/Models/Photometrics.swift. Keep the two in step: the lux a
// crew sees must be the same on the phone, the web and the desktop. See Docs/DECISIONS.md D-006.
import type { BarnDoors, LightFixture, LightKind, PhotometricReference, Provenance } from './types';
import { kelvinRGB } from './kelvin';

export type BeamDistribution = 'beam' | 'lambertian' | 'omni' | 'tube';
export type FixtureCategory = 'cob' | 'fresnel' | 'panel' | 'tube' | 'soft' | 'hmi' | 'tungsten' | 'spaceLight' | 'practical';
export type LampTechnology = 'led' | 'hmi' | 'tungsten';
type Range = [number, number];
export type RGB = { r: number; g: number; b: number };

export const categoryLabel: Record<FixtureCategory, string> = {
  cob: 'COB LED', fresnel: 'Fresnel', panel: 'LED panel', tube: 'LED tube', soft: 'Soft source',
  hmi: 'HMI', tungsten: 'Tungsten', spaceLight: 'Space light / lantern', practical: 'Practical',
};

export function relativeIntensity(d: BeamDistribution, theta: number, beamAngle: number): number {
  switch (d) {
    case 'beam': {
      const half = Math.max(beamAngle, 1) / 2;
      if (!(theta < 179)) return 0;
      return Math.pow(2, -Math.pow(theta / half, 4));
    }
    case 'lambertian': return Math.max(0, Math.cos(theta * Math.PI / 180));
    case 'omni': return 1;
    case 'tube': return Math.abs(Math.sin(theta * Math.PI / 180));
  }
}

const solidAngleCache = new Map<number, number>();
export function solidAngleFactor(d: BeamDistribution, beamAngle: number): number {
  switch (d) {
    case 'lambertian': return Math.PI;
    case 'omni': return 4 * Math.PI;
    case 'tube': return Math.PI * Math.PI;
    case 'beam': {
      const cached = solidAngleCache.get(beamAngle);
      if (cached !== undefined) return cached;
      const n = 720;
      const h = Math.PI / n;
      let sum = 0;
      for (let i = 0; i <= n; i++) {
        const t = i * h;
        const f = relativeIntensity('beam', t * 180 / Math.PI, beamAngle) * Math.sin(t);
        sum += f * (i === 0 || i === n ? 1 : (i % 2 === 1 ? 4 : 2));
      }
      const v = 2 * Math.PI * sum * h / 3;
      solidAngleCache.set(beamAngle, v);
      return v;
    }
  }
}

export function nominalBeam(d: BeamDistribution): number | undefined {
  switch (d) {
    case 'beam': return undefined;
    case 'lambertian': return 120;
    case 'omni': case 'tube': return 360;
  }
}

export interface ColorCapability { minKelvin: number; maxKelvin: number; rgb: boolean }
const fixed = (k: number): ColorCapability => ({ minKelvin: k, maxKelvin: k, rgb: false });
const biColour = (lo: number, hi: number): ColorCapability => ({ minKelvin: lo, maxKelvin: hi, rgb: false });
const fullColour = (lo: number, hi: number): ColorCapability => ({ minKelvin: lo, maxKelvin: hi, rgb: true });
export const isAdjustable = (c: ColorCapability) => c.maxKelvin - c.minKelvin > 1;

export function drawFraction(t: LampTechnology, output: number): number {
  const o = Math.min(Math.max(output, 0), 1);
  switch (t) {
    case 'led': return o <= 0 ? 0 : 0.06 + 0.94 * o;
    case 'hmi': return o <= 0 ? 0 : 0.25 + 0.75 * o;
    case 'tungsten': return o <= 0 ? 0 : Math.pow(o, 1.6 / 3.4);
  }
}

export function dimmedKelvin(t: LampTechnology, k: number, output: number): number {
  return t === 'tungsten' ? k * Math.pow(Math.min(Math.max(output, 0.01), 1), 0.42 / 3.4) : k;
}

export interface FixtureProfile {
  id: string; name: string; category: FixtureCategory; kind: LightKind; technology: LampTechnology;
  ratedPower: number; color: ColorCapability; distribution: BeamDistribution; defaultBeam: number;
  beamRange?: Range; reference: PhotometricReference; emitterWidth: number; emitterHeight: number;
  hasBarnDoors: boolean; minOutput: number; defaultModifierID?: string;
}

export const powerLabel = (p: FixtureProfile) =>
  p.ratedPower >= 1000 ? `${+(p.ratedPower / 1000).toPrecision(6)}K` : `${Math.trunc(p.ratedPower)} W`;

export interface LightModifier {
  id: string; name: string; appliesTo: FixtureCategory[]; transmission: number;
  distribution?: BeamDistribution; beam?: number; beamRange?: Range; size?: number; allowsBarnDoors: boolean;
  /** Focuses like a fresnel lens: loses flux when spotted (see `focusFactor`). */
  focusesLikeFresnel?: boolean;
}

export interface LightFilter {
  id: string; name: string; transmission: number; mired: number; diffusion?: 'light' | 'medium' | 'heavy';
}

export const openBarnDoors: BarnDoors = { top: 90, bottom: 90, left: 90, right: 90 };
export const barnDoorsOpen = (b: BarnDoors) => Math.min(b.top, b.bottom, b.left, b.right) >= 89.5;
export function barnDoorTransmission(b: BarnDoors, h: number, v: number, softness = 6): number {
  const pass = (angle: number, limit: number) => limit < 89.5 ? Math.min(1, Math.max(0, (limit - angle) / softness + 0.5)) : 1;
  return pass(h, b.right) * pass(-h, b.left) * pass(v, b.top) * pass(-v, b.bottom);
}

const ref = (lux: number, d: number, beam: number | undefined, note: string): PhotometricReference =>
  ({ lux, distance: d, beamAngle: beam, provenance: 'estimated', note });

type P = Omit<FixtureProfile, 'hasBarnDoors' | 'minOutput'> & { hasBarnDoors?: boolean; minOutput?: number };
const prof = (p: P): FixtureProfile => ({ hasBarnDoors: false, minOutput: 0.01, ...p });

export const profiles: FixtureProfile[] = [
  prof({ id: 'cob-1200-d', name: '1200 W COB LED · daylight', category: 'cob', kind: 'fresnel', technology: 'led', ratedPower: 1200, color: fixed(5600), distribution: 'beam', defaultBeam: 55, reference: ref(20000, 3, 55, 'Standard 55° reflector'), emitterWidth: 0.25, emitterHeight: 0.25, defaultModifierID: 'reflector-55' }),
  prof({ id: 'cob-600-d', name: '600 W COB LED · daylight', category: 'cob', kind: 'fresnel', technology: 'led', ratedPower: 600, color: fixed(5600), distribution: 'beam', defaultBeam: 55, reference: ref(9000, 3, 55, 'Standard 55° reflector'), emitterWidth: 0.2, emitterHeight: 0.2, defaultModifierID: 'reflector-55' }),
  prof({ id: 'cob-600-bi', name: '600 W COB LED · bi-colour', category: 'cob', kind: 'fresnel', technology: 'led', ratedPower: 600, color: biColour(2700, 6500), distribution: 'beam', defaultBeam: 55, reference: ref(6500, 3, 55, 'Standard 55° reflector, 5600 K'), emitterWidth: 0.2, emitterHeight: 0.2, defaultModifierID: 'reflector-55' }),
  prof({ id: 'cob-300-d', name: '300 W COB LED · daylight', category: 'cob', kind: 'fresnel', technology: 'led', ratedPower: 300, color: fixed(5600), distribution: 'beam', defaultBeam: 55, reference: ref(3500, 3, 55, 'Standard 55° reflector'), emitterWidth: 0.18, emitterHeight: 0.18, defaultModifierID: 'reflector-55' }),
  prof({ id: 'cob-300-bi', name: '300 W COB LED · bi-colour', category: 'cob', kind: 'fresnel', technology: 'led', ratedPower: 300, color: biColour(2700, 6500), distribution: 'beam', defaultBeam: 55, reference: ref(2800, 3, 55, 'Standard 55° reflector, 5600 K'), emitterWidth: 0.18, emitterHeight: 0.18, defaultModifierID: 'reflector-55' }),
  prof({ id: 'cob-100-bi', name: '100 W COB LED · bi-colour', category: 'cob', kind: 'fresnel', technology: 'led', ratedPower: 100, color: biColour(2700, 6500), distribution: 'beam', defaultBeam: 55, reference: ref(900, 3, 55, 'Standard 55° reflector, 5600 K'), emitterWidth: 0.12, emitterHeight: 0.12, defaultModifierID: 'reflector-55' }),
  prof({ id: 'fresnel-led-200-bi', name: '200 W LED fresnel · bi-colour', category: 'fresnel', kind: 'fresnel', technology: 'led', ratedPower: 200, color: biColour(2700, 6500), distribution: 'beam', defaultBeam: 50, beamRange: [15, 50], reference: ref(1100, 3, 50, 'Full flood, 5600 K'), emitterWidth: 0.2, emitterHeight: 0.2, hasBarnDoors: true }),
  prof({ id: 'fresnel-led-600-d', name: '600 W LED fresnel · daylight', category: 'fresnel', kind: 'fresnel', technology: 'led', ratedPower: 600, color: fixed(5600), distribution: 'beam', defaultBeam: 60, beamRange: [15, 60], reference: ref(2500, 3, 60, 'Full flood'), emitterWidth: 0.3, emitterHeight: 0.3, hasBarnDoors: true }),
  prof({ id: 'panel-1x1-bi', name: '1×1 LED panel · bi-colour (≈100 W)', category: 'panel', kind: 'ledPanel', technology: 'led', ratedPower: 100, color: biColour(3200, 5600), distribution: 'lambertian', defaultBeam: 120, reference: ref(1850, 1, undefined, 'Bare panel, 5600 K'), emitterWidth: 0.3, emitterHeight: 0.3, hasBarnDoors: true }),
  prof({ id: 'panel-2x1-bi', name: '2×1 LED panel · bi-colour (≈200 W)', category: 'panel', kind: 'ledPanel', technology: 'led', ratedPower: 200, color: biColour(2700, 6500), distribution: 'lambertian', defaultBeam: 120, reference: ref(3600, 1, undefined, 'Bare panel, 5600 K'), emitterWidth: 0.6, emitterHeight: 0.3, hasBarnDoors: true }),
  prof({ id: 'panel-1x1-rgb', name: '1×1 LED panel · RGB (≈150 W)', category: 'panel', kind: 'ledPanel', technology: 'led', ratedPower: 150, color: fullColour(2500, 10000), distribution: 'lambertian', defaultBeam: 120, reference: ref(1900, 1, undefined, 'Bare panel, 5600 K white'), emitterWidth: 0.3, emitterHeight: 0.3, hasBarnDoors: true }),
  prof({ id: 'panel-2x1-rgb', name: '2×1 LED panel · RGB (≈350 W)', category: 'panel', kind: 'ledPanel', technology: 'led', ratedPower: 350, color: fullColour(2500, 10000), distribution: 'lambertian', defaultBeam: 120, reference: ref(4800, 1, undefined, 'Bare panel, 5600 K white'), emitterWidth: 0.6, emitterHeight: 0.3, hasBarnDoors: true }),
  prof({ id: 'mat-4x4-bi', name: '4×4 LED soft mat · bi-colour (≈400 W)', category: 'soft', kind: 'softbox', technology: 'led', ratedPower: 400, color: biColour(2700, 6500), distribution: 'lambertian', defaultBeam: 120, reference: ref(600, 3, undefined, 'With its diffusion, 5600 K'), emitterWidth: 1.2, emitterHeight: 1.2 }),
  prof({ id: 'mat-2x2-bi', name: '2×2 LED soft mat · bi-colour (≈150 W)', category: 'soft', kind: 'softbox', technology: 'led', ratedPower: 150, color: biColour(2700, 6500), distribution: 'lambertian', defaultBeam: 120, reference: ref(230, 3, undefined, 'With its diffusion, 5600 K'), emitterWidth: 0.6, emitterHeight: 0.6 }),
  prof({ id: 'tube-4ft-rgb', name: '4 ft LED tube · RGB (≈40 W)', category: 'tube', kind: 'tube', technology: 'led', ratedPower: 40, color: fullColour(2000, 10000), distribution: 'tube', defaultBeam: 360, reference: ref(300, 1, undefined, 'Broadside, 5600 K white'), emitterWidth: 1.2, emitterHeight: 0.04 }),
  prof({ id: 'tube-2ft-rgb', name: '2 ft LED tube · RGB (≈20 W)', category: 'tube', kind: 'tube', technology: 'led', ratedPower: 20, color: fullColour(2000, 10000), distribution: 'tube', defaultBeam: 360, reference: ref(130, 1, undefined, 'Broadside, 5600 K white'), emitterWidth: 0.6, emitterHeight: 0.04 }),
  prof({ id: 'hmi-1800-par', name: '1.8K HMI PAR', category: 'hmi', kind: 'hmi', technology: 'hmi', ratedPower: 1800, color: fixed(5600), distribution: 'beam', defaultBeam: 30, reference: ref(40000, 3, 30, 'Medium flood lens'), emitterWidth: 0.4, emitterHeight: 0.4, hasBarnDoors: true, minOutput: 0.5 }),
  prof({ id: 'hmi-4000-par', name: '4K HMI PAR', category: 'hmi', kind: 'hmi', technology: 'hmi', ratedPower: 4000, color: fixed(5600), distribution: 'beam', defaultBeam: 30, reference: ref(75000, 3, 30, 'Medium flood lens'), emitterWidth: 0.55, emitterHeight: 0.55, hasBarnDoors: true, minOutput: 0.5 }),
  prof({ id: 'tungsten-650', name: '650 W tungsten fresnel', category: 'tungsten', kind: 'fresnel', technology: 'tungsten', ratedPower: 650, color: fixed(3200), distribution: 'beam', defaultBeam: 55, beamRange: [15, 55], reference: ref(1200, 3, 55, 'Full flood'), emitterWidth: 0.15, emitterHeight: 0.15, hasBarnDoors: true }),
  prof({ id: 'tungsten-1k', name: '1K tungsten fresnel', category: 'tungsten', kind: 'fresnel', technology: 'tungsten', ratedPower: 1000, color: fixed(3200), distribution: 'beam', defaultBeam: 55, beamRange: [15, 55], reference: ref(2250, 3, 55, 'Full flood'), emitterWidth: 0.2, emitterHeight: 0.2, hasBarnDoors: true }),
  prof({ id: 'tungsten-2k', name: '2K tungsten fresnel', category: 'tungsten', kind: 'fresnel', technology: 'tungsten', ratedPower: 2000, color: fixed(3200), distribution: 'beam', defaultBeam: 55, beamRange: [15, 55], reference: ref(3800, 3, 55, 'Full flood'), emitterWidth: 0.25, emitterHeight: 0.25, hasBarnDoors: true }),
  prof({ id: 'lantern-300-bi', name: 'LED lantern / space light · bi-colour (≈300 W)', category: 'spaceLight', kind: 'spaceLight', technology: 'led', ratedPower: 300, color: biColour(2700, 6500), distribution: 'omni', defaultBeam: 360, reference: ref(110, 3, undefined, '5600 K'), emitterWidth: 0.65, emitterHeight: 0.65 }),
  prof({ id: 'bulb-led-60', name: 'Household LED bulb (60 W equivalent)', category: 'practical', kind: 'practical', technology: 'led', ratedPower: 9, color: fixed(2700), distribution: 'omni', defaultBeam: 360, reference: ref(64, 1, undefined, 'About 800 lm, bare'), emitterWidth: 0.06, emitterHeight: 0.1 }),
  prof({ id: 'bulb-tungsten-100', name: 'Tungsten bulb 100 W', category: 'practical', kind: 'practical', technology: 'tungsten', ratedPower: 100, color: fixed(2850), distribution: 'omni', defaultBeam: 360, reference: ref(110, 1, undefined, 'About 1,400 lm, bare'), emitterWidth: 0.06, emitterHeight: 0.1 }),
];

type M = Omit<LightModifier, 'allowsBarnDoors'> & { allowsBarnDoors?: boolean };
const mod = (m: M): LightModifier => ({ allowsBarnDoors: false, ...m });
export const modifiers: LightModifier[] = [
  mod({ id: 'reflector-55', name: 'Standard reflector (55°)', appliesTo: ['cob'], transmission: 1, distribution: 'beam', beam: 55, allowsBarnDoors: true }),
  mod({ id: 'reflector-30', name: 'Narrow reflector (30°)', appliesTo: ['cob'], transmission: 0.92, distribution: 'beam', beam: 30, allowsBarnDoors: true }),
  mod({ id: 'reflector-15', name: 'Long-throw reflector (15°)', appliesTo: ['cob'], transmission: 0.85, distribution: 'beam', beam: 15 }),
  mod({ id: 'cob-bare', name: 'Bare (no reflector)', appliesTo: ['cob'], transmission: 1.3, distribution: 'lambertian' }),
  mod({ id: 'fresnel-attachment', name: 'Fresnel attachment (12–45°)', appliesTo: ['cob'], transmission: 0.55, distribution: 'beam', beam: 45, beamRange: [12, 45], allowsBarnDoors: true, focusesLikeFresnel: true }),
  mod({ id: 'projector', name: 'Spot projector (19–36°)', appliesTo: ['cob'], transmission: 0.25, distribution: 'beam', beam: 26, beamRange: [19, 36] }),
  mod({ id: 'softbox-90', name: 'Softbox 90 cm', appliesTo: ['cob', 'fresnel', 'hmi', 'tungsten'], transmission: 0.5, distribution: 'lambertian', size: 0.9 }),
  mod({ id: 'softbox-90-grid', name: 'Softbox 90 cm + 40° grid', appliesTo: ['cob', 'fresnel', 'hmi', 'tungsten'], transmission: 0.33, distribution: 'beam', beam: 40, size: 0.9 }),
  mod({ id: 'softbox-150', name: 'Large softbox 150 cm', appliesTo: ['cob', 'hmi'], transmission: 0.45, distribution: 'lambertian', size: 1.5 }),
  mod({ id: 'lantern-65', name: 'Lantern 65 cm', appliesTo: ['cob'], transmission: 0.55, distribution: 'omni', size: 0.65 }),
  mod({ id: 'panel-grid-40', name: 'Egg-crate grid (40°)', appliesTo: ['panel', 'soft'], transmission: 0.65, distribution: 'beam', beam: 40, allowsBarnDoors: true }),
  mod({ id: 'panel-softbox', name: 'Panel softbox', appliesTo: ['panel'], transmission: 0.6, distribution: 'lambertian', size: 0.6 }),
  mod({ id: 'par-spot', name: 'Spot lens (12°)', appliesTo: ['hmi'], transmission: 0.8, distribution: 'beam', beam: 12, allowsBarnDoors: true }),
  mod({ id: 'par-wide', name: 'Wide flood lens (50°)', appliesTo: ['hmi'], transmission: 0.95, distribution: 'beam', beam: 50, allowsBarnDoors: true }),
  mod({ id: 'par-superwide', name: 'Super-wide lens (70°)', appliesTo: ['hmi'], transmission: 0.9, distribution: 'beam', beam: 70, allowsBarnDoors: true }),
  mod({ id: 'shade', name: 'Lampshade (fabric)', appliesTo: ['practical'], transmission: 0.55, distribution: 'omni', size: 0.35 }),
];

export const filters: LightFilter[] = [
  { id: 'cto-full', name: 'Full CTO', transmission: 0.55, mired: 159 },
  { id: 'cto-half', name: '½ CTO', transmission: 0.70, mired: 81 },
  { id: 'cto-quarter', name: '¼ CTO', transmission: 0.81, mired: 42 },
  { id: 'ctb-full', name: 'Full CTB', transmission: 0.36, mired: -131 },
  { id: 'ctb-half', name: '½ CTB', transmission: 0.52, mired: -68 },
  { id: 'ctb-quarter', name: '¼ CTB', transmission: 0.75, mired: -30 },
  { id: 'plus-green-quarter', name: '¼ Plus Green', transmission: 0.87, mired: 0 },
  { id: 'minus-green-quarter', name: '¼ Minus Green', transmission: 0.82, mired: 0 },
  { id: 'nd-3', name: 'ND 0.3 (1 stop)', transmission: 0.5, mired: 0 },
  { id: 'nd-6', name: 'ND 0.6 (2 stops)', transmission: 0.25, mired: 0 },
  { id: 'nd-9', name: 'ND 0.9 (3 stops)', transmission: 0.125, mired: 0 },
  { id: 'diff-light', name: 'Light diffusion (opal / ¼ frost)', transmission: 0.8, mired: 0, diffusion: 'light' },
  { id: 'diff-medium', name: 'Medium diffusion (½ white)', transmission: 0.6, mired: 0, diffusion: 'medium' },
  { id: 'diff-heavy', name: 'Heavy diffusion (full white)', transmission: 0.36, mired: 0, diffusion: 'heavy' },
];

export const profileByID = (id?: string) => (id ? profiles.find(p => p.id === id) : undefined);
export const modifierByID = (id?: string) => (id ? modifiers.find(m => m.id === id) : undefined);
export const filterByID = (id: string) => filters.find(f => f.id === id);
export const modifiersFor = (p: FixtureProfile) => modifiers.filter(m => m.appliesTo.includes(p.category));

export function defaultProfile(kind: LightKind): FixtureProfile {
  const ids: Partial<Record<LightKind, string>> = {
    fresnel: 'fresnel-led-200-bi', hmi: 'hmi-1800-par', ledPanel: 'panel-1x1-bi', tube: 'tube-4ft-rgb',
    softbox: 'mat-4x4-bi', spaceLight: 'lantern-300-bi', practical: 'bulb-led-60',
  };
  return profileByID(ids[kind] ?? 'cob-300-bi') ?? profiles[0];
}

export interface ResolvedPhotometrics {
  profile: FixtureProfile; modifier?: LightModifier; distribution: BeamDistribution; beamAngle: number;
  beamIsAdjustable: boolean; beamRange?: Range; peakIntensity: number; flux: number;
  emitterRadius: number; tubeLength: number; kelvin: number; color: RGB; drawWatts: number;
  barnDoorsAvailable: boolean; provenance: Provenance; notes: string[];
}

export function distanceFactor(d0: number, distribution: BeamDistribution, emitterRadius: number, tubeLength: number): number {
  const d = Math.max(d0, 0.05);
  switch (distribution) {
    case 'omni': return 1 / (d * d);
    case 'tube': {
      if (!(tubeLength > 0.01)) return 1 / (d * d);
      const a = Math.atan(tubeLength / (2 * d));
      return (a + Math.sin(a) * Math.cos(a)) / (tubeLength * d);
    }
    default: return 1 / (d * d + emitterRadius * emitterRadius);
  }
}

export const illuminanceOnAxis = (pm: ResolvedPhotometrics, distance: number) =>
  pm.peakIntensity * distanceFactor(distance, pm.distribution, pm.emitterRadius, pm.tubeLength);

export function distanceForLux(pm: ResolvedPhotometrics, lux: number): number | undefined {
  if (!(lux > 0) || !(pm.peakIntensity > 0)) return undefined;
  let lo = 0.3, hi = 200;
  if (illuminanceOnAxis(pm, lo) < lux) return undefined;
  if (illuminanceOnAxis(pm, hi) > lux) return hi;
  for (let i = 0; i < 60; i++) {
    const mid = (lo + hi) / 2;
    if (illuminanceOnAxis(pm, mid) > lux) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

/** Exponent of the fresnel focus loss: beam flux ∝ (beam ÷ full flood)^k (Photometry.fresnelFocusExponent). */
export const FRESNEL_FOCUS_EXPONENT = 0.85;
/** Fraction of the full-flood beam flux a fresnel lens passes at `beam` (1 at full flood). */
export function focusFactor(beam: number, range: Range): number {
  const b = Math.min(Math.max(beam, range[0]), range[1]);
  return Math.pow(b / range[1], FRESNEL_FOCUS_EXPONENT);
}

export function shiftedKelvin(kelvin: number, mired: number): number {
  const m = 1_000_000 / Math.max(kelvin, 1000) + mired;
  return 1_000_000 / Math.max(m, 50);
}

export function hueRGB(hue: number, saturation: number): RGB {
  const h = (((hue % 360) + 360) % 360) / 60;
  const x = 1 - Math.abs((h % 2) - 1);
  let r: number, g: number, b: number;
  switch (Math.trunc(h)) {
    case 0: [r, g, b] = [1, x, 0]; break;
    case 1: [r, g, b] = [x, 1, 0]; break;
    case 2: [r, g, b] = [0, 1, x]; break;
    case 3: [r, g, b] = [0, x, 1]; break;
    case 4: [r, g, b] = [x, 0, 1]; break;
    default: [r, g, b] = [1, 0, x];
  }
  const s = Math.min(Math.max(saturation, 0), 1);
  return { r: 1 - s + s * r, g: 1 - s + s * g, b: 1 - s + s * b };
}

export function rgbOutputFactor(hue: number, saturation: number): number {
  const c = hueRGB(hue, saturation);
  const y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
  return Math.max(0.03, Math.min(1, y));
}

// MARK: LightFixture extensions

export const fixtureProfile = (l: LightFixture) => profileByID(l.profileID) ?? defaultProfile(l.kind);

export function fixtureModifier(l: LightFixture): LightModifier | undefined {
  const p = fixtureProfile(l);
  if (l.modifierID) {
    if (l.modifierID === 'none') return p.defaultModifierID === undefined ? undefined : modifierByID('cob-bare');
    const m = modifierByID(l.modifierID);
    if (m && m.appliesTo.includes(p.category)) return m;
  }
  return modifierByID(p.defaultModifierID);
}

export const usesRGB = (l: LightFixture) => fixtureProfile(l).color.rgb && l.colorMode === 'rgb';

const fmtG = (v: number) => String(+v.toPrecision(6));

export function photometrics(l: LightFixture): ResolvedPhotometrics {
  const p = fixtureProfile(l);
  const reference = l.photometricOverride ?? p.reference;
  const notes: string[] = [];

  // 1. Reference reading → flux in the reference configuration.
  const refModifier = modifierByID(p.defaultModifierID);
  const refDistribution = refModifier?.distribution ?? p.distribution;
  const refBeam = reference.beamAngle ?? refModifier?.beam ?? p.defaultBeam;
  const refRadius = Math.sqrt(p.emitterWidth * p.emitterHeight / Math.PI);
  const refFactor = distanceFactor(reference.distance, refDistribution, refRadius, p.emitterWidth);
  const refPeak = reference.lux / Math.max(refFactor, 1e-9);
  let flux = refPeak * solidAngleFactor(refDistribution, refBeam);
  // A fresnel's own reading taken spotted in → the flux at full flood.
  if (!refModifier && p.beamRange && refDistribution === 'beam') flux /= focusFactor(refBeam, p.beamRange);

  // 2. Modifier.
  const modifier = fixtureModifier(l);
  let distribution: BeamDistribution = modifier?.distribution ?? p.distribution;
  let radius = refRadius;
  if (modifier) {
    flux *= modifier.transmission / (refModifier?.transmission ?? 1);
    if (modifier.size !== undefined) radius = Math.sqrt(modifier.size * modifier.size / Math.PI);
  }
  const range = modifier?.beamRange ?? (modifier?.beam === undefined ? p.beamRange : undefined);
  let beam = range ? Math.min(Math.max(l.beamAngle, range[0]), range[1]) : (modifier?.beam ?? p.defaultBeam);
  if (distribution !== 'beam') beam = nominalBeam(distribution) ?? beam;
  // Spotting a fresnel lens loses flux.
  if (distribution === 'beam' && range && (modifier?.focusesLikeFresnel || (!modifier && p.beamRange))) flux *= focusFactor(beam, range);

  // 3. Filters.
  let kelvin = isAdjustable(p.color) ? Math.min(Math.max(l.colorTemperature, p.color.minKelvin), p.color.maxKelvin) : p.color.minKelvin;
  for (const f of (l.filterIDs ?? []).map(filterByID)) {
    if (!f) continue;
    flux *= f.transmission;
    kelvin = shiftedKelvin(kelvin, f.mired);
    if (f.diffusion === 'light') { if (distribution === 'beam') beam = Math.min(beam + 15, 160); }
    else if (f.diffusion === 'medium') { if (distribution === 'beam') beam = Math.min(Math.max(beam * 1.8, 90), 160); }
    else if (f.diffusion === 'heavy') { if (distribution === 'beam') { distribution = 'lambertian'; beam = 120; } }
  }

  // 4. Colour mode and output level.
  const rgb = usesRGB(l);
  if (rgb) {
    flux *= rgbOutputFactor(l.hue ?? 0, l.saturation ?? 1);
    notes.push("Colour output scaled by the colour's brightness relative to white (estimate).");
  }
  const output = l.isOn ? Math.min(Math.max(l.dimmer, p.minOutput), 1) : 0;
  flux *= output;
  kelvin = dimmedKelvin(p.technology, kelvin, output);
  if (p.technology === 'tungsten' && output < 0.99 && output > 0) notes.push('Tungsten warms as it dims.');

  const peak = flux / solidAngleFactor(distribution, beam);
  const color = rgb ? hueRGB(l.hue ?? 0, l.saturation ?? 1) : kelvinRGB(kelvin);
  notes.push(reference.provenance === 'manual'
    ? `Output from your reference reading: ${Math.trunc(reference.lux)} lx at ${fmtG(reference.distance)} m.`
    : `Output estimated for a typical ${p.name} (${reference.note.toLowerCase()}). Enter the maker's data in Details for better figures.`);

  return {
    profile: p, modifier, distribution, beamAngle: beam,
    beamIsAdjustable: range !== undefined && distribution === 'beam', beamRange: range,
    peakIntensity: peak, flux, emitterRadius: radius, tubeLength: p.emitterWidth, kelvin, color,
    drawWatts: p.ratedPower * drawFraction(p.technology, output),
    barnDoorsAvailable: p.hasBarnDoors ? (modifier?.allowsBarnDoors ?? true) : (modifier?.allowsBarnDoors ?? false),
    provenance: reference.provenance === 'manual' ? 'manual' : 'estimated',
    notes,
  };
}

/// Mirrors `LightFixture.apply(profile:)`.
export function applyProfile(l: LightFixture, p: FixtureProfile): LightFixture {
  const kindWidth = KIND_INFO[p.kind].width;
  const n: LightFixture = { ...l, profileID: p.id, kind: p.kind };
  delete n.modifierID;
  n.width = Math.max(p.emitterWidth, kindWidth * 0.5);
  n.beamAngle = p.beamRange ? Math.min(Math.max(l.beamAngle, p.beamRange[0]), p.beamRange[1]) : p.defaultBeam;
  n.colorTemperature = isAdjustable(p.color) ? Math.min(Math.max(l.colorTemperature, p.color.minKelvin), p.color.maxKelvin) : p.color.minKelvin;
  if (!p.color.rgb) delete n.colorMode;
  n.power = powerLabel(p);
  delete n.photometricOverride;
  if (!p.hasBarnDoors) delete n.barnDoors;
  return n;
}

export const KIND_INFO: Record<LightKind, { label: string; emits: boolean; beam: number; width: number; height: number }> = {
  fresnel: { label: 'Fresnel', emits: true, beam: 35, width: 0.3, height: 2.2 },
  hmi: { label: 'HMI', emits: true, beam: 30, width: 0.3, height: 2.2 },
  ledPanel: { label: 'LED panel', emits: true, beam: 90, width: 0.6, height: 2.2 },
  tube: { label: 'Tube', emits: true, beam: 120, width: 1.2, height: 2.2 },
  softbox: { label: 'Softbox', emits: true, beam: 100, width: 0.9, height: 2.2 },
  spaceLight: { label: 'Space light', emits: true, beam: 160, width: 0.3, height: 2.6 },
  practical: { label: 'Practical', emits: true, beam: 180, width: 0.3, height: 1.0 },
  bounce: { label: 'Bounce', emits: false, beam: 0, width: 1.2, height: 1.5 },
  negative: { label: 'Negative fill', emits: false, beam: 0, width: 1.2, height: 1.5 },
  flag: { label: 'Flag', emits: false, beam: 0, width: 0.6, height: 1.5 },
  diffusion: { label: 'Diffusion frame', emits: false, beam: 0, width: 1.2, height: 1.5 },
};
