import type { ExposureSettings } from '../model/types';
import { useSyncExternalStore } from 'react';
import { meterStop, stopsDelta, stopLabel, stopsForLux } from '../model/exposure';

export function lux(v: number): string {
  if (v >= 10_000) return `${(v / 1000).toFixed(0)}k lx`;
  if (v >= 1000) return `${(v / 1000).toFixed(1)}k lx`;
  if (v >= 10) return `${Math.round(v)} lx`;
  return `${v.toFixed(1)} lx`;
}
export const watts = (w: number) => (w >= 1000 ? `${(w / 1000).toFixed(2)} kW` : `${Math.round(w)} W`);

// Lengths: metres, or feet and inches for crews who work in them. Same choice as Settings → Units on
// the iPhone (UnitsFormatter.useImperial); remembered per browser.
export type Units = 'metric' | 'imperial';
const UNITS_KEY = 'framescan.units';
export const M_PER_FT = 0.3048;
let units: Units = (() => { try { return localStorage.getItem(UNITS_KEY) === 'imperial' ? 'imperial' : 'metric'; } catch { return 'metric'; } })();
const unitListeners = new Set<() => void>();
export const lengthUnits = () => units;
export function setLengthUnits(next: Units) {
  units = next;
  try { localStorage.setItem(UNITS_KEY, next); } catch { /* private mode */ }
  unitListeners.forEach(l => l());
}
/// Subscribes a component to the units choice.
export const useLengthUnits = () => useSyncExternalStore(l => { unitListeners.add(l); return () => { unitListeners.delete(l); }; }, lengthUnits);
/** 3.05 → "10′ 0″" (nearest inch). */
export function feetInches(m: number): string {
  const total = Math.round(Math.abs(m) / 0.0254);
  return `${m < 0 ? '−' : ''}${Math.floor(total / 12)}′ ${total % 12}″`;
}
export const metres = (m: number, u: Units = units) => (u === 'imperial' ? feetInches(m) : `${m.toFixed(2)} m`);
/** Room sizes on a list: one decimal in metres, whole feet and inches otherwise. */
export const roomSize = (a: number, b: number, u: Units = units) => (u === 'imperial' ? `${feetInches(a)} × ${feetInches(b)}` : `${a.toFixed(1)} × ${b.toFixed(1)} m`);
export const area = (m2: number, u: Units = units) => (u === 'imperial' ? `${Math.round(m2 * 10.7639)} ft²` : `${m2.toFixed(1)} m²`);
/** What a size field shows and steps by: metres, or decimal feet. */
export const lengthUnitLabel = (u: Units = units) => (u === 'imperial' ? 'ft' : 'm');
export const toInput = (m: number, u: Units = units) => (u === 'imperial' ? Math.round((m / M_PER_FT) * 10) / 10 : Math.round(m * 100) / 100);
/** Typed text to metres. Feet also take 12'6" or 12 6 (feet then inches). */
export function fromInput(text: string, u: Units = units): number | undefined {
  const t = text.trim().replace(',', '.');
  if (u === 'imperial') {
    const fi = t.match(/^(-?\d+(?:\.\d+)?)\s*(?:'|′|ft)?\s+(\d+(?:\.\d+)?)\s*(?:"|″|in)?$/) ?? t.match(/^(-?\d+(?:\.\d+)?)\s*(?:'|′)\s*(\d+(?:\.\d+)?)\s*(?:"|″)?$/);
    if (fi) return (Number(fi[1]) + Number(fi[2]) / 12) * M_PER_FT;
    const n = parseFloat(t);
    return Number.isFinite(n) ? n * M_PER_FT : undefined;
  }
  const n = parseFloat(t);
  return Number.isFinite(n) ? n : undefined;
}
export const deg = (d: number) => `${Math.round(((d % 360) + 360) % 360)}°`;
export const signedDeg = (d: number) => `${d >= 0 ? '+' : '−'}${Math.abs(Math.round(d))}°`;
export const pct = (v: number) => `${Math.round(v * 100)} %`;

/// Readings always lead with the T-stop an incident meter would show (crews think in stops). Lux or
/// foot-candles can follow it. Same choice and names as ReadingExtra on the iPhone.
export type ReadingExtra = 'off' | 'lux' | 'footCandles';
export const READING_EXTRAS: [ReadingExtra, string][] = [['off', 'Off'], ['lux', 'Lux'], ['footCandles', 'Foot-candles']];
export const LUX_PER_FOOT_CANDLE = 10.764;
const EXTRA_KEY = 'framescan.readings.extra';
/** The older single-unit setting ('tStop' | 'stops' | 'lux' | 'footCandles'). */
const LEGACY_KEY = 'framescan.readings';
/** Someone who chose lux or foot-candles before readings always led with the stop keeps it. */
export const migratedExtra = (legacy: string | null): ReadingExtra | undefined => (legacy === 'lux' || legacy === 'footCandles' ? legacy : undefined);
let extra: ReadingExtra = (() => {
  try {
    const v = localStorage.getItem(EXTRA_KEY);
    if (READING_EXTRAS.some(u => u[0] === v)) return v as ReadingExtra;
    return migratedExtra(localStorage.getItem(LEGACY_KEY)) ?? 'off';
  } catch { return 'off'; }
})();
const listeners = new Set<() => void>();
export const readingExtra = () => extra;
export function setReadingExtra(next: ReadingExtra) {
  extra = next;
  try { localStorage.setItem(EXTRA_KEY, next); } catch { /* private mode */ }
  listeners.forEach(l => l());
}
/// Subscribes a component to the readings choice, so everything under it redraws when it changes.
export const useReadingExtra = () => useSyncExternalStore(l => { listeners.add(l); return () => { listeners.delete(l); }; }, readingExtra);

export function footCandles(luxValue: number): string {
  const fc = luxValue / LUX_PER_FOOT_CANDLE;
  if (fc >= 1000) return `${(fc / 1000).toFixed(1)}k fc`;
  if (fc >= 10) return `${Math.round(fc)} fc`;
  return `${fc.toFixed(1)} fc`;
}
/// The light level in the chosen unit, or undefined when it is switched off.
export function extraText(v: number, x: ReadingExtra = extra): string | undefined {
  return x === 'lux' ? lux(v) : x === 'footCandles' ? footCandles(v) : undefined;
}
/// One reading: the stop, then lux or foot-candles if switched on: "T4 +⅓" or "T4 +⅓ · 420 lx".
export function reading(v: number, e: ExposureSettings, x: ReadingExtra = extra): string {
  const more = extraText(v, x);
  return more ? `${meterStop(e, v)} · ${more}` : meterStop(e, v);
}
/// Label for the plan and the 3D tags. Every reading is an estimate (D-006).
export const readingShort = (v: number, e: ExposureSettings, x: ReadingExtra = extra) => `≈ ${reading(v, e, x)}`;
/// Full line for a panel: the reading, then how far off the set stop it is.
export function readingText(v: number, e: ExposureSettings, x: ReadingExtra = extra): string {
  return `≈ ${reading(v, e, x)} · ${stopsDelta(stopsForLux(e, v))} at ${stopLabel(e.tStop)}`;
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
