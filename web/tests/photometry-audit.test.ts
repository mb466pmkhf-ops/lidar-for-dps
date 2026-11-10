// Audit of the lighting maths (2026-11): formulas re-derived by hand, library figures checked
// against published manufacturer tables, the TypeScript tables checked against the Swift source,
// and (in CI) every fixture configuration compared number for number with the Swift model.
import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import {
  profiles, modifiers, filters, photometrics, illuminanceOnAxis, applyProfile, solidAngleFactor,
  relativeIntensity, distanceFactor, shiftedKelvin, focusFactor, profileByID,
} from '../src/model/photometrics';
import { buildScene, reading, vec, direction, solveOutput } from '../src/model/calculator';
import { withDefaults, keyLux, tStopForLux, stopsForLux, stopLabel, stopsDelta, fStop, exposureTime, luxForTStop, fullStops, METER_CALIBRATION } from '../src/model/exposure';
import { newLight } from '../src/model/factory';
import type { LightFixture } from '../src/model/types';
import { photometricsMatrix, exposureMatrix } from './support/matrix';

const light = (id: string, set: (l: LightFixture) => void = () => {}) => {
  const p = profileByID(id)!;
  const l = applyProfile(newLight(p.kind, { x: 0, z: 0 }), p);
  set(l);
  return l;
};
const luxAt = (id: string, d: number, set?: (l: LightFixture) => void) => illuminanceOnAxis(photometrics(light(id, set)), d);
/** Difference in stops between a model figure and a published one. */
const stopsOff = (model: number, published: number) => Math.abs(Math.log2(model / published));
const THIRD = 1 / 3 + 1e-9;

