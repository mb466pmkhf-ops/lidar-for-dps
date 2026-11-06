import { describe, expect, it } from 'vitest';
import { profiles, photometrics, illuminanceOnAxis, applyProfile, solidAngleFactor } from '../src/model/photometrics';
import { buildScene, reading, vec, direction, solveOutput } from '../src/model/calculator';
import { keyLux, tStopForLux, stopLabel, stopsDelta, defaultExposure } from '../src/model/exposure';
import { newLight } from '../src/model/factory';
import type { FloorPlan } from '../src/model/types';

describe('photometrics port', () => {
  it('reproduces every library reference reading on axis', () => {
    for (const p of profiles) {
      const l = applyProfile(newLight(p.kind, { x: 0, z: 0 }), p);
      l.beamAngle = p.reference.beamAngle ?? p.defaultBeam; // reading was taken at this beam
      const pm = photometrics(l);
      if (pm.distribution === 'tube') continue; // reference is broadside; on-axis uses the same factor
      expect(illuminanceOnAxis(pm, p.reference.distance) / p.reference.lux).toBeCloseTo(1, 3);
    }
  });

  it('a lambertian solid-angle factor is π', () => {
    expect(solidAngleFactor('lambertian', 120)).toBeCloseTo(Math.PI, 10);
  });

  it('calculator agrees with the on-axis figure for a light aimed at a meter', () => {
    const l = applyProfile(newLight('fresnel', { x: 0, z: 3 }), profiles.find(p => p.id === 'cob-1200-d')!);
    l.pan = 0; l.tilt = 0; l.height = 1.5;
    const r = reading(vec(0, 1.5, 0), direction(180, 0), buildScene([l]));
    expect(r.lux).toBeCloseTo(9000, -1);
  });

  it('a wall blocks and a window passes its transmission', () => {
    const l = newLight('ledPanel', { x: 0, z: 2 }); l.pan = 0; l.tilt = 0; l.height = 1.5;
    const wall = { id: 'W', kind: 'wall' as const, a: { x: -2, z: 1 }, b: { x: 2, z: 1 }, height: 2.5, bottom: 0, isOpen: false };
    const plan: FloorPlan = { walls: [wall], doors: [], windows: [], openings: [], floorPolygons: [], objects: [], occupancy: [], occupancyCellSize: 0.1, floorY: 0, bounds: { minX: -2, minZ: -2, maxX: 2, maxZ: 2 } };
    const open = reading(vec(0, 1.5, 0), direction(180, 0), buildScene([l])).lux;
    expect(reading(vec(0, 1.5, 0), direction(180, 0), buildScene([l], plan)).lux).toBe(0);
    plan.windows = [{ ...wall, id: 'G', kind: 'window', bottom: 0.9, height: 1.2 }];
    expect(reading(vec(0, 1.5, 0), direction(180, 0), buildScene([l], plan)).lux / open).toBeCloseTo(0.78, 5);
  });

  it('solves the dimmer for a target', () => {
    const l = applyProfile(newLight('fresnel', { x: 0, z: 3 }), profiles.find(p => p.id === 'cob-300-d')!);
    l.tilt = 0; l.height = 1.5;
    const s = solveOutput(l, 1000, vec(0, 1.5, 0), direction(180, 0), [l]);
    expect(s.kind).toBe('output');
    if (s.kind === 'output') expect(s.output).toBeCloseTo(1000 / 2200, 2);
  });
});

describe('exposure port', () => {
  it('ISO 800, 180° at 24 fps, T2.8 keys at about 117 lx', () => {
    const e = defaultExposure();
    expect(keyLux(e)).toBeCloseTo(250 * 2.8 * 2.8 / (800 / 48), 6);
    expect(tStopForLux(e, keyLux(e))).toBeCloseTo(2.8, 6);
    expect(stopLabel(2.8)).toBe('T2.8');
    expect(stopLabel(3.2)).toBe('T2.8 +⅓');
    expect(stopsDelta(1.34)).toBe('+1⅓');
    expect(stopsDelta(-0.66)).toBe('−⅔');
  });
});
