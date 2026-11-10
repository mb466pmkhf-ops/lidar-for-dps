import type { ExposureSettings } from '../model/types';
import { useSyncExternalStore } from 'react';
import { stopsDelta, stopLabel, stopsForLux, tStopForLux } from '../model/exposure';

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

/// How a light reading is written out (same choice and names as ReadingUnit on the iPhone).
/// Crews think in stops, so the default is the T-stop an incident meter would show.
export type ReadingUnit = 'tStop' | 'stops' | 'lux' | 'footCandles';
export const READING_UNITS: [ReadingUnit, string][] = [['tStop', 'T-stop'], ['stops', 'Stops over / under'], ['lux', 'Lux'], ['footCandles', 'Foot-candles']];
export const LUX_PER_FOOT_CANDLE = 10.764;
const UNIT_KEY = 'framescan.readings';
let unit: ReadingUnit = (() => {
  try { const v = localStorage.getItem(UNIT_KEY); return READING_UNITS.some(u => u[0] === v) ? v as ReadingUnit : 'tStop'; } catch { return 'tStop'; }
})();
const listeners = new Set<() => void>();
export const readingUnit = () => unit;
export function setReadingUnit(next: ReadingUnit) {
  unit = next;
  try { localStorage.setItem(UNIT_KEY, next); } catch { /* private mode */ }
  listeners.forEach(l => l());
}
/// Subscribes a component to the readings unit, so everything under it redraws when it changes.
export const useReadingUnit = () => useSyncExternalStore(l => { listeners.add(l); return () => { listeners.delete(l); }; }, readingUnit);

export function footCandles(luxValue: number): string {
  const fc = luxValue / LUX_PER_FOOT_CANDLE;
  if (fc >= 1000) return `${(fc / 1000).toFixed(1)}k fc`;
  if (fc >= 10) return `${Math.round(fc)} fc`;
  return `${fc.toFixed(1)} fc`;
}
/// One reading in the chosen unit: "T4 +⅓", "+⅓", "420 lx" or "39 fc".
export function reading(v: number, e: ExposureSettings, u: ReadingUnit = unit): string {
  switch (u) {
    case 'tStop': return stopLabel(tStopForLux(e, v));
    case 'stops': return stopsDelta(stopsForLux(e, v));
    case 'lux': return lux(v);
    case 'footCandles': return footCandles(v);
  }
}
/// Short label for the plan: lux and foot-candles also say how far off the set stop they are.
export function readingShort(v: number, e: ExposureSettings, u: ReadingUnit = unit): string {
  return u === 'lux' || u === 'footCandles' ? `≈ ${reading(v, e, u)} · ${stopsDelta(stopsForLux(e, v))}` : `≈ ${reading(v, e, u)}`;
}
/// Full line for a panel. Every reading is an estimate (D-006), whatever unit it is shown in.
export function readingText(v: number, e: ExposureSettings, u: ReadingUnit = unit): string {
  if (u === 'tStop') return `≈ ${reading(v, e, u)}`;
  if (u === 'stops') return `≈ ${reading(v, e, u)} at ${stopLabel(e.tStop)}`;
  return `≈ ${reading(v, e, u)} · ${stopsDelta(stopsForLux(e, v))} at ${stopLabel(e.tStop)}`;
}

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
