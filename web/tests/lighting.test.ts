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

  it('picking a unit that dims less far lifts the dimmer to its lowest', () => {
    const dim = { ...newLight('fresnel', { x: 0, z: 0 }), dimmer: 0.2 };
    const hmi = applyProfile(dim, profiles.find(p => p.id === 'hmi-1800-par')!);
    expect(hmi.dimmer).toBe(0.5);
    expect(applyProfile(dim, profiles.find(p => p.id === 'cob-300-d')!).dimmer).toBe(0.2);
  });

  it('a lambertian solid-angle factor is π', () => {
    expect(solidAngleFactor('lambertian', 120)).toBeCloseTo(Math.PI, 10);
  });

  it('calculator agrees with the on-axis figure for a light aimed at a meter', () => {
    const l = applyProfile(newLight('fresnel', { x: 0, z: 3 }), profiles.find(p => p.id === 'cob-1200-d')!);
    l.pan = 0; l.tilt = 0; l.height = 1.5;
    const r = reading(vec(0, 1.5, 0), direction(180, 0), buildScene([l]));
    expect(r.lux / 20000).toBeCloseTo(1, 3);
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
    if (s.kind === 'output') expect(s.output).toBeCloseTo(1000 / 3500, 2);
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

describe('grip (D-013)', () => {
  // A narrow unit 3 m from a meter, a board half way.
  const spot = () => { const l = newLight('fresnel', { x: 0, z: 3 }); l.pan = 0; l.tilt = 0; l.height = 1.5; l.beamAngle = 12; return l; };
  const boardAt = (kind: 'flag' | 'negative' | 'bounce' | 'diffusion') => { const b = newLight(kind, { x: 0, z: 1.5 }); b.pan = 180; b.height = 1.5; b.width = 1.2; b.boardHeight = 1.2; return b; };
  const meter = vec(0, 1.5, 0), facingLight = direction(180, 0);

  it('a flag or neg cuts the beam completely', () => {
    for (const k of ['flag', 'negative'] as const) expect(reading(meter, facingLight, buildScene([spot(), boardAt(k)])).lux).toBe(0);
  });

  it('a flag throws a little light back off the side the light hits, a bounce board much more', () => {
    const front = vec(0.8, 1.5, 2.2), facingBoard = direction(311, 0); // beside the unit, looking back at the board
    const flag = reading(front, facingBoard, buildScene([spot(), boardAt('flag')]));
    const bounce = reading(front, facingBoard, buildScene([spot(), boardAt('bounce')]));
    expect(flag.lux).toBeGreaterThan(0);
    expect(flag.contributions.every(c => c.viaBounce)).toBe(true);
    expect(flag.lux / bounce.lux).toBeCloseTo(0.04 / 0.8, 6);
  });

  it('a diffusion frame passes less light but spreads it, so the edge of the beam gets more', () => {
    const open = reading(meter, facingLight, buildScene([spot()])).lux;
    const diffused = reading(meter, facingLight, buildScene([spot(), boardAt('diffusion')]));
    expect(diffused.lux).toBeGreaterThan(0);
    expect(diffused.lux).toBeLessThan(open * 0.5);
    expect(diffused.contributions.every(c => c.viaBounce)).toBe(true); // nothing comes straight through
    // Well outside the bare beam, but in front of the frame.
    const side = vec(1.2, 1.5, 0.3), facingFrame = direction(180 - 40, 0);
    const bare = reading(side, facingFrame, buildScene([spot()])).lux;
    const soft = reading(side, facingFrame, buildScene([spot(), boardAt('diffusion')])).lux;
    expect(soft).toBeGreaterThan(bare * 4 + 1);
  });
});

describe('changing a grip kind', () => {
  it('renames a unit still called after its kind, and keeps a name the user gave it', async () => {
    const { renamedForKind } = await import('../src/model/factory');
    expect(renamedForKind('Negative fill', 'negative', 'flag')).toBe('Flag');
    expect(renamedForKind('Neg', 'negative', 'bounce')).toBe('Bounce');
    expect(renamedForKind('Neg 2', 'negative', 'diffusion')).toBe('Diffusion 2');
    expect(renamedForKind('Diffusion frame 3', 'diffusion', 'negative')).toBe('Negative fill 3');
    expect(renamedForKind('Window cutter', 'flag', 'negative')).toBe('Window cutter');
  });
});
