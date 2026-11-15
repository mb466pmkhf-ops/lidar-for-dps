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

describe('egg-crate grid', () => {
  it('has a soft edge, 50 % at half its rating, nothing past the cut-off', async () => {
    const { relativeIntensity } = await import('../src/model/photometrics');
    expect(relativeIntensity('grid', 20, 40)).toBeCloseTo(0.5, 9);
    expect(relativeIntensity('grid', 30, 40)).toBeGreaterThan(0.15);
    expect(relativeIntensity('grid', 40, 40)).toBe(0);
  });
  it('never makes the centre hotter than the bare panel', () => {
    const bare = { ...newLight('ledPanel', { x: 0, z: 0 }), profileID: 'panel-1x1-bi' };
    const gridded = { ...bare, modifierID: 'panel-grid-40' };
    const pm = photometrics(gridded);
    expect(pm.distribution).toBe('grid');
    expect(pm.peakIntensity / photometrics(bare).peakIntensity).toBeCloseTo(0.8, 9);
    expect(pm.flux / (photometrics(bare).peakIntensity * Math.PI)).toBeLessThan(0.2);
  });
});

describe('daylight and grip light the room and bounce off grip', async () => {
  const { buildRoomPlan } = await import('../src/model/room');
  // Same cases as "Grip bounces daylight and lights the room" in Tests/CoreLogicTests/main.swift.
  const board = (kind: 'flag' | 'bounce', z = 1.5) => { const b = newLight(kind, { x: 0, z }); b.pan = 180; b.height = 1.5; b.width = 1.2; b.boardHeight = 1.2; return b; };
  it('the sun bounces off a bounce board onto a face in its shade', () => {
    const env = { sun: { bearing: 180, elevation: 10, directNormal: 50000 }, windowLuminance: 0, ledWalls: [] };
    const front = vec(0.8, 1.5, 2.2), facingBoard = direction(311, 0);
    const flag = reading(front, facingBoard, buildScene([board('flag')], undefined, 0.78, env));
    const b = board('bounce');
    const bounce = reading(front, facingBoard, buildScene([b], undefined, 0.78, env));
    expect(bounce.lux).toBeGreaterThan(100);
    expect(bounce.contributions.every(c => c.lightID === '5A11D000-0000-4000-8000-000000000001' && c.viaBounce === b.id)).toBe(true);
    expect(flag.lux / bounce.lux).toBeCloseTo(0.04 / 0.8, 6);
  });
  it('light off a bounce board reaches the walls, floor and ceiling', () => {
    const plan = buildRoomPlan({ shape: 'box', length: 5, width: 4, ceiling: 2.6, windows: 0, door: false });
    const spot = newLight('fresnel', { x: 0, z: 1.8 }); spot.pan = 0; spot.tilt = 0; spot.height = 1.5; spot.beamAngle = 12;
    const fromSpot = (kind: 'flag' | 'bounce') => buildScene([spot, board(kind, 0.5)], plan).room
      .reduce((s, q) => s + q.shares.filter(x => x.lightID === spot.id).reduce((t, x) => t + x.intensity, 0), 0);
    expect(fromSpot('bounce')).toBeGreaterThan(5 * fromSpot('flag'));
  });
});

describe('light off the room', async () => {
  const { buildRoomPlan } = await import('../src/model/room');
  // Same case as "Light off the room" in Tests/CoreLogicTests/main.swift.
  const plan = buildRoomPlan({ shape: 'box', length: 5, width: 4, ceiling: 2.6, windows: 0, door: false });
  const up = { ...newLight('ledPanel', { x: 0, z: 0 }), profileID: 'panel-1x1-bi', height: 1.2, tilt: 90 };
  const point = vec(1.5, 1.2, 0), normal = vec(-1, 0, 0);
  const lux = (s: 'off' | 'dark' | 'typical' | 'light') => reading(point, normal, buildScene([up], plan, 0.78, undefined, s));
  it('a unit bounced off the ceiling lights a face it can\'t see', () => {
    expect(lux('off').lux).toBe(0);
    expect(lux('typical').lux).toBeGreaterThan(5);
    expect(lux('dark').lux).toBeLessThan(lux('typical').lux);
    expect(lux('light').lux).toBeGreaterThan(lux('typical').lux);
    const c = lux('typical').contributions;
    expect(c.length).toBe(1);
    expect(c[0].lightID).toBe(up.id);
    expect(c[0].viaBounce).toBe('5A11D000-0000-4000-8000-000000000004');
  });
  it('is the default, and needs walls', () => {
    expect(reading(point, normal, buildScene([up], plan)).lux).toBeCloseTo(lux('typical').lux, 9);
    expect(reading(point, normal, buildScene([up])).lux).toBe(0);
  });
});
