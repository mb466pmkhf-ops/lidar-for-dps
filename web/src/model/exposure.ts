// Port of FrameScout/Core/Models/Exposure.swift: incident-meter equation N²/t = E·S/C, C = 250.
// The stop is a T-stop (an exposure setting), never a measure of scene brightness.
import type { ExposureSettings } from './types';

export const METER_CALIBRATION = 250;
export const defaultExposure = (): ExposureSettings => ({ iso: 800, frameRate: 24, shutterAngle: 180, tStop: 2.8, lensTransmission: 0.85, ndStops: 0 });
export const withDefaults = (e?: Partial<ExposureSettings>): ExposureSettings => ({ ...defaultExposure(), ...(e ?? {}) });

export const exposureTime = (e: ExposureSettings) =>
  e.shutterSeconds !== undefined ? Math.max(e.shutterSeconds, 1e-5) : Math.max(e.shutterAngle, 1) / 360 / Math.max(e.frameRate, 1);
export const fStop = (e: ExposureSettings) => e.tStop * Math.sqrt(e.lensTransmission);
export const luxForTStop = (e: ExposureSettings, n: number) => METER_CALIBRATION * n * n * Math.pow(2, e.ndStops) / (e.iso * exposureTime(e));
export const keyLux = (e: ExposureSettings) => luxForTStop(e, e.tStop);
export const tStopForLux = (e: ExposureSettings, lux: number) => Math.sqrt(Math.max(lux, 1e-6) * e.iso * exposureTime(e) / (METER_CALIBRATION * Math.pow(2, e.ndStops)));
export const stopsForLux = (e: ExposureSettings, lux: number) => Math.log2(Math.max(lux, 1e-6) / keyLux(e));

export const fullStops = [1, 1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22, 32, 45, 64, 90, 128, 180, 256];
export const trim = (v: number) => (Math.abs(v - Math.round(v)) < 0.001 ? String(Math.round(v)) : v.toFixed(1));

export function stopLabel(n: number, prefix = 'T'): string {
  if (!(n > 0)) return '—';
  const thirds = Math.round(6 * Math.log2(n));
  const fullIndex = Math.round(thirds / 3);
  const offset = thirds - fullIndex * 3;
  // More than six stops under T1 is next to no light: say so rather than round to "T0" (same as Swift).
  if (fullIndex < -6) return `under ${prefix}0.13`;
  const v = Math.pow(2, fullIndex / 2);
  const name = fullIndex >= 0 && fullIndex < fullStops.length ? trim(fullStops[fullIndex]) : v < 1 ? String(Math.round(v * 100) / 100) : String(Math.round(v)); // same rounding as Swift
  return offset === 1 ? `${prefix}${name} +⅓` : offset === -1 ? `${prefix}${name} −⅓` : `${prefix}${name}`;
}

export function stopsDelta(stops: number): string {
  const thirds = Math.round(stops * 3);
  if (thirds === 0) return '±0';
  const sign = thirds > 0 ? '+' : '−';
  const whole = Math.trunc(Math.abs(thirds) / 3), frac = Math.abs(thirds) % 3;
  return sign + (whole > 0 ? String(whole) : '') + (frac === 1 ? '⅓' : frac === 2 ? '⅔' : '');
}

export const speedLabel = (s: number) => (s >= 1 ? `${trim(s)} s` : `1/${Math.round(1 / s)}`);

export const isoPresets = [100, 200, 400, 640, 800, 1280, 1600, 3200, 6400];
export const frameRates = [23.976, 24, 25, 30, 48, 50, 60, 100, 120];
export const shutterAngles = [45, 90, 144, 172.8, 180, 270, 360];
export const tStops = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16];

// Same as the ExposureSettings extension in Exposure.swift.
/** Thirds of a stop from T1: 2^(k/6). The pickers on both platforms list these. */
export const thirdStop = (k: number) => Math.pow(2, k / 6);
/** T1 to T32 in thirds. */
export const thirdStops = Array.from({ length: 31 }, (_, k) => thirdStop(k));
/** The T-stop `thirds` thirds of a stop away from `n`, kept between T1 and T32. */
export function steppedStop(n: number, thirds: number): number {
  const k = Math.round(6 * Math.log2(Math.max(n, 0.01))) + thirds;
  return thirdStop(Math.min(Math.max(k, 0), 30));
}
/** ISO in thirds of a stop, as cameras offer it. */
export const isoSteps = [100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1280, 1600, 2000, 2560, 3200, 4000, 5000, 6400, 8000, 10000, 12800];
/** The next or previous ISO in `isoSteps`. */
export function steppedISO(iso: number, step: number): number {
  let best = 0;
  isoSteps.forEach((v, i) => { if (Math.abs(Math.log2(v / iso)) < Math.abs(Math.log2(isoSteps[best] / iso))) best = i; });
  return isoSteps[Math.min(Math.max(best + step, 0), isoSteps.length - 1)];
}
/** Below this a meter has nothing useful to say and no lens opens that far. */
export const DARKEST_STOP = 0.5;
/** The stop an incident meter would show: "T4 +⅓", or "under T0.5" when it is that dark (never "T0"). */
export function meterStop(e: ExposureSettings, lux: number): string {
  const n = tStopForLux(e, lux);
  return n < DARKEST_STOP ? `under ${stopLabel(DARKEST_STOP)}` : stopLabel(n);
}