describe('formulas, re-derived by hand', () => {
  it('a bare bulb follows the inverse-square law: E = Φ / (4π d²)', () => {
    // 800 lm household LED, bare: I = 800 / 4π = 63.66 cd.
    for (const d of [1, 2, 3.5]) expect(luxAt('bulb-led-60', d)).toBeCloseTo(64 / (d * d), 6); // library reading is 64 lx at 1 m
    expect(64 * 4 * Math.PI).toBeCloseTo(800, -1);
    expect(luxAt('bulb-led-60', 2) / luxAt('bulb-led-60', 4)).toBeCloseTo(4, 9);
  });

  it('a diffuse disc on its axis gives I / (d² + R²) — checked by integrating over the disc', () => {
    const R = 0.6, L = 1000; // luminance (cd/m²)
    for (const d of [0.3, 1, 3]) {
      let e = 0; const n = 20000;
      for (let i = 0; i < n; i++) { const rho = (i + 0.5) * R / n; const r2 = d * d + rho * rho; e += L * d * d / (r2 * r2) * 2 * Math.PI * rho * (R / n); }
      const I = L * Math.PI * R * R;
      expect(e / (I * distanceFactor(d, 'lambertian', R, 0))).toBeCloseTo(1, 6);
    }
  });

  it('a diffuse tube broadside gives I (α + sin α cos α) / (L d) — checked by integrating along the tube', () => {
    const len = 1.2, I0 = 100;
    for (const d of [0.25, 1, 4]) {
      let e = 0; const n = 20000;
      for (let i = 0; i < n; i++) { const x = -len / 2 + (i + 0.5) * len / n; const r2 = d * d + x * x; e += (I0 / len) * d * d / (r2 * r2) * (len / n); }
      expect(e / (I0 * distanceFactor(d, 'tube', 0, len))).toBeCloseTo(1, 6);
    }
    expect(distanceFactor(50, 'tube', 0, len) * 2500).toBeCloseTo(1, 3); // → 1/d² far away
  });

  it('beam angle is the 50 % point and the field angle (10 %) is 1.35× wider', () => {
    for (const beam of [12, 30, 55]) {
      expect(relativeIntensity('beam', beam / 2, beam)).toBeCloseTo(0.5, 12);
      const field = 2 * (beam / 2) * Math.pow(Math.log2(10), 0.25);
      expect(relativeIntensity('beam', field / 2, beam)).toBeCloseTo(0.1, 12);
      expect(field / beam).toBeCloseTo(1.35, 2);
    }
    expect(relativeIntensity('lambertian', 60, 120)).toBeCloseTo(0.5, 12);
  });

  it('flux = peak × solid-angle factor, integrated independently', () => {
    const integrate = (f: (t: number) => number) => { let s = 0; const n = 200000; for (let i = 0; i < n; i++) { const t = (i + 0.5) * Math.PI / n; s += f(t) * Math.sin(t) * Math.PI / n; } return 2 * Math.PI * s; };
    for (const beam of [5, 12, 30, 55, 90, 160])
      expect(solidAngleFactor('beam', beam) / integrate(t => relativeIntensity('beam', t * 180 / Math.PI, beam))).toBeCloseTo(1, 6);
    expect(integrate(t => Math.max(0, Math.cos(t)))).toBeCloseTo(solidAngleFactor('lambertian', 120), 6);
    expect(integrate(() => 1)).toBeCloseTo(solidAngleFactor('omni', 360), 6);
    // Tube: I = I₀ sin ψ, integrated over the sphere around the tube axis = π².
    expect(integrate(t => Math.sin(t))).toBeCloseTo(solidAngleFactor('tube', 360), 6);
  });

  it('cosine law at the receptor, and units add up', () => {
    const l = light('cob-300-d', x => { x.position = { x: 0, z: 3 }; x.pan = 0; x.tilt = 0; x.height = 1.5; });
    const p = vec(0, 1.5, 0), face = direction(180, 0);
    const one = reading(p, face, buildScene([l])).lux;
    expect(one).toBeCloseTo(luxAt('cob-300-d', 3), 6);
    const at60 = { x: 0, y: Math.sin(Math.PI / 3), z: Math.cos(Math.PI / 3) };
    expect(reading(p, at60, buildScene([l])).lux / one).toBeCloseTo(0.5, 9);
    const two = reading(p, face, buildScene([l, { ...l, id: 'B' }])).lux;
    expect(two / one).toBeCloseTo(2, 9);
    const e = withDefaults({});
    expect(stopsForLux(e, two) - stopsForLux(e, one)).toBeCloseTo(1, 9);              // two equal units: +1 stop
    expect(stopsDelta(Math.log2(1.5))).toBe('+⅔');                                     // adding one a stop under the key: +0.58
    expect(stopsForLux(e, 4 * one) - stopsForLux(e, one)).toBeCloseTo(2, 9);
  });

  it('gels shift in mireds', () => {
    expect(shiftedKelvin(5600, 159)).toBeCloseTo(1e6 / (1e6 / 5600 + 159), 9);
    expect(Math.round(shiftedKelvin(5600, 159))).toBe(2962);    // full CTO on daylight ≈ 2960 K
    expect(Math.round(shiftedKelvin(3200, -131))).toBe(5510);   // full CTB on tungsten ≈ 5500 K
    expect(Math.round(shiftedKelvin(6500, 159))).toBe(3196);    // the datasheet's 6500 → 3200 K (±5 K)
  });

  it('tungsten dims warm and keeps drawing power (V^3.4 light, V^1.6 power, V^0.42 colour)', () => {
    const pm = photometrics(light('tungsten-1k', l => { l.dimmer = 0.5; }));
    expect(pm.kelvin).toBeCloseTo(3200 * Math.pow(0.5, 0.42 / 3.4), 6);
    expect(pm.drawWatts).toBeCloseTo(1000 * Math.pow(0.5, 1.6 / 3.4), 6);
    expect(Math.round(pm.kelvin)).toBe(2937);
    expect(Math.round(pm.drawWatts)).toBe(722);
  });
});

