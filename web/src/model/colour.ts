// How each light's colour reads at the camera's white balance. Port of FrameScout/Core/Models/ColourBalance.swift.
// The figures come from the colour temperature set on each unit, its gels and dimming (photometrics.ts) and the
// white balance typed in for the camera. They describe the settings, not a measured colour, so they are estimates.
import type { LightFixture } from './types';
import { KIND_INFO, photometrics, usesRGB } from './photometrics';

/** White balance choices offered in the pickers on both platforms (Kelvin). */
export const WB_PRESETS = [2700, 3200, 4300, 5000, 5600, 6500];
/** Mireds of a full CTO and a full CTB (Rosco 3407 / 3202), the yardsticks a gaffer speaks in. */
export const FULL_CTO_MIRED = 159;
export const FULL_CTB_MIRED = 131;
/** Within this many mireds a source reads as white at the camera's balance (about ⅛ CTO). */
export const MATCH_MIRED = 20;

export type ColourTone = 'warm' | 'cool' | 'match';
export interface ColourShift { mired: number; tone: ColourTone; label: string }

const mired = (kelvin: number) => 1_000_000 / Math.max(kelvin, 1000);

/** "½", "¼"… for a fraction of a full gel, to the nearest eighth; whole numbers past one. */
function gelAmount(f: number): string {
  if (f > 1.125) return `${Math.round(f * 2) / 2}× full`.replace('.5×', '½×');
  const eighths = Math.min(8, Math.max(1, Math.round(f * 8)));
  return ({ 1: '⅛', 2: '¼', 3: '⅜', 4: '½', 5: '⅝', 6: '¾', 7: '⅞', 8: 'full' } as Record<number, string>)[eighths];
}

/** How a source of `kelvin` reads on a camera balanced to `whiteBalance`: positive mireds read warm. */
export function colourShift(kelvin: number, whiteBalance: number): ColourShift {
  const m = mired(kelvin) - mired(whiteBalance);
  if (Math.abs(m) < MATCH_MIRED) return { mired: m, tone: 'match', label: 'reads white' };
  return m > 0
    ? { mired: m, tone: 'warm', label: `reads warm, about ${gelAmount(m / FULL_CTO_MIRED)} CTO` }
    : { mired: m, tone: 'cool', label: `reads cool, about ${gelAmount(-m / FULL_CTB_MIRED)} CTB` };
}

export interface ColourRow { id: string; name: string; kelvin?: number; rgb: boolean; shift?: ColourShift }
export interface ColourSummary { whiteBalance: number; rows: ColourRow[]; warm: number; cool: number; match: number; rgb: number; line: string }

/** Every light that is on and gives light, with how it reads at `whiteBalance`. */
export function colourSummary(lights: LightFixture[], whiteBalance: number): ColourSummary {
  const rows: ColourRow[] = lights.filter(l => l.isOn && KIND_INFO[l.kind].emits).map(l => {
    if (usesRGB(l)) return { id: l.id, name: l.name, rgb: true };
    const kelvin = photometrics(l).kelvin;
    return { id: l.id, name: l.name, kelvin, rgb: false, shift: colourShift(kelvin, whiteBalance) };
  });
  const count = (t: ColourTone) => rows.filter(r => r.shift?.tone === t).length;
  const s = { warm: count('warm'), cool: count('cool'), match: count('match'), rgb: rows.filter(r => r.rgb).length };
  const parts = [s.match ? `${s.match} white` : '', s.warm ? `${s.warm} warm` : '', s.cool ? `${s.cool} cool` : '', s.rgb ? `${s.rgb} RGB colour` : ''].filter(Boolean);
  const line = rows.length ? `At ${Math.round(whiteBalance)} K: ${parts.join(', ')}` : 'No lights on';
  return { whiteBalance, rows, ...s, line };
}
