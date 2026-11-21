// Depth of field: how much of the frame is acceptably sharp for a lens, stop and focus distance.
// Thin-lens maths, the same as any depth-of-field table. Mirrored in FrameScout/Core/Models/DepthOfField.swift.
//
// Honesty: this is an estimate. It treats the T-stop as the f-stop (a real lens's f-stop is a little
// wider, so the true depth is a touch shallower), and "acceptably sharp" depends on the circle of
// confusion, which is a convention: here the image area's diagonal / 1500.
import type { CameraRig, HazeLevel, PlanPoint } from './types';
import { imageArea } from './camera';

/** The usual rule for the circle of confusion: the format's diagonal divided by this. */
export const COC_DIVISOR = 1500;
/** Eyes sit at about 0.94 of a standing person's height (anthropometric average); focus is pulled on the eyes. */
export const EYE_HEIGHT_RATIO = 0.94;
/** Closest focus the controls offer, in metres; most cinema primes focus nearer than this only with macro. */
export const MIN_FOCUS = 0.3;

/** Circle of confusion for this camera's image area, in millimetres. */
export function circleOfConfusion(rig: CameraRig): number {
  const a = imageArea(rig);
  return Math.hypot(a.width, a.height) / COC_DIVISOR;
}

export interface FocusPoint { metres: number; from: 'set' | 'subject' }

/** Where the camera is focused: the distance typed on the rig, else the shot's subject's eyes. */
export function focusFor(rig: CameraRig, subject?: PlanPoint, subjectHeight?: number): FocusPoint | undefined {
  if (rig.focusDistance !== undefined && rig.focusDistance > 0) return { metres: Math.max(MIN_FOCUS, rig.focusDistance), from: 'set' };
  if (!subject) return undefined;
  const eyes = (subjectHeight ?? 1.75) * EYE_HEIGHT_RATIO;
  const d = Math.hypot(subject.x - rig.position.x, subject.z - rig.position.z, eyes - rig.height);
  return { metres: Math.max(MIN_FOCUS, d), from: 'subject' };
}

export interface DepthOfField {
  /** Focus distance (m). */
  focus: number;
  /** Nearest and furthest acceptably sharp distances (m); far is Infinity past the hyperfocal distance. */
  near: number; far: number;
  hyperfocal: number;
}

/** Near and far limits of acceptable sharpness. Focal length and circle of confusion in mm, distances in m. */
export function depthOfField(focalMm: number, fNumber: number, focusM: number, cocMm: number): DepthOfField {
  const f = focalMm / 1000, c = cocMm / 1000, n = Math.max(fNumber, 0.5);
  const s = Math.max(focusM, f * 1.01);
  const h = (f * f) / (n * c) + f;
  const near = (s * (h - f)) / (h + s - 2 * f);
  const far = s >= h ? Infinity : (s * (h - f)) / (h - s);
  return { focus: s, near, far, hyperfocal: h };
}

export function depthOfFieldFor(rig: CameraRig, tStop: number, focusM: number): DepthOfField {
  return depthOfField(rig.focalLength, tStop, focusM, circleOfConfusion(rig));
}

/**
 * How big a point at `distM` is smeared on the sensor when focused at `focusM` (blur-circle diameter, mm).
 * Zero at the focus distance; grows towards f² / (N (s − f)) far behind it.
 */
export function blurDiameter(focalMm: number, fNumber: number, focusM: number, distM: number): number {
  const f = focalMm / 1000, s = Math.max(focusM, f * 1.01), d = Math.max(distM, 1e-3);
  return ((f * f) / (Math.max(fNumber, 0.5) * (s - f))) * (Math.abs(d - s) / d) * 1000;
}

const m = (x: number) => (x >= 10 ? `${Math.round(x)} m` : `${x.toFixed(x < 1 ? 2 : 1)} m`);

/** "Focus 3.2 m · sharp 2.8–3.7 m" or "Focus 8.0 m · sharp 4.1 m to infinity". */
export function focusLabel(d: DepthOfField, len: (metres: number) => string = m): string {
  const range = d.far === Infinity ? `${len(d.near)} to infinity` : `${len(d.near)}–${len(d.far)}`;
  return `Focus ${len(d.focus)} · sharp ${range}`;
}

// Haze, for the 3D view only: how strongly beams show and how much of a veil hangs in the room. A look
// for judging the frame, not a measurement of any hazer.
export const HAZE_LEVELS: { id: HazeLevel; name: string; beams: number; veil: number }[] = [
  { id: 'none', name: 'No haze', beams: 0, veil: 0 },
  { id: 'light', name: 'Light haze', beams: 0.2, veil: 0.05 },
  { id: 'medium', name: 'Medium haze', beams: 0.35, veil: 0.09 },
  { id: 'heavy', name: 'Heavy haze', beams: 0.6, veil: 0.14 },
];
export const hazeLevel = (id?: string) => HAZE_LEVELS.find(h => h.id === id) ?? HAZE_LEVELS[0];