describe('exposure maths, by hand (incident meter N²/t = E·S/C, C = 250)', () => {
  it('key levels', () => {
    expect(METER_CALIBRATION).toBe(250);
    const e = withDefaults({});                                   // ISO 800, 180° @ 24 fps, T2.8
    expect(exposureTime(e)).toBeCloseTo(1 / 48, 12);
    expect(keyLux(e)).toBeCloseTo(117.6, 6);                      // 250 × 2.8² × 48 / 800
    expect(keyLux(e) / 10.7639).toBeCloseTo(10.93, 2);            // ≈ 11 fc
    // Rule of thumb: ISO 100, 1/48, T2.8 wants about 100 fc. C = 250 gives 87 fc, within ⅓ stop.
    const iso100 = withDefaults({ iso: 100 });
    expect(keyLux(iso100)).toBeCloseTo(940.8, 6);
    expect(stopsOff(keyLux(iso100), 1076.39)).toBeLessThan(THIRD);
    expect(luxForTStop(e, 5.6)).toBeCloseTo(470.4, 6);            // one stop = twice the light… twice
    expect(keyLux(withDefaults({ ndStops: 3 })) / keyLux(e)).toBeCloseTo(8, 9); // ND 0.9
    expect(exposureTime(withDefaults({ frameRate: 25, shutterAngle: 172.8 }))).toBeCloseTo(1 / 52.083, 6);
    expect(exposureTime(withDefaults({ shutterSeconds: 1 / 125 }))).toBeCloseTo(0.008, 12);
    expect(fStop(e)).toBeCloseTo(2.8 * Math.sqrt(0.85), 12);
    expect(tStopForLux(e, 4 * keyLux(e))).toBeCloseTo(5.6, 9);
  });

  it('stop labels in thirds, across the whole range', () => {
    fullStops.forEach((n, i) => expect(stopLabel(Math.pow(2, i / 2))).toBe(`T${n}`));
    expect(stopLabel(3.2)).toBe('T2.8 +⅓');
    expect(stopLabel(3.56)).toBe('T4 −⅓');
    expect(stopLabel(128)).toBe('T128');            // was "T1.3e+02" on the phone, "T130" on the web
    expect(stopLabel(Math.pow(2, 15 / 2))).toBe('T180');
    expect(stopLabel(0.7)).toBe('T0.71');
    expect(stopLabel(0.125)).toBe('T0.13');         // Swift's %.2g gave "T0.12" here, the web "T0.13"
    expect(stopLabel(0.25)).toBe('T0.25');
    expect(stopLabel(0)).toBe('—');
    expect(stopsDelta(0.05)).toBe('±0');
    expect(stopsDelta(-2.4)).toBe('−2⅓');
  });
});

describe('library against published manufacturer data (estimates, within ⅓ stop)', () => {
  // ARRI 650 Plus fresnel (Junior poster, 2022): 3 m — flood 54° 1,194 lx, medium 30° 2,528, spot 13° 5,861.
  // ARRI True Blue T1 1 kW (2009 brochure): 4 m — flood 54° 1,267, medium 30° 2,419, spot 10° 8,341.
  // ARRI True Blue T2 2 kW: 6 m — flood 57° 958, medium 30° 1,878, spot 12° 6,017.
  it('tungsten fresnels at flood and medium', () => {
    expect(stopsOff(luxAt('tungsten-650', 3, l => { l.beamAngle = 55; }), 1194)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('tungsten-650', 3, l => { l.beamAngle = 30; }), 2528)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('tungsten-1k', 4, l => { l.beamAngle = 55; }), 1267)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('tungsten-1k', 4, l => { l.beamAngle = 30; }), 2419)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('tungsten-2k', 6, l => { l.beamAngle = 55; }), 958)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('tungsten-2k', 6, l => { l.beamAngle = 30; }), 1878)).toBeLessThan(THIRD);
  });

  it('spotting a fresnel gains about 5× on axis, not the 13× a constant flux would give', () => {
    for (const id of ['tungsten-650', 'tungsten-1k', 'tungsten-2k', 'fresnel-led-200-bi', 'fresnel-led-600-d']) {
      const p = profileByID(id)!;
      const gain = luxAt(id, 5, l => { l.beamAngle = 15; }) / luxAt(id, 5, l => { l.beamAngle = p.beamRange![1]; });
      expect(gain).toBeGreaterThan(3.5);
      expect(gain).toBeLessThan(7);
    }
    // 650 W at 15° against the published 13° spot (5,861 lx), scaled to 15° along the published curve.
    expect(stopsOff(luxAt('tungsten-650', 3, l => { l.beamAngle = 15; }), 5861 * Math.pow(13 / 15, 1.1))).toBeLessThan(THIRD);
    expect(focusFactor(55, [15, 55])).toBe(1);
  });

  // Aputure LS 600d Pro bare 2,600 lx at 3 m; LS 1200d Pro bare 6,380; LS 600x Pro bare 5600 K 1,880.
  it('COB units run bare (no reflector)', () => {
    const bare = (l: LightFixture) => { l.modifierID = 'none'; };
    expect(stopsOff(luxAt('cob-600-d', 3, bare), 2600)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('cob-1200-d', 3, bare), 6380)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('cob-600-bi', 3, bare), 1880)).toBeLessThan(THIRD);
  });

  // ARRI M18 (1.8 kW): 10 m — spot 15° 11,250, medium 40° 2,120 (≈3,450 at 30° along the curve).
  // ARRI M40 (4 kW): 10 m — medium 30° 6,500.
  it('HMIs at 30° and with the spot lens', () => {
    expect(stopsOff(luxAt('hmi-1800-par', 10), 2120 * Math.pow(40 / 30, 1.7))).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('hmi-4000-par', 10), 6500)).toBeLessThan(THIRD);
    expect(stopsOff(luxAt('hmi-1800-par', 10, l => { l.modifierID = 'par-spot'; }), 11250 * Math.pow(15 / 12, 1.7))).toBeLessThan(THIRD);
  });

  // LEE datasheets (Y % under tungsten/daylight, mired shift).
  it('gels and diffusion', () => {
    const f = (id: string) => filters.find(x => x.id === id)!;
    const t = (id: string, published: number) => expect(stopsOff(f(id).transmission, published)).toBeLessThan(1 / 6);
    t('cto-full', 0.554); t('ctb-full', 0.34); t('ctb-half', 0.549); t('ctb-quarter', 0.693);
    t('cto-half', 0.708); t('cto-quarter', 0.791); t('plus-green-quarter', 0.846);
    t('diff-light', 0.80); t('diff-medium', 0.60); t('diff-heavy', 0.36);
    expect(f('cto-full').mired).toBe(159);
    for (const [id, stops] of [['nd-3', 1], ['nd-6', 2], ['nd-9', 3]] as const) expect(stopsOff(f(id).transmission, Math.pow(2, -stops))).toBeLessThan(0.01);
  });
});

