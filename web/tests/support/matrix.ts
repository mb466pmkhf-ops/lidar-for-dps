// Every fixture × modifier × beam × filters × dimmer, and a spread of exposure settings, computed
// with the TypeScript port. Tests/CoreLogicTests/main.swift builds the same matrix with the Swift
// model ("Photometrics matrix") and CI compares the two in photometry-audit.test.ts, so the phone,
// the web and the desktop show the same numbers for every unit, not only the demo project.
// Keep the case lists here and in main.swift identical.
import { profiles, photometrics, illuminanceOnAxis, applyProfile, modifiersFor } from '../../src/model/photometrics';
import { withDefaults, keyLux, tStopForLux, stopsForLux, stopLabel, stopsDelta } from '../../src/model/exposure';
import { newLight } from '../../src/model/factory';
import type { ExposureSettings } from '../../src/model/types';

export const MATRIX_BEAMS = [12, 30, 60];
export const MATRIX_FILTERS = [[], ['cto-full'], ['diff-light'], ['diff-medium', 'ctb-half'], ['diff-heavy', 'nd-6']];
export const MATRIX_DISTANCES = [0.5, 1, 3, 7];

export function photometricsMatrix(): Record<string, number[]> {
  const out: Record<string, number[]> = {};
  for (const p of profiles) {
    const mods: (string | undefined)[] = [undefined, 'none', ...modifiersFor(p).map(m => m.id)];
    for (const mod of mods) for (const beam of MATRIX_BEAMS) MATRIX_FILTERS.forEach((filters, fi) => {
      for (const dimmer of [1, 0.37]) for (const rgb of p.color.rgb ? [false, true] : [false]) {
        const l = applyProfile(newLight(p.kind, { x: 0, z: 0 }), p);
        if (mod) l.modifierID = mod;
        l.beamAngle = beam; l.colorTemperature = 4300; l.dimmer = dimmer;
        if (filters.length) l.filterIDs = filters;
        if (rgb) { l.colorMode = 'rgb'; l.hue = 200; l.saturation = 0.7; }
        const pm = photometrics(l);
        const key = [p.id, mod ?? '-', beam, fi, dimmer, rgb ? 'rgb' : 'w'].join('|');
        out[key] = [pm.peakIntensity, pm.flux, pm.beamAngle, pm.kelvin, pm.drawWatts, ...MATRIX_DISTANCES.map(d => illuminanceOnAxis(pm, d))];
      }
    });
  }
  return out;
}

export const EXPOSURE_ISOS = [100, 800, 3200];
export const EXPOSURE_SHUTTERS: [number, number, number | undefined][] = [[24, 180, undefined], [25, 172.8, undefined], [23.976, 90, undefined], [24, 180, 1 / 125]];
export const EXPOSURE_ND = [0, 2];
export const EXPOSURE_LUX = [3, 117, 1000, 250000];

export function exposureMatrix(): Record<string, (number | string)[]> {
  const out: Record<string, (number | string)[]> = {};
  for (const iso of EXPOSURE_ISOS) EXPOSURE_SHUTTERS.forEach(([fps, angle, secs], si) => {
    for (const nd of EXPOSURE_ND) for (const lux of EXPOSURE_LUX) {
      const e: ExposureSettings = withDefaults({ iso, frameRate: fps, shutterAngle: angle, ndStops: nd, tStop: 4 });
      if (secs !== undefined) e.shutterSeconds = secs;
      const t = tStopForLux(e, lux), s = stopsForLux(e, lux);
      out[[iso, si, nd, lux].join('|')] = [keyLux(e), t, s, stopLabel(t), stopsDelta(s)];
    }
  });
  return out;
}
