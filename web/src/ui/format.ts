import type { ExposureSettings } from '../model/types';
import { stopsDelta, stopLabel, stopsForLux } from '../model/exposure';

export function lux(v: number): string {
  if (v >= 10_000) return `${(v / 1000).toFixed(0)}k lx`;
  if (v >= 1000) return `${(v / 1000).toFixed(1)}k lx`;
  if (v >= 10) return `${Math.round(v)} lx`;
  return `${v.toFixed(1)} lx`;
}
export const watts = (w: number) => (w >= 1000 ? `${(w / 1000).toFixed(2)} kW` : `${Math.round(w)} W`);
export const metres = (m: number) => `${m.toFixed(2)} m`;
export const deg = (d: number) => `${Math.round(((d % 360) + 360) % 360)}°`;
export const signedDeg = (d: number) => `${d >= 0 ? '+' : '−'}${Math.abs(Math.round(d))}°`;
export const pct = (v: number) => `${Math.round(v * 100)} %`;
/// "≈ 420 lx · +⅓ at T5.6": every reading is an estimate (D-006).
export const readingText = (v: number, e: ExposureSettings) => `≈ ${lux(v)} · ${stopsDelta(stopsForLux(e, v))} at ${stopLabel(e.tStop)}`;

/// False-colour for an exposure, from the iOS plan (PlanLuxMap.color): blue under, green on key, red over.
export function stopColor(stops: number): string | undefined {
  if (stops < -4) return undefined;
  if (stops < -3) return 'rgb(31,41,107)';
  if (stops < -2) return 'rgb(46,84,204)';
  if (stops < -1) return 'rgb(77,158,199)';
  if (stops < -1 / 3) return 'rgb(140,140,140)';
  if (stops <= 1 / 3) return 'rgb(64,191,94)';
  if (stops <= 1) return 'rgb(230,140,168)';
  if (stops <= 2) return 'rgb(224,102,61)';
  return 'rgb(255,41,41)';
}
export const stopLegend: [string, number][] = [['−3', -3.5], ['−2', -2.5], ['−1', -1.5], ['−⅓', -0.6], ['KEY', 0], ['+1', 0.7], ['+2', 1.5], ['2+', 2.5]];