describe('model behaviour', () => {
  it('a reading entered at spot on a fresnel round-trips', () => {
    const ov = { lux: 5000, distance: 3, beamAngle: 20, provenance: 'manual' as const, note: '' };
    expect(luxAt('tungsten-1k', 3, l => { l.photometricOverride = ov; l.beamAngle = 20; })).toBeCloseTo(5000, 6);
    // …and flooding from there loses less than the constant-flux model said it would.
    const flooded = luxAt('tungsten-1k', 3, l => { l.photometricOverride = ov; l.beamAngle = 55; });
    expect(flooded).toBeGreaterThan(5000 * solidAngleFactor('beam', 20) / solidAngleFactor('beam', 55));
  });

  it("an HMI that can't dim low enough says so instead of claiming the target", () => {
    const l = light('hmi-1800-par', x => { x.position = { x: 0, z: 3 }; x.pan = 0; x.tilt = 0; x.height = 1.5; });
    const s = solveOutput(l, 1000, vec(0, 1.5, 0), direction(180, 0), [l]);
    expect(s.kind).toBe('atMinimum');
    if (s.kind === 'atMinimum') {
      expect(s.output).toBe(0.5);
      expect(s.lux).toBeCloseTo(reading(vec(0, 1.5, 0), direction(180, 0), buildScene([{ ...l, dimmer: 0.5 }])).lux, 6);
    }
    expect(solveOutput(l, 30000, vec(0, 1.5, 0), direction(180, 0), [l]).kind).toBe('output');
  });
});

