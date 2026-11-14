// Cine lens sets: the same list as FrameScout/Core/Models/Lenses.swift (web/tests/lenses.test.ts
// checks they match). Coverage is the maker's format class, not a measured image circle, so the
// vignetting hint built on it is an estimate.
import type { SensorFormat } from './types';

export type LensCoverage = 'super35' | 'fullFrame' | 'largeFormat';

export interface LensSeries {
  id: string;
  maker: string;
  name: string;
  /** Primes: every focal length in the set. Zooms: the two ends. */
  focalLengths: number[];
  isZoom?: boolean;
  /** 1 for spherical lenses. */
  squeeze: number;
  coverage: LensCoverage;
}

export const COVERAGE: Record<LensCoverage, { label: string; maxDiagonal: number }> = {
  super35: { label: 'Super 35', maxDiagonal: 34 },
  fullFrame: { label: 'Full frame', maxDiagonal: 44 },
  largeFormat: { label: 'Large format', maxDiagonal: 47 },
};

export const COMMON_FOCAL_LENGTHS = [14, 18, 21, 24, 28, 32, 35, 40, 50, 65, 75, 85, 100, 135];

export const LENS_SERIES: LensSeries[] = [
  { id: 'angenieux-15-40', maker: 'Angénieux', name: 'Optimo 15–40 zoom', focalLengths: [15, 40], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'angenieux-24-290', maker: 'Angénieux', name: 'Optimo 24–290 zoom', focalLengths: [24, 290], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'angenieux-28-76', maker: 'Angénieux', name: 'Optimo 28–76 zoom', focalLengths: [28, 76], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'angenieux-45-120', maker: 'Angénieux', name: 'Optimo 45–120 zoom', focalLengths: [45, 120], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'arri-signature', maker: 'ARRI', name: 'Signature Prime', focalLengths: [12, 15, 18, 21, 25, 29, 35, 40, 47, 58, 75, 95, 125, 150, 200, 280], squeeze: 1, coverage: 'largeFormat' },
  { id: 'arri-master-prime', maker: 'ARRI / Zeiss', name: 'Master Prime', focalLengths: [12, 14, 16, 18, 21, 25, 27, 32, 35, 40, 50, 65, 75, 100, 135, 150], squeeze: 1, coverage: 'super35' },
  { id: 'arri-ultra-prime', maker: 'ARRI / Zeiss', name: 'Ultra Prime', focalLengths: [8, 10, 12, 14, 16, 20, 24, 28, 32, 40, 50, 65, 85, 100, 135, 180], squeeze: 1, coverage: 'super35' },
  { id: 'arri-master-anamorphic', maker: 'ARRI', name: 'Master Anamorphic 2×', focalLengths: [28, 32, 35, 40, 50, 60, 75, 100, 135, 180], squeeze: 2, coverage: 'super35' },
  { id: 'arri-alura-18-80', maker: 'ARRI', name: 'Alura 18–80 zoom', focalLengths: [18, 80], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'arri-alura-45-250', maker: 'ARRI', name: 'Alura 45–250 zoom', focalLengths: [45, 250], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'atlas-orion', maker: 'Atlas', name: 'Orion 2× anamorphic', focalLengths: [21, 25, 32, 40, 50, 65, 80, 100], squeeze: 2, coverage: 'super35' },
  { id: 'canon-sumire', maker: 'Canon', name: 'CN-E Sumire Prime', focalLengths: [14, 20, 24, 35, 50, 85, 135], squeeze: 1, coverage: 'fullFrame' },
  { id: 'canon-cne-15-47', maker: 'Canon', name: 'CN-E 15.5–47 zoom', focalLengths: [15.5, 47], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'canon-cne-30-105', maker: 'Canon', name: 'CN-E 30–105 zoom', focalLengths: [30, 105], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'cooke-s4i', maker: 'Cooke', name: 'S4/i', focalLengths: [12, 14, 16, 18, 21, 25, 27, 32, 35, 40, 50, 65, 75, 100, 135, 150, 180, 300], squeeze: 1, coverage: 'super35' },
  { id: 'cooke-s7i', maker: 'Cooke', name: 'S7/i', focalLengths: [16, 18, 21, 25, 27, 32, 40, 50, 65, 75, 100, 135, 180, 300], squeeze: 1, coverage: 'largeFormat' },
  { id: 'cooke-anamorphic-i', maker: 'Cooke', name: 'Anamorphic/i 2×', focalLengths: [25, 32, 40, 50, 65, 75, 100, 135, 180, 300], squeeze: 2, coverage: 'super35' },
  { id: 'fujinon-cabrio-19-90', maker: 'Fujinon', name: 'Cabrio 19–90 zoom', focalLengths: [19, 90], isZoom: true, squeeze: 1, coverage: 'super35' },
  { id: 'fujinon-premista-19-45', maker: 'Fujinon', name: 'Premista 19–45 zoom', focalLengths: [19, 45], isZoom: true, squeeze: 1, coverage: 'largeFormat' },
  { id: 'fujinon-premista-28-100', maker: 'Fujinon', name: 'Premista 28–100 zoom', focalLengths: [28, 100], isZoom: true, squeeze: 1, coverage: 'largeFormat' },
  { id: 'fujinon-premista-80-250', maker: 'Fujinon', name: 'Premista 80–250 zoom', focalLengths: [80, 250], isZoom: true, squeeze: 1, coverage: 'largeFormat' },
  { id: 'leitz-summilux-c', maker: 'Leitz', name: 'Summilux-C', focalLengths: [16, 18, 21, 25, 29, 35, 40, 50, 65, 75, 100, 135], squeeze: 1, coverage: 'super35' },
  { id: 'sigma-ff-high-speed', maker: 'Sigma', name: 'Cine FF High Speed', focalLengths: [14, 20, 24, 28, 35, 40, 50, 65, 85, 105, 135], squeeze: 1, coverage: 'fullFrame' },
  { id: 'zeiss-supreme', maker: 'Zeiss', name: 'Supreme Prime', focalLengths: [15, 18, 21, 25, 29, 35, 50, 65, 85, 100, 135, 150, 200], squeeze: 1, coverage: 'largeFormat' },
  { id: 'zeiss-cp3', maker: 'Zeiss', name: 'CP.3', focalLengths: [15, 18, 21, 25, 28, 35, 50, 85, 100, 135], squeeze: 1, coverage: 'fullFrame' },
  { id: 'zeiss-cz2-28-80', maker: 'Zeiss', name: 'CZ.2 28–80 zoom', focalLengths: [28, 80], isZoom: true, squeeze: 1, coverage: 'fullFrame' },
  { id: 'zeiss-cz2-70-200', maker: 'Zeiss', name: 'CZ.2 70–200 zoom', focalLengths: [70, 200], isZoom: true, squeeze: 1, coverage: 'fullFrame' },
];

