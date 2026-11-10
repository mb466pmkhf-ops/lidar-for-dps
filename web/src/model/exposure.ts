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
  const v = Math.pow(2, fullIndex / 2);
  const name = fullIndex >= 0 && fullIndex < fullStops.length ? trim(fullStops[fullIndex]) : v < 1 ? Number(v.toPrecision(2)).toString() : String(Math.round(v));
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

export function exposureSummary(e: ExposureSettings): string {
  let s = `ISO ${Math.trunc(e.iso)} · ${e.shutterSeconds === undefined ? `${trim(e.shutterAngle)}° @ ${trim(e.frameRate)}` : speedLabel(exposureTime(e))} · ${stopLabel(e.tStop)}`;
  if (e.ndStops > 0) s += ` · ND ${(e.ndStops * 0.3).toFixed(1)}`;
  return s;
}

export const isoPresets = [100, 200, 400, 640, 800, 1280, 1600, 3200, 6400];
export const frameRates = [23.976, 24, 25, 30, 48, 50, 60, 100, 120];
export const shutterAngles = [45, 90, 144, 172.8, 180, 270, 360];
export const tStops = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16];