describe('TypeScript tables match the Swift source', () => {
  const swift = readFileSync(new URL('../../FrameScout/Core/Models/Photometrics.swift', import.meta.url), 'utf8');
  const blocks = (head: string) => swift.split(head).slice(1).map(b => b.split(/\n\s*(?:FixtureProfile|LightModifier|LightFilter)\(id:|\n {4}\]/)[0]);
  const num = (b: string, key: string) => { const m = b.match(new RegExp(`${key}: ([\\d.]+)`)); return m ? Number(m[1]) : undefined; };

  it('fixture profiles', () => {
    const sw = blocks('FixtureProfile(id: ');
    expect(sw.length).toBe(profiles.length);
    sw.forEach((b, i) => {
      const p = profiles[i];
      expect(b.match(/^"([^"]+)"/)![1]).toBe(p.id);
      expect(b.match(/name: "([^"]+)"/)![1]).toBe(p.name);
      expect(num(b, 'ratedPower')).toBe(p.ratedPower);
      expect(num(b, 'defaultBeam')).toBe(p.defaultBeam);
      expect(b.match(/distribution: \.(\w+)/)![1]).toBe(p.distribution);
      const r = b.match(/ref\(([\d.]+), at: ([\d.]+)(?:, beam: ([\d.]+))?/)!;
      expect([Number(r[1]), Number(r[2]), r[3] ? Number(r[3]) : undefined]).toEqual([p.reference.lux, p.reference.distance, p.reference.beamAngle]);
      expect([num(b, 'emitterWidth'), num(b, 'emitterHeight')]).toEqual([p.emitterWidth, p.emitterHeight]);
      const range = b.match(/beamRange: ([\d.]+)\.\.\.([\d.]+)/);
      expect(range ? [Number(range[1]), Number(range[2])] : undefined).toEqual(p.beamRange);
      expect(/hasBarnDoors: true/.test(b)).toBe(p.hasBarnDoors);
      expect(num(b, 'minOutput') ?? 0.01).toBe(p.minOutput);
      expect(b.match(/defaultModifierID: "([^"]+)"/)?.[1]).toBe(p.defaultModifierID);
      const c = b.match(/color: \.(fixed|biColour|fullColour)\(([\d.]+)(?:, ([\d.]+))?\)/)!;
      expect([Number(c[2]), Number(c[3] ?? c[2]), c[1] === 'fullColour']).toEqual([p.color.minKelvin, p.color.maxKelvin, p.color.rgb]);
    });
  });

  it('modifiers', () => {
    const sw = blocks('LightModifier(id: ');
    expect(sw.length).toBe(modifiers.length);
    sw.forEach((b, i) => {
      const m = modifiers[i];
      expect(b.match(/^"([^"]+)"/)![1]).toBe(m.id);
      expect(num(b, 'transmission')).toBe(m.transmission);
      expect(b.match(/distribution: \.(\w+)/)?.[1]).toBe(m.distribution);
      expect(num(b, 'beam')).toBe(m.beam);
      expect(num(b, 'size')).toBe(m.size);
      const range = b.match(/beamRange: ([\d.]+)\.\.\.([\d.]+)/);
      expect(range ? [Number(range[1]), Number(range[2])] : undefined).toEqual(m.beamRange);
      expect([...b.matchAll(/\.(\w+)/g)].map(x => x[1]).filter(x => ['cob', 'fresnel', 'panel', 'tube', 'soft', 'hmi', 'tungsten', 'spaceLight', 'practical'].includes(x))).toEqual(m.appliesTo);
      expect(/allowsBarnDoors: true/.test(b)).toBe(m.allowsBarnDoors);
      expect(/focusesLikeFresnel: true/.test(b)).toBe(!!m.focusesLikeFresnel);
    });
  });

  it('filters', () => {
    const sw = blocks('LightFilter(id: ');
    expect(sw.length).toBe(filters.length);
    sw.forEach((b, i) => {
      const f = filters[i];
      expect(b.match(/^"([^"]+)"/)![1]).toBe(f.id);
      expect(num(b, 'transmission')).toBe(f.transmission);
      expect(Number(b.match(/mired: (-?[\d.]+)/)?.[1] ?? 0)).toBe(f.mired);
      expect(b.match(/diffusion: \.(\w+)/)?.[1]).toBe(f.diffusion);
    });
  });

  it('constants', () => {
    expect(swift).toContain(`fresnelFocusExponent = 0.85`);
    const exposure = readFileSync(new URL('../../FrameScout/Core/Models/Exposure.swift', import.meta.url), 'utf8');
    expect(exposure).toContain(`meterCalibration = ${METER_CALIBRATION}.0`);
    expect(exposure).toContain(`fullStops: [Double] = [${fullStops.join(', ')}]`);
  });
});

describe('Swift parity for every fixture configuration and exposure', () => {
  const path = process.env.PHOTOMETRICS_MATRIX;
  it('the matrix covers every fixture and modifier', () => {
    const m = photometricsMatrix();
    expect(Object.keys(m).length).toBeGreaterThan(2000);
    expect(Object.values(m).every(v => v.every(Number.isFinite))).toBe(true);
  });
  it.skipIf(!path || !existsSync(path))('matches the Swift model number for number', () => {
    const swift = JSON.parse(readFileSync(path!, 'utf8')) as { photometrics: Record<string, number[]>; exposure: Record<string, (number | string)[]> };
    const web = photometricsMatrix();
    expect(Object.keys(swift.photometrics).sort()).toEqual(Object.keys(web).sort());
    const bad: string[] = [];
    for (const [k, v] of Object.entries(web)) v.forEach((x, i) => { const s = swift.photometrics[k][i]; if (Math.abs(s - x) > 1e-7 * Math.max(1, Math.abs(x))) bad.push(`${k}[${i}] web ${x} swift ${s}`); });
    expect(bad.slice(0, 20)).toEqual([]);
    const ex = exposureMatrix();
    expect(Object.keys(swift.exposure).sort()).toEqual(Object.keys(ex).sort());
    for (const [k, v] of Object.entries(ex)) v.forEach((x, i) => {
      const s = swift.exposure[k][i];
      if (typeof x === 'string') expect(`${k}: ${s}`).toBe(`${k}: ${x}`);
      else expect(Math.abs((s as number) - x)).toBeLessThan(1e-9 * Math.max(1, Math.abs(x)));
    });
  });
});