/** Sets offered for plan cameras: those have no squeeze, so anamorphic sets are left out. */
export const PLAN_LENS_SERIES = LENS_SERIES.filter(s => s.squeeze === 1);

export const lensName = (s: LensSeries) => (s.maker ? `${s.maker} ${s.name}` : s.name);
export const focalNumber = (f: number) => String(Math.round(f * 10) / 10);

/** "24–290 mm" for a zoom, "16 lenses, 12–280 mm" for a set. */
export function rangeLabel(s: LensSeries): string {
  const lo = focalNumber(s.focalLengths[0]), hi = focalNumber(s.focalLengths[s.focalLengths.length - 1]);
  return s.isZoom ? `${lo}–${hi} mm` : `${s.focalLengths.length} lenses, ${lo}–${hi} mm`;
}

/** Nearest focal length the set can be set to. */
export function nearestFocal(s: LensSeries, f: number): number {
  const lo = s.focalLengths[0], hi = s.focalLengths[s.focalLengths.length - 1];
  if (s.isZoom) return Math.min(Math.max(f, lo), hi);
  return s.focalLengths.reduce((a, b) => (Math.abs(b - f) < Math.abs(a - f) ? b : a));
}

/** Diagonal (mm) of the sensor area inside the frame lines (`ratio` undefined = whole sensor). */
export function usedDiagonal(s: LensSeries, sensor: Pick<SensorFormat, 'width' | 'height'>, ratio?: number): number {
  let w = sensor.width * s.squeeze, h = sensor.height;
  if (ratio) { if (w / h > ratio) w = h * ratio; else h = w / ratio; }
  w /= s.squeeze;
  return Math.hypot(w, h);
}

/** True when the framed part of the sensor is bigger than the set's class is made for (estimate). */
export function mayVignette(s: LensSeries, sensor: Pick<SensorFormat, 'width' | 'height'>, ratio?: number): boolean {
  return usedDiagonal(s, sensor, ratio) > COVERAGE[s.coverage].maxDiagonal + 0.01;
}
